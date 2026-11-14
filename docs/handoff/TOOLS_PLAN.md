# Vision tools: how a tool is built

How a vision tool is split into its SPARK kernel and its Ada wrapper.
docs/DESIGN.md section 9 has the rules for every kernel; this page adds
what is particular to tools.

## Tools as SPARK kernels

These rules are binding for every tool.

1. **Where the logic lives.** Every tool's logic lives in a SPARK kernel
   `AMV.Kernels.<Tool>` (`src/amv-kernels-<tool>.ads/.adb`) under the
   rules of docs/DESIGN.md section 9: absence of run-time errors proved by
   `make prove`, no `pragma Assume`, and `SPARK_Mode => Off` bodies only
   for allocation (`Storage_Error` turned into `Failure_Out_Of_Memory`)
   and C memory views, each listed in docs/PROOF.md. Its entry points are
   the tool's C API (`Export, Convention => C`, names `ks_<tool>_*`),
   declared in `include/amv_<tool>.h`, which `include/amv.h` includes in
   its "Tools" section.
2. **The Ada API only wraps.** `AMV.<Tool>` keeps the object model of
   docs/DESIGN.md section 4 (a record extension of `AMV.Tools.Ks_Tool`,
   Run_Params, Results).
   Its `Execute` obtains kernel handles and transforms through entry
   points (`AMV.Images.Kernel_Images`, `AMV.Shapes.Kernel_Shapes`, the
   Regions kernel), calls the tool's execute entry point,
   `AMV.Checks.Check (Status)`, and stores the results; it never computes,
   validates or loops over pixels (docs/DESIGN.md 9.3; `make check` runs
   `tools/shell_check`, and new files never go on its legacy list).
3. **Run parameters.** A C struct `ks_<tool>_run_params` (int32_t codes
   for enumerations, int32_t 0/1 for booleans, double for reals, a fixed
   capacity array plus a count for a list) that
   `ks_<tool>_run_params_default` fills with the defaults. In Ada the
   kernel's record type (Convention C, every component with its default)
   is the run parameter record; `AMV.<Tool>` re-exports it as a subtype so
   that `Tool.Run_Params.Contrast_Threshold := 5.0;` works. The tool's
   header gives every enumeration code as a constant; the Ada API
   converts with `'Pos` / `'Val` or a constant table.
4. **Inputs.** Images arrive as kernel handles (`const ks_image_8_grey *`
   and so on); NULL is an image without pixels and fails with
   `KS_FAILURE_IMAGE_NO_PIXELS` and a message naming the property
   ("InputImage has no pixels"). A region that may be any shape arrives
   as a pixel region (`const ks_pixel_region *`) that
   the wrapper builds with the Regions kernel: the whole image
   (`ks_pixel_region_whole_image`) for an empty holder, otherwise
   `ks_pixel_region_rasterize_<shape>` with the transform
   `Image.Get_Transform ("#", Region.Selected_Space_Name)`. NULL, the
   empty region (no pixel of the image inside it), is legal: document
   what the tool reports for it. A tool that needs one particular shape
   (Caliper's affine rectangle) takes the shape struct of
   AMV.Kernels.Shapes and the transform from the shape's space to pixel
   space instead.
5. **Coordinates.** The kernel works in pixel space. The wrapper passes
   the transform from pixel space to the input image's selected space
   (`Get_Transform (".", "#")` through the Images kernel), and the kernel
   maps every position, angle and length it reports with it (document how
   lengths and areas scale under a transform that is not a similarity).
   Every reported coordinate stays within the bounds of
   AMV.Kernels.Shapes (1.0E150) so it is a valid argument again.
6. **Results.** An owned opaque handle `ks_<tool>_results *` that
   `ks_<tool>_execute` returns (NULL when it fails), with
   `ks_<tool>_results_destroy`, `ks_<tool>_results_count` and
   `ks_<tool>_results_item (results, index, ks_<tool>_result *item,
   status)` (0-based; `KS_FAILURE_INDEX_OUT_OF_RANGE` outside), plus the
   tool's own accessors (a label image as a new image handle, a boundary
   as a new polygon handle). Items are fixed-size C structs. In Ada,
   Results is a private type that keeps the handle in an
   `AMV.Shared_Handles` holder (copies share it, nobody changes it), and
   `Reset_Results` clears the holder. Results are not stored in streams
   (the holder writes nothing). A tool with a single result has
   singular accessors (`ks_<tool>_result_*`), and Blob's count and item
   take a `filtered` flag. A tool whose output is only an image or a
   number (OutputImage, Score) returns it from its execute entry point
   directly, as new image handles or a double, without a results handle.
7. **Trained objects** (the patterns of CNLSearch and PMAlign, the
   calibrations of CalibFix) are owned handles with train, destroy and
   duplicate entry points; using an untrained one fails with
   `KS_FAILURE_OPERATOR_NOT_TRAINED`. Users save them, so their Ada types
   get stream attributes that store the data by value through Ada-only
   kernel helpers that treat the stream as untrusted (as AMV.Images does).
8. **Failures and limits.** Only the failure codes the spec documents,
   with messages that name the property
   ("RunParams.ContrastThreshold must be >= 0"). Every size, count and
   capacity has a named limit (a C macro too); a run that would exceed one
   fails or cuts its results, as documented.
9. **Proof.** Silver everywhere: no run-time error for any argument,
   including non-finite values (rejected at the entry point, see
   docs/PROOF.md) and any handle that is NULL or came from the kernel.
   Gold for the discrete facts each task names (for example: the blob
   areas and the background count add up to the region's pixel count; the
   histogram bins add up to the number of samples). Floating-point
   results: finite and within their stated ranges.
10. **Tests.** `tests/test_<tool>.adb` tests the Ada API through `Run`
    (the cases the task lists) and calls the kernel directly for what the
    Ada API cannot reach (NULL handles, non-finite values, limits); add it
    to `tests/test_suite.adb` (one `with`, one `Run_Area`).
    `tests/c/test_c_<tool>.c` defines `void test_c_<tool> (void)` with the
    helpers of `tests/c/c_test_support.h`; `tests/c/test_c_api.c`
    declares and calls it.
11. **Shared files.** Besides its own files a tool may touch only: one
    include line in `include/amv.h`, one entry each in
    `tests/test_suite.adb` and `tests/c/test_c_api.c`, its unit in the
    `Prove` package of `amv.gpr` (only to raise its level), new rows and
    paragraphs in `docs/PROOF.md`, and new
    subprograms (never changes) in the core kernels when a proof needs a
    helper. It does not edit the total line of docs/PROOF.md,
    docs/handoff/SPARK_PLAN.md or the READMEs; it reports its counts.
12. **Build and check** in your own git worktree: `make check`,
    `make test`, and `make prove` (or, while working, `gnatprove -P
    amv.gpr -u <your units>`). Every PR passes all three.
