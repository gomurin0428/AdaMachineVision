# Changelog

All notable changes to AdaMachineVision (AMV) are recorded in this file.
Versions follow [Semantic Versioning](https://semver.org/); before 1.0.0 a
minor version may break compatibility. Every incompatible change to the C
API raises `ks_abi_version` (`KS_ABI_VERSION`) and is listed here, as is
every change to what the proofs cover. The rules are in `docs/DESIGN.md`
section 9.1.

## [Unreleased]

## [0.2.0] - 2026-11-27

The C ABI is version 3 (`ks_abi_version` returns 3). New since 0.1.0: the
Code Reader (linear barcodes, Data Matrix, QR Code), the optional GigE
Vision camera adapter, and the optional AMV Flow engine with its no-code
editor and operator screen (`optional/`).

Code written for 0.1.0 has to change: C callers must be rebuilt for ABI
version 3 (`ks_blob_run_params` has grown), the pattern location and
correlation search tools are now Shape Match and NCC Search in every
public name (the earlier names are gone), and some stream formats have
changed (below). AMV is now dual-licensed, and it needs GNAT 16 or later.

### Changed

* The toolchain: GNAT 16 or later (`alire.toml`: `gnat >= 16`; GNAT 14
  is no longer supported).
* Proofs: `ks_image_8_grey_create` states exactly when it fails with
  Bad_Parameter: when the width or the height is less than 1, or the
  image would have more than `Max_Pixels` pixels.
  The optional GigE Vision adapter has proofs of its own, outside the
  library's (`make prove-aravis`: `AMV.Spec.GigE_Vision` and the
  adapter's production engine, `docs/PROOF.md`).
* The tests check the contracts of the kernels: every precondition,
  postcondition, predicate and piece of ghost code runs in `test_suite`,
  so that each test also compares the code with its contracts. The
  policies of the contracts are two configuration pragma files instead of
  a pragma at the top of every kernel unit: `contracts.adc` for the
  library (preconditions only, as before) and `tests/contracts.adc` for
  the tests; loop invariants and assertions are left to the proofs. The
  same tests run a second time with the library's policy
  (`test_suite_library`, `amv_tests_library.gpr`), with the timings and
  the NaNs that the proofs assume away; the real-image tests run with it
  too. What would be too slow to check at every call is at the assertion
  level `Static`, proved only: a postcondition of the flood fill of the
  Sobel tool, and the parts of the postconditions of the image kernel's
  pixel and row setters that compare the whole image; the rest of those
  is at the level `Tested`, which the tests check. `make check` rejects a policy
  pragma in a unit. The first step of `docs/PLATINUM.md`, with the root of
  the specifications, `AMV.Spec`.
* The two-image tools are specified completely (Platinum,
  `docs/PLATINUM.md`): `AMV.Spec.IP_Two_Image` transcribes their
  formulas from the documentation, and the postconditions of
  `ks_ip_two_image_*_execute` fix the output and the failure code, in
  the documented order of the checks (`Input_Failure`), from the inputs;
  only the text of a message and Out_Of_Memory stay open. The checks of
  an input image (`Image_Sampling.Check_Image`) state their failure code
  exactly. A new area of `test_suite`, `Test_Spec`, runs the
  specifications on their own.
* The pixel map tool and the image convert tool are specified completely
  in the same way (`AMV.Spec.Pixel_Map`, `AMV.Spec.Image_Convert`), but
  the mode `INTENSITY_FROM_WEIGHTED_RGB`, a formula in floating point. The
  image kernel states what an input image the tools take is
  (`Usable_Image`) and the failure of its check (`Input_Image_Failure`),
  which the checks of the filters (`Filter_Inputs`) and of the sampling
  now state exactly.

* Licence: AMV is dual-licensed, under the PolyForm Noncommercial
  License 1.0.0 for noncommercial use (`LICENSE.md`) or under a paid
  commercial licence (`LICENSING.md`).
* The C ABI is version 3: `ks_blob_run_params` has three fields at its
  end (`save_segmented_image`, `save_segmented_image_before_masking`,
  `save_segmented_image_before_morphology`) and is 2288 bytes. The
  stream format of `Ks_Blob` (and of `Ks_Blob_Tool`) grows with it.
* `Ks_Histogram_Tool` has a new component, `Region_Mode`, so its stream
  format changes.
* The message for a code that is not one of an enumeration's values
  names the family of C constants (`GetMedianX: Axis must be a
  KS_BLOB_AXIS_* value (0 .. 4)`); eight families of constants are named
  this way.
* `docs/API_MAPPING.md` is removed. The spec of each package documents
  the tool, its defaults and what it does not support.
* The pattern location tool and the correlation search tool are named
  Shape Match and NCC Search, in every public name: `AMV.Shape_Match`
  (`Ks_Shape_Match_*`, `ks_shape_match_*`, `KS_SHAPE_MATCH_*`,
  `include/amv_shape_match.h`) and `AMV.NCC_Search` (`Ks_NCC_Search_*`,
  `ks_ncc_search_*`, `KS_NCC_SEARCH_*`, `include/amv_ncc_search.h`), with
  the kernels `AMV.Kernels.Shape_Match` and `AMV.Kernels.NCC_Search`. The
  algorithms of Shape Match are `Edge_Fit` (0), `Grid_Search` (1) and, as
  code 2, `Edge_Fit_And_Grid_Search` for training and `Best_Trained` for
  a run; those of NCC Search are `Linear_Search` (1) and `Pyramid_Search`
  (2). The earlier names are not kept: code that uses the two tools has
  to be changed to the new names. The records, the codes, the stream
  formats and what the tools compute are the same, so the ABI version
  stays 3. The algorithm codes that were declared only to be rejected are
  no longer declared; they fail with a bad parameter as before, like any
  other code that is not listed. The messages of both tools spell the
  new names (`ShapeMatch: out of memory`, `RunParams.RunAlgorithm must
  be EdgeFit, GridSearch or BestTrained`).

### Fixed

* The builds did not compute in floating point what the proofs proved, on
  arm64: at `-O2`, GCC fused a multiplication and an addition into one
  instruction that rounds once (more than 150 such instructions in the
  objects of the kernels on a Mac), while gnatprove takes every operation
  to be rounded on its own. Every project now compiles with
  `-ffp-contract=off`
  (`docs/PROOF.md`, Assumptions and limits). On x86_64, GCC fuses nothing
  without a target that has the instruction, and nothing changes there.
* `ks_misc_hypot` (`AMV.Misc.Hypot`) and the length used inside the
  kernels dropped the smaller component when the larger was between
  2**(-500) and 2**(-400) and the smaller at most 2**(-500): the length
  of (2**(-500), 2**(-500)) came out as 2**(-500), 29 % short. The smaller
  component is now left out only next to one that is 2**100 times larger.
  The proved contracts (no run-time error, the result in [0, 2 max]) are
  unchanged; they never stated the accuracy, which the tests check.

### Added

* Optional components in `optional/`, outside the library (`amv.gpr`),
  each with its own README: a GigE Vision camera adapter on Aravis 0.8
  (`optional/aravis`); the AMV Flow engine, which runs the tools as a
  graph of nodes saved as a file, with the `amv_flow` command-line
  runner and a C API of its own (`optional/flow`, `amv_flow.h`, with its
  own ABI version); and its no-code editor and operator screen in Java
  (`optional/flow_editor`), packaged with jpackage on Windows only so
  far.
* Blob: `Create_Blob_Image` (with filtered, viewable and background) and
  `Create_Segmented_Image` (with the stages FinalImage, BeforeMorphology
  and BeforeMasking and stretching), with the run parameters
  `Save_Segmented_Image`, `Save_Segmented_Image_Before_Masking` and
  `Save_Segmented_Image_Before_Morphology` (default False). C:
  `ks_blob_results_create_blob_image`,
  `ks_blob_results_create_segmented_image`. Every pixel of both images is
  proved to follow its rule.
* ToolGroup: `Run_Tool` for scripts, with the decisions in the kernel
  (`ks_tool_group_run_tool_begin`, `_end`).
* Histogram: `Region_Mode` (AdjustMask, the default,
  PixelAlignedBoundingBox and AffineTransform); C:
  `ks_histogram_execute_affine` and `ks_pixel_region_bounding_box`.
* NCC Search: the AffineTransform region mode, for `Train_Region_Mode`
  and `Search_Region_Mode`, in the new kernel
  `AMV.Kernels.NCC_Search.Region_Modes`. An affine rectangle is
  resampled into an upright image by the affine transform tool's kernel
  with its default run parameters: training makes it the pattern (the
  train region must be an affine rectangle lying entirely in the train
  image; the origin is carried into the pattern by the resampling and
  the train image mask is resampled with it), and the search searches it
  and maps every location back into the input image's selected space.
  With any other search region, both search region modes search the
  region's bounding box, so `ks_ncc_search_execute` now accepts
  `search_region_mode` 2 for its pixel region instead of rejecting it.
  C: `ks_ncc_search_pattern_train_affine`,
  `ks_ncc_search_execute_affine` (no record changes). Patterns trained in
  the new mode are streamed with the existing format code "KSCR". Proved:
  the trained pattern has exactly the resampled size, and the results of
  an affine search have the proved facts of `ks_ncc_search_execute`, with
  every window inside the resampled rectangle.
* Code Reader: a new tool, `AMV.Code_Reader` (`Ks_Code_Reader_Tool`),
  reads the linear barcodes of an 8-bit grey image: EAN-13, EAN-8,
  UPC-A, UPC-E, Code 128, Code 39 and Interleaved 2 of 5 (ITF), at any
  orientation and any number of them per image. A result has the text,
  the symbology, the centre, the angle, the four corners and the number
  of scan lines that read the symbol; the check digits are verified
  (those of Code 39 and ITF when asked for). C:
  `include/amv_code_reader.h` (`ks_code_reader_run_params_default`,
  `ks_code_reader_execute`, `ks_code_reader_results_destroy`,
  `ks_code_reader_results_count`, `ks_code_reader_results_item`); no
  existing record or function changes, so the ABI version stays 3. The
  new kernel `AMV.Kernels.Code_Reader` (with the private children
  `Linear`, the decoders, and `Profiles`, the scan lines and their
  edges) adds 1281 checks, all proved: no run-time error for any image,
  region and parameters, no memory leak, and every result a symbology
  with a text of 1 to 255 characters. That the text is the one of the
  symbol is tested, not proved: on generated symbols of every symbology
  (turned, blurred, with bars that gained or lost width, at low
  contrast, shaded, noisy and sharpened) and on the 487 barcode
  photographs of the ZXing project's tests (Apache-2.0), of which the
  default run parameters read 382, with no wrong text
  (`tests/real_images/README.md` has the table and the known failures).
  Not read: Extended Code 39, symbols without a light margin inside the
  image, and modules narrower than 1.5 pixels.
* Code Reader: Data Matrix. With `KS_CODE_READER_SYMBOLOGY_DATA_MATRIX`
  (128) among the symbologies of the run parameters, the tool also
  reads the Data Matrix symbols (ECC 200) of the image: the 24 square
  sizes (10 x 10 to 144 x 144 modules), the 6 rectangular ones and the
  18 of the rectangular extension (DMRE, ISO/IEC 21471: 8 x 48 to
  26 x 64 modules), at any orientation, seen at an angle or mirrored,
  and any number of them per image. A symbol is found from the dark
  area with its two solid sides (the "L"), its modules are looked up
  through the perspective mapping of its four corners, and its
  codewords are corrected (Reed-Solomon) and decoded (the ASCII, C40,
  Text, X12, EDIFACT and Base 256 encodations). A result has the text,
  the four corners of the symbol as it is printed, the centre and the
  angle; its `num_scan_lines` is 0. A text can have up to 3125
  characters: a result holds the first 255 and the whole length, and
  the new `ks_code_reader_results_text` gives all of it. Data Matrix is
  not among the default symbologies: its symbols are looked for in a
  pass of its own over the image. C: `symbologies` is a sum in 1 .. 255
  (1 .. 127 before), with the new constants
  `KS_CODE_READER_SYMBOLOGY_DATA_MATRIX`, `KS_CODE_READER_SYMBOLOGY_ALL`
  and `KS_CODE_READER_MAX_MATRIX_TEXT_LENGTH`; the `length` of a result
  exceeds 255 only for a Data Matrix symbol, which a caller has to ask
  for; no record and no existing function changes, so the ABI version
  stays 3. Ada: `Data_Matrix` in `AMV.Code_Reader.Symbology`,
  `All_Symbologies` and `Text`. The new children of the kernel,
  `Dark_Areas` (the dark pixels, the outlines of the dark areas and
  their convex hulls), `Data_Matrix.Finder` (the corners and the
  modules), `Data_Matrix` (the codewords and the text) and
  `Reed_Solomon`, and the Data Matrix pass of the kernel itself add
  1710 checks, all proved: no run-time error for any image,
  region and parameters, no memory leak, every result a symbology with
  its text (1 to 255 characters for a linear barcode, 1 to 7089 for a
  two-dimensional symbol, all of them in the results), and a word that
  `Reed_Solomon` has corrected is a codeword of its code. That a symbol
  is found and that the text is the one printed is tested, not proved:
  on generated symbols of every size (turned, mirrored, seen at an
  angle, blurred, noisy, at low contrast, shaded and damaged, with
  modules of 3 to 20 pixels) and on the 59 Data Matrix photographs of
  the ZXing project's tests (Apache-2.0). The default run parameters
  read all 59, but the part that finds a symbol was written while
  looking at these same photographs, so this number records what is
  read and is not an evaluation (`tests/real_images/README.md`). Not
  read: the older Data Matrix ECC 000 to 140, symbols that are light on
  dark or made of separate dots, symbols without a light margin of two
  pixels, and modules smaller than two pixels.
* Code Reader: QR Code. With `KS_CODE_READER_SYMBOLOGY_QR_CODE` (256)
  among the symbologies of the run parameters, the tool also reads the
  QR Code symbols (Model 2) of the image, in the pass that reads Data
  Matrix: the versions 1 to 40 (21 x 21 to 177 x 177 modules) at the
  four error correction levels, at any orientation, seen at an angle
  or mirrored, and any number of them per image. A symbol is found
  from its three finder patterns (dark and light in the proportions
  1 : 1 : 3 : 1 : 1 along a row, a column and the two diagonals). They
  give the version and, with the alignment pattern nearest to the
  fourth corner, the place of every module in perspective; the format
  and the version information are read, and the codewords are
  corrected (Reed-Solomon) and decoded (the numeric, alphanumeric, byte
  and Kanji modes, with FNC1; ECI and structured append are passed
  over). A result has the text, the four corners of the symbol as it
  is printed, the centre and the angle; its `num_scan_lines` is 0. The
  text is the bytes as the symbol encodes them (no character set is
  applied; a Kanji character is the two bytes of its Shift JIS code),
  up to 7089 of them, held and given like the text of a Data Matrix
  symbol. QR Code is not among the default symbologies. C:
  `symbologies` is a sum in 1 .. 511 (1 .. 255 before), with the new
  constant `KS_CODE_READER_SYMBOLOGY_QR_CODE`, and
  `KS_CODE_READER_SYMBOLOGY_ALL` is 511; no record and no function
  changes, so the ABI version stays 3. Ada: `QR_Code` in
  `AMV.Code_Reader.Symbology`. The new children of the kernel,
  `QR_Code` (the codewords and the text), `QR_Code.Finder` (the finder
  patterns and the modules) and `Views` (what the two-dimensional
  symbologies share: the dark pixel at a point and the perspective
  mapping, which the Data Matrix finder now takes from it), and the QR
  Code pass of the kernel itself bring the code reader kernel from
  2991 to 3964 checks, all proved: no run-time error for any image,
  region and parameters, no memory leak, and every result a symbology
  with its text. That a symbol is found and that the text is the one
  printed is tested, not proved: on symbols painted by an encoder of
  the tests' own (every version, level and mask, modules of 2 to 20
  pixels, turned, mirrored, seen at an angle, blurred, noisy, at low
  contrast, shaded and damaged) and on the 179 QR Code photographs of
  the ZXing project's tests (Apache-2.0). These were split in two by
  the number in their name before any of them was opened. The reader
  was made on the 90 odd-numbered ones, of which it reads 81, and
  frozen; the 89 even-numbered ones were then run once, and 80 are
  read. No wrong text is reported. The two halves show the same
  symbols in other photographs, so the second figure is of photographs
  not seen before, not of other kinds of symbols
  (`tests/real_images/README.md` has the table and the 18 known
  failures: symbols on cloth that is not flat, a blurred symbol with
  modules of about three pixels, a symbol drawn as a picture and one
  in the Hanzi mode of GB/T 18284). Not read: Micro QR Code, QR Code
  Model 1, the modes that ISO/IEC 18004 does not define, symbols that
  are light on dark, symbols with a finder pattern that is covered or
  has no light pixels around it, symbols on a surface that is not
  flat, and modules smaller than two pixels (three where the image is
  not sharp).
* Code Reader: in the pass for the two-dimensional symbols, a block of
  8 by 8 pixels has dark and light pixels when its lightest and its
  darkest pixel differ by twice `contrast_threshold` (24 grey levels
  with the default; it was the threshold itself, in the entry of Data
  Matrix above). The lightest and the darkest of 64 pixels differ by
  the whole swing of the noise, so the blocks in the middle of a large
  dark area were given light pixels. A faint Data Matrix symbol needs
  twice the contrast that it needed: one of 30 grey levels is read
  with a threshold of up to 15. The 59 Data Matrix photographs are
  read as before.
* Real-image tests: `tools/fetch_real_images.sh` takes three more kinds
  of manifest entries (a PNG converted without loss by the new
  `tools/png_to_bmp.py`, a text file, and a text file whose text is
  also written in Shift JIS by the new `tools/text_to_sjis.py`),
  downloads in parallel, and the CI keeps the downloads from run to
  run.
* Mutation testing: `make mutation` and `make mutation-diff` run
  AdaMutant (https://github.com/gomurin0428/AdaMutant, `adamutant.toml`)
  on the bodies of the library: every small change of a body (a mutant)
  is run with the areas of `test_suite` that execute it (`test_suite
  <area> ...` runs only the areas named) and, where they pass, with the
  proof of its unit (`tools/mutant_prove.sh`). The workflow Mutation does
  this for the bodies that a pull request changes, one job for each, and
  keeps the report. On the code reader it found what the tests did not
  check: 390 of the 1076 mutants of the QR Code finder survived the
  tests, which paint whole and even symbols. Three new test units check
  the finder on maps made pixel by pixel, at the limits of its search
  for finder patterns, of the placing of a symbol on three of them and
  of the sampling of its modules (`tests/test_code_reader_qr_patterns.adb`,
  `test_code_reader_qr_placing.adb`, `test_code_reader_qr_sampling.adb`).
  The tests of the kernel got symbols whose dark modules are a pixel
  thinner on each side (their finder patterns give a version one or two
  above theirs), the 16 pairs that a corner is tried with, and the
  exact number of symbols that the 256 finder patterns of a run give;
  those of the decoder, a designator of an extended channel
  interpretation whose first codeword of three is above 192; those of
  the finder patterns, a symbol in perspective on which two rows with
  modules more than a pixel apart in width are one pattern; those of
  the sampling, a placing whose widths change across the symbol and not
  down it, and two symbols in perspective on which it matters which of
  the best places of the alignment pattern is taken and which places
  around it the mean of its middle takes. The symbols in perspective
  were found by a search.
  `docs/MUTATION.md` lists the mutants that survive the tests and the
  proof with the reason (`docs/DESIGN.md` 8).
* Examples: every example writes a picture of its results, the input
  image with what the tools found drawn on it (`examples/example_draw`,
  for the examples only), and four new examples run on photographs
  (`examples/real_images`: `coin_count`, `pcb_gauging`, `candle_rims`,
  `nuclei_count`; `make run-real-image-examples`). The READMEs show the
  pictures (`docs/images`, written again by `make pictures`).

## [0.1.0] - 2026-11-12

The first release. The C ABI is version 2 (`ks_abi_version` returns 2).
It predates the history of this repository, so it has no tag. This
section calls its correlation search and pattern location tools by their
names in 0.2.0, NCC Search and Shape Match; 0.1.0 named them otherwise.

### Core

* 2-D linear transforms, also decomposed into scaling, aspect, rotation
  and skew, and coordinate space trees with the root (`@`), pixel (`#`)
  and selected (`.`) spaces.
* 8-bit and 16-bit grey images and planar colour images that carry a
  coordinate space tree and share their pixels on assignment; image
  files in PNM and BMP.
* Shapes (point markers, lines, segments, rectangles, affine rectangles,
  circles, ellipses, polygons, circular arcs, annulus sections),
  rasterised into pixel regions in any coordinate space; regions
  restricted by masks.
* Floating point image maths, geometry fitting (lines, circles) and the
  tool framework (`Ks_Tool`, `Run`, `Run_Status`,
  `Ks_Tool_Result_Constants`), where a tool never propagates an exception
  out of `Run`.

### Vision tools

* Blob: hard thresholds (fixed, relative, dynamic) and soft thresholds,
  connectivity and the blob tree, measures, filters and sorting,
  ExtremaAngle and its measures, medians.
* Caliper, Find Line and Find Circle.
* Image processing: Histogram (with the minimum within-group variance
  threshold), PixelMap, SobelEdge, Sharpness; the IP one-image tool and
  its operators; the affine transform, copy region, two-image, image
  convert and polar unwrap tools. IPOneImage and SobelEdge have a
  RegionMode, with PixelAlignedBoundingBox as the default.
* Dimensioning: the 22 measuring tools, the fitting tools and the 8 shape
  creation tools.
* CalibFix: N-point to N-point fits, fixtures, N-point and checkerboard
  calibration, including the nonlinear PerspectiveAndRadialWarp mode, the
  calibrated origin and handedness, and mapping points of a distorted
  input image.
* NCC Search: normalised correlation with trained patterns, train and
  search masks, partial matches, and TrainRegionMode with the default
  AdjustMask.
* Shape Match: pattern location under rotation and scale with train and
  search masks and XYOverlap. The search is AMV's own method from public
  literature.
* ToolGroup and ToolBlock.

Barcodes (ID) and OCR are not part of this release.

### C API

* Every kernel entry point is exported with the C calling convention and
  declared in `include/amv.h` and the headers it includes. Records grow
  only at their end; `ks_abi_version` reports the layout version.

### Proofs and tests

* All logic lives in SPARK kernels: 34514 checks, all proved by gnatprove
  16.1, with no `pragma Assume` and no justified checks. `docs/PROOF.md`
  lists the functional properties proved and what is trusted without
  proof.
* `make test`: 26487 Ada checks and 914 C checks, including a robustness
  sweep of the whole Ada API with extreme values (no exception other than
  AMV's own).
* `make test-real-images`: tests on public images (OpenCV and
  scikit-image samples, VisA, BBBC006, BBBC039), fetched at test
  time and pinned by SHA-256, with separate tuning and evaluation sets.
* Example programs (`examples/`) in Ada and C, run and checked by
  `make run-examples`.

[Unreleased]: https://github.com/gomurin0428/AdaMachineVision/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/gomurin0428/AdaMachineVision/releases/tag/v0.2.0
