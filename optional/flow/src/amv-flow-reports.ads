pragma SPARK_Mode (Off);

with AMV.Flow.Graphs;
with AMV.Flow.Values;

--  What an editor shows, as JSON (docs/FLOW_EDITOR_DESIGN.md 7.3): the
--  node kinds, a flow's problems, the results of its last run and the
--  graphics of a node; and the image a node took in its last run.

package AMV.Flow.Reports is

   function Kinds_JSON return String;
   --  [{"kind": "Caliper",
   --    "ports":  [{"name", "direction": "in" | "out", "type", "required",
   --                "help"}],
   --    "params": [{"name", "kind": "Real" | "Integer" | "Boolean" |
   --                "Choice" | "String" | "Shape", "low", "high" (Real
   --                and Integer), "choices" (Choice), "unit", "help"}]}]

   function Problems_JSON (Flow : AMV.Flow.Graphs.Ks_Flow) return String;
   --  The problems (AMV.Flow.Graphs.Problems) as a JSON array of strings.

   function Results_JSON (Flow : AMV.Flow.Graphs.Ks_Flow) return String;
   --  {"result": "accept" | "warning" | "reject" | "error",
   --   "message": "...",
   --   "nodes": [{"id", "state": "not run" | "ran" | "skipped", "result",
   --              "message", "timeMs", "outputs": {"<port>": value}}],
   --   "outputs": {"<flow output>": value}}
   --  A value is a number, true / false, a string, the short text of an
   --  image, transform or shape ("image 400x300"), or null for no value.

   function Node_Image (Flow : AMV.Flow.Graphs.Ks_Flow;
                        Id   : Positive) return AMV.Flow.Values.Ks_Flow_Value;
   --  The image that went into the node's input port "Image" in the last
   --  run (No_Value when there is none, or the node has no such port).

   function Graphics_JSON (Flow : AMV.Flow.Graphs.Ks_Flow;
                           Id   : Positive) return String;
   --  What to draw over Node_Image, in its pixel coordinates (the centre
   --  of pixel (i, j) at (i, j)):
   --  {"width", "height",
   --   "items": [{"kind": "polygon", "role": "region" | "train",
   --              "points": [[x, y], ...]},
   --             {"kind": "point", "role": "found", "x", "y"}]}
   --  Regions are the node's shape parameters mapped from their space; a
   --  found point is the node's X, Y (or CenterX, CenterY) outputs mapped
   --  from the image's selected space. {"width": 0, "height": 0,
   --  "items": []} without an image.

end AMV.Flow.Reports;
