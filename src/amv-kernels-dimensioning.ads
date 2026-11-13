--  Kernel of AMV.Dimensioning: the measuring tools of
--  Cognex.VisionPro.Dimensioning (CogDistance*Tool, CogAngle*Tool,
--  CogIntersect*Tool). Its entry points are the C API of
--  include/amv_dimensioning.h (names ks_distance_*, ks_angle_*,
--  ks_intersect_*). The fitting tools (CogFitLineTool, CogFitCircleTool,
--  CogFitEllipseTool) are in the child AMV.Kernels.Dimensioning.Fitting.
--
--  These tools measure shapes and points; they read no pixels. Each takes
--  its inputs (numbers and the shape records of AMV.Kernels.Shapes) and
--  fills a fixed-size result record (C: ks_<tool>_result), or returns a
--  single angle, as the read-only properties of the VisionPro tool.
--
--  Coordinates. Every result is expressed in one space, the "measuring
--  space": in the Ada API the selected space of the tool's InputImage.
--  Each shape comes with the transform from its own selected space to the
--  measuring space (Selected_From_<Shape>), and the kernel maps the shape
--  with the map entry points of AMV.Kernels.Shapes before it measures;
--  plain coordinates (X, Y, StartX, ...) are taken in the measuring space
--  as they are. With identity transforms everything is in one space. A
--  circle must stay a circle under its transform (a similarity, possibly
--  reflecting, within the tolerance of ks_circle_map); otherwise the call
--  fails with Bad_Parameter.
--
--  Bounds. Every coordinate taken or returned, and every radius after the
--  mapping, lies within [-Max_Value, Max_Value] (1.0E150, the bound of
--  AMV.Kernels.Shapes and AMV.Kernels.Geometry); distances lie within
--  [-Max_Length, Max_Length] (4.0E150, more than the largest distance
--  between two points within the bound); angles in (-Pi, Pi]. A NaN, an
--  infinity or a value beyond its bound gives Bad_Parameter naming the
--  property ("X must be finite and within +/-1.0E150"); a mapped shape
--  beyond the bounds gives Bad_Parameter too, and a line whose transform
--  is singular Transform_Singular. A result point that would leave the
--  bound (possible only for inputs near it) gives Bad_Parameter ("the
--  result would exceed +/-1.0E150"). An ellipse needs both radii > 0.
--
--  Signs and degenerate cases follow the VisionPro reference (CogMath):
--
--  * Distances are >= 0, except where one shape lies inside a circle or an
--    ellipse: a point inside (DistancePointCircle, DistancePointEllipse), a
--    segment inside (DistanceSegmentCircle, DistanceSegmentEllipse) and a
--    circle inside another (DistanceCircleCircle) give the negative of the
--    shortest distance between the boundaries. A point exactly at the
--    centre of a circle gives +Radius and an arbitrary point of the circle
--    (the reference documents this case so).
--  * Shapes that touch or cross (a line through a circle, two crossing
--    segments, overlapping circles) are at distance 0, and the points of
--    a tool that measures between two shapes are then (0, 0).
--  * Intersections report NumPoints: 0 (Intersects False) when the shapes
--    do not meet, the number of points found (1 or 2), or -1 (Intersects
--    True, no point) when they coincide: coincident lines, collinear
--    overlapping segments, a segment lying on a line, identical circles.
--    Points that are not reported are (0, 0). Tangent shapes give one
--    point.
--
--  The tolerances (the same as AMV.Kernels.Geometry's where they overlap):
--  lines are parallel when the sine of the angle between them is at most
--  1.0E-12; parallel lines, segments and a segment on a line coincide when
--  their distance is at most 1.0E-9 times the larger of 1 and the extent
--  of the configuration (the distance between the lines' reference points,
--  the segments' lengths); a line or a circle is tangent to a circle, and
--  circles touch, when the distance differs from the radius (sum or
--  difference) by at most 1.0E-9 times the larger of 1 and the radius
--  (sum); a line is tangent to an ellipse when its distance from the
--  centre differs from the ellipse's extent across the line by at most
--  1.0E-9 times the larger radius; an intersection point found on a
--  segment's line counts for the segment when it lies within 1.0E-9 times
--  the segment's length beyond an end (it is then moved onto that end).
--  Distances use exact comparisons (a tangent line is at distance 0 only
--  when the computed gap is not positive).
--
--  Proved (docs/PROOF.md): absence of run-time errors for any argument
--  (NaN and infinities included); only the documented failure codes;
--  every result within its bounds: distances >= 0 where VisionPro
--  documents them unsigned and >= -Max_Length (never below -Radius for a
--  point and a circle) where it does not, angles in (-Pi, Pi], every
--  point within 1.0E150, NumPoints within its documented range (-1 .. 1,
--  0 .. 2 or -1 .. 2), Intersects = (NumPoints /= 0), and the points not
--  reported, and every value of a failed call, exactly 0 (Gold).
--
--  Nothing is trusted: the kernel has no SPARK_Mode Off body.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Numerics;

with AMV.Kernels.Shapes;
with AMV.Kernels.Transforms;

package AMV.Kernels.Dimensioning with SPARK_Mode, Preelaborate is

   package KS renames AMV.Kernels.Shapes;
   package KT renames AMV.Kernels.Transforms;

   Pi : constant := Ada.Numerics.Pi;

   Max_Value : constant := 1.0E150;
   --  The bound of coordinates and radii (C: KS_DIMENSIONING_MAX_VALUE).

   Max_Length : constant := 4.0E150;
   --  The bound of distances (C: KS_DIMENSIONING_MAX_LENGTH).

   function Bounded (X : Long_Float) return Boolean is
     (X >= -Max_Value and then X <= Max_Value);
   --  A coordinate within the bound (False for a NaN at run time).

   function Unsigned_Distance (D : Long_Float) return Boolean is
     (D >= 0.0 and then D <= Max_Length);

   function Signed_Distance (D : Long_Float) return Boolean is
     (D >= -Max_Length and then D <= Max_Length);

   function Valid_Angle (A : Long_Float) return Boolean is
     (A > -Pi and then A <= Pi);

   function Status_OK (Status : Ks_Status) return Boolean is
     (Valid (Status)
      and then Status.Failure
                 in Failure_None | Failure_Bad_Parameter
                  | Failure_Transform_Singular);
   --  A valid status with one of the failures the tools can report.

   ---------------------------------------------------------------------
   --  Result records (the read-only properties of the tools)
   ---------------------------------------------------------------------

   --  Every record of a failed call holds zeros (its default value).

   type Ks_Distance_Point_Point_Result is record
      Distance : Long_Float := 0.0;
      Angle    : Long_Float := 0.0;
   end record
     with Convention => C;
   --  C: ks_distance_point_point_result. Distance and Angle of
   --  CogDistancePointPointTool.

   function Valid_Result (R : Ks_Distance_Point_Point_Result) return Boolean
   is (Unsigned_Distance (R.Distance) and then Valid_Angle (R.Angle));

   type Ks_Distance_Point_Line_Result is record
      Distance : Long_Float := 0.0;
      Line_X   : Long_Float := 0.0;
      Line_Y   : Long_Float := 0.0;
   end record
     with Convention => C;
   --  C: ks_distance_point_line_result (CogDistancePointLineTool).

   function Valid_Result (R : Ks_Distance_Point_Line_Result) return Boolean
   is (Unsigned_Distance (R.Distance)
       and then Bounded (R.Line_X) and then Bounded (R.Line_Y));

   type Ks_Distance_Point_Segment_Result is record
      Distance  : Long_Float := 0.0;
      Segment_X : Long_Float := 0.0;
      Segment_Y : Long_Float := 0.0;
   end record
     with Convention => C;
   --  C: ks_distance_point_segment_result (CogDistancePointSegmentTool).

   function Valid_Result (R : Ks_Distance_Point_Segment_Result)
      return Boolean
   is (Unsigned_Distance (R.Distance)
       and then Bounded (R.Segment_X) and then Bounded (R.Segment_Y));

   type Ks_Distance_Point_Circle_Result is record
      Distance : Long_Float := 0.0;
      Circle_X : Long_Float := 0.0;
      Circle_Y : Long_Float := 0.0;
   end record
     with Convention => C;
   --  C: ks_distance_point_circle_result (CogDistancePointCircleTool).

   function Valid_Result (R : Ks_Distance_Point_Circle_Result) return Boolean
   is (Signed_Distance (R.Distance)
       and then Bounded (R.Circle_X) and then Bounded (R.Circle_Y));

   type Ks_Distance_Point_Ellipse_Result is record
      Distance  : Long_Float := 0.0;
      Ellipse_X : Long_Float := 0.0;
      Ellipse_Y : Long_Float := 0.0;
   end record
     with Convention => C;
   --  C: ks_distance_point_ellipse_result (CogDistancePointEllipseTool).

   function Valid_Result (R : Ks_Distance_Point_Ellipse_Result)
      return Boolean
   is (Signed_Distance (R.Distance)
       and then Bounded (R.Ellipse_X) and then Bounded (R.Ellipse_Y));

   type Ks_Distance_Segment_Segment_Result is record
      Distance    : Long_Float := 0.0;
      Segment_A_X : Long_Float := 0.0;
      Segment_A_Y : Long_Float := 0.0;
      Segment_B_X : Long_Float := 0.0;
      Segment_B_Y : Long_Float := 0.0;
   end record
     with Convention => C;
   --  C: ks_distance_segment_segment_result
   --  (CogDistanceSegmentSegmentTool: SegmentAX, SegmentAY, SegmentBX,
   --  SegmentBY).

   function Valid_Result (R : Ks_Distance_Segment_Segment_Result)
      return Boolean
   is (Unsigned_Distance (R.Distance)
       and then Bounded (R.Segment_A_X) and then Bounded (R.Segment_A_Y)
       and then Bounded (R.Segment_B_X) and then Bounded (R.Segment_B_Y)
       and then (if R.Distance = 0.0
                 then R.Segment_A_X = 0.0 and then R.Segment_A_Y = 0.0
                      and then R.Segment_B_X = 0.0
                      and then R.Segment_B_Y = 0.0));

   type Ks_Distance_Segment_Line_Result is record
      Distance  : Long_Float := 0.0;
      Segment_X : Long_Float := 0.0;
      Segment_Y : Long_Float := 0.0;
      Line_X    : Long_Float := 0.0;
      Line_Y    : Long_Float := 0.0;
   end record
     with Convention => C;
   --  C: ks_distance_segment_line_result (CogDistanceSegmentLineTool).

   function Valid_Result (R : Ks_Distance_Segment_Line_Result)
      return Boolean
   is (Unsigned_Distance (R.Distance)
       and then Bounded (R.Segment_X) and then Bounded (R.Segment_Y)
       and then Bounded (R.Line_X) and then Bounded (R.Line_Y)
       and then (if R.Distance = 0.0
                 then R.Segment_X = 0.0 and then R.Segment_Y = 0.0
                      and then R.Line_X = 0.0 and then R.Line_Y = 0.0));

   type Ks_Distance_Line_Circle_Result is record
      Distance : Long_Float := 0.0;
      Line_X   : Long_Float := 0.0;
      Line_Y   : Long_Float := 0.0;
      Circle_X : Long_Float := 0.0;
      Circle_Y : Long_Float := 0.0;
   end record
     with Convention => C;
   --  C: ks_distance_line_circle_result (CogDistanceLineCircleTool).

   function Valid_Result (R : Ks_Distance_Line_Circle_Result) return Boolean
   is (Unsigned_Distance (R.Distance)
       and then Bounded (R.Line_X) and then Bounded (R.Line_Y)
       and then Bounded (R.Circle_X) and then Bounded (R.Circle_Y)
       and then (if R.Distance = 0.0
                 then R.Line_X = 0.0 and then R.Line_Y = 0.0
                      and then R.Circle_X = 0.0 and then R.Circle_Y = 0.0));

   type Ks_Distance_Segment_Circle_Result is record
      Distance  : Long_Float := 0.0;
      Segment_X : Long_Float := 0.0;
      Segment_Y : Long_Float := 0.0;
      Circle_X  : Long_Float := 0.0;
      Circle_Y  : Long_Float := 0.0;
   end record
     with Convention => C;
   --  C: ks_distance_segment_circle_result (CogDistanceSegmentCircleTool).

   function Valid_Result (R : Ks_Distance_Segment_Circle_Result)
      return Boolean
   is (Signed_Distance (R.Distance)
       and then Bounded (R.Segment_X) and then Bounded (R.Segment_Y)
       and then Bounded (R.Circle_X) and then Bounded (R.Circle_Y)
       and then (if R.Distance = 0.0
                 then R.Segment_X = 0.0 and then R.Segment_Y = 0.0
                      and then R.Circle_X = 0.0 and then R.Circle_Y = 0.0));

   type Ks_Distance_Circle_Circle_Result is record
      Distance   : Long_Float := 0.0;
      Circle_A_X : Long_Float := 0.0;
      Circle_A_Y : Long_Float := 0.0;
      Circle_B_X : Long_Float := 0.0;
      Circle_B_Y : Long_Float := 0.0;
   end record
     with Convention => C;
   --  C: ks_distance_circle_circle_result (CogDistanceCircleCircleTool:
   --  CircleAX, CircleAY, CircleBX, CircleBY).

   function Valid_Result (R : Ks_Distance_Circle_Circle_Result)
      return Boolean
   is (Signed_Distance (R.Distance)
       and then Bounded (R.Circle_A_X) and then Bounded (R.Circle_A_Y)
       and then Bounded (R.Circle_B_X) and then Bounded (R.Circle_B_Y)
       and then (if R.Distance = 0.0
                 then R.Circle_A_X = 0.0 and then R.Circle_A_Y = 0.0
                      and then R.Circle_B_X = 0.0
                      and then R.Circle_B_Y = 0.0));

   type Ks_Distance_Line_Ellipse_Result is record
      Distance  : Long_Float := 0.0;
      Line_X    : Long_Float := 0.0;
      Line_Y    : Long_Float := 0.0;
      Ellipse_X : Long_Float := 0.0;
      Ellipse_Y : Long_Float := 0.0;
   end record
     with Convention => C;
   --  C: ks_distance_line_ellipse_result (CogDistanceLineEllipseTool).

   function Valid_Result (R : Ks_Distance_Line_Ellipse_Result)
      return Boolean
   is (Unsigned_Distance (R.Distance)
       and then Bounded (R.Line_X) and then Bounded (R.Line_Y)
       and then Bounded (R.Ellipse_X) and then Bounded (R.Ellipse_Y)
       and then (if R.Distance = 0.0
                 then R.Line_X = 0.0 and then R.Line_Y = 0.0
                      and then R.Ellipse_X = 0.0
                      and then R.Ellipse_Y = 0.0));

   type Ks_Distance_Segment_Ellipse_Result is record
      Distance  : Long_Float := 0.0;
      Segment_X : Long_Float := 0.0;
      Segment_Y : Long_Float := 0.0;
      Ellipse_X : Long_Float := 0.0;
      Ellipse_Y : Long_Float := 0.0;
   end record
     with Convention => C;
   --  C: ks_distance_segment_ellipse_result
   --  (CogDistanceSegmentEllipseTool).

   function Valid_Result (R : Ks_Distance_Segment_Ellipse_Result)
      return Boolean
   is (Signed_Distance (R.Distance)
       and then Bounded (R.Segment_X) and then Bounded (R.Segment_Y)
       and then Bounded (R.Ellipse_X) and then Bounded (R.Ellipse_Y)
       and then (if R.Distance = 0.0
                 then R.Segment_X = 0.0 and then R.Segment_Y = 0.0
                      and then R.Ellipse_X = 0.0
                      and then R.Ellipse_Y = 0.0));

   type Ks_Intersect_Line_Line_Result is record
      Intersects : Int32 := False_Value;
      Num_Points : Int32 := 0;
      X          : Long_Float := 0.0;
      Y          : Long_Float := 0.0;
      Angle      : Long_Float := 0.0;
   end record
     with Convention => C;
   --  C: ks_intersect_line_line_result (CogIntersectLineLineTool).

   function Valid_Result (R : Ks_Intersect_Line_Line_Result) return Boolean
   is (R.Num_Points in -1 .. 1
       and then R.Intersects
                  = (if R.Num_Points /= 0 then True_Value else False_Value)
       and then Bounded (R.X) and then Bounded (R.Y)
       and then (if R.Num_Points /= 1 then R.X = 0.0 and then R.Y = 0.0)
       and then Valid_Angle (R.Angle));

   type Ks_Intersect_Segment_Line_Result is record
      Intersects : Int32 := False_Value;
      Num_Points : Int32 := 0;
      X          : Long_Float := 0.0;
      Y          : Long_Float := 0.0;
   end record
     with Convention => C;
   --  C: ks_intersect_segment_line_result (CogIntersectSegmentLineTool).

   function Valid_Result (R : Ks_Intersect_Segment_Line_Result)
      return Boolean
   is (R.Num_Points in -1 .. 1
       and then R.Intersects
                  = (if R.Num_Points /= 0 then True_Value else False_Value)
       and then Bounded (R.X) and then Bounded (R.Y)
       and then (if R.Num_Points /= 1 then R.X = 0.0 and then R.Y = 0.0));

   type Ks_Intersect_Segment_Segment_Result is record
      Intersects : Int32 := False_Value;
      Num_Points : Int32 := 0;
      X          : Long_Float := 0.0;
      Y          : Long_Float := 0.0;
   end record
     with Convention => C;
   --  C: ks_intersect_segment_segment_result
   --  (CogIntersectSegmentSegmentTool).

   function Valid_Result (R : Ks_Intersect_Segment_Segment_Result)
      return Boolean
   is (R.Num_Points in -1 .. 1
       and then R.Intersects
                  = (if R.Num_Points /= 0 then True_Value else False_Value)
       and then Bounded (R.X) and then Bounded (R.Y)
       and then (if R.Num_Points /= 1 then R.X = 0.0 and then R.Y = 0.0));

   type Ks_Intersect_Two_Points_Result is record
      Intersects : Int32 := False_Value;
      Num_Points : Int32 := 0;
      X0         : Long_Float := 0.0;
      Y0         : Long_Float := 0.0;
      X1         : Long_Float := 0.0;
      Y1         : Long_Float := 0.0;
   end record
     with Convention => C;
   --  The properties of the tools that find at most two points
   --  (CogIntersectLineCircleTool, CogIntersectSegmentCircleTool,
   --  CogIntersectLineEllipseTool, CogIntersectSegmentEllipseTool). C:
   --  ks_intersect_line_circle_result and the three others, which are this
   --  struct.

   function Valid_Result (R : Ks_Intersect_Two_Points_Result) return Boolean
   is (R.Num_Points in 0 .. 2
       and then R.Intersects
                  = (if R.Num_Points /= 0 then True_Value else False_Value)
       and then Bounded (R.X0) and then Bounded (R.Y0)
       and then Bounded (R.X1) and then Bounded (R.Y1)
       and then (if R.Num_Points < 1 then R.X0 = 0.0 and then R.Y0 = 0.0)
       and then (if R.Num_Points < 2 then R.X1 = 0.0 and then R.Y1 = 0.0));

   subtype Ks_Intersect_Line_Circle_Result is Ks_Intersect_Two_Points_Result;
   subtype Ks_Intersect_Segment_Circle_Result is
     Ks_Intersect_Two_Points_Result;
   subtype Ks_Intersect_Line_Ellipse_Result is
     Ks_Intersect_Two_Points_Result;
   subtype Ks_Intersect_Segment_Ellipse_Result is
     Ks_Intersect_Two_Points_Result;

   type Ks_Intersect_Circle_Circle_Result is record
      Intersects : Int32 := False_Value;
      Num_Points : Int32 := 0;
      X0         : Long_Float := 0.0;
      Y0         : Long_Float := 0.0;
      X1         : Long_Float := 0.0;
      Y1         : Long_Float := 0.0;
      X2         : Long_Float := 0.0;
      Y2         : Long_Float := 0.0;
      X3         : Long_Float := 0.0;
      Y3         : Long_Float := 0.0;
   end record
     with Convention => C;
   --  C: ks_intersect_circle_circle_result (CogIntersectCircleCircleTool).
   --  As in VisionPro, at most two points are found here, so X2, Y2, X3
   --  and Y3 are always 0 (they are kept for the layout of the tool).

   function Valid_Result (R : Ks_Intersect_Circle_Circle_Result)
      return Boolean
   is (R.Num_Points in -1 .. 2
       and then R.Intersects
                  = (if R.Num_Points /= 0 then True_Value else False_Value)
       and then Bounded (R.X0) and then Bounded (R.Y0)
       and then Bounded (R.X1) and then Bounded (R.Y1)
       and then (if R.Num_Points < 1 then R.X0 = 0.0 and then R.Y0 = 0.0)
       and then (if R.Num_Points < 2 then R.X1 = 0.0 and then R.Y1 = 0.0)
       and then R.X2 = 0.0 and then R.Y2 = 0.0
       and then R.X3 = 0.0 and then R.Y3 = 0.0);

   ---------------------------------------------------------------------
   --  Points and angles
   ---------------------------------------------------------------------

   procedure Distance_Point_Point
     (Start_X, Start_Y, End_X, End_Y : Long_Float;
      Result                         : out Ks_Distance_Point_Point_Result;
      Status                         : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_distance_point_point_execute",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Valid_Result (Result)
             and then (if not Succeeded (Status)
                       then Result = (others => <>));
   --  CogDistancePointPointTool: the length of the segment from (StartX,
   --  StartY) to (EndX, EndY), and its direction from the x axis in
   --  (-Pi, Pi] (0 when the points coincide).

   procedure Angle_Point_Point
     (Start_X, Start_Y, End_X, End_Y : Long_Float;
      Angle                          : out Long_Float;
      Status                         : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_angle_point_point_execute",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Valid_Angle (Angle)
             and then (if not Succeeded (Status) then Angle = 0.0);
   --  CogAnglePointPointTool: the direction from (StartX, StartY) to
   --  (EndX, EndY), as DistancePointPoint's Angle.

   procedure Angle_Line_Line
     (Line_A, Line_B                       : KS.Ks_Line;
      Selected_From_Line_A                 : KT.Ks_Transform_2D_Linear;
      Selected_From_Line_B                 : KT.Ks_Transform_2D_Linear;
      Angle                                : out Long_Float;
      Status                               : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_angle_line_line_execute",
     Post => Status_OK (Status)
             and then Valid_Angle (Angle)
             and then (if not Succeeded (Status) then Angle = 0.0);
   --  CogAngleLineLineTool: LineB.Rotation - LineA.Rotation (after the
   --  mapping), reduced to (-Pi, Pi]: the angle from line A to line B.

   ---------------------------------------------------------------------
   --  Distances
   ---------------------------------------------------------------------

   procedure Distance_Point_Line
     (X, Y               : Long_Float;
      Line               : KS.Ks_Line;
      Selected_From_Line : KT.Ks_Transform_2D_Linear;
      Result             : out Ks_Distance_Point_Line_Result;
      Status             : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_distance_point_line_execute",
     Post => Status_OK (Status) and then Valid_Result (Result)
             and then (if not Succeeded (Status)
                       then Result = (others => <>));
   --  CogDistancePointLineTool: the perpendicular distance from (X, Y) to
   --  the line, and the foot of the perpendicular (LineX, LineY).

   procedure Distance_Point_Segment
     (X, Y                  : Long_Float;
      Segment               : KS.Ks_Line_Segment;
      Selected_From_Segment : KT.Ks_Transform_2D_Linear;
      Result                : out Ks_Distance_Point_Segment_Result;
      Status                : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_distance_point_segment_execute",
     Post => Status_OK (Status) and then Valid_Result (Result)
             and then (if not Succeeded (Status)
                       then Result = (others => <>));
   --  CogDistancePointSegmentTool: the distance from (X, Y) to the
   --  nearest point of the segment (SegmentX, SegmentY), an end point or
   --  the foot of the perpendicular. A segment of no length is its start
   --  point.

   procedure Distance_Point_Circle
     (X, Y                 : Long_Float;
      Input_Circle         : KS.Ks_Circle;
      Selected_From_Circle : KT.Ks_Transform_2D_Linear;
      Result               : out Ks_Distance_Point_Circle_Result;
      Status               : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_distance_point_circle_execute",
     Post => Status_OK (Status) and then Valid_Result (Result)
             and then Result.Distance >= -Max_Value
             and then (if not Succeeded (Status)
                       then Result = (others => <>));
   --  CogDistancePointCircleTool: |P - centre| - Radius (negative inside
   --  the circle, 0 on it, so never below -Radius), and the nearest point
   --  of the circle (CircleX, CircleY), (X, Y) itself on the circle. A
   --  point exactly at the centre gives +Radius and the point at angle 0.

   procedure Distance_Point_Ellipse
     (X, Y                  : Long_Float;
      Ellipse               : KS.Ks_Ellipse;
      Selected_From_Ellipse : KT.Ks_Transform_2D_Linear;
      Result                : out Ks_Distance_Point_Ellipse_Result;
      Status                : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_distance_point_ellipse_execute",
     Post => Status_OK (Status) and then Valid_Result (Result)
             and then (if not Succeeded (Status)
                       then Result = (others => <>));
   --  CogDistancePointEllipseTool: the distance from (X, Y) to the nearest
   --  point of the ellipse (EllipseX, EllipseY), negative inside it (the
   --  negative of the distance to the boundary). The nearest point is
   --  found by bisection (Eberly's method: a root of a monotone function
   --  of one variable in the ellipse's own frame), to about the precision
   --  of the coordinates. Of several nearest points (a point on an axis
   --  inside the ellipse) one is chosen. A point exactly at the centre of
   --  an ellipse whose radii are equal gives +Radius, as for a circle.

   procedure Distance_Segment_Segment
     (Segment_A, Segment_B    : KS.Ks_Line_Segment;
      Selected_From_Segment_A : KT.Ks_Transform_2D_Linear;
      Selected_From_Segment_B : KT.Ks_Transform_2D_Linear;
      Result                  : out Ks_Distance_Segment_Segment_Result;
      Status                  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_distance_segment_segment_execute",
     Post => Status_OK (Status) and then Valid_Result (Result)
             and then (if not Succeeded (Status)
                       then Result = (others => <>));
   --  CogDistanceSegmentSegmentTool: 0 (and (0, 0) points) when the
   --  segments touch, cross or overlap (as
   --  ks_intersect_segment_segment_execute decides); otherwise the shortest distance between them, which is
   --  reached at an end point of one of them, and the nearest points on
   --  segment A and on segment B (of several equally near pairs, as for
   --  parallel segments, the first of: A's start, A's end, B's start,
   --  B's end and its nearest point on the other segment).

   procedure Distance_Segment_Line
     (Segment               : KS.Ks_Line_Segment;
      Line                  : KS.Ks_Line;
      Selected_From_Segment : KT.Ks_Transform_2D_Linear;
      Selected_From_Line    : KT.Ks_Transform_2D_Linear;
      Result                : out Ks_Distance_Segment_Line_Result;
      Status                : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_distance_segment_line_execute",
     Post => Status_OK (Status) and then Valid_Result (Result)
             and then (if not Succeeded (Status)
                       then Result = (others => <>));
   --  CogDistanceSegmentLineTool: 0 (and (0, 0) points) when the segment
   --  touches or crosses the line (its end points are not strictly on one
   --  side); otherwise the distance of the nearer end point (the start
   --  point when both are as near, as for a parallel segment) and its
   --  foot on the line.

   procedure Distance_Line_Circle
     (Line                 : KS.Ks_Line;
      Input_Circle         : KS.Ks_Circle;
      Selected_From_Line   : KT.Ks_Transform_2D_Linear;
      Selected_From_Circle : KT.Ks_Transform_2D_Linear;
      Result               : out Ks_Distance_Line_Circle_Result;
      Status               : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_distance_line_circle_execute",
     Post => Status_OK (Status) and then Valid_Result (Result)
             and then (if not Succeeded (Status)
                       then Result = (others => <>));
   --  CogDistanceLineCircleTool: 0 (and (0, 0) points) when the line meets
   --  the circle (its distance from the centre is at most the radius);
   --  otherwise that distance minus the radius, the foot of the
   --  perpendicular from the centre (LineX, LineY) and the point of the
   --  circle facing the line (CircleX, CircleY).

   procedure Distance_Segment_Circle
     (Segment               : KS.Ks_Line_Segment;
      Input_Circle          : KS.Ks_Circle;
      Selected_From_Segment : KT.Ks_Transform_2D_Linear;
      Selected_From_Circle  : KT.Ks_Transform_2D_Linear;
      Result                : out Ks_Distance_Segment_Circle_Result;
      Status                : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_distance_segment_circle_execute",
     Post => Status_OK (Status) and then Valid_Result (Result)
             and then (if not Succeeded (Status)
                       then Result = (others => <>));
   --  CogDistanceSegmentCircleTool. Outside the circle (its nearest point
   --  farther than the radius from the centre): the distance from the
   --  segment's point nearest the centre to the circle, that point and the
   --  circle's point towards it. Inside (both end points nearer than the
   --  radius): the negative of the distance from the end point farther
   --  from the centre to the circle, that end point and the circle's point
   --  beyond it. Otherwise (touching or crossing): 0 and (0, 0) points.

   procedure Distance_Circle_Circle
     (Circle_A, Circle_B     : KS.Ks_Circle;
      Selected_From_Circle_A : KT.Ks_Transform_2D_Linear;
      Selected_From_Circle_B : KT.Ks_Transform_2D_Linear;
      Result                 : out Ks_Distance_Circle_Circle_Result;
      Status                 : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_distance_circle_circle_execute",
     Post => Status_OK (Status) and then Valid_Result (Result)
             and then (if not Succeeded (Status)
                       then Result = (others => <>));
   --  CogDistanceCircleCircleTool. Apart: the gap between the circles and
   --  the facing points on the line of the centres. One inside the other:
   --  the negative of the gap, and the facing points (on the side of the
   --  inner centre). Concentric (equal centres) with different radii: the
   --  negative of the difference of the radii, and the points at angle 0.
   --  Identical, touching or crossing circles: 0 and (0, 0) points.

   procedure Distance_Line_Ellipse
     (Line                  : KS.Ks_Line;
      Ellipse               : KS.Ks_Ellipse;
      Selected_From_Line    : KT.Ks_Transform_2D_Linear;
      Selected_From_Ellipse : KT.Ks_Transform_2D_Linear;
      Result                : out Ks_Distance_Line_Ellipse_Result;
      Status                : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_distance_line_ellipse_execute",
     Post => Status_OK (Status) and then Valid_Result (Result)
             and then (if not Succeeded (Status)
                       then Result = (others => <>));
   --  CogDistanceLineEllipseTool: 0 (and (0, 0) points) when the line
   --  meets the ellipse; otherwise the gap between them, the point of the
   --  ellipse nearest the line (where its tangent is parallel to the line)
   --  and that point's foot on the line.

   procedure Distance_Segment_Ellipse
     (Segment               : KS.Ks_Line_Segment;
      Ellipse               : KS.Ks_Ellipse;
      Selected_From_Segment : KT.Ks_Transform_2D_Linear;
      Selected_From_Ellipse : KT.Ks_Transform_2D_Linear;
      Result                : out Ks_Distance_Segment_Ellipse_Result;
      Status                : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_distance_segment_ellipse_execute",
     Post => Status_OK (Status) and then Valid_Result (Result)
             and then (if not Succeeded (Status)
                       then Result = (others => <>));
   --  CogDistanceSegmentEllipseTool: 0 (and (0, 0) points) when the
   --  segment meets the ellipse's boundary (as
   --  ks_intersect_segment_ellipse_execute finds it) or has one end point
   --  inside
   --  and one outside. Inside (both end points inside): the negative of
   --  the smaller distance of an end point to the boundary, that end point
   --  and its nearest point of the ellipse. Outside: the shortest distance,
   --  reached at an end point or where the segment passes the ellipse's
   --  nearest point to its line, and the two points.

   ---------------------------------------------------------------------
   --  Intersections
   ---------------------------------------------------------------------

   procedure Intersect_Line_Line
     (Line_A, Line_B       : KS.Ks_Line;
      Selected_From_Line_A : KT.Ks_Transform_2D_Linear;
      Selected_From_Line_B : KT.Ks_Transform_2D_Linear;
      Result               : out Ks_Intersect_Line_Line_Result;
      Status               : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_intersect_line_line_execute",
     Post => Status_OK (Status) and then Valid_Result (Result)
             and then (if not Succeeded (Status)
                       then Result = (others => <>));
   --  CogIntersectLineLineTool: NumPoints 1 and the point (X, Y) for
   --  lines that cross; 0 for parallel lines; -1 for coincident ones.
   --  Angle is the angle from line A to line B in (-Pi, Pi] (as
   --  ks_angle_line_line_execute), for parallel lines too.

   procedure Intersect_Segment_Line
     (Segment               : KS.Ks_Line_Segment;
      Line                  : KS.Ks_Line;
      Selected_From_Segment : KT.Ks_Transform_2D_Linear;
      Selected_From_Line    : KT.Ks_Transform_2D_Linear;
      Result                : out Ks_Intersect_Segment_Line_Result;
      Status                : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_intersect_segment_line_execute",
     Post => Status_OK (Status) and then Valid_Result (Result)
             and then (if not Succeeded (Status)
                       then Result = (others => <>));
   --  CogIntersectSegmentLineTool: NumPoints 1 and the point where the
   --  segment crosses or touches the line; 0 when both end points lie
   --  strictly on one side; -1 when the whole segment (of a length > 0)
   --  lies on the line. A segment of no length on the line gives its
   --  point.

   procedure Intersect_Segment_Segment
     (Segment_A, Segment_B    : KS.Ks_Line_Segment;
      Selected_From_Segment_A : KT.Ks_Transform_2D_Linear;
      Selected_From_Segment_B : KT.Ks_Transform_2D_Linear;
      Result                  : out Ks_Intersect_Segment_Segment_Result;
      Status                  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_intersect_segment_segment_execute",
     Post => Status_OK (Status) and then Valid_Result (Result)
             and then (if not Succeeded (Status)
                       then Result = (others => <>));
   --  CogIntersectSegmentSegmentTool: NumPoints 1 and the point where the
   --  segments cross or touch; 0 when they do not meet (parallel segments
   --  on different lines included); -1 when they lie on one line and
   --  overlap along a piece of a length > 0. Collinear segments that only
   --  share an end point give that point.

   procedure Intersect_Line_Circle
     (Line                 : KS.Ks_Line;
      Input_Circle         : KS.Ks_Circle;
      Selected_From_Line   : KT.Ks_Transform_2D_Linear;
      Selected_From_Circle : KT.Ks_Transform_2D_Linear;
      Result               : out Ks_Intersect_Line_Circle_Result;
      Status               : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_intersect_line_circle_execute",
     Post => Status_OK (Status) and then Valid_Result (Result)
             and then (if not Succeeded (Status)
                       then Result = (others => <>));
   --  CogIntersectLineCircleTool: 0, 1 (tangent: the foot of the
   --  perpendicular from the centre) or 2 points, the first one first
   --  along the line's direction (as ks_geometry_intersect_line_circle).

   procedure Intersect_Segment_Circle
     (Segment               : KS.Ks_Line_Segment;
      Input_Circle          : KS.Ks_Circle;
      Selected_From_Segment : KT.Ks_Transform_2D_Linear;
      Selected_From_Circle  : KT.Ks_Transform_2D_Linear;
      Result                : out Ks_Intersect_Segment_Circle_Result;
      Status                : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_intersect_segment_circle_execute",
     Post => Status_OK (Status) and then Valid_Result (Result)
             and then (if not Succeeded (Status)
                       then Result = (others => <>));
   --  CogIntersectSegmentCircleTool: the points of the segment's line on
   --  the circle that lie on the segment (within the tolerance at its
   --  ends, then moved onto the end), in the order from start to end: 0,
   --  1 (tangent, an end point on the circle, or a segment from inside to
   --  outside) or 2.

   procedure Intersect_Circle_Circle
     (Circle_A, Circle_B     : KS.Ks_Circle;
      Selected_From_Circle_A : KT.Ks_Transform_2D_Linear;
      Selected_From_Circle_B : KT.Ks_Transform_2D_Linear;
      Result                 : out Ks_Intersect_Circle_Circle_Result;
      Status                 : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_intersect_circle_circle_execute",
     Post => Status_OK (Status) and then Valid_Result (Result)
             and then (if not Succeeded (Status)
                       then Result = (others => <>));
   --  CogIntersectCircleCircleTool: -1 for identical circles (centres and
   --  radii equal within the tolerance), otherwise 0, 1 (touching) or 2
   --  points as ks_geometry_intersect_circles finds them (with two
   --  points, the first lies to the left of the line from centre A to
   --  centre B in a y-up view: on the side of its left normal).

   procedure Intersect_Line_Ellipse
     (Line                  : KS.Ks_Line;
      Ellipse               : KS.Ks_Ellipse;
      Selected_From_Line    : KT.Ks_Transform_2D_Linear;
      Selected_From_Ellipse : KT.Ks_Transform_2D_Linear;
      Result                : out Ks_Intersect_Line_Ellipse_Result;
      Status                : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_intersect_line_ellipse_execute",
     Post => Status_OK (Status) and then Valid_Result (Result)
             and then (if not Succeeded (Status)
                       then Result = (others => <>));
   --  CogIntersectLineEllipseTool: 0, 1 (tangent: the ellipse's point
   --  nearest the line) or 2 points, the first one first along the line's
   --  direction.

   procedure Intersect_Segment_Ellipse
     (Segment               : KS.Ks_Line_Segment;
      Ellipse               : KS.Ks_Ellipse;
      Selected_From_Segment : KT.Ks_Transform_2D_Linear;
      Selected_From_Ellipse : KT.Ks_Transform_2D_Linear;
      Result                : out Ks_Intersect_Segment_Ellipse_Result;
      Status                : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_intersect_segment_ellipse_execute",
     Post => Status_OK (Status) and then Valid_Result (Result)
             and then (if not Succeeded (Status)
                       then Result = (others => <>));
   --  CogIntersectSegmentEllipseTool: as for a circle, with the points of
   --  ks_intersect_line_ellipse_execute.

end AMV.Kernels.Dimensioning;
