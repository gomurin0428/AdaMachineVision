--  Kernel of AMV.Dimensioning.Fitting: the fitting tools CogFitLineTool,
--  CogFitCircleTool and CogFitEllipseTool, with their run parameters
--  (CogFitLine, CogFitCircle, CogFitEllipse) and results
--  (CogFitLineResult, CogFitCircleResult, CogFitEllipseResult). In
--  VisionPro these live in the core namespace Cognex.VisionPro; AMV keeps
--  them with the dimensioning tools. C API: include/amv_dimensioning.h,
--  names ks_fit_*.
--
--  The points. The list of points a fit uses (AddPoint, DeletePoint,
--  NumPoints, ...) is variable-sized, so it lives behind an owned handle:
--  the polygon handle of AMV.Kernels.Shapes, whose vertices are the points
--  (C: ks_fit_points, the same type as ks_polygon; NULL is an empty list).
--  The ks_fit_points_* entry points below manage it with the VisionPro
--  names; at most Max_Points points (2**20), each within 1.0E150.
--
--  What a fit does. Line: the orthogonal least squares line of
--  ks_geometry_fit_line_robust. Circle: the geometric least squares circle
--  of ks_geometry_fit_circle_robust or, with RadiusConstraintEnabled, the
--  circle of radius RadiusConstraint that minimises the sum of squared
--  radial residuals (our own alternating minimisation: each step moves the
--  centre to the mean of the points pulled back by the radius along their
--  directions from it; started from the free fit's centre, or from the
--  centroid when no free circle fits). Ellipse: the direct least squares
--  fit of Fitzgibbon, Pilu and Fisher in the numerically stable form of
--  Halir and Flusser (the algebraic distance minimised under the ellipse
--  constraint 4AC - B**2 = 1, reduced to a 3 x 3 generalised eigenproblem
--  whose single positive eigenvalue is found by bisection on its
--  characteristic polynomial and whose eigenvector is a cross product of
--  two rows), on the points moved to their centroid and divided by their
--  largest offset; with RotationConstraintEnabled the ellipse's axes are
--  fixed along RotationConstraint and the problem is 2 x 2, solved in
--  closed form. The fitted ellipse has Radius_X >= Radius_Y and a rotation
--  in (-Pi/2, Pi/2] (the major axis), or, with the rotation constraint,
--  exactly the given rotation, with Radius_X along it.
--
--  NumToIgnore. VisionPro considers every subset of NumPoints -
--  NumToIgnore points. Here points are discarded one at a time, greedily
--  (as ks_find_line_execute and ks_find_circle_execute do): each step tries
--  the fit without each point still in use and drops the point whose
--  removal gives the best fit (the lowest RMS error of the remaining
--  points: radial residuals for circles; for ellipses the distance along
--  the ray from the centre, which is exact on the ellipse and finite at
--  its centre and costs no iteration; ties drop the lowest index). This
--  finds a single gross outlier (it is the exhaustive search for
--  NumToIgnore = 1) and costs NumToIgnore * NumPoints fits.
--
--  Results. A new owned handle (C: ks_fit_result *, one type for the three
--  fits): NumPoints (the number of points given), for each point its
--  coordinates, whether the final fit used it and its distance to the
--  fitted shape (>= 0, for every point: the perpendicular distance to the
--  line, |distance to centre - radius| for the circle, the distance to the
--  nearest point of the ellipse, found as for
--  ks_distance_point_ellipse_execute), RMSError (the root mean square of
--  the distances of the used points), NumPointsUsed (AMV's: the number of
--  used points) and the fitted shape (GetLine, GetCircle or GetEllipse).
--  The shape and the distances are in the space of the points.
--
--  Failures. Bad_Parameter for an inconsistent points handle, for run
--  parameters out of range ("RunParams.NumToIgnore must be >= 0"), for
--  fewer points than the fit needs once NumToIgnore are left out (2 for a
--  line, 3 for a circle, 5 for an ellipse, 4 with its rotation
--  constraint), for degenerate points (coincident or collinear, with the
--  messages of AMV.Kernels.Geometry for lines and circles), when no
--  ellipse fits, and when a result would exceed its bound; Out_Of_Memory.
--
--  Proved (docs/PROOF.md): absence of run-time errors for any argument and
--  any handle that is null or came from this kernel; no memory leaks; and
--  of every result handle an execute entry point returns (Gold_Result):
--  one point, flag and distance per point given, every distance in
--  [0, Max_Length], RMSError in [0, Max_Length], NumPointsUsed exactly the
--  number of used flags (a recursive ghost count) and at least the minimum
--  number of points of the fit, and a valid shape within the bounds (radii
--  > 0 for the ellipse). The ellipse fit is proved free of run-time
--  errors; its accuracy is tested.
--
--  Trusted parts (SPARK_Mode Off bodies, listed in docs/PROOF.md): the
--  allocation helpers, which turn a failed allocation into Out_Of_Memory.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Geometry;

package AMV.Kernels.Dimensioning.Fitting with SPARK_Mode, Preelaborate is

   pragma Unevaluated_Use_Of_Old (Allow);
   --  The postconditions of the point list compare counts with their
   --  values on entry through the total function KS.Count_Of.

   package KG renames AMV.Kernels.Geometry;

   use type KS.Ks_Polygon;

   Max_Points : constant := KS.Max_Vertices;
   --  The largest number of points of a fit, 2**20 (C:
   --  KS_FIT_MAX_POINTS).

   ---------------------------------------------------------------------
   --  The points (C: ks_fit_points, alias of ks_polygon)
   ---------------------------------------------------------------------

   --  Index_Out_Of_Range for an index outside 0 .. NumPoints - 1;
   --  Bad_Parameter for a coordinate that is not finite or not within
   --  1.0E150, and for a handle that is not consistent. A failed call
   --  changes nothing.

   procedure Points_Num_Points
     (Points : access constant KS.Ks_Polygon_Data;
      Count  : out Int32;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_fit_points_num_points",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Count in 0 .. Max_Points
             and then (if Succeeded (Status)
                       then Count = Int32 (KS.Count_Of (Points)));
   --  NumPoints (0 for null).

   procedure Points_Set_Num_Points
     (Points : in out KS.Ks_Polygon;
      Count  : Int32;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_fit_points_set_num_points",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Count in 0 .. Max_Points
                            and then KS.Count_Of (Points) = Natural (Count));
   --  Set NumPoints: new points (0, 0) are appended, or points are removed
   --  from the end. Count must be in 0 .. Max_Points. Creates the handle
   --  when Points is null and Count > 0. On Out_Of_Memory the points added
   --  so far are removed again.

   procedure Points_Add_Point
     (Points : in out KS.Ks_Polygon;
      X, Y   : Long_Float;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_fit_points_add_point",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then KS.Valid_Polygon (Points)
                            and then Points.Count
                                       = KS.Count_Of (Points)'Old + 1
                            and then Points.Vertices (Points.Count - 1).X
                                       = X
                            and then Points.Vertices (Points.Count - 1).Y
                                       = Y);
   --  AddPoint: appends (X, Y). Creates the handle when Points is null.
   --  Bad_Parameter when the list already holds Max_Points points.

   procedure Points_Delete_Point
     (Points : KS.Ks_Polygon;
      Index  : Int32;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_fit_points_delete_point",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then (if Succeeded (Status)
                       then KS.Count_Of (Points)
                              = KS.Count_Of (Points)'Old - 1);
   --  DeletePoint: removes point Index; the later points move down by
   --  one.

   procedure Points_Get_Point
     (Points : access constant KS.Ks_Polygon_Data;
      Index  : Int32;
      X, Y   : out Long_Float;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_fit_points_get_point",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then (if Succeeded (Status)
                       then KS.Valid_Polygon (Points)
                            and then Index in 0 .. Int32 (Points.Count) - 1
                            and then X = Points.Vertices (Natural (Index)).X
                            and then Y = Points.Vertices (Natural (Index)).Y
                       else X = 0.0 and then Y = 0.0);
   --  GetPoint (also GetX and GetY).

   procedure Points_Set_Point
     (Points : KS.Ks_Polygon;
      Index  : Int32;
      X, Y   : Long_Float;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_fit_points_set_point",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then KS.Count_Of (Points) = KS.Count_Of (Points)'Old
             and then (if Succeeded (Status)
                       then KS.Valid_Polygon (Points)
                            and then Index in 0 .. Int32 (Points.Count) - 1
                            and then Points.Vertices (Natural (Index)).X = X
                            and then Points.Vertices (Natural (Index)).Y
                                       = Y);
   --  SetPoint.

   procedure Points_Set_X
     (Points : KS.Ks_Polygon;
      Index  : Int32;
      Value  : Long_Float;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_fit_points_set_x",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then KS.Count_Of (Points) = KS.Count_Of (Points)'Old
             and then (if Succeeded (Status)
                       then KS.Valid_Polygon (Points)
                            and then Index in 0 .. Int32 (Points.Count) - 1
                            and then Points.Vertices (Natural (Index)).X
                                       = Value);
   --  SetX: changes the X coordinate of point Index only.

   procedure Points_Set_Y
     (Points : KS.Ks_Polygon;
      Index  : Int32;
      Value  : Long_Float;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_fit_points_set_y",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then KS.Count_Of (Points) = KS.Count_Of (Points)'Old
             and then (if Succeeded (Status)
                       then KS.Valid_Polygon (Points)
                            and then Index in 0 .. Int32 (Points.Count) - 1
                            and then Points.Vertices (Natural (Index)).Y
                                       = Value);
   --  SetY: changes the Y coordinate of point Index only.

   procedure Points_Clear
     (Points : KS.Ks_Polygon;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_fit_points_clear",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status) then KS.Count_Of (Points) = 0);
   --  Removes every point (AMV name; VisionPro sets NumPoints to 0).

   procedure Points_Duplicate
     (Points : access constant KS.Ks_Polygon_Data;
      Copy   : out KS.Ks_Polygon;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_fit_points_duplicate",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if not Succeeded (Status) then Copy = null);
   --  A new list with the same points (null for null).

   procedure Points_Destroy (Points : in out KS.Ks_Polygon)
   with
     Export, Convention => C,
     External_Name => "ks_fit_points_destroy",
     Post => Points = null;
   --  Frees the list (nothing for null).

   ---------------------------------------------------------------------
   --  Run parameters
   ---------------------------------------------------------------------

   type Ks_Fit_Line_Run_Params is record
      Num_To_Ignore : Int32 := 0;
   end record
     with Convention => C;
   --  CogFitLine without its points (C: ks_fit_line_run_params).
   --  NumToIgnore >= 0.

   type Ks_Fit_Circle_Run_Params is record
      Num_To_Ignore             : Int32 := 0;
      Radius_Constraint_Enabled : Int32 := False_Value;
      Radius_Constraint         : Long_Float := 100.0;
   end record
     with Convention => C;
   --  CogFitCircle without its points (C: ks_fit_circle_run_params).
   --  NumToIgnore >= 0; RadiusConstraintEnabled 0 or 1; RadiusConstraint
   --  in (0, 1.0E150] when it is enabled (finite in any case).

   type Ks_Fit_Ellipse_Run_Params is record
      Num_To_Ignore               : Int32 := 0;
      Rotation_Constraint_Enabled : Int32 := False_Value;
      Rotation_Constraint         : Long_Float := 0.0;
   end record
     with Convention => C;
   --  CogFitEllipse without its points (C: ks_fit_ellipse_run_params).
   --  NumToIgnore >= 0; RotationConstraintEnabled 0 or 1;
   --  RotationConstraint (radians) within 1.0E150.

   procedure Line_Run_Params_Default
     (Params : out Ks_Fit_Line_Run_Params;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_fit_line_run_params_default",
     Post => Valid (Status) and then Succeeded (Status);

   procedure Circle_Run_Params_Default
     (Params : out Ks_Fit_Circle_Run_Params;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_fit_circle_run_params_default",
     Post => Valid (Status) and then Succeeded (Status);

   procedure Ellipse_Run_Params_Default
     (Params : out Ks_Fit_Ellipse_Run_Params;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_fit_ellipse_run_params_default",
     Post => Valid (Status) and then Succeeded (Status);
   --  The record's default values.

   ---------------------------------------------------------------------
   --  Results (C: ks_fit_result *, opaque)
   ---------------------------------------------------------------------

   Fit_Line    : constant Int32 := 1;
   Fit_Circle  : constant Int32 := 2;
   Fit_Ellipse : constant Int32 := 3;
   --  The kind of a result (C: KS_FIT_LINE, KS_FIT_CIRCLE,
   --  KS_FIT_ELLIPSE).

   function Min_Points (Kind : Int32) return Natural is
     (case Kind is
         when Fit_Line   => 2,
         when Fit_Circle => 3,
         when others     => 4);
   --  The fewest points a fit of that kind uses (an ellipse needs 5
   --  without its rotation constraint; ks_fit_ellipse_execute states it).

   type Value_Array is array (Natural range <>) of Long_Float;

   type Point_Array_Access is access KG.Point_Array;
   type Flag_Array_Access is access KG.Flag_Array;
   type Value_Array_Access is access Value_Array;

   type Ks_Fit_Result_Data is limited record
      Kind            : Int32 := 0;
      Count           : Natural := 0;
      Points          : Point_Array_Access;
      Used            : Flag_Array_Access;
      Distances       : Value_Array_Access;
      Line            : KS.Ks_Line;
      Circle          : KS.Ks_Circle;
      Ellipse         : KS.Ks_Ellipse;
      RMS_Error       : Long_Float := 0.0;
      Num_Points_Used : Natural := 0;
   end record;
   --  What a handle designates (opaque for C): the kind, Count points
   --  with their used flags and distances (indexed from 0), the fitted
   --  shape of the kind, the RMS error and the number of used points.

   type Ks_Fit_Result is access Ks_Fit_Result_Data
     with Convention => C;
   --  C: ks_fit_result *.

   function Count_Used (Used : KG.Flag_Array; Last : Integer) return Natural
   is (if Last < 0 or else Last > Used'Last then 0
       else Count_Used (Used, Last - 1) + (if Used (Last) then 1 else 0))
   with
     Ghost,
     Pre  => Used'First = 0 and then Last < Max_Points,
     Subprogram_Variant => (Decreases => Last),
     Post => Count_Used'Result <= Natural'Max (0, Last + 1);
   --  The number of True flags among Used (0 .. Last).

   function Valid_Result
     (Result : access constant Ks_Fit_Result_Data) return Boolean
   is
     (Result /= null
      and then Result.Kind in Fit_Line .. Fit_Ellipse
      and then Result.Count in Min_Points (Result.Kind) .. Max_Points
      and then Result.Points /= null
      and then Result.Used /= null
      and then Result.Distances /= null
      and then Result.Points'First = 0
      and then Result.Points'Last = Result.Count - 1
      and then Result.Used'First = 0
      and then Result.Used'Last = Result.Count - 1
      and then Result.Distances'First = 0
      and then Result.Distances'Last = Result.Count - 1
      and then Result.Num_Points_Used <= Result.Count);
   --  A handle as the execute entry points make it (the structural part,
   --  which the accessors check).

   function Valid_Shape
     (Result : access constant Ks_Fit_Result_Data) return Boolean
   is
     (Result /= null
      and then (case Result.Kind is
                   when Fit_Line   => KS.Valid_Line (Result.Line),
                   when Fit_Circle =>
                      KS.Valid_Circle (Result.Circle)
                      and then Result.Circle.Radius <= Max_Value,
                   when Fit_Ellipse =>
                      KS.Valid_Ellipse (Result.Ellipse)
                      and then Result.Ellipse.Radius_X > 0.0
                      and then Result.Ellipse.Radius_X <= Max_Value
                      and then Result.Ellipse.Radius_Y > 0.0
                      and then Result.Ellipse.Radius_Y <= Max_Value,
                   when others => False));
   --  The fitted shape of the result's kind, valid and within the bounds.

   function Gold_Result
     (Result : access constant Ks_Fit_Result_Data) return Boolean
   is
     (Valid_Result (Result)
      and then Valid_Shape (Result)
      and then Result.Num_Points_Used
                 = Count_Used (Result.Used.all, Result.Count - 1)
      and then Result.Num_Points_Used >= Min_Points (Result.Kind)
      and then (for all I in 0 .. Result.Count - 1 =>
                  Result.Distances (I) >= 0.0
                  and then Result.Distances (I) <= Max_Length)
      and then Result.RMS_Error >= 0.0
      and then Result.RMS_Error <= Max_Length)
   with Ghost;
   --  The proved facts of every handle an execute entry point returns.

   ---------------------------------------------------------------------
   --  Execution
   ---------------------------------------------------------------------

   procedure Line_Execute
     (Points : access constant KS.Ks_Polygon_Data;
      Params : Ks_Fit_Line_Run_Params;
      Result : out Ks_Fit_Result;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_fit_line_execute",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory | Failure_Other
             and then (if Succeeded (Status)
                       then Gold_Result (Result)
                            and then Result.Kind = Fit_Line
                            and then Result.Count = KS.Count_Of (Points)
                       else Result = null);
   --  CogFitLine.Execute: fits a line to the points (see above). Returns
   --  a new result handle (null on failure).

   procedure Circle_Execute
     (Points : access constant KS.Ks_Polygon_Data;
      Params : Ks_Fit_Circle_Run_Params;
      Result : out Ks_Fit_Result;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_fit_circle_execute",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory | Failure_Other
             and then (if Succeeded (Status)
                       then Gold_Result (Result)
                            and then Result.Kind = Fit_Circle
                            and then Result.Count = KS.Count_Of (Points)
                            and then
                              (if Params.Radius_Constraint_Enabled
                                    = True_Value
                               then Result.Circle.Radius
                                      = Params.Radius_Constraint)
                       else Result = null);
   --  CogFitCircle.Execute. With RadiusConstraintEnabled the radius is
   --  exactly RadiusConstraint.

   procedure Ellipse_Execute
     (Points : access constant KS.Ks_Polygon_Data;
      Params : Ks_Fit_Ellipse_Run_Params;
      Result : out Ks_Fit_Result;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_fit_ellipse_execute",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory | Failure_Other
             and then (if Succeeded (Status)
                       then Gold_Result (Result)
                            and then Result.Kind = Fit_Ellipse
                            and then Result.Count = KS.Count_Of (Points)
                            and then Result.Num_Points_Used
                                       >= (if Params
                                                .Rotation_Constraint_Enabled
                                              = True_Value
                                           then 4 else 5)
                            and then
                              (if Params.Rotation_Constraint_Enabled
                                    = True_Value
                               then Result.Ellipse.Rotation
                                      = Params.Rotation_Constraint)
                       else Result = null);
   --  CogFitEllipse.Execute. With RotationConstraintEnabled the rotation
   --  is exactly RotationConstraint.

   procedure Result_Destroy (Result : in out Ks_Fit_Result)
   with
     Export, Convention => C,
     External_Name => "ks_fit_result_destroy",
     Post => Result = null;
   --  Frees the result; nothing for null.

   procedure Result_Kind
     (Result : access constant Ks_Fit_Result_Data;
      Kind   : out Int32;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_fit_result_kind",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Kind in 0 .. Fit_Ellipse;
   --  KS_FIT_LINE, KS_FIT_CIRCLE or KS_FIT_ELLIPSE (0 for null).

   procedure Result_Num_Points
     (Result : access constant Ks_Fit_Result_Data;
      Count  : out Int32;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_fit_result_num_points",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Count in 0 .. Max_Points
             and then (if Succeeded (Status) and then Result /= null
                       then Count = Int32 (Result.Count));
   --  NumPoints: the number of points given to the fit (0 for null).

   procedure Result_Num_Points_Used
     (Result : access constant Ks_Fit_Result_Data;
      Count  : out Int32;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_fit_result_num_points_used",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Count in 0 .. Max_Points
             and then (if Succeeded (Status) and then Result /= null
                       then Count = Int32 (Result.Num_Points_Used));
   --  The number of points the fit used (AMV name; 0 for null).

   procedure Result_RMS_Error
     (Result    : access constant Ks_Fit_Result_Data;
      RMS_Error : out Long_Float;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_fit_result_rms_error",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status) and then Result /= null
                       then RMS_Error = Result.RMS_Error
                       else RMS_Error = 0.0);
   --  RMSError (0 for null).

   procedure Result_Get_XY_Used_Distance
     (Result   : access constant Ks_Fit_Result_Data;
      Index    : Int32;
      X, Y     : out Long_Float;
      Used     : out Int32;
      Distance : out Long_Float;
      Status   : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_fit_result_get_xy_used_distance",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then Used in False_Value | True_Value
             and then (if Succeeded (Status)
                       then Valid_Result (Result)
                            and then Index in 0 .. Int32 (Result.Count) - 1
                            and then X = Result.Points (Natural (Index)).X
                            and then Y = Result.Points (Natural (Index)).Y
                            and then (Used = True_Value)
                                       = Result.Used (Natural (Index))
                            and then Distance
                                       = Result.Distances (Natural (Index))
                       else X = 0.0 and then Y = 0.0
                            and then Used = False_Value
                            and then Distance = 0.0);
   --  GetXYUsedDistance (also GetX, GetY, GetUsed and GetDistance) of
   --  point Index; Index_Out_Of_Range outside 0 .. NumPoints - 1 (always
   --  for null).

   procedure Result_Get_Line
     (Result : access constant Ks_Fit_Result_Data;
      Line   : out KS.Ks_Line;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_fit_result_get_line",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status) then KS.Valid_Line (Line));
   --  GetLine of a line fit; Bad_Parameter for null or another kind.

   procedure Result_Get_Circle
     (Result : access constant Ks_Fit_Result_Data;
      Circle : out KS.Ks_Circle;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_fit_result_get_circle",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then KS.Valid_Circle (Circle));
   --  GetCircle of a circle fit; Bad_Parameter for null or another kind.

   procedure Result_Get_Ellipse
     (Result  : access constant Ks_Fit_Result_Data;
      Ellipse : out KS.Ks_Ellipse;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_fit_result_get_ellipse",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then KS.Valid_Ellipse (Ellipse));
   --  GetEllipse of an ellipse fit; Bad_Parameter for null or another
   --  kind.

end AMV.Kernels.Dimensioning.Fitting;
