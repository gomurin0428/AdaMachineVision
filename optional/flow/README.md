# AMV Flow (engine)

AMV tools as nodes whose ports are linked into a flow that can be checked,
run, saved and loaded without writing code. The design, including the
JavaFX editor still to come, is in [`docs/FLOW_EDITOR_DESIGN.md`](../../docs/FLOW_EDITOR_DESIGN.md)
(in Japanese). This directory holds the engine (`AMV.Flow`, in Ada, over
the AMV Ada API), the `amv_flow` command-line runner and the tests. It is
outside the proved library and needs AMV only.

```sh
make build-flow                  # build/bin/amv_flow
make test-flow                   # build/bin/test_flow, from the repository root
build/bin/amv_flow kinds         # the node kinds, their ports and parameters
build/bin/amv_flow check part.amvflow
build/bin/amv_flow run part.amvflow scene1.bmp scene2.bmp
build/bin/amv_flow run --images out part.amvflow scene1.bmp   # and each node's image
```

`run` takes a flow with one `Image_8_Grey` input and prints one CSV line
per image: the image, the result (`accept`, `warning`, `reject`,
`error`), the message and the flow's outputs. Its exit status is 0 when
every image was accepted, 1 when one was rejected or failed, 2 for a flow
that cannot be loaded or run. With `--images DIR` it also writes the
image each node made (PolarUnwrap's strip, Morphology's result, ...) into
`DIR/<image name>_node<id>.bmp`, to see what a flow does at each step.

## Packages

| Package | |
|---|---|
| `AMV.Flow` | value types, names, `Ks_Flow_Exception` |
| `AMV.Flow.JSON` | the JSON reader (strict, for untrusted files) and writer |
| `AMV.Flow.Values` | the values of ports and parameters; shapes in flow files |
| `AMV.Flow.Nodes` | the node interface: ports, parameters, `Run`, status |
| `AMV.Flow.Nodes.Vision` | ShapeMatch, Fixture, Caliper, Blob, Circularity |
| `AMV.Flow.Nodes.Imaging` | PolarUnwrap (an annulus about a circle into a strip), Morphology (grey erosion, dilation, opening, closing and the top-hats) |
| `AMV.Flow.Circularity` | the cup measure (outer edge along 720 rays, roundness); also used by `examples/live_circularity` |
| `AMV.Flow.Nodes.Camera` | Camera, in `camera/` (`amv_flow_camera.gpr`): needs Aravis |
| `AMV.Flow.Nodes.Logic` | RangeCheck |
| `AMV.Flow.Kinds` | the node kinds by name |
| `AMV.Flow.Graphs` | `Ks_Flow`: nodes, links, checks, `Run`, flow files |

A flow runs its nodes in topological order (ties by ascending node id).
A node whose source failed or gave no value is skipped; the flow's result
is the worst result of the nodes that ran, and at least Reject when one
was skipped.

## Flow files

JSON, `"format": 1`: the flow's inputs and outputs, the nodes (id, kind,
name, editor position, parameters) and the links (`"1.Pose"` to
`"2.Transform"`, `"input.Image"`, `"output.Width"`). Unknown members,
kinds, ports and parameters are errors. The test flow
`build/flow-test/align.amvflow` (written by `make test-flow`) is the
locate, fixture and measure chain of `examples/align_and_measure.adb`.

## C API

`capi/` builds the engine as the shared library `amvflow`
(`make build-flow-c`, into `build/flow-c-lib`) with the C API of
[`include/amv_flow.h`](include/amv_flow.h): flows, edits, runs, and the
node kinds, problems, results and node graphics as JSON, a node's image
as BGRA. `make test-flow-c` runs its C tests. The JavaFX editor in
[`optional/flow_editor`](../flow_editor/README.md) uses it.

`make build-flow-c-camera` builds the same library with the Camera node
into `build/flow-c-camera-lib` (it needs Aravis, as `make build-aravis`
does; on Windows the Aravis and GLib DLLs are copied next to it). The
Camera node opens the camera at the first run and keeps it streaming;
each run takes the newest complete frame. A flow that starts with a
Camera node has no image input: it runs as it is, again and again in the
editor's Live mode. [`examples/cup_camera.amvflow`](examples/cup_camera.amvflow)
measures a cup's roundness this way (set the Camera node's CameraId to
your camera's address).

[`examples/cup_cut_camera.amvflow`](examples/cup_cut_camera.amvflow) finds
a cut in a cup's side wall (a slit made with scissors, seen from above):

| Node | Does |
|---|---|
| Camera | the frame |
| Circularity | the rim: its centre and radius (fitted to the part of the rim inside the image when the cup runs out of it) |
| PolarUnwrap | the side wall and rim, 0.74 to 0.94 of the rim's radius, unwrapped into a strip; AngleStart 145, AngleSpan 250 leave out the bottom of the cup, which that camera's image cuts off (360 when the whole cup is in view) |
| Morphology | CloseMinusOriginal with a 15 x 1 kernel: what is darker than its neighbours along the circle and narrower than 15 px (the cut, crossing the wall) becomes light; shading round the cup and the rim's edges do not |
| Blob | light blobs of at least 50 px at grey 14 and above: the cuts |
| RangeCheck | Count in [0, 0]: no cut, else Reject |

On the GE134GC frames the slit gives one blob of about 230 px; nothing
else in the strip reaches 30 px at grey 10. A seam or printing on the
side wall would also be a dark line: check uncut cups before relying on
the thresholds.

## Not done yet

From the first phase of the design: the FindCircle, Distance, Histogram
and CSV Log nodes, the place of a cut on the camera image (Blob gives it
in PolarUnwrap's strip), `Ks_Flow_Tool` (a saved flow as an AMV tool), saving
trained patterns (ShapeMatch trains from its `TrainImage` when the flow
loads), the image folder playback, and a camera build of `amv_flow`.
