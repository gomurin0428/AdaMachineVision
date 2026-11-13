--  The region modes of the histogram tool (CogHistogram.RegionMode,
--  CogRegionModeConstants): which pixels of the input image are the
--  samples.
--
--  * Pixel_Aligned_Bounding_Box_Adjust_Mask (0, VisionPro's default): the
--    pixels the region covers (AMV.Kernels.Histogram.Execute with the
--    rasterised region).
--  * Pixel_Aligned_Bounding_Box (1): every pixel of the region's
--    pixel-aligned bounding box, whatever the region's shape
--    (AMV.Kernels.Histogram.Execute with AMV.Kernels.Regions.Bounding_Box
--    of the rasterised region).
--  * Affine_Transform (2): the region is an affine rectangle; the samples
--    are the pixels of that rectangle resampled into an upright image by
--    AMV.Kernels.Affine_Transform with that kernel's default run
--    parameters (one output pixel per input pixel along each side;
--    samples outside the image are 0), every pixel of it (Execute_Affine).
--
--  VisionPro's reference states the default (AdjustMask) and that the
--  property accepts AffineTransform and PixelAlignedBoundingBox; AMV
--  accepts all three codes. The input image mask applies to the samples
--  of the first two modes (after the bounding box is taken); with
--  Affine_Transform it is rejected (AMV's choice: the mask lies over the
--  input image, not over the resampled one). An empty region (the whole
--  image) gives the same samples in every mode.
--
--  Proved (docs/PROOF.md): absence of run-time errors for any image
--  handle that is null or came from the kernels and any parameters; no
--  memory leaks; the result of Execute_Affine is a valid histogram.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Shapes;
with AMV.Kernels.Transforms;

package AMV.Kernels.Histogram.Region_Modes
  with SPARK_Mode, Preelaborate
is

   package KS renames AMV.Kernels.Shapes;
   package KT renames AMV.Kernels.Transforms;

   Region_Mode_Pixel_Aligned_Bounding_Box_Adjust_Mask : constant Int32 := 0;
   Region_Mode_Pixel_Aligned_Bounding_Box             : constant Int32 := 1;
   Region_Mode_Affine_Transform                       : constant Int32 := 2;
   --  CogRegionModeConstants (VisionPro's values).

   ---------------------------------------------------------------------
   --  For the Ada API only (not exported)
   ---------------------------------------------------------------------

   procedure Check_Region_Mode
     (Mode       : Int32;
      Has_Region : Int32;
      Kind       : Int32;
      Masked     : Int32;
      Status     : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then
               (if Succeeded (Status)
                then Mode in Region_Mode_Pixel_Aligned_Bounding_Box_Adjust_Mask
                          .. Region_Mode_Affine_Transform
                     and then
                       (if Mode = Region_Mode_Affine_Transform
                          and then Has_Region = True_Value
                        then Kind = KS.Shape_Rectangle_Affine
                             and then Masked = False_Value));
   --  The checks of the tool's RegionMode: Bad_Parameter "RegionMode must
   --  be PixelAlignedBoundingBoxAdjustMask (0), PixelAlignedBoundingBox
   --  (1) or AffineTransform (2)"; with Affine_Transform and a region
   --  (Has_Region = 1) of shape code Kind, "Region must be an affine
   --  rectangle for RegionMode AffineTransform" unless Kind is
   --  KS.Shape_Rectangle_Affine, then "InputImageMask is not supported
   --  with RegionMode AffineTransform" when Masked = 1.

   ---------------------------------------------------------------------
   --  Entry point
   ---------------------------------------------------------------------

   procedure Execute_Affine
     (Image             : access constant KI.Ks_Image_8_Grey_Data;
      Region            : KS.Ks_Rectangle_Affine;
      Pixel_From_Region : KT.Ks_Transform_2D_Linear;
      Params            : Ks_Histogram;
      Result            : out Ks_Histogram_Result;
      Status            : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_histogram_execute_affine",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Transform_Singular
                         | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then KI.Valid_Image (Image)
                     and then Valid_Params (Params)
                     and then Valid_Result (Result)
                     and then KS.Valid_Rectangle_Affine (Region)
                     and then KT.Bounded (Pixel_From_Region)
                else Result = null);
   --  The histogram (mode Affine_Transform, see above) of the affine
   --  rectangle Region (in the space Pixel_From_Region maps to pixel
   --  coordinates) resampled upright. The checks, in order: the image
   --  (those of Execute), the parameters (those of Execute), then those of
   --  AMV.Kernels.Affine_Transform.Execute (the rectangle, the transform,
   --  the size of the resampled image) and Out_Of_Memory. Result is null
   --  when the call fails.

end AMV.Kernels.Histogram.Region_Modes;
