--  Kernel of AMV.Blob: connected-component analysis of the pixels of a
--  region of an 8-bit image (CogBlob, CogBlobResults, CogBlobResult). The
--  Ada API documents the behaviour for Ada users; this spec is the
--  reference for the C API (include/amv_blob.h).
--
--  A run (ks_blob_execute) takes the image (a pixel handle of
--  AMV.Kernels.Images), the pixels to analyse (a pixel region of
--  AMV.Kernels.Regions; the Ada API passes the whole image for an empty
--  Region holder), the run parameters (Ks_Blob_Run_Params, CogBlob) and
--  the transform Selected_From_Pixel from pixel space to the image's
--  selected space (the Ada API passes Image.Get_Transform (".", "#")). It
--  returns an owned results handle.
--
--  1. Segmentation. Every pixel of the region is foreground or
--     background by the rule Is_Foreground: with the threshold T, a light
--     blob pixel has a grey value >= T and a dark blob pixel a grey value
--     < T (Polarity). T depends on SegmentationParams.Mode:
--     * HardFixedThreshold: HardFixedThreshold (0 .. 65535).
--     * HardRelativeThreshold: the grey levels Low and High of the
--       region's histogram after the darkest TailLow percent and the
--       brightest TailHigh percent of its pixels are set aside (Low is the
--       level of the pixel of rank floor (N TailLow / 100) in increasing
--       order of grey value, High that of rank N - 1 - floor (N TailHigh /
--       100), and High = Low when the tails overlap), then T = Low +
--       ceiling ((High - Low) HardRelativeThreshold / 100).
--     * HardDynamicThreshold: Otsu's threshold on the region's histogram:
--       the T in 1 .. 255 that maximises the between-class variance
--       n0 n1 (m0 - m1)**2 of the classes "< T" (n0 pixels, mean m0) and
--       ">= T" (the smallest such T on ties). When the region holds fewer
--       than two grey levels there is no split and no pixel is foreground
--       (T = 256 for light blobs, T = 0 for dark blobs).
--     * None: the image is segmented already: T = 1, so light blobs are
--       the pixels that are not 0 and dark blobs those that are 0.
--     * SoftFixedThreshold and SoftRelativeThreshold (soft segmentation):
--       every pixel of the region gets a level from 0 to Softness + 1,
--       and weighs level / (Softness + 1) in the measures (see "Soft
--       segmentation" below). The grey band [Low, High) is
--       SoftFixedThresholdLow .. SoftFixedThresholdHigh in the fixed
--       mode; in the relative mode Low = L + ceiling ((H - L)
--       SoftRelativeThresholdLow / 100) and High = L + ceiling ((H - L)
--       SoftRelativeThresholdHigh / 100), with L and H the tail levels
--       of HardRelativeThreshold above (TailLow and TailHigh, the same
--       rounding). The level of a pixel of grey value g is Soft_Level,
--       a rule AMV chose (VisionPro states only that values below the
--       band are background, values from High on full foreground for
--       light blobs, the band split into Softness equal steps of
--       weights strictly between 0 and 1, and the reverse for dark
--       blobs). With S = Softness:
--       - light blobs: 0 for g < Low; S + 1 for g >= High; in the band,
--         1 + floor ((g - Low) S / (High - Low));
--       - dark blobs: S + 1 for g < Low; 0 for g >= High; in the band,
--         S - floor ((g - Low) S / (High - Low));
--       - S = 0: the band is background (level 0) for both polarities;
--       - Low = High (possible in the relative mode): the band is empty
--         and the rule is the hard threshold T = Low.
--       A pixel is foreground when its level is above 0.
--     Map and SubtractionImage are not supported (Bad_Parameter); nor
--     is ScalingValue (CogBlobSegmentationParams has it for None). Then
--     MorphologyOperations are applied to the foreground in order:
--     erosion and dilation with a 3 x 1 (Horizontal), 1 x 3 (Vertical)
--     or 3 x 3 (Square) structuring element, Close = dilation then
--     erosion, Open = erosion then dilation. Only pixels of the region
--     are looked at and changed: a pixel stays foreground under erosion
--     when every pixel of the element that lies in the region is
--     foreground, and becomes foreground under dilation when any of them
--     is. In the soft modes the operations act on the levels (AMV's
--     choice): erosion gives a pixel the smallest level, dilation the
--     largest, among the pixels of the element that lie in the region,
--     which for the two levels of a hard segmentation is the rule above.
--
--  2. Connectivity (ConnectivityMode).
--     * GreyScale: a blob is an 8-connected set of foreground pixels. A
--       hole is a 4-connected set of background pixels of the region that
--       does not touch the outside (no pixel of it lies on the border of
--       the region's bounding rectangle or next to a pixel outside the
--       region). Blobs and holes form a tree: the parent of a hole is the
--       blob around it, the parent of a blob the hole around it (none for
--       a blob in the outer background). The parent of a feature is the
--       feature of the pixel just above its first pixel (first in raster
--       order: smallest y, then smallest x).
--     * Labeled: a blob is an 8-connected set of foreground pixels of
--       equal grey value (its Label); there are no holes.
--     * WholeImageGreyScale: all foreground pixels of the region form one
--       blob (when there is any); there are no holes.
--     Cleanup (ConnectivityCleanup, ConnectivityMinPixels): a feature
--     (blob or hole) with fewer than ConnectivityMinPixels pixels of its
--     own (pixels, not weights, in the soft modes) is removed. Prune: its
--     pixels belong to no feature any more, and the features inside it
--     are removed with it. Fill (GreyScale): its pixels change sides and
--     join its parent (a small hole is filled into its blob, a small blob
--     into its hole; a small blob in the outer background disappears);
--     the features directly inside it, which lie on the parent's side,
--     join the parent too, and the features inside those keep their
--     identity with the parent as their new parent. In the Labeled and
--     WholeImageGreyScale modes Fill removes small blobs as Prune does
--     (there is nothing around them to fill them into).
--
--  3. Results. The features left are numbered in raster order of their
--     first pixel; ID = that number from 0, which is also the index in
--     the unfiltered collection (GetBlobs (False)). Each item
--     (Ks_Blob_Result, a C struct) holds every measure (see the record),
--     in the selected space: positions are mapped by Selected_From_Pixel,
--     areas are multiplied by abs det, the second moments (inertia) are
--     those of the mapped pixel squares (exact for any affine transform),
--     and Angle is the direction of the axis of least inertia in the
--     selected space, in (-Pi/2, Pi/2]. The boxes and the extrema-angle
--     measures are taken along the principal axes, the selected space's
--     axes and the axes at ExtremaAngle (see Ks_Blob_Result); the boxes at
--     any angle and the medians along any axis are computed on demand
--     from the feature map (Get_Bounding_Box_At_Angle, Get_Median_X / Y).
--     Filtering keeps the features whose RunTimeMeasures with Mode =
--     Filter all accept them (Include: the value lies in [FilterRangeLow,
--     FilterRangeHigh]; Exclude: it does not); the filtered collection
--     (GetBlobs ()) lists them in ID order, or sorted by SortMeasure
--     (ascending when SortAscending, ties in ID order) when SortEnabled.
--
--  4. Soft segmentation (AMV's choices where VisionPro states only that
--     area, centre of mass and second moments are weighted and the
--     perimeter is not). The measures of a blob that come from its mass
--     weigh each pixel by level / (Softness + 1):
--     * weighted: Area (the sum of the weights, times abs det),
--       Center_Of_Mass_X / Y (the weighted mean of the pixel centres),
--       the second moments (each pixel square counts with its weight),
--       everything derived from them (Inertia_X, Inertia_Y, Inertia_Min,
--       Inertia_Max, Elongation, Angle, so also the directions of the
--       principal-axis box and of the principal medians), everything
--       built on Area (Acircularity), and filtering and sorting by these;
--     * not weighted (a pixel belongs to a blob when its level is above
--       0): connectivity, the cleanup's pixel counts, Pixel_Count,
--       Perimeter, the extents of every box, the extrema-angle measures,
--       the medians, the boundary, Label, Parent_ID, the children,
--       Not_Clipped and the ID image.
--     The sums add levels (integers) and levels times pixel offsets, and
--     are divided by Softness + 1 once, at the end.
--     A pixel of level 0 that the cleanup gave to a blob (Fill of a
--     small hole) counts with full weight. Holes are measured as in the
--     hard modes: each of their pixels counts fully (they are background,
--     level 0, or belong to a small blob that Fill gave to the hole,
--     whose weight as a blob becomes 0). The hard modes give the same
--     results as before soft segmentation existed (every pixel weighs 1).
--
--  5. Images of the results (CogBlobResults.CreateBlobImage and
--     CreateSegmentedImage). Both are 8-bit images of the input image's
--     size. VisionPro states the outline; the details marked below are
--     AMV's.
--     * The segmented value of a pixel is its level: 0 or 1 for a hard
--       segmentation (1 for foreground), 0 .. Softness + 1 for a soft
--       one; Full is the value of full weight (1, or Softness + 1).
--     * Segmented images (CreateSegmentedImage). The run keeps those of
--       the stages its SaveSegmented* parameters ask for, over the
--       region's bounding rectangle: BeforeMasking, every pixel of that
--       rectangle segmented, whether it lies in the region or not (AMV:
--       the mask is the region's shape within its bounding rectangle;
--       AMV has no InputImageMask); BeforeMorphology, the same with 0
--       outside the region; FinalImage, after the morphology (the
--       classes that connectivity used). The image holds these values (0
--       outside the rectangle) or, stretched, value * 255 / Full
--       (rounded down), so that full weight is 255. A stage that was not
--       saved gives no image (null).
--     * The blob image (CreateBlobImage) paints the features (all, or
--       those that passed the filter) onto a background. Viewable
--       (VisionPro's rule where stated): background 128, hole pixels 0,
--       blob pixels 255 for a hard segmentation, for a soft one 255 at
--       full weight and less by levels within 192 .. 255
--       (Viewable_Level, AMV's spacing), and in Labeled mode the labels
--       spread evenly over 96 .. 255 (Viewable_Label, AMV's spacing).
--       Not viewable: background Background (0 .. 255), hole pixels 0,
--       blob pixels their segmented value, or in Labeled mode their
--       Label (the grey value). A blob pixel of level 0 (one that the
--       cleanup's Fill gave to the blob) counts as full weight, as in the
--       measures.
--
--  Bounds. Selected_From_Pixel must have matrix entries within
--  +/-Max_Scale (2**64, about 1.8E19) and a translation within
--  +/-Max_Translation (1.0E140), so that every position, length, area
--  and moment fits the bounds of AMV.Kernels.Shapes (positions and boxes
--  within +/-1.0E150; areas below 2**161, inertia below 2**360).
--
--  ExtremaAngle and the angle of Get_Bounding_Box_At_Angle must be finite
--  and within +/-Max_Extrema_Angle (1.0E6 radians).
--
--  Trusted parts (SPARK_Mode Off bodies, listed in docs/PROOF.md): the
--  allocation helpers, which turn a failed allocation into Out_Of_Memory.
--  Everything else is proved.

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
with AMV.Kernels.Shapes;
with AMV.Kernels.Transforms;

package AMV.Kernels.Blob with SPARK_Mode, Preelaborate is

   pragma Unevaluated_Use_Of_Old (Allow);

   package KI renames AMV.Kernels.Images;
   package KR renames AMV.Kernels.Regions;
   package KS renames AMV.Kernels.Shapes;
   package KT renames AMV.Kernels.Transforms;

   use type Interfaces.Unsigned_8;
   use type KI.Grey_8_Pixels;
   use type KI.Ks_Image_8_Grey;
   use type KI.Ks_Image_16_Grey;
   use type KS.Ks_Polygon;

   ---------------------------------------------------------------------
   --  Codes (the numeric values of the VisionPro enumerations;
   --  C: KS_BLOB_*)
   ---------------------------------------------------------------------

   --  CogBlobSegmentationModeConstants
   Segmentation_None                    : constant Int32 := 0;
   Segmentation_Map                     : constant Int32 := 1;
   Segmentation_Hard_Fixed_Threshold    : constant Int32 := 2;
   Segmentation_Hard_Relative_Threshold : constant Int32 := 3;
   Segmentation_Hard_Dynamic_Threshold  : constant Int32 := 4;
   Segmentation_Soft_Fixed_Threshold    : constant Int32 := 5;
   Segmentation_Soft_Relative_Threshold : constant Int32 := 6;
   Segmentation_Subtraction_Image       : constant Int32 := 7;

   --  CogBlobSegmentationPolarityConstants
   Polarity_Dark_Blobs  : constant Int32 := 0;
   Polarity_Light_Blobs : constant Int32 := 1;

   --  CogBlobConnectivityModeConstants
   Connectivity_Grey_Scale             : constant Int32 := 0;
   Connectivity_Labeled                : constant Int32 := 1;
   Connectivity_Whole_Image_Grey_Scale : constant Int32 := 2;

   --  CogBlobConnectivityCleanupConstants
   Cleanup_None  : constant Int32 := 0;
   Cleanup_Prune : constant Int32 := 1;
   Cleanup_Fill  : constant Int32 := 2;

   --  CogBlobMeasureConstants (all 43; Measure_Supported tells which ones
   --  this kernel computes)
   Measure_Label                                     : constant Int32 := 0;
   Measure_Area                                      : constant Int32 := 1;
   Measure_Boundary_Pixel_Length                     : constant Int32 := 2;
   Measure_Perimeter                                 : constant Int32 := 3;
   Measure_Num_Unfiltered_Children                   : constant Int32 := 4;
   Measure_Center_Mass_X                             : constant Int32 := 5;
   Measure_Center_Mass_Y                             : constant Int32 := 6;
   Measure_Inertia_X                                 : constant Int32 := 7;
   Measure_Inertia_Y                                 : constant Int32 := 8;
   Measure_Inertia_Min                               : constant Int32 := 9;
   Measure_Inertia_Max                               : constant Int32 := 10;
   Measure_Elongation                                : constant Int32 := 11;
   Measure_Angle                                     : constant Int32 := 12;
   Measure_Acircularity                              : constant Int32 := 13;
   Measure_Acircularity_Rms                          : constant Int32 := 14;
   Measure_Bounding_Box_Pixel_Aligned_No_Exclude_Center_X :
     constant Int32 := 15;
   Measure_Bounding_Box_Pixel_Aligned_No_Exclude_Center_Y :
     constant Int32 := 16;
   Measure_Bounding_Box_Pixel_Aligned_No_Exclude_Min_X : constant Int32 := 17;
   Measure_Bounding_Box_Pixel_Aligned_No_Exclude_Max_X : constant Int32 := 18;
   Measure_Bounding_Box_Pixel_Aligned_No_Exclude_Min_Y : constant Int32 := 19;
   Measure_Bounding_Box_Pixel_Aligned_No_Exclude_Max_Y : constant Int32 := 20;
   Measure_Bounding_Box_Pixel_Aligned_No_Exclude_Width : constant Int32 := 21;
   Measure_Bounding_Box_Pixel_Aligned_No_Exclude_Height :
     constant Int32 := 22;
   Measure_Bounding_Box_Pixel_Aligned_No_Exclude_Aspect :
     constant Int32 := 23;
   Measure_Median_Extrema_Angle_X                    : constant Int32 := 24;
   Measure_Median_Extrema_Angle_Y                    : constant Int32 := 25;
   Measure_Bounding_Box_Extrema_Angle_Center_X       : constant Int32 := 26;
   Measure_Bounding_Box_Extrema_Angle_Center_Y       : constant Int32 := 27;
   Measure_Bounding_Box_Extrema_Angle_Min_X          : constant Int32 := 28;
   Measure_Bounding_Box_Extrema_Angle_Max_X          : constant Int32 := 29;
   Measure_Bounding_Box_Extrema_Angle_Min_Y          : constant Int32 := 30;
   Measure_Bounding_Box_Extrema_Angle_Max_Y          : constant Int32 := 31;
   Measure_Bounding_Box_Extrema_Angle_Width          : constant Int32 := 32;
   Measure_Bounding_Box_Extrema_Angle_Height         : constant Int32 := 33;
   Measure_Bounding_Box_Extrema_Angle_Aspect         : constant Int32 := 34;
   Measure_Bounding_Box_Principal_Axis_Min_X         : constant Int32 := 35;
   Measure_Bounding_Box_Principal_Axis_Max_X         : constant Int32 := 36;
   Measure_Bounding_Box_Principal_Axis_Min_Y         : constant Int32 := 37;
   Measure_Bounding_Box_Principal_Axis_Max_Y         : constant Int32 := 38;
   Measure_Bounding_Box_Principal_Axis_Width         : constant Int32 := 39;
   Measure_Bounding_Box_Principal_Axis_Height        : constant Int32 := 40;
   Measure_Bounding_Box_Principal_Axis_Aspect        : constant Int32 := 41;
   Measure_Not_Clipped                               : constant Int32 := 42;

   function Measure_Supported (Measure : Int32) return Boolean is
     (Measure in Measure_Label .. Measure_Area
                | Measure_Perimeter .. Measure_Acircularity
                | Measure_Bounding_Box_Pixel_Aligned_No_Exclude_Center_X
                  .. Measure_Not_Clipped);
   --  The measures a result holds. BoundaryPixelLength and AcircularityRms
   --  are not computed.

   --  CogBlobMeasureModeConstants
   Measure_Mode_None        : constant Int32 := 0;
   Measure_Mode_Pre_Compute : constant Int32 := 1;
   Measure_Mode_Filter      : constant Int32 := 2;

   --  CogBlobFilterModeConstants
   Filter_Exclude_Blobs_In_Range : constant Int32 := 0;
   Filter_Include_Blobs_In_Range : constant Int32 := 1;

   --  CogBlobAxisConstants
   Axis_Principal                : constant Int32 := 0;
   Axis_Selected_Space           : constant Int32 := 1;
   Axis_Extrema_Angle            : constant Int32 := 2;
   Axis_Pixel_Aligned            : constant Int32 := 3;
   Axis_Pixel_Aligned_No_Exclude : constant Int32 := 4;

   --  CogBlobMorphologyConstants
   Morphology_Erode_Horizontal  : constant Int32 := 0;
   Morphology_Erode_Vertical    : constant Int32 := 1;
   Morphology_Erode_Square      : constant Int32 := 2;
   Morphology_Dilate_Horizontal : constant Int32 := 3;
   Morphology_Dilate_Vertical   : constant Int32 := 4;
   Morphology_Dilate_Square     : constant Int32 := 5;
   Morphology_Close_Horizontal  : constant Int32 := 6;
   Morphology_Close_Vertical    : constant Int32 := 7;
   Morphology_Close_Square      : constant Int32 := 8;
   Morphology_Open_Horizontal   : constant Int32 := 9;
   Morphology_Open_Vertical     : constant Int32 := 10;
   Morphology_Open_Square       : constant Int32 := 11;

   --  CogBlobLabelConstants (the Label of a feature in GreyScale mode)
   Label_Hole : constant Int32 := 0;
   Label_Blob : constant Int32 := 1;

   --  CogBlobSegmentedImageConstants (the stage of a saved segmented
   --  image, Create_Segmented_Image)
   Segmented_Final_Image       : constant Int32 := 0;
   Segmented_Before_Morphology : constant Int32 := 1;
   Segmented_Before_Masking    : constant Int32 := 2;

   ---------------------------------------------------------------------
   --  Limits (C: KS_BLOB_*)
   ---------------------------------------------------------------------

   Max_Run_Time_Measures     : constant := 64;
   Max_Morphology_Operations : constant := 32;
   Max_Fixed_Threshold       : constant := 65_535;
   Max_Softness              : constant := 254;
   --  SoftFixedThresholdLow lies in 0 .. Max_Fixed_Threshold - 1,
   --  SoftFixedThresholdHigh in 1 .. Max_Fixed_Threshold, Softness in
   --  0 .. Max_Softness (so a level, 0 .. Softness + 1, fits a byte).

   Max_Scale       : constant := 2.0 ** 64;
   Max_Translation : constant := 1.0E140;
   --  The bounds of Selected_From_Pixel (see "Bounds" above).

   Max_Region_Pixels : constant := 2**31 - 3;
   --  The largest number of pixels in the bounding rectangle of the
   --  region (one label per pixel and two more must fit an Int32); a
   --  larger region fails with Out_Of_Memory (no machine could hold its
   --  label tables anyway).

   Max_ID_Image_Blobs : constant := 65_535;
   --  The most features Create_Blob_ID_Image can number (16-bit pixels).

   Max_Extrema_Angle : constant := 1.0E6;
   --  The bound of ExtremaAngle and of the angle of
   --  Get_Bounding_Box_At_Angle (radians): far beyond any useful angle,
   --  and small enough that its cosine and sine keep their accuracy.

   ---------------------------------------------------------------------
   --  Run parameters (CogBlob; C: ks_blob_run_params)
   ---------------------------------------------------------------------

   type Ks_Blob_Segmentation_Params is record
      Mode                    : Int32 := Segmentation_Hard_Dynamic_Threshold;
      Polarity                : Int32 := Polarity_Dark_Blobs;
      Hard_Fixed_Threshold    : Int32 := 128;
      Hard_Relative_Threshold : Int32 := 50;
      Tail_Low                : Int32 := 0;
      Tail_High               : Int32 := 0;
      Soft_Fixed_Threshold_Low     : Int32 := 102;
      Soft_Fixed_Threshold_High    : Int32 := 153;
      Soft_Relative_Threshold_Low  : Int32 := 40;
      Soft_Relative_Threshold_High : Int32 := 60;
      Softness                     : Int32 := 254;
   end record
     with Convention => C;
   --  CogBlobSegmentationParams (C: ks_blob_segmentation_params). The
   --  defaults are VisionPro's, except those of SoftFixedThresholdLow and
   --  SoftFixedThresholdHigh, which VisionPro does not state: AMV's 102
   --  and 153 are the relative defaults (40 and 60 percent) placed on the
   --  whole grey range 0 .. 255 with the relative mode's rounding. Every
   --  field must be valid whatever the mode (as for the hard fields):
   --  Hard_Fixed_Threshold 0 .. 65535; Hard_Relative_Threshold, Tail_Low,
   --  Tail_High, Soft_Relative_Threshold_Low and _High 0 .. 100, the low
   --  soft relative threshold at most the high one;
   --  Soft_Fixed_Threshold_Low 0 .. 65534 below Soft_Fixed_Threshold_High
   --  1 .. 65535; Softness 0 .. 254.

   type Ks_Blob_Measure is record
      Measure           : Int32 := Measure_Area;
      Mode              : Int32 := Measure_Mode_Pre_Compute;
      Filter_Mode       : Int32 := Filter_Include_Blobs_In_Range;
      Filter_Range_Low  : Long_Float := 0.0;
      Filter_Range_High : Long_Float := 0.0;
   end record
     with Convention => C;
   --  CogBlobMeasure (C: ks_blob_measure).

   type Ks_Blob_Measure_Array is
     array (0 .. Max_Run_Time_Measures - 1) of Ks_Blob_Measure
     with Convention => C;

   type Ks_Blob_Measure_Collection is record
      Count : Int32 := 0;
      Items : Ks_Blob_Measure_Array;
   end record
     with Convention => C;
   --  CogBlobMeasureCollection: Items (0 .. Count - 1).

   type Ks_Blob_Morphology_Array is
     array (0 .. Max_Morphology_Operations - 1) of Int32
     with Convention => C;

   type Ks_Blob_Morphology_Collection is record
      Count : Int32 := 0;
      Items : Ks_Blob_Morphology_Array := [others => 0];
   end record
     with Convention => C;
   --  CogBlobMorphologyCollection: Items (0 .. Count - 1), codes of
   --  CogBlobMorphologyConstants.

   type Ks_Blob_Run_Params is record
      Segmentation_Params     : Ks_Blob_Segmentation_Params;
      Connectivity_Mode       : Int32 := Connectivity_Grey_Scale;
      Connectivity_Cleanup    : Int32 := Cleanup_Fill;
      Connectivity_Min_Pixels : Int32 := 10;
      Sort_Enabled            : Int32 := True_Value;
      Sort_Measure            : Int32 := Measure_Area;
      Sort_Ascending          : Int32 := False_Value;
      Run_Time_Measures       : Ks_Blob_Measure_Collection;
      Morphology_Operations   : Ks_Blob_Morphology_Collection;
      Extrema_Angle           : Long_Float := 0.0;
      Save_Segmented_Image                   : Int32 := False_Value;
      Save_Segmented_Image_Before_Masking    : Int32 := False_Value;
      Save_Segmented_Image_Before_Morphology : Int32 := False_Value;
   end record
     with Convention => C;
   --  CogBlob (C: ks_blob_run_params), with VisionPro's defaults.
   --  Extrema_Angle (ExtremaAngle, radians, finite and within
   --  +/-Max_Extrema_Angle) is the direction, in the selected space, of
   --  the axes of the extrema-angle measures (see Ks_Blob_Result).
   --  SaveSegmentedImage, SaveSegmentedImageBeforeMasking and
   --  SaveSegmentedImageBeforeMorphology (0 or 1, default 0) keep the
   --  segmented images of the three stages in the results for
   --  Create_Segmented_Image (see "Images of the results" above).

   ---------------------------------------------------------------------
   --  Results
   ---------------------------------------------------------------------

   type Ks_Blob_Result is record
      ID                      : Int32 := 0;
      Label                   : Int32 := 0;
      Parent_ID               : Int32 := -1;
      Num_Children            : Int32 := 0;
      Num_Unfiltered_Children : Int32 := 0;
      Filtered_Out            : Int32 := 0;
      Not_Clipped             : Int32 := 0;
      Pixel_Count             : Int32 := 0;

      Area             : Long_Float := 0.0;
      Center_Of_Mass_X : Long_Float := 0.0;
      Center_Of_Mass_Y : Long_Float := 0.0;
      Angle            : Long_Float := 0.0;
      Perimeter        : Long_Float := 0.0;
      Inertia_X        : Long_Float := 0.0;
      Inertia_Y        : Long_Float := 0.0;
      Inertia_Min      : Long_Float := 0.0;
      Inertia_Max      : Long_Float := 0.0;
      Elongation       : Long_Float := 0.0;
      Acircularity     : Long_Float := 0.0;

      Pixel_Aligned_Center_X : Long_Float := 0.0;
      Pixel_Aligned_Center_Y : Long_Float := 0.0;
      Pixel_Aligned_Min_X    : Long_Float := 0.0;
      Pixel_Aligned_Max_X    : Long_Float := 0.0;
      Pixel_Aligned_Min_Y    : Long_Float := 0.0;
      Pixel_Aligned_Max_Y    : Long_Float := 0.0;
      Pixel_Aligned_Width    : Long_Float := 0.0;
      Pixel_Aligned_Height   : Long_Float := 0.0;
      Pixel_Aligned_Aspect   : Long_Float := 0.0;

      Principal_Axis_Min_X  : Long_Float := 0.0;
      Principal_Axis_Max_X  : Long_Float := 0.0;
      Principal_Axis_Min_Y  : Long_Float := 0.0;
      Principal_Axis_Max_Y  : Long_Float := 0.0;
      Principal_Axis_Width  : Long_Float := 0.0;
      Principal_Axis_Height : Long_Float := 0.0;
      Principal_Axis_Aspect : Long_Float := 0.0;

      Pixel_Aligned_Box  : KS.Ks_Rectangle_Affine;
      Principal_Axis_Box : KS.Ks_Rectangle_Affine;
      Selected_Space_Box : KS.Ks_Rectangle_Affine;

      Extrema_Angle_Center_X : Long_Float := 0.0;
      Extrema_Angle_Center_Y : Long_Float := 0.0;
      Extrema_Angle_Min_X    : Long_Float := 0.0;
      Extrema_Angle_Max_X    : Long_Float := 0.0;
      Extrema_Angle_Min_Y    : Long_Float := 0.0;
      Extrema_Angle_Max_Y    : Long_Float := 0.0;
      Extrema_Angle_Width    : Long_Float := 0.0;
      Extrema_Angle_Height   : Long_Float := 0.0;
      Extrema_Angle_Aspect   : Long_Float := 0.0;
      Median_Extrema_Angle_X : Long_Float := 0.0;
      Median_Extrema_Angle_Y : Long_Float := 0.0;
      Extrema_Angle_Box      : KS.Ks_Rectangle_Affine;
   end record
     with Convention => C;
   --  CogBlobResult (C: ks_blob_result), in the selected space:
   --
   --  * ID: the feature's number (see "Results"); Label: GreyScale 1 for a
   --    blob and 0 for a hole (CogBlobLabelConstants), Labeled the grey
   --    value, WholeImageGreyScale 1; Parent_ID the ID of the parent, -1
   --    for none (CogBlobResults.GetParent); Num_Children the number of
   --    children that passed the filter, Num_Unfiltered_Children of all
   --    children; Filtered_Out 1 when the feature did not pass the
   --    filter; Not_Clipped 1 when no pixel of the feature is next to a
   --    pixel outside the region or the image (4-neighbours); Pixel_Count
   --    the number of its pixels.
   --  * Area: Pixel_Count * abs det (Selected_From_Pixel); for a blob of
   --    a soft segmentation, the sum of its pixels' weights * abs det.
   --  * Center_Of_Mass_X/Y: the mapped centroid of the pixel centres
   --    (weighted for a blob of a soft segmentation, as the moments).
   --  * Inertia_X / Inertia_Y: the second moments of the mapped pixel
   --    squares about the lines through the centre of mass parallel to
   --    the x and y axes; Inertia_Min / Inertia_Max: about the principal
   --    axes; Elongation = Inertia_Max / Inertia_Min; Angle: the
   --    direction of the axis of Inertia_Min, in (-Pi/2, Pi/2].
   --  * Perimeter: the length of the boundary of the feature's pixels
   --    (holes' boundaries included) traced through the midpoints of the
   --    pixel edges (marching squares: a corner of a 2 x 2 cell is cut by
   --    a diagonal of length Sqrt (2) / 2, a straight edge counts 1;
   --    diagonal neighbours of a blob are joined, those of a hole are
   --    not), each segment mapped by the transform.
   --    Acircularity = Perimeter**2 / (4 Pi Area).
   --  * Pixel_Aligned_*: the bounds, centre, size and Height / Width of
   --    Pixel_Aligned_Box, the box around the pixel squares of the feature
   --    in pixel space (from X_Min - 0.5 to X_Max + 0.5 and likewise in y)
   --    mapped into the selected space (CogBlobAxisConstants.PixelAligned
   --    and PixelAlignedNoExclude; the measures
   --    BoundingBoxPixelAlignedNoExclude*).
   --  * Principal_Axis_Box: the smallest rectangle along the principal
   --    axes (Angle and Angle + Pi/2) around the mapped pixel squares;
   --    Principal_Axis_Min_X .. Max_X and Min_Y .. Max_Y its extent along
   --    those axes measured from the centre of mass, Width, Height and
   --    Aspect = Height / Width (BoundingBoxPrincipalAxis*).
   --  * Selected_Space_Box: the same along the axes of the selected space
   --    (CogBlobAxisConstants.SelectedSpace).
   --  * Extrema_Angle_Box: the same along the axes at ExtremaAngle (the
   --    run parameter Extrema_Angle, E below): the direction (cos E,
   --    sin E) of the selected space and the direction E + Pi/2; its
   --    Rotation is E as given (CogBlobAxisConstants.ExtremaAngle). The
   --    extrema-angle measures are coordinates in the frame of the
   --    selected space turned by E about its origin, where a point (x, y)
   --    has the coordinates u = x cos E + y sin E and v = -x sin E +
   --    y cos E: Extrema_Angle_Min_X .. Max_X and Min_Y .. Max_Y the
   --    extent of the box in u and v (unlike the principal-axis measures,
   --    which are measured from the centre of mass, these are positions:
   --    at E = 0 they are the bounds of Selected_Space_Box in the selected
   --    space); Center_X / Center_Y the box's centre in u and v, Width and
   --    Height its sides, Aspect = Height / Width
   --    (BoundingBoxExtremaAngle*); Median_Extrema_Angle_X / Y the medians
   --    of u and v over the mapped pixel centres of the feature
   --    (MedianExtremaAngleX / Y), the middle value of the sorted
   --    coordinates for an odd number of pixels and the mean of the two
   --    middle ones for an even number, selected exactly from the
   --    computed coordinates. Min_X <= Median_Extrema_Angle_X <= Max_X and
   --    Min_Y <= Median_Extrema_Angle_Y <= Max_Y (proved).
   --
   --  A ratio whose divisor is 0 (Aspect of a degenerate box, Elongation
   --  or Acircularity under a singular transform) is reported as 0.

   type Result_Array is array (Natural range <>) of Ks_Blob_Result;
   type Result_Array_Access is access Result_Array;

   type Int32_Matrix is array (Natural range <>, Natural range <>) of Int32
     with Default_Component_Value => 0;
   type Int32_Matrix_Access is access Int32_Matrix;
   --  Indexed (Y, X) by pixel coordinates, as the flags of a pixel region.

   type Int32_Array is array (Natural range <>) of Int32
     with Default_Component_Value => 0;
   type Int32_Array_Access is access Int32_Array;

   type Real_Array is array (Natural range <>) of Long_Float
     with Default_Component_Value => 0.0;
   type Real_Array_Access is access Real_Array;

   type U8_Matrix is
     array (Natural range <>, Natural range <>) of Interfaces.Unsigned_8
     with Default_Component_Value => 0;
   type U8_Matrix_Access is access U8_Matrix;
   --  Indexed (Y, X) by pixel coordinates: the segmentation and the
   --  levels of the region's bounding rectangle.

   type Ks_Blob_Results_Data is limited record
      Image_Width    : Int32 := 0;
      Image_Height   : Int32 := 0;
      Transform      : KT.Ks_Transform_2D_Linear;
      Count          : Int32 := 0;
      Items          : Result_Array_Access;
      First_X        : Int32_Array_Access;
      First_Y        : Int32_Array_Access;
      Kinds          : Int32_Array_Access;
      Map            : Int32_Matrix_Access;
      Filtered_Count : Int32 := 0;
      Order          : Int32_Array_Access;
      Centroid_X     : Real_Array_Access;
      Centroid_Y     : Real_Array_Access;
      Connectivity   : Int32 := Connectivity_Grey_Scale;
      Full           : Int32 := 1;
      Levels         : U8_Matrix_Access;
      Before_Morphology : U8_Matrix_Access;
      Before_Masking    : U8_Matrix_Access;
      Saved_Final             : Int32 := False_Value;
      Saved_Before_Morphology : Int32 := False_Value;
      Saved_Before_Masking    : Int32 := False_Value;
   end record;
   --  What a results handle designates (opaque for C): the size of the
   --  image; Selected_From_Pixel; Count features with their items, first
   --  pixels and kinds (Label_Blob or Label_Hole, which tells how they are
   --  connected); the feature map Map (Y, X) = ID + 1 of the feature that
   --  owns pixel (X, Y), 0 for none, over the region's bounding rectangle
   --  (null when there is no feature); the filtered collection as the IDs
   --  Order (0 .. Filtered_Count - 1); the centres of mass of the
   --  features in pixel space, Centroid_X / Centroid_Y (0 .. Count - 1),
   --  from which the boxes and medians on demand measure their pixels.
   --  For the images of the results: the run's ConnectivityMode
   --  (Connectivity); the level of a pixel of full weight (Full: 1, or
   --  Softness + 1 for a soft segmentation); the segmented values (the
   --  levels, 0 .. Full) after the morphology (Levels: kept for a soft
   --  segmentation and when SaveSegmentedImage, else null), before it
   --  (Before_Morphology) and before the region's mask (Before_Masking),
   --  each over the region's bounding rectangle and null when not saved
   --  or when the region is empty; and which stages were asked to be
   --  saved (Saved_*).

   type Ks_Blob_Results is access Ks_Blob_Results_Data
     with Convention => C;
   --  C: ks_blob_results *. A null handle has no features.

   function Valid_Results
     (Results : access constant Ks_Blob_Results_Data) return Boolean
   is
     (Results /= null
      and then Results.Image_Width >= 0 and then Results.Image_Height >= 0
      and then Results.Count >= 0
      and then Results.Filtered_Count in 0 .. Results.Count
      and then
        (if Results.Count = 0
         then Results.Items = null and then Results.First_X = null
              and then Results.First_Y = null and then Results.Kinds = null
         else Results.Items /= null and then Results.First_X /= null
              and then Results.First_Y /= null and then Results.Kinds /= null
              and then Results.Items'First = 0
              and then Results.Items'Last = Integer (Results.Count) - 1
              and then Results.First_X'First = 0
              and then Results.First_X'Last = Integer (Results.Count) - 1
              and then Results.First_Y'First = 0
              and then Results.First_Y'Last = Integer (Results.Count) - 1
              and then Results.Kinds'First = 0
              and then Results.Kinds'Last = Integer (Results.Count) - 1)
      and then
        (if Results.Count = 0
         then Results.Centroid_X = null and then Results.Centroid_Y = null
         else Results.Centroid_X /= null and then Results.Centroid_Y /= null
              and then Results.Centroid_X'First = 0
              and then Results.Centroid_X'Last = Integer (Results.Count) - 1
              and then Results.Centroid_Y'First = 0
              and then Results.Centroid_Y'Last
                         = Integer (Results.Count) - 1)
      and then
        (if Results.Filtered_Count = 0 then Results.Order = null
         else Results.Order /= null and then Results.Order'First = 0
              and then Results.Order'Last
                         = Integer (Results.Filtered_Count) - 1)
      and then (if Results.Count > 0 then Results.Map /= null)
      and then
        (if Results.Map /= null
         then Results.Map'First (1) <= Results.Map'Last (1)
              and then Results.Map'First (2) <= Results.Map'Last (2)
              and then Results.Map'Last (1) < Integer (Results.Image_Height)
              and then Results.Map'Last (2) < Integer (Results.Image_Width)));
   --  The structure a handle from Execute has (checked by every entry
   --  point that reads one).

   function Level_Matrix_In_Image
     (M             : access constant U8_Matrix;
      Width, Height : Int32) return Boolean
   is
     (M = null
      or else (M'First (1) <= M'Last (1) and then M'First (2) <= M'Last (2)
               and then M'Last (1) < Integer (Height)
               and then M'Last (2) < Integer (Width)));

   function Valid_Saved
     (Results : access constant Ks_Blob_Results_Data) return Boolean
   is
     (Results /= null
      and then Results.Connectivity
                 in Connectivity_Grey_Scale | Connectivity_Labeled
                  | Connectivity_Whole_Image_Grey_Scale
      and then Results.Full in 1 .. Max_Softness + 1
      and then Results.Saved_Final in False_Value | True_Value
      and then Results.Saved_Before_Morphology in False_Value | True_Value
      and then Results.Saved_Before_Masking in False_Value | True_Value
      and then Level_Matrix_In_Image
                 (Results.Levels, Results.Image_Width, Results.Image_Height)
      and then Level_Matrix_In_Image
                 (Results.Before_Morphology, Results.Image_Width,
                  Results.Image_Height)
      and then Level_Matrix_In_Image
                 (Results.Before_Masking, Results.Image_Width,
                  Results.Image_Height));
   --  The structure of the parts of a handle from Execute that the images
   --  of the results read (checked by Create_Blob_Image and
   --  Create_Segmented_Image).

   function In_Order
     (Ascending : Boolean; Left, Right : Long_Float) return Boolean
   is
     (if Ascending then Left <= Right else Left >= Right);

   function Measure_Value
     (Result : Ks_Blob_Result; Measure : Int32) return Long_Float;
   --  The value of a supported measure (see the record); 0.0 for any
   --  other code.

   function Item_Value
     (Results : access constant Ks_Blob_Results_Data;
      ID      : Int32;
      Measure : Int32) return Long_Float
   is
     (if Results /= null and then Results.Items /= null
         and then Integer (ID) in Results.Items'Range
      then Measure_Value (Results.Items (Integer (ID)), Measure)
      else 0.0);

   function Sorted
     (Results : access constant Ks_Blob_Results_Data;
      Params  : Ks_Blob_Run_Params) return Boolean
   is
     (Params.Sort_Enabled /= True_Value
      or else
        (Valid_Results (Results)
         and then
           (for all J in 0 .. Results.Filtered_Count - 2 =>
              In_Order (Params.Sort_Ascending = True_Value,
                        Item_Value (Results, Results.Order (Integer (J)),
                                    Params.Sort_Measure),
                        Item_Value (Results, Results.Order (Integer (J + 1)),
                                    Params.Sort_Measure)))));
   --  Gold: with SortEnabled, the filtered collection is in the order of
   --  SortMeasure (ascending or descending).

   ---------------------------------------------------------------------
   --  Entry points
   ---------------------------------------------------------------------

   procedure Run_Params_Default
     (Params : out Ks_Blob_Run_Params;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_blob_run_params_default",
     Post => Valid (Status) and then Succeeded (Status);
   --  The default run parameters (VisionPro's): HardDynamicThreshold,
   --  DarkBlobs, HardFixedThreshold 128, HardRelativeThreshold 50, no
   --  tails, SoftFixedThresholdLow 102 and High 153 (AMV's),
   --  SoftRelativeThresholdLow 40 and High 60, Softness 254, GreyScale,
   --  Fill, ConnectivityMinPixels 10, sorted by Area descending, no
   --  run-time measures, no morphology.

   function Valid_Polarity (Polarity : Int32) return Boolean is
     (Polarity in Polarity_Dark_Blobs | Polarity_Light_Blobs);

   --  The setters of CogBlobSegmentationParams. Each checks its
   --  arguments, then sets Mode and the fields it names (the others keep
   --  their values); on a failure (Bad_Parameter, which stands for
   --  VisionPro's ArgumentException; the message names the argument)
   --  Params is unchanged. Polarity must be a code of
   --  CogBlobSegmentationPolarityConstants and every percentage in
   --  0 .. 100.

   procedure Set_Hard_Fixed_Threshold
     (Params    : in out Ks_Blob_Segmentation_Params;
      Threshold : Int32;
      Polarity  : Int32;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name =>
       "ks_blob_segmentation_params_set_hard_fixed_threshold",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then
               (if Succeeded (Status)
                then Threshold in 0 .. Max_Fixed_Threshold
                     and then Valid_Polarity (Polarity)
                     and then Params
                                = (Params'Old with delta
                                     Mode =>
                                       Segmentation_Hard_Fixed_Threshold,
                                     Hard_Fixed_Threshold => Threshold,
                                     Polarity => Polarity)
                else Params = Params'Old);
   --  SetSegmentationHardFixedThreshold (hardFixedThreshold, polarity):
   --  Threshold in 0 .. 65535.

   procedure Set_Hard_Relative_Threshold
     (Params              : in out Ks_Blob_Segmentation_Params;
      Tail_Low, Tail_High : Int32;
      Threshold           : Int32;
      Polarity            : Int32;
      Status              : out Ks_Status)
   with
     Export, Convention => C,
     External_Name =>
       "ks_blob_segmentation_params_set_hard_relative_threshold",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then
               (if Succeeded (Status)
                then Tail_Low in 0 .. 100 and then Tail_High in 0 .. 100
                     and then Tail_Low + Tail_High <= 100
                     and then Threshold in 0 .. 100
                     and then Valid_Polarity (Polarity)
                     and then Params
                                = (Params'Old with delta
                                     Mode =>
                                       Segmentation_Hard_Relative_Threshold,
                                     Tail_Low => Tail_Low,
                                     Tail_High => Tail_High,
                                     Hard_Relative_Threshold => Threshold,
                                     Polarity => Polarity)
                else Params = Params'Old);
   --  SetSegmentationHardRelativeThreshold (tailLow, tailHigh,
   --  hardRelativeThreshold, polarity): the tails may not add up to more
   --  than 100.

   procedure Set_Hard_Dynamic_Threshold
     (Params              : in out Ks_Blob_Segmentation_Params;
      Tail_Low, Tail_High : Int32;
      Polarity            : Int32;
      Status              : out Ks_Status)
   with
     Export, Convention => C,
     External_Name =>
       "ks_blob_segmentation_params_set_hard_dynamic_threshold",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then
               (if Succeeded (Status)
                then Tail_Low in 0 .. 100 and then Tail_High in 0 .. 100
                     and then Tail_Low + Tail_High <= 100
                     and then Valid_Polarity (Polarity)
                     and then Params
                                = (Params'Old with delta
                                     Mode =>
                                       Segmentation_Hard_Dynamic_Threshold,
                                     Tail_Low => Tail_Low,
                                     Tail_High => Tail_High,
                                     Polarity => Polarity)
                else Params = Params'Old);
   --  SetSegmentationHardDynamicThreshold (tailLow, tailHigh, polarity).
   --  (AMV's dynamic threshold, Otsu's, takes the whole histogram: it
   --  does not use the tails it sets.)

   procedure Set_Soft_Fixed_Threshold
     (Params    : in out Ks_Blob_Segmentation_Params;
      Low, High : Int32;
      Softness  : Int32;
      Polarity  : Int32;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name =>
       "ks_blob_segmentation_params_set_soft_fixed_threshold",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then
               (if Succeeded (Status)
                then Low in 0 .. Max_Fixed_Threshold - 1
                     and then High in 1 .. Max_Fixed_Threshold
                     and then Low < High
                     and then Softness in 0 .. Max_Softness
                     and then Valid_Polarity (Polarity)
                     and then Params
                                = (Params'Old with delta
                                     Mode =>
                                       Segmentation_Soft_Fixed_Threshold,
                                     Soft_Fixed_Threshold_Low => Low,
                                     Soft_Fixed_Threshold_High => High,
                                     Softness => Softness,
                                     Polarity => Polarity)
                else Params = Params'Old);
   --  SetSegmentationSoftFixedThreshold (softFixedThresholdLow,
   --  softFixedThresholdHigh, softness, polarity): Low in 0 .. 65534,
   --  High in 1 .. 65535, Low < High, Softness in 0 .. 254.

   procedure Set_Soft_Relative_Threshold
     (Params              : in out Ks_Blob_Segmentation_Params;
      Tail_Low, Tail_High : Int32;
      Low, High           : Int32;
      Softness            : Int32;
      Polarity            : Int32;
      Status              : out Ks_Status)
   with
     Export, Convention => C,
     External_Name =>
       "ks_blob_segmentation_params_set_soft_relative_threshold",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then
               (if Succeeded (Status)
                then Tail_Low in 0 .. 100 and then Tail_High in 0 .. 100
                     and then Tail_Low + Tail_High <= 100
                     and then Low in 0 .. 100 and then High in 0 .. 100
                     and then Low <= High
                     and then Softness in 0 .. Max_Softness
                     and then Valid_Polarity (Polarity)
                     and then Params
                                = (Params'Old with delta
                                     Mode =>
                                       Segmentation_Soft_Relative_Threshold,
                                     Tail_Low => Tail_Low,
                                     Tail_High => Tail_High,
                                     Soft_Relative_Threshold_Low => Low,
                                     Soft_Relative_Threshold_High => High,
                                     Softness => Softness,
                                     Polarity => Polarity)
                else Params = Params'Old);
   --  SetSegmentationSoftRelativeThreshold (tailLow, tailHigh,
   --  softRelativeThresholdLow, softRelativeThresholdHigh, softness,
   --  polarity): the tails add up to at most 100, Low <= High, Softness
   --  in 0 .. 254.

   procedure Add_Measure
     (Collection : in out Ks_Blob_Measure_Collection;
      Measure    : Ks_Blob_Measure;
      Status     : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_blob_measure_collection_add",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Collection.Count = Collection.Count'Old + 1
                       else Collection = Collection'Old);
   --  Appends Measure (copied as it is; Execute checks it).
   --  Bad_Parameter when Count is not in 0 .. Max_Run_Time_Measures - 1.

   procedure Add_Morphology
     (Collection : in out Ks_Blob_Morphology_Collection;
      Operation  : Int32;
      Status     : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_blob_morphology_collection_add",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Collection.Count = Collection.Count'Old + 1
                       else Collection = Collection'Old);
   --  Appends Operation (a code of CogBlobMorphologyConstants, checked).
   --  Bad_Parameter for another code or a full collection.

   procedure Execute
     (Image               : access constant KI.Ks_Image_8_Grey_Data;
      Region              : access constant KR.Ks_Pixel_Region_Data;
      Params              : Ks_Blob_Run_Params;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Results             : out Ks_Blob_Results;
      Status              : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_blob_execute",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Valid_Results (Results)
                            and then Valid_Saved (Results)
                            and then Sorted (Results, Params)
                       else Results = null);
   --  CogBlob.Execute: runs the analysis described above. Region null is
   --  the empty region: no features. Failures, in this order:
   --  Image_No_Pixels for a null image ("InputImage has no pixels");
   --  Bad_Parameter for an inconsistent image handle, run parameters that
   --  are not valid (the message names the property, for example
   --  "RunParams.ConnectivityMinPixels must be >= 0"), a transform
   --  outside its bounds, or a region that is not valid or does not lie in
   --  the image; Out_Of_Memory.

   procedure Destroy
     (Results : in out Ks_Blob_Results;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_blob_results_destroy",
     Post => Valid (Status) and then Succeeded (Status)
             and then Results = null;
   --  Frees the results and sets Results to null. Nothing for null.

   procedure Count
     (Results  : access constant Ks_Blob_Results_Data;
      Filtered : Int32;
      Result   : out Int32;
      Status   : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_blob_results_count",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status) and then Results /= null
                       then Valid_Results (Results)
                            and then Result
                                       = (if Filtered = True_Value
                                          then Results.Filtered_Count
                                          else Results.Count)
                       else Result = 0);
   --  GetBlobs (Filtered).Count: the number of features that passed the
   --  filter (Filtered = 1) or of all of them (0). 0 for null.

   procedure Item
     (Results  : access constant Ks_Blob_Results_Data;
      Filtered : Int32;
      Index    : Int32;
      Result   : out Ks_Blob_Result;
      Status   : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_blob_results_item",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range;
   --  GetBlobs (Filtered).Item (Index), 0-based: the filtered collection
   --  in its order (Filtered = 1) or every feature in ID order (0).
   --  Index_Out_Of_Range outside 0 .. Count - 1 (always for null).

   procedure Get_Blob_By_ID
     (Results : access constant Ks_Blob_Results_Data;
      ID      : Int32;
      Result  : out Ks_Blob_Result;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_blob_results_get_blob_by_id",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter;
   --  GetBlobByID: the feature with this ID, filtered or not.
   --  Bad_Parameter for an ID that no feature has.

   procedure Get_Parent
     (Results   : access constant Ks_Blob_Results_Data;
      ID        : Int32;
      Parent_ID : out Int32;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_blob_results_get_parent",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status) then Parent_ID >= -1);
   --  GetParent: the ID of the parent of feature ID, -1 when it has none.
   --  Bad_Parameter for an ID that no feature has.

   procedure Get_Measure
     (Result  : Ks_Blob_Result;
      Measure : Int32;
      Value   : out Long_Float;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_blob_result_get_measure",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Measure_Supported (Measure)
                            and then Value = Measure_Value (Result, Measure)
                       else Value = 0.0);
   --  CogBlobResult.GetMeasure: the value of a supported measure, exactly
   --  as stored in Result. Bad_Parameter for another code.

   procedure Get_Bounding_Box
     (Result : Ks_Blob_Result;
      Axis   : Int32;
      Box    : out KS.Ks_Rectangle_Affine;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_blob_result_get_bounding_box",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter;
   --  CogBlobResult.GetBoundingBox: Principal_Axis_Box, Selected_Space_Box,
   --  Extrema_Angle_Box or Pixel_Aligned_Box (for PixelAligned and
   --  PixelAlignedNoExclude). Bad_Parameter for another code.

   procedure Get_Boundary
     (Results  : access constant Ks_Blob_Results_Data;
      ID       : Int32;
      Boundary : out KS.Ks_Polygon;
      Status   : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_blob_results_get_boundary",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then KS.Valid_Polygon (Boundary)
                       else Boundary = null);
   --  CogBlobResult.GetBoundary: a new polygon, the outer boundary of the
   --  feature's pixels traced along the pixel edges (a vertex at each
   --  corner where the boundary turns, in pixel space at (X +/- 0.5,
   --  Y +/- 0.5)), mapped into the selected space. The pixels are
   --  followed with the feature's connectivity (8 for a blob, 4 for a
   --  hole). Bad_Parameter for an ID that no feature has or a boundary of
   --  more than AMV.Kernels.Shapes.Max_Vertices vertices; Out_Of_Memory.

   procedure Get_Bounding_Box_At_Angle
     (Results : access constant Ks_Blob_Results_Data;
      ID      : Int32;
      Angle   : Long_Float;
      Box     : out KS.Ks_Rectangle_Affine;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_blob_results_get_bounding_box_at_angle",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then KS.Valid_Rectangle_Affine (Box));
   --  CogBlobResult.GetBoundingBoxAtAngle (on the results, since a result
   --  record holds no pixels): the smallest rectangle around the mapped
   --  pixel squares of feature ID whose sides run along the axes at Angle
   --  in the selected space (the directions (cos Angle, sin Angle) and
   --  Angle + Pi/2), with Rotation = Angle as given and Skew 0, computed
   --  from the feature map. At Angle = ExtremaAngle it is
   --  Extrema_Angle_Box, at Angle = 0 Selected_Space_Box and at the
   --  principal angle Principal_Axis_Box (the same arithmetic). Gold: the
   --  extents it is built from contain the projection of every pixel
   --  centre of the feature. Bad_Parameter for an ID that no feature has
   --  or an Angle that is not finite or exceeds Max_Extrema_Angle.

   procedure Get_Median_X
     (Results : access constant Ks_Blob_Results_Data;
      ID      : Int32;
      Axis    : Int32;
      Median  : out Long_Float;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_blob_results_get_median_x",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory;
   --  CogBlobResult.GetMedianX (on the results): the median of the first
   --  coordinates of the mapped pixel centres of feature ID in the frame
   --  of the measures of GetBoundingBox (Axis) (the middle value of the
   --  sorted coordinates, the mean of the two middle ones for an even
   --  number of pixels, selected exactly from the computed coordinates,
   --  without a sort). The frames: Principal, along the principal axes
   --  measured from the centre of mass (as Principal_Axis_Min_X ..
   --  Max_X); SelectedSpace, PixelAligned and PixelAlignedNoExclude, the
   --  selected space itself (as Pixel_Aligned_Min_X .. Max_X); ExtremaAngle,
   --  the selected space turned by ExtremaAngle (Median_Extrema_Angle_X).
   --  The median lies within the box's extent in that frame (proved for
   --  ExtremaAngle, tested for the others). Bad_Parameter for an ID that
   --  no feature has or an Axis that is not a code of
   --  CogBlobAxisConstants; Out_Of_Memory.

   procedure Get_Median_Y
     (Results : access constant Ks_Blob_Results_Data;
      ID      : Int32;
      Axis    : Int32;
      Median  : out Long_Float;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_blob_results_get_median_y",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory;
   --  CogBlobResult.GetMedianY (on the results): the same for the second
   --  coordinates (Principal_Axis_Min_Y .. Max_Y, the selected space's y,
   --  Median_Extrema_Angle_Y).

   procedure Create_Blob_ID_Image
     (Results  : access constant Ks_Blob_Results_Data;
      Filtered : Int32;
      Image    : out KI.Ks_Image_16_Grey;
      Status   : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_blob_results_create_blob_id_image",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Out_Of_Memory
             and then (if Succeeded (Status) then KI.Valid_Image (Image)
                       else Image = null);
   --  A new 16-bit image of the input image's size: ID + 1 at the pixels
   --  of each feature (of those that passed the filter when Filtered =
   --  1), 0 elsewhere. Image_No_Pixels for null results; Bad_Parameter
   --  when there are more than Max_ID_Image_Blobs features; Out_Of_Memory.

   --  The pixel values of the images of the results (Gold; see "Images
   --  of the results" above).

   function Level_At
     (M    : access constant U8_Matrix;
      X, Y : Natural) return Int32
   is
     (if M /= null and then Y in M'Range (1) and then X in M'Range (2)
      then Int32 (M (Y, X)) else 0)
   with Post => Level_At'Result in 0 .. 255;
   --  The segmented value of pixel (X, Y) in M; 0 outside M.

   function Stretched (Value, Full, Stretch : Int32)
                       return Interfaces.Unsigned_8
   is
     (if Stretch = True_Value
      then Interfaces.Unsigned_8 (Int32'Min (Value, Full) * 255 / Full)
      else Interfaces.Unsigned_8 (Value))
   with Pre => Value in 0 .. 255 and then Full in 1 .. 255;
   --  A segmented value as Create_Segmented_Image gives it: as it is, or
   --  stretched over 0 .. 255 (Full, the value of a pixel of full weight,
   --  becomes 255).

   function Segmented_Value
     (Results : access constant Ks_Blob_Results_Data;
      Which   : Int32;
      Stretch : Int32;
      X, Y    : Natural) return Interfaces.Unsigned_8
   is
     (if Which = Segmented_Final_Image
      then Stretched (Level_At (Results.Levels, X, Y), Results.Full,
                      Stretch)
      elsif Which = Segmented_Before_Morphology
      then Stretched (Level_At (Results.Before_Morphology, X, Y),
                      Results.Full, Stretch)
      else Stretched (Level_At (Results.Before_Masking, X, Y), Results.Full,
                      Stretch))
   with Pre => Valid_Saved (Results);
   --  Pixel (X, Y) of the segmented image of stage Which.

   function Viewable_Level (Level, Full : Int32) return Interfaces.Unsigned_8
   is
     (if Full = 1 then 255
      elsif (Full - 1) * 10 <= 63
      then Interfaces.Unsigned_8 (255 - (Full - Level) * 10)
      else Interfaces.Unsigned_8 (255 - (Full - Level) * 63 / (Full - 1)))
   with
     Pre  => Full in 1 .. 255 and then Level in 1 .. Full,
     Post => Viewable_Level'Result in 192 .. 255
             and then (if Level = Full then Viewable_Level'Result = 255);
   --  A blob pixel of level Level in the viewable blob image (AMV's
   --  rule): 255 at full weight, 10 less for each level below while
   --  Softness * 10 <= 63, else Softness levels spread over 192 .. 255.

   function Viewable_Label (Label : Int32) return Interfaces.Unsigned_8 is
     (Interfaces.Unsigned_8 (96 + Label * 159 / 255))
   with
     Pre  => Label in 0 .. 255,
     Post => Viewable_Label'Result in 96 .. 255;
   --  A blob pixel of Label (ConnectivityMode Labeled) in the viewable
   --  blob image: the labels spread evenly over 96 .. 255 (AMV's rule).

   function Clamped_Label (Label : Int32) return Int32 is
     (Int32'Max (0, Int32'Min (255, Label)))
   with Post => Clamped_Label'Result in 0 .. 255;
   --  A feature's Label within the grey values (it is one already).

   function Feature_Level
     (Results : access constant Ks_Blob_Results_Data;
      X, Y    : Natural) return Int32
   is
     (if Level_At (Results.Levels, X, Y) in 1 .. Results.Full
      then Level_At (Results.Levels, X, Y) else Results.Full)
   with
     Pre  => Valid_Saved (Results),
     Post => Feature_Level'Result in 1 .. Results.Full;
   --  The level of a blob pixel: its segmented value after the morphology,
   --  or full weight for a pixel the cleanup (Fill) gave to the blob and
   --  for a hard segmentation without saved levels.

   function Painted
     (Results  : access constant Ks_Blob_Results_Data;
      Filtered : Int32;
      ID       : Int32) return Boolean
   is
     (ID in 0 .. Results.Count - 1
      and then (Filtered = False_Value
                or else Results.Items (Integer (ID)).Filtered_Out
                          = False_Value))
   with Pre => Valid_Results (Results);
   --  Feature ID appears in the blob image (all features, or those that
   --  passed the filter when Filtered = 1).

   function Owner
     (Results : access constant Ks_Blob_Results_Data;
      X, Y    : Natural) return Int32
   is
     (if Results.Map /= null and then Y in Results.Map'Range (1)
         and then X in Results.Map'Range (2)
         and then Results.Map (Y, X) >= 1
      then Results.Map (Y, X) - 1 else -1)
   with Pre => Results /= null;
   --  The ID of the feature that owns pixel (X, Y), or a negative value.

   function Blob_Image_Value
     (Results    : access constant Ks_Blob_Results_Data;
      Filtered   : Int32;
      Viewable   : Int32;
      Background : Int32;
      X, Y       : Natural) return Interfaces.Unsigned_8
   is
     (if not Painted (Results, Filtered, Owner (Results, X, Y))
      then (if Viewable = True_Value then 128
            else Interfaces.Unsigned_8 (Background))
      elsif Results.Kinds (Integer (Owner (Results, X, Y))) = Label_Hole
      then 0
      elsif Results.Connectivity = Connectivity_Labeled
      then (if Viewable = True_Value
            then Viewable_Label
                   (Clamped_Label
                      (Results.Items (Integer (Owner (Results, X, Y)))
                         .Label))
            else Interfaces.Unsigned_8
                   (Clamped_Label
                      (Results.Items (Integer (Owner (Results, X, Y)))
                         .Label)))
      elsif Viewable = True_Value
      then Viewable_Level (Feature_Level (Results, X, Y), Results.Full)
      else Interfaces.Unsigned_8 (Feature_Level (Results, X, Y)))
   with
     Pre => Valid_Results (Results) and then Valid_Saved (Results)
            and then Viewable in False_Value | True_Value
            and then (Viewable = True_Value or else Background in 0 .. 255);
   --  Pixel (X, Y) of the blob image (see "Images of the results").

   procedure Create_Blob_Image
     (Results    : access constant Ks_Blob_Results_Data;
      Filtered   : Int32;
      Viewable   : Int32;
      Background : Int32;
      Image      : out KI.Ks_Image_8_Grey;
      Status     : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_blob_results_create_blob_image",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Valid_Results (Results) and then Valid_Saved (Results)
                     and then Filtered in False_Value | True_Value
                     and then Viewable in False_Value | True_Value
                     and then (Viewable = True_Value
                               or else Background in 0 .. 255)
                     and then KI.Valid_Image (Image)
                     and then Image.Width = Results.Image_Width
                     and then Image.Height = Results.Image_Height
                     and then
                       (for all Y in Image.Pixels'Range (1) =>
                          (for all X in Image.Pixels'Range (2) =>
                             Image.Pixels (Y, X)
                               = Blob_Image_Value
                                   (Results, Filtered, Viewable, Background,
                                    X, Y)))
                else Image = null);
   --  CogBlobResults.CreateBlobImage (filtered, viewable, background): a
   --  new 8-bit image of the input image's size (Gold: every pixel is
   --  Blob_Image_Value). Image_No_Pixels for null results ("there are no
   --  results"); Bad_Parameter for a results handle that is not valid,
   --  Filtered or Viewable not 0 or 1, or (when Viewable = 0) Background
   --  outside 0 .. 255; Out_Of_Memory.

   procedure Create_Segmented_Image
     (Results : access constant Ks_Blob_Results_Data;
      Which   : Int32;
      Stretch : Int32;
      Image   : out KI.Ks_Image_8_Grey;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_blob_results_create_segmented_image",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Out_Of_Memory
             and then
               (if not Succeeded (Status) then Image = null
                elsif (if Which = Segmented_Final_Image
                       then Results.Saved_Final = False_Value
                       elsif Which = Segmented_Before_Morphology
                       then Results.Saved_Before_Morphology = False_Value
                       else Results.Saved_Before_Masking = False_Value)
                then Image = null
                else Valid_Results (Results) and then Valid_Saved (Results)
                     and then Which in Segmented_Final_Image
                                     .. Segmented_Before_Masking
                     and then Stretch in False_Value | True_Value
                     and then KI.Valid_Image (Image)
                     and then Image.Width = Results.Image_Width
                     and then Image.Height = Results.Image_Height
                     and then
                       (for all Y in Image.Pixels'Range (1) =>
                          (for all X in Image.Pixels'Range (2) =>
                             Image.Pixels (Y, X)
                               = Segmented_Value
                                   (Results, Which, Stretch, X, Y))));
   --  CogBlobResults.CreateSegmentedImage (whichImage, stretchIt): a new
   --  8-bit image of the input image's size holding the segmented image
   --  of stage Which (Gold: every pixel is Segmented_Value), or null
   --  (with success) when the run did not save that stage (VisionPro
   --  returns null then). Image_No_Pixels for null results;
   --  Bad_Parameter for a results handle that is not valid, Which not a
   --  CogBlobSegmentedImageConstants value or Stretch not 0 or 1;
   --  Out_Of_Memory.

   ---------------------------------------------------------------------
   --  For the Ada API only (not exported)
   ---------------------------------------------------------------------

   procedure Check_Image
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Image_No_Pixels
                and then (Succeeded (Status) = (Image /= null));
   --  "InputImage has no pixels" for null. AMV.Blob calls it before it
   --  rasterises the region, so that a missing image is reported first.

private

   --  U8_Matrix (declared with the results above) holds the segmentation
   --  (Seg_* below) of the region's bounding rectangle, indexed (Y, X) by
   --  pixel coordinates. A soft segmentation also has a second matrix
   --  over the same rectangle with the level of every pixel (0 ..
   --  Softness + 1; 0 outside the region), from which the classes follow
   --  (foreground when the level is above 0).

   Seg_Outside    : constant Interfaces.Unsigned_8 := 0;
   Seg_Background : constant Interfaces.Unsigned_8 := 1;
   Seg_Foreground : constant Interfaces.Unsigned_8 := 2;

   type Int64_Array is array (Natural range <>) of Int64
     with Default_Component_Value => 0;
   type Int64_Array_Access is access Int64_Array;

   type Box is record
      X_Min, Y_Min, X_Max, Y_Max : Natural := 0;
   end record;
   --  The bounding rectangle of the region (pixel coordinates).

   function Valid_Box (B : Box) return Boolean is
     (B.X_Min <= B.X_Max and then B.Y_Min <= B.Y_Max);

   function Box_Of (Region : access constant KR.Ks_Pixel_Region_Data)
                    return Box
   is
     ((X_Min => Natural (Region.X_Min),
       Y_Min => Natural (Region.Y_Min),
       X_Max => Natural (Int64 (Region.X_Min) + Int64 (Region.Width) - 1),
       Y_Max => Natural (Int64 (Region.Y_Min) + Int64 (Region.Height) - 1)))
   with Pre => KR.Valid_Region (Region);

   function Region_In_Image
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data) return Boolean
   is
     (KI.Valid_Image (Image) and then KR.Valid_Region (Region)
      and then KR.In_Image (Region, Image.Width, Image.Height)
      and then Int64 (Region.Width) * Int64 (Region.Height)
                 <= Max_Region_Pixels);
   --  What the internal passes need: a valid image and a valid region
   --  inside it, small enough for the label tables.

   function Valid_Segmentation (P : Ks_Blob_Segmentation_Params)
                                return Boolean
   is
     (P.Mode in Segmentation_None | Segmentation_Hard_Fixed_Threshold
              | Segmentation_Hard_Relative_Threshold
              | Segmentation_Hard_Dynamic_Threshold
              | Segmentation_Soft_Fixed_Threshold
              | Segmentation_Soft_Relative_Threshold
      and then P.Polarity in Polarity_Dark_Blobs | Polarity_Light_Blobs
      and then P.Hard_Fixed_Threshold in 0 .. Max_Fixed_Threshold
      and then P.Hard_Relative_Threshold in 0 .. 100
      and then P.Tail_Low in 0 .. 100 and then P.Tail_High in 0 .. 100
      and then P.Soft_Fixed_Threshold_Low in 0 .. Max_Fixed_Threshold - 1
      and then P.Soft_Fixed_Threshold_High in 1 .. Max_Fixed_Threshold
      and then P.Soft_Fixed_Threshold_Low < P.Soft_Fixed_Threshold_High
      and then P.Soft_Relative_Threshold_Low in 0 .. 100
      and then P.Soft_Relative_Threshold_High in 0 .. 100
      and then P.Soft_Relative_Threshold_Low
                 <= P.Soft_Relative_Threshold_High
      and then P.Softness in 0 .. Max_Softness);

   function Is_Soft (P : Ks_Blob_Segmentation_Params) return Boolean is
     (P.Mode in Segmentation_Soft_Fixed_Threshold
              | Segmentation_Soft_Relative_Threshold);
   --  The segmentation gives levels (weights), not two classes.

   function Valid_Connectivity (P : Ks_Blob_Run_Params) return Boolean is
     (P.Connectivity_Mode
        in Connectivity_Grey_Scale | Connectivity_Labeled
         | Connectivity_Whole_Image_Grey_Scale
      and then P.Connectivity_Cleanup in Cleanup_None .. Cleanup_Fill
      and then P.Connectivity_Min_Pixels >= 0);

   function Bounded_Transform (T : KT.Ks_Transform_2D_Linear) return Boolean
   is
     (T.A >= -Max_Scale and then T.A <= Max_Scale
      and then T.B >= -Max_Scale and then T.B <= Max_Scale
      and then T.C >= -Max_Scale and then T.C <= Max_Scale
      and then T.D >= -Max_Scale and then T.D <= Max_Scale
      and then T.Translation_X >= -Max_Translation
      and then T.Translation_X <= Max_Translation
      and then T.Translation_Y >= -Max_Translation
      and then T.Translation_Y <= Max_Translation);
   --  Selected_From_Pixel within its bounds (False for NaN at run time).

   function Matrix_On_Box (M : U8_Matrix; B : Box) return Boolean is
     (M'First (1) = B.Y_Min and then M'Last (1) = B.Y_Max
      and then M'First (2) = B.X_Min and then M'Last (2) = B.X_Max);

   function Matrix_On_Box (M : Int32_Matrix; B : Box) return Boolean is
     (M'First (1) = B.Y_Min and then M'Last (1) = B.Y_Max
      and then M'First (2) = B.X_Min and then M'Last (2) = B.X_Max);

   --  Allocation (SPARK_Mode Off bodies; Storage_Error gives null).

   procedure Allocate_U8_Matrix
     (B : Box; Matrix : out U8_Matrix_Access)
   with
     Global => null,
     Pre    => Valid_Box (B),
     Post   => (if Matrix /= null
                then Matrix'First (1) = B.Y_Min
                     and then Matrix'Last (1) = B.Y_Max
                     and then Matrix'First (2) = B.X_Min
                     and then Matrix'Last (2) = B.X_Max);

   procedure Allocate_Int32_Matrix
     (B : Box; Matrix : out Int32_Matrix_Access)
   with
     Global => null,
     Pre    => Valid_Box (B),
     Post   => (if Matrix /= null
                then Matrix'First (1) = B.Y_Min
                     and then Matrix'Last (1) = B.Y_Max
                     and then Matrix'First (2) = B.X_Min
                     and then Matrix'Last (2) = B.X_Max);

   procedure Allocate_Int32_Array
     (Last : Natural; List : out Int32_Array_Access)
   with
     Global => null,
     Post   => (if List /= null
                then List'First = 0 and then List'Last = Last
                     and then (for all I in List'Range => List (I) = 0));

   procedure Allocate_Int64_Array
     (Last : Natural; List : out Int64_Array_Access)
   with
     Global => null,
     Post   => (if List /= null
                then List'First = 0 and then List'Last = Last
                     and then (for all I in List'Range => List (I) = 0));

   procedure Allocate_Results (Results : out Ks_Blob_Results)
   with
     Global => null,
     Post   => (if Results /= null
                then Results.Image_Width = 0 and then Results.Image_Height = 0
                     and then Results.Count = 0
                     and then Results.Filtered_Count = 0
                     and then Results.Items = null
                     and then Results.First_X = null
                     and then Results.First_Y = null
                     and then Results.Kinds = null
                     and then Results.Map = null
                     and then Results.Order = null
                     and then Results.Centroid_X = null
                     and then Results.Centroid_Y = null
                     and then Results.Levels = null
                     and then Results.Before_Morphology = null
                     and then Results.Before_Masking = null);

   procedure Free_Results (Results : in out Ks_Blob_Results)
   with Post => Results = null;
   --  Frees the results and everything they own.

   procedure Allocate_Result_Array
     (Last : Natural; List : out Result_Array_Access)
   with
     Global => null,
     Post   => (if List /= null
                then List'First = 0 and then List'Last = Last);

   procedure Allocate_Real_Array
     (Last : Natural; List : out Real_Array_Access)
   with
     Global => null,
     Post   => (if List /= null
                then List'First = 0 and then List'Last = Last);

end AMV.Kernels.Blob;
