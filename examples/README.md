# Examples

| Program | What it shows |
|---|---|
| `quick_look.adb` | An image, a fixture coordinate space under the root, a point mapped from pixel space into the selected space, and writing a PGM file |
| `blob_inspection.adb` | Blob analysis: find washers, filter out dust and holes by area, find each washer's holes among its children and judge it by their number and size. Reads an image file given as an argument, or inspects a synthetic one |
| `align_and_measure.adb` | The usual gauging chain: PMAlign locates a part at any angle, the fixture tool puts the part's coordinate space on the image at the found pose, and calipers set once in part coordinates measure a slot and the plate length in every scene, with a tolerance check |
| `c/c_blob_inspection.c` | The blob inspection through the C API (`include/amv.h`): `adainit`, `ks_status` checks, run parameters, results and the destroy functions |

`example_support.ads` holds what the examples share: painting a part
given by a membership test at a pose, with anti-aliased edges (so that the
examples need no image files), and number formatting.

Build them with `make examples` (the Ada examples are listed in
`amv_examples.gpr`, the C one in `amv_c_examples.gpr`, `for Main use
(...)`) and run them from any directory, for example
`./build/bin/align_and_measure`. They write their images (PGM) into the
current directory.

`make run-examples` builds them, runs them in `build/example-run` and
checks their reports; CI runs it on every pull request.
