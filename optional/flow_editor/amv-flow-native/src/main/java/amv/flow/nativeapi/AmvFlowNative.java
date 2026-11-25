package amv.flow.nativeapi;

import static java.lang.foreign.ValueLayout.ADDRESS;
import static java.lang.foreign.ValueLayout.JAVA_BYTE;
import static java.lang.foreign.ValueLayout.JAVA_DOUBLE;
import static java.lang.foreign.ValueLayout.JAVA_INT;
import static java.lang.foreign.ValueLayout.JAVA_LONG;

import java.lang.foreign.Arena;
import java.lang.foreign.FunctionDescriptor;
import java.lang.foreign.Linker;
import java.lang.foreign.MemoryLayout;
import java.lang.foreign.StructLayout;
import java.lang.foreign.SymbolLookup;
import java.lang.invoke.MethodHandle;
import java.nio.file.Files;
import java.nio.file.Path;

/**
 * The downcall handles of the C API, one per function of amv_flow.h. The
 * library is the file named by the system property {@code amv.flow.library},
 * or libamvflow next to the working directory. Loading a library and
 * making downcalls are restricted methods: the launcher grants native access
 * with --enable-native-access.
 */
@SuppressWarnings("restricted")
final class AmvFlowNative {

    static final int ABI_VERSION = 1;
    static final int MAX_MESSAGE_LENGTH = 1023;

    static final StructLayout STATUS = MemoryLayout.structLayout(
            JAVA_INT.withName("failure"),
            JAVA_INT.withName("length"),
            MemoryLayout.sequenceLayout(MAX_MESSAGE_LENGTH + 1, JAVA_BYTE).withName("message"));

    private static final Linker LINKER = Linker.nativeLinker();
    private static final SymbolLookup LOOKUP = SymbolLookup.libraryLookup(libraryPath(), Arena.global());

    // Text out: (buffer, capacity, needed*, status*)
    private static final FunctionDescriptor TEXT = FunctionDescriptor.ofVoid(ADDRESS, JAVA_LONG, ADDRESS, ADDRESS);
    // Flow text out: (flow, buffer, capacity, needed*, status*)
    private static final FunctionDescriptor FLOW_TEXT =
            FunctionDescriptor.ofVoid(ADDRESS, ADDRESS, JAVA_LONG, ADDRESS, ADDRESS);
    // (flow, string, status*)
    private static final FunctionDescriptor FLOW_STRING = FunctionDescriptor.ofVoid(ADDRESS, ADDRESS, ADDRESS);
    // (flow, string, string, status*)
    private static final FunctionDescriptor FLOW_STRING_2 =
            FunctionDescriptor.ofVoid(ADDRESS, ADDRESS, ADDRESS, ADDRESS);

    static final MethodHandle ABI_VERSION_FN = find("amvf_abi_version", FunctionDescriptor.of(JAVA_INT));
    static final MethodHandle KINDS_JSON = find("amvf_kinds_json", TEXT);
    static final MethodHandle FLOW_CREATE = find("amvf_flow_create", FunctionDescriptor.of(ADDRESS, ADDRESS));
    static final MethodHandle FLOW_DESTROY = find("amvf_flow_destroy", FunctionDescriptor.ofVoid(ADDRESS));
    static final MethodHandle FLOW_LOAD = find("amvf_flow_load", FLOW_STRING);
    static final MethodHandle FLOW_SAVE = find("amvf_flow_save", FLOW_STRING);
    static final MethodHandle FLOW_TO_JSON = find("amvf_flow_to_json", FLOW_TEXT);
    static final MethodHandle FLOW_FROM_JSON = find("amvf_flow_from_json", FLOW_STRING_2);
    static final MethodHandle FLOW_SET_BASE_DIRECTORY = find("amvf_flow_set_base_directory", FLOW_STRING);
    static final MethodHandle FLOW_ADD_NODE = find("amvf_flow_add_node",
            FunctionDescriptor.of(JAVA_LONG, ADDRESS, ADDRESS, JAVA_DOUBLE, JAVA_DOUBLE, ADDRESS));
    static final MethodHandle FLOW_REMOVE_NODE = find("amvf_flow_remove_node",
            FunctionDescriptor.ofVoid(ADDRESS, JAVA_LONG, ADDRESS));
    static final MethodHandle FLOW_SET_NODE_POSITION = find("amvf_flow_set_node_position",
            FunctionDescriptor.ofVoid(ADDRESS, JAVA_LONG, JAVA_DOUBLE, JAVA_DOUBLE, ADDRESS));
    static final MethodHandle FLOW_SET_NODE_NAME = find("amvf_flow_set_node_name",
            FunctionDescriptor.ofVoid(ADDRESS, JAVA_LONG, ADDRESS, ADDRESS));
    static final MethodHandle FLOW_LINK = find("amvf_flow_link", FLOW_STRING_2);
    static final MethodHandle FLOW_UNLINK = find("amvf_flow_unlink", FLOW_STRING);
    static final MethodHandle FLOW_SET_PARAM_JSON = find("amvf_flow_set_param_json",
            FunctionDescriptor.ofVoid(ADDRESS, JAVA_LONG, ADDRESS, ADDRESS, ADDRESS));
    static final MethodHandle FLOW_ADD_INPUT = find("amvf_flow_add_input", FLOW_STRING_2);
    static final MethodHandle FLOW_ADD_OUTPUT = find("amvf_flow_add_output", FLOW_STRING_2);
    static final MethodHandle FLOW_PROBLEMS_JSON = find("amvf_flow_problems_json", FLOW_TEXT);
    static final MethodHandle FLOW_SET_INPUT_IMAGE_8 = find("amvf_flow_set_input_image_8",
            FunctionDescriptor.ofVoid(ADDRESS, ADDRESS, JAVA_INT, JAVA_INT, JAVA_INT, ADDRESS, ADDRESS));
    static final MethodHandle FLOW_SET_INPUT_IMAGE_FILE = find("amvf_flow_set_input_image_file", FLOW_STRING_2);
    static final MethodHandle FLOW_RUN = find("amvf_flow_run", FunctionDescriptor.ofVoid(ADDRESS, ADDRESS));
    static final MethodHandle FLOW_RESULTS_JSON = find("amvf_flow_results_json", FLOW_TEXT);
    static final MethodHandle NODE_GRAPHICS_JSON = find("amvf_node_graphics_json",
            FunctionDescriptor.ofVoid(ADDRESS, JAVA_LONG, ADDRESS, JAVA_LONG, ADDRESS, ADDRESS));
    static final MethodHandle NODE_IMAGE_BGRA = find("amvf_node_image_bgra",
            FunctionDescriptor.ofVoid(ADDRESS, JAVA_LONG, ADDRESS, JAVA_LONG, ADDRESS, ADDRESS, ADDRESS));

    private AmvFlowNative() {
    }

    private static Path libraryPath() {
        String property = System.getProperty("amv.flow.library");
        if (property != null && !property.isBlank()) {
            return Path.of(property);
        }
        String os = System.getProperty("os.name").toLowerCase();
        String name = os.contains("win") ? "libamvflow.dll" : os.contains("mac") ? "libamvflow.dylib" : "libamvflow.so";
        Path here = Path.of(System.getProperty("user.dir"), name);
        if (!Files.exists(here)) {
            throw new UnsatisfiedLinkError("the AMV Flow library " + name
                    + " is not in the working directory; set -Damv.flow.library=<path>");
        }
        return here;
    }

    private static MethodHandle find(String name, FunctionDescriptor descriptor) {
        return LINKER.downcallHandle(
                LOOKUP.find(name).orElseThrow(() -> new UnsatisfiedLinkError("no " + name + " in the AMV Flow library")),
                descriptor);
    }
}
