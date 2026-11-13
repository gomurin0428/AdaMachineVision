--  The shape creation tools: the counterparts of the CogCreate*Tool classes
--  of Cognex.VisionPro.Dimensioning (CogCreateCircleTool,
--  CogCreateEllipseTool, CogCreateLineTool, CogCreateSegmentTool,
--  CogCreateLineBisectPointsTool, CogCreateLineParallelTool,
--  CogCreateLinePerpendicularTool, CogCreateSegmentAvgSegsTool). The
--  graphics-only CogCreateGraphicLabelTool is not provided.
--
--  Each tool builds one shape from its inputs; Run creates it and
--  Get_Output_<Shape> returns a copy (the value of VisionPro's
--  GetOutput<Shape>). Reset_Results (called by Run first) and a failed
--  run leave the default shape of AMV.Shapes there.
--
--     Tool.Line.Set_XY_Rotation (0.0, 0.0, 0.3);
--     Tool.X := 10.0;
--     Tool.Y := 20.0;
--     Tool.Run;
--     Perpendicular := Tool.Get_Output_Line;
--
--  Coordinates. As in AMV.Dimensioning, each input shape is mapped from
--  its own selected space into the selected space of Input_Image
--  (Input_Image.Get_Transform (".", Shape.Selected_Space_Name)), plain
--  coordinates (X, Y, Start_X, ...) are taken in that space, and the
--  created shape is expressed in it. Following the VisionPro reference,
--  the created shape's Selected_Space_Name is the image's selected space
--  as Input_Image.Selected_Space_Name reads it (a full name such as
--  "@\Fixture", or "@" for an image whose selection was never changed),
--  not ".": so the shape keeps its meaning when the image's selection
--  changes later, and it is in "." for that image. Only the coordinate
--  space tree and the selected space of Input_Image are used, so an image
--  without pixels works. A shape whose selected space the image does not
--  know raises Ks_Image_Bad_Selected_Space_Name_Exception.
--
--  What each tool creates (AMV.Kernels.Create_Shapes has the details):
--
--  * Ks_Create_Circle_Tool, Ks_Create_Ellipse_Tool, Ks_Create_Line_Tool,
--    Ks_Create_Segment_Tool: the input shape expressed in the image's
--    selected space. A circle must stay a circle under its mapping (a
--    similarity); an ellipse stays an ellipse under any mapping.
--  * Ks_Create_Line_Bisect_Points_Tool: the perpendicular bisector of the
--    points (Start_X, Start_Y) and (End_X, End_Y): through their midpoint,
--    with the direction from the start to the end point plus Pi/2.
--  * Ks_Create_Line_Parallel_Tool: the line through (X, Y) with Line's
--    rotation.
--  * Ks_Create_Line_Perpendicular_Tool: the line through (X, Y) whose
--    rotation is Line's plus Pi/2.
--  * Ks_Create_Segment_Avg_Segs_Tool: the segment from the midpoint of the
--    start points of Segment_A and Segment_B to the midpoint of their end
--    points. The segments are not turned round, so give them in the same
--    direction (two segments in opposite directions average to a short
--    segment, possibly of no length).
--
--  Every rotation of a created line or ellipse lies in (-Pi, Pi] (Pi/2 is
--  added, then 2 Pi subtracted when the sum exceeds Pi).
--
--  Failures (Run_Status Error): Ks_Bad_Parameter_Exception for values that
--  are not finite or beyond the bounds (1.0E150), a created shape that
--  would leave them, an ellipse with a radius of 0 (before or after the
--  mapping), a circle whose mapping is not a similarity, and equal points
--  for the bisector; Ks_Transform_Singular_Exception for a line whose
--  mapping is singular; Ks_Image_Bad_Selected_Space_Name_Exception for an
--  input shape whose selected space is not in the image's tree.
--
--  The SPARK kernel AMV.Kernels.Create_Shapes does the work (C API:
--  include/amv_create_shapes.h); its proofs cover the absence of run-time
--  errors, the bounds of every created shape and the construction itself
--  (the point, the midpoints and the rotation of each created shape).

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Images;
with AMV.Shapes;
with AMV.Tools;

package AMV.Dimensioning.Create_Shapes is

   ---------------------------------------------------------------------
   --  CogCreateCircleTool
   ---------------------------------------------------------------------

   type Create_Circle_Outputs is private;
   --  The shape Run creates (read it with Get_Output_Circle).

   type Ks_Create_Circle_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image  : AMV.Images.Ks_Image_8_Grey;
      Input_Circle : AMV.Shapes.Ks_Circle;
      Outputs      : Create_Circle_Outputs;
   end record;
   --  CogCreateCircleTool. Input_Circle in the image's selected space.

   overriding procedure Execute (Tool : in out Ks_Create_Circle_Tool);
   overriding procedure Reset_Results (Tool : in out Ks_Create_Circle_Tool);

   function Get_Output_Circle
     (Tool : Ks_Create_Circle_Tool) return AMV.Shapes.Ks_Circle;

   ---------------------------------------------------------------------
   --  CogCreateEllipseTool
   ---------------------------------------------------------------------

   type Create_Ellipse_Outputs is private;
   --  The shape Run creates (read it with Get_Output_Ellipse).

   type Ks_Create_Ellipse_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image : AMV.Images.Ks_Image_8_Grey;
      Ellipse     : AMV.Shapes.Ks_Ellipse;
      Outputs     : Create_Ellipse_Outputs;
   end record;
   --  CogCreateEllipseTool. Ellipse in the image's selected space (both
   --  radii must be > 0).

   overriding procedure Execute (Tool : in out Ks_Create_Ellipse_Tool);
   overriding procedure Reset_Results (Tool : in out Ks_Create_Ellipse_Tool);

   function Get_Output_Ellipse
     (Tool : Ks_Create_Ellipse_Tool) return AMV.Shapes.Ks_Ellipse;

   ---------------------------------------------------------------------
   --  CogCreateLineTool
   ---------------------------------------------------------------------

   type Create_Line_Outputs is private;
   --  The shape Run creates (read it with Get_Output_Line).

   type Ks_Create_Line_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image : AMV.Images.Ks_Image_8_Grey;
      Line        : AMV.Shapes.Ks_Line;
      Outputs     : Create_Line_Outputs;
   end record;
   --  CogCreateLineTool. Line in the image's selected space, its rotation
   --  in (-Pi, Pi].

   overriding procedure Execute (Tool : in out Ks_Create_Line_Tool);
   overriding procedure Reset_Results (Tool : in out Ks_Create_Line_Tool);

   function Get_Output_Line
     (Tool : Ks_Create_Line_Tool) return AMV.Shapes.Ks_Line;

   ---------------------------------------------------------------------
   --  CogCreateSegmentTool
   ---------------------------------------------------------------------

   type Create_Segment_Outputs is private;
   --  The shape Run creates (read it with Get_Output_Segment).

   type Ks_Create_Segment_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image : AMV.Images.Ks_Image_8_Grey;
      Segment     : AMV.Shapes.Ks_Line_Segment;
      Outputs     : Create_Segment_Outputs;
   end record;
   --  CogCreateSegmentTool. Segment in the image's selected space.

   overriding procedure Execute (Tool : in out Ks_Create_Segment_Tool);
   overriding procedure Reset_Results (Tool : in out Ks_Create_Segment_Tool);

   function Get_Output_Segment
     (Tool : Ks_Create_Segment_Tool) return AMV.Shapes.Ks_Line_Segment;

   ---------------------------------------------------------------------
   --  CogCreateLineBisectPointsTool
   ---------------------------------------------------------------------

   type Create_Line_Bisect_Points_Outputs is private;
   --  The shape Run creates (read it with Get_Output_Line).

   type Ks_Create_Line_Bisect_Points_Tool is new AMV.Tools.Ks_Tool
   with record
      Input_Image : AMV.Images.Ks_Image_8_Grey;
      Start_X     : Real := 0.0;
      Start_Y     : Real := 0.0;
      End_X       : Real := 0.0;
      End_Y       : Real := 0.0;
      Outputs     : Create_Line_Bisect_Points_Outputs;
   end record;
   --  CogCreateLineBisectPointsTool. The perpendicular bisector of the two
   --  points (which must differ).

   overriding procedure Execute
     (Tool : in out Ks_Create_Line_Bisect_Points_Tool);
   overriding procedure Reset_Results
     (Tool : in out Ks_Create_Line_Bisect_Points_Tool);

   function Get_Output_Line
     (Tool : Ks_Create_Line_Bisect_Points_Tool) return AMV.Shapes.Ks_Line;

   ---------------------------------------------------------------------
   --  CogCreateLineParallelTool
   ---------------------------------------------------------------------

   type Create_Line_Parallel_Outputs is private;
   --  The shape Run creates (read it with Get_Output_Line).

   type Ks_Create_Line_Parallel_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image : AMV.Images.Ks_Image_8_Grey;
      X           : Real := 0.0;
      Y           : Real := 0.0;
      Line        : AMV.Shapes.Ks_Line;
      Outputs     : Create_Line_Parallel_Outputs;
   end record;
   --  CogCreateLineParallelTool. The line through (X, Y) parallel to Line.

   overriding procedure Execute (Tool : in out Ks_Create_Line_Parallel_Tool);
   overriding procedure Reset_Results
     (Tool : in out Ks_Create_Line_Parallel_Tool);

   function Get_Output_Line
     (Tool : Ks_Create_Line_Parallel_Tool) return AMV.Shapes.Ks_Line;

   ---------------------------------------------------------------------
   --  CogCreateLinePerpendicularTool
   ---------------------------------------------------------------------

   type Create_Line_Perpendicular_Outputs is private;
   --  The shape Run creates (read it with Get_Output_Line).

   type Ks_Create_Line_Perpendicular_Tool is new AMV.Tools.Ks_Tool
   with record
      Input_Image : AMV.Images.Ks_Image_8_Grey;
      X           : Real := 0.0;
      Y           : Real := 0.0;
      Line        : AMV.Shapes.Ks_Line;
      Outputs     : Create_Line_Perpendicular_Outputs;
   end record;
   --  CogCreateLinePerpendicularTool. The line through (X, Y) perpendicular
   --  to Line.

   overriding procedure Execute
     (Tool : in out Ks_Create_Line_Perpendicular_Tool);
   overriding procedure Reset_Results
     (Tool : in out Ks_Create_Line_Perpendicular_Tool);

   function Get_Output_Line
     (Tool : Ks_Create_Line_Perpendicular_Tool) return AMV.Shapes.Ks_Line;

   ---------------------------------------------------------------------
   --  CogCreateSegmentAvgSegsTool
   ---------------------------------------------------------------------

   type Create_Segment_Avg_Segs_Outputs is private;
   --  The shape Run creates (read it with Get_Output_Segment).

   type Ks_Create_Segment_Avg_Segs_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image : AMV.Images.Ks_Image_8_Grey;
      Segment_A   : AMV.Shapes.Ks_Line_Segment;
      Segment_B   : AMV.Shapes.Ks_Line_Segment;
      Outputs     : Create_Segment_Avg_Segs_Outputs;
   end record;
   --  CogCreateSegmentAvgSegsTool. The average of Segment_A and Segment_B.

   overriding procedure Execute
     (Tool : in out Ks_Create_Segment_Avg_Segs_Tool);
   overriding procedure Reset_Results
     (Tool : in out Ks_Create_Segment_Avg_Segs_Tool);

   function Get_Output_Segment
     (Tool : Ks_Create_Segment_Avg_Segs_Tool)
      return AMV.Shapes.Ks_Line_Segment;

private

   type Create_Circle_Outputs is record
      Circle : AMV.Shapes.Ks_Circle;
   end record;

   type Create_Ellipse_Outputs is record
      Ellipse : AMV.Shapes.Ks_Ellipse;
   end record;

   type Create_Line_Outputs is record
      Line : AMV.Shapes.Ks_Line;
   end record;

   type Create_Segment_Outputs is record
      Segment : AMV.Shapes.Ks_Line_Segment;
   end record;

   type Create_Line_Bisect_Points_Outputs is record
      Line : AMV.Shapes.Ks_Line;
   end record;

   type Create_Line_Parallel_Outputs is record
      Line : AMV.Shapes.Ks_Line;
   end record;

   type Create_Line_Perpendicular_Outputs is record
      Line : AMV.Shapes.Ks_Line;
   end record;

   type Create_Segment_Avg_Segs_Outputs is record
      Segment : AMV.Shapes.Ks_Line_Segment;
   end record;

end AMV.Dimensioning.Create_Shapes;
