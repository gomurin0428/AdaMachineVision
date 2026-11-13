--  Kernel of AMV.PM_Align: geometric pattern location with rotation and
--  scale (CogPMAlignTool, its pattern CogPMAlignPattern, run parameters
--  CogPMAlignRunParams, zones CogPMAlignZoneAngle and CogPMAlignZoneScale,
--  results CogPMAlignResults and CogPMAlignResult). Its entry points are
--  the C API of the tool (include/amv_pm_align.h, names ks_pm_align_*).
--
--  Clean room. PatMax and PatQuick are Cognex's own algorithms, which this
--  kernel does not reproduce. Only the names of the public API follow
--  VisionPro; the method is ours, built from public literature: shape
--  matching on gradient directions (the similarity measure of C. Steger,
--  "Similarity measures for occlusion, clutter, and illumination invariant
--  object recognition", 2001), searched coarse to fine over an image
--  pyramid, and refined by least squares on sub-pixel edge points. The
--  codes PatQuick and PatMax name two variants of that method, as
--  documented below; they do not mean what they mean in VisionPro.
--
--  The pattern (C: ks_pm_align_pattern *, opaque) is an owned handle that
--  ks_pm_align_pattern_create returns and ks_pm_align_pattern_destroy
--  frees. It holds the train parameters (TrainAlgorithm, the grain limits,
--  IgnorePolarity) and, once trained, the model: for each pyramid level
--  from Finest to Coarsest a list of features, each a point on an edge of
--  the train image and the unit normal of the edge there (the direction in
--  which the grey level rises), both in pattern coordinates. Pattern
--  coordinates are those of the train image's selected space mapped by the
--  inverse of Origin (Origin is the transform from pattern coordinates to
--  the train image's selected space, as CogPMAlignPattern.Origin). A null
--  pattern reads as an untrained pattern with the default parameters;
--  every operation that changes a pattern needs a handle (Bad_Parameter
--  "Pattern is null").
--
--  Training (ks_pm_align_pattern_train). The train image is smoothed
--  (Gaussian, sigma 1) and reduced to a pyramid (level k + 1 is level k
--  smoothed again and averaged over 2 x 2 blocks), over a window around
--  the bounding box of the train region. Level k has a grain of 2**k
--  pixels. At each level from Finest to Coarsest the kernel takes the edge
--  pixels: gradient magnitude (3 x 3 Sobel divided by 8, grey levels per
--  pixel of that level) at least the train threshold, a local maximum
--  along the gradient direction, and the pixel's centre in the train
--  region. The train threshold of a level is the larger of
--  Min_Train_Contrast and Train_Contrast_Fraction times the largest
--  magnitude among the region's pixels at that level (our own automatic
--  choice). Each edge pixel is moved along its gradient direction to the
--  peak of the gradient projected on it (a parabola through three samples
--  one pixel apart). The edge pixels are thinned evenly: the level is cut
--  into cells of Spacing x Spacing pixels, Spacing the smallest size in
--  1 .. Max_Spacing at which at most Max_Features cells hold an edge
--  pixel, and each such cell keeps its strongest edge pixel (so every
--  edge pixel is within Spacing - 1 pixels, along x and y, of a feature;
--  with more than Max_Features cells even at Max_Spacing, the first
--  Max_Features in raster order are kept). The levels:
--
--  * GrainLimitAutoSelect = 1 (the default): Finest = 0, and Coarsest the
--    highest level (at most Max_Levels - 1) at which the train region's
--    bounding box still spans Min_Coarse_Size pixels in both directions
--    and which has at least Min_Features features. The level at which the
--    results are measured is then chosen at run time (stages 2 to 4
--    below): a single train image cannot tell which of its fine edges
--    stay the same from part to part (a wire mesh, lettering, the grain of
--    a surface) and which do not;
--  * otherwise Finest = floor (log2 GrainLimitFine) and Coarsest = floor
--    (log2 GrainLimitCoarse), lowered to the last level with at least
--    Min_Features features.
--
--  Finest must have at least Min_Features features (Bad_Parameter
--  "TrainImage has too few edges in TrainRegion" otherwise). A failed
--  train leaves the pattern untrained.
--
--  The train image mask (ks_pm_align_pattern_train_masked; our own
--  meaning of TrainImageMask and its offsets). Mask pixel (U, V) covers
--  train image pixel (U + OffsetX, V + OffsetY); a mask pixel of 0 marks
--  it "don't care", any other value (and every pixel the mask does not
--  cover) "care". A pixel (I, J) of level K is used only when no
--  don't-care pixel lies within 2**K + 1 image pixels, along x and along
--  y, of the image pixel at its centre (its own block, one pixel of the
--  level for the Sobel operator and one image pixel for the smoothing;
--  Masks): the train threshold, the thinning and the features take only
--  those pixels, so no level keeps a feature of the left-out content.
--  The part left out is kept as ignored points: the level is cut into
--  cells of S x S pixels, S the smallest size in 1 .. Max_Ignored_Spacing
--  at which at most Max_Features cells hold a pixel of the region that
--  is not used, and each such cell's centre, in pattern coordinates, is
--  an ignored point (the first Max_Features in raster order when even
--  Max_Ignored_Spacing leaves more). The clutter of a result does not
--  count the pixels near them (stage 3), so content that changes from
--  part to part where the mask lies costs no score.
--
--  The search (ks_pm_align_execute). A pose maps pattern coordinates to
--  the input image's selected space: (x, y) goes to Scaling * R (Rotation)
--  (x, y) + (TranslationX, TranslationY), R (a) the rotation by a (radians,
--  counter-clockwise as seen in a y-down image). The kernel searches
--  Rotation in the angle zone and Scaling in the scale zone (a Nominal
--  zone fixes the value; a LowHigh zone spans [Low, High], the whole
--  circle when High - Low >= 2 Pi) and the position of the model's centroid
--  (the mean of the finest level's features) anywhere in the bounding box
--  of the search region; it works in pixels through the inverse of
--  Selected_From_Pixel. The input image is reduced to a pyramid as above
--  (over the search region's bounding box with a margin); at each level a
--  pixel keeps its unit gradient direction when its magnitude reaches
--  ContrastThreshold and its centre lies in the search region, and has none
--  otherwise. The score of a pose at a level is the mean, over the model's
--  features of that level, of the cosine between the feature's mapped
--  normal and the image's gradient direction at the pixel nearest to the
--  mapped feature (0 where the image has none; with IgnorePolarity its
--  absolute value): Steger's measure, with directions quantised to 1/127.
--
--  1. Coarse search at level Coarsest: every pixel as the centroid's
--     position, the angle zone in steps of about one pixel at the model's
--     outermost feature (1 / radius), the scale zone likewise; a position
--     stops being scored as soon as the remaining features cannot lift its
--     score to the coarse threshold. Local maxima of the score at each
--     angle and scale that reach the coarse threshold are candidates (the
--     best Max_Candidates are kept; candidates within one pixel, one angle
--     step and one scale step of a better one are dropped). The coarse
--     threshold is CoarseAcceptThreshold when CoarseAcceptThresholdEnabled,
--     otherwise Coarse_Factor * AcceptThreshold.
--  2. The best candidates (at most Tracked_Candidates, and at least twice
--     ApproximateNumberToFind) are followed down to level Finest: at each
--     level a hill climb over the neighbouring positions (one pixel),
--     angles and scales (one step of that level). A candidate whose score
--     falls below the coarse threshold is dropped; with the automatic
--     grain it stops instead at the level above, where it still reached
--     the threshold.
--  3. Each candidate is finished at the level where stage 2 left it (the
--     finest level unless it stopped). With the automatic grain, a PatMax
--     candidate whose Score misses AcceptThreshold there is finished again
--     one level coarser, and so on up to Coarsest, as long as the level's
--     model has at least Min_Result_Features features (a candidate left at
--     a level with fewer gives no result); then only the candidates
--     finished at the finest level at which one of them reaches
--     AcceptThreshold are kept (all of them when none does), so that the
--     results of a run are measured at one level. (Our own scheme: the
--     finest level at which the part is accepted, decided per run.)
--     PatQuick: the pose of the best grid point at that level, refined
--     to a fraction of a step by a parabola through the scores of its
--     neighbours along x, y and the angle; Score and Coverage are its
--     score there, Clutter and FitError 0, FineStage 0.
--     PatMax: the pose is refined by least squares at that level: each
--     feature looks along its mapped normal (two pixels each way) for the
--     peak of the image gradient projected on the normal, and the pose
--     (position, then the angle and the scale when their zones are not
--     Nominal) moves to minimise the squared distances along the normals
--     (Gauss-Seidel sweeps on the normal equations, Refine_Iterations
--     times). Then each feature inside the search region is matched when
--     such a peak of at least ContrastThreshold lies within Match_Distance
--     pixels and the gradient there is within Max_Match_Angle of the
--     normal; its quality is the cosine of that angle. Coverage is the
--     sum of the qualities over the number of features (a feature outside
--     the search region, or without a match, adds nothing); FitError
--     the root mean square distance (pixels of the input image) of the
--     matched features; Contrast their mean gradient magnitude. Clutter is
--     the fraction of the edge pixels of the search region inside the
--     model's footprint (its bounding box in pattern coordinates, mapped by
--     the pose) that lie more than a margin, along x and y, from every
--     mapped feature. The edge pixels are taken as in training: at the
--     larger of ContrastThreshold and Train_Contrast_Fraction times the
--     largest gradient magnitude in the footprint's bounding box, so that
--     texture weaker than the trained edges is not clutter. The margin is 2 pixels plus
--     Ceiling (1.5 * (Spacing - 1) * Scaling), the distance by which the
--     thinning can separate a trained edge from its feature. The pixels
--     within 1 + Ceiling (0.75 * S * Scaling), along x and y, of a mapped
--     ignored point of the train image mask (S its cells' size, so that
--     the square covers the cell turned by any angle) count neither as
--     edge pixels nor for that largest magnitude. Score is
--     Coverage * (1 - Clutter) when ScoreUsingClutter, otherwise Coverage.
--     FineStage 1.
--     BestTrained runs PatMax for a pattern trained with PatMax or
--     PatMaxAndPatQuick and PatQuick otherwise.
--  4. A result whose fraction of features outside the search region (and
--     the image) exceeds OutsideRegionThreshold, or whose Score is below
--     AcceptThreshold, is dropped, as is one whose model centroid lies
--     within half the model's radius of a better result, or whose
--     footprint shares more than XYOverlap of the smaller footprint's area
--     with a better result's (our own meaning of XYOverlap: the footprint
--     is the bounding box of the finest level's features in pattern
--     coordinates, mapped by the result's pose, a parallelogram; the
--     shared area is that of the two convex quadrilaterals' intersection,
--     Overlaps). The default 1.0 drops none for overlap. The best
--     ApproximateNumberToFind remain, best first, with ID = their index.
--
--  Not implemented: the run algorithms PatFlex and PatMaxPerspective and
--  the train algorithms PatFlex, PatMaxHighSensitivity and
--  PatMaxPerspective (Bad_Parameter); the timeout (the kernel has no
--  clock: TimeoutEnabled and Timeout are checked and kept, and the work of
--  a run is bounded by the limits below instead).
--
--  Coordinates and bounds. Every transform must be within the bound of
--  AMV.Kernels.Transforms (1.0E150) and invertible within it. Pattern
--  coordinates of the trained features must lie within
--  Max_Pattern_Coordinate (Bad_Parameter otherwise). Zone angles lie
--  within Max_Zone_Angle, zone scales in [Min_Zone_Scale, Max_Zone_Scale].
--  A feature that the pose and Selected_From_Pixel would map beyond
--  Max_Offset pixels from the centroid is treated as lying there (outside
--  every image). Every reported translation lies within 1.0E150 (a result
--  beyond is dropped), every rotation and scaling in its zone, so the pose
--  is a valid transform of AMV.Kernels.Transforms.
--
--  Proved (docs/PROOF.md): absence of run-time errors for any argument,
--  handles that are null or came from this kernel and non-finite values
--  included; no memory leaks; an untrained (or null) pattern never yields
--  results (Operator_Not_Trained); and of every results handle Execute
--  returns: at most ApproximateNumberToFind results, sorted by score
--  (highest first), every Score in [AcceptThreshold, 1], every Coverage
--  and Clutter in [0, 1], FitError and Contrast >= 0, the rotation and
--  the scaling in their zones and the translation within 1.0E150.
--
--  Trusted parts (SPARK_Mode Off bodies, listed in docs/PROOF.md): the
--  allocation helpers of the pattern and the results, which turn a failed
--  allocation into Out_Of_Memory. The images of the pyramids come from
--  the proved entry points of AMV.Kernels.Images and
--  AMV.Kernels.Image_Math.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Numerics;
with Interfaces;

with AMV.Kernels.Images;
with AMV.Kernels.Regions;
with AMV.Kernels.Transforms;

package AMV.Kernels.PM_Align with SPARK_Mode, Preelaborate is

   package KI renames AMV.Kernels.Images;
   package KR renames AMV.Kernels.Regions;
   package KT renames AMV.Kernels.Transforms;

   use type Interfaces.Unsigned_32;

   Max_Value : constant := 1.0E150;
   --  The bound of every transform entry and reported translation (the
   --  bound of AMV.Kernels.Transforms).

   ---------------------------------------------------------------------
   --  Codes (C: KS_PM_ALIGN_*; VisionPro's numeric values)
   ---------------------------------------------------------------------

   --  CogPMAlignTrainAlgorithmConstants. Only the first three are
   --  implemented; all three train the same model (see above).
   Train_Algorithm_Pat_Max                  : constant Int32 := 0;
   Train_Algorithm_Pat_Quick                : constant Int32 := 1;
   Train_Algorithm_Pat_Max_And_Pat_Quick    : constant Int32 := 2;
   Train_Algorithm_Pat_Flex                 : constant Int32 := 3;
   Train_Algorithm_Pat_Max_High_Sensitivity : constant Int32 := 4;
   Train_Algorithm_Pat_Max_Perspective      : constant Int32 := 5;

   --  CogPMAlignRunAlgorithmConstants. PatFlex and PatMaxPerspective are
   --  not implemented.
   Run_Algorithm_Pat_Max             : constant Int32 := 0;
   Run_Algorithm_Pat_Quick           : constant Int32 := 1;
   Run_Algorithm_Best_Trained        : constant Int32 := 2;
   Run_Algorithm_Pat_Flex            : constant Int32 := 3;
   Run_Algorithm_Pat_Max_Perspective : constant Int32 := 4;

   --  CogPMAlignZoneConstants.
   Zone_Nominal  : constant Int32 := 0;
   Zone_Low_High : constant Int32 := 1;

   ---------------------------------------------------------------------
   --  Limits (C: KS_PM_ALIGN_*)
   ---------------------------------------------------------------------

   Max_Levels : constant := 6;
   --  Pyramid levels 0 .. 5 (grains 1 to 32 pixels).
   Max_Features : constant := 2048;
   --  The most features of one level of a model.
   Min_Features : constant := 8;
   --  The fewest features of a trained level.
   Min_Coarse_Size : constant := 8;

   Min_Result_Features : constant := 64;
   --  With the automatic grain, a level gives results only when its model
   --  has at least this many features: a model of fewer features matches
   --  unrelated shapes too easily (PMAlign's test of discs and polygons in
   --  noise is accepted at a level of 41 features otherwise), while the
   --  outline of a textured part one or two levels up keeps far more.
   --  The automatic coarsest level keeps the train region's bounding box
   --  at least this many pixels wide and high.
   Max_Results_Limit : constant := 256;
   --  The largest ApproximateNumberToFind.
   Max_Candidates : constant := 512;
   --  The most candidates the coarse search keeps.
   Tracked_Candidates : constant := 64;
   --  The candidates followed down the pyramid (at least twice
   --  ApproximateNumberToFind, at most Max_Candidates).
   Max_Angle_Steps : constant := 2048;
   --  The most angles the coarse search samples (the step grows beyond).
   Max_Scale_Steps : constant := 64;
   --  The most scales the coarse search samples.
   Refine_Iterations : constant := 6;
   --  The least squares iterations of PatMax.
   Max_Pattern_Coordinate : constant := 1.0E9;
   --  The bound of the trained features' pattern coordinates.
   Max_Offset : constant := 2.0 ** 20;
   --  The bound of a mapped feature's offset from the centroid (pixels).
   Max_Contrast_Threshold : constant := 1000.0;
   --  The largest ContrastThreshold (a gradient magnitude never exceeds
   --  about 361 grey levels per pixel).
   Min_Zone_Scale : constant := 0.1;
   Max_Zone_Scale : constant := 10.0;
   --  The bounds of every scale of the scale zone.
   Max_Zone_Angle : constant := 1.0E4;
   --  The bound of every angle of the angle zone (radians).
   Max_Timeout : constant := 1.0E9;
   --  The largest Timeout (milliseconds).
   Max_Grain_Limit : constant := 32.0;
   --  The largest grain limit (2 ** (Max_Levels - 1)).

   --  Constants of the method (documented above).
   Min_Train_Contrast      : constant := 5.0;
   Train_Contrast_Fraction : constant := 0.2;
   Coarse_Factor           : constant := 0.7;
   Match_Distance          : constant := 1.0;
   Max_Match_Angle         : constant := Ada.Numerics.Pi / 4.0;

   subtype Level_Index is Natural range 0 .. Max_Levels - 1;

   ---------------------------------------------------------------------
   --  Parameters (C: ks_pm_align_train_params, ks_pm_align_zone,
   --  ks_pm_align_run_params)
   ---------------------------------------------------------------------

   type Ks_PM_Align_Train_Params is record
      Train_Algorithm         : Int32 := Train_Algorithm_Pat_Max;
      Grain_Limit_Auto_Select : Int32 := True_Value;
      Ignore_Polarity         : Int32 := False_Value;
      Grain_Limit_Coarse      : Long_Float := 8.0;
      Grain_Limit_Fine        : Long_Float := 1.0;
   end record
     with Convention => C;
   --  The train inputs of CogPMAlignPattern other than the image, the
   --  region and Origin (AMV defaults). Limits: TrainAlgorithm one of the
   --  three implemented codes; the flags 0 or 1; the grain limits finite,
   --  1 <= GrainLimitFine <= GrainLimitCoarse <= Max_Grain_Limit.

   type Ks_PM_Align_Zone_Angle is record
      Configuration : Int32 := Zone_Nominal;
      Low           : Long_Float := -Ada.Numerics.Pi;
      High          : Long_Float := Ada.Numerics.Pi;
      Nominal       : Long_Float := 0.0;
   end record
     with Convention => C;
   --  CogPMAlignZoneAngle (radians; AMV defaults: Nominal 0, and the whole
   --  circle for LowHigh). Limits: Configuration a zone code; the angles
   --  finite and within Max_Zone_Angle; Low <= High for LowHigh.

   type Ks_PM_Align_Zone_Scale is record
      Configuration : Int32 := Zone_Nominal;
      Low           : Long_Float := 0.9;
      High          : Long_Float := 1.1;
      Nominal       : Long_Float := 1.0;
   end record
     with Convention => C;
   --  CogPMAlignZoneScale (AMV defaults). Limits: Configuration a zone
   --  code; the scales in [Min_Zone_Scale, Max_Zone_Scale]; Low <= High
   --  for LowHigh.

   type Ks_PM_Align_Run_Params is record
      Accept_Threshold                : Long_Float := 0.5;
      Coarse_Accept_Threshold         : Long_Float := 0.3;
      Contrast_Threshold              : Long_Float := 10.0;
      Outside_Region_Threshold        : Long_Float := 0.1;
      Timeout                         : Long_Float := 10_000.0;
      Approximate_Number_To_Find      : Int32 := 1;
      Run_Algorithm                   : Int32 := Run_Algorithm_Pat_Max;
      Score_Using_Clutter             : Int32 := True_Value;
      Timeout_Enabled                 : Int32 := False_Value;
      Coarse_Accept_Threshold_Enabled : Int32 := False_Value;
      Zone_Angle                      : Ks_PM_Align_Zone_Angle;
      Zone_Scale                      : Ks_PM_Align_Zone_Scale;
      XY_Overlap                      : Long_Float := 1.0;
   end record
     with Convention => C;
   --  CogPMAlignRunParams (AMV defaults). Limits: the thresholds
   --  AcceptThreshold, CoarseAcceptThreshold and OutsideRegionThreshold in
   --  [0, 1]; ContrastThreshold in [0, Max_Contrast_Threshold]; Timeout in
   --  [0, Max_Timeout]; ApproximateNumberToFind in 1 ..
   --  Max_Results_Limit; RunAlgorithm one of PatMax, PatQuick and
   --  BestTrained; the flags 0 or 1; the zones as above.

   ---------------------------------------------------------------------
   --  The pattern (CogPMAlignPattern; C: ks_pm_align_pattern *, opaque)
   ---------------------------------------------------------------------

   subtype Pattern_Coordinate is Long_Float
     range -Max_Pattern_Coordinate .. Max_Pattern_Coordinate;
   subtype Unit_Component is Long_Float range -1.0 .. 1.0;

   type Model_Feature is record
      X, Y   : Pattern_Coordinate := 0.0;
      NX, NY : Unit_Component := 0.0;
   end record;
   --  A feature: a point on an edge and the unit normal of the edge there
   --  (towards the brighter side), in pattern coordinates.

   type Model_Feature_Array is array (0 .. Max_Features - 1) of Model_Feature;

   subtype Feature_Count is Natural range 0 .. Max_Features;

   Max_Spacing : constant := 16;
   subtype Spacing_Value is Positive range 1 .. Max_Spacing;

   Max_Ignored_Spacing : constant := 64;
   subtype Ignored_Spacing_Value is Positive range 1 .. Max_Ignored_Spacing;

   type Ignored_Point is record
      X, Y : Pattern_Coordinate := 0.0;
   end record;
   --  The centre of a cell of a level that the train image mask leaves
   --  out (at least one of its region pixels is not cared for), in
   --  pattern coordinates.

   type Ignored_Point_Array is array (0 .. Max_Features - 1) of Ignored_Point;

   type Model_Level is record
      Count           : Feature_Count := 0;
      Spacing         : Spacing_Value := 1;
      Features        : Model_Feature_Array;
      Ignored_Count   : Feature_Count := 0;
      Ignored_Spacing : Ignored_Spacing_Value := 1;
      Ignored         : Ignored_Point_Array;
   end record;
   --  The features of one level: Features (0 .. Count - 1), at most one in
   --  each Spacing x Spacing cell of the level's pixels (see Training);
   --  and, with a train image mask, Ignored (0 .. Ignored_Count - 1), the
   --  centres of the Ignored_Spacing x Ignored_Spacing cells that the
   --  mask leaves out, whose edges the clutter does not count.

   type Model_Level_Array is array (Level_Index) of Model_Level;

   type Ks_PM_Align_Pattern_Data is record
      Params   : Ks_PM_Align_Train_Params;
      Trained  : Boolean := False;
      Finest   : Level_Index := 0;
      Coarsest : Level_Index := 0;
      Levels   : Model_Level_Array;
   end record;
   --  What a handle designates (opaque for C): the train parameters and,
   --  when Trained, the model at the levels Finest .. Coarsest (the other
   --  levels are empty).

   type Ks_PM_Align_Pattern is access Ks_PM_Align_Pattern_Data
     with Convention => C;
   --  C: ks_pm_align_pattern *.

   function Trained_Pattern
     (Pattern : access constant Ks_PM_Align_Pattern_Data) return Boolean
   is (Pattern /= null and then Pattern.Trained);
   --  A pattern that can be searched for.

   type Ks_PM_Align_Feature is record
      X, Y               : Long_Float := 0.0;
      Normal_X, Normal_Y : Long_Float := 0.0;
   end record
     with Convention => C;
   --  C: ks_pm_align_feature. A trained feature as the accessors give it:
   --  its point and its unit normal in pattern coordinates.

   type Ks_PM_Align_Feature_Array is
     array (Natural range <>) of Ks_PM_Align_Feature;

   ---------------------------------------------------------------------
   --  Results (CogPMAlignResults; C: ks_pm_align_results *, opaque)
   ---------------------------------------------------------------------

   type Ks_PM_Align_Result is record
      Score                             : Long_Float := 0.0;
      Coverage                          : Long_Float := 0.0;
      Clutter                           : Long_Float := 0.0;
      Fit_Error                         : Long_Float := 0.0;
      Contrast                          : Long_Float := 0.0;
      Outside_Region_Feature_Proportion : Long_Float := 0.0;
      Translation_X                     : Long_Float := 0.0;
      Translation_Y                     : Long_Float := 0.0;
      Rotation                          : Long_Float := 0.0;
      Scaling                           : Long_Float := 1.0;
      ID                                : Int32 := 0;
      Fine_Stage                        : Int32 := 0;
   end record
     with Convention => C;
   --  C: ks_pm_align_result (CogPMAlignResult): the measures described
   --  above and the pose (TranslationX/Y, Rotation, Scaling; GetPose
   --  builds the transform).

   type Result_Array is array (0 .. Max_Results_Limit - 1)
     of Ks_PM_Align_Result;

   subtype Result_Count is Natural range 0 .. Max_Results_Limit;

   type Ks_PM_Align_Results_Data is record
      Count : Result_Count := 0;
      Items : Result_Array;
   end record;
   --  What a handle designates (opaque for C): Items (0 .. Count - 1).

   type Ks_PM_Align_Results is access Ks_PM_Align_Results_Data
     with Convention => C;
   --  C: ks_pm_align_results *.

   function In_Bound (X : Long_Float) return Boolean is
     (X >= -Max_Value and then X <= Max_Value);

   function In_Zone
     (Value : Long_Float;
      Zone  : Ks_PM_Align_Zone_Angle) return Boolean
   is (if Zone.Configuration = Zone_Low_High
       then Value >= Zone.Low and then Value <= Zone.High
       else Value = Zone.Nominal);

   function In_Zone
     (Value : Long_Float;
      Zone  : Ks_PM_Align_Zone_Scale) return Boolean
   is (if Zone.Configuration = Zone_Low_High
       then Value >= Zone.Low and then Value <= Zone.High
       else Value = Zone.Nominal);
   --  Value lies in the zone: within [Low, High] for LowHigh, Nominal
   --  itself for Nominal.

   function Good_Result
     (Item   : Ks_PM_Align_Result;
      Params : Ks_PM_Align_Run_Params) return Boolean
   is (Item.Score >= Params.Accept_Threshold and then Item.Score <= 1.0
       and then Item.Coverage >= 0.0 and then Item.Coverage <= 1.0
       and then Item.Clutter >= 0.0 and then Item.Clutter <= 1.0
       and then Item.Fit_Error >= 0.0 and then Item.Contrast >= 0.0
       and then Item.Outside_Region_Feature_Proportion >= 0.0
       and then Item.Outside_Region_Feature_Proportion <= 1.0
       and then In_Bound (Item.Translation_X)
       and then In_Bound (Item.Translation_Y)
       and then In_Zone (Item.Rotation, Params.Zone_Angle)
       and then In_Zone (Item.Scaling, Params.Zone_Scale));
   --  The proved facts of one result.

   function Gold_Results
     (Results : access constant Ks_PM_Align_Results_Data;
      Params  : Ks_PM_Align_Run_Params) return Boolean
   is (Results /= null
       and then Int64 (Results.Count)
                  <= Int64 (Params.Approximate_Number_To_Find)
       and then (for all I in 0 .. Results.Count - 1 =>
                   Good_Result (Results.Items (I), Params))
       and then (for all I in 1 .. Results.Count - 1 =>
                   Results.Items (I - 1).Score >= Results.Items (I).Score));
   --  The proved facts of every handle Execute returns.

   ---------------------------------------------------------------------
   --  Entry points: parameters
   ---------------------------------------------------------------------

   procedure Train_Params_Default
     (Params : out Ks_PM_Align_Train_Params;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_pm_align_train_params_default",
     Post => Valid (Status) and then Succeeded (Status);
   --  The defaults of the train parameters (the record's default values).

   procedure Run_Params_Default
     (Params : out Ks_PM_Align_Run_Params;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_pm_align_run_params_default",
     Post => Valid (Status) and then Succeeded (Status);
   --  The defaults of CogPMAlignRunParams (the record's default values).

   procedure Check_Run_Params
     (Params : Ks_PM_Align_Run_Params;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_pm_align_check_run_params",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter;
   --  The checks of the run parameters that Execute makes, alone
   --  ("RunParams.AcceptThreshold must be in [0, 1]", ...).

   ---------------------------------------------------------------------
   --  Entry points: the pattern
   ---------------------------------------------------------------------

   procedure Pattern_Create
     (Pattern : out Ks_PM_Align_Pattern;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_pm_align_pattern_create",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Pattern /= null and then not Pattern.Trained
                       else Pattern = null);
   --  A new untrained pattern with the default train parameters.

   procedure Pattern_Destroy (Pattern : in out Ks_PM_Align_Pattern)
   with
     Export, Convention => C,
     External_Name => "ks_pm_align_pattern_destroy",
     Post => Pattern = null;
   --  Frees the pattern and sets the handle to null; nothing for null.

   procedure Pattern_Duplicate
     (Pattern : access constant Ks_PM_Align_Pattern_Data;
      Copy    : out Ks_PM_Align_Pattern;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_pm_align_pattern_duplicate",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then (if Succeeded (Status) and then Pattern /= null
                       then Copy /= null and then Copy.all = Pattern.all
                       else Copy = null);
   --  A new pattern with the same parameters and model (null for null).

   procedure Pattern_Get_Train_Params
     (Pattern : access constant Ks_PM_Align_Pattern_Data;
      Params  : out Ks_PM_Align_Train_Params;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_pm_align_pattern_get_train_params",
     Post => Valid (Status) and then Succeeded (Status)
             and then Params.Train_Algorithm
                        in Train_Algorithm_Pat_Max | Train_Algorithm_Pat_Quick
                         | Train_Algorithm_Pat_Max_And_Pat_Quick;
   --  The pattern's train parameters (the defaults for null, and for
   --  parameters that are not valid, which a pattern never holds: every
   --  entry point that stores them checks them first).

   procedure Pattern_Set_Train_Params
     (Pattern : Ks_PM_Align_Pattern;
      Params  : Ks_PM_Align_Train_Params;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_pm_align_pattern_set_train_params",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Pattern /= null and then not Pattern.Trained
                            and then Pattern.Params = Params);
   --  Stores Params (checked: Bad_Parameter naming the property, "Pattern.
   --  GrainLimitFine must be in [1, GrainLimitCoarse]") and untrains the
   --  pattern. A failed call changes nothing. Bad_Parameter for null.

   procedure Pattern_Train
     (Pattern             : Ks_PM_Align_Pattern;
      Image               : access constant KI.Ks_Image_8_Grey_Data;
      Region              : access constant KR.Ks_Pixel_Region_Data;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Origin              : KT.Ks_Transform_2D_Linear;
      Status              : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_pm_align_pattern_train",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Transform_Singular
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status) then Trained_Pattern (Pattern)
                       elsif Pattern /= null then not Pattern.Trained);
   --  Train: builds the model from Image within Region (the region of the
   --  image's pixels, as AMV.Regions rasterises TrainRegion; null, the
   --  empty region, fails), with Selected_From_Pixel the transform from
   --  pixel space to the train image's selected space and Origin the
   --  transform from pattern coordinates to that space. Failures, in this
   --  order: Bad_Parameter for a null pattern; Image_No_Pixels for a null
   --  image ("TrainImage has no pixels"); Bad_Parameter for an
   --  inconsistent image or region handle, an empty region or one that
   --  does not lie in the image ("TrainRegion ..."), a transform beyond
   --  the bound; Transform_Singular when Origin or Selected_From_Pixel has
   --  no inverse within the bound; Bad_Parameter for too few edges or a
   --  feature beyond Max_Pattern_Coordinate; Out_Of_Memory. The pattern is
   --  untrained when the call fails. The same as Pattern_Train_Masked
   --  without a mask.

   procedure Pattern_Train_Masked
     (Pattern             : Ks_PM_Align_Pattern;
      Image               : access constant KI.Ks_Image_8_Grey_Data;
      Region              : access constant KR.Ks_Pixel_Region_Data;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Origin              : KT.Ks_Transform_2D_Linear;
      Mask                : access constant KI.Ks_Image_8_Grey_Data;
      Mask_Offset_X       : Int32;
      Mask_Offset_Y       : Int32;
      Status              : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_pm_align_pattern_train_masked",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Transform_Singular
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status) then Trained_Pattern (Pattern)
                       elsif Pattern /= null then not Pattern.Trained);
   --  Train with TrainImageMask (Mask; null: none) at TrainImageMaskOffsetX
   --  and TrainImageMaskOffsetY: mask pixel (U, V) covers train image pixel
   --  (U + Mask_Offset_X, V + Mask_Offset_Y); a mask pixel of value 0
   --  marks it "don't care", any other value (and every pixel the mask
   --  does not cover) "care" (see "The train image mask" above). Failures
   --  as Pattern_Train, and Bad_Parameter for an inconsistent mask handle
   --  ("TrainImageMask is not a valid image handle", after the checks of
   --  Origin) or a train window too large for a mask.

   procedure Pattern_Trained
     (Pattern : access constant Ks_PM_Align_Pattern_Data;
      Result  : out Int32;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_pm_align_pattern_trained",
     Post => Valid (Status) and then Succeeded (Status)
             and then Result in False_Value | True_Value
             and then (Result = True_Value) = Trained_Pattern (Pattern);
   --  Trained: 1 when the pattern holds a model (0 for null).

   procedure Pattern_Untrain
     (Pattern : Ks_PM_Align_Pattern;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_pm_align_pattern_untrain",
     Post => Valid (Status) and then Succeeded (Status)
             and then not Trained_Pattern (Pattern);
   --  Untrain: drops the model (nothing for null).

   procedure Pattern_Levels
     (Pattern          : access constant Ks_PM_Align_Pattern_Data;
      Finest, Coarsest : out Int32;
      Status           : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_pm_align_pattern_levels",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Operator_Not_Trained
             and then Finest in 0 .. Max_Levels - 1
             and then Coarsest in Finest .. Max_Levels - 1;
   --  The finest and coarsest level of the model. Operator_Not_Trained
   --  (and 0, 0) for a pattern that is not trained.

   procedure Pattern_Feature_Count
     (Pattern : access constant Ks_PM_Align_Pattern_Data;
      Level   : Int32;
      Count   : out Int32;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_pm_align_pattern_feature_count",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Operator_Not_Trained
                         | Failure_Index_Out_Of_Range
             and then Count in 0 .. Max_Features
             and then (if Succeeded (Status)
                       then Trained_Pattern (Pattern)
                            and then Level in 0 .. Max_Levels - 1);
   --  The number of features of a level of the model (0 for a level
   --  outside Finest .. Coarsest within 0 .. Max_Levels - 1).
   --  Operator_Not_Trained for a pattern that is not trained;
   --  Index_Out_Of_Range for a level outside 0 .. Max_Levels - 1.

   procedure Pattern_Feature
     (Pattern : access constant Ks_PM_Align_Pattern_Data;
      Level   : Int32;
      Index   : Int32;
      Feature : out Ks_PM_Align_Feature;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_pm_align_pattern_feature",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Operator_Not_Trained
                         | Failure_Index_Out_Of_Range;
   --  Feature Index (0-based) of a level of the model (the trained
   --  features, for display: VisionPro draws them with
   --  CreateGraphicsCoarse and CreateGraphicsFine). Index_Out_Of_Range
   --  outside the level or its features.

   ---------------------------------------------------------------------
   --  Entry points: running
   ---------------------------------------------------------------------

   procedure Execute
     (Image               : access constant KI.Ks_Image_8_Grey_Data;
      Region              : access constant KR.Ks_Pixel_Region_Data;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Pattern             : access constant Ks_PM_Align_Pattern_Data;
      Params              : Ks_PM_Align_Run_Params;
      Results             : out Ks_PM_Align_Results;
      Status              : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_pm_align_execute",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter
                         | Failure_Operator_Not_Trained
                         | Failure_Transform_Singular
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Trained_Pattern (Pattern)
                            and then Gold_Results (Results, Params)
                       else Results = null);
   --  Runs the search (CogPMAlignTool.Run) on Image within Region (the
   --  search region of the image's pixels, as AMV.Regions rasterises
   --  SearchRegion; null, the empty region, gives no results), reporting
   --  poses in the space that Selected_From_Pixel maps pixel space to.
   --  Returns a new results handle (null on failure). Failures, in this
   --  order: Operator_Not_Trained for a pattern that is null or not
   --  trained ("Pattern is not trained"); Bad_Parameter for bad run
   --  parameters (naming the property); Operator_Not_Trained when
   --  RunAlgorithm needs what TrainAlgorithm did not train ("Pattern is
   --  not trained for PatQuick"); Image_No_Pixels for a null image
   --  ("InputImage has no pixels"); Bad_Parameter for an inconsistent
   --  image or region handle, a region that does not lie in the image, a
   --  transform beyond the bound; Transform_Singular when
   --  Selected_From_Pixel has no inverse within the bound; Out_Of_Memory.

   procedure Results_Destroy (Results : in out Ks_PM_Align_Results)
   with
     Export, Convention => C,
     External_Name => "ks_pm_align_results_destroy",
     Post => Results = null;
   --  Frees the results and sets the handle to null; nothing for null.

   procedure Results_Count
     (Results : access constant Ks_PM_Align_Results_Data;
      Count   : out Int32;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_pm_align_results_count",
     Post => Valid (Status) and then Succeeded (Status)
             and then Count in 0 .. Max_Results_Limit
             and then (if Results /= null then Count = Int32 (Results.Count)
                       else Count = 0);
   --  Count: the number of results (0 for null).

   procedure Results_Item
     (Results : access constant Ks_PM_Align_Results_Data;
      Index   : Int32;
      Item    : out Ks_PM_Align_Result;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_pm_align_results_item",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Index_Out_Of_Range
             and then (if Succeeded (Status)
                       then Results /= null
                            and then Index in 0 .. Int32 (Results.Count) - 1
                            and then Item
                                       = Results.Items (Natural (Index)));
   --  Item (Index), 0-based: Index_Out_Of_Range outside 0 .. Count - 1
   --  (always for null).

   procedure Result_Get_Pose
     (Item   : Ks_PM_Align_Result;
      Pose   : out KT.Ks_Transform_2D_Linear;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_pm_align_result_get_pose",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status) then KT.Bounded (Pose));
   --  GetPose: the similarity Scaling * R (Rotation) followed by the
   --  translation, as ks_transform_2d_linear_create_similarity builds it.
   --  Bad_Parameter for an item whose values are beyond the bounds (never
   --  for an item of a results handle).

   ---------------------------------------------------------------------
   --  Ada-only helpers (no C entry points)
   ---------------------------------------------------------------------

   procedure Get_Features
     (Pattern  : access constant Ks_PM_Align_Pattern_Data;
      Level    : Int32;
      Features : out Ks_PM_Align_Feature_Array;
      Status   : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Operator_Not_Trained
                         | Failure_Index_Out_Of_Range
                         | Failure_Bad_Parameter;
   --  Copies the features of a level into Features, which must have
   --  exactly as many elements (Bad_Parameter otherwise; any bounds), for
   --  the Ada API's Get_Trained_Features.

   procedure Check_Train_Image
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter;
   --  The first checks of Pattern_Train: Image_No_Pixels for null
   --  ("TrainImage has no pixels"), Bad_Parameter for an inconsistent
   --  handle. The Ada API makes them before it rasterises TrainRegion.

   procedure Check_Inputs
     (Image   : access constant KI.Ks_Image_8_Grey_Data;
      Pattern : access constant Ks_PM_Align_Pattern_Data;
      Params  : Ks_PM_Align_Run_Params;
      Status  : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter
                         | Failure_Operator_Not_Trained;
   --  The checks of Execute that come before the search region, in its
   --  order (the pattern, the run parameters, the algorithm, the image).
   --  The Ada API makes them before it rasterises SearchRegion.

   --  Streams (the stream attributes of AMV.PM_Align.Ks_PM_Align_Pattern).
   --  The Ada API reads the stream; these helpers check every value read
   --  and fail with Image_File ("Ks_PM_Align_Pattern'Read: ...").

   Stream_Code : constant Interfaces.Unsigned_32 := 16#4B53_5042#;
   --  "KSPB": the format code of a pattern in a stream (since the levels
   --  carry their spacing; "KSPA" streams are rejected).

   Stream_Code_Masked : constant Interfaces.Unsigned_32 := 16#4B53_5043#;
   --  "KSPC": the format 'Write uses since the train image mask: each
   --  level's features are followed by its ignored points (their spacing,
   --  their count and their coordinates), and the model by the mask and
   --  its offsets. "KSPB" streams are still read (no mask, no ignored
   --  points).

   procedure Write_Levels
     (Pattern          : access constant Ks_PM_Align_Pattern_Data;
      Trained          : out Int32;
      Finest, Coarsest : out Int32;
      First, Last      : out Int32;
      Status           : out Ks_Status)
   with
     Post => Valid (Status) and then Succeeded (Status)
             and then Trained in False_Value | True_Value
             and then Finest in 0 .. Max_Levels - 1
             and then Coarsest in 0 .. Max_Levels - 1
             and then First in 0 .. Max_Levels - 1
             and then Last in -1 .. Max_Levels - 1;
   --  What 'Write stores of the model: Trained (0 or 1), the levels
   --  (Finest and Coarsest, 0 and 0 for an untrained pattern) and the
   --  levels whose features follow (First .. Last: Finest .. Coarsest, or
   --  none, 0 .. -1, for an untrained pattern).

   procedure Check_Read_Code
     (Code   : Interfaces.Unsigned_32;
      Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Image_File;
   --  The format code read must be Stream_Code or Stream_Code_Masked.

   procedure Read_Start
     (Pattern          : Ks_PM_Align_Pattern;
      Params           : Ks_PM_Align_Train_Params;
      Trained          : Int32;
      Finest, Coarsest : Int32;
      First, Last      : out Int32;
      Status           : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Image_File
             and then (if Pattern /= null then not Pattern.Trained)
             and then First in 0 .. Max_Levels - 1
             and then Last in -1 .. Max_Levels - 1;
   --  Starts reading a pattern: checks Params (as
   --  Pattern_Set_Train_Params), Trained (0 or 1) and, when Trained is 1,
   --  the levels (0 <= Finest <= Coarsest < Max_Levels); stores them in
   --  the pattern and empties every level. First .. Last are the levels
   --  whose features follow in the stream (Finest .. Coarsest when
   --  Trained is 1; none, 0 .. -1, otherwise or on failure). The pattern
   --  stays untrained (and, when Trained is 1, until Read_Finish
   --  succeeds).

   procedure Read_Feature
     (Pattern        : Ks_PM_Align_Pattern;
      Level          : Int32;
      X, Y, NX, NY   : Long_Float;
      Status         : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Image_File;
   --  Appends a feature read to a level between Finest and Coarsest: the
   --  level must have room, X and Y must be finite and within
   --  Max_Pattern_Coordinate, NX and NY finite and within [-1, 1].

   procedure Read_Finish
     (Pattern : Ks_PM_Align_Pattern;
      Trained : Int32;
      Status  : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Image_File;
   --  Ends reading a pattern: when Trained is 1, marks the model trained
   --  when every level between Finest and Coarsest holds at least
   --  Min_Features features (Image_File otherwise); nothing for 0.

   procedure Level_Spacing
     (Pattern : access constant Ks_PM_Align_Pattern_Data;
      Level   : Int32;
      Spacing : out Interfaces.Unsigned_32;
      Status  : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Operator_Not_Trained
                         | Failure_Index_Out_Of_Range
             and then Spacing in 1 .. Max_Spacing;
   --  What 'Write stores before the features of a level: its spacing
   --  (failures as Pattern_Feature_Count; 1 on failure).

   procedure Read_Spacing
     (Pattern : Ks_PM_Align_Pattern;
      Level   : Int32;
      Spacing : Interfaces.Unsigned_32;
      Status  : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Image_File;
   --  Sets the spacing read for a level between Finest and Coarsest: it
   --  must be in 1 .. Max_Spacing.

   procedure Check_Read_Count
     (Count  : Interfaces.Unsigned_32;
      Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Image_File
             and then (if Succeeded (Status)
                       then Count in Min_Features .. Max_Features);
   --  The number of features of a level read must be in Min_Features ..
   --  Max_Features.

   procedure Level_Ignored
     (Pattern : access constant Ks_PM_Align_Pattern_Data;
      Level   : Int32;
      Spacing : out Interfaces.Unsigned_32;
      Count   : out Int32;
      Status  : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Operator_Not_Trained
                         | Failure_Index_Out_Of_Range
             and then Spacing in 1 .. Max_Ignored_Spacing
             and then Count in 0 .. Max_Features;
   --  What 'Write stores after the features of a level: the spacing and
   --  the number of its ignored points (failures as Level_Spacing; 1 and
   --  0 on failure).

   procedure Pattern_Ignored_Point
     (Pattern : access constant Ks_PM_Align_Pattern_Data;
      Level   : Int32;
      Index   : Int32;
      X, Y    : out Long_Float;
      Status  : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Operator_Not_Trained
                         | Failure_Index_Out_Of_Range;
   --  Ignored point Index (0-based) of a level of a trained pattern (0.0
   --  and 0.0 on failure).

   procedure Read_Ignored_Spacing
     (Pattern : Ks_PM_Align_Pattern;
      Level   : Int32;
      Spacing : Interfaces.Unsigned_32;
      Status  : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Image_File;
   --  Sets the spacing of the ignored points read for a level between
   --  Finest and Coarsest: it must be in 1 .. Max_Ignored_Spacing.

   procedure Check_Read_Ignored_Count
     (Count  : Interfaces.Unsigned_32;
      Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Image_File
             and then (if Succeeded (Status) then Count <= Max_Features);
   --  The number of ignored points of a level read must be at most
   --  Max_Features.

   procedure Read_Ignored
     (Pattern : Ks_PM_Align_Pattern;
      Level   : Int32;
      X, Y    : Long_Float;
      Status  : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Image_File;
   --  Appends an ignored point read to a level between Finest and
   --  Coarsest: the level must have room, X and Y must be finite and
   --  within Max_Pattern_Coordinate.

private

   --  The checks of the parameters, for the private children.

   function Valid_Angle_Zone (Z : Ks_PM_Align_Zone_Angle) return Boolean is
     (if Z.Configuration = Zone_Low_High
      then Z.Low >= -Max_Zone_Angle and then Z.High <= Max_Zone_Angle
           and then Z.Low <= Z.High
      else Z.Configuration = Zone_Nominal
           and then Z.Nominal >= -Max_Zone_Angle
           and then Z.Nominal <= Max_Zone_Angle);
   --  The values the zone uses are finite and within Max_Zone_Angle.

   function Valid_Scale_Zone (Z : Ks_PM_Align_Zone_Scale) return Boolean is
     (if Z.Configuration = Zone_Low_High
      then Z.Low >= Min_Zone_Scale and then Z.High <= Max_Zone_Scale
           and then Z.Low <= Z.High
      else Z.Configuration = Zone_Nominal
           and then Z.Nominal >= Min_Zone_Scale
           and then Z.Nominal <= Max_Zone_Scale);
   --  The values the zone uses are within [Min_Zone_Scale,
   --  Max_Zone_Scale].

   function Valid_Train_Params (P : Ks_PM_Align_Train_Params) return Boolean
   is (P.Train_Algorithm
         in Train_Algorithm_Pat_Max | Train_Algorithm_Pat_Quick
          | Train_Algorithm_Pat_Max_And_Pat_Quick
       and then P.Grain_Limit_Auto_Select in False_Value | True_Value
       and then P.Ignore_Polarity in False_Value | True_Value
       and then P.Grain_Limit_Fine >= 1.0
       and then P.Grain_Limit_Fine <= P.Grain_Limit_Coarse
       and then P.Grain_Limit_Coarse <= Max_Grain_Limit);

   function Valid_Run_Params (P : Ks_PM_Align_Run_Params) return Boolean is
     (P.Accept_Threshold >= 0.0 and then P.Accept_Threshold <= 1.0
      and then P.Coarse_Accept_Threshold >= 0.0
      and then P.Coarse_Accept_Threshold <= 1.0
      and then P.Contrast_Threshold >= 0.0
      and then P.Contrast_Threshold <= Max_Contrast_Threshold
      and then P.Outside_Region_Threshold >= 0.0
      and then P.Outside_Region_Threshold <= 1.0
      and then P.Timeout >= 0.0 and then P.Timeout <= Max_Timeout
      and then P.Approximate_Number_To_Find in 1 .. Max_Results_Limit
      and then P.Run_Algorithm
                 in Run_Algorithm_Pat_Max | Run_Algorithm_Pat_Quick
                  | Run_Algorithm_Best_Trained
      and then P.Score_Using_Clutter in False_Value | True_Value
      and then P.Timeout_Enabled in False_Value | True_Value
      and then P.Coarse_Accept_Threshold_Enabled in False_Value | True_Value
      and then Valid_Angle_Zone (P.Zone_Angle)
      and then Valid_Scale_Zone (P.Zone_Scale)
      and then P.XY_Overlap >= 0.0 and then P.XY_Overlap <= 1.0);

end AMV.Kernels.PM_Align;
