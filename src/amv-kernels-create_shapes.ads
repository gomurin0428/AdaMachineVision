--  Kernel of AMV.Dimensioning.Create_Shapes: the shape creation tools of
--  Cognex.VisionPro.Dimensioning (CogCreateCircleTool, CogCreateEllipseTool,
--  CogCreateLineTool, CogCreateSegmentTool, CogCreateLineBisectPointsTool,
--  CogCreateLineParallelTool, CogCreateLinePerpendicularTool and
--  CogCreateSegmentAvgSegsTool). Its entry points are the C API of
--  include/amv_create_shapes.h (names ks_create_*_execute).
--
--  Each tool builds one shape from its inputs and returns it as the shape
--  record of AMV.Kernels.Shapes (C: ks_circle, ks_ellipse, ks_line,
--  ks_line_segment), the value of its VisionPro GetOutput* method. No
--  pixel is read.
--
--  Coordinates. Every shape is created in one space, the "selected space"
--  (in the Ada API the selected space of the tool's InputImage, which is
--  also the space the created shape is said to be in). Each input shape
--  comes with the transform from its own selected space to the selected
--  space (Selected_From_<Shape>), and the kernel maps the shape with the
--  map entry points of AMV.Kernels.Shapes first; plain coordinates (X, Y,
--  StartX, ...) are taken in the selected space as they are. With
--  identity transforms everything is in one space.
--
--  The tools, in the selected space:
--
--  * Create_Circle, Create_Ellipse, Create_Line, Create_Segment: the input
--    shape itself, mapped. A circle must stay a circle (its transform a
--    similarity, possibly reflecting, within the tolerance of
--    ks_circle_map). An ellipse is mapped by ks_ellipse_map (the image of
--    an ellipse under any affine map is an ellipse; its RadiusX axis is
--    the one nearest the image of the original RadiusX axis). A line's
--    point is mapped and its direction mapped as by
--    ks_transform_2d_linear_map_angle. A segment's two end points are
--    mapped (a singular transform may shrink it to a point).
--  * Create_Line_Bisect_Points: the perpendicular bisector of the segment
--    from (StartX, StartY) to (EndX, EndY): the line through its midpoint
--    whose rotation is the direction from the start to the end point plus
--    Pi/2. The two points must differ.
--  * Create_Line_Parallel: the line through (X, Y) with the rotation of
--    the input line.
--  * Create_Line_Perpendicular: the line through (X, Y) whose rotation is
--    the input line's plus Pi/2.
--  * Create_Segment_Avg_Segs: the segment from the midpoint of the two
--    start points to the midpoint of the two end points (start with start
--    and end with end, as the VisionPro reference defines it). Segments
--    that point in opposite directions are not turned round, so their
--    average can be short or even of no length (still a valid segment):
--    to get the centre line of two parallel edges, pass them in the same
--    direction.
--
--  Angles. Every rotation a tool returns lies in (-Pi, Pi]: a mapped line
--  or ellipse has its rotation there already, and a rotation plus Pi/2
--  beyond Pi is brought back by subtracting 2 Pi (Normalize).
--
--  Bounds and failures. Every coordinate taken, and every coordinate and
--  radius of a created shape, lies within [-Max_Value, Max_Value]
--  (1.0E150, the bound of AMV.Kernels.Shapes and of the measuring tools of
--  AMV.Kernels.Dimensioning), so that a created shape is a valid input to
--  every other tool. A NaN, an infinity or a value beyond its bound gives
--  Bad_Parameter naming the property ("X must be finite and within
--  +/-1.0E150"), and so does a shape that would leave the bound once
--  mapped. Further Bad_Parameter cases: an ellipse with a radius of 0
--  (before or after the mapping, as the ellipse tools of
--  AMV.Kernels.Dimensioning require), a circle whose transform is not a
--  similarity, and two equal points for the bisector. A circle of radius
--  0 is accepted (it is a valid circle for every tool). A line whose
--  transform maps its direction to zero gives Transform_Singular. A failed
--  call returns the shape record's default value (as the entry points of
--  AMV.Kernels.Shapes do on failure).
--
--  Proved (docs/PROOF.md): absence of run-time errors for any argument
--  (NaN and infinities included); only the documented failure codes; every
--  created shape valid and within the bounds, rotations in (-Pi, Pi] and
--  radii in [0, Max_Value] (a circle) or (0, Max_Value] (an ellipse); and
--  (Gold) the construction itself: each created shape is exactly the
--  input mapped (Map_Line, Map_Segment, Map_Circle, Map_Ellipse below), or
--  for the parallel and the perpendicular line exactly (X, Y, R) and
--  (X, Y, Quarter_Turn (R)) with R the mapped input's rotation, for the
--  bisector exactly the midpoint of the points and Quarter_Turn of their
--  direction, and for the average exactly the midpoints of the mapped
--  segments' end points (Average); a failed call returns the default
--  shape.
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

package AMV.Kernels.Create_Shapes with SPARK_Mode, Preelaborate is

   package KS renames AMV.Kernels.Shapes;
   package KT renames AMV.Kernels.Transforms;

   use type KS.Ks_Circle;
   use type KS.Ks_Ellipse;
   use type KS.Ks_Line;
   use type KS.Ks_Line_Segment;

   Pi      : constant := Ada.Numerics.Pi;
   Half_Pi : constant := Pi / 2.0;

   Max_Value : constant := 1.0E150;
   --  The bound of coordinates and radii (C: KS_CREATE_SHAPES_MAX_VALUE).

   function Bounded (X : Long_Float) return Boolean is
     (X >= -Max_Value and then X <= Max_Value);
   --  A coordinate within the bound (False for a NaN at run time).

   function Valid_Angle (A : Long_Float) return Boolean is
     (A > -Pi and then A <= Pi);

   function Status_OK (Status : Ks_Status) return Boolean is
     (Valid (Status)
      and then Status.Failure
                 in Failure_None | Failure_Bad_Parameter
                  | Failure_Transform_Singular);
   --  A valid status with one of the failures the tools can report.

   ---------------------------------------------------------------------
   --  Created shapes
   ---------------------------------------------------------------------

   --  What every tool returns, also after a failure (the default value of
   --  each record satisfies these).

   function Valid_Created_Circle (C : KS.Ks_Circle) return Boolean is
     (Bounded (C.Center_X) and then Bounded (C.Center_Y)
      and then C.Radius >= 0.0 and then C.Radius <= Max_Value);

   function Valid_Created_Ellipse (E : KS.Ks_Ellipse) return Boolean is
     (Bounded (E.Center_X) and then Bounded (E.Center_Y)
      and then E.Radius_X > 0.0 and then E.Radius_X <= Max_Value
      and then E.Radius_Y > 0.0 and then E.Radius_Y <= Max_Value
      and then Valid_Angle (E.Rotation));

   function Valid_Created_Line (L : KS.Ks_Line) return Boolean is
     (Bounded (L.X) and then Bounded (L.Y)
      and then Valid_Angle (L.Rotation));

   function Valid_Created_Segment (S : KS.Ks_Line_Segment) return Boolean
   is (Bounded (S.Start_X) and then Bounded (S.Start_Y)
       and then Bounded (S.End_X) and then Bounded (S.End_Y));

   ---------------------------------------------------------------------
   --  The constructions (Ada only; they state what the tools compute)
   ---------------------------------------------------------------------

   function Normalize (A : Long_Float) return Long_Float
   with Post => Valid_Angle (Normalize'Result)
                and then (if Valid_Angle (A) then Normalize'Result = A);
   --  A itself when it lies in (-Pi, Pi], otherwise A minus the nearest
   --  multiple of 2 Pi (the exact IEEE remainder; -Pi becomes +Pi).

   function Quarter_Turn (Rotation : Long_Float) return Long_Float is
     (Normalize (Rotation + Half_Pi))
   with Pre  => Valid_Angle (Rotation),
        Post => Valid_Angle (Quarter_Turn'Result);
   --  The rotation of a line perpendicular to one with this rotation:
   --  Rotation + Pi/2, less 2 Pi when that exceeds Pi.

   function Direction_Of (DX, DY : Long_Float) return Long_Float
   with Pre  => DX /= 0.0 or else DY /= 0.0,
        Post => Valid_Angle (Direction_Of'Result);
   --  The direction of the non-zero vector (DX, DY) in (-Pi, Pi] (+Pi
   --  along the negative x axis).

   function Midpoint (A, B : Long_Float) return Long_Float is
     ((A + B) / 2.0)
   with Pre  => Bounded (A) and then Bounded (B),
        Post => Bounded (Midpoint'Result);
   --  The midpoint of two coordinates (rounded once, at the sum).

   function Average (A, B : KS.Ks_Line_Segment) return KS.Ks_Line_Segment
   is ((Start_X => Midpoint (A.Start_X, B.Start_X),
        Start_Y => Midpoint (A.Start_Y, B.Start_Y),
        End_X   => Midpoint (A.End_X, B.End_X),
        End_Y   => Midpoint (A.End_Y, B.End_Y)))
   with Pre  => Valid_Created_Segment (A) and then Valid_Created_Segment (B),
        Post => Valid_Created_Segment (Average'Result);
   --  The segment between the midpoints of the start points and of the end
   --  points.

   --  An input shape mapped into the selected space, with the status of the
   --  mapping (the failures the entry points report for that input, the
   --  messages naming it by Name). The shape is the record's default value
   --  when the mapping fails.

   type Input_Name is
     (Input_Circle_Name, Ellipse_Name, Line_Name, Segment_Name,
      Segment_A_Name, Segment_B_Name);
   --  The VisionPro property names of the input shapes, as the messages
   --  give them: InputCircle, Ellipse, Line, Segment, SegmentA, SegmentB.

   type Mapped_Line is record
      Line   : KS.Ks_Line;
      Status : Ks_Status;
   end record;

   type Mapped_Segment is record
      Segment : KS.Ks_Line_Segment;
      Status  : Ks_Status;
   end record;

   type Mapped_Circle is record
      Circle : KS.Ks_Circle;
      Status : Ks_Status;
   end record;

   type Mapped_Ellipse is record
      Ellipse : KS.Ks_Ellipse;
      Status  : Ks_Status;
   end record;

   function Map_Line
     (Line      : KS.Ks_Line;
      Transform : KT.Ks_Transform_2D_Linear;
      Name      : Input_Name) return Mapped_Line
   with Post => Status_OK (Map_Line'Result.Status)
                and then Valid_Created_Line (Map_Line'Result.Line)
                and then (if not Succeeded (Map_Line'Result.Status)
                          then Map_Line'Result.Line = (others => <>));
   --  ks_line_map, its rotation brought into (-Pi, Pi] by Normalize (which
   --  leaves it as it is: ks_transform_2d_linear_map_angle returns it
   --  there). Bad_Parameter for a line or a transform that is not finite or
   --  beyond the bound, or a mapped point beyond it; Transform_Singular
   --  when the direction maps to zero.

   function Map_Segment
     (Segment   : KS.Ks_Line_Segment;
      Transform : KT.Ks_Transform_2D_Linear;
      Name      : Input_Name) return Mapped_Segment
   with Post => Map_Segment'Result.Status.Failure
                  in Failure_None | Failure_Bad_Parameter
                and then Valid (Map_Segment'Result.Status)
                and then Valid_Created_Segment (Map_Segment'Result.Segment)
                and then (if not Succeeded (Map_Segment'Result.Status)
                          then Map_Segment'Result.Segment = (others => <>));
   --  ks_line_segment_map. Bad_Parameter as for a line.

   function Map_Circle
     (Circle    : KS.Ks_Circle;
      Transform : KT.Ks_Transform_2D_Linear;
      Name      : Input_Name) return Mapped_Circle
   with Post => Map_Circle'Result.Status.Failure
                  in Failure_None | Failure_Bad_Parameter
                and then Valid (Map_Circle'Result.Status)
                and then Valid_Created_Circle (Map_Circle'Result.Circle)
                and then (if not Succeeded (Map_Circle'Result.Status)
                          then Map_Circle'Result.Circle = (others => <>));
   --  ks_circle_map when it gives a circle. Bad_Parameter as for a line, a
   --  negative radius, a transform that is not a similarity, and a mapped
   --  radius beyond Max_Value.

   function Map_Ellipse
     (Ellipse   : KS.Ks_Ellipse;
      Transform : KT.Ks_Transform_2D_Linear;
      Name      : Input_Name) return Mapped_Ellipse
   with Post => Map_Ellipse'Result.Status.Failure
                  in Failure_None | Failure_Bad_Parameter
                and then Valid (Map_Ellipse'Result.Status)
                and then Valid_Created_Ellipse (Map_Ellipse'Result.Ellipse)
                and then (if not Succeeded (Map_Ellipse'Result.Status)
                          then Map_Ellipse'Result.Ellipse
                                 = (others => <>));
   --  ks_ellipse_map. Bad_Parameter as for a line, a radius of 0 before or
   --  after the mapping, and a mapped radius beyond Max_Value.

   ---------------------------------------------------------------------
   --  Entry points
   ---------------------------------------------------------------------

   procedure Create_Circle
     (Input_Circle               : KS.Ks_Circle;
      Selected_From_Input_Circle : KT.Ks_Transform_2D_Linear;
      Result                     : out KS.Ks_Circle;
      Status                     : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_create_circle_execute",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Valid_Created_Circle (Result)
             and then Status
                        = Map_Circle (Input_Circle,
                                      Selected_From_Input_Circle,
                                      Input_Circle_Name).Status
             and then Result
                        = Map_Circle (Input_Circle,
                                      Selected_From_Input_Circle,
                                      Input_Circle_Name).Circle
             and then (if not Succeeded (Status)
                       then Result = (others => <>));
   --  CogCreateCircleTool: InputCircle in the selected space.

   procedure Create_Ellipse
     (Ellipse               : KS.Ks_Ellipse;
      Selected_From_Ellipse : KT.Ks_Transform_2D_Linear;
      Result                : out KS.Ks_Ellipse;
      Status                : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_create_ellipse_execute",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Valid_Created_Ellipse (Result)
             and then Status
                        = Map_Ellipse (Ellipse, Selected_From_Ellipse,
                                       Ellipse_Name).Status
             and then Result
                        = Map_Ellipse (Ellipse, Selected_From_Ellipse,
                                       Ellipse_Name).Ellipse
             and then (if not Succeeded (Status)
                       then Result = (others => <>));
   --  CogCreateEllipseTool: Ellipse in the selected space.

   procedure Create_Line
     (Line               : KS.Ks_Line;
      Selected_From_Line : KT.Ks_Transform_2D_Linear;
      Result             : out KS.Ks_Line;
      Status             : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_create_line_execute",
     Post => Status_OK (Status)
             and then Valid_Created_Line (Result)
             and then Status
                        = Map_Line (Line, Selected_From_Line,
                                    Line_Name).Status
             and then Result
                        = Map_Line (Line, Selected_From_Line,
                                    Line_Name).Line
             and then (if not Succeeded (Status)
                       then Result = (others => <>));
   --  CogCreateLineTool: Line in the selected space.

   procedure Create_Segment
     (Segment               : KS.Ks_Line_Segment;
      Selected_From_Segment : KT.Ks_Transform_2D_Linear;
      Result                : out KS.Ks_Line_Segment;
      Status                : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_create_segment_execute",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Valid_Created_Segment (Result)
             and then Status
                        = Map_Segment (Segment, Selected_From_Segment,
                                       Segment_Name).Status
             and then Result
                        = Map_Segment (Segment, Selected_From_Segment,
                                       Segment_Name).Segment
             and then (if not Succeeded (Status)
                       then Result = (others => <>));
   --  CogCreateSegmentTool: Segment in the selected space.

   procedure Create_Line_Bisect_Points
     (Start_X, Start_Y, End_X, End_Y : Long_Float;
      Result                         : out KS.Ks_Line;
      Status                         : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_create_line_bisect_points_execute",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Valid_Created_Line (Result)
             and then (if Succeeded (Status)
                       then Bounded (Start_X) and then Bounded (Start_Y)
                            and then Bounded (End_X) and then Bounded (End_Y)
                            and then (End_X - Start_X /= 0.0
                                      or else End_Y - Start_Y /= 0.0)
                            and then Result.X = Midpoint (Start_X, End_X)
                            and then Result.Y = Midpoint (Start_Y, End_Y)
                            and then Result.Rotation
                                       = Quarter_Turn
                                           (Direction_Of (End_X - Start_X,
                                                          End_Y - Start_Y))
                       else Result = (others => <>));
   --  CogCreateLineBisectPointsTool: the perpendicular bisector of the
   --  points (StartX, StartY) and (EndX, EndY). Bad_Parameter when they are
   --  the same point.

   procedure Create_Line_Parallel
     (X, Y               : Long_Float;
      Line               : KS.Ks_Line;
      Selected_From_Line : KT.Ks_Transform_2D_Linear;
      Result             : out KS.Ks_Line;
      Status             : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_create_line_parallel_execute",
     Post => Status_OK (Status)
             and then Valid_Created_Line (Result)
             and then (if Succeeded (Status)
                       then Succeeded
                              (Map_Line (Line, Selected_From_Line,
                                         Line_Name).Status)
                            and then Result
                              = (X        => X,
                                 Y        => Y,
                                 Rotation =>
                                   Map_Line (Line, Selected_From_Line,
                                             Line_Name).Line.Rotation)
                       else Result = (others => <>));
   --  CogCreateLineParallelTool: the line through (X, Y) parallel to Line.

   procedure Create_Line_Perpendicular
     (X, Y               : Long_Float;
      Line               : KS.Ks_Line;
      Selected_From_Line : KT.Ks_Transform_2D_Linear;
      Result             : out KS.Ks_Line;
      Status             : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_create_line_perpendicular_execute",
     Post => Status_OK (Status)
             and then Valid_Created_Line (Result)
             and then (if Succeeded (Status)
                       then Succeeded
                              (Map_Line (Line, Selected_From_Line,
                                         Line_Name).Status)
                            and then Result
                              = (X        => X,
                                 Y        => Y,
                                 Rotation =>
                                   Quarter_Turn
                                     (Map_Line (Line, Selected_From_Line,
                                                Line_Name).Line.Rotation))
                       else Result = (others => <>));
   --  CogCreateLinePerpendicularTool: the line through (X, Y)
   --  perpendicular to Line.

   procedure Create_Segment_Avg_Segs
     (Segment_A, Segment_B    : KS.Ks_Line_Segment;
      Selected_From_Segment_A : KT.Ks_Transform_2D_Linear;
      Selected_From_Segment_B : KT.Ks_Transform_2D_Linear;
      Result                  : out KS.Ks_Line_Segment;
      Status                  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_create_segment_avg_segs_execute",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Valid_Created_Segment (Result)
             and then (if Succeeded (Status)
                       then Succeeded
                              (Map_Segment (Segment_A,
                                            Selected_From_Segment_A,
                                            Segment_A_Name).Status)
                            and then Succeeded
                              (Map_Segment (Segment_B,
                                            Selected_From_Segment_B,
                                            Segment_B_Name).Status)
                            and then Result
                              = Average
                                  (Map_Segment (Segment_A,
                                                Selected_From_Segment_A,
                                                Segment_A_Name).Segment,
                                   Map_Segment (Segment_B,
                                                Selected_From_Segment_B,
                                                Segment_B_Name).Segment)
                       else Result = (others => <>));
   --  CogCreateSegmentAvgSegsTool: the average of SegmentA and SegmentB.

end AMV.Kernels.Create_Shapes;
