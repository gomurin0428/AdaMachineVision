package amv.flow.editor;

import amv.flow.editor.Model.Results;
import amv.flow.nativeapi.Flow;
import java.util.List;
import java.util.Map;
import javafx.geometry.Insets;
import javafx.geometry.Pos;
import javafx.scene.control.Button;
import javafx.scene.control.ComboBox;
import javafx.scene.control.Label;
import javafx.scene.control.Separator;
import javafx.scene.control.ToggleButton;
import javafx.scene.control.Tooltip;
import javafx.scene.layout.BorderPane;
import javafx.scene.layout.GridPane;
import javafx.scene.layout.HBox;
import javafx.scene.layout.Priority;
import javafx.scene.layout.Region;
import javafx.scene.layout.VBox;
import javafx.scene.paint.Color;
import javafx.scene.text.Font;
import javafx.scene.text.FontWeight;

/**
 * The screen for the people who run the inspection: the verdict in large
 * letters, the image with what was found drawn over it, the counts, and the
 * few things an operator does: start and stop, run once, change the recipe,
 * count from zero. Nothing of the flow can be changed here but the
 * parameters a recipe sets.
 */
final class OperatorView extends BorderPane {

    interface Listener {
        void live(boolean on);

        void runOnce();

        void changeRecipe();

        void resetCounts();

        /** The node whose image to show. */
        void display(long nodeId);

        void fullScreen();

        void backToEditor();
    }

    /** A node whose image can be shown. */
    record Choice(long id, String label) {
        @Override
        public String toString() {
            return label;
        }
    }

    /**
     * What the screen shows: the flow's name, the recipe (or null), the nodes
     * whose image can be shown and the one shown, its image and graphics,
     * the results of the last run (Results.NONE before one), the problems
     * that keep the flow from running, and what went wrong in the step
     * that led here (a new image that could not be read), or null.
     */
    record State(String flowName, String recipe, List<Choice> choices, Long displayed, Flow.NodeImage image,
            String graphicsJson, Results results, List<String> problems, String error) {
    }

    private static final Font BIG = Font.font("System", FontWeight.BOLD, 96);
    private static final Font MEDIUM = Font.font("System", FontWeight.BOLD, 40);
    private static final Font COUNT = Font.font("System", FontWeight.BOLD, 22);
    private static final Font TEXT = Font.font("System", 16);

    private final ToggleButton live = new ToggleButton();
    private final Label flowLabel = new Label();
    private final Label recipeLabel = new Label();
    private final ComboBox<Choice> display = new ComboBox<>();
    private boolean updatingChoices;
    private final ImagePane imagePane = new ImagePane(null);
    private final Label verdict = new Label();
    private final Label message = new Label();
    private final Label inspected = countLabel();
    private final Label ok = countLabel();
    private final Label ng = countLabel();
    private final Label rate = countLabel();
    private final GridPane outputs = new GridPane();
    private final Label status = new Label();

    OperatorView(Listener listener, boolean canGoBack) {
        live.setFont(Font.font("System", FontWeight.BOLD, 18));
        live.setMinWidth(150);
        live.setOnAction(e -> listener.live(live.isSelected()));
        setLive(false);
        Button runOnce = new Button("Run once (F5)");
        runOnce.setFont(TEXT);
        runOnce.setOnAction(e -> listener.runOnce());
        flowLabel.setFont(Font.font("System", FontWeight.BOLD, 16));
        recipeLabel.setFont(TEXT);
        Button recipe = new Button("Change recipe…");
        recipe.setFont(TEXT);
        recipe.setTooltip(new Tooltip("Load another product's settings"));
        recipe.setOnAction(e -> listener.changeRecipe());
        display.setTooltip(new Tooltip("The node whose image is shown"));
        display.setOnAction(e -> {
            Choice c = display.getValue();
            if (!updatingChoices && c != null) {
                listener.display(c.id());
            }
        });
        Button full = new Button("Full screen (F11)");
        full.setOnAction(e -> listener.fullScreen());
        Region spring = new Region();
        HBox.setHgrow(spring, Priority.ALWAYS);
        HBox top = new HBox(10, live, runOnce, new Separator(javafx.geometry.Orientation.VERTICAL), flowLabel,
                recipeLabel, recipe, spring, new Label("Image"), display, full);
        if (canGoBack) {
            Button back = new Button("Back to editor");
            back.setOnAction(e -> listener.backToEditor());
            top.getChildren().add(back);
        }
        top.setAlignment(Pos.CENTER_LEFT);
        top.setPadding(new Insets(8));
        setTop(top);

        setCenter(imagePane);

        verdict.setMaxWidth(Double.MAX_VALUE);
        verdict.setAlignment(Pos.CENTER);
        verdict.setMinHeight(170);
        verdict.setTextFill(Color.WHITE);
        message.setFont(TEXT);
        message.setWrapText(true);
        message.setMinHeight(Region.USE_PREF_SIZE);
        GridPane counts = new GridPane();
        counts.setHgap(16);
        counts.setVgap(4);
        counts.addRow(0, textLabel("Inspected"), inspected);
        counts.addRow(1, textLabel("OK"), ok);
        counts.addRow(2, textLabel("NG"), ng);
        counts.addRow(3, textLabel("OK rate"), rate);
        Button reset = new Button("Reset counts");
        reset.setOnAction(e -> listener.resetCounts());
        outputs.setHgap(16);
        outputs.setVgap(2);
        VBox side = new VBox(12, verdict, message, new Separator(), counts, reset, new Separator(),
                textLabel("Values"), outputs);
        side.setPadding(new Insets(10));
        side.setPrefWidth(380);
        side.setMinWidth(300);
        javafx.scene.control.ScrollPane scroll = new javafx.scene.control.ScrollPane(side);
        scroll.setFitToWidth(true);
        scroll.setHbarPolicy(javafx.scene.control.ScrollPane.ScrollBarPolicy.NEVER);
        setRight(scroll);

        status.setPadding(new Insets(3, 8, 3, 8));
        setBottom(status);
        showVerdict("READY", "#607d8b", BIG);
    }

    private static Label countLabel() {
        Label l = new Label("0");
        l.setFont(COUNT);
        return l;
    }

    private static Label textLabel(String text) {
        Label l = new Label(text);
        l.setFont(TEXT);
        return l;
    }

    /** Shows whether live is on (the button is also the operator's way to switch it). */
    void setLive(boolean on) {
        live.setSelected(on);
        live.setText(on ? "■  Stop (F6)" : "▶  Start (F6)");
    }

    void setStatus(String text, boolean error) {
        status.setText(text);
        status.setTextFill(error ? Color.web("#c62828") : Color.web("#444"));
    }

    void show(State s) {
        flowLabel.setText(s.flowName() == null || s.flowName().isBlank() ? "untitled" : s.flowName());
        recipeLabel.setText("Recipe: " + (s.recipe() == null ? "as saved in the flow" : s.recipe()));
        if (!display.getItems().equals(s.choices())) {
            updatingChoices = true;
            try {
                display.getItems().setAll(s.choices());
            } finally {
                updatingChoices = false;
            }
        }
        Choice shown = s.choices().stream().filter(c -> s.displayed() != null && c.id() == s.displayed())
                .findFirst().orElse(null);
        if (!java.util.Objects.equals(display.getValue(), shown)) {
            updatingChoices = true;
            try {
                display.setValue(shown);
            } finally {
                updatingChoices = false;
            }
        }
        imagePane.show(s.image(), s.graphicsJson(), Map.of(), shown == null ? "No node with an image to show"
                : s.image() == null ? shown.label() + ": no image yet" : shown.label());

        Results r = s.results();
        if (!s.problems().isEmpty()) {
            showVerdict("CANNOT RUN", "#c62828", MEDIUM);
            message.setText(String.join("\n", s.problems()));
        } else if (s.error() != null) {
            // Not the last run's verdict: that was for another image, or from before.
            showVerdict("ERROR", "#37474f", MEDIUM);
            message.setText(s.error());
        } else if (r.result().isEmpty()) {
            showVerdict("READY", "#607d8b", BIG);
            message.setText("Start, or Run once");
        } else {
            switch (r.result()) {
                case "accept" -> showVerdict("OK", "#2e7d32", BIG);
                case "warning" -> showVerdict("OK", "#b08900", BIG);
                case "reject" -> showVerdict("NG", "#c62828", BIG);
                default -> showVerdict("ERROR", "#37474f", MEDIUM);
            }
            message.setText(r.message());
        }
        int runs = r.count("runs");
        int good = r.count("accept") + r.count("warning");
        inspected.setText(String.valueOf(runs));
        ok.setText(String.valueOf(good));
        ng.setText(String.valueOf(runs - good));
        rate.setText(runs == 0 ? "-" : String.format("%.1f %%", 100.0 * good / runs));
        outputs.getChildren().clear();
        int row = 0;
        for (Map.Entry<String, Object> e : r.outputs().entrySet()) {
            outputs.addRow(row++, textLabel(e.getKey()), textLabel(Model.text(e.getValue())));
        }
    }

    private void showVerdict(String text, String colour, Font font) {
        verdict.setText(text);
        verdict.setFont(font);
        verdict.setStyle("-fx-background-color: " + colour + "; -fx-background-radius: 8;");
    }
}
