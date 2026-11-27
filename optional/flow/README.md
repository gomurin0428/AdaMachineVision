# AMV Flow (engine)

AMV tools as nodes whose ports are linked into a flow that can be checked,
run, saved and loaded without writing code. The design is in
[`docs/FLOW_EDITOR_DESIGN.md`](../../docs/FLOW_EDITOR_DESIGN.md) (in
Japanese); the JavaFX editor is in [`optional/flow_editor`](../flow_editor/README.md). This directory holds the engine (`AMV.Flow`, in Ada, over
the AMV Ada API), the `amv_flow` command-line runner and the tests. It is
outside the proved library and needs AMV only.

```sh
make build-flow                  # build/bin/amv_flow
make test-flow                   # build/bin/test_flow, from the repository root
build/bin/amv_flow kinds         # the node kinds, their ports and parameters
build/bin/amv_flow check part.amvflow
build/bin/amv_flow run part.amvflow scene1.bmp scene2.bmp
build/bin/amv_flow run --images out part.amvflow scene1.bmp   # and each node's image
build/bin/amv_flow run --recipe productB.amvrecipe part.amvflow scene1.bmp
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
| `AMV.Flow.Nodes.Imaging` | PolarUnwrap (an annulus about a circle into a strip), PolarPoint (a point of that strip back on the image), Morphology (grey erosion, dilation, opening, closing and the top-hats) |
| `AMV.Flow.Circularity` | the cup measure (outer edge along 720 rays, roundness); also used by `examples/live_circularity` |
| `AMV.Flow.Nodes.Camera` | Camera, in `camera/` (`amv_flow_camera.gpr`): needs Aravis |
| `AMV.Flow.Nodes.Measure` | FindCircle (calipers round an expected circle; a Pose for a Fixture), Distance (two points), Histogram (grey statistics and Otsu's threshold in a region) |
| `AMV.Flow.Nodes.Logic` | RangeCheck; And, Or (In1 .. In4, Judge: a False verdict rejects the run), Not |
| `AMV.Flow.Nodes.Logging` | CsvLog: a row per run, of the values linked into it (its inputs are of type Any) |
| `AMV.Flow.Kinds` | the node kinds by name |
| `AMV.Flow.Graphs` | `Ks_Flow`: nodes, links, checks, `Run`, flow files |

A recipe is one product's settings for a flow: the value of every
parameter of every node, `{"format": 1, "recipe", "flow", "params":
{"<node id>.<parameter>": value}}` (`Recipe_JSON`). `Apply_Recipe` sets
the parameters a recipe names, all or nothing, so that one flow serves
several products (`amvf_flow_recipe_json`, `amvf_flow_apply_recipe`;
`--recipe` for `amv_flow run`; Save / Load recipe in the editor).

ShapeMatch trains its pattern when the flow loads. With `PatternPath`
(an `.amvpattern` file next to the flow), the trained pattern is saved
with what it was trained from (the SHA-256 of the train image file, the
region, the origin) and read again instead of training while those stay
the same, wherever the files are copied to. Without the train image
(`TrainImage` empty, or a file that is not there) the saved pattern is
used, so a flow can be shipped with its pattern only; a region or origin
other than the pattern's is then a problem, as there is nothing to train
from. A pattern that cannot be saved (a read-only folder) does not stop
the node: its runs warn instead. A file at `PatternPath` that is not a
saved pattern is never written over. The pattern is written only once
the flow keeps it (`Commit`, after `Prepare`): a recipe that is refused
leaves the file as it was.

A flow counts its runs by result (`Counts`, `Reset_Counts`; `"counts"` in
the results JSON, `amvf_flow_reset_counts` in the C API): a pass / fail
tally, which the editor shows.

A flow runs its nodes in topological order (ties by ascending node id).
A node whose source failed or gave no value is skipped (an optional
input, such as CsvLog's, just has no value then); the flow's result
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
a cut in a cup's side wall (a slit made with scissors, seen from above),
with the same pattern as locate, fixture and measure:

| Node | Does |
|---|---|
| Camera | the frame |
| Circularity | finds the rim; its Pose (a translation to the rim's centre) goes to the Fixture |
| Fixture | adds the space "Cup", centred on the rim, so that the region below follows the cup |
| PolarUnwrap | Region: an annulus in "Cup" (radii 326 to 414 px, all round) over the side wall and the rim, unwrapped into a strip |
| Morphology | CloseMinusOriginal, 15 x 1: what is darker than its neighbours along the circle and narrower than 15 px (a cut crossing the wall) becomes light; shading round the cup and the edges of the rim and the bottom do not |
| Morphology | Dilate, 7 x 7: joins the pieces of one cut (an opened cut has two edges, broken in places) |
| Blob | light blobs of at least 200 px at grey 14 and above: the lines on the wall |
| RangeCheck | Count in [1, 1]: only the cup's seam |
| RangeCheck | the largest line's Area in [0, 1400]: no line wider than the seam (a cut pulled open) |
| CsvLog | a row a run into `build/cup_cut_checks.csv`: the lines, the largest one's area, both checks, the rim's roundness and the verdict, to set the limits from many cups |
| And | the verdict: both checks pass (output OK; Judge on) |
| PolarPoint | the largest line, back on the camera image (select it in the editor to see the mark; LineAngle in radians) |

A paper cup has one seam, a line down its wall, and from above it looks
like a fresh cut: on the GE134GC frames the seam is a line of 1005 px
(after the dilation), a fresh cut one of 936 px, and both mark the rim's
edge (the seam even more, 11 px against 4). So the flow does not tell a
line from a cut; it expects exactly one line, the seam: two or more is a
cut, none means the seam was not seen (the light, the region) and is a
reject too. A cut pulled open is wider (1748 px) and fails the second
check even where it is the only line found; a fresh cut on the seam
itself would join it and pass. Measured on a single cup: set
the limits from a few uncut and cut cups before relying on them. The
seam must be inside the annulus, so the annulus goes all round: the whole
cup must be in the image (else PolarUnwrap stops with an error; a part of
the cup left out could hide the seam, and one cut would pass for it).

## Not done yet

From the first phase of the design: `Ks_Flow_Tool` (a saved flow as an
AMV tool) and a camera build of `amv_flow`.
