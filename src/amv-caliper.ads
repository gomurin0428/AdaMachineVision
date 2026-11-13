--  The caliper: the counterpart of Cognex.VisionPro.Caliper's
--  CogCaliperTool, with its run parameters (CogCaliper), scorers
--  (CogCaliperScorerContrast, CogCaliperScorerPosition, ...) and results
--  (CogCaliperResults, CogCaliperResult, CogCaliperEdge).
--
--  A caliper looks for edges along one direction inside a rectangle:
--
--     Tool.Input_Image := Image;
--     Tool.Region.Set_Center_Lengths_Rotation_Skew (100.0, 80.0, 60.0, 20.0,
--                                                   0.3, 0.0);
--     Tool.Run_Params.Contrast_Threshold := 10.0;
--     Tool.Run;
--     if Tool.Results.Count > 0 then
--        X := Tool.Results.Item (0).Position_X;
--
--  Side X of the region is the search direction, side Y the projection
--  direction: the image is sampled about once per pixel over the region,
--  each column of samples across side Y is averaged into a profile along
--  side X, an edge filter of half size FilterHalfSizeInPixels finds the
--  edges (local extrema of at least ContrastThreshold grey levels), and the
--  candidates (single edges, or pairs of edges in Pair mode) are scored and
--  the best MaxResults reported, best first. The algorithm, the scorers and
--  every limit are described in AMV.Kernels.Caliper, the SPARK kernel that
--  does all the work (C API: include/amv_caliper.h). Its proofs cover,
--  besides the absence of run-time errors, that there are at most
--  MaxResults results, sorted by score, every score in [0, 1] and every
--  edge inside the region's search length.
--
--  Coordinates: the region is taken in its own selected space
--  (Image.Get_Transform ("#", Region.Selected_Space_Name)); positions are
--  reported in the input image's selected space ("."). An edge's or a
--  result's Position is its signed distance from the region's centre along
--  the search direction, measured in the selected space.
--
--  Run parameters: Ks_Caliper is the kernel's C-compatible record, so
--  enumerations are Int32 codes (VisionPro's numeric values) and Booleans
--  0 or 1. The Code functions below give the codes:
--
--     Tool.Run_Params.Edge_Mode := Code (Pair);
--     Tool.Run_Params.Edge_0_Polarity := Code (Dark_To_Light);
--
--  Scorers: Single_Edge_Scorers and Two_Edge_Scorers are lists of scorer
--  records (a kind, Enabled and the five parameters of SetXYParameters):
--
--     S : Ks_Caliper_Scorer := New_Scorer (Position);
--     Set_XY_Parameters (S, 5.0, 5.0, 0.0, 0.0, 1.0);
--     Add (Tool.Run_Params.Single_Edge_Scorers, S);
--
--  Results are shared by copies of the tool or of the results (read-only;
--  the next run replaces them) and are not stored in streams.

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Images;
with AMV.Kernels.Caliper;
with AMV.Shapes;
with AMV.Tools;

private with AMV.Shared_Handles;

package AMV.Caliper is

   package KC renames AMV.Kernels.Caliper;

   subtype Int32 is AMV.Kernels.Int32;

   ---------------------------------------------------------------------
   --  Enumerations (C: KS_CALIPER_* codes)
   ---------------------------------------------------------------------

   type Ks_Caliper_Edge_Mode_Constants is (Single_Edge, Pair);
   for Ks_Caliper_Edge_Mode_Constants use (Single_Edge => 1, Pair => 2);

   type Ks_Caliper_Polarity_Constants is
     (Dark_To_Light, Light_To_Dark, Dont_Care);
   for Ks_Caliper_Polarity_Constants use
     (Dark_To_Light => 1, Light_To_Dark => 2, Dont_Care => 3);
   --  Dark_To_Light: the grey level rises along the search direction.

   type Ks_Caliper_Sampling_Mode_Constants is
     (Bilinear_Interpolation, Bilinear_Accurate);
   for Ks_Caliper_Sampling_Mode_Constants use
     (Bilinear_Interpolation => 2, Bilinear_Accurate => 4);
   --  Both sample bilinearly in this implementation.

   type Ks_Caliper_Scorer_Kind is
     (Contrast, Position, Position_Neg, Position_Norm, Position_Norm_Neg,
      Size_Norm, Size_Diff_Norm, Size_Diff_Norm_Asym, Straddle);
   --  (AMV name) One kind per scorer class: Contrast stands for
   --  CogCaliperScorerContrast, Position for CogCaliperScorerPosition, and
   --  so on. The measure of each kind is described in AMV.Kernels.Caliper.

   function Code (Value : Ks_Caliper_Edge_Mode_Constants) return Int32 is
     (Ks_Caliper_Edge_Mode_Constants'Enum_Rep (Value));
   function Code (Value : Ks_Caliper_Polarity_Constants) return Int32 is
     (Ks_Caliper_Polarity_Constants'Enum_Rep (Value));
   function Code (Value : Ks_Caliper_Sampling_Mode_Constants) return Int32
   is (Ks_Caliper_Sampling_Mode_Constants'Enum_Rep (Value));
   function Code (Value : Ks_Caliper_Scorer_Kind) return Int32 is
     (Ks_Caliper_Scorer_Kind'Pos (Value));
   --  The codes the run parameter records hold.

   function Edge_Mode (Code : Int32) return Ks_Caliper_Edge_Mode_Constants
   is (Ks_Caliper_Edge_Mode_Constants'Enum_Val (Code));
   function Polarity (Code : Int32) return Ks_Caliper_Polarity_Constants
   is (Ks_Caliper_Polarity_Constants'Enum_Val (Code));
   function Sampling_Mode
     (Code : Int32) return Ks_Caliper_Sampling_Mode_Constants
   is (Ks_Caliper_Sampling_Mode_Constants'Enum_Val (Code));
   function Scorer_Kind (Code : Int32) return Ks_Caliper_Scorer_Kind is
     (Ks_Caliper_Scorer_Kind'Val (Code));
   --  The enumeration value of a code (Constraint_Error for a code that
   --  is not one).

   ---------------------------------------------------------------------
   --  Scorers (ICogCaliperScorer, CogCaliperScorers)
   ---------------------------------------------------------------------

   subtype Ks_Caliper_Scorer is KC.Ks_Caliper_Scorer;
   --  Kind (a code of Ks_Caliper_Scorer_Kind), Enabled (0 or 1) and the
   --  parameters X0, X1, XC, Y0, Y1 (see AMV.Kernels.Caliper). The default
   --  record is an enabled contrast scorer.

   function New_Scorer (Kind : Ks_Caliper_Scorer_Kind)
      return Ks_Caliper_Scorer;
   --  A new enabled scorer of that kind with its default parameters (the
   --  constructor of the scorer class).

   function Kind (Scorer : Ks_Caliper_Scorer) return Ks_Caliper_Scorer_Kind;
   --  The kind of Scorer. Ks_Bad_Parameter_Exception when Scorer.Kind is
   --  not the code of a kind (a record changed by hand).

   function Enabled (Scorer : Ks_Caliper_Scorer) return Boolean;
   --  Ks_Bad_Parameter_Exception when Scorer.Enabled is not 0 or 1.
   procedure Set_Enabled (Scorer : in out Ks_Caliper_Scorer; Value : Boolean);

   procedure Set_XY_Parameters
     (Scorer             : in out Ks_Caliper_Scorer;
      X0, X1, XC, Y0, Y1 : Real);
   --  SetXYParameters: X0 and X1 must be finite, >= 0 and <= 1.0E150, XC
   --  finite and within +/-1.0E150, Y0 and Y1 within [0, 1]
   --  (Ks_Bad_Parameter_Exception otherwise, Scorer unchanged).

   procedure Get_XY_Parameters
     (Scorer             : Ks_Caliper_Scorer;
      X0, X1, XC, Y0, Y1 : out Real);
   --  GetXYParameters.

   subtype Ks_Caliper_Scorers is KC.Ks_Caliper_Scorers;
   --  A list of at most KC.Max_Scorers (8) scorers: Items (0 .. Count - 1).

   function Count (Scorers : Ks_Caliper_Scorers) return Natural;
   --  Scorers.Count. Ks_Bad_Parameter_Exception when it is not in
   --  0 .. KC.Max_Scorers (a list whose Count was set by hand).

   procedure Add
     (Scorers : in out Ks_Caliper_Scorers;
      Scorer  : Ks_Caliper_Scorer);
   --  Appends Scorer; Ks_Bad_Parameter_Exception when the list is full.

   procedure Remove_At (Scorers : in out Ks_Caliper_Scorers; Index : Natural);
   --  Removes Items (Index); Constraint_Error unless Index < Count.

   procedure Clear (Scorers : in out Ks_Caliper_Scorers);
   --  Removes every scorer.

   ---------------------------------------------------------------------
   --  Run parameters (CogCaliper)
   ---------------------------------------------------------------------

   subtype Ks_Caliper is KC.Ks_Caliper_Run_Params;
   --  The components and defaults of CogCaliper: Edge_Mode (Single_Edge),
   --  Edge_0_Polarity and Edge_1_Polarity (Dont_Care), Edge_0_Position
   --  (0.0) and Edge_1_Position (10.0) (their difference is the expected
   --  width of a pair), Contrast_Threshold (5.0 grey levels),
   --  Filter_Half_Size_In_Pixels (2), Max_Results (1), Sampling_Mode
   --  (Bilinear_Interpolation), Single_Edge_Scorers (one contrast scorer)
   --  and Two_Edge_Scorers (one Size_Diff_Norm scorer). They are checked
   --  when the tool runs (Ks_Bad_Parameter_Exception naming the property,
   --  "RunParams.ContrastThreshold must be >= 0").

   ---------------------------------------------------------------------
   --  Results (CogCaliperResults)
   ---------------------------------------------------------------------

   subtype Ks_Caliper_Edge is KC.Ks_Caliper_Edge;
   --  CogCaliperEdge: Position, Position_X, Position_Y and Contrast (in
   --  grey levels, positive for a dark to light edge).

   subtype Ks_Caliper_Result is KC.Ks_Caliper_Result;
   --  CogCaliperResult: Score (0 .. 1), Position, Position_X, Position_Y,
   --  Width (0 for a single edge), Edge_0 and Edge_1 (equal to Edge_0 for
   --  a single edge).

   subtype Real_Array is KC.Value_Array;

   type Ks_Caliper_Results is tagged private;
   --  The results of a run; empty before the first successful run.

   function Count (Results : Ks_Caliper_Results) return Natural;
   --  The number of results (at most MaxResults).

   function Item
     (Results : Ks_Caliper_Results;
      Index   : Natural) return Ks_Caliper_Result;
   --  Result Index (0-based), best first. Constraint_Error unless
   --  Index < Count.

   function Get_Projection_Values
     (Results : Ks_Caliper_Results) return Real_Array;
   --  GetProjectionValues: the projection profile (indexed from 0, one
   --  value per sample along the search direction; empty before a run).

   function Get_Filtered_Values
     (Results : Ks_Caliper_Results) return Real_Array;
   --  GetFilteredValues: the edge filter at each boundary between
   --  consecutive samples (the last value is 0).

   ---------------------------------------------------------------------
   --  The tool (CogCaliperTool)
   ---------------------------------------------------------------------

   type Ks_Caliper_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image : AMV.Images.Ks_Image_8_Grey;
      Region      : AMV.Shapes.Ks_Rectangle_Affine;
      Run_Params  : Ks_Caliper;
      Results     : Ks_Caliper_Results;
   end record;

   overriding procedure Execute (Tool : in out Ks_Caliper_Tool);
   --  Runs the caliper on Input_Image within Region. Raises
   --  Ks_Image_No_Pixels_Exception for an unallocated image and
   --  Ks_Bad_Parameter_Exception for bad run parameters, a side length of
   --  0 or a region too large (see AMV.Kernels.Caliper); Run reports them
   --  in Run_Status. Finding no edge is a success with no results.

   overriding procedure Reset_Results (Tool : in out Ks_Caliper_Tool);

   ---------------------------------------------------------------------
   --  For the find tools (AMV.Caliper.Find_Line, AMV.Caliper.Find_Circle)
   ---------------------------------------------------------------------

   function Adopt (Handle : KC.Ks_Caliper_Results) return Ks_Caliper_Results;
   --  Results that take over Handle (a new handle the caller owns; null
   --  gives empty results). The caller must not use Handle afterwards.

private

   procedure Destroy (Handle : in out KC.Ks_Caliper_Results);

   package Results_Holders is new AMV.Shared_Handles
     (KC.Ks_Caliper_Results, null, Destroy);

   type Ks_Caliper_Results is tagged record
      Holder : Results_Holders.Holder;
   end record;

end AMV.Caliper;
