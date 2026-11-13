--  Kernel of AMV.Caliper.Find_Circle: CogFindCircleTool (run parameters
--  CogFindCircle, results CogFindCircleResults and CogFindCircleResult).
--  Its entry points are part of the C API of the caliper tools
--  (include/amv_caliper.h, names ks_find_circle_*).
--
--  What a run does. NumCalipers calipers are placed on the expected
--  circular arc, in the arc's own space: caliper K (0-based) is centred
--  on the arc at the angle AngleStart + K / (NumCalipers - 1) AngleSpan
--  (the first and the last on the arc's ends), or, when the arc is a full
--  circle (abs AngleSpan >= 2 Pi), at AngleStart + K / NumCalipers 2 Pi
--  (signed like AngleSpan), so that no two coincide. Each caliper searches
--  along the radius, towards the centre (Inward) or away from it
--  (Outward): a rectangle CaliperSearchLength long radially and
--  CaliperProjectionLength wide, without skew
--  (ks_find_circle_caliper_region returns it). Each caliper runs as
--  ks_caliper_execute does, with CaliperRunParams; a caliper that finds a
--  result contributes the position of its best result, in the space that
--  Selected_From_Pixel maps pixel space to.
--
--  The fit. Without the radius constraint: ks_geometry_fit_circle_robust
--  (a geometric least squares circle, NumToIgnore points discarded one at
--  a time), which needs 3 points. With RadiusConstraintEnabled: the
--  circle of radius RadiusConstraint (in the selected space) whose centre
--  minimises the sum of squared radial residuals (abs (P - C) - R)**2 of
--  the used points, which needs 2 points. That fit is our own: it
--  minimises over the centre C and unit vectors U_I the sum of
--  abs (P_I - C - R U_I)**2, whose minimum over the U_I is exactly the
--  sum above, by alternating the two exact partial minimisations (U_I =
--  (P_I - C) / abs (P_I - C), then C = mean (P_I - R U_I)); every step
--  lowers the sum, and it stops when the centre moves by at most 1.0E-12
--  times the radius, or after Max_Iterations steps. It starts from the
--  expected arc's centre mapped into the selected space (the centroid of
--  the points when that fails), so that a short arc converges to the
--  centre on the expected side. NumToIgnore points are discarded one at a
--  time as for the free fit: each time the point whose removal gives the
--  smallest sum of squared residuals. With DecrementNumToIgnore set,
--  NumToIgnore is lowered as far as needed (not below 0) to leave the
--  points the fit needs.
--
--  Curvature. A caliper averages its edge across its projection length
--  L, over which a circle of radius R bends away from the caliper's
--  centre line by y**2 / (2 R) at an offset y. So every caliper finds its
--  edge L**2 / (24 R) closer to the centre than the circle (0.08 pixel
--  for L = 10 and R = 50). The kernel corrects for it: after the fit
--  (with or without the radius constraint) it moves every found point
--  away from the fitted centre by L**2 / (24 R), R the fitted radius (or
--  RadiusConstraint), L the projection length in the selected space (at
--  most 2 R), and fits again from those points; the results give the
--  moved points and the second fit. Measured on anti-aliased discs of
--  radius 12 to 200 (tests/test_find_circle.adb), the corrected radius
--  is within about 0.02 pixel while the circle's largest bend across a
--  caliper, L**2 / (8 R), stays within the caliper's
--  FilterHalfSizeInPixels; beyond that the edge is smeared over more
--  pixels than the filter spans, the caliper no longer finds the mean
--  position, and the correction overshoots (choose a shorter projection
--  length). VisionPro's behaviour here is not known.
--
--  Results. One item per caliper, in the order of the calipers: Found,
--  Used, X and Y (0 when not found), DistanceToCircle (abs (abs (P - C) -
--  R) >= 0; 0 when not found) and the caliper's own results. GetCircle:
--  the fitted circle; GetCircularArc: that circle from the angle of the
--  first used point (in caliper order) through the signed sum of the
--  angle steps between consecutive used points (each step in (-Pi, Pi]),
--  so the arc runs through the used points in the order of the calipers;
--  RMSError over the used points; NumPointsFound and NumPointsUsed.
--
--  Failures. Image_No_Pixels for a null image; Bad_Parameter for bad run
--  parameters ("RunParams.NumCalipers must be in 3 .. 1000"), a caliper
--  centre beyond 1.0E150, a caliper region the caliper rejects, a fitted
--  circle or RMS error beyond 1.0E150, and the fit's own Bad_Parameter
--  (collinear points for the free fit); Out_Of_Memory; Other
--  ("FindCircle: ...") when too few points remain for the fit.
--
--  Proved (docs/PROOF.md): absence of run-time errors for any argument;
--  no memory leaks; and of every results handle Execute returns: one item
--  per caliper, each with its caliper's results, Used only for a found
--  point, NumPointsFound and NumPointsUsed exactly the numbers of found
--  and used items, and NumPointsUsed <= NumPointsFound <= NumCalipers
--  (Gold); the circle, the arc, the RMS error and every distance within
--  the bounds of AMV.Kernels.Shapes.
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

with AMV.Kernels.Caliper;
with AMV.Kernels.Images;
with AMV.Kernels.Shapes;
with AMV.Kernels.Transforms;

package AMV.Kernels.Find_Circle with SPARK_Mode, Preelaborate is

   package KC renames AMV.Kernels.Caliper;
   package KI renames AMV.Kernels.Images;
   package KS renames AMV.Kernels.Shapes;
   package KT renames AMV.Kernels.Transforms;

   use type KC.Ks_Caliper_Results;

   Max_Value : constant := 1.0E150;

   Max_Calipers : constant := 1000;
   --  The largest NumCalipers (C: KS_FIND_CIRCLE_MAX_CALIPERS).

   Max_Iterations : constant := 200;
   --  The most steps of the fixed-radius fit.

   --  CogFindCircleSearchDirectionConstants (VisionPro's values).
   Search_Direction_Inward  : constant Int32 := 0;
   Search_Direction_Outward : constant Int32 := 1;

   ---------------------------------------------------------------------
   --  Run parameters (CogFindCircle; C: ks_find_circle_run_params)
   ---------------------------------------------------------------------

   type Ks_Find_Circle_Run_Params is record
      Num_Calipers              : Int32 := 6;
      Num_To_Ignore             : Int32 := 0;
      Decrement_Num_To_Ignore   : Int32 := False_Value;
      Caliper_Search_Direction  : Int32 := Search_Direction_Inward;
      Radius_Constraint_Enabled : Int32 := False_Value;
      Expected_Circular_Arc     : KS.Ks_Circular_Arc;
      Caliper_Search_Length     : Long_Float := 30.0;
      Caliper_Projection_Length : Long_Float := 10.0;
      Radius_Constraint         : Long_Float := 100.0;
      Caliper_Run_Params        : KC.Ks_Caliper_Run_Params;
   end record
     with Convention => C;
   --  Limits: NumCalipers in 3 .. Max_Calipers; NumToIgnore in 0 ..
   --  NumCalipers - 3 (NumCalipers - 2 with the radius constraint); the
   --  flags 0 or 1; CaliperSearchDirection Inward or Outward; the arc
   --  valid (AMV.Kernels.Shapes) with a radius > 0; the lengths > 0 and
   --  within 4.0E150; RadiusConstraint > 0 and within 1.0E150 when
   --  enabled; the caliper parameters as ks_caliper_check_run_params
   --  checks them.

   ---------------------------------------------------------------------
   --  Results (CogFindCircleResults; C: ks_find_circle_results *)
   ---------------------------------------------------------------------

   type Ks_Find_Circle_Result is record
      Found              : Int32 := False_Value;
      Used               : Int32 := False_Value;
      X                  : Long_Float := 0.0;
      Y                  : Long_Float := 0.0;
      Distance_To_Circle : Long_Float := 0.0;
   end record
     with Convention => C;
   --  C: ks_find_circle_result (CogFindCircleResult without its
   --  CaliperResults, which ks_find_circle_results_caliper_results
   --  returns).

   type Item_Array is array (Natural range <>) of Ks_Find_Circle_Result;
   type Item_Array_Access is access Item_Array;

   type Caliper_Array is array (Natural range <>) of KC.Ks_Caliper_Results;
   type Caliper_Array_Access is access Caliper_Array;

   type Ks_Find_Circle_Results_Data is limited record
      Count            : Natural := 0;
      Items            : Item_Array_Access;
      Calipers         : Caliper_Array_Access;
      Circle           : KS.Ks_Circle;
      Arc              : KS.Ks_Circular_Arc;
      RMS_Error        : Long_Float := 0.0;
      Num_Points_Found : Natural := 0;
      Num_Points_Used  : Natural := 0;
   end record;
   --  What a handle designates (opaque for C).

   type Ks_Find_Circle_Results is access Ks_Find_Circle_Results_Data
     with Convention => C;
   --  C: ks_find_circle_results *.

   function Count_Found (Items : Item_Array; Last : Integer) return Natural
   is (if Last < 0 or else Last > Items'Last then 0
       else Count_Found (Items, Last - 1)
            + (if Items (Last).Found = True_Value then 1 else 0))
   with
     Ghost,
     Pre  => Items'First = 0 and then Last < Max_Calipers,
     Subprogram_Variant => (Decreases => Last),
     Post => Count_Found'Result <= Natural'Max (0, Last + 1);
   --  The number of found items among Items (0 .. Last).

   function Count_Used (Items : Item_Array; Last : Integer) return Natural
   is (if Last < 0 or else Last > Items'Last then 0
       else Count_Used (Items, Last - 1)
            + (if Items (Last).Used = True_Value then 1 else 0))
   with
     Ghost,
     Pre  => Items'First = 0 and then Last < Max_Calipers,
     Subprogram_Variant => (Decreases => Last),
     Post => Count_Used'Result <= Natural'Max (0, Last + 1);
   --  The number of used items among Items (0 .. Last).

   function Valid_Results
     (Results : access constant Ks_Find_Circle_Results_Data) return Boolean
   is
     (Results /= null
      and then Results.Count in 3 .. Max_Calipers
      and then Results.Items /= null
      and then Results.Calipers /= null
      and then Results.Items'First = 0
      and then Results.Items'Last = Results.Count - 1
      and then Results.Calipers'First = 0
      and then Results.Calipers'Last = Results.Count - 1
      and then Results.Num_Points_Used <= Results.Num_Points_Found
      and then Results.Num_Points_Found <= Results.Count);
   --  A handle as Execute makes it (the structural part).

   function Gold_Results
     (Results : access constant Ks_Find_Circle_Results_Data) return Boolean
   is
     (Valid_Results (Results)
      and then (for all I in 0 .. Results.Count - 1 =>
                  Results.Calipers (I) /= null
                  and then Results.Items (I).Found
                             in False_Value | True_Value
                  and then Results.Items (I).Used
                             in False_Value | True_Value
                  and then (if Results.Items (I).Used = True_Value
                            then Results.Items (I).Found = True_Value)
                  and then Results.Items (I).Distance_To_Circle >= 0.0
                  and then Results.Items (I).Distance_To_Circle
                             <= Max_Value)
      and then Results.Num_Points_Found
                 = Count_Found (Results.Items.all, Results.Count - 1)
      and then Results.Num_Points_Used
                 = Count_Used (Results.Items.all, Results.Count - 1)
      and then KS.Valid_Circle (Results.Circle)
      and then KS.Valid_Circular_Arc (Results.Arc)
      and then Results.RMS_Error >= 0.0
      and then Results.RMS_Error <= Max_Value)
   with Ghost;
   --  The proved facts of every handle Execute returns.

   ---------------------------------------------------------------------
   --  Entry points
   ---------------------------------------------------------------------

   procedure Run_Params_Default
     (Params : out Ks_Find_Circle_Run_Params;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_find_circle_run_params_default",
     Post => Valid (Status) and then Succeeded (Status);
   --  The defaults of CogFindCircle (the record's default values).

   procedure Caliper_Region
     (Params : Ks_Find_Circle_Run_Params;
      Index  : Int32;
      Region : out KS.Ks_Rectangle_Affine;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_find_circle_caliper_region",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then (if Succeeded (Status)
                       then KS.Valid_Rectangle_Affine (Region));
   --  The region of caliper Index (0-based), in the expected arc's space.
   --  Bad_Parameter for bad run parameters or a centre beyond 1.0E150,
   --  Index_Out_Of_Range outside 0 .. NumCalipers - 1.

   procedure Execute
     (Image               : access constant KI.Ks_Image_8_Grey_Data;
      Params              : Ks_Find_Circle_Run_Params;
      Pixel_From_Arc      : KT.Ks_Transform_2D_Linear;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Results             : out Ks_Find_Circle_Results;
      Status              : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_find_circle_execute",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Out_Of_Memory
                         | Failure_Other
             and then (if Succeeded (Status)
                       then Gold_Results (Results)
                            and then Results.Count
                                       = Natural (Params.Num_Calipers)
                       else Results = null);
   --  Runs the find circle tool (CogFindCircle.Execute). Returns a new
   --  results handle (null on failure).

   procedure Results_Destroy (Results : in out Ks_Find_Circle_Results)
   with
     Export, Convention => C,
     External_Name => "ks_find_circle_results_destroy",
     Post => Results = null;

   procedure Results_Count
     (Results : access constant Ks_Find_Circle_Results_Data;
      Count   : out Int32;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_find_circle_results_count",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Count in 0 .. Max_Calipers;

   procedure Results_Item
     (Results : access constant Ks_Find_Circle_Results_Data;
      Index   : Int32;
      Item    : out Ks_Find_Circle_Result;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_find_circle_results_item",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then (if Succeeded (Status)
                       then Valid_Results (Results)
                            and then Index in 0 .. Int32 (Results.Count) - 1
                            and then Item
                                       = Results.Items (Natural (Index))
                            and then Item.Found in False_Value | True_Value
                            and then Item.Used in False_Value | True_Value);
   --  Item (Index), 0-based (Index_Out_Of_Range outside, always for null).
   --  Its Found and Used are 0 or 1 (Bad_Parameter for an item whose flags
   --  are not, which Execute never makes).

   procedure Results_Caliper_Results
     (Results : access constant Ks_Find_Circle_Results_Data;
      Index   : Int32;
      Copy    : out KC.Ks_Caliper_Results;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_find_circle_results_caliper_results",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range | Failure_Out_Of_Memory
             and then (if not Succeeded (Status) then Copy = null);

   procedure Results_Circle
     (Results : access constant Ks_Find_Circle_Results_Data;
      Circle  : out KS.Ks_Circle;
      Arc     : out KS.Ks_Circular_Arc;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_find_circle_results_circle",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then KS.Valid_Circle (Circle)
                            and then KS.Valid_Circular_Arc (Arc));
   --  GetCircle and GetCircularArc (Bad_Parameter for null).

   procedure Results_Fit
     (Results          : access constant Ks_Find_Circle_Results_Data;
      RMS_Error        : out Long_Float;
      Num_Points_Found : out Int32;
      Num_Points_Used  : out Int32;
      Status           : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_find_circle_results_fit",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Num_Points_Used in 0 .. Max_Calipers
             and then Num_Points_Found in 0 .. Max_Calipers
             and then Num_Points_Used <= Num_Points_Found;
   --  RMSError, NumPointsFound and NumPointsUsed (all 0 for null).

end AMV.Kernels.Find_Circle;
