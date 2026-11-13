# AdaMachineVision design rules

This file is the contract for every package in the library. Read it before
adding or changing a public unit.

## 1. Goal and the clean-room rule

AMV mirrors the *interface* of the Cognex VisionPro .NET API: the same
concepts (images with a coordinate space tree, shapes and regions, tools
with `InputImage` / `Region` / `RunParams` / `Run` / `Results` /
`RunStatus`), the same class, property, method and enumeration names mapped
to Ada naming, and the same coordinate and result conventions where the
public VisionPro documentation states them.

Everything behind the interface is our own implementation:

* Never copy Cognex source code, headers, binaries, sample code or
  documentation text. Write all comments and docs in our own words.
* Algorithms come from public literature (connected components, Gaussian
  and Sobel filters, normalized cross-correlation, gradient-orientation
  shape matching, least squares fitting, ...) or are our own.
* Where VisionPro behaviour is unknown or undocumented, choose a sensible
  behaviour and document it in the package spec. Fidelity of the *interface*
  matters more than bit-exact results.
* "Cognex" and "VisionPro" appear only in documentation that explains the
  mapping and in the trademark notice. The root package is `AMV`. Type and
  exception names replace VisionPro's `Cog` prefix with `Ks`
  (`CogBlobTool` -> `Ks_Blob_Tool`), so code ports mechanically while AMV
  does not reuse the Cognex prefix. Original VisionPro names such as
  `CogBlobTool` appear only in comments and mapping documents, as
  references.

## 2. Package layout

VisionPro namespaces map to child packages of `AMV`:

| VisionPro namespace                 | Ada package                    |
|-------------------------------------|--------------------------------|
| `Cognex.VisionPro` (core)           | `AMV`, `AMV.Misc`, `AMV.Transforms`, `AMV.Coordinate_Spaces`, `AMV.Images`, `AMV.Shapes`, `AMV.Tools` |
| `Cognex.VisionPro.ImageFile`        | `AMV.Image_File`               |
| `Cognex.VisionPro.Blob`             | `AMV.Blob`                     |
| `Cognex.VisionPro.Caliper`          | `AMV.Caliper`, `AMV.Caliper.Find_Line`, `AMV.Caliper.Find_Circle` |
| `Cognex.VisionPro.Dimensioning`     | `AMV.Dimensioning`             |
| `Cognex.VisionPro.ImageProcessing`  | `AMV.Image_Processing` (+ children) |
| `Cognex.VisionPro.CNLSearch`        | `AMV.CNL_Search`               |
| `Cognex.VisionPro.PMAlign`          | `AMV.PM_Align`                 |
| `Cognex.VisionPro.CalibFix`         | `AMV.Cal_Fix`                  |
| `Cognex.VisionPro.ToolGroup`        | `AMV.Tool_Group`               |

Support packages that have no VisionPro counterpart: `AMV.Regions`
(rasterising a region into image pixels), `AMV.Image_Math` (floating point
images, sampling, filters, pyramids), `AMV.Geometry` (lines, circles and
least squares fitting). Tools reuse these instead of re-implementing them.

`AMV.Kernels` and its children hold the SPARK kernels behind all of these
packages; their entry points form the C API (section 9).

## 3. Naming

* `CogBlobTool` -> `Ks_Blob_Tool`; `CogImage8Grey` -> `Ks_Image_8_Grey`;
  `CogPMAlignTool` -> `Ks_PM_Align_Tool`; `CogCNLSearchTool` ->
  `Ks_CNL_Search_Tool`; `CogIPOneImageTool` -> `Ks_IP_One_Image_Tool`.
  Replace the leading `Cog` (or `ICog` for interfaces) by `Ks`, then insert
  `_` at every lower-to-upper case boundary and between letters and digits;
  keep known acronyms (PM, CNL, IP, ID, RMS) together. `XY` naming a
  coordinate pair also stays one word, set off by `_`:
  `SetCenterXYRadiusXYRotation` -> `Set_Center_XY_Radius_XY_Rotation`,
  `SetFromStartXYEndXY` -> `Set_From_Start_XY_End_XY`.
* Properties: a read-only property `Foo` is a function `Foo (Obj)`. A
  read-write property on a *private* type is a function `Foo (Obj)` plus a
  procedure `Set_Foo (Obj, Value)`. On a *public record* (see 4) it is a
  record component.
* Methods keep their name: `Run`, `Train`, `MapPoint` -> `Map_Point`,
  `GetPose` -> `Get_Pose`, `SetCenterLengthsRotationSkew` ->
  `Set_Center_Lengths_Rotation_Skew`.
* .NET `out` parameters stay `out` parameters, in the same order.
* Enumerations keep the VisionPro type name (`Ks_Blob_Segmentation_Polarity_Constants`)
  and literal names (`Dark_Blobs`, `Light_Blobs`). A literal that is an Ada
  reserved word gets `_` plus the last noun of the type name appended:
  `CogToolResultConstants.Accept` -> `Accept_Result`. Record every such
  rename in `docs/API_MAPPING.md`.
* Collections are 0-based like .NET: `Results.Count` and
  `Results.Item (0 .. Count - 1)`.

## 4. Object model

* **Value objects with invariants** (transforms, shapes, images, coordinate
  space trees, run status, results, trained patterns, calibrations) are
  tagged private types with getter functions and `Set_` procedures, so
  prefix notation reads like VisionPro: `Rect.Set_Center_Width_Height (...)`,
  `Pose.Translation_X`.
* **Parameter bags** (RunParams objects such as `CogBlob`, `CogCaliper`,
  segmentation parameters) are public records with default values for every
  component, so `Tool.Run_Params.Contrast_Threshold := 5.0;` works.
* **Tools** are public record extensions of the private
  `AMV.Tools.Ks_Tool`:

  ```ada
  type Ks_Blob_Tool is new AMV.Tools.Ks_Tool with record
     Input_Image : AMV.Images.Ks_Image_8_Grey;
     Region      : AMV.Shapes.Region_Holders.Holder;  --  empty = whole image
     Run_Params  : Ks_Blob;
     Results     : Ks_Blob_Results;                  --  set by Run
  end record;

  overriding procedure Execute (Tool : in out Ks_Blob_Tool);
  overriding procedure Reset_Results (Tool : in out Ks_Blob_Tool);
  ```

  so user code reads `Tool.Input_Image := Img; Tool.Run;
  N := Tool.Results.Count;`. `Results` is read-only by convention: only the
  tool writes it. Result items (one blob, one edge, one match) are public
  records; methods VisionPro offers on them (`GetPose`, `GetMeasure`) are
  functions in the same package.
* `Run` (class-wide, in `AMV.Tools`) clears the results via the
  `Reset_Results` primitive, times the run, calls the `Execute` primitive
  and turns any exception into `Run_Status.Result = Error` with the
  exception message. Tools never let an exception escape `Run`. `Execute`
  may call `Set_Result (Tool, Warning | Reject, "why")`.
* Images have .NET reference semantics for pixels: assignment shares the
  pixel buffer (reference counted); `Copy` makes an independent image
  (`Copy (Image, No_Pixels)` an unallocated one with the same coordinate
  space state). The coordinate space tree and selected space name are
  copied by assignment.

## 5. Coordinates

* Pixel space `"#"`: x to the right, y down, **the centre of pixel (i, j)
  is at (i, j)**. The image covers [-0.5, Width - 0.5] x [-0.5, Height - 0.5].
* Angles are radians, counter-clockwise *as seen in a y-down image* means
  the rotation matrix [cos -sin; sin cos] applied to (x, y). `AMV.Misc` has
  `Deg_To_Rad` / `Rad_To_Deg` / `Norm_Angle`.
* Every image has a coordinate space tree whose root is `"@"`, a
  `Pixel_From_Root_Transform` (identity by default) and a
  `Selected_Space_Name` (`"@"` by default). Child spaces are named by path:
  `"@\Fixture"`, `"@\Fixture\Part"`. `"."` means "the image's selected
  space" and `"#"` means pixel space wherever a space name is accepted.
* Every space of a tree other than the root stores its
  `Parent_From_Child` transform, which maps coordinates in the space to
  coordinates in its parent, exactly as given. As in VisionPro, it is
  given to `Add_Space` as `Parent_From_New` (and to `Change_Transform` as
  `New_Parent_From_Child`): a space added with a translation (10, 0) has
  its origin at (10, 0) in the parent. `Tree.Get_Transform (To, From)`
  maps From's coordinates up to the root and then down to To.
* Shapes have a `Selected_Space_Name` (default `"."`). A tool maps its
  region into pixel space with
  `Image.Get_Transform ("#", Region.Selected_Space_Name)`.
* Tools report positions, poses and lengths in the input image's selected
  space `"."` unless the VisionPro equivalent documents otherwise. Internally
  they work in pixel space and map results with
  `Image.Get_Transform (".", "#")`.
* `Ks_Transform_2D_Linear` maps (x, y) to (A x + B y + Tx, C x + D y + Ty).
  `T1.Compose (T2)` is "apply T2, then T1". A pose returned by a search tool
  maps pattern (model) coordinates to the input image's selected space, so
  it can be fed directly to the fixture tool as
  `Unfixtured_From_Fixtured_Transform`, which the fixture tool passes on
  unchanged to `Add_Space` as `Parent_From_New` (the fixtured space is a
  child of the selected space).

## 6. Errors

* Exceptions are declared in `AMV` (`Ks_Exception`,
  `Ks_Image_No_Pixels_Exception`, `Ks_Image_Bad_Selected_Space_Name_Exception`,
  `Ks_Operator_Not_Trained_Exception`, `Ks_Transform_Singular_Exception`,
  `Ks_Image_File_Exception`, `Ks_Bad_Parameter_Exception`).
  `Ks_Operator_Not_Trained_Exception` is VisionPro's
  `CogOperatorNotTrainedException`; `Ks_Bad_Parameter_Exception` stands
  for .NET's `System.ArgumentException`, which VisionPro raises for a bad
  argument (it has no Cog exception of its own for that); the mapping is
  in `docs/API_MAPPING.md`. Raise them with a message that names the
  offending property, e.g.
  `raise Ks_Bad_Parameter_Exception with "RunParams.ContrastThreshold must be >= 0";`
* Pixel index errors in `Get_Pixel` / `Set_Pixel` raise `Constraint_Error`.
* Validate parameters at `Run` / `Train` time, as VisionPro does.
* The kernels (section 9) never raise: they return a `Ks_Status` whose
  failure code corresponds one to one to the exceptions above
  (`Failure_Operator_Not_Trained` to `Ks_Operator_Not_Trained_Exception`,
  ..., `Failure_Out_Of_Memory` to `Storage_Error`). The Ada API turns it into
  the exception with `AMV.Checks.Check`, keeping the kernel's message.

## 7. Implementation rules

* Ada 2022. The reference toolchain is GNAT 16.1, gprbuild 26 and
  gnatprove 16.1 (GNAT FSF builds); GNAT 14 also builds and tests the
  library's Ada code, but proofs need gnatprove 16. No external libraries: the
  runtime (`Ada.*`, `Interfaces`, `System.Atomic_Operations`) only. The
  library itself is written in Ada; C appears only in the C API header
  (`include/amv.h`), the C tests (`tests/c/`) and C examples.
* Large pixel data lives on the heap (images, `Real_Image`, masks). Never
  declare a whole-image array as a local object on the primary stack.
* No memory leaks. In the Ada API every heap object is owned by a
  controlled type; in the kernels every heap object is owned by an access
  object under SPARK's ownership rules (section 9), which gnatprove checks
  for leaks.
* Every type that owns heap memory through an access component specifies
  its own `Read` and `Write` stream attributes. The predefined ones would
  copy the pointer itself (without counting the new owner) and `Read`
  would install whatever pointer the stream holds. Store the data by value
  and treat a stream being read as untrusted: validate every size before
  allocating and leave the target valid when the data is malformed
  (`Ks_Image_File_Exception`). A record that holds such a type gets its
  own `Read` too: it reads every component into a fresh object, checks
  each enumeration, Boolean and Natural with `'Valid`
  (`AMV.Checks.Check_Read`), assigns the object only when all were read,
  and turns `End_Error`, `Tag_Error` and `Constraint_Error` into
  `Ks_Image_File_Exception` (`AMV.Checks.Stream_Malformed`).
* Use `-gnatwa`-clean code; `make check` builds with `-gnatwe`.
* Each package spec documents the behaviour, units and coordinate space of
  every subprogram in comments of our own wording.
* Prefer clarity over micro-optimisation, but keep algorithms at sensible
  complexity (no O(N^2) over image pixels where O(N) is standard).

## 8. Tests

* Tests live in `tests/`. Each area has a parameterless procedure
  `tests/test_<area>.adb` (for example `Test_Blob`) that uses
  `AMV_Test_Support` (`Section`, `Check`, `Check_Near`) and is also usable
  as a standalone main:

  ```
  gprbuild -p -P amv_tests.gpr --subdirs=<you> test_blob.adb
  ./build/bin/<you>/test_blob      # exit status 1 on any failure
  ```

  Pass a private `--subdirs` value when several people build at once.
  `tests/test_suite.adb` calls every `Test_<area>` procedure.
* Test images are generated in code with `AMV_Test_Images` (filled
  rectangles, circles and polygons with anti-aliased edges, gradients,
  deterministic noise); no binary fixtures in the repository.
* Every tool has tests that check its geometric results against known
  ground truth (positions to sub-pixel tolerance, angles, areas), its
  parameter validation, and its `Run_Status` on success and failure.
* Tests stay alongside the proofs: proofs show the absence of run-time
  errors and the stated properties, tests show numerical accuracy and the
  behaviour of the Ada API. `tests/test_kernels.adb` covers the kernel
  layer itself (status, layout, non-finite inputs); `tests/c/` calls the
  C API from C (`make test` runs both).
* `tests/test_robustness.adb` sweeps the whole Ada API with adversarial
  inputs: every tool type runs with an unallocated, a 1 x 1, a large and
  oddly placed input image, and with each numeric parameter, region and
  shape coordinate set in turn to NaN, +-Inf, 0, -1 and huge values, each
  integer to Integer'First, -1, 0 and Integer'Last, each space name to a
  malformed one; the other subprograms that take numbers (and the
  stream attributes of images, trees, pixel regions, real images, shapes,
  patterns, calibrations and fit points) get
  the same values. Every exception must be an AMV one, or the
  Constraint_Error a spec documents for an index. A new tool or
  subprogram that takes numbers gets its place in that sweep.

## 9. SPARK kernels and the C API

The library has three layers (the full rationale is in
`docs/handoff/SPARK_PLAN.md`):

| Layer | Packages | SPARK_Mode | Contents |
|---|---|---|---|
| Kernel entry points | visible part of `AMV.Kernels.*` | On | A VisionPro-like API with C-compatible types; **this is the C API** (`include/amv.h`). Validates every input, returns a `Ks_Status`. |
| Kernel internals | private parts, bodies, private children of `AMV.Kernels.*` | On | All the logic, written with whatever Ada types prove best. |
| Ada API | `AMV.Misc`, `AMV.Transforms`, ... | Off | VisionPro-style objects (controlled types, exceptions, class-wide types) that only call entry points. |

Every file of the Ada API starts with `pragma SPARK_Mode (Off);`, so that
gnatprove leaves it alone (gnatprove 16.1 crashed on an Ada API unit that
did not say, AdaCore/spark2014#84). Only the root package `AMV` is in
SPARK, because the kernels are its children.

Packages whose logic has not moved into a kernel yet are listed in
`tools/shell_check_legacy.txt`; new packages, tools included, are written
in this form from the start. How a vision tool is split into its kernel
and its Ada wrapper is set out in `docs/handoff/TOOLS_PLAN.md` ("Tools as
SPARK kernels").

### 9.1 Entry points (the C API)

* C-compatible types only: `Long_Float` (C `double`), `AMV.Kernels.Int32` /
  `Int64`, the unsigned types of `Interfaces`, records with
  `Convention => C`, and owned access types for handles (C sees an opaque
  `ks_..._t *`). No `Boolean` (an `Int32` that must be 0 or 1) and no
  enumeration (an `Int32` code checked before it is converted). Variable
  sized data (pixels, result lists, trained patterns, polygon vertices)
  lives behind handles with `ks_<type>_create` / `ks_<type>_destroy`.
* `Export`, `Convention => C`, `External_Name => "ks_<type>_<operation>"`
  (for example `ks_misc_norm_angle`, `ks_transform_2d_linear_invert`,
  `ks_blob_tool_run`).
* No precondition. Every input is checked inside: finiteness and the
  documented bounds of every `Long_Float` (each kernel states its bounds
  and why), codes, sizes, null handles. Failures are reported in an
  `out Ks_Status` whose message names the property or argument at fault,
  VisionPro style.
* A null handle stands for an object without contents (an image without
  pixels): queries of its size give 0, operations that need the contents
  fail with the matching code (`Image_No_Pixels`). SPARK cannot compare
  two handles (`=` on access values is not SPARK), so an entry point
  cannot reject the same handle passed twice; an entry point that takes
  several handles must therefore stay safe when they alias (change only
  values, never a size or an owned array) and document the result.
* Never raise. The only exception that can escape is `Storage_Error`;
  allocations go through small trusted helpers that turn it into
  `Failure_Out_Of_Memory`, and no array whose size depends on the input
  is declared on the stack.
* Records grow only at their end. `AMV.Kernels.ABI_Version`
  (`ks_abi_version`) changes on any incompatible change.
* Compatibility since release 0.1.0 (ABI version 2). A pull request that
  makes the C API incompatible (a record's layout or size, a parameter
  list, the meaning of a code or a value) raises `ABI_Version` and
  `KS_ABI_VERSION` together, unless an earlier change since the last
  release already raised them, and says so under "Unreleased" in
  `CHANGELOG.md`. A type with its own stream format (a stream code: the
  images, trees, regions, patterns, calibrations, fit points) keeps the
  streams of an earlier release readable: a changed format gets a new
  stream code, and `Read` still accepts the old code with the old
  meaning (as the CNL pattern does for its train region mode). A record
  streamed by the predefined attributes (run parameters, tools, result
  records) changes its stream format whenever a component is added;
  `CHANGELOG.md` lists such a change. Removing or renaming a public Ada
  or C name is listed in `CHANGELOG.md` as well.
* Images: the kernels never share a pixel buffer (`SPARK_PLAN.md` 3.6,
  plan A). Sharing by assignment, as in VisionPro, is done only by the
  Ada API, which keeps the kernel's pixel handle in a reference-counted
  box; the coordinate space state is passed separately. Other handles
  the Ada API only reads (the results of a tool run) are shared the same
  way through the generic `AMV.Shared_Handles`.

### 9.2 Every kernel unit

* Starts (spec and body) with `pragma Validity_Checks ("F");` so that NaN
  and infinities reach the entry point's range checks instead of raising
  at the call, and with the assertion policy of `SPARK_PLAN.md` 4.5
  (`Pre => Check`, everything else `Ignore`): contracts are proved, not
  executed, even in the test build.
* Depends only on `AMV`, other kernels, `Interfaces`,
  `Ada.Numerics.Long_Elementary_Functions` and, for the trusted entry
  points that take C memory, `System` (`System.Address`). No sparklib,
  no controlled types, tasks, exceptions, tagged or class-wide types, or
  aliasing access types.
* Every subprogram has a contract: `Pre` (cheap, without quantifiers) on
  internal subprograms, and a `Post` that states at least the range of
  the results and the failure codes that can occur.
* Forbidden: `pragma Assume`, `pragma Annotate (GNATprove, False_Positive
  | Intentional, ...)`, `Skip_Proof` / `Skip_Flow_And_Proof`, and
  `SPARK_Mode => Off` except in the trusted helpers listed in
  `docs/PROOF.md`. A property that cannot be proved is dropped from the
  `Post` and documented, never assumed.
* gnatprove 16 does not support the non-static attributes `'Exponent` and
  `'Scaling`. Scale by static powers of two instead (for example
  `X / 2.0**600`), which is just as exact.
* Every kernel bounds its floating-point inputs (and its results, so that
  they are valid inputs again) and states the bound and its reason in its
  spec; `AMV.Kernels.Transforms` uses 1.0E150. Keep floating-point proofs
  linear: compute products and quotients through the bounded helpers of
  the private package `AMV.Kernels.Numerics` (`Mul`, `Times_Unit`,
  `Unit_Ratio`, `Ratio_Within`, `Hypot`, and `Mul_Small` and `Times_Small`
  for tighter bounds), whose bodies are hidden from the
  caller, and wrap attributes whose prover model is heavy (`'Remainder`)
  in a function without a postcondition. A clamp that can never trigger
  may stand in for a missing library contract (the `Sqrt` upper bound),
  but list it in `docs/PROOF.md`.
* Data invariants (such as `Valid_Tree` of the coordinate space kernel):
  state the quantified part on array entries rather than through a
  function of the whole structure, call only functions without
  preconditions inside the quantifier, and let internal subprograms take
  a subtype whose `Dynamic_Predicate` is the invariant (proved at each
  call, not executed) instead of a quantified `Pre`. See "Proof notes" in
  `docs/PROOF.md`.

### 9.3 The Ada API stays thin

The body of an Ada API subprogram may only: pass values to an entry point
(converting enumerations with `'Pos` / `'Val`), call entry points (one per
operation as a rule), manage handle lifetimes and the reference counting
of pixel handles and of the handles in `AMV.Shared_Handles`, call
`AMV.Checks.Check (Status)`, record the run status and time in `Run`
(`AMV.Tools`), and do file I/O to and from byte arrays. It does not
compute with `Real` or pixel values, validate inputs, loop over pixels or
coordinates, use `Ada.Numerics`, branch on results or parse space names.

One exception is allowed for accessors called once per pixel (in
`AMV.Images`, `Get_Pixel` and `Set_Pixel`), where building a status
costs more than the access itself: they call a lean Ada-only kernel
variant (`Try_*`) whose proved postcondition says it succeeds exactly
when the entry point does, with the same effect, and only when it
reports a failure do they call the entry point to obtain the status.

A conversion to a constrained Ada type (`Natural (Count)`,
`Boolean'Val (Flag)`, `'Val (Code)`) is applied only to a value whose
range the entry point that produced it states in its `Post`. A code, flag
or count that the user can write into a public record goes through an
entry point that checks it (`AMV.Caliper.Kind` of a scorer, `Count` of a
scorer list, ...: Bad_Parameter), never through a bare conversion.

Every file of the Ada API, spec and body, starts with
`pragma SPARK_Mode (Off);` and `pragma Validity_Checks ("F");`. The
layer passes values on to the entry points, which reject NaNs and
infinities with Bad_Parameter; with floating-point validity checks on
(`-gnatVf`, part of the `-gnatVa` of `amv.gpr` and of the tests) it would
raise Constraint_Error ("invalid data") itself first, at the call (`in`
parameters) or where it copies the value. GNAT 16.1 also applies a
`pragma Validity_Checks` at the top of a spec to every unit that withs
the spec, so the pragma of the kernel specs used to switch these checks
off in the Ada layer without saying so (and it still does in a user's
unit that withs an AMV package); the Ada layer no longer relies on that.

`make check` enforces this with `tools/shell_check` (loops, quantified
expressions, `Ada.Numerics`, real literals, arithmetic operators in the
bodies `src/amv-*.adb` outside the kernels and the legacy list; a file
`src/amv-*.ad?` outside the kernels without the `Validity_Checks` pragma).
A line that legitimately needs one carries a comment `--  SHELL: reason`.

### 9.4 Proofs

`make prove` runs gnatprove on `amv.gpr` (level 2 by default, raised per
unit in its `Prove` package) and fails on any unproved check or warning.
Proof status, trusted parts and known limits are listed in
`docs/PROOF.md`; update it with every kernel.
