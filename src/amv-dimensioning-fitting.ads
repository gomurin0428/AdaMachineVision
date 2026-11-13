--  The fitting tools: the counterparts of CogFitLineTool, CogFitCircleTool
--  and CogFitEllipseTool, their run parameters CogFitLine, CogFitCircle
--  and CogFitEllipse, and their results CogFitLineResult,
--  CogFitCircleResult and CogFitEllipseResult (VisionPro keeps them in
--  the core namespace Cognex.VisionPro).
--
--     Tool.Run_Params.Add_Point (10.0, 20.0);
--     ...
--     Tool.Run_Params.Set_Num_To_Ignore (1);
--     Tool.Run;
--     Circle := Tool.Result.Get_Circle;
--     RMS := Tool.Result.RMS_Error;
--
--  The run parameters hold the points (AddPoint, DeletePoint, SetPoint,
--  NumPoints, ...; at most Max_Points, each within 1.0E150) and
--  NumToIgnore, plus the radius constraint of the circle fit and the
--  rotation constraint of the ellipse fit. Copies of them are
--  independent (assignment copies the points). Execute (the method of the
--  run parameters) and the tool's Run fit the points:
--
--  * a line by orthogonal least squares (as AMV.Geometry.Fit_Line);
--  * a circle by geometric least squares (as AMV.Geometry.Fit_Circle),
--    or with Radius_Constraint_Enabled the circle of radius
--    Radius_Constraint closest to the points;
--  * an ellipse by the direct least squares fit of Fitzgibbon, Pilu and
--    Fisher (in the stable form of Halir and Flusser), optionally with its
--    axes along Rotation_Constraint.
--
--  Num_To_Ignore points are left out one at a time, each time the point
--  whose removal gives the best fit (VisionPro searches all subsets; see
--  AMV.Kernels.Dimensioning.Fitting for the details). The results give
--  for each point whether the final fit used it and its distance to the
--  fitted shape (>= 0), the RMS error of the used points and the shape.
--  Everything is in the space of the points; the shape's selected space
--  is the name given to Execute ("." for the tool). The tool's
--  Input_Image is only where VisionPro draws its graphics; it is not used.
--
--  Failures (Run_Status Error, or raised by Execute): Ks_Bad_Parameter_
--  Exception for fewer points than the fit needs after Num_To_Ignore (2,
--  3, 5, or 4 for an ellipse with its rotation fixed), degenerate points
--  (coincident, collinear for a circle or an ellipse), a bad constraint,
--  no ellipse fitting the points, and a result beyond the bounds.
--  Constraint_Error for a point index outside 0 .. Num_Points - 1.
--
--  The SPARK kernel AMV.Kernels.Dimensioning.Fitting does the work (C API:
--  include/amv_dimensioning.h); its proofs cover the absence of run-time
--  errors, and of every result: a distance >= 0 per point, Num_Points_Used
--  exactly the number of used points and at least the number the fit
--  needs, the RMS error >= 0, and a valid shape.

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

private with Ada.Strings.Unbounded;

with AMV.Images;
with AMV.Kernels.Dimensioning.Fitting;
with AMV.Shapes;
with AMV.Tools;

private with Ada.Finalization;
private with Ada.Streams;
private with AMV.Kernels.Shapes;
private with AMV.Shared_Handles;

package AMV.Dimensioning.Fitting is

   package KF renames AMV.Kernels.Dimensioning.Fitting;

   Max_Points : constant := KF.Max_Points;
   --  2**20.

   ---------------------------------------------------------------------
   --  Run parameters
   ---------------------------------------------------------------------

   type Ks_Fit_Points is tagged private;
   --  (AMV name) What CogFitLine, CogFitCircle and CogFitEllipse have in
   --  common: the points and NumToIgnore. Default: no points,
   --  NumToIgnore 0.

   function Num_Points (Params : Ks_Fit_Points) return Natural;
   procedure Set_Num_Points (Params : in out Ks_Fit_Points; Value : Natural);
   --  NumPoints. Setting it appends points (0, 0) or removes points from
   --  the end; at most Max_Points (Ks_Bad_Parameter_Exception).

   procedure Add_Point (Params : in out Ks_Fit_Points; X, Y : Real);
   --  AddPoint: appends (X, Y).

   procedure Delete_Point (Params : in out Ks_Fit_Points; Index : Natural);
   --  DeletePoint: removes point Index; the later points move down.

   procedure Get_Point
     (Params : Ks_Fit_Points;
      Index  : Natural;
      X, Y   : out Real);
   procedure Set_Point
     (Params : in out Ks_Fit_Points;
      Index  : Natural;
      X, Y   : Real);
   function Get_X (Params : Ks_Fit_Points; Index : Natural) return Real;
   function Get_Y (Params : Ks_Fit_Points; Index : Natural) return Real;
   procedure Set_X
     (Params : in out Ks_Fit_Points;
      Index  : Natural;
      Value  : Real);
   procedure Set_Y
     (Params : in out Ks_Fit_Points;
      Index  : Natural;
      Value  : Real);
   --  GetPoint, SetPoint, GetX, GetY, SetX, SetY (0-based; Constraint_Error
   --  outside 0 .. Num_Points - 1; coordinates within 1.0E150).

   function Num_To_Ignore (Params : Ks_Fit_Points) return Natural;
   procedure Set_Num_To_Ignore
     (Params : in out Ks_Fit_Points;
      Value  : Natural);
   --  NumToIgnore (checked against Num_Points when the fit runs).

   type Ks_Fit_Line is new Ks_Fit_Points with private;
   --  CogFitLine.

   type Ks_Fit_Circle is new Ks_Fit_Points with private;
   --  CogFitCircle. Default: Radius_Constraint_Enabled False,
   --  Radius_Constraint 100.0 (AMV defaults).

   function Radius_Constraint_Enabled (Params : Ks_Fit_Circle) return Boolean;
   procedure Set_Radius_Constraint_Enabled
     (Params : in out Ks_Fit_Circle;
      Value  : Boolean);
   function Radius_Constraint (Params : Ks_Fit_Circle) return Real;
   procedure Set_Radius_Constraint
     (Params : in out Ks_Fit_Circle;
      Value  : Real);
   --  The radius of the fitted circle when the constraint is enabled; it
   --  must then be in (0, 1.0E150] (checked when the fit runs).

   type Ks_Fit_Ellipse is new Ks_Fit_Points with private;
   --  CogFitEllipse. Default: Rotation_Constraint_Enabled False,
   --  Rotation_Constraint 0.0.

   function Rotation_Constraint_Enabled
     (Params : Ks_Fit_Ellipse) return Boolean;
   procedure Set_Rotation_Constraint_Enabled
     (Params : in out Ks_Fit_Ellipse;
      Value  : Boolean);
   function Rotation_Constraint (Params : Ks_Fit_Ellipse) return Real;
   procedure Set_Rotation_Constraint
     (Params : in out Ks_Fit_Ellipse;
      Value  : Real);
   --  The rotation (radians) of the fitted ellipse's first axis when the
   --  constraint is enabled: the fitted ellipse then has exactly this
   --  Rotation, with Radius_X along it (which may be the shorter radius).
   --  Without the constraint Radius_X >= Radius_Y and Rotation, the
   --  direction of the major axis, lies in (-Pi/2, Pi/2].

   ---------------------------------------------------------------------
   --  Results
   ---------------------------------------------------------------------

   type Ks_Fit_Result is tagged private;
   --  (AMV name) What the three results have in common. Empty before a
   --  fit: Num_Points 0, RMS_Error 0.

   function Num_Points (Result : Ks_Fit_Result) return Natural;
   --  NumPoints: the number of points given to the fit.

   function RMS_Error (Result : Ks_Fit_Result) return Real;
   --  RMSError: the root mean square of the distances of the used points.

   function Num_Points_Used (Result : Ks_Fit_Result) return Natural;
   --  (AMV name) The number of points the fit used.

   procedure Get_XY_Used_Distance
     (Result   : Ks_Fit_Result;
      Index    : Natural;
      X, Y     : out Real;
      Used     : out Boolean;
      Distance : out Real);
   function Get_X (Result : Ks_Fit_Result; Index : Natural) return Real;
   function Get_Y (Result : Ks_Fit_Result; Index : Natural) return Real;
   function Get_Used (Result : Ks_Fit_Result; Index : Natural) return Boolean;
   function Get_Distance (Result : Ks_Fit_Result; Index : Natural)
      return Real;
   --  GetXYUsedDistance, GetX, GetY, GetUsed, GetDistance of point Index
   --  (0-based; Constraint_Error outside 0 .. Num_Points - 1): its
   --  coordinates, whether the fit used it and its distance to the fitted
   --  shape (>= 0, for unused points too).

   type Ks_Fit_Line_Result is new Ks_Fit_Result with private;
   --  CogFitLineResult.

   function Get_Line (Result : Ks_Fit_Line_Result) return AMV.Shapes.Ks_Line;
   --  GetLine: the fitted line, through the centroid of the used points,
   --  with a rotation in (-Pi/2, Pi/2]. Ks_Bad_Parameter_Exception before
   --  a fit.

   type Ks_Fit_Circle_Result is new Ks_Fit_Result with private;
   --  CogFitCircleResult.

   function Get_Circle
     (Result : Ks_Fit_Circle_Result) return AMV.Shapes.Ks_Circle;
   --  GetCircle: the fitted circle. Ks_Bad_Parameter_Exception before a
   --  fit.

   type Ks_Fit_Ellipse_Result is new Ks_Fit_Result with private;
   --  CogFitEllipseResult.

   function Get_Ellipse
     (Result : Ks_Fit_Ellipse_Result) return AMV.Shapes.Ks_Ellipse;
   --  GetEllipse: the fitted ellipse. Ks_Bad_Parameter_Exception before a
   --  fit.

   function Execute
     (Params              : Ks_Fit_Line'Class;
      Selected_Space_Name : String := ".") return Ks_Fit_Line_Result;
   function Execute
     (Params              : Ks_Fit_Circle'Class;
      Selected_Space_Name : String := ".") return Ks_Fit_Circle_Result;
   function Execute
     (Params              : Ks_Fit_Ellipse'Class;
      Selected_Space_Name : String := ".") return Ks_Fit_Ellipse_Result;
   --  CogFitLine.Execute, CogFitCircle.Execute, CogFitEllipse.Execute: the
   --  fit of the points; Selected_Space_Name becomes the selected space of
   --  the fitted shape. Raises the exceptions listed above.

   ---------------------------------------------------------------------
   --  The tools
   ---------------------------------------------------------------------

   type Ks_Fit_Line_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image : AMV.Images.Ks_Image_8_Grey;
      Run_Params  : Ks_Fit_Line;
      Result      : Ks_Fit_Line_Result;
   end record;
   --  CogFitLineTool.

   overriding procedure Execute (Tool : in out Ks_Fit_Line_Tool);
   overriding procedure Reset_Results (Tool : in out Ks_Fit_Line_Tool);

   type Ks_Fit_Circle_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image : AMV.Images.Ks_Image_8_Grey;
      Run_Params  : Ks_Fit_Circle;
      Result      : Ks_Fit_Circle_Result;
   end record;
   --  CogFitCircleTool.

   overriding procedure Execute (Tool : in out Ks_Fit_Circle_Tool);
   overriding procedure Reset_Results (Tool : in out Ks_Fit_Circle_Tool);

   type Ks_Fit_Ellipse_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image : AMV.Images.Ks_Image_8_Grey;
      Run_Params  : Ks_Fit_Ellipse;
      Result      : Ks_Fit_Ellipse_Result;
   end record;
   --  CogFitEllipseTool.

   overriding procedure Execute (Tool : in out Ks_Fit_Ellipse_Tool);
   overriding procedure Reset_Results (Tool : in out Ks_Fit_Ellipse_Tool);

private

   package KS renames AMV.Kernels.Shapes;

   --  The points: a polygon handle of the kernel (its vertices are the
   --  points) that each run parameter object owns. Assignment duplicates
   --  it, finalization destroys it, "=" compares the points, and the
   --  stream attributes read and write the points by value.

   type Point_List is new Ada.Finalization.Controlled with record
      Handle : KS.Ks_Polygon;
   end record;

   overriding procedure Adjust (Points : in out Point_List);
   overriding procedure Finalize (Points : in out Point_List);

   overriding function "=" (Left, Right : Point_List) return Boolean;

   procedure Write_Points
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : Point_List);
   procedure Read_Points
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Point_List);

   for Point_List'Write use Write_Points;
   for Point_List'Read use Read_Points;

   type Ks_Fit_Points is tagged record
      Points        : Point_List;
      Num_To_Ignore : Natural := 0;
   end record;

   procedure Read_Fit_Points
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Fit_Points);
   for Ks_Fit_Points'Read use Read_Fit_Points;
   --  The 'Read of the records here reads the components in the order of
   --  the predefined 'Write (the parent part first) into a fresh object,
   --  checks every Natural and Boolean value, and assigns the object to
   --  Item only when all were read; a malformed stream (one that ends
   --  early, an invalid value) raises Ks_Image_File_Exception and leaves
   --  Item as it was (a point count above Max_Points or a coordinate
   --  beyond the bounds raises Ks_Bad_Parameter_Exception, as before).
   --  Ks_Fit_Line has no component of its own: its predefined 'Read is
   --  Read_Fit_Points.

   type Ks_Fit_Line is new Ks_Fit_Points with null record;

   type Ks_Fit_Circle is new Ks_Fit_Points with record
      Radius_Constraint_Enabled : Boolean := False;
      Radius_Constraint         : Real := 100.0;
   end record;

   procedure Read_Fit_Circle
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Fit_Circle);
   for Ks_Fit_Circle'Read use Read_Fit_Circle;

   type Ks_Fit_Ellipse is new Ks_Fit_Points with record
      Rotation_Constraint_Enabled : Boolean := False;
      Rotation_Constraint         : Real := 0.0;
   end record;

   procedure Read_Fit_Ellipse
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Fit_Ellipse);
   for Ks_Fit_Ellipse'Read use Read_Fit_Ellipse;

   procedure Destroy (Handle : in out KF.Ks_Fit_Result);

   package Result_Holders is new AMV.Shared_Handles
     (KF.Ks_Fit_Result, null, Destroy);

   type Ks_Fit_Result is tagged record
      Holder     : Result_Holders.Holder;
      Space_Name : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.To_Unbounded_String (".");
   end record;

   type Ks_Fit_Line_Result is new Ks_Fit_Result with null record;
   type Ks_Fit_Circle_Result is new Ks_Fit_Result with null record;
   type Ks_Fit_Ellipse_Result is new Ks_Fit_Result with null record;

end AMV.Dimensioning.Fitting;
