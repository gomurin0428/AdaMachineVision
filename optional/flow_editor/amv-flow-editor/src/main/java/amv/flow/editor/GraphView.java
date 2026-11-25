package amv.flow.editor;

import amv.flow.editor.Model.FlowInfo;
import amv.flow.editor.Model.IoInfo;
import amv.flow.editor.Model.KindInfo;
import amv.flow.editor.Model.LinkInfo;
import amv.flow.editor.Model.NodeInfo;
import amv.flow.editor.Model.NodeResult;
import amv.flow.editor.Model.PortInfo;
import amv.flow.editor.Model.Results;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import javafx.geometry.Point2D;
import javafx.scene.Group;
import javafx.scene.control.ScrollPane;
import javafx.scene.control.Tooltip;
import javafx.scene.input.Dragboard;
import javafx.scene.input.MouseEvent;
import javafx.scene.input.TransferMode;
import javafx.scene.layout.Pane;
import javafx.scene.paint.Color;
import javafx.scene.shape.Circle;
import javafx.scene.shape.CubicCurve;
import javafx.scene.shape.Line;
import javafx.scene.shape.Rectangle;
import javafx.scene.text.Font;
import javafx.scene.text.FontWeight;
import javafx.scene.text.Text;

/**
 * The flow as boxes and curves: each node with its input ports on the left
 * and output ports on the right, the flow's inputs and outputs as two more
 * boxes, links from output ports to input ports. Nodes are moved by
 * dragging, linked by dragging from an output port to an input port, and
 * added by dropping a kind from the palette.
 */
final class GraphView extends ScrollPane {

    interface Listener {
        void selectNode(Long id);

        void selectLink(String to);

        void moveNode(long id, double x, double y);

        void link(String from, String to);

        void dropKind(String kind, double x, double y);
    }

    static final double W = 200;
    static final double HEADER = 26;
    static final double ROW = 20;
    static final double OFFSET_X = 250;
    static final double OFFSET_Y = 40;
    private static final double PORT_R = 5.5;
    private static final long INPUTS = -1;
    private static final long OUTPUTS = -2;

    private static final Font TITLE_FONT = Font.font("System", FontWeight.BOLD, 12);
    private static final Font PORT_FONT = Font.font("System", 11);

    private record Port(String name, String type) {
    }

    private final Pane canvas = new Pane();
    private final Group linkLayer = new Group();
    private final Group nodeLayer = new Group();
    private final Listener listener;
    private final Map<Long, Point2D> positions = new HashMap<>();

    private FlowInfo flow;
    private Map<String, KindInfo> kinds = Map.of();
    private Results results = Results.NONE;
    private Long selectedNode;
    private String selectedLink;

    private Line dragLine;
    private String dragFrom;
    private Point2D dragAnchor;
    private Point2D dragStart;
    private boolean dragMoved;

    GraphView(Listener listener) {
        this.listener = listener;
        canvas.setStyle("-fx-background-color: #1e2126;");
        canvas.getChildren().addAll(linkLayer, nodeLayer);
        setContent(canvas);
        canvas.setOnMouseClicked(e -> {
            if (e.getTarget() == canvas) {
                listener.selectNode(null);
            }
        });
        canvas.setOnDragOver(e -> {
            if (e.getDragboard().hasString()) {
                e.acceptTransferModes(TransferMode.COPY);
            }
            e.consume();
        });
        canvas.setOnDragDropped(e -> {
            Dragboard board = e.getDragboard();
            boolean done = false;
            if (board.hasString()) {
                listener.dropKind(board.getString(), Math.max(0, e.getX() - OFFSET_X),
                        Math.max(0, e.getY() - OFFSET_Y));
                done = true;
            }
            e.setDropCompleted(done);
            e.consume();
        });
    }

    void show(FlowInfo flow, Map<String, KindInfo> kinds, Results results, Long selectedNode,
            String selectedLink) {
        this.flow = flow;
        this.kinds = kinds;
        this.results = results;
        this.selectedNode = selectedNode;
        this.selectedLink = selectedLink;
        layoutBoxes();
        rebuild();
    }

    // ------------------------------------------------------------------
    //  Geometry
    // ------------------------------------------------------------------

    private List<Port> inputs(long id) {
        List<Port> ports = new ArrayList<>();
        if (id == OUTPUTS) {
            for (IoInfo io : flow.outputs()) {
                ports.add(new Port(io.name(), io.type()));
            }
        } else if (id != INPUTS) {
            KindInfo kind = kinds.get(flow.nodes().get(id).kind());
            if (kind != null) {
                for (PortInfo p : kind.inputs()) {
                    ports.add(new Port(p.name(), p.type()));
                }
            }
        }
        return ports;
    }

    private List<Port> outputs(long id) {
        List<Port> ports = new ArrayList<>();
        if (id == INPUTS) {
            for (IoInfo io : flow.inputs()) {
                ports.add(new Port(io.name(), io.type()));
            }
        } else if (id != OUTPUTS) {
            KindInfo kind = kinds.get(flow.nodes().get(id).kind());
            if (kind != null) {
                for (PortInfo p : kind.outputs()) {
                    ports.add(new Port(p.name(), p.type()));
                }
            }
        }
        return ports;
    }

    private double height(long id) {
        return HEADER + Math.max(1, Math.max(inputs(id).size(), outputs(id).size())) * ROW + 8;
    }

    private void layoutBoxes() {
        positions.clear();
        double right = OFFSET_X + W;
        for (NodeInfo n : flow.nodes().values()) {
            Point2D p = new Point2D(n.x() + OFFSET_X, n.y() + OFFSET_Y);
            positions.put(n.id(), p);
            right = Math.max(right, p.getX() + W);
        }
        positions.put(INPUTS, new Point2D(20, OFFSET_Y));
        positions.put(OUTPUTS, new Point2D(right + 60, OFFSET_Y));
    }

    private Point2D inputPoint(long id, int index) {
        Point2D p = positions.get(id);
        return new Point2D(p.getX(), p.getY() + HEADER + ROW * index + ROW / 2);
    }

    private Point2D outputPoint(long id, int index) {
        Point2D p = positions.get(id);
        return new Point2D(p.getX() + W, p.getY() + HEADER + ROW * index + ROW / 2);
    }

    private static String sourceEndpoint(long id, String port) {
        return id == INPUTS ? "input." + port : id + "." + port;
    }

    private static String destinationEndpoint(long id, String port) {
        return id == OUTPUTS ? "output." + port : id + "." + port;
    }

    /** The box id and port name of an endpoint, or null. */
    private static Object[] parse(String endpoint, boolean source) {
        int dot = endpoint.indexOf('.');
        if (dot <= 0) {
            return null;
        }
        String left = endpoint.substring(0, dot);
        String port = endpoint.substring(dot + 1);
        if (left.equals("input")) {
            return source ? new Object[] {INPUTS, port} : null;
        }
        if (left.equals("output")) {
            return source ? null : new Object[] {OUTPUTS, port};
        }
        try {
            return new Object[] {Long.parseLong(left), port};
        } catch (NumberFormatException e) {
            return null;
        }
    }

    private static int indexOf(List<Port> ports, String name) {
        for (int i = 0; i < ports.size(); i++) {
            if (ports.get(i).name().equals(name)) {
                return i;
            }
        }
        return -1;
    }

    // ------------------------------------------------------------------
    //  Drawing
    // ------------------------------------------------------------------

    private void rebuild() {
        nodeLayer.getChildren().clear();
        double maxX = 0;
        double maxY = 0;
        List<Long> ids = new ArrayList<>(flow.nodes().keySet());
        ids.add(INPUTS);
        ids.add(OUTPUTS);
        for (long id : ids) {
            nodeLayer.getChildren().add(box(id));
            Point2D p = positions.get(id);
            maxX = Math.max(maxX, p.getX() + W);
            maxY = Math.max(maxY, p.getY() + height(id));
        }
        drawLinks();
        canvas.setMinSize(maxX + 300, maxY + 300);
    }

    private static Color typeColor(String type) {
        return switch (type) {
            case "Image_8_Grey" -> Color.web("#4a90d9");
            case "Real" -> Color.web("#e0a030");
            case "Integer" -> Color.web("#c07a20");
            case "Boolean" -> Color.web("#59b35a");
            case "Transform" -> Color.web("#a565c8");
            case "Shape" -> Color.web("#3cb4b4");
            default -> Color.web("#9a9a9a");
        };
    }

    private Color border(long id) {
        if (selectedNode != null && selectedNode == id) {
            return Color.WHITE;
        }
        NodeResult r = results.nodes().get(id);
        if (r == null || r.state().equals("not run")) {
            return Color.web("#5a606a");
        }
        if (r.state().equals("skipped")) {
            return Color.web("#8a8a8a");
        }
        return switch (r.result()) {
            case "accept" -> Color.web("#4caf50");
            case "warning" -> Color.web("#e6c229");
            case "reject" -> Color.web("#ff9800");
            default -> Color.web("#f44336");
        };
    }

    private String title(long id) {
        if (id == INPUTS) {
            return "Flow inputs";
        }
        if (id == OUTPUTS) {
            return "Flow outputs";
        }
        NodeInfo n = flow.nodes().get(id);
        String text = id + "  " + (n.name().isEmpty() ? n.kind() : n.name() + " (" + n.kind() + ")");
        return text.length() > 30 ? text.substring(0, 29) + "…" : text;
    }

    private static double textWidth(String s, Font font) {
        Text t = new Text(s);
        t.setFont(font);
        return t.getLayoutBounds().getWidth();
    }

    private Group box(long id) {
        Group g = new Group();
        Point2D p = positions.get(id);
        g.setLayoutX(p.getX());
        g.setLayoutY(p.getY());
        boolean real = id != INPUTS && id != OUTPUTS;

        Rectangle body = new Rectangle(W, height(id));
        body.setArcWidth(10);
        body.setArcHeight(10);
        body.setFill(Color.web(real ? "#2d323a" : "#262a30"));
        body.setStroke(border(id));
        body.setStrokeWidth(selectedNode != null && selectedNode == id ? 2.5 : 1.6);
        Rectangle header = new Rectangle(W, HEADER);
        header.setArcWidth(10);
        header.setArcHeight(10);
        header.setFill(Color.web(real ? "#3b424c" : "#30353c"));
        Text title = new Text(8, 17, title(id));
        title.setFont(TITLE_FONT);
        title.setFill(Color.WHITE);
        g.getChildren().addAll(body, header, title);

        NodeResult r = results.nodes().get(id);
        if (real && r != null && r.state().equals("ran")) {
            Text time = new Text(String.format("%.0f ms", r.timeMs()));
            time.setFont(PORT_FONT);
            time.setFill(Color.web("#aab"));
            time.setX(W - 8 - textWidth(time.getText(), PORT_FONT));
            time.setY(17);
            g.getChildren().add(time);
        }

        List<Port> ins = inputs(id);
        for (int i = 0; i < ins.size(); i++) {
            Port port = ins.get(i);
            double y = HEADER + ROW * i + ROW / 2;
            Circle c = new Circle(0, y, PORT_R, typeColor(port.type()));
            Tooltip.install(c, new Tooltip(port.name() + " : " + port.type()));
            Text t = new Text(10, y + 4, port.name());
            t.setFont(PORT_FONT);
            t.setFill(Color.web("#dde"));
            g.getChildren().addAll(c, t);
        }
        List<Port> outs = outputs(id);
        for (int j = 0; j < outs.size(); j++) {
            Port port = outs.get(j);
            double y = HEADER + ROW * j + ROW / 2;
            Circle c = new Circle(W, y, PORT_R, typeColor(port.type()));
            Tooltip.install(c, new Tooltip(port.name() + " : " + port.type() + " (drag to an input)"));
            Text t = new Text(port.name());
            t.setFont(PORT_FONT);
            t.setFill(Color.web("#dde"));
            t.setX(W - 10 - textWidth(port.name(), PORT_FONT));
            t.setY(y + 4);
            g.getChildren().addAll(c, t);
            String from = sourceEndpoint(id, port.name());
            int index = j;
            c.setOnMousePressed(e -> startLink(from, outputPoint(id, index), e));
            c.setOnMouseDragged(this::dragLink);
            c.setOnMouseReleased(this::endLink);
        }

        for (var part : List.of(body, header, title)) {
            part.setOnMousePressed(e -> {
                dragAnchor = canvas.sceneToLocal(e.getSceneX(), e.getSceneY());
                dragStart = positions.get(id);
                dragMoved = false;
                e.consume();
            });
            part.setOnMouseDragged(e -> {
                if (!real || dragAnchor == null) {
                    return;
                }
                Point2D now = canvas.sceneToLocal(e.getSceneX(), e.getSceneY());
                Point2D moved = dragStart.add(now.subtract(dragAnchor));
                moved = new Point2D(Math.max(OFFSET_X, moved.getX()), Math.max(OFFSET_Y, moved.getY()));
                if (moved.distance(dragStart) > 2) {
                    dragMoved = true;
                }
                positions.put(id, moved);
                g.setLayoutX(moved.getX());
                g.setLayoutY(moved.getY());
                drawLinks();
                e.consume();
            });
            part.setOnMouseReleased(e -> {
                if (real && dragMoved) {
                    Point2D at = positions.get(id);
                    listener.moveNode(id, at.getX() - OFFSET_X, at.getY() - OFFSET_Y);
                } else {
                    listener.selectNode(real ? id : null);
                }
                dragAnchor = null;
                e.consume();
            });
        }
        return g;
    }

    private void drawLinks() {
        linkLayer.getChildren().clear();
        for (LinkInfo link : flow.links()) {
            Object[] from = parse(link.from(), true);
            Object[] to = parse(link.to(), false);
            if (from == null || to == null || !positions.containsKey((Long) from[0])
                    || !positions.containsKey((Long) to[0])) {
                continue;
            }
            List<Port> outs = outputs((Long) from[0]);
            List<Port> ins = inputs((Long) to[0]);
            int i = indexOf(outs, (String) from[1]);
            int j = indexOf(ins, (String) to[1]);
            if (i < 0 || j < 0) {
                continue;
            }
            Point2D a = outputPoint((Long) from[0], i);
            Point2D b = inputPoint((Long) to[0], j);
            double bend = Math.max(40, Math.abs(b.getX() - a.getX()) / 2);
            boolean selected = link.to().equals(selectedLink);
            CubicCurve curve = new CubicCurve(a.getX(), a.getY(), a.getX() + bend, a.getY(), b.getX() - bend,
                    b.getY(), b.getX(), b.getY());
            curve.setFill(null);
            curve.setStroke(selected ? Color.WHITE : typeColor(outs.get(i).type()));
            curve.setStrokeWidth(selected ? 3.5 : 2.2);
            curve.setMouseTransparent(true);
            CubicCurve hit = new CubicCurve(a.getX(), a.getY(), a.getX() + bend, a.getY(), b.getX() - bend,
                    b.getY(), b.getX(), b.getY());
            hit.setFill(null);
            hit.setStroke(Color.TRANSPARENT);
            hit.setStrokeWidth(10);
            hit.setOnMouseClicked(e -> {
                listener.selectLink(link.to());
                e.consume();
            });
            Tooltip.install(hit, new Tooltip(link.from() + " → " + link.to() + " (Delete removes it)"));
            linkLayer.getChildren().addAll(hit, curve);
        }
    }

    private void startLink(String from, Point2D at, MouseEvent e) {
        dragFrom = from;
        dragLine = new Line(at.getX(), at.getY(), at.getX(), at.getY());
        dragLine.setStroke(Color.WHITE);
        dragLine.getStrokeDashArray().addAll(6.0, 4.0);
        dragLine.setMouseTransparent(true);
        canvas.getChildren().add(dragLine);
        e.consume();
    }

    private void dragLink(MouseEvent e) {
        if (dragLine != null) {
            Point2D q = canvas.sceneToLocal(e.getSceneX(), e.getSceneY());
            dragLine.setEndX(q.getX());
            dragLine.setEndY(q.getY());
        }
        e.consume();
    }

    private void endLink(MouseEvent e) {
        if (dragLine == null) {
            return;
        }
        canvas.getChildren().remove(dragLine);
        dragLine = null;
        Point2D q = canvas.sceneToLocal(e.getSceneX(), e.getSceneY());
        String best = null;
        double bestDistance = 14;
        for (long id : positions.keySet()) {
            List<Port> ins = inputs(id);
            for (int j = 0; j < ins.size(); j++) {
                double d = inputPoint(id, j).distance(q);
                if (d < bestDistance) {
                    bestDistance = d;
                    best = destinationEndpoint(id, ins.get(j).name());
                }
            }
        }
        if (best != null) {
            listener.link(dragFrom, best);
        }
        e.consume();
    }
}
