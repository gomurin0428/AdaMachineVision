package amv.flow.editor;

import amv.flow.nativeapi.Flow;
import amv.flow.nativeapi.Json;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import javafx.scene.canvas.Canvas;
import javafx.scene.canvas.GraphicsContext;
import javafx.scene.image.PixelFormat;
import javafx.scene.image.WritableImage;
import javafx.scene.input.MouseButton;
import javafx.scene.input.MouseEvent;
import javafx.scene.input.ScrollEvent;
import javafx.scene.layout.Pane;
import javafx.scene.paint.Color;
import javafx.scene.text.Font;

/**
 * The selected node's image with its graphics drawn over it: regions
 * (green), what it found (orange outlines, red points). The wheel zooms
 * about the cursor, the right or middle button pans, a double click fits
 * the image again. The node's regions are edited with the left button:
 * drag inside one to move it, a corner to size it, the round handle to
 * turn a rectangle, the handle on a circle's edge for its radius; on
 * release the new shape goes to the listener.
 */
final class ImagePane extends Pane {

    interface Listener {
        void regionEdited(String param, String shapeJson);
    }

    private record Item(boolean polygon, boolean found, double[] xs, double[] ys) {
    }

    /** An editable region: its parameter, its shape, and its space-to-pixel map a, b, c, d, tx, ty. */
    private record Region(String param, Map<String, Object> shape, double[] toPixel) {
    }

    private enum Handle {
        MOVE, CORNER, ROTATE, RADIUS
    }

    private static final double HANDLE = 5;

    private final Canvas canvas = new Canvas();
    private final Listener listener;
    private WritableImage image;
    private List<Item> items = List.of();
    private List<Region> regions = List.of();
    private String caption = "Select a node to see its image";

    // The view: the centre of pixel (i, j) is at (ox + (i + 0.5) s, oy + (j + 0.5) s).
    private boolean fit = true;
    private double scale = 1;
    private double ox;
    private double oy;
    private double panX;
    private double panY;

    // A region being edited.
    private Region editing;
    private Handle handle;
    private Map<String, Object> draft;
    private double[] anchor;

    ImagePane(Listener listener) {
        this.listener = listener;
        setStyle("-fx-background-color: #121417;");
        setMinSize(0, 0);
        getChildren().add(canvas);
        canvas.setOnScroll(this::zoom);
        canvas.setOnMousePressed(this::press);
        canvas.setOnMouseDragged(this::drag);
        canvas.setOnMouseReleased(this::release);
        canvas.setOnMouseClicked(e -> {
            if (e.getButton() == MouseButton.PRIMARY && e.getClickCount() == 2 && editing == null) {
                fit = true;
                redraw();
            }
        });
    }

    /** Shows a new image; the view is kept while the image keeps its size. */
    void show(Flow.NodeImage nodeImage, String graphicsJson, Map<String, Object> params, String text) {
        caption = text;
        if (nodeImage == null) {
            image = null;
            items = List.of();
            regions = List.of();
        } else {
            if (image == null || image.getWidth() != nodeImage.width() || image.getHeight() != nodeImage.height()) {
                fit = true;
            }
            image = new WritableImage(nodeImage.width(), nodeImage.height());
            image.getPixelWriter().setPixels(0, 0, nodeImage.width(), nodeImage.height(),
                    PixelFormat.getByteBgraPreInstance(), nodeImage.bgra(), 0, nodeImage.width() * 4);
            parse(graphicsJson, params);
        }
        if (editing != null) {
            // A live run came in during an edit: keep editing the same parameter.
            String param = editing.param();
            editing = regions.stream().filter(r -> r.param().equals(param)).findFirst().orElse(null);
            if (editing == null) {
                draft = null;
            }
        }
        redraw();
    }

    private void parse(String json, Map<String, Object> params) {
        List<Item> newItems = new ArrayList<>();
        List<Region> newRegions = new ArrayList<>();
        if (json != null) {
            for (Object o : Json.array(Json.object(Json.parse(json)).get("items"))) {
                Map<String, Object> item = Json.object(o);
                if ("polygon".equals(item.get("kind"))) {
                    List<Object> points = Json.array(item.get("points"));
                    double[] xs = new double[points.size()];
                    double[] ys = new double[points.size()];
                    for (int i = 0; i < points.size(); i++) {
                        List<Object> p = Json.array(points.get(i));
                        xs[i] = Json.number(p.get(0));
                        ys[i] = Json.number(p.get(1));
                    }
                    newItems.add(new Item(true, "found".equals(item.get("role")), xs, ys));
                    Object param = item.get("param");
                    if (param != null && item.get("toPixel") != null && params.get(param) instanceof Map<?, ?>) {
                        List<Object> t = Json.array(item.get("toPixel"));
                        double[] toPixel = new double[6];
                        for (int i = 0; i < 6; i++) {
                            toPixel[i] = Json.number(t.get(i));
                        }
                        newRegions.add(new Region((String) param, Json.object(params.get(param)), toPixel));
                    }
                } else if ("point".equals(item.get("kind"))) {
                    newItems.add(new Item(false, true, new double[] {Json.number(item.get("x"))},
                            new double[] {Json.number(item.get("y"))}));
                }
            }
        }
        items = newItems;
        regions = newRegions;
    }

    // ------------------------------------------------------------------
    //  Coordinates
    // ------------------------------------------------------------------

    private double screenX(double px) {
        return ox + (px + 0.5) * scale;
    }

    private double screenY(double py) {
        return oy + (py + 0.5) * scale;
    }

    private static double[] toPixel(double[] t, double x, double y) {
        return new double[] {t[0] * x + t[1] * y + t[4], t[2] * x + t[3] * y + t[5]};
    }

    private double[] toScreen(double[] t, double x, double y) {
        double[] p = toPixel(t, x, y);
        return new double[] {screenX(p[0]), screenY(p[1])};
    }

    /** From the screen to the region's own space (null when the map cannot be inverted). */
    private double[] toShape(double[] t, double sx, double sy) {
        double px = (sx - ox) / scale - 0.5 - t[4];
        double py = (sy - oy) / scale - 0.5 - t[5];
        double det = t[0] * t[3] - t[1] * t[2];
        if (Math.abs(det) < 1e-12) {
            return null;
        }
        return new double[] {(t[3] * px - t[1] * py) / det, (-t[2] * px + t[0] * py) / det};
    }

    // ------------------------------------------------------------------
    //  Shapes (AMV.Shapes: side X along Rotation, side Y along
    //  Rotation + Skew + Pi/2)
    // ------------------------------------------------------------------

    private static double num(Map<String, Object> shape, String key) {
        Object v = shape.get(key);
        return v instanceof Double d ? d : 0;
    }

    private static String kind(Map<String, Object> shape) {
        return Json.string(shape.get("shape"));
    }

    private static double[] axisX(Map<String, Object> s) {
        double r = num(s, "rotation");
        return new double[] {Math.cos(r), Math.sin(r)};
    }

    private static double[] axisY(Map<String, Object> s) {
        double a = num(s, "rotation") + num(s, "skew");
        return new double[] {-Math.sin(a), Math.cos(a)};
    }

    /** The corners (or the points round a circle) in the shape's space. */
    private static double[][] outline(Map<String, Object> s) {
        double cx = num(s, "centerX");
        double cy = num(s, "centerY");
        switch (kind(s)) {
            case "Rectangle" -> {
                double hw = num(s, "width") / 2;
                double hh = num(s, "height") / 2;
                return new double[][] {{cx - hw, cy - hh}, {cx + hw, cy - hh}, {cx + hw, cy + hh}, {cx - hw, cy + hh}};
            }
            case "RectangleAffine" -> {
                double[] ux = axisX(s);
                double[] uy = axisY(s);
                double hx = num(s, "sideX") / 2;
                double hy = num(s, "sideY") / 2;
                double[][] corners = new double[4][];
                int i = 0;
                for (double[] sign : new double[][] {{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}) {
                    corners[i++] = new double[] {cx + sign[0] * hx * ux[0] + sign[1] * hy * uy[0],
                            cy + sign[0] * hx * ux[1] + sign[1] * hy * uy[1]};
                }
                return corners;
            }
            case "Circle" -> {
                double r = num(s, "radius");
                double[][] points = new double[72][];
                for (int i = 0; i < 72; i++) {
                    double a = 2 * Math.PI * i / 72;
                    points[i] = new double[] {cx + r * Math.cos(a), cy + r * Math.sin(a)};
                }
                return points;
            }
            default -> {
                return new double[0][];
            }
        }
    }

    /** The handles in screen coordinates, each with its kind. */
    private List<Object[]> handles(Region region, Map<String, Object> s) {
        List<Object[]> result = new ArrayList<>();
        double[] t = region.toPixel();
        switch (kind(s)) {
            case "Rectangle", "RectangleAffine" -> {
                for (double[] c : outline(s)) {
                    result.add(new Object[] {Handle.CORNER, toScreen(t, c[0], c[1])});
                }
                if (kind(s).equals("RectangleAffine")) {
                    double[] ux = axisX(s);
                    double hx = num(s, "sideX") / 2;
                    double[] centre = toScreen(t, num(s, "centerX"), num(s, "centerY"));
                    double[] side = toScreen(t, num(s, "centerX") + hx * ux[0], num(s, "centerY") + hx * ux[1]);
                    double dx = side[0] - centre[0];
                    double dy = side[1] - centre[1];
                    double len = Math.max(1e-6, Math.hypot(dx, dy));
                    result.add(new Object[] {Handle.ROTATE,
                        new double[] {side[0] + 22 * dx / len, side[1] + 22 * dy / len}});
                }
            }
            case "Circle" -> result.add(new Object[] {Handle.RADIUS,
                toScreen(t, num(s, "centerX") + num(s, "radius"), num(s, "centerY"))});
            default -> {
            }
        }
        return result;
    }

    private static boolean inside(double[][] screen, double x, double y) {
        boolean in = false;
        for (int i = 0, j = screen.length - 1; i < screen.length; j = i++) {
            if ((screen[i][1] > y) != (screen[j][1] > y)
                    && x < (screen[j][0] - screen[i][0]) * (y - screen[i][1]) / (screen[j][1] - screen[i][1])
                            + screen[i][0]) {
                in = !in;
            }
        }
        return in;
    }

    private double[][] screenOutline(Region region, Map<String, Object> s) {
        double[][] shape = outline(s);
        double[][] screen = new double[shape.length][];
        for (int i = 0; i < shape.length; i++) {
            screen[i] = toScreen(region.toPixel(), shape[i][0], shape[i][1]);
        }
        return screen;
    }

    // ------------------------------------------------------------------
    //  Mouse
    // ------------------------------------------------------------------

    private void zoom(ScrollEvent e) {
        if (image == null || e.getDeltaY() == 0) {
            return;
        }
        double factor = e.getDeltaY() > 0 ? 1.2 : 1 / 1.2;
        double next = Math.max(0.05, Math.min(40, scale * factor));
        factor = next / scale;
        ox = e.getX() - (e.getX() - ox) * factor;
        oy = e.getY() - (e.getY() - oy) * factor;
        scale = next;
        fit = false;
        redraw();
        e.consume();
    }

    private void press(MouseEvent e) {
        if (image == null) {
            return;
        }
        if (e.getButton() != MouseButton.PRIMARY) {
            panX = e.getX();
            panY = e.getY();
            return;
        }
        for (Region region : regions) {
            for (Object[] h : handles(region, region.shape())) {
                double[] p = (double[]) h[1];
                if (Math.hypot(p[0] - e.getX(), p[1] - e.getY()) <= HANDLE + 3) {
                    begin(region, (Handle) h[0], e);
                    return;
                }
            }
        }
        for (Region region : regions) {
            if (inside(screenOutline(region, region.shape()), e.getX(), e.getY())) {
                begin(region, Handle.MOVE, e);
                return;
            }
        }
    }

    private void begin(Region region, Handle kind, MouseEvent e) {
        double[] at = toShape(region.toPixel(), e.getX(), e.getY());
        if (at == null) {
            return;
        }
        editing = region;
        handle = kind;
        anchor = at;
        draft = new LinkedHashMap<>(region.shape());
        e.consume();
    }

    private void drag(MouseEvent e) {
        if (image == null) {
            return;
        }
        if (e.getButton() != MouseButton.PRIMARY) {
            ox += e.getX() - panX;
            oy += e.getY() - panY;
            panX = e.getX();
            panY = e.getY();
            fit = false;
            redraw();
            return;
        }
        if (editing == null) {
            return;
        }
        double[] p = toShape(editing.toPixel(), e.getX(), e.getY());
        if (p == null) {
            return;
        }
        Map<String, Object> s = editing.shape();
        double cx = num(s, "centerX");
        double cy = num(s, "centerY");
        double dx = p[0] - cx;
        double dy = p[1] - cy;
        switch (handle) {
            case MOVE -> {
                draft.put("centerX", round(cx + p[0] - anchor[0]));
                draft.put("centerY", round(cy + p[1] - anchor[1]));
            }
            case CORNER -> {
                if (kind(s).equals("Rectangle")) {
                    draft.put("width", round(Math.max(1, 2 * Math.abs(dx))));
                    draft.put("height", round(Math.max(1, 2 * Math.abs(dy))));
                } else {
                    // d = a ux + b uy, along the rectangle's own sides.
                    double[] ux = axisX(s);
                    double[] uy = axisY(s);
                    double det = ux[0] * uy[1] - ux[1] * uy[0];
                    if (Math.abs(det) > 1e-9) {
                        double a = (dx * uy[1] - dy * uy[0]) / det;
                        double b = (ux[0] * dy - ux[1] * dx) / det;
                        draft.put("sideX", round(Math.max(1, 2 * Math.abs(a))));
                        draft.put("sideY", round(Math.max(1, 2 * Math.abs(b))));
                    }
                }
            }
            case ROTATE -> draft.put("rotation", Math.round(Math.atan2(dy, dx) * 1e6) / 1e6);
            case RADIUS -> draft.put("radius", round(Math.max(1, Math.hypot(dx, dy))));
            default -> {
            }
        }
        redraw();
        e.consume();
    }

    private static double round(double v) {
        return Math.round(v * 100) / 100.0;
    }

    private void release(MouseEvent e) {
        if (editing != null && e.getButton() == MouseButton.PRIMARY) {
            Region region = editing;
            Map<String, Object> shape = draft;
            editing = null;
            draft = null;
            if (!shape.equals(region.shape())) {
                listener.regionEdited(region.param(), Json.write(shape));
            }
            redraw();
            e.consume();
        }
    }

    // ------------------------------------------------------------------
    //  Drawing
    // ------------------------------------------------------------------

    @Override
    protected void layoutChildren() {
        canvas.setWidth(getWidth());
        canvas.setHeight(getHeight());
        redraw();
    }

    private void redraw() {
        GraphicsContext gc = canvas.getGraphicsContext2D();
        double w = canvas.getWidth();
        double h = canvas.getHeight();
        gc.setFill(Color.web("#121417"));
        gc.fillRect(0, 0, w, h);
        gc.setFont(Font.font(12));
        if (image == null) {
            gc.setFill(Color.web("#889"));
            gc.fillText(caption, 12, 22);
            return;
        }
        double iw = image.getWidth();
        double ih = image.getHeight();
        if (fit) {
            scale = Math.min((w - 8) / iw, (h - 28) / ih);
            if (scale <= 0) {
                return;
            }
            ox = (w - iw * scale) / 2;
            oy = 22 + (h - 28 - ih * scale) / 2;
        }
        gc.setImageSmoothing(scale < 1);
        gc.drawImage(image, ox, oy, iw * scale, ih * scale);
        for (Item item : items) {
            if (item.polygon()) {
                if (!item.found() && editing != null) {
                    continue;  // the region being edited is drawn as its draft below
                }
                double[] xs = new double[item.xs().length];
                double[] ys = new double[item.ys().length];
                for (int i = 0; i < xs.length; i++) {
                    xs[i] = screenX(item.xs()[i]);
                    ys[i] = screenY(item.ys()[i]);
                }
                gc.setStroke(Color.web(item.found() ? "#ffa726" : "#3ee05a"));
                gc.setLineWidth(item.found() ? 2.0 : 1.6);
                gc.strokePolygon(xs, ys, xs.length);
            } else {
                double x = screenX(item.xs()[0]);
                double y = screenY(item.ys()[0]);
                gc.setStroke(Color.web("#ff4d4d"));
                gc.setLineWidth(2);
                gc.strokeLine(x - 8, y, x + 8, y);
                gc.strokeLine(x, y - 8, x, y + 8);
            }
        }
        for (Region region : regions) {
            Map<String, Object> s = region == editing ? draft : region.shape();
            if (region == editing) {
                double[][] screen = screenOutline(region, s);
                double[] xs = new double[screen.length];
                double[] ys = new double[screen.length];
                for (int i = 0; i < screen.length; i++) {
                    xs[i] = screen[i][0];
                    ys[i] = screen[i][1];
                }
                gc.setStroke(Color.web("#fff176"));
                gc.setLineWidth(2);
                gc.setLineDashes(6, 4);
                gc.strokePolygon(xs, ys, xs.length);
                gc.setLineDashes();
            }
            for (Object[] hdl : handles(region, s)) {
                double[] p = (double[]) hdl[1];
                gc.setFill(Color.WHITE);
                gc.setStroke(Color.web("#222"));
                gc.setLineWidth(1);
                if (hdl[0] == Handle.ROTATE) {
                    gc.fillOval(p[0] - HANDLE, p[1] - HANDLE, 2 * HANDLE, 2 * HANDLE);
                    gc.strokeOval(p[0] - HANDLE, p[1] - HANDLE, 2 * HANDLE, 2 * HANDLE);
                } else {
                    gc.fillRect(p[0] - HANDLE, p[1] - HANDLE, 2 * HANDLE, 2 * HANDLE);
                    gc.strokeRect(p[0] - HANDLE, p[1] - HANDLE, 2 * HANDLE, 2 * HANDLE);
                }
            }
        }
        gc.setFill(Color.web("#ccd"));
        gc.fillText(caption + String.format("   (%d x %d, %.0f%%)", (int) iw, (int) ih, scale * 100)
                + (regions.isEmpty() ? "" : "   drag a region to edit it"), 8, 16);
    }
}
