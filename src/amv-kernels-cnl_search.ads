--  Kernel of AMV.CNL_Search: normalised correlation search, translation
--  only (CogCNLSearchTool, its pattern CogCNLSearchPattern, its run
--  parameters CogCNLSearchRunParams and its results CogCNLSearchResults).
--  Its entry points are the C API of the tool (include/amv_cnl_search.h,
--  names ks_cnl_search_*).
--
--  The pattern. A pattern lives behind an owned handle
--  (Ks_CNL_Search_Pattern; C: ks_cnl_search_pattern *, opaque) that
--  ks_cnl_search_pattern_create, ks_cnl_search_pattern_duplicate, or an
--  entry point given a null handle to change, returns; destroy frees it.
--  A null handle is an untrained pattern with the default training
--  parameters. A handle holds the training parameters (the origin in the
--  train image's selected space, the trained algorithms and accuracies,
--  IgnorePolarity) and, once trained, everything the search needs: the
--  pattern's pixels at every pyramid level (stacked one level under the
--  other in one 8-bit image), with a train image mask their care flags
--  (stacked the same way), the number, sum and spread of the cared-for
--  pixels of each level, and the origin in the pattern's own pixel
--  coordinates. Training copies these, so the train image and the mask may
--  change or go away afterwards. Changing a training parameter
--  (set_train_params) or a failed training untrains it.
--
--  Training (ks_cnl_search_pattern_train, and _train_masked with a train
--  image mask). The pattern is the pixel aligned bounding box of the train
--  region's pixels (a pixel region of the train image, AMV.Kernels.Regions;
--  VisionPro's TrainRegionMode PixelAlignedBoundingBox): at least
--  Min_Pattern_Side and at most Max_Pattern_Side pixels along each side.
--  Its origin is OriginX, OriginY mapped into pixel space with
--  Pixel_From_Selected, relative to the centre of the pattern's first
--  pixel; it must lie within Max_Origin pixels of it. A pattern whose
--  cared-for pixels all have one grey level cannot be trained. With
--  LinearCNLPAS among the trained algorithms the pattern is also halved
--  (each pixel the rounded mean of a 2 x 2 block, a trailing odd row or
--  column dropped) while both sides stay at least Min_Coarse_Side, up to
--  Max_Levels levels, and while the halved pattern keeps at least
--  Min_Cared_Pixels cared-for pixels that do not all have one grey level.
--
--  The score. At a window of the image as large as the pattern, the grey
--  levels p of the N cared-for pixels of the pattern (every pixel without
--  a mask) and w of the window's pixels at the same positions give the
--  zero-mean normalised cross-correlation (Pearson's r)
--
--     r = (N Sum (p w) - Sum p Sum w)
--         / Sqrt ((N Sum p**2 - (Sum p)**2) (N Sum w**2 - (Sum w)**2)).
--
--  The score is r**2 for r > 0 and 0 otherwise (a window of the opposite
--  contrast does not match); with IgnorePolarity and the LinearSearch
--  algorithm it is r**2 whatever the sign of r (VisionPro applies
--  IgnorePolarity to LinearSearch only). A flat window scores 0. Every
--  sum is computed exactly in 64-bit integers (without a mask the window
--  sums come from integral images), so the score is within rounding of
--  r**2; it lies in [0, 1]. The contrast of a result is the ratio of the
--  standard deviation of the window to that of the pattern, Sqrt ((N Sum
--  w**2 - (Sum w)**2) / (N Sum p**2 - (Sum p)**2)), within [0, 2**28].
--
--  The train image mask (ks_cnl_search_pattern_train_masked; AMV's own
--  meaning of VisionPro's TrainImageMask, TrainImageMaskOffsetX and
--  TrainImageMaskOffsetY). Mask pixel (U, V) covers train image pixel
--  (U + OffsetX, V + OffsetY), in pixel space; a mask pixel of value 0
--  marks that train pixel "don't care", any other value, and every train
--  pixel the mask does not cover, "care". The trained pattern keeps a care
--  flag for each of its pixels at every level: at full resolution the
--  flag of the train pixel, at a halved level the conjunction of the flags
--  of the 2 x 2 block the pixel averages, so that a level pixel is cared
--  for exactly when every train pixel it averages is. The score and the
--  contrast take their sums over the cared-for pixels only (above), so
--  whatever lies in a window under the don't-care pixels changes nothing.
--  Training fails with Bad_Parameter when fewer than Min_Cared_Pixels
--  pixels of the pattern are cared for at full resolution (the pixels of
--  the smallest pattern, Min_Pattern_Side**2). A mask that leaves every
--  pixel cared for gives exactly the scores of no mask; but the masked
--  window sums are computed window by window (about three times the work
--  of the cross sum), where the unmasked ones come from integral images.
--
--  The train region mode (VisionPro's TrainRegionMode). With
--  PixelAlignedBoundingBox every pixel of the box is part of the pattern.
--  With PixelAlignedBoundingBoxAdjustMask (the default) the pixels of the
--  box that the train region does not contain are don't-care pixels of
--  the pattern, as if a train image mask marked them so (and together
--  with the train image mask, when there is one); VisionPro does this for
--  LinearSearch only and treats the region as its box for the CNLPAS
--  algorithms, so a pattern trained for LinearCNLPAS alone is the whole
--  box, and one trained for both is masked (AMV's CNLPAS search then uses
--  the same care flags). A region that fills its box (a rectangle along
--  the axes) gives the same pattern in both modes. With AffineTransform
--  the train region is an affine rectangle resampled into an upright
--  pattern: ks_cnl_search_pattern_train_affine
--  (AMV.Kernels.CNL_Search.Region_Modes); ks_cnl_search_pattern_train
--  and _train_masked, which take a pixel region, reject a pattern in that
--  mode (Bad_Parameter).
--
--  The search (ks_cnl_search_execute). The search area is the bounding
--  box of the search region's pixels (VisionPro's SearchRegionMode
--  PixelAlignedBoundingBox; with SearchRegionMode AffineTransform too,
--  since VisionPro searches the bounding box of every region in that mode
--  but an affine rectangle, which ks_cnl_search_execute_affine of
--  AMV.Kernels.CNL_Search.Region_Modes resamples), which lies in the
--  image. The positions scored
--  are those where the window lies within the search area and, with the
--  partial match limits (below), those where it crosses a side of the area
--  by at most the limit of that side. A null region (the empty region) or
--  a box smaller than the pattern along either axis gives no results (a
--  successful run), whatever the limits. Positions are the pixel
--  coordinates of the window's first pixel (negative for a window that
--  crosses the left or top side of an area at the image's border).
--
--  Partial matches (AMV's meaning of VisionPro's PartialMatchLimitLeft,
--  PartialMatchLimitRight, PartialMatchLimitUp, PartialMatchLimitDown and
--  PartialMatchReduceScore). Each limit is the number of the pattern's
--  columns (Left, Right) or rows (Up, Down) that may lie outside the
--  search area on that side: 0 .. half the trained pattern's width (Left,
--  Right) or height (Up, Down), rounded down, so that at least half of the
--  pattern's columns and half of its rows always lie inside. The defaults,
--  0, score the windows inside the search area only. As the area is at
--  least as large as the pattern, a window crosses at most one side along
--  each axis. A window that crosses a side (a partial window) is scored as
--  above over its clipped part only: the N_in cared-for pixels of the
--  pattern (of its N) whose window pixel lies inside the search area, and
--  the window's pixels at their positions; its contrast likewise. It
--  scores 0 when N_in is less than N / 4 (possible only with a mask:
--  without one the limits keep at least a quarter of the pattern inside)
--  or when the pattern's cared-for pixels inside all have one grey level.
--  With PartialMatchReduceScore (0 or 1) its score is multiplied by
--  N_in / N, the fraction of the pattern's cared-for pixels inside. The
--  image pixels outside the search area never count, even where the image
--  has pixels there (a region smaller than the image). Partial matches
--  need the LinearSearch algorithm: non-zero limits with LinearCNLPAS are
--  rejected (Bad_Parameter). The pattern's own limits
--  (CogCNLSearchPattern.PartialMatchLimit*, PartialMatchLimitsUsePattern)
--  are not provided.
--
--  * LinearSearch: every position is scored. Every local maximum (at
--    least every later neighbour and above every earlier one, in raster
--    order, among the 8 neighbours) whose score is at least
--    AcceptThreshold is a candidate; the best Max_Candidates are kept.
--  * LinearCNLPAS: the image's search box is halved as the pattern was,
--    once per trained level, and every position of the coarsest level is
--    scored; the local maxima scoring at least Coarse_Factor *
--    AcceptThreshold there are the candidates (the best Candidate_Limit
--    (MaxResults) of them). Each candidate is followed down the levels:
--    on the next finer level the best of the 5 x 5 positions around twice
--    its position, and on the finest level from there uphill to a local
--    maximum (at most Max_Climb_Steps steps to a better neighbour).
--    Candidates are followed in the order of their coarse scores; once
--    MaxResults followed candidates that do not overlap (see XYOverlap)
--    score at least ConfusionThreshold, the rest are not followed.
--  * NonLinearCNLPAS is not supported (Bad_Parameter).
--
--  Every candidate that scores at least AcceptThreshold at full
--  resolution gets a sub-pixel position from its score and those of its
--  8 neighbours: with VeryFine the peak of the quadratic surface fitted
--  to the 3 x 3 scores by least squares (when that surface has a maximum
--  within one pixel along both axes; otherwise as with Fine), with Fine
--  the peak of a parabola through the three scores along each axis
--  separately (within half a pixel; this ignores the coupling of the
--  axes and is less accurate), with Coarse none (whole pixels). A
--  neighbour that is not a position (outside the search area extended by
--  the limits) leaves its axis at the whole pixel, so a position never
--  leaves that extended area. The sub-pixel fit uses the scores as they
--  are, reduced by PartialMatchReduceScore near the sides. The candidates
--  are then ranked by score, highest first, and taken in that order
--  unless the windows of one already taken and of this one share more
--  than XYOverlap of the pattern's area (or lie at the same whole-pixel
--  position), until MaxResults are taken. These are the results, with
--  ID = their index, Accepted = 1, ContrastComputed = 1 and EdgeHit the
--  sides of the search area that the reported window (at its sub-pixel
--  position) crosses: the sum (the bitwise or) of Edge_Hit_Left when the
--  window's first column lies left of the area's (its position is less
--  than the first position inside the area), Edge_Hit_Right when its last
--  column lies right of the area's (its position is more than the last
--  position inside), and Edge_Hit_Top and Edge_Hit_Bottom likewise for
--  the rows; Edge_Hit_None for a window inside the area, so for every
--  result when the limits are 0 (Edge_Hit_Unknown is never reported). The
--  reference is the search area, not the image: with a search region
--  smaller than the image, a window that crosses the area's side is
--  partial although the image has pixels there. LocationX, LocationY is
--  the pattern's origin at the result, mapped with Selected_From_Pixel
--  (the input image's selected space in the Ada API); a location beyond
--  1.0E150 fails the run with Bad_Parameter.
--
--  Bounds and limits: the origin and every transform entry finite and
--  within 1.0E150 (AMV.Kernels.Transforms), the thresholds and XYOverlap
--  in [0, 1] (ConfusionThreshold at least AcceptThreshold), MaxResults in
--  1 .. Max_Results_Limit, the partial match limits in 0 .. half the
--  trained pattern's side (0 with LinearCNLPAS), PartialMatchReduceScore 0
--  or 1, the search box at most Max_Search_Pixels pixels; Bad_Parameter
--  otherwise, naming the property.
--
--  Proved (docs/PROOF.md): absence of run-time errors for any argument,
--  handles that are null or came from this kernel included (an
--  inconsistent pattern, mask or results handle is rejected with
--  Bad_Parameter; a trained pattern's care flags, when it has them, are
--  an image of the size of its stacked pixels, Valid_Care); no memory
--  leaks (the care flags included); and of every results handle Execute
--  returns (Gold): every score in [0, 1] and at least AcceptThreshold, at
--  most MaxResults results, sorted by score (highest first), ID = index,
--  every window inside the search area extended by the partial match
--  limits (the limits of the run, each at most half the pattern's side),
--  the search area in the image and in the region's bounding box, EdgeHit
--  exactly the sides of the search area the window crosses (None for
--  every result when the limits are 0), and every location within
--  1.0E150; an untrained pattern never yields results
--  (Operator_Not_Trained). Not proved (tested): the accuracy of the
--  correlation (over the clipped part of a partial window too), of the
--  sub-pixel positions and of the contrast, and that the pyramid finds
--  what the exhaustive search finds.
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

with Interfaces;

with AMV.Kernels.Images;
with AMV.Kernels.Regions;
with AMV.Kernels.Transforms;

package AMV.Kernels.CNL_Search with SPARK_Mode, Preelaborate is

   package KI renames AMV.Kernels.Images;
   package KR renames AMV.Kernels.Regions;
   package KT renames AMV.Kernels.Transforms;

   use type KI.Ks_Image_8_Grey;
   use type Interfaces.Unsigned_32;

   Max_Value : constant := 1.0E150;
   --  The bound of every coordinate and transform entry (the bound of
   --  AMV.Kernels.Shapes and AMV.Kernels.Transforms).

   ---------------------------------------------------------------------
   --  Codes (C: KS_CNL_SEARCH_*)
   ---------------------------------------------------------------------

   --  CogCNLSearchAlgorithmConstants (VisionPro's values; flags, so that
   --  a pattern's Algorithms can name several).
   Algorithm_Linear_Search     : constant Int32 := 1;
   Algorithm_Linear_CNLPAS     : constant Int32 := 2;
   Algorithm_Non_Linear_CNLPAS : constant Int32 := 4;

   --  CogCNLSearchAccuracyConstants (VisionPro's values; flags, as above).
   Accuracy_Very_Fine : constant Int32 := 1;
   Accuracy_Fine      : constant Int32 := 2;
   Accuracy_Coarse    : constant Int32 := 4;

   --  CogCNLSearchEdgeHitConstants (VisionPro's values; flags). A result's
   --  EdgeHit is the sum of the flags of the sides of the search area its
   --  window crosses (partial matches), Edge_Hit_None when it crosses none;
   --  Edge_Hit_Unknown is never reported.
   Edge_Hit_None    : constant Int32 := 0;
   Edge_Hit_Unknown : constant Int32 := 1;
   Edge_Hit_Left    : constant Int32 := 2;
   Edge_Hit_Top     : constant Int32 := 4;
   Edge_Hit_Right   : constant Int32 := 8;
   Edge_Hit_Bottom  : constant Int32 := 16;

   --  CogRegionModeConstants (VisionPro's values), for SearchRegionMode.
   Region_Mode_Pixel_Aligned_Bounding_Box_Adjust_Mask : constant Int32 := 0;
   Region_Mode_Pixel_Aligned_Bounding_Box             : constant Int32 := 1;
   Region_Mode_Affine_Transform                       : constant Int32 := 2;

   ---------------------------------------------------------------------
   --  Limits (C: KS_CNL_SEARCH_*)
   ---------------------------------------------------------------------

   Min_Pattern_Side  : constant := 8;
   --  The fewest pixels along each side of a pattern (as VisionPro).
   Max_Pattern_Side  : constant := 1024;
   --  The most pixels along each side of a pattern, so a pattern has at
   --  most 2**20 pixels.
   Max_Search_Pixels : constant := 2**24;
   --  The most pixels of a search box.
   Max_Levels        : constant := 6;
   --  The most pyramid levels, the full resolution included.
   Min_Coarse_Side   : constant := 8;
   --  The fewest pixels along each side of the pattern at a coarser level.
   Max_Results_Limit : constant := 1000;
   --  The largest MaxResults.
   Max_Candidates    : constant := 4096;
   --  The most candidates a search keeps.
   Max_Climb_Steps   : constant := 16;
   --  The most steps uphill on the finest level of the pyramid search.
   Max_Origin        : constant := 1.0E140;
   --  The largest distance in pixels, along each axis, of the trained
   --  origin from the pattern's first pixel.
   Min_Cared_Pixels  : constant := Min_Pattern_Side * Min_Pattern_Side;
   --  The fewest cared-for pixels of a pattern at every level it keeps
   --  (64, the pixels of the smallest pattern; see the train image mask).

   Coarse_Factor : constant := 0.5;
   --  The candidates of the pyramid search score at least Coarse_Factor *
   --  AcceptThreshold at the coarsest level.

   function Candidate_Limit (Max_Results : Int32) return Natural is
     (if Max_Results in 1 .. Max_Results_Limit
      then Natural'Min (Max_Candidates, 8 * Natural (Max_Results) + 32)
      else Max_Candidates);
   --  The number of candidates the pyramid search follows at most.

   ---------------------------------------------------------------------
   --  Training parameters (C: ks_cnl_search_train_params)
   ---------------------------------------------------------------------

   type Ks_CNL_Search_Train_Params is record
      Algorithms        : Int32 := Algorithm_Linear_Search;
      Accuracies        : Int32 := Accuracy_Very_Fine;
      Ignore_Polarity   : Int32 := False_Value;
      Origin_X          : Long_Float := 70.0;
      Origin_Y          : Long_Float := 70.0;
      Train_Region_Mode : Int32 :=
        Region_Mode_Pixel_Aligned_Bounding_Box_Adjust_Mask;
   end record
     with Convention => C;
   --  The scalar properties of CogCNLSearchPattern, with VisionPro's
   --  defaults: Algorithms (flags, LinearSearch and LinearCNLPAS only,
   --  1 .. 3), Accuracies (flags, 1 .. 7), IgnorePolarity (0 or 1),
   --  OriginX, OriginY (the origin in the train image's selected space,
   --  finite and within Max_Value), and TrainRegionMode
   --  (PixelAlignedBoundingBoxAdjustMask, PixelAlignedBoundingBox or
   --  AffineTransform; see "The train region mode" above).

   function Valid_Train_Params
     (Params : Ks_CNL_Search_Train_Params) return Boolean
   is
     (Params.Algorithms in 1 .. 3
      and then Params.Accuracies in 1 .. 7
      and then Params.Ignore_Polarity in False_Value | True_Value
      and then Params.Origin_X >= -Max_Value
      and then Params.Origin_X <= Max_Value
      and then Params.Origin_Y >= -Max_Value
      and then Params.Origin_Y <= Max_Value
      and then Params.Train_Region_Mode
                 in Region_Mode_Pixel_Aligned_Bounding_Box_Adjust_Mask
                  | Region_Mode_Pixel_Aligned_Bounding_Box
                  | Region_Mode_Affine_Transform);

   function Masks_Region (Params : Ks_CNL_Search_Train_Params) return Boolean
   is
     (Params.Train_Region_Mode
        = Region_Mode_Pixel_Aligned_Bounding_Box_Adjust_Mask
      and then Params.Algorithms in 1 .. 7
      and then Params.Algorithms mod 2 = 1);
   --  Training leaves the pixels of the box outside the train region out
   --  of the pattern (the region mode is Adjust_Mask and the pattern is
   --  trained for LinearSearch).

   ---------------------------------------------------------------------
   --  Patterns (C: ks_cnl_search_pattern *, opaque)
   ---------------------------------------------------------------------

   type Level_Geometry is record
      Row    : Natural := 0;
      Width  : Natural := 0;
      Height : Natural := 0;
   end record;
   --  One pyramid level stacked in an image: Height rows of Width pixels
   --  starting at row Row, column 0.

   type Level_Info is record
      Geometry : Level_Geometry;
      Count    : Int64 := 0;
      Sum      : Int64 := 0;
      Spread   : Int64 := 0;
   end record;
   --  A level of a trained pattern: its place in the stacked pixels, the
   --  number N of its cared-for pixels (all of them without a mask), the
   --  sum of their grey levels and their spread N Sum p**2 - (Sum p)**2.

   Max_Grey_Sum : constant := 255 * 2**20;
   Max_Spread   : constant := 2**56;
   --  Bounds of Sum and Spread for a pattern of at most 2**20 pixels.

   type Level_Table is array (0 .. Max_Levels - 1) of Level_Info;

   type Ks_CNL_Search_Pattern_Data is limited record
      Params   : Ks_CNL_Search_Train_Params;
      Trained  : Boolean := False;
      Levels   : Natural := 0;
      Info     : Level_Table;
      Origin_X : Long_Float := 0.0;
      Origin_Y : Long_Float := 0.0;
      Pixels   : KI.Ks_Image_8_Grey;
      Care     : KI.Ks_Image_8_Grey;
   end record;
   --  What a handle designates (opaque for C): the training parameters,
   --  and once trained the number of levels, each level's place and
   --  statistics, the origin relative to the centre of the pattern's first
   --  pixel (pixels), the stacked pixels of every level, and when it was
   --  trained with a mask the care flags of those pixels (an image of the
   --  same size, 1 for a cared-for pixel and 0 for a don't-care one; null
   --  without a mask: every pixel is cared for). Valid_Pattern states the
   --  invariant.

   type Ks_CNL_Search_Pattern is access Ks_CNL_Search_Pattern_Data
     with Convention => C;
   --  C: ks_cnl_search_pattern *.

   function Valid_Level
     (Info          : Level_Info;
      Width, Height : Int32) return Boolean
   is
     (Info.Geometry.Width in 1 .. Max_Pattern_Side
      and then Info.Geometry.Height in 1 .. Max_Pattern_Side
      and then Width >= 1 and then Height >= 1
      and then Info.Geometry.Width <= Natural (Width)
      and then Info.Geometry.Row <= Natural (Height)
      and then Info.Geometry.Height <= Natural (Height) - Info.Geometry.Row
      and then Info.Count in Min_Cared_Pixels .. Max_Pattern_Side**2
      and then Info.Sum in 0 .. Max_Grey_Sum
      and then Info.Spread in 1 .. Max_Spread);
   --  A level that lies in a Width x Height stack, with its statistics in
   --  their ranges.

   function Valid_Care
     (Care, Pixels : access constant KI.Ks_Image_8_Grey_Data) return Boolean
   is
     (Care = null
      or else (KI.Valid_Image (Care) and then KI.Valid_Image (Pixels)
               and then Care.Width = Pixels.Width
               and then Care.Height = Pixels.Height));
   --  No care flags (every pixel cared for), or an image of the size of
   --  the stacked pixels.

   function Is_Trained
     (Pattern : access constant Ks_CNL_Search_Pattern_Data) return Boolean
   is
     (Pattern /= null and then Pattern.Trained);

   function Valid_Data (Pattern : Ks_CNL_Search_Pattern_Data) return Boolean
   is
     (Valid_Train_Params (Pattern.Params)
      and then
        (if Pattern.Trained
         then Pattern.Levels in 1 .. Max_Levels
              and then KI.Valid_Image (Pattern.Pixels)
              and then Pattern.Pixels.Width <= Max_Pattern_Side
              and then Pattern.Pixels.Height <= 2 * Max_Pattern_Side
              and then Pattern.Origin_X >= -Max_Origin
              and then Pattern.Origin_X <= Max_Origin
              and then Pattern.Origin_Y >= -Max_Origin
              and then Pattern.Origin_Y <= Max_Origin
              and then (for all L in 0 .. Pattern.Levels - 1 =>
                          Valid_Level (Pattern.Info (L),
                                       Pattern.Pixels.Width,
                                       Pattern.Pixels.Height))
              and then Valid_Care (Pattern.Care, Pattern.Pixels)
         else Pattern.Pixels = null and then Pattern.Care = null));

   function Valid_Pattern
     (Pattern : access constant Ks_CNL_Search_Pattern_Data) return Boolean
   is
     (Pattern /= null and then Valid_Data (Pattern.all));
   --  A handle as the entry points make it.

   ---------------------------------------------------------------------
   --  Run parameters (C: ks_cnl_search_run_params)
   ---------------------------------------------------------------------

   type Ks_CNL_Search_Run_Params is record
      Algorithm                  : Int32 := Algorithm_Linear_Search;
      Accuracy                   : Int32 := Accuracy_Very_Fine;
      Max_Results                : Int32 := 1;
      Search_Region_Mode         : Int32 :=
        Region_Mode_Pixel_Aligned_Bounding_Box;
      Accept_Threshold           : Long_Float := 0.3;
      Confusion_Threshold        : Long_Float := 0.5;
      XY_Overlap                 : Long_Float := 1.0;
      Partial_Match_Limit_Left   : Int32 := 0;
      Partial_Match_Limit_Right  : Int32 := 0;
      Partial_Match_Limit_Up     : Int32 := 0;
      Partial_Match_Limit_Down   : Int32 := 0;
      Partial_Match_Reduce_Score : Int32 := False_Value;
   end record
     with Convention => C;
   --  CogCNLSearchRunParams, with VisionPro's defaults where it states
   --  them (AcceptThreshold 0.3, ConfusionThreshold 0.5, XYOverlap 1.0)
   --  and ours otherwise (Algorithm LinearSearch, Accuracy VeryFine,
   --  MaxResults 1, SearchRegionMode PixelAlignedBoundingBox, the partial
   --  match limits 0 and PartialMatchReduceScore 0). Algorithm and
   --  Accuracy must be among the pattern's trained Algorithms and
   --  Accuracies; MaxResults in 1 .. Max_Results_Limit; the thresholds and
   --  XYOverlap in [0, 1] with ConfusionThreshold >= AcceptThreshold;
   --  SearchRegionMode PixelAlignedBoundingBox or AffineTransform (see
   --  "The search" above: ks_cnl_search_execute searches the bounding box
   --  of its pixel region in both, ks_cnl_search_execute_affine needs
   --  AffineTransform); PartialMatchLimitLeft and PartialMatchLimitRight in
   --  0 .. TrainedPatternWidth / 2, PartialMatchLimitUp and
   --  PartialMatchLimitDown in 0 .. TrainedPatternHeight / 2 (all 0 with
   --  LinearCNLPAS), PartialMatchReduceScore 0 or 1 (see "Partial
   --  matches" above).

   function Partial_OK
     (Params        : Ks_CNL_Search_Run_Params;
      Width, Height : Natural) return Boolean
   is
     (Width <= Max_Pattern_Side and then Height <= Max_Pattern_Side
      and then Params.Partial_Match_Limit_Left in 0 .. Int32 (Width / 2)
      and then Params.Partial_Match_Limit_Right in 0 .. Int32 (Width / 2)
      and then Params.Partial_Match_Limit_Up in 0 .. Int32 (Height / 2)
      and then Params.Partial_Match_Limit_Down in 0 .. Int32 (Height / 2)
      and then Params.Partial_Match_Reduce_Score
                 in False_Value | True_Value
      and then (if Params.Algorithm /= Algorithm_Linear_Search
                then Params.Partial_Match_Limit_Left = 0
                     and then Params.Partial_Match_Limit_Right = 0
                     and then Params.Partial_Match_Limit_Up = 0
                     and then Params.Partial_Match_Limit_Down = 0));
   --  The partial match parameters are valid for a trained pattern of
   --  Width x Height pixels.

   ---------------------------------------------------------------------
   --  Results (C: ks_cnl_search_results *, opaque)
   ---------------------------------------------------------------------

   type Ks_CNL_Search_Result is record
      ID                : Int32 := 0;
      Accepted          : Int32 := True_Value;
      Contrast_Computed : Int32 := True_Value;
      Edge_Hit          : Int32 := Edge_Hit_None;
      Score             : Long_Float := 0.0;
      Location_X        : Long_Float := 0.0;
      Location_Y        : Long_Float := 0.0;
      Contrast          : Long_Float := 0.0;
   end record
     with Convention => C;
   --  C: ks_cnl_search_result (CogCNLSearchResult).

   type Found is record
      Item     : Ks_CNL_Search_Result;
      Window_X : Long_Float := 0.0;
      Window_Y : Long_Float := 0.0;
   end record;
   --  A result as a handle keeps it: the item, and the pixel coordinates
   --  of the window's first pixel (sub-pixel) before mapping.

   type Found_Array is array (Natural range <>) of Found;
   type Found_Array_Access is access Found_Array;

   type Ks_CNL_Search_Results_Data is limited record
      Count          : Natural := 0;
      Items          : Found_Array_Access;
      Area_X_First   : Int32 := 0;
      Area_X_Last    : Int32 := -1;
      Area_Y_First   : Int32 := 0;
      Area_Y_Last    : Int32 := -1;
      Pattern_Width  : Int32 := 0;
      Pattern_Height : Int32 := 0;
      Margin_Left    : Natural := 0;
      Margin_Right   : Natural := 0;
      Margin_Up      : Natural := 0;
      Margin_Down    : Natural := 0;
   end record;
   --  What a handle designates (opaque for C): Count results in Items
   --  (0 .. Count - 1; null when there are none), the window positions
   --  that were scored (Area_X_First .. Area_X_Last by Area_Y_First ..
   --  Area_Y_Last, in pixels: the search area extended by the partial
   --  match limits), the pattern's size, and the limits of the run (the
   --  margins): the positions inside the search area are Area_X_First +
   --  Margin_Left .. Area_X_Last - Margin_Right by Area_Y_First +
   --  Margin_Up .. Area_Y_Last - Margin_Down.

   type Ks_CNL_Search_Results is access Ks_CNL_Search_Results_Data
     with Convention => C;
   --  C: ks_cnl_search_results *.

   function Valid_Results
     (Results : access constant Ks_CNL_Search_Results_Data) return Boolean
   is
     (Results /= null
      and then Results.Count <= Max_Results_Limit
      and then (if Results.Count = 0 then Results.Items = null
                else Results.Items /= null
                     and then Results.Items'First = 0
                     and then Results.Items'Last = Results.Count - 1));
   --  A handle as Execute makes it.

   function Item_OK (Item : Ks_CNL_Search_Result) return Boolean is
     (Item.Score >= 0.0 and then Item.Score <= 1.0
      and then KT.Bounded (Item.Location_X)
      and then KT.Bounded (Item.Location_Y)
      and then Item.Contrast >= 0.0 and then Item.Contrast <= 2.0**28
      and then Item.Accepted = True_Value
      and then Item.Contrast_Computed = True_Value);
   --  A result's values in their ranges.

   function Edge_Hit_Within
     (Window_X, Window_Y : Long_Float;
      X_First, X_Last    : Int64;
      Y_First, Y_Last    : Int64) return Int32
   is
     ((if Window_X < Long_Float (X_First) then Edge_Hit_Left
       else Edge_Hit_None)
      + (if Window_Y < Long_Float (Y_First) then Edge_Hit_Top
         else Edge_Hit_None)
      + (if Window_X > Long_Float (X_Last) then Edge_Hit_Right
         else Edge_Hit_None)
      + (if Window_Y > Long_Float (Y_Last) then Edge_Hit_Bottom
         else Edge_Hit_None));
   --  The EdgeHit of a window at (Window_X, Window_Y) when the positions
   --  inside the search area are X_First .. X_Last by Y_First .. Y_Last:
   --  the flags of the sides it crosses.

   function Edge_Hit_Of
     (Item    : Found;
      Results : access constant Ks_CNL_Search_Results_Data) return Int32
   is
     (if Results = null then Edge_Hit_None
      else Edge_Hit_Within
             (Item.Window_X, Item.Window_Y,
              Int64 (Results.Area_X_First) + Int64 (Results.Margin_Left),
              Int64 (Results.Area_X_Last) - Int64 (Results.Margin_Right),
              Int64 (Results.Area_Y_First) + Int64 (Results.Margin_Up),
              Int64 (Results.Area_Y_Last) - Int64 (Results.Margin_Down)));
   --  The EdgeHit of Item's window in the search area of Results.

   function Placed_Facts
     (Item                             : Found;
      X_First, X_Last, Y_First, Y_Last : Int32;
      Left, Right, Up, Down            : Natural) return Boolean
   is
     (Item.Window_X >= Long_Float (X_First)
      and then Item.Window_X <= Long_Float (X_Last)
      and then Item.Window_Y >= Long_Float (Y_First)
      and then Item.Window_Y <= Long_Float (Y_Last)
      and then Item.Item.Edge_Hit
                 = Edge_Hit_Within
                     (Item.Window_X, Item.Window_Y,
                      Int64 (X_First) + Int64 (Left),
                      Int64 (X_Last) - Int64 (Right),
                      Int64 (Y_First) + Int64 (Up),
                      Int64 (Y_Last) - Int64 (Down)));
   --  The window of Item lies at the positions X_First .. X_Last by
   --  Y_First .. Y_Last that were scored (the search area extended by the
   --  partial match limits Left, Right, Up and Down), and its EdgeHit is
   --  the sides of the search area (the positions without the limits) that
   --  it crosses.

   function Placed
     (Item                             : Found;
      X_First, X_Last, Y_First, Y_Last : Int32;
      Left, Right, Up, Down            : Natural) return Boolean
   with Post => Placed'Result
                  = Placed_Facts (Item, X_First, X_Last, Y_First, Y_Last,
                                  Left, Right, Up, Down);
   --  Placed_Facts as an ordinary function, so that a quantified fact of
   --  the results is matched by Placed (..) instead of being taken apart
   --  (docs/PROOF.md, proof notes).

   function Gold_Results
     (Results : access constant Ks_CNL_Search_Results_Data) return Boolean
   is
     (Valid_Results (Results)
      and then (for all I in 0 .. Results.Count - 1 =>
                  Item_OK (Results.Items (I).Item)
                  and then Results.Items (I).Item.ID = Int32 (I)
                  and then Placed (Results.Items (I),
                                   Results.Area_X_First, Results.Area_X_Last,
                                   Results.Area_Y_First, Results.Area_Y_Last,
                                   Results.Margin_Left, Results.Margin_Right,
                                   Results.Margin_Up, Results.Margin_Down))
      and then (for all I in 0 .. Results.Count - 2 =>
                  Results.Items (I).Item.Score
                    >= Results.Items (I + 1).Item.Score));
   --  The proved facts of every handle Execute returns: scores in [0, 1],
   --  locations within the bound, IDs the indices, windows at the scored
   --  positions, EdgeHit the sides of the search area each window
   --  crosses, sorted by score (highest first).

   function Margins_OK
     (Results : access constant Ks_CNL_Search_Results_Data) return Boolean
   is
     (Results /= null
      and then 2 * Int64 (Results.Margin_Left) <= Int64 (Results.Pattern_Width)
      and then 2 * Int64 (Results.Margin_Right)
                 <= Int64 (Results.Pattern_Width)
      and then 2 * Int64 (Results.Margin_Up) <= Int64 (Results.Pattern_Height)
      and then 2 * Int64 (Results.Margin_Down)
                 <= Int64 (Results.Pattern_Height));
   --  Each partial match limit is at most half the pattern's side.

   function Area_In_Image
     (Results       : access constant Ks_CNL_Search_Results_Data;
      Width, Height : Int32) return Boolean
   is
     (Results /= null
      and then Int64 (Results.Area_X_First) + Int64 (Results.Margin_Left)
                 >= 0
      and then Int64 (Results.Area_Y_First) + Int64 (Results.Margin_Up)
                 >= 0
      and then Results.Pattern_Width >= 1
      and then Results.Pattern_Height >= 1
      and then Int64 (Results.Area_X_Last) - Int64 (Results.Margin_Right)
                 + Int64 (Results.Pattern_Width) <= Int64 (Width)
      and then Int64 (Results.Area_Y_Last) - Int64 (Results.Margin_Down)
                 + Int64 (Results.Pattern_Height) <= Int64 (Height));
   --  Every window inside the search area lies in a Width x Height image
   --  (the search area lies in the image).

   function Area_In_Region
     (Results : access constant Ks_CNL_Search_Results_Data;
      Region  : access constant KR.Ks_Pixel_Region_Data) return Boolean
   is
     (Results /= null and then Region /= null
      and then Int64 (Results.Area_X_First) + Int64 (Results.Margin_Left)
                 >= Int64 (Region.X_Min)
      and then Int64 (Results.Area_Y_First) + Int64 (Results.Margin_Up)
                 >= Int64 (Region.Y_Min)
      and then Int64 (Results.Area_X_Last) - Int64 (Results.Margin_Right)
                 + Int64 (Results.Pattern_Width)
                 <= Int64 (Region.X_Min) + Int64 (Region.Width)
      and then Int64 (Results.Area_Y_Last) - Int64 (Results.Margin_Down)
                 + Int64 (Results.Pattern_Height)
                 <= Int64 (Region.Y_Min) + Int64 (Region.Height));
   --  Every window inside the search area lies in the region's bounding
   --  box (the search area is that box).

   ---------------------------------------------------------------------
   --  Entry points: patterns
   ---------------------------------------------------------------------

   procedure Train_Params_Default
     (Params : out Ks_CNL_Search_Train_Params;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_cnl_search_train_params_default",
     Post => Valid (Status) and then Succeeded (Status)
             and then Valid_Train_Params (Params);
   --  The default training parameters (the record's default values).

   procedure Pattern_Create
     (Pattern : out Ks_CNL_Search_Pattern;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_cnl_search_pattern_create",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Valid_Pattern (Pattern)
                            and then not Is_Trained (Pattern)
                       else Pattern = null);
   --  A new untrained pattern with the default training parameters.

   procedure Pattern_Destroy
     (Pattern : in out Ks_CNL_Search_Pattern;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_cnl_search_pattern_destroy",
     Post => Valid (Status) and then Succeeded (Status)
             and then Pattern = null;
   --  Frees the pattern and sets the handle to null; nothing for null.

   procedure Pattern_Duplicate
     (Pattern : access constant Ks_CNL_Search_Pattern_Data;
      Copy    : out Ks_CNL_Search_Pattern;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_cnl_search_pattern_duplicate",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then (if Pattern = null then Copy = null
                             else Valid_Pattern (Copy)
                                  and then Is_Trained (Copy)
                                             = Is_Trained (Pattern))
                       else Copy = null);
   --  A new pattern with the same parameters and trained data, sharing
   --  nothing with Pattern (null for null). Bad_Parameter for an
   --  inconsistent handle.

   procedure Pattern_Get_Train_Params
     (Pattern : access constant Ks_CNL_Search_Pattern_Data;
      Params  : out Ks_CNL_Search_Train_Params;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_cnl_search_pattern_get_train_params",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Valid_Train_Params (Params);
   --  The training parameters (the defaults for null, and on failure).

   procedure Pattern_Set_Train_Params
     (Pattern : in out Ks_CNL_Search_Pattern;
      Params  : Ks_CNL_Search_Train_Params;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_cnl_search_pattern_set_train_params",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Valid_Pattern (Pattern)
                            and then not Is_Trained (Pattern)
                            and then Pattern.Params = Params);
   --  Stores the training parameters and untrains the pattern (creating
   --  it when the handle is null). Bad_Parameter, leaving the pattern as
   --  it was, for parameters outside their ranges ("Pattern.Algorithms
   --  must be LinearSearch, LinearCNLPAS or both", "Pattern.OriginX must
   --  be finite and within 1.0E150", ...) or an inconsistent handle.

   procedure Pattern_Train
     (Pattern             : in out Ks_CNL_Search_Pattern;
      Image               : access constant KI.Ks_Image_8_Grey_Data;
      Region              : access constant KR.Ks_Pixel_Region_Data;
      Pixel_From_Selected : KT.Ks_Transform_2D_Linear;
      Status              : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_cnl_search_pattern_train",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Out_Of_Memory
             and then (if Pattern /= null then Valid_Pattern (Pattern))
             and then Is_Trained (Pattern) = Succeeded (Status);
   --  Train: trains the pattern on the pixels of Image that Region bounds
   --  (see above; Pixel_From_Selected maps the train image's selected
   --  space, where the origin is, to pixel space), creating it when the
   --  handle is null. Bad_Parameter first for a pattern whose
   --  TrainRegionMode is AffineTransform ("Pattern.TrainRegionMode
   --  AffineTransform needs an affine rectangle TrainRegion
   --  (ks_cnl_search_pattern_train_affine)"). Image_No_Pixels for a null
   --  image ("TrainImage has no
   --  pixels"); Bad_Parameter for an inconsistent image or pattern, a null
   --  region ("TrainRegion lies entirely outside TrainImage"), a region
   --  that does not lie in the image, a box smaller than Min_Pattern_Side
   --  or larger than Max_Pattern_Side, a transform beyond the bound, an
   --  origin beyond Max_Origin, and a flat pattern; Out_Of_Memory. The
   --  pattern is untrained on failure. The same as Pattern_Train_Masked
   --  without a mask.

   procedure Pattern_Train_Masked
     (Pattern             : in out Ks_CNL_Search_Pattern;
      Image               : access constant KI.Ks_Image_8_Grey_Data;
      Region              : access constant KR.Ks_Pixel_Region_Data;
      Pixel_From_Selected : KT.Ks_Transform_2D_Linear;
      Mask                : access constant KI.Ks_Image_8_Grey_Data;
      Mask_Offset_X       : Int32;
      Mask_Offset_Y       : Int32;
      Status              : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_cnl_search_pattern_train_masked",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Out_Of_Memory
             and then (if Pattern /= null then Valid_Pattern (Pattern))
             and then Is_Trained (Pattern) = Succeeded (Status);
   --  Train with TrainImageMask (Mask; null: none) at
   --  TrainImageMaskOffsetX and TrainImageMaskOffsetY: mask pixel (U, V)
   --  covers train image pixel (U + Mask_Offset_X, V + Mask_Offset_Y); a
   --  mask pixel of value 0 marks that pixel "don't care", any other value
   --  (and every pixel the mask does not cover) "care" (see "The train
   --  image mask" above). Failures as Pattern_Train, and Bad_Parameter for
   --  an inconsistent mask handle ("TrainImageMask is not a valid image
   --  handle", after the checks of the region and the transform) and for a
   --  mask that leaves fewer than Min_Cared_Pixels pixels of the pattern
   --  cared for.

   procedure Pattern_Trained
     (Pattern : access constant Ks_CNL_Search_Pattern_Data;
      Result  : out Int32;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_cnl_search_pattern_trained",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Result in False_Value | True_Value
             and then (if Succeeded (Status)
                       then (Result = True_Value) = Is_Trained (Pattern)
                       else Result = False_Value);
   --  Trained: 1 for a trained pattern, 0 otherwise (and for null).

   procedure Pattern_Untrain
     (Pattern : Ks_CNL_Search_Pattern;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_cnl_search_pattern_untrain",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then not Is_Trained (Pattern)
             and then (if Pattern /= null then Valid_Pattern (Pattern));
   --  Untrain: frees the trained data and keeps the training parameters;
   --  nothing for null. An inconsistent pattern is reset to the default
   --  untrained pattern (Bad_Parameter).

   procedure Pattern_Trained_Size
     (Pattern       : access constant Ks_CNL_Search_Pattern_Data;
      Width, Height : out Int32;
      Status        : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_cnl_search_pattern_trained_size",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Operator_Not_Trained
                         | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Width in Min_Pattern_Side .. Max_Pattern_Side
                            and then Height
                                       in Min_Pattern_Side .. Max_Pattern_Side
                       else Width = 0 and then Height = 0);
   --  TrainedPatternWidth and TrainedPatternHeight (pixels).
   --  Operator_Not_Trained for an untrained pattern (and null).

   procedure Pattern_Trained_Origin
     (Pattern : access constant Ks_CNL_Search_Pattern_Data;
      X, Y    : out Long_Float;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_cnl_search_pattern_trained_origin",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Operator_Not_Trained
                         | Failure_Bad_Parameter
             and then X >= -Max_Origin and then X <= Max_Origin
             and then Y >= -Max_Origin and then Y <= Max_Origin;
   --  The trained origin in the pattern's pixel coordinates (relative to
   --  the centre of its first pixel). Operator_Not_Trained for an
   --  untrained pattern; 0, 0 on failure.

   procedure Pattern_Get_Trained_Pattern_Image
     (Pattern : access constant Ks_CNL_Search_Pattern_Data;
      Image   : out KI.Ks_Image_8_Grey;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_cnl_search_pattern_get_trained_pattern_image",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Operator_Not_Trained
                         | Failure_Bad_Parameter | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then KI.Valid_Image (Image)
                            and then Image.Width
                                       in Min_Pattern_Side .. Max_Pattern_Side
                            and then Image.Height
                                       in Min_Pattern_Side .. Max_Pattern_Side
                       else Image = null);
   --  GetTrainedPatternImage: a new image holding the trained pattern's
   --  pixels at full resolution. Operator_Not_Trained for an untrained
   --  pattern.

   ---------------------------------------------------------------------
   --  Entry points: running
   ---------------------------------------------------------------------

   procedure Run_Params_Default
     (Params : out Ks_CNL_Search_Run_Params;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_cnl_search_run_params_default",
     Post => Valid (Status) and then Succeeded (Status);
   --  The default run parameters (the record's default values).

   procedure Execute
     (Image               : access constant KI.Ks_Image_8_Grey_Data;
      Region              : access constant KR.Ks_Pixel_Region_Data;
      Pattern             : access constant Ks_CNL_Search_Pattern_Data;
      Params              : Ks_CNL_Search_Run_Params;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Results             : out Ks_CNL_Search_Results;
      Status              : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_cnl_search_execute",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Operator_Not_Trained
                         | Failure_Bad_Parameter | Failure_Out_Of_Memory
             and then (if not Is_Trained (Pattern)
                       then not Succeeded (Status))
             and then
               (if Succeeded (Status)
                then Gold_Results (Results)
                     and then Results.Count <= Natural (Params.Max_Results)
                     and then (for all I in 0 .. Results.Count - 1 =>
                                 Results.Items (I).Item.Score
                                   >= Params.Accept_Threshold)
                     and then (if Results.Count > 0
                               then KI.Valid_Image (Image)
                                    and then Area_In_Image
                                               (Results, Image.Width,
                                                Image.Height)
                                    and then Area_In_Region
                                               (Results, Region)
                                    and then Margins_OK (Results)
                                    and then Int64 (Results.Margin_Left)
                                      = Int64
                                          (Params.Partial_Match_Limit_Left)
                                    and then Int64 (Results.Margin_Right)
                                      = Int64
                                          (Params.Partial_Match_Limit_Right)
                                    and then Int64 (Results.Margin_Up)
                                      = Int64
                                          (Params.Partial_Match_Limit_Up)
                                    and then Int64 (Results.Margin_Down)
                                      = Int64
                                          (Params.Partial_Match_Limit_Down))
                     and then
                       (if Params.Partial_Match_Limit_Left = 0
                          and then Params.Partial_Match_Limit_Right = 0
                          and then Params.Partial_Match_Limit_Up = 0
                          and then Params.Partial_Match_Limit_Down = 0
                        then (for all I in 0 .. Results.Count - 1 =>
                                Results.Items (I).Item.Edge_Hit
                                  = Edge_Hit_None))
                else Results = null);
   --  Searches Image within Region for Pattern (CogCNLSearchTool.Run, see
   --  above). Returns a new results handle (null on failure).
   --  Image_No_Pixels for a null image ("InputImage has no pixels");
   --  Operator_Not_Trained for a null or untrained pattern ("Pattern is
   --  not trained"); Bad_Parameter for an inconsistent image, pattern or
   --  region, a region that does not lie in the image, run parameters out
   --  of range ("RunParams.PartialMatchLimitLeft must be in 0 ..
   --  TrainedPatternWidth / 2", "RunParams.PartialMatchLimitLeft, Right, Up
   --  and Down must be 0 with LinearCNLPAS", ...), a transform beyond the
   --  bound, a search box larger than Max_Search_Pixels and a location
   --  beyond 1.0E150; Out_Of_Memory.

   procedure Results_Destroy (Results : in out Ks_CNL_Search_Results)
   with
     Export, Convention => C,
     External_Name => "ks_cnl_search_results_destroy",
     Post => Results = null;
   --  Frees the results and sets the handle to null; nothing for null.

   procedure Results_Count
     (Results : access constant Ks_CNL_Search_Results_Data;
      Count   : out Int32;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_cnl_search_results_count",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Count in 0 .. Max_Results_Limit
             and then (if Succeeded (Status) and then Results /= null
                       then Count = Int32 (Results.Count));
   --  Count: the number of results (0 for null).

   procedure Results_Item
     (Results : access constant Ks_CNL_Search_Results_Data;
      Index   : Int32;
      Item    : out Ks_CNL_Search_Result;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_cnl_search_results_item",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then (if Succeeded (Status)
                       then Valid_Results (Results)
                            and then Index in 0 .. Int32 (Results.Count) - 1
                            and then Item
                                       = Results.Items (Natural (Index)).Item);
   --  Item (Index), 0-based: Index_Out_Of_Range outside 0 .. Count - 1
   --  (always for null).

   ---------------------------------------------------------------------
   --  Ada-only helpers (no C entry points)
   ---------------------------------------------------------------------

   procedure Check_Input_Image
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter;
   --  The check of the input image that Execute makes first, so that the
   --  Ada API reports an unallocated image before it rasterises the
   --  search region.

   procedure Check_Train_Image
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter;
   --  The same for the train image ("TrainImage has no pixels").

   subtype U32 is Interfaces.Unsigned_32;

   Stream_Code : constant U32 := 16#4B53_434E#;
   --  "KSCN": the format code of a pattern in a stream before the train
   --  image mask (still read: no mask).

   Stream_Code_Masked : constant U32 := 16#4B53_434D#;
   --  "KSCM": the format code of a pattern since the train image mask: the
   --  training inputs are followed by the mask and its offsets, and a
   --  trained pattern's pixels by its trained care flags (still read: the
   --  train region mode PixelAlignedBoundingBox, which those patterns were
   --  trained with).

   Stream_Code_Region_Mode : constant U32 := 16#4B53_4352#;
   --  "KSCR": the format code 'Write uses since the train region mode: as
   --  "KSCM", with TrainRegionMode after OriginY (any of the three modes;
   --  a pattern trained with AffineTransform needs nothing more, since the
   --  stream keeps its resampled pixels, care flags and origin).

   procedure Check_Stream_Code
     (Code        : U32;
      Masked      : out Boolean;
      Region_Mode : out Boolean;
      Status      : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Image_File
             and then Succeeded (Status)
                        = (Code in Stream_Code | Stream_Code_Masked
                                 | Stream_Code_Region_Mode)
             and then Masked
                        = (Code in Stream_Code_Masked
                                 | Stream_Code_Region_Mode)
             and then Region_Mode = (Code = Stream_Code_Region_Mode);
   --  Ks_CNL_Search_Pattern'Read: the format code read must be one of the
   --  three; Masked tells that the mask follows, Region_Mode that
   --  TrainRegionMode does.

   procedure Check_Search
     (Pattern : access constant Ks_CNL_Search_Pattern_Data;
      Params  : Ks_CNL_Search_Run_Params;
      Status  : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Operator_Not_Trained
                         | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Valid_Pattern (Pattern)
                            and then Is_Trained (Pattern)
                            and then Params.Search_Region_Mode
                                       in Region_Mode_Pixel_Aligned_Bounding_Box
                                        | Region_Mode_Affine_Transform);
   --  The checks of the pattern and of the run parameters that Execute
   --  makes after the image (Operator_Not_Trained "Pattern is not
   --  trained", Bad_Parameter for an inconsistent pattern and for run
   --  parameters out of range, the partial match limits included), for
   --  AMV.Kernels.CNL_Search.Region_Modes.

   procedure Check_Stream_Flag
     (Value  : U32;
      Flag   : out Boolean;
      Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Image_File
             and then Succeeded (Status) = (Value <= 1)
             and then Flag = (Value = 1);
   --  A flag read must be 0 or 1.

   procedure Pattern_Get_Trained_Care_Image
     (Pattern : access constant Ks_CNL_Search_Pattern_Data;
      Image   : out KI.Ks_Image_8_Grey;
      Status  : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Operator_Not_Trained
                         | Failure_Bad_Parameter | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Image = null
                            or else (KI.Valid_Image (Image)
                                     and then Image.Width
                                       in Min_Pattern_Side .. Max_Pattern_Side
                                     and then Image.Height
                                       in Min_Pattern_Side .. Max_Pattern_Side)
                       else Image = null);
   --  Ks_CNL_Search_Pattern'Write: the care flags of the trained pattern
   --  at full resolution, as a new image of the size of
   --  Get_Trained_Pattern_Image (1 for a cared-for pixel, 0 for a
   --  don't-care one); null for a pattern trained without a mask.
   --  Operator_Not_Trained for an untrained pattern.

   procedure Restore_Trained
     (Pattern          : in out Ks_CNL_Search_Pattern;
      Pattern_Image    : access constant KI.Ks_Image_8_Grey_Data;
      Care_Image       : access constant KI.Ks_Image_8_Grey_Data;
      Origin_X         : Long_Float;
      Origin_Y         : Long_Float;
      Status           : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Out_Of_Memory
             and then (if Pattern /= null then Valid_Pattern (Pattern))
             and then Is_Trained (Pattern) = Succeeded (Status)
             and then
               (if Succeeded (Status)
                then KI.Valid_Image (Pattern_Image)
                     and then Pattern.Info (0).Geometry
                                = (Row    => 0,
                                   Width  => Natural (Pattern_Image.Width),
                                   Height => Natural (Pattern_Image.Height))
                     and then Pattern.Origin_X = Origin_X
                     and then Pattern.Origin_Y = Origin_Y
                     and then (if Care_Image = null
                               then Pattern.Care = null));
   --  Ks_CNL_Search_Pattern'Read (and ks_cnl_search_pattern_train_affine,
   --  on the resampled train region): trains the pattern on the whole of
   --  Pattern_Image (the trained pattern's pixels as the stream stores
   --  them) with the care flags of Care_Image (null: every pixel cared
   --  for; otherwise an image of the same size, 0 for a don't-care pixel,
   --  as a train image mask at offsets 0, 0) and the origin Origin_X,
   --  Origin_Y given in the pattern's pixel coordinates, keeping its
   --  training parameters. The checks are those of Pattern_Train_Masked
   --  (the image's size, the origin within Max_Origin and finite, enough
   --  cared-for pixels, a pattern that is not flat), and Bad_Parameter for
   --  care flags of another size, so a malformed stream cannot make an
   --  invalid pattern. Untrained on failure.

end AMV.Kernels.CNL_Search;
