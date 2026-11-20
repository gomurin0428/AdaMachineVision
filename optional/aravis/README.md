# Optional Aravis GigE Vision adapter

`AMV.GigE_Vision` is an optional, non-SPARK Ada adapter for GigE Vision
cameras. Its implementation and C shim live outside `src/`; it does not
change the default `amv.gpr` build, the SPARK kernels, or `include/amv.h`.
The adapter targets Linux and Windows. Aravis 0.8.20 is the minimum tested
Linux version; Windows CI pins Aravis 0.8.33. Its first implementation accepts
packed Mono8 payloads only and rejects other pixel formats instead of
converting them.
Exposure and gain controls are not included.

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

The capture example and loopback tests are separate consumer GPR projects;
neither is part of the adapter library's sources.

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

The C shim checks the Aravis buffer status and image payload, requires
Mono8, and validates positive dimensions. Aravis 0.8.20 exposes raw
`arv_buffer_get_data` and image dimensions. Later 0.8 releases add
`arv_buffer_get_image_padding` (since 0.8.23) and
`arv_buffer_get_image_data` (since 0.8.25), but the first adapter version
intentionally does not use those accessors: it accepts only packed payloads
whose size is exactly `width * height`, and rejects nonpacked or otherwise
mismatched payloads rather than inferring a stride. Payloads with chunk data
are not accepted. The internal row-copy validator receives explicit row
stride and X/Y padding values; its fixtures cover padded rows, trailing
Y-padding rows, and truncated payloads.

Invalid identifiers, lifecycle calls, or zero timeouts raise
`AMV.Ks_Bad_Parameter_Exception`; backend or malformed-frame failures and
unsupported formats raise `AMV.Ks_Exception`. A finite acquisition timeout
raises `AMV.GigE_Vision.Ks_GigE_Vision_Timeout_Exception`. Packet loss,
camera-side trigger settings, routing, and packet-size mismatches can cause
timeouts or frame errors; increase the timeout only when appropriate and
check the camera/network configuration rather than expecting video-style
recovery.

## Tests and verification scope

`make test-aravis` builds the optional project and uses an in-process fake
camera explicitly bound to `127.0.0.1`; the Ada client opens that literal
address and the test shim rejects every other selector before route or device
calls. Linux runs in a fresh network namespace, trying an unprivileged
namespace and then `sudo -n unshare --net`; it refuses to run if neither is
available. Windows runs the `.exe` directly, with both endpoints restricted
to loopback. The test reports the native OS and successful Mono8 frame
dimensions, and covers lifecycle behavior, timeout handling, distinct frames,
copy lifetime, unsupported formats, and padded/truncated row fixtures. It
does not scan for or connect to hardware cameras. No physical camera hardware
verification is claimed.
