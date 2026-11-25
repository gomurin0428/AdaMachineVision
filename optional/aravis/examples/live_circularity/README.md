# Live circularity (Windows)

A Windows program that shows a GigE Vision camera live through
`AMV.GigE_Vision` and measures how round the largest object in view is,
frame by frame. It was written for checking the rims of ice cream cups seen
from above, but works for any single round object on a contrasting
background.

```sh
make build-live-circularity           # MSYS2 MINGW64, see ../../README.md
build/bin/live_circularity.exe        # or: live_circularity.exe 192.168.1.20
```

The Aravis and GLib DLLs must be on `PATH` or next to the `.exe`. A first
command-line argument is taken as the camera's address and connected at
once. Windows Defender Firewall must let the camera's image stream through
(see "On Windows" in `../../README.md`).

## Window

* **Camera / Connect**: the camera's IPv4 address or Aravis device ID.
* **Exposure**: the slider (log scale) or a value in milliseconds typed
  in the box and applied with **Set** or Enter; the camera's own value
  (it may round) is read back and shown. **Gain** and **Auto exposure**
  set the camera's Gain and ExposureAuto. All go through
  `AMV.GigE_Vision.Settings`, also while the view is live.
* **Threshold**: Otsu's threshold (**Automatic threshold**) or a fixed
  grey level. **Object lighter / darker than background** picks which
  side of the threshold the object is on; blobs smaller than **Min. area**
  are ignored.
* The image shows the measured outer edge (green) and the centre of the
  circle fitted to it (red). The panel shows the roundness, diameter,
  area, perimeter and centre.
* **Ref. dia (mm) / Calibrate**: with the reference cup fully in view,
  **Calibrate** sets the scale so that the measured diameter equals the
  reference diameter; lengths and areas are then shown in millimetres.
  The scale is saved in `calibration.txt` in the working directory and
  read at start. See "Calibration" below.
* **Capture** works while the view is live: it takes the newest complete
  frame, measures it and saves, in `captures` under the working directory,
  the frame (`cup_YYYYMMDD_HHMMSS_cc.bmp`, 8-bit grey), the picture with
  the measurement drawn on it (`..._result.bmp`, 24-bit) and one line of
  `circularity_log.csv`: time, image, found, the measures (with the
  circularity, which the window does not show), the radii, clipped, the
  exposure (µs), the gain, the threshold, the scale and the diameter,
  area and perimeter in millimetres (empty before calibration). An older
  log's header is rewritten to the new columns. The live view goes on.

## Measures

`Circularity_Measure` thresholds the frame (Otsu's threshold, or the fixed
one) and runs the AMV blob tool only to find the object: the largest blob
of at least the minimum area, preferring one that does not touch the
image border. The outer edge is then found along 720 rays from the
object's centre: each ray takes the radius where it first enters the
object coming in from outside, with the threshold crossing interpolated
between grey values. So what lies inside the edge does not matter: the
inside of a cup, its shadows, or a seam in the rim that breaks the blob
in two. A ray whose radius is more than 3 % (at least 4 px) off the median
of its 15 neighbours, as where a seam lets it run past the rim, takes that
median, and the radii are averaged over 5 rays (2.5 degrees). The rays
start from the centre of the blob's box and again from the centre of the
circle fitted to that first edge. The object must be star-shaped from its
centre, and features narrower than about 3 degrees of the rim are not
seen.

| Value | Meaning |
|---|---|
| Roundness | smallest / largest distance of the edge from the centre of the least-squares circle (1 for a circle) |
| Circularity | 4π × area / perimeter² of the edge (1 for a circle); in the CSV only |
| Diameter | diameter of the least-squares (Kåsa) circle, in pixels |
| Area, Perimeter, Center | area inside the edge, its length, the circle's centre |

On synthetic images, circularity / roundness (exact in brackets):

| Shape | Circularity | Roundness |
|---|---|---|
| circle, r = 200 px | 0.9987 (1) | 0.997 (1) |
| ellipse 200 x 190 px | 0.9975 (0.9993) | 0.948 (0.95) |
| ellipse 200 x 160 px | 0.9800 (0.9817) | 0.798 (0.80) |
| ellipse 280 x 100 px | 0.693 (0.694) | 0.357 (0.357) |
| cup ring with a dark half inside and a seam, 200 x 180 px | 0.994 | 0.898 (0.90) |

The circle's diameter comes out at 400.01 px for 400. The circularity
hardly moves for slightly oval shapes, which is why the window shows the
roundness only: a paper cup read 0.983 as it was and 0.95 when lightly
squeezed.

## Calibration

The default reference, 76.0 mm, is the outer rim diameter of a
Haagen-Dazs mini cup (110 ml) as sellers list it (7.6 cm on Amazon.co.jp,
about 7.5 cm in a review); it is not a maker's figure, so for exact
millimetres measure your own cup's rim with calipers and type that value
before pressing **Calibrate**. Calibrate with the cup in its normal,
unsqueezed shape.

One scale holds only for edges at the same distance from the camera: the
rim of another cup of the same kind standing in the same place. A cup
that is taller, shorter or tilted, or far from the image centre (lens
distortion is not corrected), is measured with a small error.

The camera and the measurement run on the window's thread: each frame is
measured before the next is taken (about 150 ms for 1280 x 1024 pixels), so
the view updates a few times a second. Frames queued in the meantime are
skipped, so the view always shows the newest one.
