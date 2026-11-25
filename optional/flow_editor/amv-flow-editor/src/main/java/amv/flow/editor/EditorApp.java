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
    private Long selected;
    private String selectedLink;
    // Set on either thread.
    private volatile Path flowFile;
    private volatile Path imageFile;
    private volatile boolean ranOnce;

    private GraphView graph;
    private PropertiesView properties;
    private ImagePane imagePane;
    private final ListView<String> problems = new ListView<>();
    private final Label status = new Label();
    private final Label result = new Label();

    @Override
    public void start(Stage primary) {
        stage = primary;
        String startError = null;
        try {
            startError = engine.submit(() -> {
                if (!Flow.abiMatches()) {
                    return "the AMV Flow library has ABI version " + Flow.abiVersion() + "; this editor needs 1";
                }
                flow = new Flow();
                kinds = Model.parseKinds(Flow.kindsJson());
                // Arguments: [flow file [image file]]
                List<String> args = getParameters().getRaw();
                if (!args.isEmpty()) {
                    flowFile = Path.of(args.get(0)).toAbsolutePath();
                    flow.load(flowFile);
                } else {
                    flow.fromJson(EMPTY_FLOW, null);
                }
                if (args.size() >= 2) {
                    imageFile = Path.of(args.get(1)).toAbsolutePath();
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
                File file = imageChooser("Train image").showOpenDialog(stage);
                if (file != null) {
                    String path = relativeToFlow(file.toPath());
                    setParam(id, param, Json.quote(path));
                }
            }
        });
        imagePane = new ImagePane();

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
        stage.setScene(scene);
        stage.show();
        act(null, imageFile != null);
        if (startError != null) {
            showStatus(startError, true);
        }
    }

    @Override
    public void stop() {
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
                ranOnce = false;
                return NONE;
            }, false);
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
        Button addInput = new Button("Add input…");
        addInput.setOnAction(e -> addPort(true));
        Button addOutput = new Button("Add output…");
        addOutput.setOnAction(e -> addPort(false));
        result.setPadding(new Insets(0, 0, 0, 16));
        return new ToolBar(newFlow, open, save, saveAs, new Separator(), image, run, new Separator(), addInput,
                addOutput, result);
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
            setImageInput(f);
            return NONE;
        }, true);
    }

    private void save() {
        if (flowFile == null) {
            saveAs();
            return;
        }
        Path path = flowFile;
        act(f -> {
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
        act(f -> {
            f.save(path);
            f.setBaseDirectory(path.getParent());
            flowFile = path;
            return null;
        }, false);
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
     * (and it has an image and no problems), then shows the engine's view.
     */
    private void act(EngineTask task, boolean rerun) {
        Long current = selected;
        engine.execute(() -> {
            String error = null;
            Long select = current;
            if (task != null) {
                try {
                    Long chosen = task.run(flow);
                    if (chosen != null) {
                        select = chosen == NONE ? null : chosen;
                    }
                } catch (RuntimeException e) {
                    error = message(e);
                }
            }
            String problemsJson = flow.problemsJson();
            boolean runnable = Json.array(Json.parse(problemsJson)).isEmpty();
            if (rerun && imageFile != null && runnable && error == null) {
                try {
                    flow.run();
                    ranOnce = true;
                } catch (RuntimeException e) {
                    error = message(e);
                }
            }
            String flowJson = flow.toJson();
            Flow.NodeImage image = null;
            String graphics = null;
            if (select != null && FlowInfo.parse(flowJson).nodes().containsKey(select)) {
                try {
                    image = flow.nodeImage(select);
                    graphics = flow.graphicsJson(select);
                } catch (RuntimeException e) {
                    error = error == null ? message(e) : error;
                }
            } else {
                select = null;
            }
            Snapshot snapshot = new Snapshot(flowJson, problemsJson, flow.resultsJson(), select, image, graphics,
                    error);
            Platform.runLater(() -> apply(snapshot));
        });
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
            imagePane.show(s.image(), s.graphicsJson(),
                    s.image() == null ? "Node " + selected + " has taken no image yet" : "Node " + selected
                            + " input image");
        } else {
            properties.showFlow(model, results);
            imagePane.show(null, null, imageFile == null ? "Open an image to run the flow"
                    : "Select a node to see the image it takes");
        }
        problems.getItems().setAll(Json.array(Json.parse(s.problemsJson())).stream().map(Json::string).toList());
        if (results.result().isEmpty()) {
            result.setText(imageFile == null ? "no image" : "not run");
            result.setTextFill(Color.GRAY);
        } else {
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
            showStatus(imageFile == null ? "No image: use Open image…" : "Image: " + imageFile, false);
        }
        stage.setTitle("AMV Flow Editor — " + (flowFile == null ? "untitled"
                : flowFile.getFileName() + (Files.exists(flowFile) ? "" : " (not saved)")));
    }

    private void showStatus(String text, boolean error) {
        status.setText(text);
        status.setTextFill(error ? Color.web("#c62828") : Color.web("#444"));
    }
}
