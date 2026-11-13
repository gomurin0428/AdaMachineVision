--  Kernel of AMV.Geometry: plane geometry and least squares fitting shared
--  by the caliper-based tools, the dimensioning tools and calibration. No
--  VisionPro counterpart. The behaviour of every operation (tolerances,
--  degenerate cases, the fitting methods) is documented in AMV.Geometry;
--  this spec states the C view and the bounds.
--
--  Points, lines and circles are small C structs (ks_point_2d,
--  ks_line_2d, ks_circle_2d). Point lists are Ada arrays for the Ada-only
--  subprograms and, for C, a pointer and a count: the C entry points check
--  the request (a count in 0 .. Max_Points, a non-null pointer when it is
--  positive) and then view the C memory as an Ada array (trusted, see
--  docs/PROOF.md). The Used flags of the robust fits are int32_t (0 or 1)
--  for C.
--
--  Bounds. Every coordinate and radius an operation takes must be finite
--  and within [-Max_Coordinate, Max_Coordinate] (1.0E150); a rotation must
--  be finite. Every coordinate, length and radius an operation returns is
--  within that bound too, so it is a valid argument again: a result that
--  would leave it (possible only for arguments beyond about 3.5E149, or
--  for nearly parallel lines meeting far away) gives Bad_Parameter
--  ("<Subprogram>: the result would exceed +/-1.0E150"). With the bound,
--  differences of two coordinates (at most 2.0E150) and products of two of
--  them (at most 4.0E300) cannot overflow. The fits work on the offsets of
--  the points from their centroid scaled by an exact power of two (static
--  powers of two, see the body), so their squares and higher powers stay
--  within a few units whatever the size of the coordinates; Num_To_Ignore
--  and the counts are integers. A NaN or an infinity anywhere gives
--  Bad_Parameter. Degenerate input gives Bad_Parameter with the messages
--  of AMV.Geometry ("Fit_Line: the points coincide").

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Numerics;
with System;

package AMV.Kernels.Geometry with SPARK_Mode, Preelaborate is

   Pi : constant := Ada.Numerics.Pi;

   Max_Coordinate : constant := 1.0E150;
   --  The bound of coordinates, lengths and radii (C:
   --  KS_GEOMETRY_MAX_COORDINATE).

   Max_Points : constant := 2**31 - 1;
   --  The largest number of points of a fit (C: KS_GEOMETRY_MAX_POINTS).

   type Ks_Point_2D is record
      X, Y : Long_Float := 0.0;
   end record
     with Convention => C;
   --  C: ks_point_2d.

   type Ks_Line_2D is record
      X, Y     : Long_Float := 0.0;   --  a point on the line
      Rotation : Long_Float := 0.0;   --  direction of the line
   end record
     with Convention => C;
   --  C: ks_line_2d. The infinite line through (X, Y) with direction
   --  (cos Rotation, sin Rotation); its left normal is (-sin, cos).

   type Ks_Circle_2D is record
      Center_X, Center_Y : Long_Float := 0.0;
      Radius             : Long_Float := 0.0;
   end record
     with Convention => C;
   --  C: ks_circle_2d.

   type Point_Array is array (Natural range <>) of Ks_Point_2D;
   type Flag_Array is array (Natural range <>) of Boolean;

   function Bounded (X : Long_Float) return Boolean is
     (X >= -Max_Coordinate and then X <= Max_Coordinate);
   --  X is finite and within the bound (False for NaN at run time).

   function Bounded (P : Ks_Point_2D) return Boolean is
     (Bounded (P.X) and then Bounded (P.Y));

   function Bounded (C : Ks_Circle_2D) return Boolean is
     (Bounded (C.Center_X) and then Bounded (C.Center_Y)
      and then Bounded (C.Radius));

   function Is_Finite (X : Long_Float) return Boolean is
     (X >= -Long_Float'Last and then X <= Long_Float'Last);
   --  False for NaN and the infinities at run time.

   function Valid_Line (L : Ks_Line_2D) return Boolean is
     (Bounded (L.X) and then Bounded (L.Y) and then Is_Finite (L.Rotation));
   --  A line argument: its point within the bound, its rotation finite.

   ---------------------------------------------------------------------
   --  Distances and projections
   ---------------------------------------------------------------------

   --  Every entry point fails with Bad_Parameter, naming the argument
   --  ("Distance: P.X must be finite and within +/-1.0E150"), when an
   --  argument is not finite or not within the bound; the results are 0
   --  when the call fails.

   procedure Distance
     (P, Q   : Ks_Point_2D;
      Result : out Long_Float;
      Status : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_geometry_distance",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Result >= 0.0 and then Result <= Max_Coordinate;
   --  |P - Q|, without intermediate overflow or underflow.

   procedure Signed_Distance
     (P      : Ks_Point_2D;
      Line   : Ks_Line_2D;
      Result : out Long_Float;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_geometry_signed_distance",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Bounded (Result)
             and then (if not Succeeded (Status) then Result = 0.0);
   --  Positive when P lies on the side of the left normal.

   procedure Line_Distance
     (P      : Ks_Point_2D;
      Line   : Ks_Line_2D;
      Result : out Long_Float;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_geometry_distance_to_line",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Result >= 0.0 and then Result <= Max_Coordinate;
   --  abs Signed_Distance.

   procedure Project
     (P      : Ks_Point_2D;
      Line   : Ks_Line_2D;
      Result : out Ks_Point_2D;
      Status : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_geometry_project",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Bounded (Result);
   --  The foot of the perpendicular from P to Line.

   procedure Position_Along
     (P      : Ks_Point_2D;
      Line   : Ks_Line_2D;
      Result : out Long_Float;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_geometry_position_along",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Bounded (Result);
   --  The signed coordinate of Project (P, Line) along the line direction,
   --  measured from (Line.X, Line.Y).

   procedure Circle_Distance
     (P      : Ks_Point_2D;
      Circle : Ks_Circle_2D;
      Result : out Long_Float;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_geometry_distance_to_circle",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Result >= 0.0 and then Result <= Max_Coordinate;
   --  abs (|P - centre| - radius).

   ---------------------------------------------------------------------
   --  Intersections and angles
   ---------------------------------------------------------------------

   procedure Intersect_Lines
     (Line_1, Line_2 : Ks_Line_2D;
      Point          : out Ks_Point_2D;
      Parallel       : out Int32;
      Status         : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_geometry_intersect_lines",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Bounded (Point)
             and then Parallel in False_Value | True_Value
             and then (if Parallel = True_Value or else not Succeeded (Status)
                       then Point.X = 0.0 and then Point.Y = 0.0);
   --  The intersection point; Parallel is 1 (and Point (0, 0)) when the
   --  sine of the angle between the lines is at most 1.0E-12 in magnitude.

   procedure Intersect_Line_Circle
     (Line             : Ks_Line_2D;
      Circle           : Ks_Circle_2D;
      Point_1, Point_2 : out Ks_Point_2D;
      Count            : out Int32;
      Status           : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_geometry_intersect_line_circle",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Bounded (Point_1) and then Bounded (Point_2)
             and then Count in 0 .. 2
             and then (if not Succeeded (Status) then Count = 0);
   --  Count = 0, 1 (tangent; both points equal) or 2; Point_1 first along
   --  the line. Bad_Parameter when the radius is negative ("Intersect:
   --  Circle.Radius must be >= 0").

   procedure Intersect_Circles
     (Circle_1, Circle_2 : Ks_Circle_2D;
      Point_1, Point_2   : out Ks_Point_2D;
      Count              : out Int32;
      Status             : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_geometry_intersect_circles",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Bounded (Point_1) and then Bounded (Point_2)
             and then Count in 0 .. 2
             and then (if not Succeeded (Status) then Count = 0);
   --  Count = 0, 1 (tangent; both points equal) or 2; with two points,
   --  Point_1 lies on the positive side of the line from centre 1 towards
   --  centre 2. Bad_Parameter when a radius is negative ("Intersect:
   --  circle radii must be >= 0").

   procedure Angle_Between
     (Line_1, Line_2 : Ks_Line_2D;
      Result         : out Long_Float;
      Status         : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_geometry_angle_between",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Result > -Pi and then Result <= Pi;
   --  Line_2.Rotation - Line_1.Rotation reduced to (-Pi, Pi] (as
   --  ks_misc_angle_difference).

   ---------------------------------------------------------------------
   --  Fits (Ada arrays)
   ---------------------------------------------------------------------

   --  Points may have any bounds and at most Max_Points elements. The
   --  robust variants need Used with the index range of Points
   --  (Bad_Parameter otherwise) and set Used (I) when point I takes part in
   --  the final fit. On failure Line or Circle and RMS_Error are 0 and
   --  Used is all False.

   procedure Fit_Line
     (Points    : Point_Array;
      Line      : out Ks_Line_2D;
      RMS_Error : out Long_Float;
      Status    : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Bounded (Line.X) and then Bounded (Line.Y)
             and then Line.Rotation > -Pi / 2.0
             and then Line.Rotation <= Pi / 2.0
             and then RMS_Error >= 0.0 and then RMS_Error <= Max_Coordinate;
   --  Orthogonal (total) least squares line through the centroid.

   procedure Fit_Line_Robust
     (Points        : Point_Array;
      Num_To_Ignore : Int32;
      Line          : out Ks_Line_2D;
      RMS_Error     : out Long_Float;
      Used          : out Flag_Array;
      Status        : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Bounded (Line.X) and then Bounded (Line.Y)
             and then Line.Rotation > -Pi / 2.0
             and then Line.Rotation <= Pi / 2.0
             and then RMS_Error >= 0.0 and then RMS_Error <= Max_Coordinate;
   --  Discards Num_To_Ignore points one at a time by leave-one-out.

   procedure Fit_Circle
     (Points    : Point_Array;
      Circle    : out Ks_Circle_2D;
      RMS_Error : out Long_Float;
      Status    : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Bounded (Circle) and then Circle.Radius >= 0.0
             and then RMS_Error >= 0.0 and then RMS_Error <= Max_Coordinate;
   --  Geometric least squares circle (Kasa estimate refined by Newton and
   --  damped Gauss-Newton steps).

   procedure Fit_Circle_Robust
     (Points        : Point_Array;
      Num_To_Ignore : Int32;
      Circle        : out Ks_Circle_2D;
      RMS_Error     : out Long_Float;
      Used          : out Flag_Array;
      Status        : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Bounded (Circle) and then Circle.Radius >= 0.0
             and then RMS_Error >= 0.0 and then RMS_Error <= Max_Coordinate;
   --  Discards Num_To_Ignore points one at a time by leave-one-out.

   ---------------------------------------------------------------------
   --  Fits (C memory)
   ---------------------------------------------------------------------

   --  points: count ks_point_2d values; used: count int32_t values (set to
   --  0 or 1). Bad_Parameter when count is negative or above Max_Points, or
   --  a pointer is null while count is positive ("Fit_Line: Points must
   --  not be null"). Trusted: the memory holds count elements and does not
   --  overlap the other arguments.

   procedure Fit_Line_C
     (Points    : System.Address;
      Count     : Int32;
      Line      : out Ks_Line_2D;
      RMS_Error : out Long_Float;
      Status    : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_geometry_fit_line",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter;

   procedure Fit_Line_Robust_C
     (Points        : System.Address;
      Count         : Int32;
      Num_To_Ignore : Int32;
      Line          : out Ks_Line_2D;
      RMS_Error     : out Long_Float;
      Used          : System.Address;
      Status        : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_geometry_fit_line_robust",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory;

   procedure Fit_Circle_C
     (Points    : System.Address;
      Count     : Int32;
      Circle    : out Ks_Circle_2D;
      RMS_Error : out Long_Float;
      Status    : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_geometry_fit_circle",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter;

   procedure Fit_Circle_Robust_C
     (Points        : System.Address;
      Count         : Int32;
      Num_To_Ignore : Int32;
      Circle        : out Ks_Circle_2D;
      RMS_Error     : out Long_Float;
      Used          : System.Address;
      Status        : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_geometry_fit_circle_robust",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory;

end AMV.Kernels.Geometry;
