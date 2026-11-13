--  The AffineTransform region mode of the CNL search tool, in both places
--  VisionPro has it (CogRegionModeConstants AffineTransform):
--  CogCNLSearchPattern.TrainRegionMode (Train_Affine) and
--  CogCNLSearchRunParams.SearchRegionMode (Execute_Affine). In both, the
--  region is an affine rectangle resampled into an upright image by
--  AMV.Kernels.Affine_Transform with that kernel's default run parameters
--  (one output pixel per input pixel along each side: a side of length L
--  pixels gives round (L) pixels; bilinear sampling), as the region modes
--  of the IP one-image and Sobel edge tools do; the pattern is trained,
--  or searched for, in that image. The C API is declared in
--  include/amv_cnl_search.h.
--
--  Training (Train_Affine, ks_cnl_search_pattern_train_affine). The
--  pattern's TrainRegionMode must be AffineTransform. Its pixels are the
--  resampled train region: output x runs along the rectangle's side X
--  from its corner origin, output y along side Y, so a rotated or skewed
--  part is trained upright. As in VisionPro, the train region must be an
--  affine rectangle (the Ada API rejects other shapes and an empty
--  region, Check_Affine_Train_Region) and must lie entirely in the train
--  image: every sample point of the resampled image within the area its
--  pixels cover (VisionPro may also reject a region a few pixels from the
--  edge; AMV needs no margin, since the bilinear sampling repeats the
--  border pixels within the outer half pixel). The resampled pattern must
--  have 8 .. 1024 pixels along each side.
--
--  The origin (AMV's rule; VisionPro states only that a result's location
--  is the position of the origin in the search image, and that OriginX,
--  OriginY are in the train image's selected space). The origin is the
--  point OriginX, OriginY of the train image's selected space, carried
--  into the resampled pattern by the resampling: mapped into the train
--  image's pixel space (Pixel_From_Selected) and then into the pattern's
--  pixels by the inverse of the resampling map (the pattern's
--  pixel-from-root transform that AMV.Kernels.Affine_Transform returns
--  when it is given Pixel_From_Selected as the root). It therefore marks
--  the same physical point of the trained part wherever the rectangle
--  lies and however it is turned, and a result's location is that point
--  in the search image: a part trained from a rectangle turned by 30
--  degrees and found upright in a scene is reported at the place of the
--  trained point, not at the corner of a window.
--
--  The train image mask (AMV's rule). Mask pixel (U, V) still covers
--  train image pixel (U + OffsetX, V + OffsetY). The mask is resampled
--  with the same rectangle, by nearest neighbour: a pattern pixel is
--  "don't care" when the train image pixel nearest to its sample point is
--  covered by a mask pixel of value 0, and "care" otherwise (any other
--  value, or not covered by the mask). The care flags then act as those of
--  any pattern (AMV.Kernels.CNL_Search, "The train image mask"). The
--  region itself masks nothing in this mode (the whole rectangle is the
--  pattern).
--
--  The search (Execute_Affine, ks_cnl_search_execute_affine). The run's
--  SearchRegionMode must be AffineTransform. The search region, an affine
--  rectangle, is resampled as above and searched whole, exactly as
--  ks_cnl_search_execute searches a pixel-aligned box: every window of the
--  resampled image, the partial match limits counting from its sides.
--  Each result's location (the pattern's origin at the match) is mapped
--  back from the resampled image into the input image's pixel space by
--  the resampling map and then by Selected_From_Pixel, so it is reported
--  in the input image's selected space like any other result; the score,
--  contrast and EdgeHit are those of the resampled image, where Left is
--  the rectangle's side through its corner origin along side Y, Top the
--  side through it along side X, and Right and Bottom the opposite sides.
--  CNL results have no angle: the pattern is searched for in the
--  rectangle's frame, so a turned rectangle finds the parts turned (and
--  skewed) with it relative to the trained pattern, and a part upright in
--  the image only when the rectangle is upright too; the location is the
--  only result mapped back. Samples outside the input image are 0 (the
--  resampling's default), so windows there are compared with black; keep
--  the rectangle in the image. A rectangle whose resampled image is
--  smaller than the pattern along either axis gives no results (a
--  successful run), as a pixel-aligned box does. VisionPro searches the
--  pixel-aligned bounding box of any other region in this mode (the Ada
--  API does so through ks_cnl_search_execute).
--
--  Bounds: the rectangle's values as in AMV.Kernels.Shapes (the centre and
--  the angles finite and within 1.0E150, the sides in 0 .. 4.0E150) and
--  every transform entry within 1.0E150 (AMV.Kernels.Transforms), the
--  bounds of AMV.Kernels.Affine_Transform; the resampled pattern 8 .. 1024
--  pixels along each side (Min_Pattern_Side, Max_Pattern_Side), the
--  resampled search rectangle at most Max_Search_Pixels pixels (the bound
--  of a search box); Bad_Parameter otherwise, naming the property.
--
--  Proved (docs/PROOF.md): absence of run-time errors for any image,
--  mask and pattern handle that is null or came from the kernels and any
--  rectangle, transform, offset and parameter values; no memory leaks (the
--  resampled images, the output mask and the work region are freed on
--  every path); Gold: a pattern trained by Train_Affine has exactly the
--  size AMV.Kernels.Affine_Transform gives the rectangle with its default
--  run parameters, and no care flags without a mask; every results handle
--  of Execute_Affine has the proved facts of ks_cnl_search_execute
--  (Gold_Results: scores in [0, 1] and at least AcceptThreshold, at most
--  MaxResults, sorted, IDs, EdgeHit), with every window inside the
--  resampled rectangle of that size extended by the partial match limits.
--  Not proved (tested): the resampled pixels and care flags (they come
--  from the proved resampling kernel), and the mapping of the locations
--  (tested against pixel-aligned searches and scenes with known ground
--  truth).

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Affine_Transform;
with AMV.Kernels.Shapes;

package AMV.Kernels.CNL_Search.Region_Modes
  with SPARK_Mode, Preelaborate
is

   package KA renames AMV.Kernels.Affine_Transform;
   package KSH renames AMV.Kernels.Shapes;

   Resampling : constant KA.Ks_Affine_Transform := (others => <>);
   --  The run parameters of the resampling (the affine transform tool's
   --  defaults).

   function Resampled_Width
     (Region            : KSH.Ks_Rectangle_Affine;
      Pixel_From_Region : KT.Ks_Transform_2D_Linear) return Int32
   is
     (KA.Output_Width (Region, Pixel_From_Region, Resampling))
   with Pre => KSH.Valid_Rectangle_Affine (Region)
               and then KT.Bounded (Pixel_From_Region);
   --  The width of the resampled rectangle (0 .. 32768; the resampling
   --  fails outside 1 .. 32767).

   function Resampled_Height
     (Region            : KSH.Ks_Rectangle_Affine;
      Pixel_From_Region : KT.Ks_Transform_2D_Linear) return Int32
   is
     (KA.Output_Height (Region, Pixel_From_Region, Resampling))
   with Pre => KSH.Valid_Rectangle_Affine (Region)
               and then KT.Bounded (Pixel_From_Region);

   ---------------------------------------------------------------------
   --  For the Ada API only (not exported)
   ---------------------------------------------------------------------

   procedure Check_Affine_Train_Region
     (Kind   : Int32;
      Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Succeeded (Status) = (Kind = KSH.Shape_Rectangle_Affine);
   --  Bad_Parameter "TrainRegion must be an affine rectangle for
   --  TrainRegionMode AffineTransform" unless Kind (a KSH.Shape_* code; 0
   --  for no region) is KSH.Shape_Rectangle_Affine.

   ---------------------------------------------------------------------
   --  Entry points
   ---------------------------------------------------------------------

   procedure Train_Affine
     (Pattern             : in out Ks_CNL_Search_Pattern;
      Image               : access constant KI.Ks_Image_8_Grey_Data;
      Region              : KSH.Ks_Rectangle_Affine;
      Pixel_From_Region   : KT.Ks_Transform_2D_Linear;
      Pixel_From_Selected : KT.Ks_Transform_2D_Linear;
      Mask                : access constant KI.Ks_Image_8_Grey_Data;
      Mask_Offset_X       : Int32;
      Mask_Offset_Y       : Int32;
      Status              : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_cnl_search_pattern_train_affine",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Transform_Singular
                         | Failure_Out_Of_Memory
             and then (if Pattern /= null then Valid_Pattern (Pattern))
             and then Is_Trained (Pattern) = Succeeded (Status)
             and then
               (if Succeeded (Status)
                then KSH.Valid_Rectangle_Affine (Region)
                     and then KT.Bounded (Pixel_From_Region)
                     and then Int64 (Pattern.Info (0).Geometry.Width)
                                = Int64 (Resampled_Width
                                           (Region, Pixel_From_Region))
                     and then Int64 (Pattern.Info (0).Geometry.Height)
                                = Int64 (Resampled_Height
                                           (Region, Pixel_From_Region))
                     and then (if Mask = null then Pattern.Care = null));
   --  Train in the mode AffineTransform (see above): trains the pattern
   --  on the affine rectangle Region of Image (Region is in the space that
   --  Pixel_From_Region maps to pixel space; Pixel_From_Selected maps the
   --  train image's selected space, where the origin is, to pixel space),
   --  with the train image mask Mask (null: none) at Mask_Offset_X,
   --  Mask_Offset_Y. The pattern is untrained first and on failure; a null
   --  handle stays null (it has the default mode). The checks, in order:
   --  the pattern (Bad_Parameter "Pattern is not a valid CNL search
   --  pattern", which resets it, then "Pattern.TrainRegionMode must be
   --  AffineTransform (2) for ks_cnl_search_pattern_train_affine"), the
   --  image (Image_No_Pixels "TrainImage has no pixels", Bad_Parameter),
   --  the rectangle ("TrainRegion.CenterX must be finite and within
   --  1.0E150", ...), the transforms, the mask handle ("TrainImageMask is
   --  not a valid image handle"), the size of the resampled rectangle
   --  ("TrainRegion must span at least 8 x 8 pixels", "... at most 1024 x
   --  1024 pixels"), then the failures of the resampling
   --  (Transform_Singular for a rectangle too flat, Out_Of_Memory), the
   --  rectangle outside the image ("TrainRegion must lie entirely in
   --  TrainImage for TrainRegionMode AffineTransform"), the origin
   --  ("Pattern.OriginX, OriginY lie more than 1.0E140 pixels from
   --  TrainRegion", ...), the mask's offsets ("TrainImageMaskOffsetX,
   --  TrainImageMaskOffsetY move TrainRegion beyond 1.0E150") and the
   --  training itself (too few cared-for pixels, a flat pattern; the
   --  messages of ks_cnl_search_pattern_train_masked).

   procedure Execute_Affine
     (Image               : access constant KI.Ks_Image_8_Grey_Data;
      Region              : KSH.Ks_Rectangle_Affine;
      Pixel_From_Region   : KT.Ks_Transform_2D_Linear;
      Pattern             : access constant Ks_CNL_Search_Pattern_Data;
      Params              : Ks_CNL_Search_Run_Params;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Results             : out Ks_CNL_Search_Results;
      Status              : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_cnl_search_execute_affine",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Operator_Not_Trained
                         | Failure_Bad_Parameter | Failure_Transform_Singular
                         | Failure_Out_Of_Memory
             and then (if not Is_Trained (Pattern)
                       then not Succeeded (Status))
             and then
               (if Succeeded (Status)
                then Gold_Results (Results)
                     and then KSH.Valid_Rectangle_Affine (Region)
                     and then KT.Bounded (Pixel_From_Region)
                     and then Results.Count <= Natural (Params.Max_Results)
                     and then (for all I in 0 .. Results.Count - 1 =>
                                 Results.Items (I).Item.Score
                                   >= Params.Accept_Threshold)
                     and then (if Results.Count > 0
                               then Area_In_Image
                                      (Results,
                                       Resampled_Width
                                         (Region, Pixel_From_Region),
                                       Resampled_Height
                                         (Region, Pixel_From_Region))
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
   --  Searches the affine rectangle Region of Image for Pattern in the
   --  mode AffineTransform (see above; Region is in the space that
   --  Pixel_From_Region maps to pixel space, Selected_From_Pixel maps
   --  pixel space to the image's selected space, where the locations are
   --  reported). Returns a new results handle (null on failure). The
   --  checks, in order: the image (Image_No_Pixels "InputImage has no
   --  pixels"), the pattern and the run parameters (those of
   --  ks_cnl_search_execute: Operator_Not_Trained "Pattern is not
   --  trained", Bad_Parameter for parameters out of range), the mode
   --  ("RunParams.SearchRegionMode PixelAlignedBoundingBox needs a pixel
   --  region (ks_cnl_search_execute)"), the rectangle ("SearchRegion.CenterX
   --  must be finite and within 1.0E150", ...), the transforms, the size of
   --  the resampled rectangle ("SearchRegion: the resampled rectangle must
   --  have at most 16777216 pixels"), then the failures of the resampling
   --  (Transform_Singular for a rectangle too flat, Out_Of_Memory) and of
   --  the search (a location beyond 1.0E150, Out_Of_Memory).

end AMV.Kernels.CNL_Search.Region_Modes;
