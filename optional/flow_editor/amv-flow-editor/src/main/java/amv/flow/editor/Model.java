package amv.flow.editor;

import amv.flow.nativeapi.Json;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** What the editor knows of the engine's JSON: node kinds, the flow and the results of a run. */
final class Model {

    private Model() {
    }

    record PortInfo(String name, boolean input, String type, boolean required, String help) {
    }

    /** A parameter; path: a file, relative to the flow file's folder unless absolute. */
    record ParamInfo(String name, String kind, Double low, Double high, List<String> choices, String unit,
            String help, boolean path) {
    }

    record KindInfo(String kind, List<PortInfo> ports, List<ParamInfo> params) {

        List<PortInfo> inputs() {
            return ports.stream().filter(PortInfo::input).toList();
        }

        List<PortInfo> outputs() {
            return ports.stream().filter(p -> !p.input()).toList();
        }
    }

    record IoInfo(String name, String type) {
    }

    record NodeInfo(long id, String kind, String name, double x, double y, Map<String, Object> params) {
    }

    record LinkInfo(String from, String to) {
    }

    record FlowInfo(String name, List<IoInfo> inputs, List<IoInfo> outputs, Map<Long, NodeInfo> nodes,
            List<LinkInfo> links) {

        static FlowInfo parse(String json) {
            Map<String, Object> root = Json.object(Json.parse(json));
            Map<Long, NodeInfo> nodes = new LinkedHashMap<>();
            for (Object o : Json.array(root.get("nodes"))) {
                Map<String, Object> n = Json.object(o);
                long id = (long) Json.number(n.get("id"));
                Map<String, Object> ui = n.containsKey("ui") ? Json.object(n.get("ui")) : Map.of();
                nodes.put(id, new NodeInfo(id, Json.string(n.get("kind")), Json.string(n.get("name")),
                        ui.containsKey("x") ? Json.number(ui.get("x")) : 0,
                        ui.containsKey("y") ? Json.number(ui.get("y")) : 0,
                        n.containsKey("params") ? Json.object(n.get("params")) : Map.of()));
            }
            List<LinkInfo> links = new ArrayList<>();
            for (Object o : Json.array(root.get("links"))) {
                Map<String, Object> l = Json.object(o);
                links.add(new LinkInfo(Json.string(l.get("from")), Json.string(l.get("to"))));
            }
            return new FlowInfo(Json.string(root.get("name")), io(root.get("inputs")), io(root.get("outputs")),
                    nodes, links);
        }

        private static List<IoInfo> io(Object list) {
            List<IoInfo> result = new ArrayList<>();
            for (Object o : Json.array(list)) {
                Map<String, Object> p = Json.object(o);
                result.add(new IoInfo(Json.string(p.get("name")), Json.string(p.get("type"))));
            }
            return result;
        }
    }

    record NodeResult(String state, String result, String message, double timeMs, Map<String, Object> outputs) {
    }

    record Results(String result, String message, Map<Long, NodeResult> nodes, Map<String, Object> outputs,
            Map<String, Object> counts) {

        static final Results NONE = new Results("", "", Map.of(), Map.of(), Map.of());

        /** The runs counted with the given result ("runs", "accept", "warning", "reject", "error"). */
        int count(String key) {
            return counts.get(key) instanceof Double d ? d.intValue() : 0;
        }

        static Results parse(String json) {
            Map<String, Object> root = Json.object(Json.parse(json));
            Map<Long, NodeResult> nodes = new LinkedHashMap<>();
            for (Object o : Json.array(root.get("nodes"))) {
                Map<String, Object> n = Json.object(o);
                nodes.put((long) Json.number(n.get("id")),
                        new NodeResult(Json.string(n.get("state")), Json.string(n.get("result")),
                                Json.string(n.get("message")), Json.number(n.get("timeMs")),
                                Json.object(n.get("outputs"))));
            }
            return new Results(Json.string(root.get("result")), Json.string(root.get("message")), nodes,
                    Json.object(root.get("outputs")),
                    root.get("counts") == null ? Map.of() : Json.object(root.get("counts")));
        }
    }

    static Map<String, KindInfo> parseKinds(String json) {
        Map<String, KindInfo> kinds = new LinkedHashMap<>();
        for (Object o : Json.array(Json.parse(json))) {
            Map<String, Object> k = Json.object(o);
            List<PortInfo> ports = new ArrayList<>();
            for (Object p : Json.array(k.get("ports"))) {
                Map<String, Object> m = Json.object(p);
                ports.add(new PortInfo(Json.string(m.get("name")), "in".equals(m.get("direction")),
                        Json.string(m.get("type")), Boolean.TRUE.equals(m.get("required")),
                        Json.string(m.get("help"))));
            }
            List<ParamInfo> params = new ArrayList<>();
            for (Object p : Json.array(k.get("params"))) {
                Map<String, Object> m = Json.object(p);
                List<String> choices = new ArrayList<>();
                if (m.containsKey("choices")) {
                    for (Object c : Json.array(m.get("choices"))) {
                        choices.add(Json.string(c));
                    }
                }
                params.add(new ParamInfo(Json.string(m.get("name")), Json.string(m.get("kind")),
                        m.containsKey("low") ? Json.number(m.get("low")) : null,
                        m.containsKey("high") ? Json.number(m.get("high")) : null,
                        choices, Json.string(m.get("unit")), Json.string(m.get("help")),
                        Boolean.TRUE.equals(m.get("path"))));
            }
            kinds.put(Json.string(k.get("kind")), new KindInfo(Json.string(k.get("kind")), ports, params));
        }
        return kinds;
    }

    /** A value of the results JSON as short text. */
    static String text(Object value) {
        if (value == null) {
            return "-";
        }
        if (value instanceof Double d) {
            return d == Math.rint(d) && Math.abs(d) < 1e12 ? String.valueOf(d.longValue())
                    : String.format("%.4f", d);
        }
        return value.toString();
    }
}
