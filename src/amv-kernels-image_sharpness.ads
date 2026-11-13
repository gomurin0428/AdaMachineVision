--  Kernel of AMV.Image_Processing.Sharpness: the image sharpness tool
--  (CogImageSharpnessTool, whose run parameters are a CogImageSharpness
--  and whose result is its Score). The C API is declared in
--  include/amv_image_processing.h.
--
--  Execute measures how sharp the pixels of a region are (the region is a
--  pixel region handle of AMV.Kernels.Regions; the Ada API passes the whole
--  image for an empty Region). The score is only comparable with scores of
--  the same mode on similar image content; larger is sharper. Modes
--  (CogImageSharpnessModeConstants, the C codes are VisionPro's values):
--
--  * GradientEnergy (8, AMV's default): the mean over the region pixels of
--    Dx**2 + Dy**2, where Dx, Dy are the 3 x 3 Sobel derivatives of
--    ks_real_image_sobel (grey levels per pixel) of the whole image, after
--    a Gaussian smoothing with Sigma = GradientEnergyLowPassSmoothing
--    pixels when that is positive (ks_real_image_gaussian_smooth; 0, the
--    default, smooths nothing). Score in [0, 2 * 127.5**2 = 32512.5].
--  * AbsDiff (2): the mean of abs (I (X + AbsDiffDistanceX, Y +
--    AbsDiffDistanceY) - I (X, Y)) over the region pixels (X, Y) whose
--    partner lies in the image (the partner need not be in the region).
--    Score in [0, 255]. Each distance must be >= 0 and smaller than the
--    image's size along its axis.
--  * AutoCorrelation (1) and BandPass (4) are not implemented: Execute
--    fails with Bad_Parameter. (VisionPro's default mode is BandPass; AMV's
--    default is GradientEnergy.) Their parameters are still checked.
--
--  Without samples (a null region, the empty region, or no region pixel
--  with a partner in the image) the score is 0. Pixels of the region
--  outside the image are ignored.
--
--  Proved (docs/PROOF.md): absence of run-time errors for any handles and
--  parameters, including non-finite values; no memory leaks; the score is
--  finite, >= 0 and within the bound of its mode.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Images;
with AMV.Kernels.Regions;

package AMV.Kernels.Image_Sharpness with SPARK_Mode, Preelaborate is

   package KI renames AMV.Kernels.Images;
   package KR renames AMV.Kernels.Regions;

   ---------------------------------------------------------------------
   --  Run parameters (CogImageSharpness; C: ks_image_sharpness)
   ---------------------------------------------------------------------

   Mode_Auto_Correlation : constant Int32 := 1;
   Mode_Abs_Diff         : constant Int32 := 2;
   Mode_Band_Pass        : constant Int32 := 4;
   Mode_Gradient_Energy  : constant Int32 := 8;
   --  CogImageSharpnessModeConstants (C: KS_IMAGE_SHARPNESS_MODE_*).

   Max_Low_Pass_Smoothing : constant := 100;
   --  The largest GradientEnergyLowPassSmoothing (C:
   --  KS_IMAGE_SHARPNESS_MAX_LOW_PASS_SMOOTHING).

   Max_Noise_Level : constant := 255.0;
   --  The largest AutoCorrelationNoiseLevel (a grey level variation).

   Max_Gradient_Energy : constant := 32_512.5;
   --  2 * 127.5**2: the largest GradientEnergy score (Dx and Dy of grey
   --  levels 0 .. 255 are at most 127.5 in magnitude).

   type Ks_Image_Sharpness is record
      Mode                               : Int32 := Mode_Gradient_Energy;
      Abs_Diff_Distance_X                : Int32 := 1;
      Abs_Diff_Distance_Y                : Int32 := 1;
      Gradient_Energy_Low_Pass_Smoothing : Int32 := 0;
      Auto_Correlation_Noise_Level       : Long_Float := 0.0;
      Band_Pass_Max_Frequency            : Long_Float := 0.45;
      Band_Pass_Min_Frequency            : Long_Float := 0.25;
   end record
     with Convention => C;
   --  C: ks_image_sharpness, with VisionPro's defaults except Mode.

   for Ks_Image_Sharpness use record
      Mode                               at 0 range 0 .. 31;
      Abs_Diff_Distance_X                at 4 range 0 .. 31;
      Abs_Diff_Distance_Y                at 8 range 0 .. 31;
      Gradient_Energy_Low_Pass_Smoothing at 12 range 0 .. 31;
      Auto_Correlation_Noise_Level       at 16 range 0 .. 63;
      Band_Pass_Max_Frequency            at 24 range 0 .. 63;
      Band_Pass_Min_Frequency            at 32 range 0 .. 63;
   end record;

   procedure Run_Params_Default (Params : out Ks_Image_Sharpness)
   with
     Export, Convention => C,
     External_Name => "ks_image_sharpness_run_params_default",
     Post => Params = (others => <>);
   --  The default run parameters. Cannot fail.

   ---------------------------------------------------------------------
   --  Entry point
   ---------------------------------------------------------------------

   procedure Execute
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Params : Ks_Image_Sharpness;
      Score  : out Long_Float;
      Status : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_image_sharpness_execute",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then KI.Valid_Image (Image)
                     and then Params.Mode
                                in Mode_Abs_Diff | Mode_Gradient_Energy
                     and then Score >= 0.0
                     and then Score <= Max_Gradient_Energy
                     and then (if Params.Mode = Mode_Abs_Diff
                               then Score <= 255.0)
                else Score = 0.0);
   --  The score (see above). The checks, in order: the image
   --  (Image_No_Pixels "InputImage has no pixels", Bad_Parameter
   --  "InputImage is not a valid image handle"), the region (Bad_Parameter
   --  "Region is not a valid pixel region handle"), the parameters
   --  (Bad_Parameter: "RunParams.Mode must be AutoCorrelation (1), AbsDiff
   --  (2), BandPass (4) or GradientEnergy (8)", "RunParams.AbsDiffDistanceX
   --  must be >= 0" (and Y), "RunParams.GradientEnergyLowPassSmoothing must
   --  be in 0 .. 100", "RunParams.AutoCorrelationNoiseLevel must be in
   --  0 .. 255", "RunParams.BandPassMaxFrequency must be in 0 .. 0.5" (and
   --  Min), "RunParams.BandPassMinFrequency must not exceed
   --  BandPassMaxFrequency"), the mode ("RunParams.Mode: AutoCorrelation is
   --  not implemented", likewise BandPass), the distances of AbsDiff
   --  ("RunParams.AbsDiffDistanceX must be less than the width of
   --  InputImage", likewise Y and the height), then Out_Of_Memory. Score is
   --  0 when the call fails.

   ---------------------------------------------------------------------
   --  For the Ada API only (not exported)
   ---------------------------------------------------------------------

   procedure Check_Input_Image
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Image_No_Pixels
                            | Failure_Bad_Parameter;
   --  The image check of Execute, made by the Ada API before it
   --  rasterises the region.

end AMV.Kernels.Image_Sharpness;
