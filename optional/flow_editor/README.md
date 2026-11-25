# AMV Flow editor (JavaFX)

The editor of AMV Flow ([`docs/FLOW_EDITOR_DESIGN.md`](../../docs/FLOW_EDITOR_DESIGN.md)
6 and 7): a JavaFX application that calls the Ada engine of
[`optional/flow`](../flow/README.md), built as the shared library
`amvflow`, through its C API with Java's Foreign Function & Memory API,
in the same process.

| Project | |
|---|---|
| `amv-flow-native` | `amv.flow.nativeapi.Flow`: the C API of `optional/flow/include/amv_flow.h` as a Java class (no JavaFX); a small JSON reader |
| `amv-flow-editor` | the JavaFX editor |

## Building and running

Needs Java 25 (the Foreign Function & Memory API is final from Java 22)
and Gradle 9; JavaFX 25.0.5 and JUnit come from Maven Central. Build the
engine library first, from the repository's root:

```sh
make test-flow            # also writes the example flow and images into build/flow-test
make build-flow-c         # build/flow-c-lib/libamvflow.dll (.so, .dylib)
make build-flow-c-camera  # or with the Camera node: build/flow-c-camera-lib (needs Aravis)
```

The Gradle build uses the camera library when it has been built, else the
plain one. On Windows the binding adds the library's own directory to the
DLL search path, so the Aravis and GLib DLLs next to it are found.

Then, in `optional/flow_editor`:

```sh
gradle :amv-flow-native:test          # the binding against the library
gradle :amv-flow-editor:run           # the editor with an empty flow
gradle :amv-flow-editor:run -Pflow=build/flow-test/align.amvflow
gradle :amv-flow-editor:installDist   # amv-flow-editor/build/install/amv-flow-editor
```

`run` works in the repository's root and finds the library in
`build/flow-c-lib`; give another with `-PamvFlowLibrary=<path>`. The
installed launcher takes the library from `-Damv.flow.library=<path>` in
`JAVA_OPTS` (or `libamvflow` in the working directory) and the arguments
`[flow file [image file or folder of images]]`:

```sh
set JAVA_OPTS=-Damv.flow.library=D:\...\build\flow-c-lib\libamvflow.dll
amv-flow-editor build\flow-test\align.amvflow build\flow-test\align_scene_1.bmp
```

## Using it

* **Tools** (left): drag a node kind onto the flow, or double-click it.
* **Flow** (centre, top): boxes with input ports on the left and output
  ports on the right, coloured by type; the flow's inputs and outputs are
  the boxes at either end. Drag a box by its title to move it; drag from
  an output port to an input port to link (the engine refuses links
  between types that do not match, a second link into one input and
  cycles, and the status line says why); click a link and press Delete to
  remove it, or a node and Delete to remove the node. A box's border shows
  its last result: green accept, orange reject, red error, grey skipped.
* **Image** (centre, bottom): the selected node's input image from the
  last run (a camera's own frame), with its regions in green and what it
  found in orange (an outline, such as the edge Circularity measured) and
  red (a point). The wheel zooms about the cursor, the right or middle
  button pans, a double click fits the image again. The node's regions
  are edited on the image: drag inside one to move it, a corner (square
  handle) to size it, the round handle to turn a rectangle, the handle on
  a circle's edge for its radius; an annulus (PolarUnwrap's region) has a
  square handle on each of its two arcs for the radii and round ones where
  it starts and ends (a full annulus has one: drag it to open the
  annulus). The drag works in the region's own space
  (a region in a fixtured space turns with the part), and on release the
  flow runs again.
* **Properties** (right): the node's name and parameters, with an editor
  for each (a number, a check box, a choice, a path with a file chooser,
  a shape as JSON); and the outputs of its last run. With no node
  selected: the flow's inputs, outputs and result.
* **Toolbar**: new, open, save; **Undo** / **Redo** (Ctrl+Z, Ctrl+Y or
  Ctrl+Shift+Z: every edit, moves of nodes included, up to 100); Open
  image sets the flow's image input and runs it; **Open folder** plays the
  images of a folder through it (the arrows or Page Up / Page Down, in
  name order); every change runs the flow again (F5 runs it too);
  **Live** (F6) runs it again and again, so that a flow starting with a
  Camera node shows each new frame, or one with an image input steps
  through the folder (edits made meanwhile apply at once); add flow inputs
  and outputs.
* **Flow zoom**: Ctrl + wheel over the flow; Ctrl+0 back to 100 %.

Not yet: drawing a new region on the image (a region parameter is set
first as JSON, then dragged; a new PolarUnwrap has an annulus to drag),
a polygon region, the C API's
image transfer without a copy (`PixelBuffer`).
