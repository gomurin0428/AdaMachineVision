package amv.flow.nativeapi;

import java.io.Serial;

/** A failure reported by the AMV Flow engine (an amvf_status that is not OK). */
public final class AmvFlowException extends RuntimeException {

    @Serial
    private static final long serialVersionUID = 1L;

    /** AMVF_FAILURE_FLOW: not a valid flow, file or edit. */
    public static final int FAILURE_FLOW = 1;
    /** AMVF_FAILURE_BAD_ARGUMENT: a NULL handle, a small buffer, a bad size. */
    public static final int FAILURE_BAD_ARGUMENT = 2;
    /** AMVF_FAILURE_AMV: an AMV tool or image failure. */
    public static final int FAILURE_AMV = 3;
    /** AMVF_FAILURE_OUT_OF_MEMORY. */
    public static final int FAILURE_OUT_OF_MEMORY = 4;
    /** AMVF_FAILURE_INTERNAL. */
    public static final int FAILURE_INTERNAL = 5;

    private final int failure;

    public AmvFlowException(int failure, String message) {
        super(message);
        this.failure = failure;
    }

    /** The failure code (one of the FAILURE_ constants). */
    public int failure() {
        return failure;
    }
}
