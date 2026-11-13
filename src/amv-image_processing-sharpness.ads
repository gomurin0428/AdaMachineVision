--  The image sharpness tool: the counterpart of CogImageSharpnessTool and
--  its run parameters CogImageSharpness (Cognex.VisionPro.ImageProcessing).
--
--     Tool.Input_Image := Image;
--     Tool.Run;
--     if Tool.Score > Best then ...
--
--  Score measures how sharp the pixels the Region covers are
--  (AMV.Regions.Rasterize; an empty Region holder means the whole image);
--  larger is sharper. Scores are only comparable for one mode and similar
--  image content. Modes: GradientEnergy (AMV's default), the mean squared
--  Sobel gradient (grey levels per pixel) after an optional Gaussian
--  smoothing of Sigma = Gradient_Energy_Low_Pass_Smoothing pixels, in
--  [0, 32512.5]; AbsDiff, the mean absolute difference between a pixel and
--  the pixel (Abs_Diff_Distance_X, Abs_Diff_Distance_Y) away, in [0, 255].
--  AutoCorrelation and BandPass (VisionPro's default) are not implemented:
--  Run fails with Ks_Bad_Parameter_Exception. A region that covers no
--  pixel centre gives Score 0 (no exception).
--
--  The work is done by the SPARK kernel AMV.Kernels.Image_Sharpness (C:
--  ks_image_sharpness_*, include/amv_image_processing.h), which proves the
--  score finite and within the bounds above.
--
--  Run fails (Run_Status Error, Score 0) with Ks_Image_No_Pixels_Exception
--  for an unallocated Input_Image ("InputImage has no pixels"),
--  Ks_Image_Bad_Selected_Space_Name_Exception for a region in an unknown
--  space, and Ks_Bad_Parameter_Exception for run parameters out of range
--  ("RunParams.GradientEnergyLowPassSmoothing must be in 0 .. 100").

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Images;
with AMV.Kernels;
with AMV.Kernels.Image_Sharpness;
with AMV.Shapes.Region_Holders;
with AMV.Tools;

package AMV.Image_Processing.Sharpness is

   subtype Ks_Image_Sharpness_Mode_Constants is AMV.Kernels.Int32
     with Static_Predicate =>
       Ks_Image_Sharpness_Mode_Constants in 1 | 2 | 4 | 8;
   --  CogImageSharpnessModeConstants, with VisionPro's values. The run
   --  parameter record is the kernel's C record, so its Mode holds one of
   --  these codes: Tool.Run_Params.Mode := Abs_Diff;

   Auto_Correlation : constant Ks_Image_Sharpness_Mode_Constants :=
     AMV.Kernels.Image_Sharpness.Mode_Auto_Correlation;
   --  Not implemented.
   Abs_Diff : constant Ks_Image_Sharpness_Mode_Constants :=
     AMV.Kernels.Image_Sharpness.Mode_Abs_Diff;
   Band_Pass : constant Ks_Image_Sharpness_Mode_Constants :=
     AMV.Kernels.Image_Sharpness.Mode_Band_Pass;
   --  Not implemented.
   Gradient_Energy : constant Ks_Image_Sharpness_Mode_Constants :=
     AMV.Kernels.Image_Sharpness.Mode_Gradient_Energy;

   subtype Ks_Image_Sharpness is
     AMV.Kernels.Image_Sharpness.Ks_Image_Sharpness;
   --  The run parameters (CogImageSharpness), a record with the components
   --  Mode (Gradient_Energy), Abs_Diff_Distance_X (1), Abs_Diff_Distance_Y
   --  (1), Gradient_Energy_Low_Pass_Smoothing (0, 0 .. 100),
   --  Auto_Correlation_Noise_Level (0.0, 0 .. 255), Band_Pass_Max_Frequency
   --  (0.45) and Band_Pass_Min_Frequency (0.25, both in 0 .. 0.5).

   type Ks_Image_Sharpness_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image : AMV.Images.Ks_Image_8_Grey;
      Region      : AMV.Shapes.Region_Holders.Holder;
      --  Empty: the whole image.
      Run_Params  : Ks_Image_Sharpness;
      Score       : Real := 0.0;
      --  Set by Run (read-only by convention); 0 after a run that failed.
   end record;

   overriding procedure Execute (Tool : in out Ks_Image_Sharpness_Tool);
   overriding procedure Reset_Results
     (Tool : in out Ks_Image_Sharpness_Tool);

private

   No_Score : constant Real := 0.0;

end AMV.Image_Processing.Sharpness;
