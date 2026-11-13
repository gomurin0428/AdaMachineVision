--  Kernel of AMV.Caliper.Find_Line: CogFindLineTool (run parameters
--  CogFindLine, results CogFindLineResults and CogFindLineResult). Its
--  entry points are part of the C API of the caliper tools
--  (include/amv_caliper.h, names ks_find_line_*).
--
--  What a run does. NumCalipers calipers are placed along the expected
--  line segment, in the segment's own space: caliper K (0-based) is
--  centred at Start + K / (NumCalipers - 1) (End - Start), so the first
--  and the last sit on the end points; each is a rectangle
--  CaliperSearchLength long along its search direction (the segment's
--  direction turned by CaliperSearchDirection, radians) and
--  CaliperProjectionLength wide, without skew (ks_find_line_caliper_region
--  returns it). Each caliper runs as ks_caliper_execute does, with
--  CaliperRunParams, on the image (the segment's space mapped to pixel
--  space by Pixel_From_Segment, the results reported in the space
--  Selected_From_Pixel maps to); a caliper that finds a result contributes
--  the position (PositionX, PositionY) of its best result. The line is
--  then fitted to those points with ks_geometry_fit_line_robust, which
--  discards NumToIgnore of them (the ones whose removal lowers the RMS
--  error most, one at a time). With DecrementNumToIgnore set, NumToIgnore
--  is lowered as far as needed (not below 0) to leave 2 points.
--
--  Results. One item per caliper, in the order of the calipers: Found
--  (the caliper found an edge), Used (its point took part in the fit),
--  X and Y (the point; 0 when not found), DistanceToLine (the
--  perpendicular distance of the point from the fitted line, >= 0; 0 when
--  not found) and the caliper's own results
--  (ks_find_line_results_caliper_results, a copy). GetLine: the fitted
--  line through the centroid of the used points, directed like the
--  expected segment (the direction from the first to the last used point
--  along the calipers); GetLineSegment: the part of that line between the
--  projections of the two extreme used points; RMSError over the used
--  points; NumPointsFound and NumPointsUsed. Everything is in the selected
--  space.
--
--  Failures. Image_No_Pixels for a null image; Bad_Parameter for bad run
--  parameters (naming them: "RunParams.NumCalipers must be in 2 .. 1000",
--  "RunParams.CaliperRunParams.ContrastThreshold must be >= 0"), an
--  expected segment of length 0, a caliper region the caliper rejects
--  (too large, beyond the bounds), and a result beyond 1.0E150;
--  Out_Of_Memory; Other ("FindLine: ...") when fewer than 2 points
--  remain for the fit after NumToIgnore, and the fit's own Bad_Parameter
--  when the points coincide.
--
--  Proved (docs/PROOF.md): absence of run-time errors for any argument;
--  no memory leaks (every caliper's results are freed on every path); and
--  of every results handle Execute returns: one item per caliper, each
--  with its caliper's results, Used only for a found point, the number of
--  found items NumPointsFound and of used items NumPointsUsed, and
--  NumPointsUsed <= NumPointsFound <= NumCalipers (Gold); every
--  coordinate, the RMS error and every distance within 1.0E150.
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

with Ada.Numerics;

with AMV.Kernels.Caliper;
with AMV.Kernels.Images;
with AMV.Kernels.Shapes;
with AMV.Kernels.Transforms;

package AMV.Kernels.Find_Line with SPARK_Mode, Preelaborate is

   package KC renames AMV.Kernels.Caliper;
   package KI renames AMV.Kernels.Images;
   package KS renames AMV.Kernels.Shapes;
   package KT renames AMV.Kernels.Transforms;

   use type KC.Ks_Caliper_Results;

   Max_Value : constant := 1.0E150;

   Max_Calipers : constant := 1000;
   --  The largest NumCalipers (C: KS_FIND_LINE_MAX_CALIPERS).

   ---------------------------------------------------------------------
   --  Run parameters (CogFindLine; C: ks_find_line_run_params)
   ---------------------------------------------------------------------

   type Ks_Find_Line_Run_Params is record
      Num_Calipers              : Int32 := 6;
      Num_To_Ignore             : Int32 := 0;
      Decrement_Num_To_Ignore   : Int32 := False_Value;
      Expected_Line_Segment     : KS.Ks_Line_Segment;
      Caliper_Search_Length     : Long_Float := 30.0;
      Caliper_Projection_Length : Long_Float := 10.0;
      Caliper_Search_Direction  : Long_Float := Ada.Numerics.Pi / 2.0;
      Caliper_Run_Params        : KC.Ks_Caliper_Run_Params;
   end record
     with Convention => C;
   --  Limits: NumCalipers in 2 .. Max_Calipers; NumToIgnore in 0 ..
   --  NumCalipers - 2; DecrementNumToIgnore 0 or 1; the segment valid
   --  (AMV.Kernels.Shapes) and of a length > 0; the lengths > 0 and
   --  within 4.0E150; CaliperSearchDirection within 1.0E150; the caliper
   --  parameters as ks_caliper_check_run_params checks them.

   ---------------------------------------------------------------------
   --  Results (CogFindLineResults; C: ks_find_line_results *, opaque)
   ---------------------------------------------------------------------

   type Ks_Find_Line_Result is record
      Found            : Int32 := False_Value;
      Used             : Int32 := False_Value;
      X                : Long_Float := 0.0;
      Y                : Long_Float := 0.0;
      Distance_To_Line : Long_Float := 0.0;
   end record
     with Convention => C;
   --  C: ks_find_line_result (CogFindLineResult without CaliperResults,
   --  which ks_find_line_results_caliper_results returns).

   type Item_Array is array (Natural range <>) of Ks_Find_Line_Result;
   type Item_Array_Access is access Item_Array;

   type Caliper_Array is array (Natural range <>) of KC.Ks_Caliper_Results;
   type Caliper_Array_Access is access Caliper_Array;

   type Ks_Find_Line_Results_Data is limited record
      Count            : Natural := 0;
      Items            : Item_Array_Access;
      Calipers         : Caliper_Array_Access;
      Line             : KS.Ks_Line;
      Segment          : KS.Ks_Line_Segment;
      RMS_Error        : Long_Float := 0.0;
      Num_Points_Found : Natural := 0;
      Num_Points_Used  : Natural := 0;
   end record;
   --  What a handle designates (opaque for C): Count = NumCalipers items
   --  and caliper results, the line, the segment, the RMS error and the
   --  counts.

   type Ks_Find_Line_Results is access Ks_Find_Line_Results_Data
     with Convention => C;
   --  C: ks_find_line_results *.

   function Count_Found (Items : Item_Array; Last : Integer) return Natural
   is (if Last < 0 or else Last > Items'Last then 0
       else Count_Found (Items, Last - 1)
            + (if Items (Last).Found = True_Value then 1 else 0))
   with
     Ghost,
     Pre  => Items'First = 0 and then Last < Max_Calipers,
     Subprogram_Variant => (Decreases => Last),
     Post => Count_Found'Result <= Natural'Max (0, Last + 1);
   --  The number of found items among Items (Items'First .. Last).

   function Count_Used (Items : Item_Array; Last : Integer) return Natural
   is (if Last < 0 or else Last > Items'Last then 0
       else Count_Used (Items, Last - 1)
            + (if Items (Last).Used = True_Value then 1 else 0))
   with
     Ghost,
     Pre  => Items'First = 0 and then Last < Max_Calipers,
     Subprogram_Variant => (Decreases => Last),
     Post => Count_Used'Result <= Natural'Max (0, Last + 1);
   --  The number of used items among Items (Items'First .. Last).

   function Valid_Results
     (Results : access constant Ks_Find_Line_Results_Data) return Boolean
   is
     (Results /= null
      and then Results.Count in 2 .. Max_Calipers
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
     (Results : access constant Ks_Find_Line_Results_Data) return Boolean
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
                  and then Results.Items (I).Distance_To_Line >= 0.0
                  and then Results.Items (I).Distance_To_Line <= Max_Value)
      and then Results.Num_Points_Found
                 = Count_Found (Results.Items.all, Results.Count - 1)
      and then Results.Num_Points_Used
                 = Count_Used (Results.Items.all, Results.Count - 1)
      and then KS.Valid_Line (Results.Line)
      and then KS.Valid_Line_Segment (Results.Segment)
      and then Results.RMS_Error >= 0.0
      and then Results.RMS_Error <= Max_Value)
   with Ghost;
   --  The proved facts of every handle Execute returns.

   ---------------------------------------------------------------------
   --  Entry points
   ---------------------------------------------------------------------

   procedure Run_Params_Default
     (Params : out Ks_Find_Line_Run_Params;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_find_line_run_params_default",
     Post => Valid (Status) and then Succeeded (Status);
   --  The defaults of CogFindLine (the record's default values).

   procedure Caliper_Region
     (Params : Ks_Find_Line_Run_Params;
      Index  : Int32;
      Region : out KS.Ks_Rectangle_Affine;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_find_line_caliper_region",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then (if Succeeded (Status)
                       then KS.Valid_Rectangle_Affine (Region));
   --  The region of caliper Index (0-based), in the expected segment's
   --  space. Bad_Parameter for bad run parameters, Index_Out_Of_Range
   --  outside 0 .. NumCalipers - 1.

   procedure Execute
     (Image               : access constant KI.Ks_Image_8_Grey_Data;
      Params              : Ks_Find_Line_Run_Params;
      Pixel_From_Segment  : KT.Ks_Transform_2D_Linear;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Results             : out Ks_Find_Line_Results;
      Status              : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_find_line_execute",
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
   --  Runs the find line tool (CogFindLine.Execute). Returns a new
   --  results handle (null on failure).

   procedure Results_Destroy (Results : in out Ks_Find_Line_Results)
   with
     Export, Convention => C,
     External_Name => "ks_find_line_results_destroy",
     Post => Results = null;
   --  Frees the results (the calipers' results too); nothing for null.

   procedure Results_Count
     (Results : access constant Ks_Find_Line_Results_Data;
      Count   : out Int32;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_find_line_results_count",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Count in 0 .. Max_Calipers;
   --  Count: the number of calipers (0 for null).

   procedure Results_Item
     (Results : access constant Ks_Find_Line_Results_Data;
      Index   : Int32;
      Item    : out Ks_Find_Line_Result;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_find_line_results_item",
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
     (Results : access constant Ks_Find_Line_Results_Data;
      Index   : Int32;
      Copy    : out KC.Ks_Caliper_Results;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_find_line_results_caliper_results",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range | Failure_Out_Of_Memory
             and then (if not Succeeded (Status) then Copy = null);
   --  Item (Index).CaliperResults: a new handle holding a copy of the
   --  results of caliper Index.

   procedure Results_Line
     (Results : access constant Ks_Find_Line_Results_Data;
      Line    : out KS.Ks_Line;
      Segment : out KS.Ks_Line_Segment;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_find_line_results_line",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then KS.Valid_Line (Line)
                            and then KS.Valid_Line_Segment (Segment));
   --  GetLine and GetLineSegment. Bad_Parameter for null ("Results has no
   --  line") and an inconsistent handle.

   procedure Results_Fit
     (Results          : access constant Ks_Find_Line_Results_Data;
      RMS_Error        : out Long_Float;
      Num_Points_Found : out Int32;
      Num_Points_Used  : out Int32;
      Status           : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_find_line_results_fit",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Num_Points_Used in 0 .. Max_Calipers
             and then Num_Points_Found in 0 .. Max_Calipers
             and then Num_Points_Used <= Num_Points_Found;
   --  RMSError, NumPointsFound and NumPointsUsed (all 0 for null).

end AMV.Kernels.Find_Line;
