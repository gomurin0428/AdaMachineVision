package amv.flow.editor;

import amv.flow.nativeapi.Flow;
import amv.flow.nativeapi.Json;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import javafx.scene.canvas.Canvas;
import javafx.scene.canvas.GraphicsContext;
import javafx.scene.image.PixelFormat;
import javafx.scene.image.WritableImage;
import javafx.scene.layout.Pane;
import javafx.scene.paint.Color;
import javafx.scene.text.Font;

/** The selected node's input image with its graphics (regions, found points) drawn over it. */
final class ImagePane extends Pane {

    private record Item(boolean polygon, boolean found, double[] xs, double[] ys) {
    }

    private final Canvas canvas = new Canvas();
    private WritableImage image;
    private List<Item> items = List.of();
    private String caption = "Select a node to see the image it takes";

    ImagePane() {
        setStyle("-fx-background-color: #121417;");
        setMinSize(0, 0);
        getChildren().add(canvas);
    }

    void show(Flow.NodeImage nodeImage, String graphicsJson, String text) {
        caption = text;
        if (nodeImage == null) {
            image = null;
            items = List.of();
        } else {
            image = new WritableImage(nodeImage.width(), nodeImage.height());
            image.getPixelWriter().setPixels(0, 0, nodeImage.width(), nodeImage.height(),
                    PixelFormat.getByteBgraPreInstance(), nodeImage.bgra(), 0, nodeImage.width() * 4);
            items = parse(graphicsJson);
        }
        redraw();
    }

    private static List<Item> parse(String json) {
        List<Item> result = new ArrayList<>();
        if (json == null) {
            return result;
        }
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
                result.add(new Item(true, "found".equals(item.get("role")), xs, ys));
            } else if ("point".equals(item.get("kind"))) {
                result.add(new Item(false, true, new double[] {Json.number(item.get("x"))},
                        new double[] {Json.number(item.get("y"))}));
            }
        }
        return result;
    }

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
        double scale = Math.min((w - 8) / iw, (h - 28) / ih);
        if (scale <= 0) {
            return;
        }
        double ox = (w - iw * scale) / 2;
        double oy = 22 + (h - 28 - ih * scale) / 2;
        gc.setImageSmoothing(scale < 1);
        gc.drawImage(image, ox, oy, iw * scale, ih * scale);
        // Pixel (i, j) covers [i - 0.5, i + 0.5]: its centre is at (i, j).
        for (Item item : items) {
            if (item.polygon()) {
                double[] xs = new double[item.xs().length];
                double[] ys = new double[item.ys().length];
                for (int i = 0; i < xs.length; i++) {
                    xs[i] = ox + (item.xs()[i] + 0.5) * scale;
                    ys[i] = oy + (item.ys()[i] + 0.5) * scale;
                }
                // Regions green, what the node found orange.
                gc.setStroke(Color.web(item.found() ? "#ffa726" : "#3ee05a"));
                gc.setLineWidth(item.found() ? 2.0 : 1.6);
                gc.strokePolygon(xs, ys, xs.length);
            } else {
                double x = ox + (item.xs()[0] + 0.5) * scale;
                double y = oy + (item.ys()[0] + 0.5) * scale;
                gc.setStroke(Color.web("#ff4d4d"));
                gc.setLineWidth(2);
                gc.strokeLine(x - 8, y, x + 8, y);
                gc.strokeLine(x, y - 8, x, y + 8);
            }
        }
        gc.setFill(Color.web("#ccd"));
        gc.fillText(caption + String.format("   (%d x %d)", (int) iw, (int) ih), 8, 16);
    }
}
