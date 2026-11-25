package amv.flow.nativeapi;

import static java.lang.foreign.ValueLayout.JAVA_BYTE;
import static java.lang.foreign.ValueLayout.JAVA_INT;
import static java.lang.foreign.ValueLayout.JAVA_LONG;
import static java.nio.charset.StandardCharsets.UTF_8;

import java.lang.foreign.Arena;
import java.lang.foreign.MemorySegment;
import java.nio.file.Path;

/**
 * A flow of the AMV Flow engine (AMV.Flow.Graphs.Ks_Flow) behind the C API.
 * Every failure of the engine becomes an {@link AmvFlowException} with its
 * message. A flow is used by one thread at a time; {@link #close} frees it.
 */
public final class Flow implements AutoCloseable {

    /** An image a node took in the last run, as B, G, R, A bytes, rows top to bottom. */
    public record NodeImage(int width, int height, byte[] bgra) {
    }

    private MemorySegment handle;

    /** A new, empty flow. */
    public Flow() {
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment status = arena.allocate(AmvFlowNative.STATUS);
            handle = (MemorySegment) AmvFlowNative.FLOW_CREATE.invoke(status);
            check(status);
        } catch (AmvFlowException e) {
            throw e;
        } catch (Throwable t) {
            throw new IllegalStateException(t);
        }
    }

    /** The version of the C API of the loaded library. */
    public static int abiVersion() {
        try {
            return (int) AmvFlowNative.ABI_VERSION_FN.invoke();
        } catch (Throwable t) {
            throw new IllegalStateException(t);
        }
    }

    /** Whether the loaded library has the C API this binding was written for. */
    public static boolean abiMatches() {
        return abiVersion() == AmvFlowNative.ABI_VERSION;
    }

    /** The node kinds, their ports and parameters (AMV.Flow.Reports.Kinds_JSON). */
    public static String kindsJson() {
        return text((buffer, capacity, needed, status) ->
                AmvFlowNative.KINDS_JSON.invoke(buffer, capacity, needed, status));
    }

    // ------------------------------------------------------------------
    //  Files and JSON
    // ------------------------------------------------------------------

    public void load(Path path) {
        call((arena, status) -> AmvFlowNative.FLOW_LOAD.invoke(handle(), str(arena, path.toString()), status));
    }

    public void save(Path path) {
        call((arena, status) -> AmvFlowNative.FLOW_SAVE.invoke(handle(), str(arena, path.toString()), status));
    }

    public String toJson() {
        return text((buffer, capacity, needed, status) ->
                AmvFlowNative.FLOW_TO_JSON.invoke(handle(), buffer, capacity, needed, status));
    }

    /** Replaces the flow with the one in {@code json}; relative paths are taken from {@code baseDirectory}. */
    public void fromJson(String json, Path baseDirectory) {
        call((arena, status) -> AmvFlowNative.FLOW_FROM_JSON.invoke(handle(), str(arena, json),
                str(arena, baseDirectory == null ? "" : baseDirectory.toString()), status));
    }

    public void setBaseDirectory(Path directory) {
        call((arena, status) ->
                AmvFlowNative.FLOW_SET_BASE_DIRECTORY.invoke(handle(), str(arena, directory.toString()), status));
    }

    // ------------------------------------------------------------------
    //  Editing
    // ------------------------------------------------------------------

    /** Adds a node of the kind at the editor position and returns its id. */
    public long addNode(String kind, double x, double y) {
        long[] id = new long[1];
        call((arena, status) ->
                id[0] = (long) AmvFlowNative.FLOW_ADD_NODE.invoke(handle(), str(arena, kind), x, y, status));
        return id[0];
    }

    public void removeNode(long node) {
        call((arena, status) -> AmvFlowNative.FLOW_REMOVE_NODE.invoke(handle(), node, status));
    }

    public void setNodePosition(long node, double x, double y) {
        call((arena, status) -> AmvFlowNative.FLOW_SET_NODE_POSITION.invoke(handle(), node, x, y, status));
    }

    public void setNodeName(long node, String name) {
        call((arena, status) -> AmvFlowNative.FLOW_SET_NODE_NAME.invoke(handle(), node, str(arena, name), status));
    }

    /** Links two endpoints ("3.Width", "input.Image", "output.Pass"). */
    public void link(String from, String to) {
        call((arena, status) -> AmvFlowNative.FLOW_LINK.invoke(handle(), str(arena, from), str(arena, to), status));
    }

    public void unlink(String to) {
        call((arena, status) -> AmvFlowNative.FLOW_UNLINK.invoke(handle(), str(arena, to), status));
    }

    /** Sets a parameter from its JSON (a number, true / false, a quoted string or a shape object). */
    public void setParamJson(long node, String name, String valueJson) {
        call((arena, status) -> AmvFlowNative.FLOW_SET_PARAM_JSON.invoke(handle(), node, str(arena, name),
                str(arena, valueJson), status));
    }

    public void addInput(String name, String typeName) {
        call((arena, status) ->
                AmvFlowNative.FLOW_ADD_INPUT.invoke(handle(), str(arena, name), str(arena, typeName), status));
    }

    public void addOutput(String name, String typeName) {
        call((arena, status) ->
                AmvFlowNative.FLOW_ADD_OUTPUT.invoke(handle(), str(arena, name), str(arena, typeName), status));
    }

    /** What keeps the flow from running, as a JSON array of strings. */
    public String problemsJson() {
        return text((buffer, capacity, needed, status) ->
                AmvFlowNative.FLOW_PROBLEMS_JSON.invoke(handle(), buffer, capacity, needed, status));
    }

    // ------------------------------------------------------------------
    //  Running
    // ------------------------------------------------------------------

    /** Sets an Image_8_Grey input from grey pixels (one byte each, rows {@code stride} bytes apart). */
    public void setInputImage8(String input, int width, int height, int stride, byte[] pixels) {
        // The engine reads stride * (height - 1) + width bytes: the array must hold them.
        if (width < 1 || height < 1 || stride < width
                || pixels.length < (long) stride * (height - 1) + width) {
            throw new IllegalArgumentException("the pixels do not hold a " + width + " x " + height
                    + " image with rows " + stride + " bytes apart");
        }
        call((arena, status) -> AmvFlowNative.FLOW_SET_INPUT_IMAGE_8.invoke(handle(), str(arena, input), width,
                height, stride, arena.allocateFrom(JAVA_BYTE, pixels), status));
    }

    /** Sets an Image_8_Grey input from an image file (BMP or PGM). */
    public void setInputImageFile(String input, Path file) {
        call((arena, status) -> AmvFlowNative.FLOW_SET_INPUT_IMAGE_FILE.invoke(handle(), str(arena, input),
                str(arena, file.toString()), status));
    }

    public void run() {
        call((arena, status) -> AmvFlowNative.FLOW_RUN.invoke(handle(), status));
    }

    /** The results of the last run (AMV.Flow.Reports.Results_JSON). */
    public String resultsJson() {
        return text((buffer, capacity, needed, status) ->
                AmvFlowNative.FLOW_RESULTS_JSON.invoke(handle(), buffer, capacity, needed, status));
    }

    /** What to draw over the node's input image (AMV.Flow.Reports.Graphics_JSON). */
    public String graphicsJson(long node) {
        return text((buffer, capacity, needed, status) ->
                AmvFlowNative.NODE_GRAPHICS_JSON.invoke(handle(), node, buffer, capacity, needed, status));
    }

    /** The node's input image of the last run; null when it had none. */
    public NodeImage nodeImage(long node) {
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment status = arena.allocate(AmvFlowNative.STATUS);
            MemorySegment width = arena.allocate(JAVA_INT);
            MemorySegment height = arena.allocate(JAVA_INT);
            AmvFlowNative.NODE_IMAGE_BGRA.invoke(handle(), node, MemorySegment.NULL, 0L, width, height, status);
            check(status);
            int w = width.get(JAVA_INT, 0);
            int h = height.get(JAVA_INT, 0);
            if (w == 0 || h == 0) {
                return null;
            }
            long size = (long) w * h * 4;
            MemorySegment pixels = arena.allocate(size);
            AmvFlowNative.NODE_IMAGE_BGRA.invoke(handle(), node, pixels, size, width, height, status);
            check(status);
            return new NodeImage(w, h, pixels.toArray(JAVA_BYTE));
        } catch (AmvFlowException e) {
            throw e;
        } catch (Throwable t) {
            throw new IllegalStateException(t);
        }
    }

    @Override
    public void close() {
        if (handle != null) {
            try {
                AmvFlowNative.FLOW_DESTROY.invoke(handle);
            } catch (Throwable t) {
                throw new IllegalStateException(t);
            } finally {
                handle = null;
            }
        }
    }

    // ------------------------------------------------------------------
    //  Helpers
    // ------------------------------------------------------------------

    @FunctionalInterface
    private interface Call {
        void run(Arena arena, MemorySegment status) throws Throwable;
    }

    @FunctionalInterface
    private interface TextCall {
        void run(MemorySegment buffer, long capacity, MemorySegment needed, MemorySegment status) throws Throwable;
    }

    private MemorySegment handle() {
        if (handle == null) {
            throw new IllegalStateException("the flow is closed");
        }
        return handle;
    }

    private static MemorySegment str(Arena arena, String text) {
        return arena.allocateFrom(text, UTF_8);
    }

    private static void call(Call body) {
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment status = arena.allocate(AmvFlowNative.STATUS);
            body.run(arena, status);
            check(status);
        } catch (AmvFlowException | IllegalStateException e) {
            throw e;
        } catch (Throwable t) {
            throw new IllegalStateException(t);
        }
    }

    /** Asks for the size the text needs, then fetches it. */
    private static String text(TextCall body) {
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment status = arena.allocate(AmvFlowNative.STATUS);
            MemorySegment needed = arena.allocate(JAVA_LONG);
            body.run(MemorySegment.NULL, 0L, needed, status);
            check(status);
            long size = needed.get(JAVA_LONG, 0);
            MemorySegment buffer = arena.allocate(size);
            body.run(buffer, size, needed, status);
            check(status);
            return buffer.getString(0, UTF_8);
        } catch (AmvFlowException | IllegalStateException e) {
            throw e;
        } catch (Throwable t) {
            throw new IllegalStateException(t);
        }
    }

    private static void check(MemorySegment status) {
        int failure = status.get(JAVA_INT, 0);
        if (failure != 0) {
            int length = Math.max(0, Math.min(status.get(JAVA_INT, 4), AmvFlowNative.MAX_MESSAGE_LENGTH));
            byte[] message = status.asSlice(8, length).toArray(JAVA_BYTE);
            throw new AmvFlowException(failure, new String(message, UTF_8));
        }
    }
}
