# Optional Aravis GigE Vision adapter

`AMV.GigE_Vision` is an optional, non-SPARK Ada adapter for GigE Vision
cameras. Its implementation and C shim live outside `src/`; it does not
change the default `amv.gpr` build, the SPARK kernels, or `include/amv.h`.
The adapter currently targets Linux and Aravis 0.8, and accepts Mono8 image
payloads only. It rejects other pixel formats instead of converting them.
Exposure and gain controls are not included.

## Dependency and build

Install GNAT/gprbuild as for AMV, plus the Aravis 0.8 development package,
`libusb-1.0-0-dev`, and `pkg-config` (for example, `libaravis-dev` on Debian
or Ubuntu). Aravis is an independent backend dependency, licensed
LGPL-2.1-or-later; its licence does not change AMV's licensing. The default
core build and tests do not require Aravis.

```sh
make build-aravis
make test-aravis
make example-aravis CAMERA_ID=192.168.1.20 IMAGE=capture.pgm
```

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
Mono8, and validates positive dimensions. The Aravis 0.8 public
`ArvBuffer` API exposes raw `arv_buffer_get_data` and image dimensions,
but no image-data/padding metadata or row-stride accessor. This adapter
therefore accepts only packed payloads whose size is exactly
`width * height`; any nonpacked or otherwise mismatched payload is
rejected rather than interpreting its size as a stride. Payloads with
chunk data are not accepted. The internal row-copy validator receives
explicit row stride and X/Y padding values; its fixtures cover padded
rows, trailing Y-padding rows, and truncated payloads.

Invalid identifiers, lifecycle calls, or zero timeouts raise
`AMV.Ks_Bad_Parameter_Exception`; backend or malformed-frame failures and
unsupported formats raise `AMV.Ks_Exception`. A finite acquisition timeout
raises `AMV.GigE_Vision.Ks_GigE_Vision_Timeout_Exception`. Packet loss,
camera-side trigger settings, routing, and packet-size mismatches can cause
timeouts or frame errors; increase the timeout only when appropriate and
check the camera/network configuration rather than expecting video-style
recovery.

## Tests and verification scope

`make test-aravis` builds the optional project and runs the in-process fake
camera explicitly on `127.0.0.1` in a fresh network namespace, bringing up
loopback only. It first tries an unprivileged user/network namespace and
falls back to `sudo -n unshare --net` when necessary; if neither can create
a namespace, it refuses to run rather than testing outside one. It tests
invalid inputs, lifecycle behavior, timeout handling, Mono8 copy lifetime,
unsupported pixel formats, and padded/truncated row fixtures. It does not
scan for or connect to hardware cameras. No physical camera hardware
verification is claimed.
