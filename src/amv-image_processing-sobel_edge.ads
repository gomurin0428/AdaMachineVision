--  The Sobel edge tool: the counterpart of CogSobelEdgeTool, its run
--  parameters CogSobelEdge and its result CogSobelEdgeResult
--  (Cognex.VisionPro.ImageProcessing).
--
--     Tool.Input_Image := Image;
--     Tool.Run_Params.Post_Process_Mode := Peak_Detect;
--     Tool.Run;
--     Edges := Tool.Result.Final_Magnitude_Image;
--
--  The result holds three images of the size of Input_Image, each with its
--  coordinate space tree, selected space and pixel-from-root transform:
--  the edge magnitude (MagnitudeScale times the grey level difference
--  across the edge, clamped to 255), the edge angle (the gradient
--  direction as a binary angle, 256 steps per turn, 0 along +x, 64 along
--  +y) and the final magnitude (the magnitude after the post-processing
--  PostProcessMode selects). An empty Region holder means the whole
--  image. Otherwise Run_Params.Region_Mode (CogSobelEdge.RegionMode)
--  selects the part of the image processed, and the three images are that
--  part only (AMV.Kernels.Sobel_Edge.Region_Modes describes it in detail):
--  * Pixel_Aligned_Bounding_Box (the default, as in VisionPro): the
--    bounding box of the pixels AMV.Regions.Rasterize gives for Region,
--    whatever its shape; every pixel of the box is processed, as if the
--    box were the input image.
--  * Affine_Transform: Region must be a Ks_Rectangle_Affine; it is
--    resampled into an upright image (one output pixel per input pixel
--    along each side, as AMV.Image_Processing.Affine_Transform does with
--    its default run parameters), which is processed.
--  The images keep the input's coordinate space tree and selected space,
--  with a pixel-from-root transform that names the same physical places
--  as in the input image.
--
--  The work is done by the SPARK kernel AMV.Kernels.Sobel_Edge (C:
--  ks_sobel_edge_*, include/amv_image_processing.h), whose spec describes
--  the gradients, the angle encoding and the post-processing in detail.
--
--  Run fails (Run_Status Error, results cleared) with
--  Ks_Image_No_Pixels_Exception for an unallocated Input_Image ("InputImage
--  has no pixels"), Ks_Image_Bad_Selected_Space_Name_Exception for a
--  region in an unknown space, Ks_Bad_Parameter_Exception for run
--  parameters out of range ("RunParams.MagnitudeScale must be in 0 ..
--  50", "RunParams.RegionMode must be PixelAlignedBoundingBox (1) or
--  AffineTransform (2)"), a region that covers no pixel of the image and
--  a region other than a Ks_Rectangle_Affine with Affine_Transform, and
--  Ks_Transform_Singular_Exception for a rectangle too flat to resample.

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Images;
with AMV.Kernels;
with AMV.Kernels.Sobel_Edge;
with AMV.Shapes.Region_Holders;
with AMV.Tools;

package AMV.Image_Processing.Sobel_Edge is

   ---------------------------------------------------------------------
   --  Run parameters (CogSobelEdge)
   ---------------------------------------------------------------------

   subtype Ks_Sobel_Edge_Post_Process_Mode_Constants is
     AMV.Kernels.Int32 range 0 .. 2;
   --  CogSobelEdgePostProcessModeConstants, with VisionPro's values. The
   --  run parameter record is the kernel's C record, so its
   --  Post_Process_Mode holds one of these codes.

   None : constant Ks_Sobel_Edge_Post_Process_Mode_Constants :=
     AMV.Kernels.Sobel_Edge.Post_Process_None;
   --  No post-processing: the final image is the magnitude image.
   Peak_Detect : constant Ks_Sobel_Edge_Post_Process_Mode_Constants :=
     AMV.Kernels.Sobel_Edge.Post_Process_Peak_Detect;
   --  Whole-pixel non-maximum suppression along the gradient.
   Hysteresis_Threshold : constant Ks_Sobel_Edge_Post_Process_Mode_Constants
     := AMV.Kernels.Sobel_Edge.Post_Process_Hysteresis_Threshold;
   --  Hysteresis thresholding with 8-connectivity.

   subtype Ks_Region_Mode_Constants is AMV.Kernels.Int32 range 0 .. 2;
   --  CogRegionModeConstants (Cognex.VisionPro), with VisionPro's values;
   --  the Sobel edge tool accepts the two below.

   Pixel_Aligned_Bounding_Box : constant Ks_Region_Mode_Constants :=
     AMV.Kernels.Sobel_Edge.Region_Mode_Pixel_Aligned_Bounding_Box;
   --  The default: every pixel of the region's box is processed.
   Affine_Transform : constant Ks_Region_Mode_Constants :=
     AMV.Kernels.Sobel_Edge.Region_Mode_Affine_Transform;
   --  The affine rectangle Region resampled into an upright image.

   subtype Ks_Sobel_Edge is AMV.Kernels.Sobel_Edge.Ks_Sobel_Edge;
   --  The run parameters (CogSobelEdge), a record with VisionPro's
   --  defaults: Magnitude_Scale (1.0, 0 .. 50), Post_Process_Mode (None),
   --  Peak_Detect_Threshold (20), Hysteresis_Threshold_Low (10),
   --  Hysteresis_Threshold_High (20), Hysteresis_Survivor_Pel_Value (255)
   --  and Hysteresis_Non_Survivor_Pel_Value (0), the integers in 0 .. 255,
   --  and Region_Mode (Pixel_Aligned_Bounding_Box).
   --  Unlike VisionPro's coupled properties, the two thresholds are
   --  independent components; Run requires High >= Low.

   procedure Set_Hysteresis_Thresholds
     (Params                    : in out Ks_Sobel_Edge;
      Hysteresis_Threshold_Low  : Integer;
      Hysteresis_Threshold_High : Integer);
   --  Sets both thresholds (VisionPro: SetHysteresisThresholds). They are
   --  checked when the tool runs.

   ---------------------------------------------------------------------
   --  The result (CogSobelEdgeResult)
   ---------------------------------------------------------------------

   type Ks_Sobel_Edge_Result is tagged private;
   --  The images of the last successful run (unallocated images when the
   --  tool has not run or its last run failed). Copies share the pixels.

   function Edge_Magnitude_Image
     (Result : Ks_Sobel_Edge_Result) return AMV.Images.Ks_Image_8_Grey;
   function Edge_Angle_Image
     (Result : Ks_Sobel_Edge_Result) return AMV.Images.Ks_Image_8_Grey;
   function Final_Magnitude_Image
     (Result : Ks_Sobel_Edge_Result) return AMV.Images.Ks_Image_8_Grey;

   ---------------------------------------------------------------------
   --  The tool (CogSobelEdgeTool)
   ---------------------------------------------------------------------

   type Ks_Sobel_Edge_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image : AMV.Images.Ks_Image_8_Grey;
      Region      : AMV.Shapes.Region_Holders.Holder;
      --  Empty: the whole image.
      Run_Params  : Ks_Sobel_Edge;
      Result      : Ks_Sobel_Edge_Result;
      --  Set by Run.
   end record;

   overriding procedure Execute (Tool : in out Ks_Sobel_Edge_Tool);
   overriding procedure Reset_Results (Tool : in out Ks_Sobel_Edge_Tool);

private

   type Ks_Sobel_Edge_Result is tagged record
      Edge_Magnitude  : AMV.Images.Ks_Image_8_Grey;
      Edge_Angle      : AMV.Images.Ks_Image_8_Grey;
      Final_Magnitude : AMV.Images.Ks_Image_8_Grey;
   end record;

end AMV.Image_Processing.Sobel_Edge;
