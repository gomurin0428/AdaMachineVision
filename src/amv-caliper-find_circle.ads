--  Find circle: the counterpart of CogFindCircleTool (run parameters
--  CogFindCircle, results CogFindCircleResults and CogFindCircleResult).
--
--  NumCalipers calipers are placed on the expected circular arc (evenly
--  from its start to its end, or evenly around a full circle without a
--  duplicate at 2 Pi), each searching along the radius, inward or outward.
--  Every caliper that finds an edge contributes the position of its best
--  result, and a circle is fitted to those points by geometric least
--  squares (or, with RadiusConstraintEnabled, the best circle of radius
--  RadiusConstraint), NumToIgnore of them discarded as outliers.
--  Everything is reported in the input image's selected space. A caliper
--  averages its edge across its projection length L, over which the
--  circle bends, so it finds the edge L**2 / (24 R) inside the circle of
--  radius R (0.08 pixel for L = 10, R = 50); the points are moved out by
--  that much and fitted again. The correction holds (within about 0.02
--  pixel on synthetic discs) while L**2 / (8 R), the largest bend across
--  a caliper, stays within the caliper's FilterHalfSizeInPixels; use a
--  shorter projection length beyond that.
--
--     Tool.Input_Image := Image;
--     Tool.Run_Params.Expected_Circular_Arc
--       .Set_Center_Radius_Angle_Start_Angle_Span (160.0, 120.0, 50.0,
--                                                   0.0, 2.0 * Pi);
--     Tool.Run;
--     Circle := Tool.Results.Get_Circle;
--
--  The SPARK kernel AMV.Kernels.Find_Circle does the work (C API:
--  include/amv_caliper.h); its spec describes the placement, both fits
--  and the failures. Its proofs cover, besides the absence of run-time
--  errors, that the results hold one item per caliper, that only found
--  points are used, and that NumPointsUsed <= NumPointsFound <=
--  NumCalipers count exactly the used and found items.

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Images;
with AMV.Kernels.Find_Circle;
with AMV.Shapes;
with AMV.Tools;

private with AMV.Shared_Handles;

package AMV.Caliper.Find_Circle is

   package KF renames AMV.Kernels.Find_Circle;

   type Ks_Find_Circle_Search_Direction_Constants is (Inward, Outward);
   --  CogFindCircleSearchDirectionConstants (Inward = 0, Outward = 1, as
   --  in VisionPro): towards the centre or away from it.

   Defaults : constant KF.Ks_Find_Circle_Run_Params := (others => <>);
   --  The kernel's defaults, which the record below starts from.

   type Ks_Find_Circle is record
      Expected_Circular_Arc     : AMV.Shapes.Ks_Circular_Arc;
      Num_Calipers              : Integer := Integer (Defaults.Num_Calipers);
      Caliper_Search_Length     : Real := Defaults.Caliper_Search_Length;
      Caliper_Projection_Length : Real := Defaults.Caliper_Projection_Length;
      Caliper_Search_Direction  : Ks_Find_Circle_Search_Direction_Constants
        := Inward;
      Num_To_Ignore             : Integer :=
        Integer (Defaults.Num_To_Ignore);
      Decrement_Num_To_Ignore   : Boolean := False;
      Radius_Constraint_Enabled : Boolean := False;
      Radius_Constraint         : Real := Defaults.Radius_Constraint;
      Caliper_Run_Params        : AMV.Caliper.Ks_Caliper;
   end record;
   --  CogFindCircle. Expected_Circular_Arc is taken in its own selected
   --  space (default "."; default arc: centre (0, 0), radius 50, start 0,
   --  span Pi). Defaults: 6 calipers, search length 30, projection length
   --  10, search Inward, NumToIgnore 0, DecrementNumToIgnore False,
   --  RadiusConstraintEnabled False, RadiusConstraint 100 (in the selected
   --  space), the default caliper parameters. Checked when the tool runs:
   --  NumCalipers in 3 .. 1000, NumToIgnore in 0 .. NumCalipers - 3
   --  (NumCalipers - 2 with the radius constraint), lengths > 0, an arc
   --  radius > 0, RadiusConstraint > 0 when enabled
   --  (Ks_Bad_Parameter_Exception).

   function Get_Caliper_Region
     (Params : Ks_Find_Circle;
      Index  : Natural) return AMV.Shapes.Ks_Rectangle_Affine;
   --  (AMV name) The region of caliper Index (0-based), in the expected
   --  arc's selected space. Constraint_Error unless Index < NumCalipers.

   ---------------------------------------------------------------------
   --  Results
   ---------------------------------------------------------------------

   type Ks_Find_Circle_Result is record
      Found              : Boolean := False;
      Used               : Boolean := False;
      X                  : Real := 0.0;
      Y                  : Real := 0.0;
      Distance_To_Circle : Real := 0.0;
      Caliper_Results    : AMV.Caliper.Ks_Caliper_Results;
   end record;
   --  CogFindCircleResult: whether the caliper found an edge, whether its
   --  point was used in the fit, the point (0 when not found), its radial
   --  distance from the fitted circle (>= 0) and the caliper's results.

   type Ks_Find_Circle_Results is tagged private;
   --  CogFindCircleResults: one item per caliper, in the order of the
   --  calipers; empty before the first successful run.

   function Count (Results : Ks_Find_Circle_Results) return Natural;
   function Item
     (Results : Ks_Find_Circle_Results;
      Index   : Natural) return Ks_Find_Circle_Result;
   --  Item Index (0-based); Constraint_Error unless Index < Count.

   function Get_Circle
     (Results : Ks_Find_Circle_Results) return AMV.Shapes.Ks_Circle;
   --  The fitted circle. Ks_Bad_Parameter_Exception before a successful
   --  run.

   function Get_Circular_Arc
     (Results : Ks_Find_Circle_Results) return AMV.Shapes.Ks_Circular_Arc;
   --  The fitted circle from the first used point through the last, in
   --  the order of the calipers.

   function RMS_Error (Results : Ks_Find_Circle_Results) return Real;
   function Num_Points_Found
     (Results : Ks_Find_Circle_Results) return Natural;
   function Num_Points_Used (Results : Ks_Find_Circle_Results) return Natural;
   --  0 before a successful run.

   ---------------------------------------------------------------------
   --  The tool (CogFindCircleTool)
   ---------------------------------------------------------------------

   type Ks_Find_Circle_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image : AMV.Images.Ks_Image_8_Grey;
      Run_Params  : Ks_Find_Circle;
      Results     : Ks_Find_Circle_Results;
   end record;

   overriding procedure Execute (Tool : in out Ks_Find_Circle_Tool);
   --  Runs the calipers and fits the circle. Raises
   --  Ks_Image_No_Pixels_Exception for an unallocated image,
   --  Ks_Bad_Parameter_Exception for bad run parameters or collinear
   --  points, and Ks_Exception when too few points remain for the fit; Run
   --  reports them in Run_Status (and leaves no results).

   overriding procedure Reset_Results (Tool : in out Ks_Find_Circle_Tool);

private

   procedure Destroy (Handle : in out KF.Ks_Find_Circle_Results);

   package Results_Holders is new AMV.Shared_Handles
     (KF.Ks_Find_Circle_Results, null, Destroy);

   type Ks_Find_Circle_Results is tagged record
      Holder : Results_Holders.Holder;
   end record;

end AMV.Caliper.Find_Circle;
