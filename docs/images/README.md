# Result pictures

The pictures the READMEs show. Each one was written by an example
program: the input image with what AMV's tools found drawn on it
(`examples/example_draw.ads` does the drawing). What the pictures show
is explained in [`examples/README.md`](../../examples/README.md) and
[`examples/real_images/README.md`](../../examples/real_images/README.md).

```
make pictures    # run the examples and write the pictures here again
```

`make pictures` runs every example (`make run-examples`,
`make run-real-image-examples`) and converts the BMP pictures they write
in `build/example-run` to PNG (`tools/update_pictures.sh`; ImageMagick,
or `sips` on macOS). Run it when an example's picture changes, and commit
the result.

## Sources and licences

Thirteen of the pictures are photographs from open collections with
AMV's results drawn on them. The photographs keep their own licences;
AMV's licences ([`LICENSING.md`](../../LICENSING.md)) cover only what
the examples drew. The two other pictures are images the examples paint
themselves.

| Picture | Written by | Image underneath | Licence of that image | Changes |
|---|---|---|---|---|
| `blob_result.png` | `examples/blob_inspection.adb` | painted by the example | AMV's | — |
| `align_result.png` | `examples/align_and_measure.adb` | painted by the example | AMV's | — |
| `coin_count_steps.png`, `coin_count_result.png` | `examples/real_images/coin_count.adb` | `coins.png` of scikit-image `data`: "Greek coins from Pompeii", Brooklyn Museum | no known copyright restrictions | shown as it is, after a top-hat, and enlarged twice; outlines, numbers and captions drawn on it |
| `pcb_gauging_*.png` (six) | `examples/real_images/pcb_gauging.adb` | VisA, category `pcb1`, normal images 0000, 0100, 0250, 0400, 0550, 0700 and 0900 | CC BY 4.0 | converted to grey; reduced to a half or a quarter, or a part enlarged; regions, features, circles, lines, edge points, labels and captions drawn on it |
| `candle_rims_*.png` (four) | `examples/real_images/candle_rims.adb` | VisA, category `candle`, normal images 0000 and 0450 | CC BY 4.0 | converted to grey; reduced to a half, or a part enlarged; regions, features, circles, edge points, labels and captions drawn on it |
| `nuclei_count_result.png` | `examples/real_images/nuclei_count.adb` | BBBC039v1, field `IXMtest_B05_s5` (`eval_07` here) and its hand-drawn mask | CC0 1.0 | reduced to 8 bits, grey levels multiplied by 3, enlarged 1.5 times; outlines, crosses and captions drawn on it |

* **VisA**: the Visual Anomaly dataset, by Yang Zou, Jongheon Jeong,
  Latha Pemula, Dongqing Zhang and Onkar Dabeer ("SPot-the-Difference
  Self-Supervised Pre-training for Anomaly Detection and Segmentation",
  ECCV 2022), Amazon, <https://github.com/amazon-science/spot-diff>,
  licensed under
  [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). The pictures
  named above are adapted from its images as the table says.
* **BBBC039v1**: "Nuclei of U2OS cells in a chemical screen", from the
  Broad Bioimage Benchmark Collection (Ljosa et al., Nature Methods
  2012), <https://bbbc.broadinstitute.org/BBBC039>, dedicated to the
  public domain under
  [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).
* **coins**: `coins.png` of
  [scikit-image](https://github.com/scikit-image/scikit-image)'s `data`,
  a photograph of Greek coins from Pompeii in the Brooklyn Museum's
  collection, with no known copyright restrictions.

The photographs themselves are not in this repository:
`make fetch-real-images` downloads them, checked by SHA-256
(`tests/real_images/README.md`).
