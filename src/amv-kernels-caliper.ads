--  Kernel of AMV.Caliper: the caliper (CogCaliperTool, run parameters
--  CogCaliper, results CogCaliperResults) and the scorers that rank its
--  candidates (CogCaliperScorerContrast, CogCaliperScorerPosition, ...).
--  Its entry points are the C API of the caliper (include/amv_caliper.h,
--  names ks_caliper_*); AMV.Kernels.Find_Line and AMV.Kernels.Find_Circle
--  run it once per caliper.
--
--  What a run does. The region is a CogRectangleAffine: side X is the
--  search direction, side Y the projection direction. The kernel maps the
--  region into pixel space (Pixel_From_Region, from the region's space to
--  pixel space) and lays a grid of Nx x Ny samples over it, Nx = the pixel
--  length of side X rounded (at least 1) and Ny the same for side Y, so
--  that samples lie about one pixel apart along both sides. Sample (I, J)
--  is the bilinear value of the image at the centre of cell (I, J) of the
--  grid (ks_real_image_bilinear_8_grey: points outside the image take the
--  value of the nearest border pixel). The projection profile is the mean
--  of each column of the grid (Nx values, the mean along side Y). The
--  edge filter of half size N (FilterHalfSizeInPixels) gives, at the
--  boundary between samples I and I + 1, the mean of the N samples after
--  it minus the mean of the N samples before it (samples beyond the ends
--  repeat the end samples): positive where the profile rises (dark to
--  light along the search direction), negative where it falls. An edge is
--  a boundary where the filter has a local extremum of magnitude at least
--  ContrastThreshold (and not zero). Its position is refined to a fraction
--  of a sample by the centroid of the profile differences
--  (P (K + 1) - P (K), sign-corrected) over the boundaries within N of
--  the extremum, which is not biased by the shape of the filter response
--  (a parabola through the extremum would be, by up to about 0.05 pixel).
--  Its contrast is the filter value (signed, grey levels, so within
--  [-255, 255]). At most Max_Edges edges are kept: the ones with the
--  largest contrast magnitude.
--
--  Single edge mode: every edge whose polarity matches Edge0Polarity is a
--  candidate. Pair mode: every ordered pair (edge 0 before edge 1 along
--  the search direction) whose polarities match Edge0Polarity and
--  Edge1Polarity is a candidate. Each candidate gets the product of the
--  outputs of the enabled scorers of SingleEdgeScorers (single edge) or
--  TwoEdgeScorers (pair), 1 when none is enabled; the results are the
--  MaxResults candidates with the highest scores, highest first (ties:
--  the stronger edge first, then the earlier one along the search
--  direction).
--
--  Scorers (our own design; VisionPro sets a scorer with SetXYParameters
--  (x0, x1, xc, y0, y1), but what the numbers mean here is defined here).
--  A scorer measures one value M of a candidate and maps it through a
--  tent: the score is Y1 at M = XC, changes linearly to Y0 at XC - X0 and
--  at XC + X1, and is Y0 beyond (X0, X1 >= 0 are the half widths below and
--  above XC; a zero half width makes that side Y0 at once). Y0 and Y1 lie
--  in [0, 1], so every score does. The measures (Kind codes, in the order
--  of the VisionPro class names; P is a position along the search
--  direction from the region's centre in selected-space units, H half the
--  search length in the same units, W the width of a pair, Wx =
--  Edge1Position - Edge0Position the expected width):
--
--    Scorer_Contrast (0)          the contrast magnitude (a pair: the mean
--                                 of both);                 default: XC =
--                                 255, X0 = 255, X1 = 0, Y0 = 0, Y1 = 1,
--                                 so the score is contrast / 255;
--    Scorer_Position (1)          P (a pair: its centre);   default: XC
--                                 = 0, X0 = X1 = 10, Y0 = 0, Y1 = 1;
--    Scorer_Position_Neg (2)      -P;                       as Position;
--    Scorer_Position_Norm (3)     P / H, within [-1, 1];    default: XC =
--                                 0, X0 = X1 = 1, Y0 = 0, Y1 = 1;
--    Scorer_Position_Norm_Neg (4) -P / H;                   as Norm;
--    Scorer_Size_Norm (5)         W / Wx;                   default: XC =
--                                 1, X0 = X1 = 1, Y0 = 0, Y1 = 1;
--    Scorer_Size_Diff_Norm (6)    abs (W - Wx) / Wx;        default: XC =
--                                 0, X0 = X1 = 1, Y0 = 0, Y1 = 1;
--    Scorer_Size_Diff_Norm_Asym (7) (W - Wx) / Wx (signed); as Size_Diff;
--    Scorer_Straddle (8)          1 when the pair straddles the region's
--                                 centre (P0 <= 0 <= P1), else 0;
--                                 default: XC = 1, X0 = 1, X1 = 0, Y0 = 0,
--                                 Y1 = 1.
--
--  The size and straddle scorers measure pairs: they are rejected in
--  SingleEdgeScorers, and need Wx > 0 when enabled in TwoEdgeScorers of a
--  run in Pair mode. The ratios saturate at +/-1.0E150. By default
--  SingleEdgeScorers holds one contrast scorer and TwoEdgeScorers one
--  Size_Diff_Norm scorer, both enabled.
--
--  Results. Positions are reported in the image's selected space: the
--  kernel maps pixel-space points with Selected_From_Pixel. An edge's
--  Position is its signed distance from the region's centre along the
--  search direction, measured in the selected space (along a line an
--  affine map scales every length by the same factor, so this is exact
--  for any transform; across a transform that is not a similarity the
--  factor differs between directions, which is why distances are measured
--  along the search direction only). PositionX, PositionY is the point
--  where the edge crosses the centre line of the region (halfway along
--  side Y). A result's Position is that of its edge (single edge) or the
--  mean of its two edges (pair), its PositionX/Y the point at that
--  position, its Width 0 (single edge) or the distance between the edges
--  (pair). A single edge result has Edge_1 = Edge_0. The results also
--  keep the projection profile and the filter values (GetProjectionValues
--  and GetFilteredValues: Nx values each; filter value I belongs to the
--  boundary between samples I and I + 1, and the last one is 0).
--
--  Bounds. Every coordinate, length and angle of the region and the
--  transforms must be finite and within the bounds of AMV.Kernels.Shapes
--  and AMV.Kernels.Transforms (1.0E150; side lengths 4.0E150), and the
--  run parameters within the limits below (Bad_Parameter otherwise,
--  naming the property). The region's sides must map to at most
--  Max_Search_Samples and Max_Projection_Samples pixels and to at most
--  Max_Samples samples in all, and half the search length in the selected
--  space must be within 1.0E150 (Bad_Parameter otherwise), so every
--  reported position, coordinate and width is within the bounds of
--  AMV.Kernels.Shapes (a point mapped beyond 1.0E150 fails the run with
--  Bad_Parameter). A region whose side maps to zero pixels (a singular
--  transform) fails with Bad_Parameter. Grey values, profile values and
--  contrasts lie within [-255, 255], scores within [0, 1].
--
--  Proved (docs/PROOF.md): absence of run-time errors for any argument,
--  handles that are null or came from this kernel included; no memory
--  leaks; and of every results handle Execute returns: at most MaxResults
--  results, sorted by score (highest first), every score within [0, 1],
--  every edge position (and every result position) within half the
--  search length of the region's centre, widths within [0, the search
--  length], both profiles Nx values long.
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

with AMV.Kernels.Images;
with AMV.Kernels.Shapes;
with AMV.Kernels.Transforms;

package AMV.Kernels.Caliper with SPARK_Mode, Preelaborate is

   package KI renames AMV.Kernels.Images;
   package KS renames AMV.Kernels.Shapes;
   package KT renames AMV.Kernels.Transforms;

   Max_Value : constant := 1.0E150;
   --  The bound of every coordinate, position and threshold (the bound of
   --  AMV.Kernels.Shapes and AMV.Kernels.Transforms).

   ---------------------------------------------------------------------
   --  Codes (C: KS_CALIPER_*)
   ---------------------------------------------------------------------

   --  CogCaliperEdgeModeConstants (VisionPro's values).
   Edge_Mode_Single_Edge : constant Int32 := 1;
   Edge_Mode_Pair        : constant Int32 := 2;

   --  CogCaliperPolarityConstants (VisionPro's values).
   Polarity_Dark_To_Light : constant Int32 := 1;
   Polarity_Light_To_Dark : constant Int32 := 2;
   Polarity_Dont_Care     : constant Int32 := 3;

   --  CogCaliperSamplingModeConstants (VisionPro's values). Both sample
   --  bilinearly in this implementation.
   Sampling_Mode_Bilinear_Interpolation : constant Int32 := 2;
   Sampling_Mode_Bilinear_Accurate      : constant Int32 := 4;

   --  Scorer kinds, one per CogCaliperScorer* class (AMV codes, in the
   --  order of the class names).
   Scorer_Contrast            : constant Int32 := 0;
   Scorer_Position            : constant Int32 := 1;
   Scorer_Position_Neg        : constant Int32 := 2;
   Scorer_Position_Norm       : constant Int32 := 3;
   Scorer_Position_Norm_Neg   : constant Int32 := 4;
   Scorer_Size_Norm           : constant Int32 := 5;
   Scorer_Size_Diff_Norm      : constant Int32 := 6;
   Scorer_Size_Diff_Norm_Asym : constant Int32 := 7;
   Scorer_Straddle            : constant Int32 := 8;

   subtype Scorer_Kind is Int32 range Scorer_Contrast .. Scorer_Straddle;

   subtype Pair_Scorer_Kind is Int32
     range Scorer_Size_Norm .. Scorer_Straddle;
   --  The kinds that measure pairs only.

   ---------------------------------------------------------------------
   --  Limits (C: KS_CALIPER_MAX_*)
   ---------------------------------------------------------------------

   Max_Scorers            : constant := 8;
   --  The capacity of a scorer list.
   Max_Results_Limit      : constant := 1000;
   --  The largest MaxResults.
   Max_Filter_Half_Size   : constant := 1000;
   --  The largest FilterHalfSizeInPixels.
   Max_Search_Samples     : constant := 2**15;
   --  The most samples along side X (the search length in pixels).
   Max_Projection_Samples : constant := 2**15;
   --  The most samples along side Y.
   Max_Samples            : constant := 2**24;
   --  The most samples of one run (Nx * Ny).
   Max_Edges              : constant := 1024;
   --  The most edges a run keeps (the strongest).

   ---------------------------------------------------------------------
   --  Run parameters (CogCaliper; C: ks_caliper_run_params)
   ---------------------------------------------------------------------

   type Ks_Caliper_Scorer is record
      Kind    : Int32 := Scorer_Contrast;
      Enabled : Int32 := True_Value;
      X0      : Long_Float := 255.0;
      X1      : Long_Float := 0.0;
      XC      : Long_Float := 255.0;
      Y0      : Long_Float := 0.0;
      Y1      : Long_Float := 1.0;
   end record
     with Convention => C;
   --  C: ks_caliper_scorer. One scorer (see above); the default record is
   --  the default contrast scorer.

   type Ks_Caliper_Scorer_Array is
     array (0 .. Max_Scorers - 1) of Ks_Caliper_Scorer
     with Convention => C;

   type Ks_Caliper_Scorers is record
      Count : Int32 := 0;
      Items : Ks_Caliper_Scorer_Array;
   end record
     with Convention => C;
   --  C: ks_caliper_scorers (CogCaliperScorers): Items (0 .. Count - 1).

   Default_Size_Diff_Norm_Scorer : constant Ks_Caliper_Scorer :=
     (Kind => Scorer_Size_Diff_Norm, Enabled => True_Value,
      X0 => 1.0, X1 => 1.0, XC => 0.0, Y0 => 0.0, Y1 => 1.0);

   Default_Single_Edge_Scorers : constant Ks_Caliper_Scorers :=
     (Count => 1, Items => [others => (others => <>)]);

   Default_Two_Edge_Scorers : constant Ks_Caliper_Scorers :=
     (Count => 1,
      Items => [0      => (Kind    => Scorer_Size_Diff_Norm,
                           Enabled => True_Value,
                           X0      => 1.0, X1 => 1.0, XC => 0.0,
                           Y0      => 0.0, Y1 => 1.0),
                others => (others => <>)]);

   type Ks_Caliper_Run_Params is record
      Edge_Mode                  : Int32 := Edge_Mode_Single_Edge;
      Edge_0_Polarity            : Int32 := Polarity_Dont_Care;
      Edge_1_Polarity            : Int32 := Polarity_Dont_Care;
      Filter_Half_Size_In_Pixels : Int32 := 2;
      Max_Results                : Int32 := 1;
      Sampling_Mode              : Int32 :=
        Sampling_Mode_Bilinear_Interpolation;
      Edge_0_Position            : Long_Float := 0.0;
      Edge_1_Position            : Long_Float := 10.0;
      Contrast_Threshold         : Long_Float := 5.0;
      Single_Edge_Scorers        : Ks_Caliper_Scorers :=
        Default_Single_Edge_Scorers;
      Two_Edge_Scorers           : Ks_Caliper_Scorers :=
        Default_Two_Edge_Scorers;
   end record
     with Convention => C;
   --  C: ks_caliper_run_params; the defaults of CogCaliper. Limits:
   --  EdgeMode and the polarities are codes above; FilterHalfSizeInPixels
   --  in 1 .. Max_Filter_Half_Size; MaxResults in 1 .. Max_Results_Limit;
   --  Edge0Position and Edge1Position finite and within Max_Value;
   --  ContrastThreshold in [0, Max_Value]; each scorer list holds 0 ..
   --  Max_Scorers valid scorers (a known Kind, Enabled 0 or 1, X0 and X1
   --  in [0, Max_Value], XC within Max_Value, Y0 and Y1 in [0, 1]).

   ---------------------------------------------------------------------
   --  Results (CogCaliperResults; C: ks_caliper_results *, opaque)
   ---------------------------------------------------------------------

   type Ks_Caliper_Edge is record
      Position   : Long_Float := 0.0;
      Position_X : Long_Float := 0.0;
      Position_Y : Long_Float := 0.0;
      Contrast   : Long_Float := 0.0;
   end record
     with Convention => C;
   --  C: ks_caliper_edge (CogCaliperEdge). Contrast is signed: positive
   --  for a dark to light edge.

   type Ks_Caliper_Result is record
      Score      : Long_Float := 0.0;
      Position   : Long_Float := 0.0;
      Position_X : Long_Float := 0.0;
      Position_Y : Long_Float := 0.0;
      Width      : Long_Float := 0.0;
      Edge_0     : Ks_Caliper_Edge;
      Edge_1     : Ks_Caliper_Edge;
   end record
     with Convention => C;
   --  C: ks_caliper_result (CogCaliperResult).

   type Result_Array is array (Natural range <>) of Ks_Caliper_Result;
   type Result_Array_Access is access Result_Array;

   type Value_Array is array (Natural range <>) of Long_Float;
   type Value_Array_Access is access Value_Array;

   type Ks_Caliper_Results_Data is limited record
      Count       : Natural := 0;
      Items       : Result_Array_Access;
      Projection  : Value_Array_Access;
      Filtered    : Value_Array_Access;
      Half_Length : Long_Float := 0.0;
   end record;
   --  What a handle designates (opaque for C): Count results in Items
   --  (0 .. Count - 1; null when there are none), the projection profile
   --  and the filter values (the same length), and half the search length
   --  in the selected space. Valid_Results states the invariant.

   type Ks_Caliper_Results is access Ks_Caliper_Results_Data
     with Convention => C;
   --  C: ks_caliper_results *.

   function Valid_Results
     (Results : access constant Ks_Caliper_Results_Data) return Boolean
   is
     (Results /= null
      and then Results.Count <= Max_Results_Limit
      and then (if Results.Count = 0 then Results.Items = null
                else Results.Items /= null
                     and then Results.Items'First = 0
                     and then Results.Items'Last = Results.Count - 1)
      and then Results.Projection /= null
      and then Results.Filtered /= null
      and then Results.Projection'First = 0
      and then Results.Projection'Last >= 0
      and then Results.Filtered'First = 0
      and then Results.Projection'Last = Results.Filtered'Last
      and then Results.Projection'Last < Max_Search_Samples
      and then Results.Half_Length >= 0.0
      and then Results.Half_Length <= Max_Value);
   --  A handle as Execute makes it.

   function Score_In_Range (Item : Ks_Caliper_Result) return Boolean is
     (Item.Score >= 0.0 and then Item.Score <= 1.0);

   function Within (Item : Ks_Caliper_Result; Half : Long_Float)
      return Boolean
   is
     (Item.Edge_0.Position >= -Half and then Item.Edge_0.Position <= Half
      and then Item.Edge_1.Position >= -Half
      and then Item.Edge_1.Position <= Half
      and then Item.Position >= -Half and then Item.Position <= Half
      and then Item.Width >= 0.0 and then Item.Width / 2.0 <= Half);
   --  Every position within Half of the region's centre, the width within
   --  the search length.

   function Coordinates_In_Bound (Item : Ks_Caliper_Result) return Boolean
   is
     (Item.Position_X >= -Max_Value and then Item.Position_X <= Max_Value
      and then Item.Position_Y >= -Max_Value
      and then Item.Position_Y <= Max_Value);
   --  The point of the result within the bound.

   function Gold_Results
     (Results : access constant Ks_Caliper_Results_Data) return Boolean
   is
     (Valid_Results (Results)
      and then (for all I in 0 .. Results.Count - 1 =>
                  Score_In_Range (Results.Items (I))
                  and then Within (Results.Items (I), Results.Half_Length)
                  and then Coordinates_In_Bound (Results.Items (I)))
      and then (for all I in 0 .. Results.Count - 2 =>
                  Results.Items (I).Score >= Results.Items (I + 1).Score));
   --  The proved facts of every handle Execute returns (scores within
   --  [0, 1], positions within the search length, points within the
   --  bound, sorted by score).

   ---------------------------------------------------------------------
   --  Entry points: run parameters and scorers
   ---------------------------------------------------------------------

   procedure Run_Params_Default
     (Params : out Ks_Caliper_Run_Params;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_caliper_run_params_default",
     Post => Valid (Status) and then Succeeded (Status);
   --  The defaults of CogCaliper (the record's default values).

   procedure Scorer_Default
     (Kind   : Int32;
      Scorer : out Ks_Caliper_Scorer;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_caliper_scorer_default",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Scorer.Kind = Kind
                            and then Scorer.Enabled = True_Value);
   --  A new enabled scorer of the given kind with its default parameters
   --  (see above). Bad_Parameter for an unknown kind.

   procedure Scorer_Set_XY_Parameters
     (Scorer             : Ks_Caliper_Scorer;
      X0, X1, XC, Y0, Y1 : Long_Float;
      Result             : out Ks_Caliper_Scorer;
      Status             : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_caliper_scorer_set_xy_parameters",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Result = (Scorer.Kind, Scorer.Enabled,
                                      X0, X1, XC, Y0, Y1)
                       else Result = Scorer);
   --  SetXYParameters: Scorer with these parameters (X0 and X1 in
   --  [0, Max_Value], XC within Max_Value, Y0 and Y1 in [0, 1];
   --  Bad_Parameter naming the parameter otherwise).

   procedure Scorers_Add
     (Scorers : in out Ks_Caliper_Scorers;
      Scorer  : Ks_Caliper_Scorer;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_caliper_scorers_add",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Scorers.Count = Scorers.Count'Old + 1
                            and then Scorers.Count in 1 .. Max_Scorers
                            and then Scorers.Items
                                       (Integer (Scorers.Count) - 1)
                                       = Scorer
                       else Scorers = Scorers'Old);
   --  Add: appends Scorer. Bad_Parameter when the list is full
   --  (Max_Scorers) or its Count is not in 0 .. Max_Scorers.

   procedure Scorers_Remove_At
     (Scorers : in out Ks_Caliper_Scorers;
      Index   : Int32;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_caliper_scorers_remove_at",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then (if Succeeded (Status)
                       then Scorers.Count = Scorers.Count'Old - 1
                       else Scorers = Scorers'Old);
   --  RemoveAt: removes Items (Index), moving the later ones down.
   --  Index_Out_Of_Range unless Index is in 0 .. Count - 1; Bad_Parameter
   --  when Count is not in 0 .. Max_Scorers.

   procedure Scorers_Count
     (Scorers : Ks_Caliper_Scorers;
      Count   : out Int32;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_caliper_scorers_count",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Count = Scorers.Count
                            and then Count in 0 .. Max_Scorers
                       else Count = 0);
   --  Count: Scorers.Count. Bad_Parameter when it is not in
   --  0 .. Max_Scorers (a list whose Count was set by hand).

   procedure Scorer_Get_Kind
     (Scorer : Ks_Caliper_Scorer;
      Kind   : out Int32;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_caliper_scorer_get_kind",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Kind = Scorer.Kind and then Kind in Scorer_Kind
                       else Kind = Scorer_Contrast);
   --  Scorer.Kind. Bad_Parameter when it is not the code of a kind (a
   --  record changed by hand).

   procedure Scorer_Get_Enabled
     (Scorer  : Ks_Caliper_Scorer;
      Enabled : out Int32;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_caliper_scorer_get_enabled",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Enabled = Scorer.Enabled
                            and then Enabled in False_Value | True_Value
                       else Enabled = False_Value);
   --  Scorer.Enabled. Bad_Parameter when it is not 0 or 1.

   procedure Check_Run_Params
     (Params : Ks_Caliper_Run_Params;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_caliper_check_run_params",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter;
   --  The checks of the run parameters that Execute makes, alone
   --  ("RunParams.ContrastThreshold must be >= 0", ...).

   ---------------------------------------------------------------------
   --  Entry points: running
   ---------------------------------------------------------------------

   procedure Execute
     (Image               : access constant KI.Ks_Image_8_Grey_Data;
      Region              : KS.Ks_Rectangle_Affine;
      Pixel_From_Region   : KT.Ks_Transform_2D_Linear;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Params              : Ks_Caliper_Run_Params;
      Results             : out Ks_Caliper_Results;
      Status              : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_caliper_execute",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Gold_Results (Results)
                            and then Results.Count
                                       <= Natural (Params.Max_Results)
                       else Results = null);
   --  Runs the caliper (CogCaliper.Execute) on Image within Region, the
   --  region in the space that Pixel_From_Region maps to pixel space; the
   --  results are reported in the space that Selected_From_Pixel maps
   --  pixel space to. Returns a new results handle (null on failure).
   --  Image_No_Pixels for a null image ("InputImage has no pixels");
   --  Bad_Parameter for an inconsistent image handle, a region or
   --  transform beyond its bounds, a side length of 0 ("Region.SideXLength
   --  must be > 0"), a region too large (see above), bad run parameters,
   --  and a result point beyond 1.0E150; Out_Of_Memory.

   procedure Results_Destroy (Results : in out Ks_Caliper_Results)
   with
     Export, Convention => C,
     External_Name => "ks_caliper_results_destroy",
     Post => Results = null;
   --  Frees the results and sets the handle to null; nothing for null.

   procedure Results_Duplicate
     (Results : access constant Ks_Caliper_Results_Data;
      Copy    : out Ks_Caliper_Results;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_caliper_results_duplicate",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then (if Results = null then Copy = null
                             else Valid_Results (Copy)
                                  and then Copy.Count = Results.Count)
                       else Copy = null);
   --  A new handle with the same contents (null for null). Bad_Parameter
   --  for an inconsistent handle.

   procedure Results_Count
     (Results : access constant Ks_Caliper_Results_Data;
      Count   : out Int32;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_caliper_results_count",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Count in 0 .. Max_Results_Limit
             and then (if Succeeded (Status) and then Results /= null
                       then Count = Int32 (Results.Count));
   --  Count: the number of results (0 for null).

   procedure Results_Item
     (Results : access constant Ks_Caliper_Results_Data;
      Index   : Int32;
      Item    : out Ks_Caliper_Result;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_caliper_results_item",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then (if Succeeded (Status)
                       then Valid_Results (Results)
                            and then Index in 0 .. Int32 (Results.Count) - 1
                            and then Item
                                       = Results.Items (Natural (Index)));
   --  Item (Index), 0-based: Index_Out_Of_Range outside 0 .. Count - 1
   --  (always for null).

   procedure Results_Profile_Length
     (Results : access constant Ks_Caliper_Results_Data;
      Length  : out Int32;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_caliper_results_profile_length",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Length in 0 .. Max_Search_Samples;
   --  The number of values of each profile, Nx (0 for null).

   procedure Results_Projection_Value
     (Results : access constant Ks_Caliper_Results_Data;
      Index   : Int32;
      Value   : out Long_Float;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_caliper_results_projection_value",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then Value >= -255.0 and then Value <= 255.0;
   --  GetProjectionValues, one value: the mean grey value of column Index
   --  of the sample grid (0-based; Index_Out_Of_Range outside the
   --  profile, always for null).

   procedure Results_Filtered_Value
     (Results : access constant Ks_Caliper_Results_Data;
      Index   : Int32;
      Value   : out Long_Float;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_caliper_results_filtered_value",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then Value >= -255.0 and then Value <= 255.0;
   --  GetFilteredValues, one value: the edge filter at the boundary after
   --  sample Index (the last value is 0).

   ---------------------------------------------------------------------
   --  Ada-only helpers (no C entry points)
   ---------------------------------------------------------------------

   procedure Check_Nested_Run_Params
     (Params : Ks_Caliper_Run_Params;
      Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter;
   --  As Check_Run_Params, naming the parameters "RunParams.
   --  CaliperRunParams.<property>": the caliper parameters of the find
   --  tools (AMV.Kernels.Find_Line, AMV.Kernels.Find_Circle).

   procedure Get_Profile
     (Results  : access constant Ks_Caliper_Results_Data;
      Filtered : Boolean;
      Values   : out Value_Array;
      Status   : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter;
   --  Copies the projection profile (Filtered = False) or the filter
   --  values into Values, which must have exactly as many elements
   --  (Bad_Parameter otherwise; any bounds), for the Ada API's
   --  GetProjectionValues and GetFilteredValues.

end AMV.Kernels.Caliper;
