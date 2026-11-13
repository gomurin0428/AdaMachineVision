--  Blob analysis: the counterpart of the namespace Cognex.VisionPro.Blob
--  (CogBlobTool, CogBlob, CogBlobSegmentationParams, CogBlobMeasure,
--  CogBlobResults, CogBlobResultCollection, CogBlobResult and their
--  enumerations).
--
--  A blob tool finds the connected sets of pixels of one kind (blobs) in
--  the pixels of its Region (the whole image for an empty holder), with
--  the holes in them, and measures them:
--
--     Tool.Input_Image := Image;
--     Tool.Run_Params.Segmentation_Params.Mode := Code (Hard_Fixed_Threshold);
--     Tool.Run_Params.Segmentation_Params.Polarity := Code (Light_Blobs);
--     Tool.Run;
--     for I in 0 .. Tool.Results.Get_Blobs.Count - 1 loop
--        Put (Tool.Results.Get_Blobs.Item (I).Area);
--     end loop;
--
--  The analysis (segmentation, connectivity, cleanup, measures, filter
--  and sort) is the SPARK kernel AMV.Kernels.Blob, whose spec documents
--  it in detail; this package passes the inputs to it and keeps its
--  results. In short:
--
--  * Segmentation (Run_Params.Segmentation_Params): a pixel of the region
--    is a blob pixel when its grey value is >= the threshold (Light_Blobs)
--    or < it (Dark_Blobs). The threshold is Hard_Fixed_Threshold, a
--    Hard_Relative_Threshold percentage between the darkest and the
--    brightest level of the region's histogram (after the Tail_Low and
--    Tail_High percent of its pixels are set aside), Otsu's threshold of
--    the histogram (Hard_Dynamic_Threshold, VisionPro's default; our own
--    choice of method), or 1 for None (the image is segmented already).
--    The soft thresholds (Soft_Fixed_Threshold, Soft_Relative_Threshold)
--    give each pixel a weight between 0 and 1 instead (see "Soft
--    segmentation" below). Map and Subtraction_Image are not supported.
--    Morphology_Operations (3 x 1, 1 x 3 or 3 x 3 erosion, dilation,
--    closing, opening) then apply to the blob pixels inside the region
--    (to the weights, for a soft segmentation: erosion takes the least
--    weight of the element's pixels, dilation the greatest).
--  * Connectivity: Grey_Scale gives 8-connected blobs and 4-connected
--    holes as their children; Labeled gives 8-connected blobs of equal
--    grey value (Label = the value); Whole_Image_Grey_Scale gives one
--    blob of all blob pixels. Prune removes features smaller than
--    Connectivity_Min_Pixels (with what lies inside them), Fill merges
--    them into the feature around them.
--  * Results: the features (blobs and, in Grey_Scale mode, holes with
--    Label 0) numbered by ID in raster order of their first pixel; every
--    measure in the input image's selected space at the time of the run
--    (positions mapped, areas scaled by abs det, second moments of the
--    mapped pixel squares, lengths along the mapped boundary). The
--    filtered collection (Get_Blobs) keeps the features that pass every
--    Run_Time_Measure with Mode Filter, sorted by Sort_Measure when
--    Sort_Enabled.
--  * Soft segmentation (AMV's rule where VisionPro states only its
--    outline). With the grey band [Low, High) (Soft_Fixed_Threshold_Low
--    and _High, or the Soft_Relative_Threshold_Low and _High percentages
--    of the way from the darker to the brighter tail level, as for
--    Hard_Relative_Threshold, rounded up) and S = Softness, a pixel of
--    grey value g gets a level from 0 to S + 1 and the weight level /
--    (S + 1): for Light_Blobs 0 below the band, S + 1 from High on and
--    1 + floor ((g - Low) S / (High - Low)) inside it; for Dark_Blobs
--    S + 1 below the band, 0 from High on and S - floor ((g - Low) S /
--    (High - Low)) inside it. With S = 0 the band is background; with
--    Low = High (relative mode) it is empty. A pixel of weight above 0
--    is a blob pixel. Weighted (for blobs): Area (sum of the weights),
--    the centre of mass, the second moments and everything derived from
--    them (Inertia_*, Elongation, Angle and the principal axes) or from
--    Area (Acircularity, and filtering and sorting by these). Not
--    weighted: connectivity and Connectivity_Min_Pixels (pixels are
--    counted), Pixel_Count, Perimeter, the boxes' extents, the
--    extrema-angle measures, the medians, Label, the tree, Not_Clipped,
--    the boundary and the ID image. A hole that Fill gives to a blob
--    counts with full weight; holes are measured as in the hard modes
--    (a small blob that Fill gives to a hole weighs 0 as a blob, so it
--    counts fully as part of the hole). The hard modes are unchanged
--    (every pixel weighs 1). Details: AMV.Kernels.Blob.
--
--  Run_Params is the kernel's C record (C: ks_blob_run_params): its
--  enumerations and Booleans are Int32 codes, set with the Code functions
--  below (Code (Labeled), Code (True)); the codes are VisionPro's numeric
--  values. The result items are the kernel's records too (C:
--  ks_blob_result), with Int32 flags (Filtered_Out, Not_Clipped).
--
--  Errors (Run_Status Error with the exception's name): an unallocated
--  Input_Image raises Ks_Image_No_Pixels_Exception; run parameters that
--  are not valid, a region that cannot be rasterised or a selected space
--  scaled beyond 2**64 relative to pixel space raise
--  Ks_Bad_Parameter_Exception naming the property.

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Images;
with AMV.Kernels;
with AMV.Kernels.Blob;
with AMV.Kernels.Blob.Tree;
with AMV.Shapes;
with AMV.Shapes.Region_Holders;
with AMV.Tools;

private with AMV.Shared_Handles;

package AMV.Blob is

   ---------------------------------------------------------------------
   --  Enumerations ('Pos is VisionPro's numeric value)
   ---------------------------------------------------------------------

   type Ks_Blob_Segmentation_Mode_Constants is
     (None, Map, Hard_Fixed_Threshold, Hard_Relative_Threshold,
      Hard_Dynamic_Threshold, Soft_Fixed_Threshold, Soft_Relative_Threshold,
      Subtraction_Image);
   --  CogBlobSegmentationModeConstants (Map and Subtraction_Image are not
   --  supported).

   type Ks_Blob_Segmentation_Polarity_Constants is (Dark_Blobs, Light_Blobs);

   type Ks_Blob_Connectivity_Mode_Constants is
     (Grey_Scale, Labeled, Whole_Image_Grey_Scale);

   type Ks_Blob_Connectivity_Cleanup_Constants is (None, Prune, Fill);

   type Ks_Blob_Measure_Constants is
     (Label, Area, Boundary_Pixel_Length, Perimeter, Num_Unfiltered_Children,
      Center_Mass_X, Center_Mass_Y, Inertia_X, Inertia_Y, Inertia_Min,
      Inertia_Max, Elongation, Angle, Acircularity, Acircularity_Rms,
      Bounding_Box_Pixel_Aligned_No_Exclude_Center_X,
      Bounding_Box_Pixel_Aligned_No_Exclude_Center_Y,
      Bounding_Box_Pixel_Aligned_No_Exclude_Min_X,
      Bounding_Box_Pixel_Aligned_No_Exclude_Max_X,
      Bounding_Box_Pixel_Aligned_No_Exclude_Min_Y,
      Bounding_Box_Pixel_Aligned_No_Exclude_Max_Y,
      Bounding_Box_Pixel_Aligned_No_Exclude_Width,
      Bounding_Box_Pixel_Aligned_No_Exclude_Height,
      Bounding_Box_Pixel_Aligned_No_Exclude_Aspect,
      Median_Extrema_Angle_X, Median_Extrema_Angle_Y,
      Bounding_Box_Extrema_Angle_Center_X,
      Bounding_Box_Extrema_Angle_Center_Y,
      Bounding_Box_Extrema_Angle_Min_X, Bounding_Box_Extrema_Angle_Max_X,
      Bounding_Box_Extrema_Angle_Min_Y, Bounding_Box_Extrema_Angle_Max_Y,
      Bounding_Box_Extrema_Angle_Width, Bounding_Box_Extrema_Angle_Height,
      Bounding_Box_Extrema_Angle_Aspect,
      Bounding_Box_Principal_Axis_Min_X, Bounding_Box_Principal_Axis_Max_X,
      Bounding_Box_Principal_Axis_Min_Y, Bounding_Box_Principal_Axis_Max_Y,
      Bounding_Box_Principal_Axis_Width,
      Bounding_Box_Principal_Axis_Height,
      Bounding_Box_Principal_Axis_Aspect,
      Not_Clipped);
   --  CogBlobMeasureConstants. Boundary_Pixel_Length and Acircularity_Rms
   --  are not computed (a run that filters or sorts by one, and
   --  Get_Measure for one, raise Ks_Bad_Parameter_Exception). The
   --  extrema-angle measures are taken along the axes at
   --  Run_Params.Extrema_Angle (see Ks_Blob_Result).

   type Ks_Blob_Measure_Mode_Constants is (None, Pre_Compute, Filter);

   type Ks_Blob_Filter_Mode_Constants is
     (Exclude_Blobs_In_Range, Include_Blobs_In_Range);

   type Ks_Blob_Axis_Constants is
     (Principal, Selected_Space, Extrema_Angle, Pixel_Aligned,
      Pixel_Aligned_No_Exclude);
   --  CogBlobAxisConstants.

   type Ks_Blob_Morphology_Constants is
     (Erode_Horizontal, Erode_Vertical, Erode_Square, Dilate_Horizontal,
      Dilate_Vertical, Dilate_Square, Close_Horizontal, Close_Vertical,
      Close_Square, Open_Horizontal, Open_Vertical, Open_Square);

   type Ks_Blob_Label_Constants is (Hole, Blob);
   --  CogBlobLabelConstants: the Label of a feature in Grey_Scale mode.

   type Ks_Blob_Segmented_Image_Constants is
     (Final_Image, Before_Morphology, Before_Masking);
   --  CogBlobSegmentedImageConstants: the stage of a segmented image
   --  (Create_Segmented_Image).

   subtype Code_Type is AMV.Kernels.Int32;

   function Code (Value : Ks_Blob_Segmentation_Mode_Constants)
                  return Code_Type;
   function Code (Value : Ks_Blob_Segmentation_Polarity_Constants)
                  return Code_Type;
   function Code (Value : Ks_Blob_Connectivity_Mode_Constants)
                  return Code_Type;
   function Code (Value : Ks_Blob_Connectivity_Cleanup_Constants)
                  return Code_Type;
   function Code (Value : Ks_Blob_Measure_Constants) return Code_Type;
   function Code (Value : Ks_Blob_Measure_Mode_Constants) return Code_Type;
   function Code (Value : Ks_Blob_Filter_Mode_Constants) return Code_Type;
   function Code (Value : Ks_Blob_Axis_Constants) return Code_Type;
   function Code (Value : Ks_Blob_Morphology_Constants) return Code_Type;
   function Code (Value : Ks_Blob_Label_Constants) return Code_Type;
   function Code (Value : Ks_Blob_Segmented_Image_Constants)
                  return Code_Type;
   function Code (Value : Boolean) return Code_Type;
   --  The code of a value in the run parameters and results (AMV): the
   --  VisionPro value of an enumeration literal ('Pos), 1 for True and 0
   --  for False. None belongs to three of the types: qualify it, as in
   --  Code (Ks_Blob_Connectivity_Cleanup_Constants'(None)).

   ---------------------------------------------------------------------
   --  Run parameters (CogBlob)
   ---------------------------------------------------------------------

   subtype Ks_Blob_Segmentation_Params is
     AMV.Kernels.Blob.Ks_Blob_Segmentation_Params;
   --  Mode (Hard_Dynamic_Threshold), Polarity (Dark_Blobs),
   --  Hard_Fixed_Threshold (128, 0 .. 65535), Hard_Relative_Threshold
   --  (50, percent), Tail_Low and Tail_High (0, percent),
   --  Soft_Fixed_Threshold_Low (102, 0 .. 65534) and
   --  Soft_Fixed_Threshold_High (153, 1 .. 65535; Low < High),
   --  Soft_Relative_Threshold_Low (40) and Soft_Relative_Threshold_High
   --  (60; percent, Low <= High), Softness (254, 0 .. 254). The defaults
   --  are VisionPro's except the soft fixed thresholds, which VisionPro
   --  does not state (AMV's: the relative defaults placed on the grey
   --  range 0 .. 255). Run checks every field, whatever the mode.

   procedure Set_Segmentation_Hard_Fixed_Threshold
     (Params               : in out Ks_Blob_Segmentation_Params;
      Hard_Fixed_Threshold : Integer;
      Polarity             : Ks_Blob_Segmentation_Polarity_Constants);
   --  SetSegmentationHardFixedThreshold: Mode := Hard_Fixed_Threshold and
   --  the two fields. Raises Ks_Bad_Parameter_Exception (Params unchanged)
   --  for a threshold outside 0 .. 65535.

   procedure Set_Segmentation_Hard_Relative_Threshold
     (Params                  : in out Ks_Blob_Segmentation_Params;
      Tail_Low                : Integer;
      Tail_High               : Integer;
      Hard_Relative_Threshold : Integer;
      Polarity                : Ks_Blob_Segmentation_Polarity_Constants);
   --  SetSegmentationHardRelativeThreshold: Mode := Hard_Relative_Threshold
   --  and the fields. Raises Ks_Bad_Parameter_Exception (Params unchanged)
   --  for a value outside 0 .. 100 or Tail_Low + Tail_High > 100.

   procedure Set_Segmentation_Hard_Dynamic_Threshold
     (Params    : in out Ks_Blob_Segmentation_Params;
      Tail_Low  : Integer;
      Tail_High : Integer;
      Polarity  : Ks_Blob_Segmentation_Polarity_Constants);
   --  SetSegmentationHardDynamicThreshold: Mode := Hard_Dynamic_Threshold
   --  and the fields (AMV's dynamic threshold does not use the tails).
   --  Raises Ks_Bad_Parameter_Exception (Params unchanged) as the relative
   --  setter does.

   procedure Set_Segmentation_Soft_Fixed_Threshold
     (Params                    : in out Ks_Blob_Segmentation_Params;
      Soft_Fixed_Threshold_Low  : Integer;
      Soft_Fixed_Threshold_High : Integer;
      Softness                  : Integer;
      Polarity                  : Ks_Blob_Segmentation_Polarity_Constants);
   --  SetSegmentationSoftFixedThreshold: Mode := Soft_Fixed_Threshold and
   --  the fields. Raises Ks_Bad_Parameter_Exception (Params unchanged) for
   --  Low outside 0 .. 65534, High outside 1 .. 65535, Low >= High or
   --  Softness outside 0 .. 254.

   procedure Set_Segmentation_Soft_Relative_Threshold
     (Params                       : in out Ks_Blob_Segmentation_Params;
      Tail_Low                     : Integer;
      Tail_High                    : Integer;
      Soft_Relative_Threshold_Low  : Integer;
      Soft_Relative_Threshold_High : Integer;
      Softness                     : Integer;
      Polarity : Ks_Blob_Segmentation_Polarity_Constants);
   --  SetSegmentationSoftRelativeThreshold: Mode := Soft_Relative_Threshold
   --  and the fields. Raises Ks_Bad_Parameter_Exception (Params unchanged)
   --  for a percentage outside 0 .. 100, Tail_Low + Tail_High > 100,
   --  Low > High or Softness outside 0 .. 254.

   subtype Ks_Blob_Measure is AMV.Kernels.Blob.Ks_Blob_Measure;
   --  Measure, Mode, Filter_Mode, Filter_Range_Low, Filter_Range_High.

   subtype Ks_Blob_Measure_Collection is
     AMV.Kernels.Blob.Ks_Blob_Measure_Collection;
   --  Count and Items (0 .. Count - 1), at most 64.

   subtype Ks_Blob_Morphology_Collection is
     AMV.Kernels.Blob.Ks_Blob_Morphology_Collection;
   --  Count and Items (0 .. Count - 1), codes of
   --  Ks_Blob_Morphology_Constants, at most 32.

   subtype Ks_Blob is AMV.Kernels.Blob.Ks_Blob_Run_Params;
   --  Segmentation_Params, Connectivity_Mode (Grey_Scale),
   --  Connectivity_Cleanup (Fill), Connectivity_Min_Pixels (10),
   --  Sort_Enabled (True), Sort_Measure (Area), Sort_Ascending (False),
   --  Run_Time_Measures (empty), Morphology_Operations (empty),
   --  Extrema_Angle (0.0; radians, finite and within +/-1.0E6, the
   --  direction in the selected space of the axes of the extrema-angle
   --  measures): VisionPro's defaults. Save_Segmented_Image,
   --  Save_Segmented_Image_Before_Masking and
   --  Save_Segmented_Image_Before_Morphology (False: whether the results
   --  keep the segmented image of that stage for Create_Segmented_Image;
   --  VisionPro states the default of the first only).

   function Blob_Measure
     (Measure           : Ks_Blob_Measure_Constants;
      Mode              : Ks_Blob_Measure_Mode_Constants := Pre_Compute;
      Filter_Mode       : Ks_Blob_Filter_Mode_Constants :=
        Include_Blobs_In_Range;
      Filter_Range_Low  : Real := 0.0;
      Filter_Range_High : Real := 0.0) return Ks_Blob_Measure;
   --  The constructors of CogBlobMeasure.

   procedure Add
     (Measures : in out Ks_Blob_Measure_Collection;
      Measure  : Ks_Blob_Measure);
   --  Appends Measure. Raises Ks_Bad_Parameter_Exception when the
   --  collection is full.

   procedure Add
     (Operations : in out Ks_Blob_Morphology_Collection;
      Operation  : Ks_Blob_Morphology_Constants);
   --  Appends Operation. Raises Ks_Bad_Parameter_Exception when the
   --  collection is full.

   procedure Clear (Measures : in out Ks_Blob_Measure_Collection);
   procedure Clear (Operations : in out Ks_Blob_Morphology_Collection);

   ---------------------------------------------------------------------
   --  Results (CogBlobResults, CogBlobResultCollection, CogBlobResult)
   ---------------------------------------------------------------------

   subtype Ks_Blob_Result is AMV.Kernels.Blob.Ks_Blob_Result;
   --  One feature (blob or hole): ID, Label, Parent_ID (AMV: -1 for
   --  none), Num_Children, Num_Unfiltered_Children, Filtered_Out (1 when
   --  it did not pass the filter), Not_Clipped (1 when it does not touch
   --  the edge of the region), Pixel_Count (AMV), Area, Center_Of_Mass_X,
   --  Center_Of_Mass_Y, Angle, Perimeter, Inertia_X, Inertia_Y,
   --  Inertia_Min, Inertia_Max, Elongation, Acircularity, and the boxes
   --  and their measures (see AMV.Kernels.Blob.Ks_Blob_Result). The
   --  extrema-angle measures are coordinates in the selected space turned
   --  by Run_Params.Extrema_Angle (E) about its origin (u = x cos E +
   --  y sin E, v = -x sin E + y cos E): the bounds, centre, sides and
   --  aspect of the box around the feature's pixel squares along those
   --  axes (Extrema_Angle_Min_X .. Max_X, Min_Y .. Max_Y, Center_X,
   --  Center_Y, Width, Height, Aspect) and the medians of u and v over its
   --  pixel centres (Median_Extrema_Angle_X / Y); the principal-axis
   --  measures are instead measured from the centre of mass.

   function Get_Measure
     (Result  : Ks_Blob_Result;
      Measure : Ks_Blob_Measure_Constants) return Real;
   --  GetMeasure. Raises Ks_Bad_Parameter_Exception for a measure that is
   --  not computed.

   function Get_Bounding_Box
     (Result : Ks_Blob_Result;
      Axis   : Ks_Blob_Axis_Constants) return AMV.Shapes.Ks_Rectangle_Affine;
   --  GetBoundingBox: the box around the feature's pixel squares along
   --  its principal axes, the axes of the selected space, the axes at
   --  Run_Params.Extrema_Angle, or the pixel axes (Pixel_Aligned and
   --  Pixel_Aligned_No_Exclude, the same box), in the selected space (the
   --  shape's Selected_Space_Name is ".").

   type Ks_Blob_Results is tagged private;
   --  The results of a run; empty before the first run and after a
   --  failed one. Copies share the kernel's results (they never change).

   type Ks_Blob_Result_Collection is tagged private;
   --  A view of the features of a Ks_Blob_Results (CogBlobResultCollection).

   function Get_Blobs
     (Results  : Ks_Blob_Results;
      Filtered : Boolean := True) return Ks_Blob_Result_Collection'Class;
   --  GetBlobs: the features that passed the filter, in the sort order
   --  (Filtered), or every feature in ID order.

   function Count (Collection : Ks_Blob_Result_Collection) return Natural;

   function Item
     (Collection : Ks_Blob_Result_Collection;
      Index      : Natural) return Ks_Blob_Result;
   --  0-based. Raises Constraint_Error for an index >= Count.

   function Get_Blob_By_ID
     (Results : Ks_Blob_Results;
      Blob_ID : Integer) return Ks_Blob_Result;
   --  GetBlobByID: the feature with this ID, filtered or not. Raises
   --  Ks_Bad_Parameter_Exception for an ID no feature has.

   function Get_Parent
     (Results : Ks_Blob_Results;
      Blob_ID : Integer) return Integer;
   --  GetParent, as an ID (AMV: VisionPro returns the result itself, or
   --  null): the ID of the parent of feature Blob_ID, -1 when it has none.
   --  Raises Ks_Bad_Parameter_Exception for an ID no feature has.

   --  The feature tree (AMV's definitions; AMV.Kernels.Blob.Tree). With
   --  Filtered the features are taken from Get_Blobs (Results, True) in
   --  its order, otherwise from every feature in ID order. Blob_ID may be
   --  any feature's ID, filtered or not; Ks_Bad_Parameter_Exception for
   --  an ID no feature has. A collection holds the IDs it was made with.

   function Get_Children
     (Results  : Ks_Blob_Results;
      Blob_ID  : Integer;
      Filtered : Boolean) return Ks_Blob_Result_Collection'Class;
   --  GetChildren: the features whose parent is feature Blob_ID (the
   --  holes of a blob, the blobs inside a hole).

   function Get_Siblings
     (Results  : Ks_Blob_Results;
      Blob_ID  : Integer;
      Filtered : Boolean) return Ks_Blob_Result_Collection'Class;
   --  GetSiblings: the features other than feature Blob_ID that have its
   --  parent (for a top-level feature, the other top-level features).

   function Get_Top_Level_Blobs
     (Results  : Ks_Blob_Results;
      Filtered : Boolean) return Ks_Blob_Result_Collection'Class;
   --  GetTopLevelBlobs: the features without a parent.

   subtype Ks_Blob_ID_Array is AMV.Kernels.Blob.Tree.Blob_ID_List;
   --  array (Natural range <>) of Integer.

   function Get_Blob_IDs
     (Results  : Ks_Blob_Results;
      Filtered : Boolean) return Ks_Blob_ID_Array;
   --  GetBlobIDs: the IDs of Get_Blobs (Results, Filtered) in its order,
   --  indexed from 0.

   function Get_Blob_Measure
     (Results : Ks_Blob_Results;
      Measure : Ks_Blob_Measure_Constants;
      Blob_ID : Integer) return Real;
   --  GetBlobMeasure: Get_Measure (Get_Blob_By_ID (Results, Blob_ID),
   --  Measure). Raises Ks_Bad_Parameter_Exception for an ID no feature
   --  has or a measure the results do not hold.

   subtype Ks_Blob_Measure_Array is AMV.Kernels.Blob.Tree.Measure_List;
   --  array (Natural range <>) of Real.

   function Get_Blob_Measures
     (Results  : Ks_Blob_Results;
      Measure  : Ks_Blob_Measure_Constants;
      Blob_IDs : Ks_Blob_ID_Array) return Ks_Blob_Measure_Array;
   --  GetBlobMeasures: the measure of each feature of Blob_IDs, with the
   --  bounds of Blob_IDs. Raises Ks_Bad_Parameter_Exception as
   --  Get_Blob_Measure does (an empty list gives an empty list).

   function Get_Boundary
     (Results : Ks_Blob_Results;
      Blob_ID : Integer) return AMV.Shapes.Ks_Polygon;
   --  CogBlobResult.GetBoundary (AMV: on the results, since a result
   --  record holds no pixels): the outer boundary of the feature along
   --  its pixel edges, a vertex at every corner where it turns, in the
   --  selected space (Selected_Space_Name "."). Raises
   --  Ks_Bad_Parameter_Exception for an ID no feature has.

   function Get_Bounding_Box_At_Angle
     (Results : Ks_Blob_Results;
      Blob_ID : Integer;
      Angle   : Real) return AMV.Shapes.Ks_Rectangle_Affine;
   --  CogBlobResult.GetBoundingBoxAtAngle (AMV: on the results, since a
   --  result record holds no pixels): the smallest rectangle around the
   --  pixel squares of feature Blob_ID whose sides run along the axes at
   --  Angle (radians) in the selected space, with Rotation = Angle and no
   --  skew (Selected_Space_Name "."). At Angle = Run_Params.Extrema_Angle
   --  it is Get_Bounding_Box (Result, Extrema_Angle), at 0 the box along
   --  the selected space's axes. Raises Ks_Bad_Parameter_Exception for an
   --  ID no feature has or an Angle that is not finite or exceeds
   --  1.0E6 in magnitude.

   function Get_Median_X
     (Results : Ks_Blob_Results;
      Blob_ID : Integer;
      Axis    : Ks_Blob_Axis_Constants) return Real;
   function Get_Median_Y
     (Results : Ks_Blob_Results;
      Blob_ID : Integer;
      Axis    : Ks_Blob_Axis_Constants) return Real;
   --  CogBlobResult.GetMedianX / GetMedianY (AMV: on the results): the
   --  median of the x (y) coordinates of the centres of the pixels of
   --  feature Blob_ID in the frame of the measures of the box of Axis
   --  (the middle value, or the mean of the two middle values for an even
   --  number of pixels, selected exactly): Principal, along the principal
   --  axes from the centre of mass (as Principal_Axis_Min_X .. Max_X);
   --  Selected_Space, Pixel_Aligned and Pixel_Aligned_No_Exclude, the
   --  selected space's x (y); Extrema_Angle, the measure
   --  Median_Extrema_Angle_X (_Y). Raises Ks_Bad_Parameter_Exception for
   --  an ID no feature has.

   function Create_Blob_ID_Image
     (Results  : Ks_Blob_Results;
      Filtered : Boolean := True) return AMV.Images.Ks_Image_16_Grey;
   --  (AMV name; VisionPro's CreateBlobImage gives an 8-bit image.) An
   --  image of the input image's size and coordinate spaces holding ID + 1
   --  at the pixels of each feature (that passed the filter, when
   --  Filtered) and 0 elsewhere. Raises Ks_Image_No_Pixels_Exception for
   --  empty results and Ks_Bad_Parameter_Exception for more than 65535
   --  features.

   function Create_Blob_Image
     (Results    : Ks_Blob_Results;
      Filtered   : Boolean := True;
      Viewable   : Boolean := True;
      Background : Integer := 0) return AMV.Images.Ks_Image_8_Grey;
   --  CogBlobResults.CreateBlobImage (filtered, viewable, background); the
   --  defaults give CreateBlobImage () (AMV's reading: the filtered
   --  features, viewable). An image of the input image's size and
   --  coordinate spaces with the features (all, or those that passed the
   --  filter when Filtered) painted onto a background:
   --  * Viewable: background 128, hole pixels 0, blob pixels 255 for a
   --    hard segmentation; for a soft one 255 at full weight and lower
   --    levels darker within 192 .. 255 (10 per level while Softness * 10
   --    <= 63, else spread evenly); in Labeled mode the labels spread
   --    evenly over 96 .. 255 (96 + Label * 159 / 255). The spacings are
   --    AMV's.
   --  * Not viewable: background Background, hole pixels 0, blob pixels
   --    their segmented value (1 for a hard segmentation, the level 1 ..
   --    Softness + 1 for a soft one), in Labeled mode their Label.
   --  A blob pixel that Fill gave to the blob counts as full weight.
   --  Raises Ks_Image_No_Pixels_Exception for empty results and
   --  Ks_Bad_Parameter_Exception for Background outside 0 .. 255 when not
   --  Viewable.

   function Create_Segmented_Image
     (Results     : Ks_Blob_Results;
      Which_Image : Ks_Blob_Segmented_Image_Constants := Final_Image;
      Stretch_It  : Boolean := True) return AMV.Images.Ks_Image_8_Grey;
   --  CogBlobResults.CreateSegmentedImage (whichImage, stretchIt); the
   --  defaults give CreateSegmentedImage (). The segmented image of a
   --  stage, in an image of the input image's size and coordinate spaces:
   --  0 or 1 per pixel for a hard segmentation (1 for a blob pixel), the
   --  level 0 .. Softness + 1 for a soft one, 0 outside the region's
   --  bounding rectangle; stretched, value * 255 / (Softness + 1) (255
   --  for a blob pixel of a hard segmentation). Final_Image is the
   --  segmentation after Morphology_Operations (the pixels connectivity
   --  used, before the cleanup), Before_Morphology the one before them,
   --  Before_Masking every pixel of the region's bounding rectangle,
   --  whether it lies in the region or not (AMV: the mask is the region's
   --  shape). An image without pixels (VisionPro: null) when the run did
   --  not save that stage (Run_Params.Save_Segmented_Image,
   --  _Before_Morphology, _Before_Masking). Raises
   --  Ks_Image_No_Pixels_Exception for empty results.

   function Selected_Space_Name (Results : Ks_Blob_Results) return String;
   --  The selected space of the input image at the run, in which the
   --  measures are given (CogBlobResult.SelectedSpaceName); "@" for empty
   --  results.

   ---------------------------------------------------------------------
   --  CogBlobTool
   ---------------------------------------------------------------------

   type Ks_Blob_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image : AMV.Images.Ks_Image_8_Grey;
      Region      : AMV.Shapes.Region_Holders.Holder;
      Run_Params  : Ks_Blob;
      Results     : Ks_Blob_Results;
   end record;
   --  Region: any region type of AMV.Shapes in a space of Input_Image's
   --  tree; an empty holder is the whole image. Results is set by Run.

   overriding procedure Execute (Tool : in out Ks_Blob_Tool);
   overriding procedure Reset_Results (Tool : in out Ks_Blob_Tool);

private

   procedure Destroy_Results
     (Handle : in out AMV.Kernels.Blob.Ks_Blob_Results);

   package Results_Holders is new AMV.Shared_Handles
     (AMV.Kernels.Blob.Ks_Blob_Results, null, Destroy_Results);

   type Ks_Blob_Results is tagged record
      Holder : Results_Holders.Holder;
      Spaces : AMV.Images.Ks_Image_8_Grey;
      --  The coordinate spaces of the input image (without pixels).
   end record;

   type ID_List_Access is access AMV.Kernels.Blob.Tree.Blob_ID_List;

   procedure Destroy_IDs (Handle : in out ID_List_Access);

   package ID_Holders is new AMV.Shared_Handles
     (ID_List_Access, null, Destroy_IDs);

   type Ks_Blob_Result_Collection is tagged record
      Holder   : Results_Holders.Holder;
      IDs      : ID_Holders.Holder;
      Filtered : AMV.Kernels.Int32 := AMV.Kernels.True_Value;
   end record;
   --  The results and the IDs of the collection's features in its order,
   --  or, when IDs is empty, GetBlobs (Filtered) itself (read through the
   --  kernel's filtered order, so that Get_Blobs builds no list).

end AMV.Blob;
