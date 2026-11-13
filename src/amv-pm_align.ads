--  Geometric pattern location: the counterpart of Cognex.VisionPro.PMAlign
--  (CogPMAlignTool, CogPMAlignPattern, CogPMAlignRunParams with its zones
--  CogPMAlignZoneAngle and CogPMAlignZoneScale, CogPMAlignResults and
--  CogPMAlignResult).
--
--  A pattern is trained once on an image and then located, turned and
--  scaled, in other images:
--
--     Tool.Pattern.Set_Train_Image (Model_Image);
--     Tool.Pattern.Set_Train_Region (Region_Holders.To_Holder (Rect));
--     Tool.Pattern.Set_Origin (Create_Rigid (0.0, 120.0, 80.0));
--     Tool.Pattern.Train;
--     Tool.Run_Params.Zone_Angle.Configuration := Code (Low_High);
--     Tool.Input_Image := Scene;
--     Tool.Run;
--     if Tool.Results.Count > 0 then
--        Pose := Get_Pose (Tool.Results.Item (0));
--
--  The method is our own (VisionPro's PatMax and PatQuick are Cognex's
--  algorithms, which we do not reproduce): gradient-direction shape
--  matching (Steger's similarity measure) on a coarse-to-fine pyramid,
--  followed (PatMax) by a least squares refinement on sub-pixel edge
--  points. AMV.Kernels.PM_Align, the SPARK kernel that does all the work
--  (C API: include/amv_pm_align.h), describes it, every measure (Score,
--  Coverage, Clutter, FitError, Contrast) and every limit. Its proofs
--  cover, besides the absence of run-time errors, that an untrained
--  pattern never yields results and, of every run, that there are at
--  most ApproximateNumberToFind results, sorted by score, each with a
--  Score in [AcceptThreshold, 1], Coverage and Clutter in [0, 1],
--  FitError >= 0, its rotation and scaling in the zones and its
--  translation within 1.0E150.
--
--  Coordinates. The pattern's coordinates are the train image's selected
--  space mapped by the inverse of Origin (the transform from pattern
--  coordinates to that space; default: the identity, so that pattern
--  coordinates are the train image's selected-space coordinates). The
--  train region is taken in its own selected space. A result's pose maps
--  pattern coordinates to the input image's selected space ("."); it can
--  be passed on as the Unfixtured_From_Fixtured transform of a fixture.
--  The search region (empty: the whole image) restricts where the
--  pattern's features may lie; an empty rasterised region gives no
--  results.
--
--  Run parameters: Ks_PM_Align_Run_Params is the kernel's C-compatible
--  record, so enumerations are Int32 codes (VisionPro's numeric values)
--  and Booleans 0 or 1; the Code functions give the codes. Two enumeration
--  types share literal names (Pat_Max, Pat_Quick), so qualify them:
--
--     Tool.Run_Params.Run_Algorithm :=
--       Code (Ks_PM_Align_Run_Algorithm_Constants'(Pat_Quick));
--
--  Results are shared by copies of the tool or of the results (read-only;
--  the next run replaces them) and are not stored in streams. Patterns
--  are stored in streams by value (see Ks_PM_Align_Pattern).

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Images;
with AMV.Kernels.PM_Align;
with AMV.Shapes.Region_Holders;
with AMV.Tools;
with AMV.Transforms;

private with Ada.Finalization;
private with Ada.Streams;
private with AMV.Shared_Handles;

package AMV.PM_Align is

   package KP renames AMV.Kernels.PM_Align;

   subtype Int32 is AMV.Kernels.Int32;

   ---------------------------------------------------------------------
   --  Enumerations (C: KS_PM_ALIGN_* codes)
   ---------------------------------------------------------------------

   type Ks_PM_Align_Train_Algorithm_Constants is
     (Pat_Max, Pat_Quick, Pat_Max_And_Pat_Quick, Pat_Flex,
      Pat_Max_High_Sensitivity, Pat_Max_Perspective);
   --  CogPMAlignTrainAlgorithmConstants. The first three train the same
   --  model here; the others are not supported (Train raises
   --  Ks_Bad_Parameter_Exception).

   type Ks_PM_Align_Run_Algorithm_Constants is
     (Pat_Max, Pat_Quick, Best_Trained, Pat_Flex, Pat_Max_Perspective);
   --  CogPMAlignRunAlgorithmConstants. Pat_Quick: the grid search alone;
   --  Pat_Max: with the least squares refinement and the edge-based
   --  measures; Best_Trained: Pat_Max unless the pattern was trained with
   --  Pat_Quick only. Pat_Flex and Pat_Max_Perspective are not supported.

   type Ks_PM_Align_Zone_Constants is (Nominal, Low_High);
   --  CogPMAlignZoneConstants.

   function Code (Value : Ks_PM_Align_Train_Algorithm_Constants) return Int32
   is (Ks_PM_Align_Train_Algorithm_Constants'Pos (Value));
   function Code (Value : Ks_PM_Align_Run_Algorithm_Constants) return Int32
   is (Ks_PM_Align_Run_Algorithm_Constants'Pos (Value));
   function Code (Value : Ks_PM_Align_Zone_Constants) return Int32 is
     (Ks_PM_Align_Zone_Constants'Pos (Value));
   --  The codes the parameter records hold.

   function Train_Algorithm
     (Code : Int32) return Ks_PM_Align_Train_Algorithm_Constants
   is (Ks_PM_Align_Train_Algorithm_Constants'Val (Code));
   function Run_Algorithm
     (Code : Int32) return Ks_PM_Align_Run_Algorithm_Constants
   is (Ks_PM_Align_Run_Algorithm_Constants'Val (Code));
   function Zone (Code : Int32) return Ks_PM_Align_Zone_Constants is
     (Ks_PM_Align_Zone_Constants'Val (Code));
   --  The enumeration value of a code (Constraint_Error for a code that
   --  is not one).

   ---------------------------------------------------------------------
   --  Run parameters (CogPMAlignRunParams)
   ---------------------------------------------------------------------

   subtype Ks_PM_Align_Zone_Angle is KP.Ks_PM_Align_Zone_Angle;
   --  CogPMAlignZoneAngle: Configuration (Nominal), Low (-Pi), High (Pi),
   --  Nominal (0.0), radians.

   subtype Ks_PM_Align_Zone_Scale is KP.Ks_PM_Align_Zone_Scale;
   --  CogPMAlignZoneScale: Configuration (Nominal), Low (0.9), High (1.1),
   --  Nominal (1.0).

   subtype Ks_PM_Align_Run_Params is KP.Ks_PM_Align_Run_Params;
   --  The components and AMV defaults of CogPMAlignRunParams:
   --  Accept_Threshold (0.5), Coarse_Accept_Threshold (0.3) with
   --  Coarse_Accept_Threshold_Enabled (0), Contrast_Threshold (10.0, a
   --  gradient magnitude in grey levels per pixel), Outside_Region_
   --  Threshold (0.1), Approximate_Number_To_Find (1), Run_Algorithm
   --  (Pat_Max), Score_Using_Clutter (1), Timeout_Enabled (0) and Timeout
   --  (10000.0 ms; checked but not used: the kernel has no clock),
   --  Zone_Angle, Zone_Scale and XY_Overlap (1.0, in [0, 1]: a result
   --  whose footprint, the trained features' bounding box mapped by its
   --  pose, shares more than that fraction of the smaller footprint with
   --  a better result's is dropped). They are checked when the tool runs
   --  (Ks_Bad_Parameter_Exception naming the property,
   --  "RunParams.AcceptThreshold must be in [0, 1]").

   ---------------------------------------------------------------------
   --  The pattern (CogPMAlignPattern)
   ---------------------------------------------------------------------

   type Ks_PM_Align_Pattern is tagged private;
   --  The train inputs and, once trained, the model. Default: no train
   --  image, no train region (the whole image), Origin the identity,
   --  Train_Algorithm Pat_Max, Grain_Limit_Auto_Select True,
   --  Grain_Limit_Coarse 8.0, Grain_Limit_Fine 1.0, Ignore_Polarity
   --  False; not trained. Copies are independent (assignment duplicates
   --  the model; the train image shares its pixels as images do). Every
   --  setter untrains the pattern.
   --
   --  Streams: 'Write stores the train image (by value, as AMV.Images
   --  does), the train region, Origin, the train parameters, the model
   --  (each level's feature spacing, each feature's coordinates and
   --  normal, the ignored points of the mask) and the train image mask
   --  with its offsets; 'Read also reads the format written before the
   --  mask (no mask then) and checks every value
   --  of the model (AMV.Kernels.PM_Align). A malformed stream (one that
   --  ends early, a train region with an unknown tag, a bad value)
   --  raises Ks_Image_File_Exception and leaves the pattern as it was.

   function Train_Image
     (Pattern : Ks_PM_Align_Pattern) return AMV.Images.Ks_Image_8_Grey;
   procedure Set_Train_Image
     (Pattern : in out Ks_PM_Align_Pattern;
      Image   : AMV.Images.Ks_Image_8_Grey);
   --  TrainImage.

   function Train_Region
     (Pattern : Ks_PM_Align_Pattern)
      return AMV.Shapes.Region_Holders.Holder;
   procedure Set_Train_Region
     (Pattern : in out Ks_PM_Align_Pattern;
      Region  : AMV.Shapes.Region_Holders.Holder);
   --  TrainRegion (any region, in its own selected space; empty: the
   --  whole train image).

   function Origin
     (Pattern : Ks_PM_Align_Pattern)
      return AMV.Transforms.Ks_Transform_2D_Linear;
   procedure Set_Origin
     (Pattern : in out Ks_PM_Align_Pattern;
      Origin  : AMV.Transforms.Ks_Transform_2D_Linear);
   --  Origin: the pattern's coordinate frame, as the transform from
   --  pattern coordinates to the train image's selected space. The pose of
   --  a result is the same transform for the found instance. Checked when
   --  the pattern is trained (Ks_Transform_Singular_Exception when it has
   --  no inverse).

   function Train_Algorithm
     (Pattern : Ks_PM_Align_Pattern)
      return Ks_PM_Align_Train_Algorithm_Constants;
   procedure Set_Train_Algorithm
     (Pattern : in out Ks_PM_Align_Pattern;
      Value   : Ks_PM_Align_Train_Algorithm_Constants);
   --  TrainAlgorithm (Ks_Bad_Parameter_Exception for the unsupported
   --  algorithms).

   function Grain_Limit_Auto_Select
     (Pattern : Ks_PM_Align_Pattern) return Boolean;
   procedure Set_Grain_Limit_Auto_Select
     (Pattern : in out Ks_PM_Align_Pattern;
      Value   : Boolean);
   function Grain_Limit_Coarse (Pattern : Ks_PM_Align_Pattern) return Real;
   procedure Set_Grain_Limit_Coarse
     (Pattern : in out Ks_PM_Align_Pattern;
      Value   : Real);
   function Grain_Limit_Fine (Pattern : Ks_PM_Align_Pattern) return Real;
   procedure Set_Grain_Limit_Fine
     (Pattern : in out Ks_PM_Align_Pattern;
      Value   : Real);
   --  GrainLimitAutoSelect, GrainLimitCoarse, GrainLimitFine: our meaning
   --  is the pyramid levels used (level k has a grain of 2**k pixels;
   --  without auto selection the finest level is floor (log2 Fine) and the
   --  coarsest floor (log2 Coarse)). 1 <= Fine <= Coarse <= 32
   --  (Ks_Bad_Parameter_Exception otherwise, the pattern unchanged).

   function Ignore_Polarity (Pattern : Ks_PM_Align_Pattern) return Boolean;
   procedure Set_Ignore_Polarity
     (Pattern : in out Ks_PM_Align_Pattern;
      Value   : Boolean);
   --  IgnorePolarity: match edges whatever the direction of their
   --  contrast.

   function Train_Image_Mask
     (Pattern : Ks_PM_Align_Pattern) return AMV.Images.Ks_Image_8_Grey;
   procedure Set_Train_Image_Mask
     (Pattern : in out Ks_PM_Align_Pattern;
      Mask    : AMV.Images.Ks_Image_8_Grey);
   function Train_Image_Mask_Offset_X
     (Pattern : Ks_PM_Align_Pattern) return Integer;
   procedure Set_Train_Image_Mask_Offset_X
     (Pattern : in out Ks_PM_Align_Pattern;
      Value   : Integer);
   function Train_Image_Mask_Offset_Y
     (Pattern : Ks_PM_Align_Pattern) return Integer;
   procedure Set_Train_Image_Mask_Offset_Y
     (Pattern : in out Ks_PM_Align_Pattern;
      Value   : Integer);
   --  TrainImageMask, TrainImageMaskOffsetX, TrainImageMaskOffsetY (AMV's
   --  meaning): the parts of the train image that training leaves out.
   --  Mask pixel (U, V) covers train image pixel (U + Offset_X, V +
   --  Offset_Y), in pixel space; a mask pixel of value 0 marks that pixel
   --  "don't care", any other value (and every pixel the mask does not
   --  cover) "care". Training takes no feature, at any level, near a
   --  don't-care pixel, and a result's Clutter does not count the edges
   --  found where the pattern's left-out part lies (AMV.Kernels.PM_Align,
   --  "The train image mask"). Default: no mask (an unallocated image) and
   --  offsets 0.

   procedure Train (Pattern : in out Ks_PM_Align_Pattern);
   --  Train: builds the model. Raises Ks_Image_No_Pixels_Exception for an
   --  unallocated train image, Ks_Bad_Parameter_Exception for a region
   --  without pixels of the image or too few edges in it,
   --  Ks_Transform_Singular_Exception for an Origin without inverse; the
   --  pattern is then untrained.

   function Trained (Pattern : Ks_PM_Align_Pattern) return Boolean;
   procedure Untrain (Pattern : in out Ks_PM_Align_Pattern);
   --  Trained, Untrain.

   subtype Ks_PM_Align_Feature is KP.Ks_PM_Align_Feature;
   subtype Ks_PM_Align_Feature_Array is KP.Ks_PM_Align_Feature_Array;

   function Get_Trained_Features
     (Pattern : Ks_PM_Align_Pattern;
      Fine    : Boolean := True) return Ks_PM_Align_Feature_Array;
   --  (AMV name) The trained features of the finest level (Fine) or of the
   --  coarsest, each a point and its unit normal in pattern coordinates
   --  (VisionPro draws them with CreateGraphicsFine and
   --  CreateGraphicsCoarse). Ks_Operator_Not_Trained_Exception for an
   --  untrained pattern.

   ---------------------------------------------------------------------
   --  Results (CogPMAlignResults, CogPMAlignResult)
   ---------------------------------------------------------------------

   subtype Ks_PM_Align_Result is KP.Ks_PM_Align_Result;
   --  CogPMAlignResult: Score, Coverage, Clutter, Fit_Error, Contrast,
   --  Outside_Region_Feature_Proportion, ID (its index), Fine_Stage (1 for
   --  PatMax) and the pose (Translation_X, Translation_Y, Rotation,
   --  Scaling).

   function Get_Pose
     (Result : Ks_PM_Align_Result)
      return AMV.Transforms.Ks_Transform_2D_Linear;
   --  GetPose: the similarity transform from pattern coordinates to the
   --  input image's selected space.

   type Ks_PM_Align_Results is tagged private;
   --  The results of a run; empty before the first successful run.

   function Count (Results : Ks_PM_Align_Results) return Natural;
   --  The number of results (at most ApproximateNumberToFind).

   function Item
     (Results : Ks_PM_Align_Results;
      Index   : Natural) return Ks_PM_Align_Result;
   --  Item (Index), 0-based, best first; Constraint_Error outside 0 ..
   --  Count - 1.

   ---------------------------------------------------------------------
   --  The tool (CogPMAlignTool)
   ---------------------------------------------------------------------

   type Ks_PM_Align_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image   : AMV.Images.Ks_Image_8_Grey;
      Search_Region : AMV.Shapes.Region_Holders.Holder;
      Pattern       : Ks_PM_Align_Pattern;
      Run_Params    : Ks_PM_Align_Run_Params;
      Results       : Ks_PM_Align_Results;
      Search_Image_Mask          : AMV.Images.Ks_Image_8_Grey;
      Search_Image_Mask_Offset_X : Integer := 0;
      Search_Image_Mask_Offset_Y : Integer := 0;
   end record;
   --  CogPMAlignTool. Search_Image_Mask and its offsets stand for
   --  CogPMAlignRunParams.SearchImageMask, SearchImageMaskOffsetX and
   --  SearchImageMaskOffsetY (components of the tool here, since the run
   --  parameters are the kernel's C record). AMV's meaning: mask pixel
   --  (U, V) covers input pixel (U + Offset_X, V + Offset_Y); the pixels
   --  under mask pixels of value 0 are left out of the search region
   --  (AMV.Regions.Restrict_To_Mask), so they count as outside it: no
   --  feature matches there, a feature over them counts towards
   --  Outside_Region_Threshold (raise it when the mask covers much of an
   --  instance) and Clutter does not count edges there. Default: no mask
   --  (an unallocated image) and offsets 0. Run fails (Run_Status Error) with
   --  Ks_Operator_Not_Trained_Exception for an untrained pattern,
   --  Ks_Bad_Parameter_Exception for bad run parameters,
   --  Ks_Image_No_Pixels_Exception for an unallocated input image.

   overriding procedure Execute (Tool : in out Ks_PM_Align_Tool);
   overriding procedure Reset_Results (Tool : in out Ks_PM_Align_Tool);

private

   --  The kernel's pattern handle, owned by each pattern object: null
   --  until a setter or Train needs it (the kernel reads null as an
   --  untrained pattern with the default parameters); assignment
   --  duplicates it, finalization destroys it, the stream attributes store
   --  the train parameters and the model by value.

   type Pattern_Handle is new Ada.Finalization.Controlled with record
      Handle        : KP.Ks_PM_Align_Pattern;
      Mask          : AMV.Images.Ks_Image_8_Grey;
      Mask_Offset_X : Integer := 0;
      Mask_Offset_Y : Integer := 0;
   end record;
   --  The model and the train image mask, which the stream attributes
   --  store together (the mask came with the format "KSPC").

   overriding procedure Adjust (Item : in out Pattern_Handle);
   overriding procedure Finalize (Item : in out Pattern_Handle);

   procedure Write_Handle
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : Pattern_Handle);
   procedure Read_Handle
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Pattern_Handle);

   for Pattern_Handle'Write use Write_Handle;
   for Pattern_Handle'Read use Read_Handle;

   type Ks_PM_Align_Pattern is tagged record
      Train_Image  : AMV.Images.Ks_Image_8_Grey;
      Train_Region : AMV.Shapes.Region_Holders.Holder;
      Origin       : AMV.Transforms.Ks_Transform_2D_Linear;
      Model        : Pattern_Handle;
   end record;

   procedure Read_Pattern
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_PM_Align_Pattern);
   for Ks_PM_Align_Pattern'Read use Read_Pattern;
   --  Reads the components in the order of the predefined 'Write into a
   --  fresh pattern and assigns it to Item only when all were read.

   procedure Destroy (Handle : in out KP.Ks_PM_Align_Results);

   package Results_Holders is new AMV.Shared_Handles
     (KP.Ks_PM_Align_Results, null, Destroy);

   type Ks_PM_Align_Results is tagged record
      Holder : Results_Holders.Holder;
   end record;

end AMV.PM_Align;
