--  The CNL search tool: the counterparts of CogCNLSearchTool, its pattern
--  CogCNLSearchPattern, its run parameters CogCNLSearchRunParams and its
--  results CogCNLSearchResults and CogCNLSearchResult
--  (Cognex.VisionPro.CNLSearch): normalised correlation search for a
--  trained grey-level pattern, translation only.
--
--     Tool.Pattern.Set_Train_Image (Train);
--     Tool.Pattern.Set_Train_Region
--       (AMV.Shapes.Region_Holders.To_Holder (Rect));
--     Tool.Pattern.Set_Origin_X (100.0);
--     Tool.Pattern.Set_Origin_Y (60.0);
--     Tool.Pattern.Train;
--     Tool.Input_Image := Image;
--     Tool.Run_Params.Max_Results := 3;
--     Tool.Run;
--     for I in 0 .. Tool.Results.Count - 1 loop
--        Put (Tool.Results.Item (I).Location_X);
--
--  The pattern. Train copies from Train_Image the pixels of the pixel
--  aligned bounding box of Train_Region (rasterised in the train image
--  with AMV.Regions; an empty holder means the whole image): 8 .. 1024
--  pixels along each side, not all of one grey level. With
--  Train_Region_Mode Pixel_Aligned_Bounding_Box_Adjust_Mask (the default,
--  as in VisionPro) the pixels of the box that the region does not contain
--  are don't-care pixels of the pattern (see the train image mask below)
--  for Linear_Search. With Train_Region_Mode Affine_Transform the train
--  region must be an affine rectangle (Ks_Rectangle_Affine) lying entirely
--  in the train image, and the pattern is that rectangle resampled
--  upright (see "The AffineTransform region mode" below). Its origin is
--  (Origin_X, Origin_Y) in the train image's selected space (VisionPro's
--  default 70, 70). Training keeps a copy of everything the search needs
--  (pixels, pyramid levels, statistics, the origin in the pattern's
--  pixels), so the train image may change afterwards; setting any
--  training input (Set_Train_Image, Set_Train_Region, Set_Origin_X, ...)
--  untrains the pattern, as does a failed Train. Train_Image shares its
--  pixels with the image given (as every image assignment does).
--
--  The train image mask (Train_Image_Mask and its offsets, AMV's meaning)
--  leaves parts of the pattern out of the correlation: the score of a
--  window does not depend on its pixels under the pattern's don't-care
--  pixels, so content that changes from part to part there (a label, a
--  date code, a reflection) does not lower the score of a match. Mask
--  pixel (U, V) covers train image pixel (U + Offset_X, V + Offset_Y);
--  a mask pixel of value 0 marks that pixel "don't care", any other value
--  (and every pixel the mask does not cover) "care". The score, the
--  contrast and the pyramid levels are then computed over the cared-for
--  pixels only (AMV.Kernels.CNL_Search, "The train image mask"); a
--  Linear_Search run with a mask takes about three times as long as one
--  without.
--
--  The search. Run scores the windows of Input_Image as large as the
--  pattern that lie in the pixel aligned bounding box of Search_Region
--  (rasterised in the input image; empty: the whole image), and with
--  partial matches (below) those that cross its sides, with r**2 of
--  the zero-mean normalised cross-correlation (Pearson's r), 0 for a
--  window of the opposite contrast unless Ignore_Polarity is set and the
--  algorithm is Linear_Search, and reports the best local maxima scoring
--  at least Accept_Threshold, best first, without windows that overlap by
--  more than XY_Overlap, at most Max_Results of them. Linear_Search scores
--  every window; Linear_CNLPAS (the pattern must be trained with it)
--  searches a coarse-to-fine pyramid, much faster on large images, and
--  stops early once Max_Results results that do not overlap score at
--  least Confusion_Threshold. Accuracy chooses the sub-pixel refinement:
--  Very_Fine (a quadratic surface fitted to the 3 x 3 scores), Fine (a
--  parabola per axis) or Coarse (whole pixels). Location_X, Location_Y is
--  the pattern's origin at the match, in Input_Image's selected space
--  (with a non-similarity transform between pixel space and that space the
--  pattern still moves by translation in pixel space; only its location is
--  mapped). Contrast is the ratio of the standard deviation of the
--  matched window to that of the pattern. AMV.Kernels.CNL_Search
--  describes the algorithm, the score and every limit in detail.
--
--  The AffineTransform region mode (AMV.Kernels.CNL_Search.Region_Modes
--  has the details). An affine rectangle is resampled into an upright
--  image by the affine transform tool's kernel with its default run
--  parameters (one pixel per pixel of the rectangle's sides, bilinear,
--  0 outside the image). Training in that mode (Train_Region_Mode
--  Affine_Transform) makes the resampled train region the pattern, so a
--  part trained turned by the rectangle's rotation (and skew) is
--  trained upright; its origin is carried along by the resampling, so it
--  marks the same physical point of the part, and a result's location is
--  that point in the search image (AMV's rule). The train image mask is
--  resampled with the same rectangle (nearest neighbour; AMV's rule).
--  Searching in that mode (Run_Params.Search_Region_Mode Affine_Transform
--  with an affine rectangle as Search_Region) searches the resampled
--  rectangle and maps every location back into Input_Image's selected
--  space; since results have no angle, the pattern is searched for in the
--  rectangle's frame, which finds the parts turned with the rectangle.
--  With any other search region (or none) that mode searches the region's
--  pixel aligned bounding box, as VisionPro documents.
--
--  Partial matches (Linear_Search only; AMV's meaning of VisionPro's run
--  parameters PartialMatchLimitLeft, ..., PartialMatchReduceScore). With
--  Run_Params.Partial_Match_Limit_Left (_Right, _Up, _Down) the pattern's
--  window may cross the left (right, top, bottom) side of the search area
--  (the bounding box of Search_Region, not the image) by that many of its
--  columns (rows), at most half the trained pattern's width (height):
--  such a window is scored over the part inside the area only, and scores
--  0 when fewer than a quarter of the pattern's cared-for pixels lie there
--  (with a train image mask) or when those are flat. With
--  Partial_Match_Reduce_Score = 1 its score is multiplied by the fraction
--  of the pattern's cared-for pixels inside. Edge_Hit of a result is the
--  sum of Left, Top, Right and Bottom for the sides of the search area its
--  window crosses (None inside). The defaults, 0, search inside the area
--  only, exactly as before; non-zero limits with Linear_CNLPAS are
--  rejected with Ks_Bad_Parameter_Exception.
--
--  Not offered (VisionPro has them): the NonLinearCNLPAS algorithm
--  (rejected with Ks_Bad_Parameter_Exception), the pattern's own partial
--  match limits (CogCNLSearchPattern's
--  PartialMatchLimit*, PartialMatchLimitsUsePattern), edge scores
--  (EdgeThreshold*), the search point (SearchPoint*), and the result
--  graphics.
--
--  Failures (Run_Status Error, results cleared; or raised by Train):
--  Ks_Image_No_Pixels_Exception for an unallocated Input_Image or
--  Train_Image; Ks_Operator_Not_Trained_Exception for a run with an
--  untrained pattern ("Pattern is not trained") and for the trained
--  properties of an untrained pattern;
--  Ks_Image_Bad_Selected_Space_Name_Exception for a region in an unknown
--  space; Ks_Bad_Parameter_Exception for run parameters out of range
--  ("RunParams.AcceptThreshold must be in 0 .. 1"), an algorithm or
--  accuracy the pattern was not trained for, partial match limits beyond
--  half the trained pattern's side or not 0 with Linear_CNLPAS
--  ("RunParams.PartialMatchLimitLeft must be in 0 .. TrainedPatternWidth
--  / 2"), a Partial_Match_Reduce_Score other than 0 and 1, a train region
--  outside the train image or too small or too large, a train region that
--  is not an affine rectangle with Train_Region_Mode Affine_Transform
--  ("TrainRegion must be an affine rectangle for TrainRegionMode
--  AffineTransform"), a flat pattern, a
--  train image mask that leaves fewer than 64 pixels of the pattern cared
--  for, and a location beyond 1.0E150.
--
--  Copies. Assigning a pattern copies it (its trained data is duplicated;
--  the pixels of the train image and of the mask are shared). Results are
--  shared by copies and read only.
--
--  Streams. Ks_CNL_Search_Pattern has 'Write and 'Read that store it by
--  value: a format code, the training parameters (Algorithms, Accuracies,
--  Ignore_Polarity as Int32, Origin_X and Origin_Y as Real,
--  Train_Region_Mode as Int32, Affine_Transform included), Train_Image
--  (AMV.Images' format), Train_Region (the holder's own format),
--  Train_Image_Mask (an image, unallocated for none) and its offsets
--  (Int32 each), a flag (Unsigned_32, 0 or 1) telling whether it is
--  trained, and for a trained pattern its trained origin (two Reals, the
--  pattern's pixel coordinates), its pixels (Get_Trained_Pattern_Image,
--  as an image) and its care flags at full resolution (an image of the
--  same size, 0 for a don't-care pixel; unallocated when it was trained
--  without a mask). 'Read also reads the format written before the mask
--  (format code "KSCN": no mask, no care flags). It treats the stream as
--  untrusted: every value is checked by the kernel as Train checks it
--  (the format code, the flag, the parameters' ranges, the pattern's size
--  and contrast, the care flags' size and number, the origin) and the
--  pattern's pyramid, care flags and statistics are rebuilt from the
--  stored pixels and flags, so a trained pattern reads back trained on
--  exactly the pixels and flags it was trained with, even when its
--  Train_Image or its mask has changed since. A malformed stream raises
--  Ks_Image_File_Exception (format code, flag, images, a stream that
--  ends early, a train region with an unknown tag) or
--  Ks_Bad_Parameter_Exception (values out of range), and leaves the
--  target unchanged. Results are not stored.
--
--  The work is done by the SPARK kernel AMV.Kernels.CNL_Search and its
--  child Region_Modes (C: ks_cnl_search_*, include/amv_cnl_search.h),
--  which prove the absence
--  of run-time errors and of every run: scores in [0, 1] and at least
--  Accept_Threshold, at most Max_Results results sorted by score, every
--  window inside the search area extended by the partial match limits,
--  Edge_Hit exactly the sides of the search area the window crosses (None
--  for every result with the limits 0), every location within 1.0E150,
--  and no results from an untrained pattern.

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Images;
with AMV.Kernels;
with AMV.Kernels.CNL_Search;
with AMV.Shapes.Region_Holders;
with AMV.Tools;

private with Ada.Finalization;
private with Ada.Streams;
private with AMV.Shared_Handles;

package AMV.CNL_Search is

   package KC renames AMV.Kernels.CNL_Search;

   ---------------------------------------------------------------------
   --  Enumerations (VisionPro's values; the records hold the codes)
   ---------------------------------------------------------------------

   subtype Ks_CNL_Search_Algorithm_Constants is AMV.Kernels.Int32
     range 0 .. 7;
   --  CogCNLSearchAlgorithmConstants. Flags: a pattern's Algorithms may
   --  name several (Linear_Search + Linear_CNLPAS, with use type
   --  AMV.Kernels.Int32); a run's Algorithm names one.

   Linear_Search     : constant Ks_CNL_Search_Algorithm_Constants :=
     KC.Algorithm_Linear_Search;
   Linear_CNLPAS     : constant Ks_CNL_Search_Algorithm_Constants :=
     KC.Algorithm_Linear_CNLPAS;
   Non_Linear_CNLPAS : constant Ks_CNL_Search_Algorithm_Constants :=
     KC.Algorithm_Non_Linear_CNLPAS;
   --  Not supported.

   subtype Ks_CNL_Search_Accuracy_Constants is AMV.Kernels.Int32
     range 0 .. 7;
   --  CogCNLSearchAccuracyConstants. Flags, as the algorithms.

   Very_Fine : constant Ks_CNL_Search_Accuracy_Constants :=
     KC.Accuracy_Very_Fine;
   Fine      : constant Ks_CNL_Search_Accuracy_Constants :=
     KC.Accuracy_Fine;
   Coarse    : constant Ks_CNL_Search_Accuracy_Constants :=
     KC.Accuracy_Coarse;

   subtype Ks_CNL_Search_Edge_Hit_Constants is AMV.Kernels.Int32
     range 0 .. 31;
   --  CogCNLSearchEdgeHitConstants. Flags: a result's Edge_Hit is the sum
   --  of Left, Top, Right and Bottom for the sides of the search area its
   --  window crosses (partial matches), None when it crosses none; Unknown
   --  is never reported.

   None    : constant Ks_CNL_Search_Edge_Hit_Constants := KC.Edge_Hit_None;
   Unknown : constant Ks_CNL_Search_Edge_Hit_Constants :=
     KC.Edge_Hit_Unknown;
   Left    : constant Ks_CNL_Search_Edge_Hit_Constants := KC.Edge_Hit_Left;
   Top     : constant Ks_CNL_Search_Edge_Hit_Constants := KC.Edge_Hit_Top;
   Right   : constant Ks_CNL_Search_Edge_Hit_Constants := KC.Edge_Hit_Right;
   Bottom  : constant Ks_CNL_Search_Edge_Hit_Constants :=
     KC.Edge_Hit_Bottom;

   subtype Ks_Region_Mode_Constants is AMV.Kernels.Int32 range 0 .. 2;
   --  CogRegionModeConstants (Cognex.VisionPro), for Search_Region_Mode.

   Pixel_Aligned_Bounding_Box_Adjust_Mask : constant
     Ks_Region_Mode_Constants :=
       KC.Region_Mode_Pixel_Aligned_Bounding_Box_Adjust_Mask;
   Pixel_Aligned_Bounding_Box             : constant
     Ks_Region_Mode_Constants :=
       KC.Region_Mode_Pixel_Aligned_Bounding_Box;
   Affine_Transform                       : constant
     Ks_Region_Mode_Constants := KC.Region_Mode_Affine_Transform;
   --  Search_Region_Mode supports Pixel_Aligned_Bounding_Box and
   --  Affine_Transform; Train_Region_Mode all three.

   ---------------------------------------------------------------------
   --  Run parameters (CogCNLSearchRunParams)
   ---------------------------------------------------------------------

   subtype Ks_CNL_Search_Run_Params is KC.Ks_CNL_Search_Run_Params;
   --  A record with the components Algorithm (Linear_Search),
   --  Accuracy (Very_Fine), Max_Results (1, 1 .. 1000), Search_Region_Mode
   --  (Pixel_Aligned_Bounding_Box, or Affine_Transform: an affine
   --  rectangle as Search_Region is then resampled, see above),
   --  Accept_Threshold (0.3, 0 .. 1),
   --  Confusion_Threshold (0.5, Accept_Threshold .. 1), XY_Overlap
   --  (1.0, 0 .. 1), Partial_Match_Limit_Left and Partial_Match_Limit_Right
   --  (0, 0 .. Trained_Pattern_Width / 2), Partial_Match_Limit_Up and
   --  Partial_Match_Limit_Down (0, 0 .. Trained_Pattern_Height / 2; all 0
   --  with Linear_CNLPAS) and Partial_Match_Reduce_Score (0, 0 or 1; see
   --  "Partial matches" above). Algorithm and Accuracy must be among the
   --  pattern's trained Algorithms and Accuracies.

   ---------------------------------------------------------------------
   --  The pattern (CogCNLSearchPattern)
   ---------------------------------------------------------------------

   type Ks_CNL_Search_Pattern is tagged private;
   --  Default: untrained, no train image, an empty train region (the
   --  whole train image), no train image mask (offsets 0, 0), origin
   --  (70, 70), Algorithms Linear_Search, Accuracies Very_Fine,
   --  Ignore_Polarity False, Train_Region_Mode
   --  Pixel_Aligned_Bounding_Box_Adjust_Mask.

   function Train_Image (Pattern : Ks_CNL_Search_Pattern)
      return AMV.Images.Ks_Image_8_Grey;
   procedure Set_Train_Image
     (Pattern : in out Ks_CNL_Search_Pattern;
      Value   : AMV.Images.Ks_Image_8_Grey);

   function Train_Region (Pattern : Ks_CNL_Search_Pattern)
      return AMV.Shapes.Region_Holders.Holder;
   procedure Set_Train_Region
     (Pattern : in out Ks_CNL_Search_Pattern;
      Value   : AMV.Shapes.Region_Holders.Holder);
   --  The region in the train image (in the space its Selected_Space_Name
   --  names); empty: the whole train image.

   function Origin_X (Pattern : Ks_CNL_Search_Pattern) return Real;
   function Origin_Y (Pattern : Ks_CNL_Search_Pattern) return Real;
   procedure Set_Origin_X (Pattern : in out Ks_CNL_Search_Pattern;
                           Value   : Real);
   procedure Set_Origin_Y (Pattern : in out Ks_CNL_Search_Pattern;
                           Value   : Real);
   --  The origin in the train image's selected space; finite and within
   --  1.0E150 (Ks_Bad_Parameter_Exception otherwise).

   function Algorithms (Pattern : Ks_CNL_Search_Pattern)
      return Ks_CNL_Search_Algorithm_Constants;
   procedure Set_Algorithms
     (Pattern : in out Ks_CNL_Search_Pattern;
      Value   : Ks_CNL_Search_Algorithm_Constants);
   --  The algorithms to train for: Linear_Search, Linear_CNLPAS or
   --  Linear_Search + Linear_CNLPAS (Ks_Bad_Parameter_Exception
   --  otherwise).

   function Accuracies (Pattern : Ks_CNL_Search_Pattern)
      return Ks_CNL_Search_Accuracy_Constants;
   procedure Set_Accuracies
     (Pattern : in out Ks_CNL_Search_Pattern;
      Value   : Ks_CNL_Search_Accuracy_Constants);
   --  The accuracies to train for: a non-empty combination of Very_Fine,
   --  Fine and Coarse.

   function Ignore_Polarity (Pattern : Ks_CNL_Search_Pattern)
      return Boolean;
   procedure Set_Ignore_Polarity
     (Pattern : in out Ks_CNL_Search_Pattern;
      Value   : Boolean);
   --  Match windows of either contrast (Linear_Search only).

   function Train_Image_Mask (Pattern : Ks_CNL_Search_Pattern)
      return AMV.Images.Ks_Image_8_Grey;
   procedure Set_Train_Image_Mask
     (Pattern : in out Ks_CNL_Search_Pattern;
      Value   : AMV.Images.Ks_Image_8_Grey);
   function Train_Image_Mask_Offset_X (Pattern : Ks_CNL_Search_Pattern)
      return Integer;
   procedure Set_Train_Image_Mask_Offset_X
     (Pattern : in out Ks_CNL_Search_Pattern;
      Value   : Integer);
   function Train_Image_Mask_Offset_Y (Pattern : Ks_CNL_Search_Pattern)
      return Integer;
   procedure Set_Train_Image_Mask_Offset_Y
     (Pattern : in out Ks_CNL_Search_Pattern;
      Value   : Integer);
   --  TrainImageMask, TrainImageMaskOffsetX, TrainImageMaskOffsetY (AMV's
   --  meaning, see "The train image mask" above): mask pixel (U, V) covers
   --  train image pixel (U + Offset_X, V + Offset_Y), in pixel space; a
   --  mask pixel of value 0 marks that pixel "don't care", any other value
   --  (and every pixel the mask does not cover) "care". Default: no mask
   --  (an unallocated image) and offsets 0. Every setter untrains the
   --  pattern; Train_Image_Mask shares its pixels with the image given.

   function Train_Region_Mode (Pattern : Ks_CNL_Search_Pattern)
      return Ks_Region_Mode_Constants;
   procedure Set_Train_Region_Mode
     (Pattern : in out Ks_CNL_Search_Pattern;
      Value   : AMV.Kernels.Int32);
   --  TrainRegionMode (default Pixel_Aligned_Bounding_Box_Adjust_Mask, as
   --  in VisionPro): with Adjust_Mask the pixels of the train region's box
   --  that the region does not contain are don't-care pixels of the
   --  pattern (as Train_Image_Mask marks them, and together with it) when
   --  the pattern is trained for Linear_Search; for Linear_CNLPAS alone
   --  the pattern is the whole box, as VisionPro does. With
   --  Pixel_Aligned_Bounding_Box every pixel of the box is part of the
   --  pattern. A rectangle along the axes gives the same pattern in both.
   --  With Affine_Transform the train region must be an affine rectangle
   --  that lies entirely in the train image, and the pattern is that
   --  rectangle resampled upright (see "The AffineTransform region mode"
   --  above). Any other value raises Ks_Bad_Parameter_Exception. The
   --  setter untrains the pattern.

   procedure Train (Pattern : in out Ks_CNL_Search_Pattern);
   --  Trains the pattern (see above). Raises the exceptions listed at the
   --  top; the pattern is untrained after a failure.

   function Trained (Pattern : Ks_CNL_Search_Pattern) return Boolean;

   procedure Untrain (Pattern : in out Ks_CNL_Search_Pattern);
   --  Frees the trained data; the training inputs stay.

   function Trained_Pattern_Width (Pattern : Ks_CNL_Search_Pattern)
      return Natural;
   function Trained_Pattern_Height (Pattern : Ks_CNL_Search_Pattern)
      return Natural;
   --  The size of the trained pattern in pixels.
   --  Ks_Operator_Not_Trained_Exception for an untrained pattern.

   function Get_Trained_Pattern_Image (Pattern : Ks_CNL_Search_Pattern)
      return AMV.Images.Ks_Image_8_Grey;
   --  A new image holding the trained pattern's pixels (default
   --  coordinate spaces). Ks_Operator_Not_Trained_Exception for an
   --  untrained pattern.

   ---------------------------------------------------------------------
   --  Results (CogCNLSearchResults, CogCNLSearchResult)
   ---------------------------------------------------------------------

   subtype Ks_CNL_Search_Result is KC.Ks_CNL_Search_Result;
   --  A record with the components ID (its index), Accepted (1),
   --  Contrast_Computed (1), Edge_Hit (the sides of the search area the
   --  window crosses, None inside), Score (0 .. 1), Location_X and
   --  Location_Y (the origin in Input_Image's selected space) and Contrast.

   type Ks_CNL_Search_Results is tagged private;
   --  The results of the last successful run, best first; none before a
   --  run and after a failed one.

   function Count (Results : Ks_CNL_Search_Results) return Natural;

   function Item
     (Results : Ks_CNL_Search_Results;
      Index   : Natural) return Ks_CNL_Search_Result;
   --  0-based; Constraint_Error outside 0 .. Count - 1.

   ---------------------------------------------------------------------
   --  The tool (CogCNLSearchTool)
   ---------------------------------------------------------------------

   type Ks_CNL_Search_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image   : AMV.Images.Ks_Image_8_Grey;
      Search_Region : AMV.Shapes.Region_Holders.Holder;
      --  Empty: the whole image.
      Pattern       : Ks_CNL_Search_Pattern;
      Run_Params    : Ks_CNL_Search_Run_Params;
      Results       : Ks_CNL_Search_Results;
      --  Set by Run.
   end record;

   overriding procedure Execute (Tool : in out Ks_CNL_Search_Tool);
   overriding procedure Reset_Results (Tool : in out Ks_CNL_Search_Tool);

private

   --  The kernel's pattern handle (null: an untrained pattern with the
   --  default training parameters). Assignment duplicates it,
   --  finalization destroys it.

   type Pattern_Handle is new Ada.Finalization.Controlled with record
      Handle : KC.Ks_CNL_Search_Pattern;
   end record;

   overriding procedure Adjust (Item : in out Pattern_Handle);
   overriding procedure Finalize (Item : in out Pattern_Handle);

   procedure Write_Handle
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : Pattern_Handle);
   procedure Read_Handle
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Pattern_Handle);
   --  Write nothing and read back the default (null) handle: the
   --  pattern's own attributes store the handle's data by value.

   for Pattern_Handle'Write use Write_Handle;
   for Pattern_Handle'Read use Read_Handle;

   type Ks_CNL_Search_Pattern is tagged record
      Train_Image   : AMV.Images.Ks_Image_8_Grey;
      Train_Region  : AMV.Shapes.Region_Holders.Holder;
      Mask          : AMV.Images.Ks_Image_8_Grey;
      Mask_Offset_X : Integer := 0;
      Mask_Offset_Y : Integer := 0;
      Kernel        : Pattern_Handle;
   end record;

   procedure Write_Pattern
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : Ks_CNL_Search_Pattern);
   procedure Read_Pattern
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_CNL_Search_Pattern);

   for Ks_CNL_Search_Pattern'Write use Write_Pattern;
   for Ks_CNL_Search_Pattern'Read use Read_Pattern;

   procedure Destroy (Handle : in out KC.Ks_CNL_Search_Results);
   --  Frees a results handle (for the holder).

   package Results_Holders is new AMV.Shared_Handles
     (KC.Ks_CNL_Search_Results, null, Destroy);

   type Ks_CNL_Search_Results is tagged record
      Holder : Results_Holders.Holder;
   end record;

end AMV.CNL_Search;
