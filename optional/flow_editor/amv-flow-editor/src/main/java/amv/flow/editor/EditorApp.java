package amv.flow.editor;

import amv.flow.editor.Model.FlowInfo;
import amv.flow.editor.Model.IoInfo;
import amv.flow.editor.Model.KindInfo;
import amv.flow.editor.Model.NodeInfo;
import amv.flow.editor.Model.Results;
import amv.flow.nativeapi.AmvFlowException;
import amv.flow.nativeapi.Flow;
import amv.flow.nativeapi.Json;
import java.io.File;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import javafx.application.Application;
import javafx.application.Platform;
import javafx.geometry.Insets;
import javafx.geometry.Orientation;
import javafx.scene.Scene;
import javafx.scene.control.Alert;
import javafx.scene.control.Button;
import javafx.scene.control.ButtonType;
import javafx.scene.control.ComboBox;
import javafx.scene.control.Dialog;
import javafx.scene.control.Label;
import javafx.scene.control.ListCell;
import javafx.scene.control.ListView;
import javafx.scene.control.ScrollPane;
import javafx.scene.control.Separator;
import javafx.scene.control.SplitPane;
import javafx.scene.control.TextField;
import javafx.scene.control.TextInputControl;
import javafx.scene.control.ToolBar;
import javafx.scene.input.ClipboardContent;
import javafx.scene.input.KeyCode;
import javafx.scene.input.KeyCodeCombination;
import javafx.scene.input.KeyCombination;
import javafx.scene.input.KeyEvent;
import javafx.scene.input.TransferMode;
import javafx.scene.layout.BorderPane;
import javafx.scene.layout.GridPane;
import javafx.scene.layout.Priority;
import javafx.scene.layout.VBox;
import javafx.scene.paint.Color;
import javafx.stage.FileChooser;
import javafx.stage.Stage;

/**
 * The AMV Flow editor: a palette of node kinds, the flow as a graph, the
 * selected node's image and properties. The engine (a {@link Flow}) is used
 * only from one engine thread; every edit goes to the engine, which checks
 * it, and the editor then shows the engine's view of the flow again.
 */
public final class EditorApp extends Application {

    private static final long NONE = -1;
    private static final String EMPTY_FLOW = "{\"format\": 1, \"name\": \"untitled\", "
            + "\"inputs\": [{\"name\": \"Image\", \"type\": \"Image_8_Grey\"}], \"nodes\": [], \"links\": []}";
    private static final List<String> TYPES =
            List.of("Image_8_Grey", "Real", "Integer", "Boolean", "String", "Transform", "Shape");

    /** An edit on the engine thread; returns the node to select, NONE for none, or null to keep it. */
    @FunctionalInterface
    private interface EngineTask {
        Long run(Flow flow);
    }

    private record Snapshot(String flowJson, String problemsJson, String resultsJson, Long selected,
            Flow.NodeImage image, String graphicsJson, String error) {
    }

    private final ExecutorService engine = Executors.newSingleThreadExecutor(r -> {
        Thread t = new Thread(r, "amv-flow-engine");
        t.setDaemon(true);
        return t;
    });
    private Flow flow; // engine thread only

    private Stage stage;
    private Map<String, KindInfo> kinds = Map.of();
    private FlowInfo model;
    private Results results = Results.NONE;
    private volatile Long selected;  // read by live mode on the engine thread
    private String selectedLink;
    // Set on either thread.
    private volatile Path flowFile;
    private volatile Path imageFile;
    private volatile boolean ranOnce;
    private volatile boolean liveOn;
    private final java.util.concurrent.atomic.AtomicBoolean uiBusy =
            new java.util.concurrent.atomic.AtomicBoolean(false);
    private final javafx.scene.control.ToggleButton liveButton = new javafx.scene.control.ToggleButton("Live (F6)");

    // Undo and redo: the flow's JSON before each edit (engine thread only).
    private static final int MAX_UNDO = 100;
    private final java.util.ArrayDeque<String> undoStack = new java.util.ArrayDeque<>();
    private final java.util.ArrayDeque<String> redoStack = new java.util.ArrayDeque<>();

    // A folder of images played through (set on the FX thread, read on both).
    private volatile List<Path> folder = List.of();
    private final java.util.concurrent.atomic.AtomicInteger folderIndex =
            new java.util.concurrent.atomic.AtomicInteger();

    private GraphView graph;
    private PropertiesView properties;
    private ImagePane imagePane;
    private final ListView<String> problems = new ListView<>();
    private final Label status = new Label();
    private final Label result = new Label();
    private final Label tally = new Label();

    @Override
    public void start(Stage primary) {
        stage = primary;
        String startError = null;
        try {
            startError = engine.submit(() -> {
                if (!Flow.abiMatches()) {
                    return "the AMV Flow library has ABI version " + Flow.abiVersion() + "; this editor needs " + amv.flow.nativeapi.Flow.ABI_VERSION;
                }
                flow = new Flow();
                kinds = Model.parseKinds(Flow.kindsJson());
                // Arguments: [flow file [image file or folder]]
                List<String> args = getParameters().getRaw();
                if (!args.isEmpty()) {
                    Path first = Path.of(args.get(0)).toAbsolutePath();
                    flow.load(first);
                    flowFile = first;  // only once loaded: Save must not write over it otherwise
                } else {
                    flow.fromJson(EMPTY_FLOW, null);
                }
                if (args.size() >= 2) {
                    // An image file, or a folder of images to play through.
                    Path second = Path.of(args.get(1)).toAbsolutePath();
                    if (Files.isDirectory(second)) {
                        try (var files = Files.list(second)) {
                            folder = files.filter(Files::isRegularFile).filter(EditorApp::isImage).sorted().toList();
                        }
                        imageFile = folder.isEmpty() ? null : folder.get(0);
                    } else {
                        imageFile = second;
                    }
                    setImageInput(flow);
                }
                return null;
            }).get(30, TimeUnit.SECONDS);
        } catch (Exception e) {
            Throwable cause = e.getCause() != null ? e.getCause() : e;
            startError = cause.getMessage() != null ? cause.getMessage() : cause.toString();
        }
        if (startError != null && flow == null) {
            new Alert(Alert.AlertType.ERROR, "Cannot start the editor: " + startError).showAndWait();
            Platform.exit();
            return;
        }

        graph = new GraphView(new GraphView.Listener() {
            @Override
            public void selectNode(Long id) {
                selected = id;
                selectedLink = null;
                act(null, false);
            }

            @Override
            public void selectLink(String to) {
                selectedLink = to;
                selected = null;
                act(null, false);
            }

            @Override
            public void moveNode(long id, double x, double y) {
                selected = id;
                act(f -> {
                    f.setNodePosition(id, x, y);
                    return null;
                }, false);
            }

            @Override
            public void link(String from, String to) {
                act(f -> {
                    f.link(from, to);
                    return null;
                }, true);
            }

            @Override
            public void dropKind(String kind, double x, double y) {
                addNode(kind, x, y);
            }
        });
        properties = new PropertiesView(new PropertiesView.Listener() {
            @Override
            public void rename(long id, String name) {
                act(f -> {
                    f.setNodeName(id, name);
                    return null;
                }, false);
            }

            @Override
            public void setParam(long id, String name, String json) {
                act(f -> {
                    f.setParamJson(id, name, json);
                    return null;
                }, true);
            }

            @Override
            public void chooseFile(long id, String param) {
                // A path parameter names a file to write (CsvLog's), an image one a file to read.
                File file = param.endsWith("Path") ? outputChooser(param).showSaveDialog(stage)
                        : imageChooser("Train image").showOpenDialog(stage);
                if (file != null) {
                    String path = relativeToFlow(file.toPath());
                    setParam(id, param, Json.quote(path));
                }
            }

            @Override
            public void drawRegion(long id, String param, String shapeType) {
                if (selected == null || selected != id) {
                    return;
                }
                imagePane.startDrawing(param, shapeType);
                showStatus("Drag on the image to draw " + param + "; another mouse button cancels", false);
            }
        });
        imagePane = new ImagePane((param, shapeJson) -> {
            Long id = selected;
            if (id != null) {
                act(f -> {
                    f.setParamJson(id, param, shapeJson);
                    return null;
                }, true);
            }
        });

        BorderPane root = new BorderPane();
        root.setTop(toolBar());
        root.setLeft(palette());
        SplitPane centre = new SplitPane(graph, imagePane);
        centre.setOrientation(Orientation.VERTICAL);
        centre.setDividerPositions(0.55);
        root.setCenter(centre);
        ScrollPane right = new ScrollPane(properties);
        right.setFitToWidth(true);
        right.setPrefWidth(340);
        root.setRight(right);
        problems.setPrefHeight(80);
        problems.setPlaceholder(new Label("No problems"));
        VBox bottom = new VBox(problems, status);
        status.setPadding(new Insets(3, 8, 3, 8));
        root.setBottom(bottom);

        Scene scene = new Scene(root, 1600, 920);
        scene.addEventFilter(KeyEvent.KEY_PRESSED, e -> {
            if ((e.getCode() == KeyCode.DELETE || e.getCode() == KeyCode.BACK_SPACE)
                    && !(scene.getFocusOwner() instanceof TextInputControl)) {
                deleteSelection();
                e.consume();
            }
        });
        scene.getAccelerators().put(new KeyCodeCombination(KeyCode.S, KeyCombination.SHORTCUT_DOWN), this::save);
        scene.getAccelerators().put(new KeyCodeCombination(KeyCode.O, KeyCombination.SHORTCUT_DOWN), this::open);
        scene.getAccelerators().put(new KeyCodeCombination(KeyCode.F5), () -> act(null, true));
        scene.getAccelerators().put(new KeyCodeCombination(KeyCode.F6), liveButton::fire);
        scene.getAccelerators().put(new KeyCodeCombination(KeyCode.Z, KeyCombination.SHORTCUT_DOWN), () -> undo(false));
        scene.getAccelerators().put(new KeyCodeCombination(KeyCode.Y, KeyCombination.SHORTCUT_DOWN), () -> undo(true));
        scene.getAccelerators().put(
                new KeyCodeCombination(KeyCode.Z, KeyCombination.SHORTCUT_DOWN, KeyCombination.SHIFT_DOWN),
                () -> undo(true));
        scene.getAccelerators().put(new KeyCodeCombination(KeyCode.PAGE_DOWN), () -> stepFolder(1));
        scene.getAccelerators().put(new KeyCodeCombination(KeyCode.PAGE_UP), () -> stepFolder(-1));
        scene.getAccelerators().put(new KeyCodeCombination(KeyCode.DIGIT0, KeyCombination.SHORTCUT_DOWN),
                graph::resetZoom);
        stage.setScene(scene);
        stage.show();
        act(null, imageFile != null);
        if (startError != null) {
            showStatus(startError, true);
        }
    }

    @Override
    public void stop() {
        liveOn = false;
        engine.execute(() -> {
            if (flow != null) {
                flow.close();
            }
        });
        engine.shutdown();
    }

    // ------------------------------------------------------------------
    //  Layout pieces
    // ------------------------------------------------------------------

    private ToolBar toolBar() {
        Button newFlow = new Button("New");
        newFlow.setOnAction(e -> {
            flowFile = null;
            act(f -> {
                f.fromJson(EMPTY_FLOW, null);
                f.resetCounts();
                ranOnce = false;
                undoStack.clear();
                redoStack.clear();
                return NONE;
            }, false, false);
        });
        Button open = new Button("Open…");
        open.setOnAction(e -> open());
        Button save = new Button("Save");
        save.setOnAction(e -> save());
        Button saveAs = new Button("Save as…");
        saveAs.setOnAction(e -> saveAs());
        Button image = new Button("Open image…");
        image.setOnAction(e -> openImage());
        Button run = new Button("Run (F5)");
        run.setOnAction(e -> act(null, true));
        liveButton.setTooltip(new javafx.scene.control.Tooltip(
                "Run the flow again and again (a Camera node takes a new frame each time)"));
        liveButton.setOnAction(e -> {
            liveOn = liveButton.isSelected();
            if (liveOn) {
                engine.execute(this::liveStep);
            }
        });
        Button undo = new Button("Undo");
        undo.setTooltip(new javafx.scene.control.Tooltip("Ctrl+Z"));
        undo.setOnAction(e -> undo(false));
        Button redo = new Button("Redo");
        redo.setTooltip(new javafx.scene.control.Tooltip("Ctrl+Y"));
        redo.setOnAction(e -> undo(true));
        Button openFolder = new Button("Open folder…");
        openFolder.setTooltip(new javafx.scene.control.Tooltip(
                "Play the images of a folder through the flow: Page Up / Page Down, or Live"));
        openFolder.setOnAction(e -> openFolder());
        Button previous = new Button("\u25c0");
        previous.setTooltip(new javafx.scene.control.Tooltip("Previous image (Page Up)"));
        previous.setOnAction(e -> stepFolder(-1));
        Button next = new Button("\u25b6");
        next.setTooltip(new javafx.scene.control.Tooltip("Next image (Page Down)"));
        next.setOnAction(e -> stepFolder(1));
        Button addInput = new Button("Add input…");
        addInput.setOnAction(e -> addPort(true));
        Button addOutput = new Button("Add output…");
        addOutput.setOnAction(e -> addPort(false));
        Button saveRecipe = new Button("Save recipe…");
        saveRecipe.setTooltip(new javafx.scene.control.Tooltip(
                "Save every parameter of every node as a recipe (one product's settings)"));
        saveRecipe.setOnAction(e -> saveRecipe());
        Button loadRecipe = new Button("Load recipe…");
        loadRecipe.setTooltip(new javafx.scene.control.Tooltip(
                "Set the parameters a recipe holds (another product's settings); Undo takes it back"));
        loadRecipe.setOnAction(e -> loadRecipe());
        Button resetCounts = new Button("Reset counts");
        resetCounts.setTooltip(new javafx.scene.control.Tooltip("Count the runs from zero again"));
        resetCounts.setOnAction(e -> act(f -> {
            f.resetCounts();
            return null;
        }, false, false));
        tally.setTooltip(new javafx.scene.control.Tooltip(
                "Runs since the flow was opened: OK (accepted or warned) and NG (rejected or failed)"));
        result.setPadding(new Insets(0, 0, 0, 16));
        return new ToolBar(newFlow, open, save, saveAs, new Separator(), undo, redo, new Separator(), image,
                openFolder, previous, next, run, liveButton, new Separator(), addInput, addOutput,
                new Separator(), saveRecipe, loadRecipe, new Separator(), tally, resetCounts, result);
    }

    private VBox palette() {
        ListView<String> list = new ListView<>();
        list.getItems().addAll(kinds.keySet());
        list.setCellFactory(v -> {
            ListCell<String> cell = new ListCell<>() {
                @Override
                protected void updateItem(String item, boolean empty) {
                    super.updateItem(item, empty);
                    setText(empty ? null : item);
                }
            };
            cell.setOnDragDetected(e -> {
                if (cell.getItem() != null) {
                    var board = cell.startDragAndDrop(TransferMode.COPY);
                    ClipboardContent content = new ClipboardContent();
                    content.putString(cell.getItem());
                    board.setContent(content);
                }
                e.consume();
            });
            cell.setOnMouseClicked(e -> {
                if (e.getClickCount() == 2 && cell.getItem() != null) {
                    int n = model == null ? 0 : model.nodes().size();
                    addNode(cell.getItem(), 30 + 240 * (n % 3), 20 + 160 * (n / 3));
                }
            });
            return cell;
        });
        Label hint = new Label("Drag a tool onto the flow, or double-click it.");
        hint.setWrapText(true);
        VBox box = new VBox(6, new Label("Tools"), list, hint);
        box.setPadding(new Insets(8));
        box.setPrefWidth(170);
        VBox.setVgrow(list, Priority.ALWAYS);
        return box;
    }

    private static FileChooser imageChooser(String title) {
        FileChooser chooser = new FileChooser();
        chooser.setTitle(title);
        chooser.getExtensionFilters().addAll(
                new FileChooser.ExtensionFilter("Images (*.bmp, *.pgm, *.pnm)", "*.bmp", "*.pgm", "*.pnm"),
                new FileChooser.ExtensionFilter("All files", "*.*"));
        chooser.setInitialDirectory(new File(System.getProperty("user.dir")));
        return chooser;
    }

    private FileChooser recipeChooser(String title) {
        FileChooser chooser = new FileChooser();
        chooser.setTitle(title);
        chooser.getExtensionFilters().add(new FileChooser.ExtensionFilter("AMV recipes (*.amvrecipe)", "*.amvrecipe"));
        File dir = flowFile != null ? flowFile.getParent().toFile() : new File(System.getProperty("user.dir"));
        if (dir.isDirectory()) {
            chooser.setInitialDirectory(dir);
        }
        return chooser;
    }

    private void saveRecipe() {
        File file = recipeChooser("Save a recipe").showSaveDialog(stage);
        if (file == null) {
            return;
        }
        Path path = file.toPath().toAbsolutePath();
        String name = path.getFileName().toString().replaceFirst("\\.amvrecipe$", "");
        act(f -> {
            try {
                Files.writeString(path, f.recipeJson(name));
            } catch (java.io.IOException e) {
                throw new AmvFlowException(0, "cannot write " + path + ": " + e.getMessage());
            }
            Platform.runLater(() -> showStatus("Saved the recipe " + path, false));
            return null;
        }, false, false);
    }

    private void loadRecipe() {
        File file = recipeChooser("Load a recipe").showOpenDialog(stage);
        if (file == null) {
            return;
        }
        Path path = file.toPath().toAbsolutePath();
        String text;
        try {
            text = Files.readString(path);
        } catch (java.io.IOException e) {
            showStatus("cannot read " + path + ": " + e.getMessage(), true);
            return;
        }
        // A recipe from elsewhere may point a train image or a log at other
        // files: say which before applying it.
        List<String> moved = pathChanges(text);
        if (!moved.isEmpty()) {
            Alert ask = new Alert(Alert.AlertType.CONFIRMATION,
                    "The recipe changes these files:\n\n" + String.join("\n", moved) + "\n\nApply it?",
                    ButtonType.OK, ButtonType.CANCEL);
            ask.setHeaderText("Load recipe " + path.getFileName());
            if (ask.showAndWait().orElse(ButtonType.CANCEL) != ButtonType.OK) {
                return;
            }
        }
        act(f -> {
            f.applyRecipe(text);
            return null;
        }, true);
    }

    /** The file parameters a recipe would change: "node 10 Path: old → new". */
    private List<String> pathChanges(String recipeJson) {
        List<String> result = new java.util.ArrayList<>();
        if (model == null) {
            return result;
        }
        try {
            Map<String, Object> params = Json.object(Json.object(Json.parse(recipeJson)).get("params"));
            Path base = flowFile != null ? flowFile.getParent() : Path.of(System.getProperty("user.dir"));
            params.forEach((key, value) -> {
                int dot = key.indexOf('.');
                if (dot <= 0 || !(value instanceof String text)) {
                    return;
                }
                NodeInfo node;
                try {
                    node = model.nodes().get(Long.parseLong(key.substring(0, dot)));
                } catch (NumberFormatException e) {
                    return;
                }
                String name = key.substring(dot + 1);
                KindInfo kind = node == null ? null : kinds.get(node.kind());
                boolean isPath = kind != null
                        && kind.params().stream().anyMatch(p -> p.name().equals(name) && p.path());
                if (!isPath) {
                    return;
                }
                String old = node.params().get(name) instanceof String s ? s : "";
                if (!base.resolve(old).normalize().equals(base.resolve(text).normalize())) {
                    result.add("node " + node.id() + " " + name + ": " + (old.isEmpty() ? "(none)" : old)
                            + " → " + text);
                }
            });
        } catch (RuntimeException e) {
            // Not a recipe: the engine says what is wrong when it is applied.
        }
        return result;
    }

    /** A save dialog for a file a node writes: a trained pattern, or else a CSV log. */
    private FileChooser outputChooser(String param) {
        FileChooser chooser = new FileChooser();
        boolean pattern = param.equals("PatternPath");
        chooser.setTitle(pattern ? "Trained pattern" : "Log file");
        chooser.getExtensionFilters().add(pattern
                ? new FileChooser.ExtensionFilter("Trained patterns (*.amvpattern)", "*.amvpattern")
                : new FileChooser.ExtensionFilter("CSV files (*.csv)", "*.csv"));
        chooser.setInitialDirectory(flowFile != null ? flowFile.getParent().toFile()
                : new File(System.getProperty("user.dir")));
        return chooser;
    }

    private FileChooser flowChooser(String title) {
        FileChooser chooser = new FileChooser();
        chooser.setTitle(title);
        chooser.getExtensionFilters().add(new FileChooser.ExtensionFilter("AMV flows (*.amvflow)", "*.amvflow"));
        File dir = flowFile != null ? flowFile.getParent().toFile() : new File(System.getProperty("user.dir"));
        if (dir.isDirectory()) {
            chooser.setInitialDirectory(dir);
        }
        return chooser;
    }

    // ------------------------------------------------------------------
    //  Actions
    // ------------------------------------------------------------------

    private void addNode(String kind, double x, double y) {
        act(f -> f.addNode(kind, x, y), true);
    }

    private void deleteSelection() {
        if (selectedLink != null) {
            String to = selectedLink;
            selectedLink = null;
            act(f -> {
                f.unlink(to);
                return null;
            }, true);
        } else if (selected != null) {
            long id = selected;
            act(f -> {
                f.removeNode(id);
                return NONE;
            }, true);
        }
    }

    private void open() {
        File file = flowChooser("Open a flow").showOpenDialog(stage);
        if (file == null) {
            return;
        }
        Path path = file.toPath().toAbsolutePath();
        act(f -> {
            f.load(path);
            flowFile = path;
            ranOnce = false;
            undoStack.clear();
            redoStack.clear();
            setImageInput(f);
            return NONE;
        }, true, false);
    }

    private void save() {
        if (flowFile == null) {
            saveAs();
            return;
        }
        Path path = flowFile;
        act(f -> {
            nameAfter(f, path);
            f.save(path);
            Platform.runLater(() -> showStatus("Saved " + path, false));
            return null;
        }, false);
    }

    private void saveAs() {
        File file = flowChooser("Save the flow").showSaveDialog(stage);
        if (file == null) {
            return;
        }
        Path path = file.toPath().toAbsolutePath();
        Path oldDir = flowFile != null ? flowFile.getParent() : Path.of(System.getProperty("user.dir"));
        act(f -> {
            Path newDir = path.getParent();
            String before = f.toJson();
            try {
                nameAfter(f, path);
                saveInto(f, path, oldDir, newDir);
            } catch (RuntimeException e) {
                f.fromJson(before, oldDir);  // as it was, paths and folder
                setImageInput(f);
                throw e;
            }
            if (!newDir.equals(oldDir)) {
                // The undo entries hold paths relative to the old folder.
                undoStack.clear();
                redoStack.clear();
            }
            flowFile = path;
            return null;
        }, false, false);
    }

    /**
     * Engine thread: an untitled flow takes its file's name, so that the
     * recipes made from it are told apart from other flows'.
     */
    private static void nameAfter(Flow f, Path file) {
        String name = FlowInfo.parse(f.toJson()).name();
        if (name == null || name.isBlank() || name.equals("untitled")) {
            f.setName(file.getFileName().toString().replaceFirst("\\.amvflow$", ""));
        }
    }

    /** Engine thread: saves the flow at path, its relative file parameters made relative to newDir. */
    private static void saveInto(Flow f, Path path, Path oldDir, Path newDir) {
        if (!newDir.equals(oldDir)) {
            // Relative file parameters are taken from the flow file's folder:
            // rewrite them so that they name the same files from the new one.
            Map<Long, Map<String, String>> moved = new java.util.LinkedHashMap<>();
            for (NodeInfo node : FlowInfo.parse(f.toJson()).nodes().values()) {
                node.params().forEach((name, value) -> {
                    if ((name.endsWith("Image") || name.endsWith("Path")) && value instanceof String v
                            && !v.isEmpty() && !Path.of(v).isAbsolute()) {
                        Path target = oldDir.resolve(v).normalize();
                        String rewritten;
                        try {
                            rewritten = newDir.relativize(target).toString().replace('\\', '/');
                        } catch (IllegalArgumentException e) {
                            rewritten = target.toString();  // another drive
                        }
                        moved.computeIfAbsent(node.id(), k -> new java.util.LinkedHashMap<>())
                                .put(name, rewritten);
                    }
                });
            }
            f.setBaseDirectory(newDir);
            moved.forEach((id, params) -> params.forEach((name, value) -> {
                try {
                    f.setParamJson(id, name, Json.quote(value));
                } catch (AmvFlowException e) {
                    // A file that is not there from either folder: the engine
                    // keeps the old value; the node shows the problem.
                }
            }));
        }
        f.save(path);
    }

    private void openImage() {
        File file = imageChooser("Open an image").showOpenDialog(stage);
        if (file == null) {
            return;
        }
        imageFile = file.toPath().toAbsolutePath();
        act(f -> {
            setImageInput(f);
            return null;
        }, true);
    }

    /** Undoes the last edit, or redoes the last one undone. */
    private void undo(boolean redo) {
        act(f -> {
            java.util.ArrayDeque<String> from = redo ? redoStack : undoStack;
            java.util.ArrayDeque<String> to = redo ? undoStack : redoStack;
            if (from.isEmpty()) {
                throw new AmvFlowException(0, redo ? "Nothing to redo" : "Nothing to undo");
            }
            String current = f.toJson();
            f.fromJson(from.pop(), flowFile == null ? null : flowFile.getParent());
            to.push(current);
            setImageInput(f);
            return null;
        }, true, false);
    }

    private static boolean isImage(Path p) {
        String name = p.getFileName().toString().toLowerCase();
        return name.endsWith(".bmp") || name.endsWith(".pgm") || name.endsWith(".pnm");
    }

    private void openFolder() {
        javafx.stage.DirectoryChooser chooser = new javafx.stage.DirectoryChooser();
        chooser.setTitle("A folder of images");
        File start = imageFile != null ? imageFile.getParent().toFile() : new File(System.getProperty("user.dir"));
        if (start.isDirectory()) {
            chooser.setInitialDirectory(start);
        }
        File dir = chooser.showDialog(stage);
        if (dir == null) {
            return;
        }
        try (var files = Files.list(dir.toPath())) {
            List<Path> images = files.filter(Files::isRegularFile).filter(EditorApp::isImage).sorted().toList();
            if (images.isEmpty()) {
                showStatus("No .bmp, .pgm or .pnm images in " + dir, true);
                return;
            }
            folder = images;
            folderIndex.set(0);
            showImage(images.get(0));
        } catch (java.io.IOException e) {
            showStatus("Cannot read " + dir + ": " + e.getMessage(), true);
        }
    }

    /** The next (+1) or previous (-1) image of the folder, round. */
    private void stepFolder(int step) {
        List<Path> images = folder;
        if (images.isEmpty()) {
            showStatus("Open a folder of images first", true);
            return;
        }
        int i = Math.floorMod(folderIndex.get() + step, images.size());
        folderIndex.set(i);
        showImage(images.get(i));
    }

    private void showImage(Path file) {
        imageFile = file.toAbsolutePath();
        act(f -> {
            setImageInput(f);
            return null;
        }, true, false);
    }

    /** Engine thread, live mode: the next image of the folder, when the flow takes an image. */
    private void nextFolderImage() {
        List<Path> images = folder;
        if (images.isEmpty() || FlowInfo.parse(flow.toJson()).links().stream()
                .noneMatch(l -> l.from().startsWith("input."))) {
            return;
        }
        int i = Math.floorMod(folderIndex.incrementAndGet(), images.size());
        folderIndex.set(i);
        imageFile = images.get(i).toAbsolutePath();
        setImageInput(flow);
    }

    /** Engine thread: sets the image file on the flow's first image input (adding one if there is none). */
    private void setImageInput(Flow f) {
        if (imageFile == null) {
            return;
        }
        FlowInfo info = FlowInfo.parse(f.toJson());
        Optional<IoInfo> input = info.inputs().stream().filter(i -> i.type().equals("Image_8_Grey")).findFirst();
        String name = input.map(IoInfo::name).orElse("Image");
        if (input.isEmpty()) {
            f.addInput(name, "Image_8_Grey");
        }
        f.setInputImageFile(name, imageFile);
    }

    private void addPort(boolean input) {
        Dialog<ButtonType> dialog = new Dialog<>();
        dialog.setTitle(input ? "Add a flow input" : "Add a flow output");
        TextField name = new TextField();
        ComboBox<String> type = new ComboBox<>();
        type.getItems().addAll(TYPES);
        type.setValue(input ? "Image_8_Grey" : "Real");
        GridPane grid = new GridPane();
        grid.setHgap(8);
        grid.setVgap(8);
        grid.addRow(0, new Label("Name"), name);
        grid.addRow(1, new Label("Type"), type);
        dialog.getDialogPane().setContent(grid);
        dialog.getDialogPane().getButtonTypes().addAll(ButtonType.OK, ButtonType.CANCEL);
        Platform.runLater(name::requestFocus);
        if (dialog.showAndWait().orElse(ButtonType.CANCEL) == ButtonType.OK) {
            String n = name.getText().trim();
            String t = type.getValue();
            act(f -> {
                if (input) {
                    f.addInput(n, t);
                } else {
                    f.addOutput(n, t);
                }
                return null;
            }, true);
        }
    }

    private String relativeToFlow(Path file) {
        Path absolute = file.toAbsolutePath().normalize();
        if (flowFile != null) {
            Path dir = flowFile.getParent().toAbsolutePath().normalize();
            if (absolute.startsWith(dir)) {
                return dir.relativize(absolute).toString().replace('\\', '/');
            }
        }
        return absolute.toString();
    }

    // ------------------------------------------------------------------
    //  Engine round trips
    // ------------------------------------------------------------------

    private static String message(RuntimeException e) {
        return e instanceof AmvFlowException ? e.getMessage() : e.toString();
    }

    /**
     * Runs the task on the engine thread, runs the flow again when asked
     * (and it can run), then shows the engine's view.
     */
    private void act(EngineTask task, boolean rerun) {
        act(task, rerun, true);
    }

    /** As act; an edit that changes the flow is recorded for undo when undoable. */
    private void act(EngineTask task, boolean rerun, boolean undoable) {
        Long current = selected;
        engine.execute(() -> {
            String error = null;
            Long select = current;
            if (task != null) {
                String before = undoable ? flow.toJson() : null;
                try {
                    Long chosen = task.run(flow);
                    if (chosen != null) {
                        select = chosen == NONE ? null : chosen;
                    }
                } catch (RuntimeException e) {
                    error = message(e);
                }
                if (before != null && !before.equals(flow.toJson())) {
                    undoStack.push(before);
                    while (undoStack.size() > MAX_UNDO) {
                        undoStack.removeLast();
                    }
                    redoStack.clear();
                }
            }
            String problemsJson = flow.problemsJson();
            if (rerun && error == null && canRun(problemsJson)) {
                error = runOnce();
            }
            Snapshot snapshot = snapshot(select, problemsJson, error);
            Platform.runLater(() -> apply(snapshot));
        });
    }

    /**
     * Engine thread: whether the flow can run: no problems, and an image for
     * its image input if it has a linked one (a flow fed by a camera node
     * has none).
     */
    private boolean canRun(String problemsJson) {
        if (!Json.array(Json.parse(problemsJson)).isEmpty()) {
            return false;
        }
        return imageFile != null
                || FlowInfo.parse(flow.toJson()).links().stream().noneMatch(l -> l.from().startsWith("input."));
    }

    /** Engine thread: runs the flow; the error, or null. */
    private String runOnce() {
        try {
            flow.run();
            ranOnce = true;
            return null;
        } catch (RuntimeException e) {
            return message(e);
        }
    }

    /** Engine thread: what the editor shows. */
    private Snapshot snapshot(Long select, String problemsJson, String error) {
        String flowJson = flow.toJson();
        Flow.NodeImage image = null;
        String graphics = null;
        Long shown = select;
        if (shown != null && FlowInfo.parse(flowJson).nodes().containsKey(shown)) {
            try {
                image = flow.nodeImage(shown);
                graphics = flow.graphicsJson(shown);
            } catch (RuntimeException e) {
                error = error == null ? message(e) : error;
            }
        } else {
            shown = null;
        }
        return new Snapshot(flowJson, problemsJson, flow.resultsJson(), shown, image, graphics, error);
    }

    /**
     * Engine thread: one step of live mode: run (a camera node takes a new
     * frame), show the result unless the screen is still showing the last
     * one, and queue the next step behind any edit waiting.
     */
    private void liveStep() {
        if (!liveOn) {
            return;
        }
        long started = System.nanoTime();
        try {
            nextFolderImage();
        } catch (RuntimeException e) {
            liveOn = false;
            Platform.runLater(() -> liveButton.setSelected(false));
        }
        String problemsJson = flow.problemsJson();
        String error;
        if (canRun(problemsJson)) {
            error = runOnce();
        } else {
            error = "Live stopped: the flow cannot run (see the problems, or open an image)";
        }
        if (error != null) {
            liveOn = false;
            Platform.runLater(() -> liveButton.setSelected(false));
        }
        if (uiBusy.compareAndSet(false, true) || error != null) {
            Snapshot snapshot = snapshot(selected, problemsJson, error);
            Platform.runLater(() -> {
                apply(snapshot);
                uiBusy.set(false);
            });
        }
        if (liveOn) {
            long spare = 30 - (System.nanoTime() - started) / 1_000_000;
            if (spare > 0) {
                try {
                    Thread.sleep(spare);  // at most about 30 runs a second
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    return;
                }
            }
            engine.execute(this::liveStep);
        }
    }

    private void apply(Snapshot s) {
        model = FlowInfo.parse(s.flowJson());
        results = ranOnce ? Results.parse(s.resultsJson()) : Results.NONE;
        selected = s.selected();
        if (selectedLink != null && model.links().stream().noneMatch(l -> l.to().equals(selectedLink))) {
            selectedLink = null;
        }
        graph.show(model, kinds, results, selected, selectedLink);
        if (selected != null) {
            NodeInfo node = model.nodes().get(selected);
            properties.showNode(node, kinds.get(node.kind()), results.nodes().get(selected));
            imagePane.show(s.image(), s.graphicsJson(), node.params(),
                    s.image() == null ? "Node " + selected + " has no image yet" : "Node " + selected
                            + " image");
        } else {
            properties.showFlow(model, results);
            imagePane.show(null, null, Map.of(), "Select a node to see its image");
        }
        problems.getItems().setAll(Json.array(Json.parse(s.problemsJson())).stream().map(Json::string).toList());
        if (results.result().isEmpty()) {
            tally.setText("");
            result.setText("not run");
            result.setTextFill(Color.GRAY);
        } else {
            int runs = results.count("runs");
            int ok = results.count("accept") + results.count("warning");
            tally.setText(runs == 0 ? "OK 0  NG 0"
                    : String.format("OK %d  NG %d  (%.1f %% OK)", ok, runs - ok, 100.0 * ok / runs));
            result.setText("Result: " + results.result().toUpperCase()
                    + (results.message().isEmpty() ? "" : "  —  " + results.message()));
            result.setTextFill(switch (results.result()) {
                case "accept" -> Color.web("#2e7d32");
                case "warning" -> Color.web("#b08900");
                case "reject" -> Color.web("#e65100");
                default -> Color.web("#c62828");
            });
        }
        if (s.error() != null) {
            showStatus(s.error(), true);
        } else {
            List<Path> images = folder;
            String place = images.isEmpty() || imageFile == null || !images.contains(imageFile) ? ""
                    : "  (" + (images.indexOf(imageFile) + 1) + " of " + images.size() + ")";
            showStatus((imageFile == null ? "No image file (Open image\u2026, or a Camera node)"
                    : "Image: " + imageFile + place) + (liveOn ? "   \u2014 live" : ""), false);
        }
        stage.setTitle("AMV Flow Editor — " + (flowFile == null ? "untitled"
                : flowFile.getFileName() + (Files.exists(flowFile) ? "" : " (not saved)")));
    }

    private void showStatus(String text, boolean error) {
        status.setText(text);
        status.setTextFill(error ? Color.web("#c62828") : Color.web("#444"));
    }
}
