# Optional Aravis GigE Vision adapter

`AMV.GigE_Vision` is an optional, non-SPARK Ada adapter for GigE Vision
cameras. Its implementation and C shim live outside `src/`; it does not
change the default `amv.gpr` build, the SPARK kernels, or `include/amv.h`.
The adapter targets Linux and Windows. Aravis 0.8.20 is the minimum tested
Linux version; Windows CI pins Aravis 0.8.33. It accepts packed Mono8
payloads and the four packed 8-bit Bayer formats (BayerGR8, BayerRG8,
BayerGB8, BayerBG8), which it converts to grey; other pixel formats are
rejected. Exposure and gain can be set through `AMV.GigE_Vision.Settings`;
there is no pixel-format control: set the camera's pixel format with its own
tools before `Open`.

## Dependency and build

On Linux, install GNAT/gprbuild as for AMV, plus Aravis 0.8.20-or-newer
development files, `libusb-1.0-0-dev`, and `pkg-config` (for example,
`libaravis-dev` on Debian or Ubuntu). Aravis is an independent backend
dependency, licensed LGPL-2.1-or-later; its licence does not change AMV's
licensing. The default core build and tests do not require Aravis.

```sh
make build-aravis
make test-aravis
make example-aravis CAMERA_ID=192.168.1.20 IMAGE=capture.pgm
```

### Windows (MSYS2 MINGW64)

Use MINGW64 for the GNAT FSF Windows ABI. Windows CI uses GNAT 16.1.0,
gprbuild 26.0.1, and builds the pinned Aravis 0.8.33 release with only the
GigE/core dependencies enabled. The release tag resolves to commit
`99081fbda9e820a171d2aaccea0bc95ba5f8c37b`; the source archive is verified
against SHA-256
`3c4409a12ea70bba4de25e5b08c777112de854bc801896594f2cb6f8c2bd6fbc`.

Install Alire 2.1.1 for Windows and, in an MSYS2 MINGW64 shell, install:

```sh
pacman -S --needed make unzip mingw-w64-x86_64-toolchain \
  mingw-w64-x86_64-gcc mingw-w64-x86_64-meson mingw-w64-x86_64-ninja \
  mingw-w64-x86_64-pkgconf mingw-w64-x86_64-glib2 \
  mingw-w64-x86_64-libxml2 mingw-w64-x86_64-zlib
alr -n toolchain --select gnat_native=16.1.0 gprbuild=26.0.1
```

Run Meson and Ninja directly in the MINGW64 shell so Aravis uses the MSYS2
MINGW64 GCC/C++ compiler and dependencies; the GNAT FSF toolchain uses that
same MINGW64 ABI/CRT.

Build and install Aravis from its pinned release archive:

```sh
mkdir -p build/deps
cd build/deps
curl -fsSL -o aravis-0.8.33.tar.xz \
  https://github.com/AravisProject/aravis/releases/download/0.8.33/aravis-0.8.33.tar.xz
printf '%s  %s\n' \
  3c4409a12ea70bba4de25e5b08c777112de854bc801896594f2cb6f8c2bd6fbc \
  aravis-0.8.33.tar.xz | sha256sum -c -
tar -xf aravis-0.8.33.tar.xz
cd aravis-0.8.33
mingw_prefix=$(cygpath -m "$MINGW_PREFIX")
CC=gcc CXX=g++ meson setup build \
  --prefix="$mingw_prefix" --libdir=lib --buildtype=plain \
  -Ddocumentation=disabled -Dgst-plugin=disabled \
  -Dintrospection=disabled -Dusb=disabled -Dpacket-socket=disabled \
  -Dviewer=disabled -Dtests=false
ninja -C build install
cd ../../..
export PATH="$MINGW_PREFIX/bin:$PATH"
alr -n exec -- make test-aravis
```

The test target links with `pkg-config --cflags/--libs aravis-0.8`; the
MINGW64 `bin` directory must remain on `PATH` so the Aravis and GLib DLLs load.
The Windows test runner executes `test_gige_vision.exe` directly and does not
use Linux namespace tools.

`optional/aravis/amv_gige_vision.gpr` is the reusable static library
project. A consumer GPR imports it, for example:

```gpr
with "optional/aravis/amv_gige_vision.gpr";

project My_Camera_App is
   for Source_Dirs use ("src");
   for Object_Dir use "build/camera-app-obj";
   for Exec_Dir use "build/bin";
   for Main use ("main.adb");
   for Languages use ("Ada");
end My_Camera_App;
```

Build the consumer from the repository root with the Aravis compile and
link flags:

```sh
gprbuild -p -P my_camera_app.gpr \
  -cargs:C $(pkg-config --cflags aravis-0.8) \
  -largs $(pkg-config --libs aravis-0.8)
```

The capture example, the Windows live circularity window
(`examples/live_circularity`, `make build-live-circularity`) and the
loopback tests are separate consumer GPR projects; none is part of the
adapter library's sources.

The example opens one explicitly supplied device, captures one image, and
writes a PGM file. `CAMERA_ID` may be an IPv4 address or an Aravis device
identifier such as a serial number. A literal IPv4 address uses Aravis's
direct GigE device API and the operating system's route-selected local
interface; a non-IP identifier is resolved by Aravis only when `Open` is
called. An empty identifier is rejected; the adapter never requests the
first available camera. It performs no discovery during elaboration.

## Lifecycle and frames

Create a limited `Ks_GigE_Camera`, call `Open`, then `Start`, `Grab`, and
`Stop`; `Close` is safe whether stopped or streaming and can be repeated.
`Start` and `Stop` are idempotent. `Grab` requires an open, streaming
camera and a positive timeout in milliseconds. It returns an
`AMV.Images.Ks_Image_8_Grey` whose pixels are copied into AMV-owned storage
before Aravis recycles its stream buffer. The object closes its backend
resources on finalization. A camera object is for single-threaded use; do
not call its operations concurrently.

The logical engine has an AMV-local state contract. `Open` is accepted only
from `Closed`; the selector must be nonempty, contain no NUL, and contain at
least one character other than a space. A successful native open changes the
logical state to `Open_Stopped`; a failed open preserves the closed state and
handle. `Start` on a closed camera is rejected, on a streaming camera is an
idempotent success without native dispatch, and on an open stopped camera
changes state only after native success. `Stop` on a non-streaming camera is
an idempotent success; a failed native stop preserves `Streaming` so it can
be retried. `Close` always clears the local handle and state. If native stop
fails during `Close`, local resources are still released; this does not claim
that the physical camera stopped.

During `Open`, the native setup path checks that the camera's current pixel
format is Mono8 or one of the four Bayer8 formats; it never changes the
camera's settings. Independently, every acquired frame is validated by the
Ada engine.
It accepts only successful image buffers with the Mono8 format, positive
dimensions no larger than `2**31 - 1` pixels, and an exact packed byte count
of `width * height`. Extended-chunk payloads, padding, truncated data,
excess data, and null byte arrays are rejected; no stride is inferred. The
frame-status precedence is specified as: invalid camera state or zero
timeout; `Native_Not_Called`/`Native_Bad_Parameter` as bad parameter,
`Native_Timeout` as timeout, `Native_Out_Of_Memory` as out of memory, and
`Native_Unsupported`/`Native_Error` as frame error; buffer timeout/error;
unsupported payload; unsupported format; invalid dimensions; too many pixels;
invalid byte length; success. For zero-based `x` and `y`, the output pixel at
`(y, x)` equals `bytes(1 + y * width + x)`.

### Exposure and gain

`AMV.GigE_Vision.Settings` sets and reads an open camera's exposure time
(microseconds), automatic exposure and gain through Aravis's standard
features (`ExposureTime` or `ExposureTimeAbs`, `ExposureAuto`, `Gain` or
`GainRaw`), also while it streams. A closed camera or a value that is not
finite raises `AMV.Ks_Bad_Parameter_Exception`; a camera that refuses or
lacks the feature raises `AMV.Ks_Exception` with Aravis's message. These
calls are not part of the SPARK proof.

### Bayer8 frames

The proved engine accepts Mono8 only. When it rejects a frame for its pixel
format alone and that format is BayerGR8, BayerRG8, BayerGB8 or BayerBG8,
the façade passes the same snapshot to `AMV.GigE_Vision_Bayer.Build_Grey`.
It checks the frame like the engine (successful image payload, at least 2x2,
at most `2**31 - 1` pixels, exactly `width * height` packed bytes) and
returns a grey image of the same size. The grey pixel at `(x, y)` is the
BT.601 luma of the 2x2 window whose top-left sample is `(x, y)`, moved one
sample left at the last column and one up at the last row:
`(77 R + 75 (G1 + G2) + 29 B + 128) / 256`. Every 2x2 window of a Bayer
mosaic holds one red, two green and one blue sample, so the weights always
sum to 256. The camera's own white balance, if any, is kept; no other
colour correction is applied. This conversion is tested (worked examples in
the fixtures and every layout through the loopback camera) but it is not
part of the SPARK proof or the Lean comparison.

A camera that only offers Bayer formats may still accept Mono8 written to
its `PixelFormat` register and label its frames Mono8 while sending the raw
mosaic; set such a camera to its Bayer format instead.

On `Grab`, the C shim obtains Aravis status and metadata and copies the raw
buffer to a temporary snapshot. The native Ada bridge copies that snapshot
to an owned Ada byte array; the SPARK engine validates the metadata and
performs the pixel mapping. The façade releases the Ada snapshot after
building/adopting the image, including exceptional exits.

Invalid identifiers, lifecycle calls, or zero timeouts raise
`AMV.Ks_Bad_Parameter_Exception`; backend or malformed-frame failures and
unsupported formats raise `AMV.Ks_Exception`. A finite acquisition timeout
raises `AMV.GigE_Vision.Ks_GigE_Vision_Timeout_Exception`. Packet loss,
camera-side trigger settings, routing, and packet-size mismatches can cause
timeouts or frame errors; increase the timeout only when appropriate and
check the camera/network configuration rather than expecting video-style
recovery.

On Windows, the camera's image stream arrives as unsolicited UDP from the
camera's stream source port, which Windows Defender Firewall blocks unless a
rule allows it (a direct link to a camera is often a Public network). If
`Open` and `Start` succeed but every `Grab` times out, add an inbound UDP
allow rule for the program, or for the camera's address and stream source
port (Aravis logs it with `ARV_DEBUG=stream:3` as "Source stream port").

## Tests and verification scope

`make test-aravis` builds the optional project and uses an in-process fake
camera explicitly bound to `127.0.0.1`; the Ada client opens that literal
address and the test shim rejects every other selector before route or device
calls. Linux runs in a fresh network namespace, trying an unprivileged
namespace and then `sudo -n unshare --net`; it refuses to run if neither is
available. Windows runs the `.exe` directly, with both endpoints restricted
to loopback. The Ada fixtures exercise the ghost specification and production
engine, including status precedence, worked 3x2 pixel mapping, snapshot
mutation/free, lifecycle receipts, timeout handling, Bayer8 worked examples
(each layout, edge windows and statuses), and unsupported or
malformed observations. The loopback test covers lifecycle behavior, distinct
frames, copy lifetime, the Open-time unsupported-format rejection, a frame
in each Bayer8 layout converted to grey, and exposure and gain set while
streaming. No physical camera discovery
or connection is performed.

`make prove-aravis` proves only `AMV.Spec.GigE_Vision` and the production
`AMV.Kernels.GigE_Vision` engine against their local contracts. It proves the
logical state/status results, frame-status precedence, packed-size checks,
and each output pixel's equality to the independent row-major specification.
The image-allocation out-of-memory result is allowed when frame validation
otherwise succeeds. The public controlled façade, the Bayer8 conversion
(`AMV.GigE_Vision_Bayer`), `AMV.Images` adoption, Aravis, C, raw pointer
validity/lifetime, and physical camera or network behavior are outside this
proof. This is not a GigE Vision standard
conformance or whole-module Platinum claim; the native bridge contracts are
trusted boundaries.
