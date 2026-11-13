--  Measures for AMV.Kernels.Blob: the sums over the pixels of each
--  feature (moments, weighted by the levels for the blobs of a soft
--  segmentation; bounding boxes, the boundary segments, clipping), the
--  measures in the selected space and the boxes along the principal and
--  selected axes. Silver: every value is finite and within the bounds
--  documented in AMV.Kernels.Blob.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

private package AMV.Kernels.Blob.Measures
  with SPARK_Mode, Preelaborate
is

   procedure Compute_Items
     (Region  : access constant KR.Ks_Pixel_Region_Data;
      Map     : Int32_Matrix;
      Count   : Int32;
      Kind    : Int32_Array;
      Label   : Int32_Array;
      Parent  : Int32_Array;
      First_X : Int32_Array;
      First_Y : Int32_Array;
      Area    : Int64_Array;
      Levels  : access constant U8_Matrix;
      Full    : Int32;
      T       : KT.Ks_Transform_2D_Linear;
      Items   : in out Result_Array;
      Cx, Cy  : in out Real_Array;
      Status  : out Ks_Status)
   with
     Pre  => (if Levels /= null
              then Levels'First (1) = Map'First (1)
                   and then Levels'Last (1) = Map'Last (1)
                   and then Levels'First (2) = Map'First (2)
                   and then Levels'Last (2) = Map'Last (2))
             and then Full in 1 .. Max_Softness + 1
             and then Map'First (1) <= Map'Last (1)
             and then Map'First (2) <= Map'Last (2)
             and then Count >= 1
             and then Kind'First = 0
             and then Int64 (Kind'Last) = Int64 (Count) - 1
             and then Label'First = 0 and then Label'Last = Kind'Last
             and then Parent'First = 0 and then Parent'Last = Kind'Last
             and then First_X'First = 0 and then First_X'Last = Kind'Last
             and then First_Y'First = 0 and then First_Y'Last = Kind'Last
             and then Area'First = 0 and then Area'Last = Kind'Last
             and then Items'First = 0 and then Items'Last = Kind'Last
             and then Cx'First = 0 and then Cx'Last = Kind'Last
             and then Cy'First = 0 and then Cy'Last = Kind'Last
             and then Bounded_Transform (T),
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory;
   --  Fills every field of Items (0 .. Count - 1) except Num_Children,
   --  Num_Unfiltered_Children, Filtered_Out and the extrema-angle fields
   --  (AMV.Kernels.Blob.Extrema), from the feature map Map (ID + 1 per
   --  pixel), the feature tables and the transform T from pixel space to
   --  the selected space (see Ks_Blob_Result), and the centres of mass of
   --  the features in pixel space to Cx, Cy (within 2**33). Levels is
   --  null for a hard segmentation; for a soft one it holds the level of
   --  every pixel of the map's rectangle and Full is Softness + 1: the
   --  area, centre of mass and second moments of a blob are then weighted
   --  by level / Full (a level of 0, which only a hole that the cleanup
   --  filled into the blob has, counting as Full), while holes and every
   --  other measure count each pixel once (see "Soft segmentation" in
   --  AMV.Kernels.Blob).
   --  Bad_Parameter when the pixel-aligned box of a feature cannot be
   --  mapped within the bounds of AMV.Kernels.Shapes (the bounds of T
   --  rule that out); Out_Of_Memory when the sums cannot be allocated.

end AMV.Kernels.Blob.Measures;
