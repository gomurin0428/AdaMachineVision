--  The histogram tool: the counterpart of CogHistogramTool, its run
--  parameters CogHistogram and its result CogHistogramResult
--  (Cognex.VisionPro.ImageProcessing).
--
--     Tool.Input_Image := Image;
--     Tool.Region := AMV.Shapes.Region_Holders.To_Holder (Circle);
--     Tool.Run;
--     if Tool.Run_Status.Result = Accept_Result then
--        Put (Tool.Result.Mean);
--
--  The tool counts the grey levels of the pixels of Input_Image that the
--  Region covers (AMV.Regions.Rasterize: a pixel belongs to the region
--  when its centre does; an empty Region holder means the whole image).
--  A region that covers no pixel centre of the image gives a result
--  without samples: Num_Samples = 0, every bin 0 and every statistic 0
--  (no exception).
--
--  Input image mask (VisionPro's InputImageMask, InputImageMaskOffsetX and
--  InputImageMaskOffsetY; in AMV components of the tool, since the run
--  parameters are the kernel's C record). An allocated
--  Input_Image_Mask removes from the samples the pixels it marks "don't
--  care": mask pixel (U, V) lies over pixel (U + Input_Image_Mask_Offset_X,
--  V + Input_Image_Mask_Offset_Y) of Input_Image, a mask pixel of value 0
--  marks the pixel under it "don't care", and a pixel under a mask pixel of
--  any other value, or under no mask pixel at all, stays a sample
--  (AMV.Regions.Restrict_To_Mask; the mask may have any size and lie partly
--  or wholly outside the image). The default, an unallocated mask with
--  offsets 0, changes nothing. A mask that removes every pixel of the
--  region gives a result without samples, as above.
--
--  Region mode (VisionPro's CogHistogram.RegionMode; in AMV a component of
--  the tool, Region_Mode, since the run parameters are the kernel's C
--  record): which pixels the Region selects.
--  * Pixel_Aligned_Bounding_Box_Adjust_Mask (0, the default, as in
--    VisionPro): the pixels the region covers (above).
--  * Pixel_Aligned_Bounding_Box (1): every pixel of the region's
--    pixel-aligned bounding box (the rectangle around the pixels it
--    covers), whatever its shape.
--  * Affine_Transform (2): the Region must be a Ks_Rectangle_Affine; the
--    samples are every pixel of that rectangle resampled upright, one
--    pixel per pixel along its sides (samples outside the image count as
--    0), as the affine transform tool would produce with its defaults.
--    Another shape raises Ks_Bad_Parameter_Exception ("Region must be an
--    affine rectangle for RegionMode AffineTransform"), and so does an
--    allocated Input_Image_Mask (AMV's choice: the mask lies over the
--    input image, not over the resampled one).
--  The mask applies after the bounding box is taken. An empty Region
--  holder (the whole image) gives the same samples in every mode. Any
--  other value raises Ks_Bad_Parameter_Exception. (VisionPro's reference
--  gives AdjustMask as the default and lists only the other two as
--  accepted; AMV accepts all three.) The kernel is
--  AMV.Kernels.Histogram.Region_Modes (C: ks_histogram_execute_affine,
--  and ks_pixel_region_bounding_box for the bounding box).
--
--  The work is done by the SPARK kernel AMV.Kernels.Histogram (C:
--  ks_histogram_*, include/amv_image_processing.h), which proves that
--  every bin holds exactly the number of samples whose grey level falls
--  into it, that Num_Samples is the number of pixels of the region, and
--  that Minimum <= Median, Mode, Mean <= Maximum. Its spec describes the
--  bin modes and the statistics in detail.
--
--  Run fails (Run_Status Error, results cleared) with
--  Ks_Image_No_Pixels_Exception for an unallocated Input_Image ("InputImage
--  has no pixels"), Ks_Image_Bad_Selected_Space_Name_Exception for a
--  region in an unknown space, and Ks_Bad_Parameter_Exception for run
--  parameters out of range ("RunParams.NumBins must be in 1 .. 65536").

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Images;
with AMV.Kernels;
with AMV.Kernels.Histogram;
with AMV.Shapes.Region_Holders;
with AMV.Tools;

private with AMV.Shared_Handles;

package AMV.Image_Processing.Histogram is

   ---------------------------------------------------------------------
   --  Run parameters (CogHistogram)
   ---------------------------------------------------------------------

   subtype Ks_Histogram_Bin_Mode_Constants is AMV.Kernels.Int32 range 1 .. 3;
   --  CogHistogramBinModeConstants, with VisionPro's values. The run
   --  parameter record is the kernel's C record, so its Bin_Mode holds one
   --  of these codes: Tool.Run_Params.Bin_Mode := Uniform;

   Compatibility : constant Ks_Histogram_Bin_Mode_Constants :=
     AMV.Kernels.Histogram.Bin_Mode_Compatibility;
   --  Num_Bins bins; grey levels >= Num_Bins - 1 go into the last one.
   Uniform : constant Ks_Histogram_Bin_Mode_Constants :=
     AMV.Kernels.Histogram.Bin_Mode_Uniform;
   --  Num_Bins (at most 256) bins of equal width over 0 .. 255.
   Auto : constant Ks_Histogram_Bin_Mode_Constants :=
     AMV.Kernels.Histogram.Bin_Mode_Auto;
   --  One bin per grey level (256), Num_Bins ignored. The default.

   subtype Ks_Histogram is AMV.Kernels.Histogram.Ks_Histogram;
   --  The run parameters (CogHistogram): a record with the components
   --  Bin_Mode (default Auto) and Num_Bins (default 256, 1 .. 65536).

   ---------------------------------------------------------------------
   --  The result (CogHistogramResult)
   ---------------------------------------------------------------------

   type Ks_Histogram_Result is tagged private;
   --  The result of the last successful run, shared by copies (read-only
   --  by convention). A tool that has not run, or whose last run failed,
   --  has no result: its functions then raise Ks_Exception ("Result: the
   --  histogram tool has no result").

   function Num_Samples (Result : Ks_Histogram_Result) return Natural;
   --  The number of pixels counted.

   function Mean (Result : Ks_Histogram_Result) return Real;
   function Standard_Deviation (Result : Ks_Histogram_Result) return Real;
   function Variance (Result : Ks_Histogram_Result) return Real;
   --  The mean grey level, the population variance (mean squared
   --  difference from the mean) and its square root.

   function Minimum (Result : Ks_Histogram_Result) return Natural;
   function Maximum (Result : Ks_Histogram_Result) return Natural;
   --  The smallest and the largest grey level counted.

   function Median (Result : Ks_Histogram_Result) return Natural;
   --  Get_Inverse_Cumulative_Grey_Level (Result, 50).

   function Mode (Result : Ks_Histogram_Result) return Natural;
   --  The most frequent grey level (the smallest one on a tie).

   subtype Ks_Histogram_Array is AMV.Kernels.Histogram.Histogram_Counts;
   --  An array (Natural range <>) of Natural.

   function Get_Histogram (Result : Ks_Histogram_Result)
      return Ks_Histogram_Array;
   --  The count of every bin, indexed from 0 (256 bins in Auto mode,
   --  Num_Bins otherwise).

   function Get_Inverse_Cumulative_Grey_Level
     (Result  : Ks_Histogram_Result;
      Percent : Integer) return Natural;
   --  The smallest grey level L such that at least Percent percent of the
   --  samples are <= L (0 without samples). Percent must be in 0 .. 100
   --  (Ks_Bad_Parameter_Exception otherwise).

   function Get_Minimum_WGV_Threshold
     (Result : Ks_Histogram_Result) return Natural;
   --  The threshold T that minimises the within-group variance of the
   --  samples < T and >= T (Otsu's method, AMV.Kernels.Otsu; the same
   --  threshold as the Blob tool's Hard_Dynamic_Threshold): in 1 .. 255,
   --  Minimum when the samples hold one grey level, 0 without samples.

   ---------------------------------------------------------------------
   --  The tool (CogHistogramTool)
   ---------------------------------------------------------------------

   Pixel_Aligned_Bounding_Box_Adjust_Mask : constant AMV.Kernels.Int32 := 0;
   Pixel_Aligned_Bounding_Box             : constant AMV.Kernels.Int32 := 1;
   Affine_Transform                       : constant AMV.Kernels.Int32 := 2;
   --  The codes of Region_Mode (CogRegionModeConstants, VisionPro's
   --  values).

   type Ks_Histogram_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image               : AMV.Images.Ks_Image_8_Grey;
      Region                    : AMV.Shapes.Region_Holders.Holder;
      --  Empty: the whole image.
      Run_Params                : Ks_Histogram;
      Input_Image_Mask          : AMV.Images.Ks_Image_8_Grey;
      --  Unallocated (the default): no mask.
      Input_Image_Mask_Offset_X : Integer := 0;
      Input_Image_Mask_Offset_Y : Integer := 0;
      --  Where the mask lies over Input_Image (see above).
      Region_Mode               : AMV.Kernels.Int32 :=
        Pixel_Aligned_Bounding_Box_Adjust_Mask;
      --  CogHistogram.RegionMode (see above).
      Result                    : Ks_Histogram_Result;
      --  Set by Run.
   end record;

   overriding procedure Execute (Tool : in out Ks_Histogram_Tool);
   overriding procedure Reset_Results (Tool : in out Ks_Histogram_Tool);

private

   procedure Destroy
     (Handle : in out AMV.Kernels.Histogram.Ks_Histogram_Result);
   --  Frees a result handle (for the holder).

   package Result_Holders is new AMV.Shared_Handles
     (AMV.Kernels.Histogram.Ks_Histogram_Result, null, Destroy);

   type Ks_Histogram_Result is tagged record
      Holder : Result_Holders.Holder;
   end record;

end AMV.Image_Processing.Histogram;
