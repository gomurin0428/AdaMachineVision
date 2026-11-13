--  Segmentation for AMV.Kernels.Blob: the histogram of the region, the
--  threshold (or, for a soft segmentation, the band) of the run
--  parameters, the segmentation of the region's bounding rectangle (Gold:
--  every pixel follows Is_Foreground, or Soft_Level for a soft
--  segmentation) and the morphology applied to it afterwards (binary, or
--  on the levels for a soft segmentation).

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Otsu;

private package AMV.Kernels.Blob.Segmentation
  with SPARK_Mode, Preelaborate
is

   subtype Grey_8 is Interfaces.Unsigned_8;

   Max_Bin : constant := AMV.Kernels.Otsu.Max_Count;
   --  A bin never holds more than the region's pixels (at most 2**31 - 1);
   --  the counting stops at Max_Bin, which keeps every sum provably small.

   subtype Bin_Count is AMV.Kernels.Otsu.Level_Count;

   subtype Histogram is AMV.Kernels.Otsu.Level_Counts;

   function Is_Foreground
     (Polarity, Threshold : Int32;
      Value               : Grey_8) return Boolean
   is
     (if Polarity = Polarity_Light_Blobs then Int32 (Value) >= Threshold
      else Int32 (Value) < Threshold);
   --  The threshold rule (Gold): a light blob pixel has a grey value of at
   --  least Threshold, a dark blob pixel one below it.

   function Expected_Segment
     (Image               : access constant KI.Ks_Image_8_Grey_Data;
      Region              : access constant KR.Ks_Pixel_Region_Data;
      Polarity, Threshold : Int32;
      X, Y                : Natural) return Grey_8
   is
     (if not KR.Contains (Region, Int32 (X), Int32 (Y)) then Seg_Outside
      elsif Image = null or else Image.Pixels = null
        or else Y not in Image.Pixels'Range (1)
        or else X not in Image.Pixels'Range (2)
      then Seg_Outside
      elsif Is_Foreground (Polarity, Threshold, Image.Pixels (Y, X))
      then Seg_Foreground
      else Seg_Background);
   --  The class of pixel (X, Y): outside the region, or foreground or
   --  background of the region by Is_Foreground. (Total: a pixel outside
   --  the image counts as outside, which cannot happen for a region that
   --  lies in the image.)

   procedure Compute_Histogram
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Hist   : out Histogram)
   with Pre => Region_In_Image (Image, Region);
   --  The number of pixels of the region with each grey value.

   function Compute_Threshold
     (Params : Ks_Blob_Segmentation_Params;
      Hist   : Histogram) return Int32
   with
     Pre  => Valid_Segmentation (Params),
     Post => Compute_Threshold'Result in 0 .. Max_Fixed_Threshold
             and then (if Params.Mode = Segmentation_Hard_Fixed_Threshold
                       then Compute_Threshold'Result
                              = Params.Hard_Fixed_Threshold)
             and then (if Params.Mode = Segmentation_None
                       then Compute_Threshold'Result = 1);
   --  The threshold T of the rule for the segmentation mode (see
   --  AMV.Kernels.Blob): HardFixedThreshold, the relative threshold
   --  between the tails of the histogram, Otsu's threshold, or 1 for None.

   procedure Segment
     (Image               : access constant KI.Ks_Image_8_Grey_Data;
      Region              : access constant KR.Ks_Pixel_Region_Data;
      Polarity, Threshold : Int32;
      S                   : in out U8_Matrix)
   with
     Post => (for all Y in S'Range (1) =>
                (for all X in S'Range (2) =>
                   S (Y, X)
                     = Expected_Segment
                         (Image, Region, Polarity, Threshold, X, Y)));
   --  Gold: every pixel of S (the region's bounding rectangle) is
   --  classified exactly by Expected_Segment, that is by Is_Foreground
   --  with this threshold for the pixels of the region.

   procedure Apply_Morphology
     (Operations : Ks_Blob_Morphology_Collection;
      S          : in out U8_Matrix;
      Status     : out Ks_Status)
   with
     Pre  => S'First (1) <= S'Last (1) and then S'First (2) <= S'Last (2),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory;
   --  Applies Operations.Items (0 .. Count - 1) in order (codes outside
   --  CogBlobMorphologyConstants are skipped; Execute rejects them
   --  before). Only foreground and background pixels change; pixels
   --  outside the region stay outside. Out_Of_Memory when the copy the
   --  operations work from cannot be allocated.

   ---------------------------------------------------------------------
   --  Soft segmentation
   ---------------------------------------------------------------------

   subtype Threshold_Level is Int32 range 0 .. Max_Fixed_Threshold;
   --  An end of the band of a soft segmentation.

   subtype Softness_Value is Int32 range 0 .. Max_Softness;

   function Soft_Level
     (Polarity  : Int32;
      Low, High : Threshold_Level;
      Softness  : Softness_Value;
      Value     : Grey_8) return Int32
   is
     (if Int32 (Value) < Low
      then (if Polarity = Polarity_Light_Blobs then 0 else Softness + 1)
      elsif Int32 (Value) >= High
      then (if Polarity = Polarity_Light_Blobs then Softness + 1 else 0)
      elsif Softness = 0 then 0
      elsif Polarity = Polarity_Light_Blobs
      then 1 + (Int32 (Value) - Low) * Softness / (High - Low)
      else Softness - (Int32 (Value) - Low) * Softness / (High - Low))
   with
     Post => Soft_Level'Result in 0 .. Softness + 1
             and then
               (if Softness > 0 and then Int32 (Value) >= Low
                  and then Int32 (Value) < High
                then Soft_Level'Result in 1 .. Softness);
   --  The level rule of a soft segmentation (Gold; AMV's rule, see
   --  AMV.Kernels.Blob): below the band [Low, High) the level is 0 for
   --  light blobs and Softness + 1 for dark blobs, from High on the
   --  reverse; inside the band (empty when Low = High) the Softness
   --  steps of equal width get the levels 1 .. Softness, rising with the
   --  grey value for light blobs and falling for dark blobs; with
   --  Softness 0 the band is background. (Ada's integer division is the
   --  floor here: both operands are non-negative.)

   function Expected_Level
     (Image                    : access constant KI.Ks_Image_8_Grey_Data;
      Region                   : access constant KR.Ks_Pixel_Region_Data;
      Polarity                 : Int32;
      Low, High                : Threshold_Level;
      Softness                 : Softness_Value;
      X, Y                     : Natural) return Grey_8
   is
     (if not KR.Contains (Region, Int32 (X), Int32 (Y)) then 0
      elsif Image = null or else Image.Pixels = null
        or else Y not in Image.Pixels'Range (1)
        or else X not in Image.Pixels'Range (2)
      then 0
      else Grey_8 (Soft_Level (Polarity, Low, High, Softness,
                               Image.Pixels (Y, X))));
   --  The level of pixel (X, Y) by Soft_Level, 0 outside the region.

   function Expected_Soft_Segment
     (Image                    : access constant KI.Ks_Image_8_Grey_Data;
      Region                   : access constant KR.Ks_Pixel_Region_Data;
      Polarity                 : Int32;
      Low, High                : Threshold_Level;
      Softness                 : Softness_Value;
      X, Y                     : Natural) return Grey_8
   is
     (if not KR.Contains (Region, Int32 (X), Int32 (Y)) then Seg_Outside
      elsif Image = null or else Image.Pixels = null
        or else Y not in Image.Pixels'Range (1)
        or else X not in Image.Pixels'Range (2)
      then Seg_Outside
      elsif Soft_Level (Polarity, Low, High, Softness, Image.Pixels (Y, X))
              > 0
      then Seg_Foreground
      else Seg_Background);
   --  The class of pixel (X, Y): outside the region, or foreground of the
   --  region when its level is above 0, background otherwise.

   procedure Soft_Band
     (Params    : Ks_Blob_Segmentation_Params;
      Hist      : Histogram;
      Low, High : out Threshold_Level)
   with
     Pre  => Valid_Segmentation (Params) and then Is_Soft (Params),
     Post => Low <= High
             and then
               (if Params.Mode = Segmentation_Soft_Fixed_Threshold
                then Low = Params.Soft_Fixed_Threshold_Low
                     and then High = Params.Soft_Fixed_Threshold_High
                else High <= 255);
   --  The band [Low, High) of the soft mode: SoftFixedThresholdLow and
   --  High, or the relative band between the tail levels of the
   --  histogram (see AMV.Kernels.Blob).

   procedure Segment_Soft
     (Image     : access constant KI.Ks_Image_8_Grey_Data;
      Region    : access constant KR.Ks_Pixel_Region_Data;
      Polarity  : Int32;
      Low, High : Threshold_Level;
      Softness  : Softness_Value;
      S         : in out U8_Matrix;
      Levels    : in out U8_Matrix)
   with
     Pre  => Levels'First (1) = S'First (1)
             and then Levels'Last (1) = S'Last (1)
             and then Levels'First (2) = S'First (2)
             and then Levels'Last (2) = S'Last (2),
     Post => (for all Y in S'Range (1) =>
                (for all X in S'Range (2) =>
                   S (Y, X)
                     = Expected_Soft_Segment
                         (Image, Region, Polarity, Low, High, Softness,
                          X, Y)
                   and then
                     Levels (Y, X)
                       = Expected_Level
                           (Image, Region, Polarity, Low, High, Softness,
                            X, Y)));
   --  Gold: every pixel of the region's bounding rectangle gets the level
   --  of Soft_Level in Levels and the class that follows from it in S.

   procedure Apply_Soft_Morphology
     (Operations : Ks_Blob_Morphology_Collection;
      S          : in out U8_Matrix;
      Levels     : in out U8_Matrix;
      Status     : out Ks_Status)
   with
     Pre  => S'First (1) <= S'Last (1) and then S'First (2) <= S'Last (2)
             and then Levels'First (1) = S'First (1)
             and then Levels'Last (1) = S'Last (1)
             and then Levels'First (2) = S'First (2)
             and then Levels'Last (2) = S'Last (2),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory;
   --  Apply_Morphology on the levels: erosion gives a pixel of the region
   --  the least level, dilation the greatest, over the pixels of the
   --  element that lie in the region; the class of a pixel of the region
   --  follows its new level. Pixels outside the region stay outside.

   ---------------------------------------------------------------------
   --  Saved segmented images (the levels: 0 or 1 for a hard segmentation,
   --  0 .. Softness + 1 for a soft one)
   ---------------------------------------------------------------------

   function Hard_Level
     (Polarity, Threshold : Int32;
      Value               : Grey_8) return Grey_8
   is
     (if Is_Foreground (Polarity, Threshold, Value) then 1 else 0);

   function Box_Fits
     (Image : access constant KI.Ks_Image_8_Grey_Data;
      M     : U8_Matrix) return Boolean
   is
     (KI.Valid_Image (Image)
      and then M'Last (1) <= Image.Pixels'Last (1)
      and then M'Last (2) <= Image.Pixels'Last (2));
   --  Every pixel of M has a pixel of Image.

   procedure Segment_Box_Hard
     (Image               : access constant KI.Ks_Image_8_Grey_Data;
      Polarity, Threshold : Int32;
      M                   : in out U8_Matrix)
   with
     Pre  => Box_Fits (Image, M),
     Post => (for all Y in M'Range (1) =>
                (for all X in M'Range (2) =>
                   M (Y, X)
                     = Hard_Level (Polarity, Threshold, Image.Pixels (Y, X))));
   --  Gold: every pixel of M, in the region or not, segmented by the
   --  threshold rule (stage BeforeMasking).

   procedure Segment_Box_Soft
     (Image     : access constant KI.Ks_Image_8_Grey_Data;
      Polarity  : Int32;
      Low, High : Threshold_Level;
      Softness  : Softness_Value;
      M         : in out U8_Matrix)
   with
     Pre  => Box_Fits (Image, M),
     Post => (for all Y in M'Range (1) =>
                (for all X in M'Range (2) =>
                   M (Y, X)
                     = Grey_8 (Soft_Level (Polarity, Low, High, Softness,
                                           Image.Pixels (Y, X)))));
   --  Gold: every pixel of M, in the region or not, at its level by
   --  Soft_Level (stage BeforeMasking).

   procedure To_Levels (S : U8_Matrix; M : in out U8_Matrix)
   with
     Pre  => M'First (1) = S'First (1) and then M'Last (1) = S'Last (1)
             and then M'First (2) = S'First (2)
             and then M'Last (2) = S'Last (2),
     Post => (for all Y in M'Range (1) =>
                (for all X in M'Range (2) =>
                   M (Y, X) = (if S (Y, X) = Seg_Foreground then 1 else 0)));
   --  Gold: the levels of a hard segmentation S: 1 for foreground, 0 for
   --  background and outside the region.

end AMV.Kernels.Blob.Segmentation;
