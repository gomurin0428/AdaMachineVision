package amv.flow.editor;

import amv.flow.editor.Model.FlowInfo;
import amv.flow.editor.Model.IoInfo;
import amv.flow.editor.Model.KindInfo;
import amv.flow.editor.Model.NodeInfo;
import amv.flow.editor.Model.NodeResult;
import amv.flow.editor.Model.ParamInfo;
import amv.flow.editor.Model.Results;
import amv.flow.nativeapi.Json;
import java.util.Map;
import javafx.geometry.Insets;
import javafx.scene.control.Button;
import javafx.scene.control.CheckBox;
import javafx.scene.control.ComboBox;
import javafx.scene.control.Label;
import javafx.scene.control.Separator;
import javafx.scene.control.TextField;
import javafx.scene.control.Tooltip;
import javafx.scene.layout.GridPane;
import javafx.scene.layout.HBox;
import javafx.scene.layout.Priority;
import javafx.scene.layout.VBox;
import javafx.scene.text.Font;
import javafx.scene.text.FontWeight;

/**
 * The selected node's name, parameters (an editor for each, made from the
 * kind's description) and the results of its last run; with no node
 * selected, the flow's inputs, outputs and result.
 */
final class PropertiesView extends VBox {

    interface Listener {
        void rename(long id, String name);

        void setParam(long id, String name, String json);

        void chooseFile(long id, String param);
    }

    private final Listener listener;

    PropertiesView(Listener listener) {
        this.listener = listener;
        setSpacing(6);
        setPadding(new Insets(10));
        setPrefWidth(330);
    }

    private static Label heading(String text) {
        Label l = new Label(text);
        l.setFont(Font.font("System", FontWeight.BOLD, 13));
        return l;
    }

    void showFlow(FlowInfo flow, Results results) {
        getChildren().clear();
        getChildren().add(heading("Flow" + (flow.name().isEmpty() ? "" : ": " + flow.name())));
        getChildren().add(new Label("Select a node to edit it. Drag a tool from the left onto the flow; "
                + "drag from an output port (right) to an input port (left) to link."));
        ((Label) getChildren().get(1)).setWrapText(true);
        getChildren().add(new Separator());
        getChildren().add(heading("Inputs"));
        for (IoInfo io : flow.inputs()) {
            getChildren().add(new Label("  " + io.name() + " : " + io.type()));
        }
        getChildren().add(heading("Outputs"));
        for (IoInfo io : flow.outputs()) {
            Object value = results.outputs().get(io.name());
            getChildren().add(new Label("  " + io.name() + " : " + io.type() + "   = " + Model.text(value)));
        }
        if (!results.result().isEmpty()) {
            getChildren().add(new Separator());
            getChildren().add(heading("Result: " + results.result()));
            if (!results.message().isEmpty()) {
                Label m = new Label(results.message());
                m.setWrapText(true);
                getChildren().add(m);
            }
        }
    }

    void showNode(NodeInfo node, KindInfo kind, NodeResult result) {
        getChildren().clear();
        getChildren().add(heading("Node " + node.id() + ": " + node.kind()));

        TextField name = new TextField(node.name());
        name.setPromptText("name shown on the node");
        commitOn(name, () -> listener.rename(node.id(), name.getText()));
        getChildren().add(row("Name", name, ""));
        getChildren().add(new Separator());
        getChildren().add(heading("Parameters"));

        if (kind != null) {
            for (ParamInfo p : kind.params()) {
                getChildren().add(editor(node, p));
            }
        }

        getChildren().add(new Separator());
        getChildren().add(heading("Last run"));
        if (result == null || result.state().equals("not run")) {
            getChildren().add(new Label("not run (open an image and run)"));
            return;
        }
        Label state = new Label(result.state().equals("ran")
                ? result.result() + String.format("   %.1f ms", result.timeMs())
                : "skipped");
        getChildren().add(state);
        if (!result.message().isEmpty()) {
            Label m = new Label(result.message());
            m.setWrapText(true);
            getChildren().add(m);
        }
        GridPane grid = new GridPane();
        grid.setHgap(10);
        grid.setVgap(2);
        int r = 0;
        for (Map.Entry<String, Object> e : result.outputs().entrySet()) {
            grid.add(new Label(e.getKey()), 0, r);
            grid.add(new Label(Model.text(e.getValue())), 1, r);
            r++;
        }
        getChildren().add(grid);
    }

    private HBox row(String label, javafx.scene.Node editor, String help) {
        Label l = new Label(label);
        l.setMinWidth(120);
        l.setPrefWidth(120);
        if (!help.isEmpty()) {
            l.setTooltip(new Tooltip(help));
        }
        HBox box = new HBox(6, l, editor);
        HBox.setHgrow(editor, Priority.ALWAYS);
        return box;
    }

    private static void commitOn(TextField field, Runnable commit) {
        String[] last = {field.getText()};
        Runnable once = () -> {
            if (!field.getText().equals(last[0])) {
                last[0] = field.getText();
                commit.run();
            }
        };
        field.setOnAction(e -> once.run());
        field.focusedProperty().addListener((obs, was, now) -> {
            if (!now) {
                once.run();
            }
        });
    }

    private HBox editor(NodeInfo node, ParamInfo p) {
        Object value = node.params().get(p.name());
        String label = p.name() + (p.unit().isEmpty() ? "" : " [" + p.unit() + "]");
        String help = p.help() + (p.low() != null ? "  (" + Model.text(p.low()) + " .. " + Model.text(p.high()) + ")" : "");
        switch (p.kind()) {
            case "Boolean" -> {
                CheckBox box = new CheckBox();
                box.setSelected(Boolean.TRUE.equals(value));
                box.setOnAction(e -> listener.setParam(node.id(), p.name(), box.isSelected() ? "true" : "false"));
                return row(label, box, help);
            }
            case "Choice" -> {
                ComboBox<String> box = new ComboBox<>();
                box.getItems().addAll(p.choices());
                box.setValue(Json.string(value));
                box.setOnAction(e -> {
                    if (box.getValue() != null && !box.getValue().equals(Json.string(value))) {
                        listener.setParam(node.id(), p.name(), Json.quote(box.getValue()));
                    }
                });
                return row(label, box, help);
            }
            case "Shape" -> {
                TextField field = new TextField(value == null ? "" : Json.write(value));
                field.setPromptText("{\"shape\": \"RectangleAffine\", \"centerX\": ...}");
                field.setTooltip(new Tooltip(help + "\nRectangle: centerX, centerY, width, height\n"
                        + "RectangleAffine: centerX, centerY, sideX, sideY, rotation, skew\n"
                        + "Circle: centerX, centerY, radius; \"space\": \".\" or \"@\\\\Part\""));
                commitOn(field, () -> listener.setParam(node.id(), p.name(), field.getText()));
                return row(label, field, help);
            }
            case "String" -> {
                TextField field = new TextField(Json.string(value));
                commitOn(field, () -> listener.setParam(node.id(), p.name(), Json.quote(field.getText())));
                if (p.name().endsWith("Image")) {
                    Button choose = new Button("…");
                    choose.setOnAction(e -> listener.chooseFile(node.id(), p.name()));
                    HBox both = new HBox(4, field, choose);
                    HBox.setHgrow(field, Priority.ALWAYS);
                    return row(label, both, help);
                }
                return row(label, field, help);
            }
            default -> {
                TextField field = new TextField(value instanceof Double d && !p.kind().equals("Integer")
                        ? Json.write(d) : Model.text(value));
                commitOn(field, () -> listener.setParam(node.id(), p.name(), field.getText().trim()));
                return row(label, field, help);
            }
        }
    }
}
