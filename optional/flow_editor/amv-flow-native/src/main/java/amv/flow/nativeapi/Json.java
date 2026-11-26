package amv.flow.nativeapi;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * A small JSON reader and writer for the engine's reports: objects become
 * {@code Map<String, Object>} (in order), arrays {@code List<Object>},
 * numbers {@code Double}, and true / false / null {@code Boolean} / null.
 */
public final class Json {

    private final String text;
    private int pos;

    private Json(String text) {
        this.text = text;
    }

    public static Object parse(String text) {
        Json json = new Json(text);
        json.space();
        Object value = json.value();
        json.space();
        if (json.pos != text.length()) {
            throw json.error("text after the value");
        }
        return value;
    }

    @SuppressWarnings("unchecked")
    public static Map<String, Object> object(Object value) {
        if (value instanceof Map<?, ?> map) {
            return (Map<String, Object>) map;
        }
        throw new IllegalArgumentException("expected a JSON object");
    }

    @SuppressWarnings("unchecked")
    public static List<Object> array(Object value) {
        if (value instanceof List<?> list) {
            return (List<Object>) list;
        }
        throw new IllegalArgumentException("expected a JSON array");
    }

    public static String string(Object value) {
        return value == null ? "" : value instanceof String s ? s : value.toString();
    }

    public static double number(Object value) {
        if (value instanceof Double d) {
            return d;
        }
        throw new IllegalArgumentException("expected a JSON number");
    }

    /** A Java value as JSON (maps, lists, numbers, booleans, strings, null). */
    public static String write(Object value) {
        StringBuilder out = new StringBuilder();
        write(out, value);
        return out.toString();
    }

    /** A string as a JSON string literal. */
    public static String quote(String s) {
        StringBuilder out = new StringBuilder("\"");
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '"' -> out.append("\\\"");
                case '\\' -> out.append("\\\\");
                case '\n' -> out.append("\\n");
                case '\r' -> out.append("\\r");
                case '\t' -> out.append("\\t");
                default -> {
                    if (c < 0x20) {
                        out.append(String.format("\\u%04x", (int) c));
                    } else {
                        out.append(c);
                    }
                }
            }
        }
        return out.append('"').toString();
    }

    private static void write(StringBuilder out, Object value) {
        if (value == null) {
            out.append("null");
        } else if (value instanceof String s) {
            out.append(quote(s));
        } else if (value instanceof Double d) {
            out.append(d == Math.rint(d) && Math.abs(d) < 1e15 ? String.valueOf(d.longValue()) + ".0" : d.toString());
        } else if (value instanceof Number || value instanceof Boolean) {
            out.append(value);
        } else if (value instanceof Map<?, ?> map) {
            out.append('{');
            boolean first = true;
            for (Map.Entry<?, ?> e : map.entrySet()) {
                if (!first) {
                    out.append(", ");
                }
                first = false;
                out.append(quote(e.getKey().toString())).append(": ");
                write(out, e.getValue());
            }
            out.append('}');
        } else if (value instanceof List<?> list) {
            out.append('[');
            for (int i = 0; i < list.size(); i++) {
                if (i > 0) {
                    out.append(", ");
                }
                write(out, list.get(i));
            }
            out.append(']');
        } else {
            throw new IllegalArgumentException("cannot write " + value.getClass());
        }
    }

    private IllegalArgumentException error(String message) {
        return new IllegalArgumentException("JSON at " + pos + ": " + message);
    }

    private void space() {
        while (pos < text.length() && " \t\r\n".indexOf(text.charAt(pos)) >= 0) {
            pos++;
        }
    }

    private Object value() {
        if (pos >= text.length()) {
            throw error("expected a value");
        }
        char c = text.charAt(pos);
        return switch (c) {
            case '{' -> object();
            case '[' -> array();
            case '"' -> string();
            case 't' -> word("true", Boolean.TRUE);
            case 'f' -> word("false", Boolean.FALSE);
            case 'n' -> word("null", null);
            default -> number();
        };
    }

    private Object word(String word, Object value) {
        if (!text.startsWith(word, pos)) {
            throw error("unexpected character");
        }
        pos += word.length();
        return value;
    }

    private Map<String, Object> object() {
        Map<String, Object> map = new LinkedHashMap<>();
        pos++;
        space();
        if (pos < text.length() && text.charAt(pos) == '}') {
            pos++;
            return map;
        }
        while (true) {
            space();
            String key = string();
            space();
            expect(':');
            space();
            map.put(key, value());
            space();
            if (pos < text.length() && text.charAt(pos) == ',') {
                pos++;
            } else {
                expect('}');
                return map;
            }
        }
    }

    private List<Object> array() {
        List<Object> list = new ArrayList<>();
        pos++;
        space();
        if (pos < text.length() && text.charAt(pos) == ']') {
            pos++;
            return list;
        }
        while (true) {
            space();
            list.add(value());
            space();
            if (pos < text.length() && text.charAt(pos) == ',') {
                pos++;
            } else {
                expect(']');
                return list;
            }
        }
    }

    private void expect(char c) {
        if (pos >= text.length() || text.charAt(pos) != c) {
            throw error("expected '" + c + "'");
        }
        pos++;
    }

    private String string() {
        expect('"');
        StringBuilder out = new StringBuilder();
        while (true) {
            if (pos >= text.length()) {
                throw error("unterminated string");
            }
            char c = text.charAt(pos++);
            if (c == '"') {
                return out.toString();
            } else if (c == '\\') {
                if (pos >= text.length()) {
                    throw error("unterminated string");
                }
                char e = text.charAt(pos++);
                switch (e) {
                    case '"', '\\', '/' -> out.append(e);
                    case 'b' -> out.append('\b');
                    case 'f' -> out.append('\f');
                    case 'n' -> out.append('\n');
                    case 'r' -> out.append('\r');
                    case 't' -> out.append('\t');
                    case 'u' -> {
                        if (pos + 4 > text.length()) {
                            throw error("bad \\u escape");
                        }
                        out.append((char) Integer.parseInt(text.substring(pos, pos + 4), 16));
                        pos += 4;
                    }
                    default -> throw error("bad escape");
                }
            } else {
                out.append(c);
            }
        }
    }

    private Double number() {
        int start = pos;
        while (pos < text.length() && "+-0123456789.eE".indexOf(text.charAt(pos)) >= 0) {
            pos++;
        }
        if (start == pos) {
            throw error("unexpected character");
        }
        try {
            return Double.valueOf(text.substring(start, pos));
        } catch (NumberFormatException e) {
            throw error("bad number");
        }
    }
}
