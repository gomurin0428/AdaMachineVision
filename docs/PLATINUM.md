# SPARK Platinum plan

This is the plan for taking the kernels of AMV from their current level to
SPARK's Platinum level: a complete functional specification, written in
SPARK, for every subprogram of a kernel, with the code proved against it.
It is a target, not evidence that anything below is specified or proved.
The current state comes from the table of kernels in
[PROOF.md](PROOF.md).

## Where the kernels are now

Every kernel unit (81 units with the QR Code pass of #8: 45 public, 36
private children) is proved free of run-time errors and leaks at
`--level=2` (Silver), with about 38 500 checks. Many postconditions state
what the code computes (marked Gold in [PROOF.md](PROOF.md)), and each row
there lists what is only tested ("Not proved (tested)"). No specification
is written as code of its own: postconditions name functions that live
beside the code (`Copied_Pixel`, `Expected_Segment`, `Is_Codeword`), and
several of them restate the code.

| State | Kernels |
| --- | --- |
| Outputs nearly all stated | `Images`, `Pixel_Map`, `IP_Two_Image`, `Image_Convert`, `Copy_Region`, `Regions`, `Histogram` (the counts), `Blob.Tree`, `Tool_Group`, `Coordinate_Spaces` |
| Integer outputs, partly stated | `IP_One_Image` (running extrema, median, window sums, equalisation, block means), `Blob` (labels by connectivity, hole tree, the sort as a permutation, medians), `Sobel_Edge` (hysteresis), `Otsu` (the maximum of the criterion), `Image_File` (the pixels decoded, the bytes encoded), the decoding of the code reader (`Reed_Solomon`, `Data_Matrix`, `QR_Code`, `Linear`) |
| Floating-point results of a closed formula | `Numerics`, `Misc`, `Transforms`, `Shapes`, `Geometry` (but its fits), `Create_Shapes`, `Dimensioning`, `Image_Math`, `Image_Sampling`, `Affine_Transform`, `Polar_Unwrap`, `Image_Sharpness`, `Sobel_Edge` (magnitude and angle), `Caliper` (profiles and scores), the region modes |
| Numerical methods and searches | the fits of `Geometry`, `Dimensioning.Fitting`, `Find_Line`, `Find_Circle`, `Calib_Fix` (fits, solver, checkerboard), `NCC_Search`, `Shape_Match`, the finders of the code reader (`Profiles`, `Dark_Areas`, `Views`, `Data_Matrix.Finder`, `QR_Code.Finder`) |

Two things found while writing this plan:

* **No postcondition ever runs.** Each kernel unit starts with a
  `pragma Assertion_Policy` that checks preconditions only. A pragma in
  the source wins over `-gnata`, so the test build ignores the
  postconditions too: they are checked by the proof alone, and a test
  never compares the code with what its contract says.
* **The library does not compute what was proved, on arm64.** GNATprove
  proves floating-point code with each operation rounded on its own. At
  `-O2`, GNAT on arm64 fuses a multiplication and an addition into one
  instruction that rounds once (more than 150 such instructions in the
  kernel objects on a Mac); on x86_64 it does not. The fix is
  `-ffp-contract=off` in every build.

## What Platinum means here

* **Every output determined.** For each subprogram of a kernel, the
  postcondition fixes every output (`out` and `in out` parameters,
  function results, the status, the contents of a handle) from the
  inputs, in terms of specification functions. Where the code
  deliberately leaves something open, the contract says so, and that is
  the exception.
* **Specifications from definitions, not from the code.** Specification
  functions transcribe a definition and cite it: a standard (ISO/IEC
  18004 for QR Code, ISO/IEC 16022 for Data Matrix, the standards of the
  linear symbologies, the BMP and PNM formats), mathematics (arithmetic in
  GF(2^8), a convolution, an order statistic, connected components), or,
  for what AMV defines itself, the definition in its documentation, which
  the specification follows word for word. They do not call the code, and
  the code calls them only as ghost code.
* **Exact failure statuses.** When several checks fail, the status is the
  one the specification's order of checks gives.
* **The boundary stays where it is.** The Ada API and the C interface are
  thin layers over the kernels and are not part of this plan.

## Decisions

The maintainer approved all of these on 2026-11-19.

* **Specifications are ghost packages.** A root `AMV.Spec` and a child per
  area (`AMV.Spec.Reed_Solomon`, `AMV.Spec.QR_Code`, ...), ghost as a
  whole, depending only on `AMV.Spec.*`, `Interfaces` and the types the
  kernels share. A check in `make check` enforces that.
* **The specifications are tested too.** Every specification function is
  executable. A new area of `test_suite` runs the specifications alone on
  worked examples: those of a standard where they may be quoted, the test
  encoders of the code reader (`tests/amv_test_barcodes`,
  `tests/amv_test_data_matrix`, `tests/amv_test_qr_code`) for round trips,
  and small cases worked by hand. The proof ties the code to the
  specification; these tests tie the specification to its definition.
* **The tests check every contract.** The 81 pragmas move to configuration
  pragma files: the library build keeps checking preconditions only (no
  change at run time), the test build checks everything, so that every
  test also compares the code with its specification. The real-image
  tests, whose images are large, keep the library's policy.
* **The build computes what is proved.** `-ffp-contract=off` in every
  project, in a pull request of its own before the rest (#9).
* **Floating point is specified exactly.** A floating-point result is
  specified by the IEEE expression of its definition, with the order of
  the operations written in the specification, and the code computes
  that expression. How close it is to the real number stays tested, as
  now.
* **Numerical methods and searches: the method's conditions, not its
  iterate.** For a fit, a solver or a search, the specification states
  the conditions that define the result and every discrete outcome
  (counts, flags, sizes, the order of the results, which candidates a
  score keeps), and lists the iterate the method converges to as the
  exception, with its Gold bounds and its tests. Writing each method
  again as its own specification would restate the code.
* **No SPARKlib.** The specifications use arrays and ghost functions of
  their own and, where they need them, the big integers of Ada 2022, so
  that AMV keeps no library outside the toolchain.
* **The order with new work.** After the QR Code pull request, this plan
  is the main line, and a new kernel comes with complete specifications.

## The work, by area

| Area | Specification | Kernels | Effort | Main obstacle |
| --- | --- | --- | --- | --- |
| Pixel-exact tools | each tool's definition | `Images`, `Pixel_Map`, `IP_Two_Image`, `Image_Convert`, `Copy_Region`, the pointwise operators, flips and expansion of `IP_One_Image` | Low | Moving the existing functions into `AMV.Spec` without slowing the proofs |
| Window operators | order statistics, sums over a window | morphology, median, convolutions, equalisation and block means of `IP_One_Image`; `Histogram`'s statistics; `Otsu` | Medium | Running extrema and a running histogram against the window's definition |
| Code reader decoding | ISO/IEC 18004, ISO/IEC 16022, the linear symbologies, GF(2^8) | `Reed_Solomon`, `QR_Code`, `Data_Matrix`, `Linear` | Medium to high | The decoder's result as "the one codeword within half the check symbols"; segments of every mode |
| Image files | BMP, PNM | `Image_File` | Medium | Every header field and both directions |
| Regions and blobs | connected components, the hole tree | `Regions`, `Blob`, `Blob.Tree` | High | Labels by union-find against connectivity, a reachability argument |
| State | each tool's definition | `Tool_Group`, `Coordinate_Spaces`, `Caliper`'s scorers, the lists | Low | Breadth |
| Floating-point formulas | the formulas, in the order they are written | the third row of the table above | Medium to high | Exact equality needs the code to keep the specification's order of operations |
| Methods and searches | the defining conditions, as above | the fourth row of the table above | High | Deciding, method by method, what the conditions are |

## Phases

Each phase is one or more pull requests, with the proofs and the tests of
the specifications passing.

1. This document.
2. **The build.** `-ffp-contract=off` (#9).
3. **Infrastructure.** The configuration pragma files and the test build
   that checks every contract, the root `AMV.Spec`, the independence
   check, and a Platinum section in [PROOF.md](PROOF.md) that each later
   phase fills in. The test area of the specifications comes with the
   first of them, in phase 4.
4. **Pixel-exact tools**, to settle the patterns.
5. **Window operators.**
6. **Code reader decoding.**
7. **Image files.**
8. **Regions and blobs.**
9. **State.**
10. **Floating-point formulas.**
11. **Methods and searches.**
12. **Release**, with [PROOF.md](PROOF.md) stating the result unit by
    unit.

The order puts the cheap, pattern-setting work first, then the areas that
a standard defines, and the floating-point work last, when the patterns are
settled.

## Risks

* **Proof time.** A group of the proof takes up to about two hours from a
  cold cache on the hosted runners, and quantified postconditions over
  images are costly. Lemmas go in units of their own, which the proof
  cache keeps, and heavy subprograms are split.
* **Executable specifications in the tests.** A recursive count over the
  pixels of an image recurses once per pixel, and a postcondition over
  every pixel runs at every call. Such functions get a body that loops,
  proved equal to the definition, and the tests keep their images small.
* **Floating-point exactness.** An exact specification holds only for the
  operations written; a change of the order in the code, or of the
  compiler's contraction, breaks it. The build switch and the proof keep
  them together.
* **The specification can be wrong.** A wrong specification proved against
  matching code is the main way Platinum can mislead. That is why the
  specifications are executable and tested, and read against their
  definition in each pull request.
* **Size.** The kernel bodies hold about 74 000 lines. The phases are
  independent enough to stop after any of them with a coherent result.

## Mutation testing as a measure

With complete specifications, a mutant of a kernel that changes what the
code computes must fail its proof. After each phase, the mutants of the
units it covers that survive the tests and the proof should be equivalent
ones only; any other survivor marks a gap in a specification, and
[MUTATION.md](MUTATION.md) lists what is left. The reason "Proof not
finished" should disappear from those units, as their proofs are split.

## Open questions

* Whether the finders of the code reader should get reference
  specifications (the method written as predicates over the map of dark
  pixels), which would restate much of their code.
* The release number: the plan does not change the API, so 0.2.0 would
  mark the change of assurance.
