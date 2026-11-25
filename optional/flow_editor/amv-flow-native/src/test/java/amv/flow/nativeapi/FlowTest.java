package amv.flow.nativeapi;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Assumptions;
import org.junit.jupiter.api.Test;

/** The binding against the real library (build it with make build-flow-c). */
class FlowTest {

    @Test
    void abiMatches() {
        assertTrue(Flow.abiMatches(), "the library's ABI version is " + Flow.abiVersion());
    }

    @Test
    void kindsListTheNodeKinds() {
        List<Object> kinds = Json.array(Json.parse(Flow.kindsJson()));
        assertTrue(kinds.stream().anyMatch(k -> "Caliper".equals(Json.object(k).get("kind"))));
    }

    @Test
    void buildAndRunABlobFlow() {
        int w = 120;
        int h = 90;
        byte[] pixels = new byte[w * h];
        for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
                double dx = x - 60.0;
                double dy = y - 45.0;
                pixels[y * w + x] = (byte) (dx * dx + dy * dy <= 400 ? 220 : 30);
            }
        }
        try (Flow flow = new Flow()) {
            flow.addInput("Image", "Image_8_Grey");
            flow.addOutput("Area", "Real");
            long blob = flow.addNode("Blob", 10, 20);
            assertEquals(1, blob);
            flow.setParamJson(blob, "MinArea", "50");
            flow.link("input.Image", "1.Image");
            flow.link("1.Area", "output.Area");
            assertEquals(List.of(), Json.array(Json.parse(flow.problemsJson())));
            flow.setInputImage8("Image", w, h, w, pixels);
            flow.run();
            Map<String, Object> results = Json.object(Json.parse(flow.resultsJson()));
            assertEquals("accept", results.get("result"));
            double area = Json.number(Json.object(results.get("outputs")).get("Area"));
            assertEquals(Math.PI * 400, area, Math.PI * 400 * 0.05);

            Flow.NodeImage image = flow.nodeImage(blob);
            assertNotNull(image);
            assertEquals(w, image.width());
            assertEquals(h, image.height());
            assertEquals((byte) 220, image.bgra()[(45 * w + 60) * 4]);
            assertEquals((byte) 255, image.bgra()[3]);

            Map<String, Object> graphics = Json.object(Json.parse(flow.graphicsJson(blob)));
            assertEquals(120.0, Json.number(graphics.get("width")));
        }
    }

    @Test
    void failuresBecomeExceptions() {
        try (Flow flow = new Flow()) {
            long blob = flow.addNode("Blob", 0, 0);
            AmvFlowException e = assertThrows(AmvFlowException.class,
                    () -> flow.link("1.Area", "1.Image"));
            assertEquals(AmvFlowException.FAILURE_FLOW, e.failure());
            assertTrue(e.getMessage().contains("cannot link"), e.getMessage());
            e = assertThrows(AmvFlowException.class, () -> flow.setParamJson(blob, "Threshold", "300"));
            assertTrue(e.getMessage().contains("must be in"), e.getMessage());
            assertThrows(AmvFlowException.class, () -> flow.addNode("Telescope", 0, 0));
            assertNull(flow.nodeImage(blob));
        }
    }

    @Test
    void theAlignFlowFile() {
        Path dir = Path.of(System.getProperty("amv.flow.testdir", "build/flow-test"));
        Path file = dir.resolve("align.amvflow");
        Assumptions.assumeTrue(Files.exists(file), "run make test-flow first");
        try (Flow flow = new Flow()) {
            flow.load(file);
            flow.setInputImageFile("Image", dir.resolve("align_model.bmp"));
            flow.run();
            Map<String, Object> results = Json.object(Json.parse(flow.resultsJson()));
            assertEquals("accept", results.get("result"));
            Map<String, Object> outputs = Json.object(results.get("outputs"));
            assertEquals(14.0, Json.number(outputs.get("Slot")), 0.1);
            assertEquals(120.0, Json.number(outputs.get("Plate")), 0.1);
            assertTrue(flow.toJson().contains("\"kind\": \"ShapeMatch\""));
        }
    }
}
