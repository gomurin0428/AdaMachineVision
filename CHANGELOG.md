# Changelog

All notable changes to AdaMachineVision (AMV) are recorded in this file.
Versions follow [Semantic Versioning](https://semver.org/); before 1.0.0 a
minor version may break compatibility. Every incompatible change to the C
API raises `ks_abi_version` (`KS_ABI_VERSION`) and is listed here, as is
every change to what the proofs cover. The rules are in `docs/DESIGN.md`
section 9.1.

## [Unreleased]

### Changed

* Licence: AMV is dual-licensed, under the PolyForm Noncommercial
  License 1.0.0 for noncommercial use (`LICENSE.md`) or under a paid
  commercial licence (`LICENSING.md`).
* The C ABI is version 3: `ks_blob_run_params` has three fields at its
  end (`save_segmented_image`, `save_segmented_image_before_masking`,
  `save_segmented_image_before_morphology`) and is 2288 bytes. The
  stream format of `Ks_Blob` (and of `Ks_Blob_Tool`) grows with it.
* `Ks_Histogram_Tool` has a new component, `Region_Mode`, so its stream
  format changes.

### Fixed

* `ks_misc_hypot` (`AMV.Misc.Hypot`) and the length used inside the
  kernels dropped the smaller component when the larger was between
  2**(-500) and 2**(-400) and the smaller at most 2**(-500): the length
  of (2**(-500), 2**(-500)) came out as 2**(-500), 29 % short. The smaller
  component is now left out only next to one that is 2**100 times larger.
  The proved contracts (no run-time error, the result in [0, 2 max]) are
  unchanged; they never stated the accuracy, which the tests check.

### Added

* Blob: `Create_Blob_Image` (CogBlobResults.CreateBlobImage, with
  filtered, viewable and background) and `Create_Segmented_Image`
  (CreateSegmentedImage, with the stages FinalImage, BeforeMorphology and
  BeforeMasking and stretching), with the run parameters
  `Save_Segmented_Image`, `Save_Segmented_Image_Before_Masking` and
  `Save_Segmented_Image_Before_Morphology` (default False). C:
  `ks_blob_results_create_blob_image`,
  `ks_blob_results_create_segmented_image`. Every pixel of both images is
  proved to follow its rule.
* ToolGroup: `Run_Tool` (CogToolGroup.RunTool) for scripts, with the
  decisions in the kernel (`ks_tool_group_run_tool_begin`, `_end`).
* Histogram: `Region_Mode` (CogHistogram.RegionMode: AdjustMask, the
  default, PixelAlignedBoundingBox and AffineTransform); C:
  `ks_histogram_execute_affine` and `ks_pixel_region_bounding_box`.
* CNL Search: the AffineTransform region mode, for
  `Train_Region_Mode` (CogCNLSearchPattern.TrainRegionMode) and
  `Search_Region_Mode` (CogCNLSearchRunParams.SearchRegionMode), in the
  new kernel `AMV.Kernels.CNL_Search.Region_Modes`. An affine rectangle
  is resampled into an upright image by the affine transform tool's
  kernel with its default run parameters: training makes it the pattern
  (the train region must be an affine rectangle lying entirely in the
  train image, as in VisionPro; the origin is carried into the pattern by
  the resampling and the train image mask is resampled with it), and the
  search searches it and maps every location back into the input image's
  selected space. With any other search region, both search region modes
  search the region's bounding box, as VisionPro documents, so
  `ks_cnl_search_execute` now accepts `search_region_mode` 2 for its pixel
  region instead of rejecting it. C: `ks_cnl_search_pattern_train_affine`,
  `ks_cnl_search_execute_affine` (no record changes). Patterns trained in
  the new mode are streamed with the existing format code "KSCR". Proved:
  the trained pattern has exactly the resampled size, and the results of
  an affine search have the proved facts of `ks_cnl_search_execute`, with
  every window inside the resampled rectangle.

## [0.1.0] - 2026-11-12

The first release. The C ABI is version 2 (`ks_abi_version` returns 2).

### Core

* 2-D linear transforms with VisionPro's decompositions, and coordinate
  space trees with the root (`@`), pixel (`#`) and selected (`.`) spaces.
* 8-bit and 16-bit grey images and planar colour images that carry a
  coordinate space tree and share their pixels on assignment, as VisionPro
  images do; image files in PNM and BMP.
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
  convert and polar unwrap tools. IPOneImage and SobelEdge follow
  VisionPro's RegionMode, with PixelAlignedBoundingBox as the default.
* Dimensioning: the 22 measuring tools, the fitting tools and the 8 shape
  creation tools.
* CalibFix: N-point to N-point fits, fixtures, N-point and checkerboard
  calibration, including the nonlinear PerspectiveAndRadialWarp mode, the
  calibrated origin and handedness, and mapping points of a distorted
  input image.
* CNL Search: normalised correlation with trained patterns, train and
  search masks, partial matches, and TrainRegionMode with VisionPro's
  default AdjustMask.
* PMAlign: pattern location under rotation and scale with train and
  search masks and XYOverlap. The search is AMV's own method from public
  literature, not Cognex's PatMax or PatQuick.
* ToolGroup and ToolBlock.

`docs/API_MAPPING.md` lists the VisionPro counterpart of every name, each
departure, and what is not provided yet. Barcodes (ID) and OCR are not
part of this release.

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

[Unreleased]: https://github.com/gomurin0428/AdaMachineVision/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/gomurin0428/AdaMachineVision/releases/tag/v0.1.0
