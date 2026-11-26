package amv.flow.editor;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import amv.flow.editor.Model.FlowInfo;
import amv.flow.editor.Model.KindInfo;
import amv.flow.editor.Model.NodeInfo;
import amv.flow.editor.Model.PortInfo;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

/** The editor's model without the engine: which node the operator screen shows. */
class ModelTest {

    private static PortInfo port(String name, boolean input, String type) {
        return new PortInfo(name, input, type, false, "");
    }

    private static final Map<String, KindInfo> KINDS = Map.of(
            "Camera", new KindInfo("Camera", List.of(port("Image", false, "Image_8_Grey")), List.of()),
            "Blob", new KindInfo("Blob", List.of(port("Image", true, "Image_8_Grey"), port("Count", false, "Integer")),
                    List.of()),
            "PolarPoint", new KindInfo("PolarPoint", List.of(port("Image", true, "Image_8_Grey"),
                    port("X", true, "Real"), port("Angle", false, "Real")), List.of()),
            "RangeCheck", new KindInfo("RangeCheck", List.of(port("Value", true, "Real"),
                    port("Pass", false, "Boolean")), List.of()));

    // A camera (1), a blob on its image (2), a check (3), a PolarPoint whose
    // image is not linked (4), and a blob on the flow's input image (5).
    private static final String FLOW = """
            {"format": 1, "name": "f", "inputs": [{"name": "Image", "type": "Image_8_Grey"}], "outputs": [],
             "nodes": [{"id": 1, "kind": "Camera"}, {"id": 2, "kind": "Blob"}, {"id": 3, "kind": "RangeCheck"},
                       {"id": 4, "kind": "PolarPoint"}, {"id": 5, "kind": "Blob"}],
             "links": [{"from": "1.Image", "to": "2.Image"}, {"from": "2.Count", "to": "3.Value"},
                       {"from": "input.Image", "to": "5.Image"}]}
            """;

    @Test
    void theNodesWithAnImage() {
        FlowInfo info = FlowInfo.parse(FLOW);
        assertEquals(List.of(1L, 2L, 5L), Model.imageNodes(info, KINDS).stream().map(NodeInfo::id).toList());
    }

    @Test
    void whetherTheFlowTakesAnImage() {
        assertTrue(Model.takesImage(FlowInfo.parse(FLOW)), "node 5 takes the input image");
        String rewired = FLOW.replace("\"from\": \"input.Image\"", "\"from\": \"1.Image\"");
        assertFalse(Model.takesImage(FlowInfo.parse(rewired)), "node 5 rewired to the camera");
    }

    @Test
    void theImageErrorShown() {
        assertEquals("cannot read b.bmp", Model.imageErrorShown(FlowInfo.parse(FLOW), "cannot read b.bmp"),
                "shown while the flow takes the image");
        String rewired = FLOW.replace("\"from\": \"input.Image\"", "\"from\": \"1.Image\"");
        assertNull(Model.imageErrorShown(FlowInfo.parse(rewired), "cannot read b.bmp"),
                "not once the flow is rewired to the camera");
        assertNull(Model.imageErrorShown(FlowInfo.parse(FLOW), null), "no error, none shown");
    }

    @Test
    void theShownNode() {
        FlowInfo info = FlowInfo.parse(FLOW);
        assertEquals(5L, Model.displayed(info, KINDS, null), "by default the last node with an image");
        assertEquals(2L, Model.displayed(info, KINDS, 2L), "the one chosen");
        assertEquals(5L, Model.displayed(info, KINDS, 3L), "a node without an image is not shown");
        assertEquals(5L, Model.displayed(info, KINDS, 4L), "nor one whose image is not linked");
        assertEquals(5L, Model.displayed(info, KINDS, 99L), "nor one that is not there");
        assertNull(Model.displayed(FlowInfo.parse(
                "{\"name\": \"e\", \"inputs\": [], \"outputs\": [], \"nodes\": [], \"links\": []}"), KINDS, null),
                "no node with an image");
    }
}
