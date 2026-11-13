--  The dimensioning tools: the counterparts of the measuring tools of
--  Cognex.VisionPro.Dimensioning (CogDistance*Tool, CogAngle*Tool,
--  CogIntersect*Tool). The fitting tools (CogFitLineTool, ...) are in
--  AMV.Dimensioning.Fitting.
--
--  Each tool takes numbers and shapes and computes the read-only values
--  of its VisionPro counterpart (a distance and the nearest points, an
--  angle, intersection points); Run sets them, Reset_Results (called by
--  Run first) sets them to 0, and a failed run leaves them 0.
--
--     Tool.Line.Set_XY_Rotation (0.0, 0.0, 0.3);
--     Tool.X := 10.0;
--     Tool.Y := 20.0;
--     Tool.Run;
--     D := Tool.Distance;
--
--  Coordinates. As VisionPro maps its shapes into the selected space of
--  the tool's InputImage before it measures, each shape is mapped here
--  from its own selected space into the input image's selected space
--  (Input_Image.Get_Transform (".", Shape.Selected_Space_Name)); plain
--  coordinates (X, Y, Start_X, ...) are taken in that space, and every
--  result is expressed in it. Only the coordinate space tree and the
--  selected space of Input_Image are used, so an image without pixels
--  works: the default image has only the root space "@", in which shapes
--  in "." (the default) or "@" are taken as they are. (VisionPro without
--  an InputImage presumes everything in one space; here a shape whose
--  selected space the image does not know raises
--  Ks_Image_Bad_Selected_Space_Name_Exception.) A circle must stay a
--  circle under its mapping (a similarity). Input_Image is an 8-bit grey
--  image here (VisionPro accepts any ICogImage); its pixels are not read.
--
--  Signs, tolerances and degenerate cases follow the VisionPro reference;
--  the kernel's spec (AMV.Kernels.Dimensioning) documents each in full:
--  distances are >= 0 except where one shape lies inside a circle or an
--  ellipse (negative), touching or crossing shapes are at distance 0 with
--  points (0, 0), NumPoints is -1 (Intersects True) for coincident
--  shapes, and points that are not reported are (0, 0).
--
--  Failures (Run_Status Error): Ks_Bad_Parameter_Exception for values that
--  are not finite or beyond the bounds (1.0E150), an ellipse with a radius
--  of 0, a circle whose mapping is not a similarity, and a result beyond
--  the bounds; Ks_Transform_Singular_Exception for a line whose mapping is
--  singular; Ks_Image_Bad_Selected_Space_Name_Exception for a shape whose
--  selected space is not in the image's tree.
--
--  The SPARK kernel AMV.Kernels.Dimensioning does the work (C API:
--  include/amv_dimensioning.h); its proofs cover the absence of run-time
--  errors and the ranges of every result (distances, angles in (-Pi, Pi],
--  NumPoints and the points within the bounds).

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Images;
with AMV.Shapes;
with AMV.Tools;

private with AMV.Kernels.Dimensioning;

package AMV.Dimensioning is

   ---------------------------------------------------------------------
   --  CogDistancePointPointTool
   ---------------------------------------------------------------------

   type Distance_Point_Point_Outputs is private;
   --  The values Run computes (read them with the functions below).

   type Ks_Distance_Point_Point_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image : AMV.Images.Ks_Image_8_Grey;
      Start_X     : Real := 0.0;
      Start_Y     : Real := 0.0;
      End_X       : Real := 0.0;
      End_Y       : Real := 0.0;
      Outputs     : Distance_Point_Point_Outputs;
   end record;
   --  CogDistancePointPointTool. The distance from (Start_X, Start_Y) to
   --  (End_X, End_Y) and the direction of that segment from the x axis, in
   --  (-Pi, Pi] (0 when the points coincide).

   overriding procedure Execute (Tool : in out Ks_Distance_Point_Point_Tool);
   overriding procedure Reset_Results
     (Tool : in out Ks_Distance_Point_Point_Tool);

   function Distance (Tool : Ks_Distance_Point_Point_Tool) return Real;
   function Angle (Tool : Ks_Distance_Point_Point_Tool) return Real;

   ---------------------------------------------------------------------
   --  CogAnglePointPointTool
   ---------------------------------------------------------------------

   type Angle_Point_Point_Outputs is private;
   --  The values Run computes (read them with the functions below).

   type Ks_Angle_Point_Point_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image : AMV.Images.Ks_Image_8_Grey;
      Start_X     : Real := 0.0;
      Start_Y     : Real := 0.0;
      End_X       : Real := 0.0;
      End_Y       : Real := 0.0;
      Outputs     : Angle_Point_Point_Outputs;
   end record;
   --  CogAnglePointPointTool. The direction from (Start_X, Start_Y) to (End_X,
   --  End_Y), in (-Pi, Pi] (0 when the points coincide).

   overriding procedure Execute (Tool : in out Ks_Angle_Point_Point_Tool);
   overriding procedure Reset_Results
     (Tool : in out Ks_Angle_Point_Point_Tool);

   function Angle (Tool : Ks_Angle_Point_Point_Tool) return Real;

   ---------------------------------------------------------------------
   --  CogAngleLineLineTool
   ---------------------------------------------------------------------

   type Angle_Line_Line_Outputs is private;
   --  The values Run computes (read them with the functions below).

   type Ks_Angle_Line_Line_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image : AMV.Images.Ks_Image_8_Grey;
      Line_A      : AMV.Shapes.Ks_Line;
      Line_B      : AMV.Shapes.Ks_Line;
      Outputs     : Angle_Line_Line_Outputs;
   end record;
   --  CogAngleLineLineTool. The angle from Line_A to Line_B, Line_B.Rotation -
   --  Line_A.Rotation reduced to (-Pi, Pi].

   overriding procedure Execute (Tool : in out Ks_Angle_Line_Line_Tool);
   overriding procedure Reset_Results (Tool : in out Ks_Angle_Line_Line_Tool);

   function Angle (Tool : Ks_Angle_Line_Line_Tool) return Real;

   ---------------------------------------------------------------------
   --  CogDistancePointLineTool
   ---------------------------------------------------------------------

   type Distance_Point_Line_Outputs is private;
   --  The values Run computes (read them with the functions below).

   type Ks_Distance_Point_Line_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image : AMV.Images.Ks_Image_8_Grey;
      X           : Real := 0.0;
      Y           : Real := 0.0;
      Line        : AMV.Shapes.Ks_Line;
      Outputs     : Distance_Point_Line_Outputs;
   end record;
   --  CogDistancePointLineTool. The distance from (X, Y) to the line (>= 0)
   --  and the foot of the perpendicular (Line_X, Line_Y).

   overriding procedure Execute (Tool : in out Ks_Distance_Point_Line_Tool);
   overriding procedure Reset_Results
     (Tool : in out Ks_Distance_Point_Line_Tool);

   function Distance (Tool : Ks_Distance_Point_Line_Tool) return Real;
   function Line_X (Tool : Ks_Distance_Point_Line_Tool) return Real;
   function Line_Y (Tool : Ks_Distance_Point_Line_Tool) return Real;

   ---------------------------------------------------------------------
   --  CogDistancePointSegmentTool
   ---------------------------------------------------------------------

   type Distance_Point_Segment_Outputs is private;
   --  The values Run computes (read them with the functions below).

   type Ks_Distance_Point_Segment_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image : AMV.Images.Ks_Image_8_Grey;
      X           : Real := 0.0;
      Y           : Real := 0.0;
      Segment     : AMV.Shapes.Ks_Line_Segment;
      Outputs     : Distance_Point_Segment_Outputs;
   end record;
   --  CogDistancePointSegmentTool. The distance from (X, Y) to the nearest
   --  point of the segment (Segment_X, Segment_Y).

   overriding procedure Execute (Tool : in out Ks_Distance_Point_Segment_Tool);
   overriding procedure Reset_Results
     (Tool : in out Ks_Distance_Point_Segment_Tool);

   function Distance (Tool : Ks_Distance_Point_Segment_Tool) return Real;
   function Segment_X (Tool : Ks_Distance_Point_Segment_Tool) return Real;
   function Segment_Y (Tool : Ks_Distance_Point_Segment_Tool) return Real;

   ---------------------------------------------------------------------
   --  CogDistancePointCircleTool
   ---------------------------------------------------------------------

   type Distance_Point_Circle_Outputs is private;
   --  The values Run computes (read them with the functions below).

   type Ks_Distance_Point_Circle_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image  : AMV.Images.Ks_Image_8_Grey;
      X            : Real := 0.0;
      Y            : Real := 0.0;
      Input_Circle : AMV.Shapes.Ks_Circle;
      Outputs      : Distance_Point_Circle_Outputs;
   end record;
   --  CogDistancePointCircleTool. The distance from (X, Y) to the circle,
   --  negative inside it, and the nearest point of the circle (Circle_X,
   --  Circle_Y). A point exactly at the centre gives +Radius and the point at
   --  angle 0.

   overriding procedure Execute (Tool : in out Ks_Distance_Point_Circle_Tool);
   overriding procedure Reset_Results
     (Tool : in out Ks_Distance_Point_Circle_Tool);

   function Distance (Tool : Ks_Distance_Point_Circle_Tool) return Real;
   function Circle_X (Tool : Ks_Distance_Point_Circle_Tool) return Real;
   function Circle_Y (Tool : Ks_Distance_Point_Circle_Tool) return Real;

   ---------------------------------------------------------------------
   --  CogDistancePointEllipseTool
   ---------------------------------------------------------------------

   type Distance_Point_Ellipse_Outputs is private;
   --  The values Run computes (read them with the functions below).

   type Ks_Distance_Point_Ellipse_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image : AMV.Images.Ks_Image_8_Grey;
      X           : Real := 0.0;
      Y           : Real := 0.0;
      Ellipse     : AMV.Shapes.Ks_Ellipse;
      Outputs     : Distance_Point_Ellipse_Outputs;
   end record;
   --  CogDistancePointEllipseTool. The distance from (X, Y) to the ellipse,
   --  negative inside it, and the nearest point of the ellipse (Ellipse_X,
   --  Ellipse_Y).

   overriding procedure Execute (Tool : in out Ks_Distance_Point_Ellipse_Tool);
   overriding procedure Reset_Results
     (Tool : in out Ks_Distance_Point_Ellipse_Tool);

   function Distance (Tool : Ks_Distance_Point_Ellipse_Tool) return Real;
   function Ellipse_X (Tool : Ks_Distance_Point_Ellipse_Tool) return Real;
   function Ellipse_Y (Tool : Ks_Distance_Point_Ellipse_Tool) return Real;

   ---------------------------------------------------------------------
   --  CogDistanceSegmentSegmentTool
   ---------------------------------------------------------------------

   type Distance_Segment_Segment_Outputs is private;
   --  The values Run computes (read them with the functions below).

   type Ks_Distance_Segment_Segment_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image : AMV.Images.Ks_Image_8_Grey;
      Segment_A   : AMV.Shapes.Ks_Line_Segment;
      Segment_B   : AMV.Shapes.Ks_Line_Segment;
      Outputs     : Distance_Segment_Segment_Outputs;
   end record;
   --  CogDistanceSegmentSegmentTool. The shortest distance between the
   --  segments and the nearest points on each; 0 and (0, 0) points when they
   --  touch, cross or overlap.

   overriding procedure Execute
     (Tool : in out Ks_Distance_Segment_Segment_Tool);
   overriding procedure Reset_Results
     (Tool : in out Ks_Distance_Segment_Segment_Tool);

   function Distance (Tool : Ks_Distance_Segment_Segment_Tool) return Real;
   function Segment_A_X (Tool : Ks_Distance_Segment_Segment_Tool) return Real;
   function Segment_A_Y (Tool : Ks_Distance_Segment_Segment_Tool) return Real;
   function Segment_B_X (Tool : Ks_Distance_Segment_Segment_Tool) return Real;
   function Segment_B_Y (Tool : Ks_Distance_Segment_Segment_Tool) return Real;

   ---------------------------------------------------------------------
   --  CogDistanceSegmentLineTool
   ---------------------------------------------------------------------

   type Distance_Segment_Line_Outputs is private;
   --  The values Run computes (read them with the functions below).

   type Ks_Distance_Segment_Line_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image : AMV.Images.Ks_Image_8_Grey;
      Segment     : AMV.Shapes.Ks_Line_Segment;
      Line        : AMV.Shapes.Ks_Line;
      Outputs     : Distance_Segment_Line_Outputs;
   end record;
   --  CogDistanceSegmentLineTool. The distance of the nearer end point of the
   --  segment from the line, that end point and its foot on the line; 0 and
   --  (0, 0) points when the segment touches or crosses the line.

   overriding procedure Execute (Tool : in out Ks_Distance_Segment_Line_Tool);
   overriding procedure Reset_Results
     (Tool : in out Ks_Distance_Segment_Line_Tool);

   function Distance (Tool : Ks_Distance_Segment_Line_Tool) return Real;
   function Segment_X (Tool : Ks_Distance_Segment_Line_Tool) return Real;
   function Segment_Y (Tool : Ks_Distance_Segment_Line_Tool) return Real;
   function Line_X (Tool : Ks_Distance_Segment_Line_Tool) return Real;
   function Line_Y (Tool : Ks_Distance_Segment_Line_Tool) return Real;

   ---------------------------------------------------------------------
   --  CogDistanceLineCircleTool
   ---------------------------------------------------------------------

   type Distance_Line_Circle_Outputs is private;
   --  The values Run computes (read them with the functions below).

   type Ks_Distance_Line_Circle_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image  : AMV.Images.Ks_Image_8_Grey;
      Line         : AMV.Shapes.Ks_Line;
      Input_Circle : AMV.Shapes.Ks_Circle;
      Outputs      : Distance_Line_Circle_Outputs;
   end record;
   --  CogDistanceLineCircleTool. The gap between the line and the circle and
   --  the facing points; 0 and (0, 0) points when the line meets the circle.

   overriding procedure Execute (Tool : in out Ks_Distance_Line_Circle_Tool);
   overriding procedure Reset_Results
     (Tool : in out Ks_Distance_Line_Circle_Tool);

   function Distance (Tool : Ks_Distance_Line_Circle_Tool) return Real;
   function Line_X (Tool : Ks_Distance_Line_Circle_Tool) return Real;
   function Line_Y (Tool : Ks_Distance_Line_Circle_Tool) return Real;
   function Circle_X (Tool : Ks_Distance_Line_Circle_Tool) return Real;
   function Circle_Y (Tool : Ks_Distance_Line_Circle_Tool) return Real;

   ---------------------------------------------------------------------
   --  CogDistanceSegmentCircleTool
   ---------------------------------------------------------------------

   type Distance_Segment_Circle_Outputs is private;
   --  The values Run computes (read them with the functions below).

   type Ks_Distance_Segment_Circle_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image  : AMV.Images.Ks_Image_8_Grey;
      Segment      : AMV.Shapes.Ks_Line_Segment;
      Input_Circle : AMV.Shapes.Ks_Circle;
      Outputs      : Distance_Segment_Circle_Outputs;
   end record;
   --  CogDistanceSegmentCircleTool. The gap between the segment and the circle
   --  (negative when the segment lies inside the circle) and the facing
   --  points; 0 and (0, 0) points when the segment touches or crosses the
   --  circle.

   overriding procedure Execute
     (Tool : in out Ks_Distance_Segment_Circle_Tool);
   overriding procedure Reset_Results
     (Tool : in out Ks_Distance_Segment_Circle_Tool);

   function Distance (Tool : Ks_Distance_Segment_Circle_Tool) return Real;
   function Segment_X (Tool : Ks_Distance_Segment_Circle_Tool) return Real;
   function Segment_Y (Tool : Ks_Distance_Segment_Circle_Tool) return Real;
   function Circle_X (Tool : Ks_Distance_Segment_Circle_Tool) return Real;
   function Circle_Y (Tool : Ks_Distance_Segment_Circle_Tool) return Real;

   ---------------------------------------------------------------------
   --  CogDistanceCircleCircleTool
   ---------------------------------------------------------------------

   type Distance_Circle_Circle_Outputs is private;
   --  The values Run computes (read them with the functions below).

   type Ks_Distance_Circle_Circle_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image : AMV.Images.Ks_Image_8_Grey;
      Circle_A    : AMV.Shapes.Ks_Circle;
      Circle_B    : AMV.Shapes.Ks_Circle;
      Outputs     : Distance_Circle_Circle_Outputs;
   end record;
   --  CogDistanceCircleCircleTool. The gap between the circles (negative when
   --  one lies inside the other) and the facing points; 0 and (0, 0) points
   --  when they are identical, touch or cross.

   overriding procedure Execute (Tool : in out Ks_Distance_Circle_Circle_Tool);
   overriding procedure Reset_Results
     (Tool : in out Ks_Distance_Circle_Circle_Tool);

   function Distance (Tool : Ks_Distance_Circle_Circle_Tool) return Real;
   function Circle_A_X (Tool : Ks_Distance_Circle_Circle_Tool) return Real;
   function Circle_A_Y (Tool : Ks_Distance_Circle_Circle_Tool) return Real;
   function Circle_B_X (Tool : Ks_Distance_Circle_Circle_Tool) return Real;
   function Circle_B_Y (Tool : Ks_Distance_Circle_Circle_Tool) return Real;

   ---------------------------------------------------------------------
   --  CogDistanceLineEllipseTool
   ---------------------------------------------------------------------

   type Distance_Line_Ellipse_Outputs is private;
   --  The values Run computes (read them with the functions below).

   type Ks_Distance_Line_Ellipse_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image : AMV.Images.Ks_Image_8_Grey;
      Line        : AMV.Shapes.Ks_Line;
      Ellipse     : AMV.Shapes.Ks_Ellipse;
      Outputs     : Distance_Line_Ellipse_Outputs;
   end record;
   --  CogDistanceLineEllipseTool. The gap between the line and the ellipse and
   --  the facing points; 0 and (0, 0) points when the line meets the ellipse.

   overriding procedure Execute (Tool : in out Ks_Distance_Line_Ellipse_Tool);
   overriding procedure Reset_Results
     (Tool : in out Ks_Distance_Line_Ellipse_Tool);

   function Distance (Tool : Ks_Distance_Line_Ellipse_Tool) return Real;
   function Line_X (Tool : Ks_Distance_Line_Ellipse_Tool) return Real;
   function Line_Y (Tool : Ks_Distance_Line_Ellipse_Tool) return Real;
   function Ellipse_X (Tool : Ks_Distance_Line_Ellipse_Tool) return Real;
   function Ellipse_Y (Tool : Ks_Distance_Line_Ellipse_Tool) return Real;

   ---------------------------------------------------------------------
   --  CogDistanceSegmentEllipseTool
   ---------------------------------------------------------------------

   type Distance_Segment_Ellipse_Outputs is private;
   --  The values Run computes (read them with the functions below).

   type Ks_Distance_Segment_Ellipse_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image : AMV.Images.Ks_Image_8_Grey;
      Segment     : AMV.Shapes.Ks_Line_Segment;
      Ellipse     : AMV.Shapes.Ks_Ellipse;
      Outputs     : Distance_Segment_Ellipse_Outputs;
   end record;
   --  CogDistanceSegmentEllipseTool. The gap between the segment and the
   --  ellipse (negative when the segment lies inside the ellipse) and the
   --  facing points; 0 and (0, 0) points when the segment meets the ellipse's
   --  boundary.

   overriding procedure Execute
     (Tool : in out Ks_Distance_Segment_Ellipse_Tool);
   overriding procedure Reset_Results
     (Tool : in out Ks_Distance_Segment_Ellipse_Tool);

   function Distance (Tool : Ks_Distance_Segment_Ellipse_Tool) return Real;
   function Segment_X (Tool : Ks_Distance_Segment_Ellipse_Tool) return Real;
   function Segment_Y (Tool : Ks_Distance_Segment_Ellipse_Tool) return Real;
   function Ellipse_X (Tool : Ks_Distance_Segment_Ellipse_Tool) return Real;
   function Ellipse_Y (Tool : Ks_Distance_Segment_Ellipse_Tool) return Real;

   ---------------------------------------------------------------------
   --  CogIntersectLineLineTool
   ---------------------------------------------------------------------

   type Intersect_Line_Line_Outputs is private;
   --  The values Run computes (read them with the functions below).

   type Ks_Intersect_Line_Line_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image : AMV.Images.Ks_Image_8_Grey;
      Line_A      : AMV.Shapes.Ks_Line;
      Line_B      : AMV.Shapes.Ks_Line;
      Outputs     : Intersect_Line_Line_Outputs;
   end record;
   --  CogIntersectLineLineTool. Num_Points 1 and the crossing point (X, Y); 0
   --  for parallel lines; -1 for coincident lines (Intersects True, no point).
   --  Angle is the angle from Line_A to Line_B in (-Pi, Pi].

   overriding procedure Execute (Tool : in out Ks_Intersect_Line_Line_Tool);
   overriding procedure Reset_Results
     (Tool : in out Ks_Intersect_Line_Line_Tool);

   function Intersects (Tool : Ks_Intersect_Line_Line_Tool) return Boolean;
   function Num_Points (Tool : Ks_Intersect_Line_Line_Tool) return Integer;
   function X (Tool : Ks_Intersect_Line_Line_Tool) return Real;
   function Y (Tool : Ks_Intersect_Line_Line_Tool) return Real;
   function Angle (Tool : Ks_Intersect_Line_Line_Tool) return Real;

   ---------------------------------------------------------------------
   --  CogIntersectSegmentLineTool
   ---------------------------------------------------------------------

   type Intersect_Segment_Line_Outputs is private;
   --  The values Run computes (read them with the functions below).

   type Ks_Intersect_Segment_Line_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image : AMV.Images.Ks_Image_8_Grey;
      Segment     : AMV.Shapes.Ks_Line_Segment;
      Line        : AMV.Shapes.Ks_Line;
      Outputs     : Intersect_Segment_Line_Outputs;
   end record;
   --  CogIntersectSegmentLineTool. Num_Points 1 and the point where the
   --  segment crosses or touches the line; 0 when it does not; -1 when the
   --  segment lies on the line.

   overriding procedure Execute (Tool : in out Ks_Intersect_Segment_Line_Tool);
   overriding procedure Reset_Results
     (Tool : in out Ks_Intersect_Segment_Line_Tool);

   function Intersects (Tool : Ks_Intersect_Segment_Line_Tool) return Boolean;
   function Num_Points (Tool : Ks_Intersect_Segment_Line_Tool) return Integer;
   function X (Tool : Ks_Intersect_Segment_Line_Tool) return Real;
   function Y (Tool : Ks_Intersect_Segment_Line_Tool) return Real;

   ---------------------------------------------------------------------
   --  CogIntersectSegmentSegmentTool
   ---------------------------------------------------------------------

   type Intersect_Segment_Segment_Outputs is private;
   --  The values Run computes (read them with the functions below).

   type Ks_Intersect_Segment_Segment_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image : AMV.Images.Ks_Image_8_Grey;
      Segment_A   : AMV.Shapes.Ks_Line_Segment;
      Segment_B   : AMV.Shapes.Ks_Line_Segment;
      Outputs     : Intersect_Segment_Segment_Outputs;
   end record;
   --  CogIntersectSegmentSegmentTool. Num_Points 1 and the point where the
   --  segments cross or touch; 0 when they do not meet; -1 when they overlap
   --  along a line.

   overriding procedure Execute
     (Tool : in out Ks_Intersect_Segment_Segment_Tool);
   overriding procedure Reset_Results
     (Tool : in out Ks_Intersect_Segment_Segment_Tool);

   function Intersects (Tool : Ks_Intersect_Segment_Segment_Tool)
     return Boolean;
   function Num_Points (Tool : Ks_Intersect_Segment_Segment_Tool)
     return Integer;
   function X (Tool : Ks_Intersect_Segment_Segment_Tool) return Real;
   function Y (Tool : Ks_Intersect_Segment_Segment_Tool) return Real;

   ---------------------------------------------------------------------
   --  CogIntersectLineCircleTool
   ---------------------------------------------------------------------

   type Intersect_Line_Circle_Outputs is private;
   --  The values Run computes (read them with the functions below).

   type Ks_Intersect_Line_Circle_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image  : AMV.Images.Ks_Image_8_Grey;
      Line         : AMV.Shapes.Ks_Line;
      Input_Circle : AMV.Shapes.Ks_Circle;
      Outputs      : Intersect_Line_Circle_Outputs;
   end record;
   --  CogIntersectLineCircleTool. 0, 1 (tangent) or 2 points, the first one
   --  first along the line.

   overriding procedure Execute (Tool : in out Ks_Intersect_Line_Circle_Tool);
   overriding procedure Reset_Results
     (Tool : in out Ks_Intersect_Line_Circle_Tool);

   function Intersects (Tool : Ks_Intersect_Line_Circle_Tool) return Boolean;
   function Num_Points (Tool : Ks_Intersect_Line_Circle_Tool) return Integer;
   function X0 (Tool : Ks_Intersect_Line_Circle_Tool) return Real;
   function Y0 (Tool : Ks_Intersect_Line_Circle_Tool) return Real;
   function X1 (Tool : Ks_Intersect_Line_Circle_Tool) return Real;
   function Y1 (Tool : Ks_Intersect_Line_Circle_Tool) return Real;

   ---------------------------------------------------------------------
   --  CogIntersectSegmentCircleTool
   ---------------------------------------------------------------------

   type Intersect_Segment_Circle_Outputs is private;
   --  The values Run computes (read them with the functions below).

   type Ks_Intersect_Segment_Circle_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image  : AMV.Images.Ks_Image_8_Grey;
      Segment      : AMV.Shapes.Ks_Line_Segment;
      Input_Circle : AMV.Shapes.Ks_Circle;
      Outputs      : Intersect_Segment_Circle_Outputs;
   end record;
   --  CogIntersectSegmentCircleTool. The points of the segment on the circle,
   --  from its start to its end: 0, 1 or 2.

   overriding procedure Execute
     (Tool : in out Ks_Intersect_Segment_Circle_Tool);
   overriding procedure Reset_Results
     (Tool : in out Ks_Intersect_Segment_Circle_Tool);

   function Intersects (Tool : Ks_Intersect_Segment_Circle_Tool)
     return Boolean;
   function Num_Points (Tool : Ks_Intersect_Segment_Circle_Tool)
     return Integer;
   function X0 (Tool : Ks_Intersect_Segment_Circle_Tool) return Real;
   function Y0 (Tool : Ks_Intersect_Segment_Circle_Tool) return Real;
   function X1 (Tool : Ks_Intersect_Segment_Circle_Tool) return Real;
   function Y1 (Tool : Ks_Intersect_Segment_Circle_Tool) return Real;

   ---------------------------------------------------------------------
   --  CogIntersectCircleCircleTool
   ---------------------------------------------------------------------

   type Intersect_Circle_Circle_Outputs is private;
   --  The values Run computes (read them with the functions below).

   type Ks_Intersect_Circle_Circle_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image : AMV.Images.Ks_Image_8_Grey;
      Circle_A    : AMV.Shapes.Ks_Circle;
      Circle_B    : AMV.Shapes.Ks_Circle;
      Outputs     : Intersect_Circle_Circle_Outputs;
   end record;
   --  CogIntersectCircleCircleTool. 0, 1 (touching) or 2 points, or -1 for
   --  identical circles. X2, Y2, X3 and Y3 are always 0 (as in VisionPro, at
   --  most two points are found).

   overriding procedure Execute
     (Tool : in out Ks_Intersect_Circle_Circle_Tool);
   overriding procedure Reset_Results
     (Tool : in out Ks_Intersect_Circle_Circle_Tool);

   function Intersects (Tool : Ks_Intersect_Circle_Circle_Tool) return Boolean;
   function Num_Points (Tool : Ks_Intersect_Circle_Circle_Tool) return Integer;
   function X0 (Tool : Ks_Intersect_Circle_Circle_Tool) return Real;
   function Y0 (Tool : Ks_Intersect_Circle_Circle_Tool) return Real;
   function X1 (Tool : Ks_Intersect_Circle_Circle_Tool) return Real;
   function Y1 (Tool : Ks_Intersect_Circle_Circle_Tool) return Real;
   function X2 (Tool : Ks_Intersect_Circle_Circle_Tool) return Real;
   function Y2 (Tool : Ks_Intersect_Circle_Circle_Tool) return Real;
   function X3 (Tool : Ks_Intersect_Circle_Circle_Tool) return Real;
   function Y3 (Tool : Ks_Intersect_Circle_Circle_Tool) return Real;

   ---------------------------------------------------------------------
   --  CogIntersectLineEllipseTool
   ---------------------------------------------------------------------

   type Intersect_Line_Ellipse_Outputs is private;
   --  The values Run computes (read them with the functions below).

   type Ks_Intersect_Line_Ellipse_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image : AMV.Images.Ks_Image_8_Grey;
      Line        : AMV.Shapes.Ks_Line;
      Ellipse     : AMV.Shapes.Ks_Ellipse;
      Outputs     : Intersect_Line_Ellipse_Outputs;
   end record;
   --  CogIntersectLineEllipseTool. 0, 1 (tangent) or 2 points, the first one
   --  first along the line.

   overriding procedure Execute (Tool : in out Ks_Intersect_Line_Ellipse_Tool);
   overriding procedure Reset_Results
     (Tool : in out Ks_Intersect_Line_Ellipse_Tool);

   function Intersects (Tool : Ks_Intersect_Line_Ellipse_Tool) return Boolean;
   function Num_Points (Tool : Ks_Intersect_Line_Ellipse_Tool) return Integer;
   function X0 (Tool : Ks_Intersect_Line_Ellipse_Tool) return Real;
   function Y0 (Tool : Ks_Intersect_Line_Ellipse_Tool) return Real;
   function X1 (Tool : Ks_Intersect_Line_Ellipse_Tool) return Real;
   function Y1 (Tool : Ks_Intersect_Line_Ellipse_Tool) return Real;

   ---------------------------------------------------------------------
   --  CogIntersectSegmentEllipseTool
   ---------------------------------------------------------------------

   type Intersect_Segment_Ellipse_Outputs is private;
   --  The values Run computes (read them with the functions below).

   type Ks_Intersect_Segment_Ellipse_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image : AMV.Images.Ks_Image_8_Grey;
      Segment     : AMV.Shapes.Ks_Line_Segment;
      Ellipse     : AMV.Shapes.Ks_Ellipse;
      Outputs     : Intersect_Segment_Ellipse_Outputs;
   end record;
   --  CogIntersectSegmentEllipseTool. The points of the segment on the
   --  ellipse, from its start to its end: 0, 1 or 2.

   overriding procedure Execute
     (Tool : in out Ks_Intersect_Segment_Ellipse_Tool);
   overriding procedure Reset_Results
     (Tool : in out Ks_Intersect_Segment_Ellipse_Tool);

   function Intersects (Tool : Ks_Intersect_Segment_Ellipse_Tool)
     return Boolean;
   function Num_Points (Tool : Ks_Intersect_Segment_Ellipse_Tool)
     return Integer;
   function X0 (Tool : Ks_Intersect_Segment_Ellipse_Tool) return Real;
   function Y0 (Tool : Ks_Intersect_Segment_Ellipse_Tool) return Real;
   function X1 (Tool : Ks_Intersect_Segment_Ellipse_Tool) return Real;
   function Y1 (Tool : Ks_Intersect_Segment_Ellipse_Tool) return Real;

private

   package KD renames AMV.Kernels.Dimensioning;

   type Distance_Point_Point_Outputs is record
      Data : KD.Ks_Distance_Point_Point_Result;
   end record;

   type Angle_Point_Point_Outputs is record
      Data : Real := 0.0;
   end record;

   type Angle_Line_Line_Outputs is record
      Data : Real := 0.0;
   end record;

   type Distance_Point_Line_Outputs is record
      Data : KD.Ks_Distance_Point_Line_Result;
   end record;

   type Distance_Point_Segment_Outputs is record
      Data : KD.Ks_Distance_Point_Segment_Result;
   end record;

   type Distance_Point_Circle_Outputs is record
      Data : KD.Ks_Distance_Point_Circle_Result;
   end record;

   type Distance_Point_Ellipse_Outputs is record
      Data : KD.Ks_Distance_Point_Ellipse_Result;
   end record;

   type Distance_Segment_Segment_Outputs is record
      Data : KD.Ks_Distance_Segment_Segment_Result;
   end record;

   type Distance_Segment_Line_Outputs is record
      Data : KD.Ks_Distance_Segment_Line_Result;
   end record;

   type Distance_Line_Circle_Outputs is record
      Data : KD.Ks_Distance_Line_Circle_Result;
   end record;

   type Distance_Segment_Circle_Outputs is record
      Data : KD.Ks_Distance_Segment_Circle_Result;
   end record;

   type Distance_Circle_Circle_Outputs is record
      Data : KD.Ks_Distance_Circle_Circle_Result;
   end record;

   type Distance_Line_Ellipse_Outputs is record
      Data : KD.Ks_Distance_Line_Ellipse_Result;
   end record;

   type Distance_Segment_Ellipse_Outputs is record
      Data : KD.Ks_Distance_Segment_Ellipse_Result;
   end record;

   type Intersect_Line_Line_Outputs is record
      Data : KD.Ks_Intersect_Line_Line_Result;
   end record;

   type Intersect_Segment_Line_Outputs is record
      Data : KD.Ks_Intersect_Segment_Line_Result;
   end record;

   type Intersect_Segment_Segment_Outputs is record
      Data : KD.Ks_Intersect_Segment_Segment_Result;
   end record;

   type Intersect_Line_Circle_Outputs is record
      Data : KD.Ks_Intersect_Line_Circle_Result;
   end record;

   type Intersect_Segment_Circle_Outputs is record
      Data : KD.Ks_Intersect_Segment_Circle_Result;
   end record;

   type Intersect_Circle_Circle_Outputs is record
      Data : KD.Ks_Intersect_Circle_Circle_Result;
   end record;

   type Intersect_Line_Ellipse_Outputs is record
      Data : KD.Ks_Intersect_Line_Ellipse_Result;
   end record;

   type Intersect_Segment_Ellipse_Outputs is record
      Data : KD.Ks_Intersect_Segment_Ellipse_Result;
   end record;

end AMV.Dimensioning;
