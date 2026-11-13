--  The affine transform tool: the counterpart of CogAffineTransformTool and
--  its run parameters CogAffineTransform
--  (Cognex.VisionPro.ImageProcessing).
--
--     Tool.Input_Image := Image;
--     Tool.Region.Set_Center_Lengths_Rotation_Skew
--       (100.0, 80.0, 60.0, 40.0, 0.3, 0.0);
--     Tool.Run_Params.Scaling_X := 2.0;
--     Tool.Run;
--     Out := Tool.Output_Image;
--
--  Output_Image is the parallelogram Region of Input_Image resampled into
--  an upright image: output x runs along the region's side X, output y
--  along its side Y. Its size is round (Scaling_X * L_X) by
--  round (Scaling_Y * L_Y), L_X and L_Y the lengths of the two sides in
--  input pixels (so the default scalings, 1.0, keep the pixel size). The
--  output keeps the input's coordinate space tree and selected space, and
--  gets a pixel-from-root transform such that every space of the tree
--  names the same physical places in both images: a position measured in
--  "." on the output is the same position on the input. Sample points
--  outside the input are clipped (Clip_Mode: Zeroes gives 0, Fill gives
--  Clip_Fill_Value, Error fails the run). With Create_Output_Image_Mask,
--  Output_Image_Mask is 255 where the output was sampled from the input
--  and 0 where it was clipped.
--
--  The work is done by the SPARK kernel AMV.Kernels.Affine_Transform (C:
--  ks_affine_transform_*, include/amv_ip_geometry.h), whose spec
--  describes the sampling in detail.
--
--  Run fails (Run_Status Error, outputs unallocated) with
--  Ks_Image_No_Pixels_Exception for an unallocated Input_Image ("InputImage
--  has no pixels"), Ks_Image_Bad_Selected_Space_Name_Exception for a region
--  in an unknown space, Ks_Bad_Parameter_Exception for run parameters out
--  of range ("RunParams.ScalingX must be in 0.001 .. 1000"), an output
--  below 1 or above 32767 pixels along an axis, and clipping with
--  Clip_Mode Error, and Ks_Transform_Singular_Exception for a region too
--  flat to relate the output to the input.

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Images;
with AMV.Kernels;
with AMV.Kernels.Affine_Transform;
with AMV.Shapes;
with AMV.Tools;

package AMV.Image_Processing.Affine_Transform is

   ---------------------------------------------------------------------
   --  Run parameters (CogAffineTransform)
   ---------------------------------------------------------------------

   subtype Ks_Affine_Transform_Sampling_Mode_Constants is
     AMV.Kernels.Int32 range 1 .. 4;
   --  CogAffineTransformSamplingModeConstants, with VisionPro's values.

   Nearest_Neighbor : constant Ks_Affine_Transform_Sampling_Mode_Constants :=
     AMV.Kernels.Affine_Transform.Sampling_Mode_Nearest_Neighbor;
   --  AMV's addition: the nearest input pixel.
   Bilinear_Interpolation :
     constant Ks_Affine_Transform_Sampling_Mode_Constants :=
       AMV.Kernels.Affine_Transform.Sampling_Mode_Bilinear_Interpolation;
   High_Precision : constant Ks_Affine_Transform_Sampling_Mode_Constants :=
     AMV.Kernels.Affine_Transform.Sampling_Mode_High_Precision;
   --  Not implemented (Run fails with Ks_Bad_Parameter_Exception).
   Bilinear_Accurate : constant Ks_Affine_Transform_Sampling_Mode_Constants :=
     AMV.Kernels.Affine_Transform.Sampling_Mode_Bilinear_Accurate;
   --  The default. Both bilinear modes interpolate between the four
   --  nearest pixel centres.

   subtype Ks_Affine_Transform_Clip_Mode_Constants is
     AMV.Kernels.Int32 range 0 .. 2;
   --  CogAffineTransformClipModeConstants, with VisionPro's values.

   Zeroes : constant Ks_Affine_Transform_Clip_Mode_Constants :=
     AMV.Kernels.Affine_Transform.Clip_Mode_Zeroes;
   Fill   : constant Ks_Affine_Transform_Clip_Mode_Constants :=
     AMV.Kernels.Affine_Transform.Clip_Mode_Fill;
   Error  : constant Ks_Affine_Transform_Clip_Mode_Constants :=
     AMV.Kernels.Affine_Transform.Clip_Mode_Error;
   --  Clipped output pixels become 0 (Zeroes, the default) or
   --  Clip_Fill_Value (Fill), or fail the run (Error). These names are
   --  VisionPro's; Error and Fill clash with AMV.Tools.Error and
   --  AMV.Images.Fill when all are use-visible, so prefix them then.

   subtype Ks_Affine_Transform is AMV.Kernels.Affine_Transform.Ks_Affine_Transform;
   --  The run parameters (CogAffineTransform), a record with VisionPro's
   --  defaults: Scaling_X and Scaling_Y (1.0, in 0.001 .. 1000),
   --  Sampling_Mode (Bilinear_Accurate), Clip_Mode (Zeroes) and
   --  Clip_Fill_Value (0, in 0 .. 255). Values are checked when the tool
   --  runs.

   ---------------------------------------------------------------------
   --  The tool (CogAffineTransformTool)
   ---------------------------------------------------------------------

   type Ks_Affine_Transform_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image              : AMV.Images.Ks_Image_8_Grey;
      Region                   : AMV.Shapes.Ks_Rectangle_Affine;
      --  In its selected space (default "."); VisionPro's null region
      --  (the whole image) has no counterpart.
      Run_Params               : Ks_Affine_Transform;
      Create_Output_Image_Mask : Boolean := False;
      Output_Image             : AMV.Images.Ks_Image_8_Grey;
      Output_Image_Mask        : AMV.Images.Ks_Image_8_Grey;
      --  Set by Run (read-only by convention); unallocated after a run
      --  that failed, and the mask also when it was not asked for.
   end record;

   overriding procedure Execute (Tool : in out Ks_Affine_Transform_Tool);
   overriding procedure Reset_Results
     (Tool : in out Ks_Affine_Transform_Tool);

end AMV.Image_Processing.Affine_Transform;
