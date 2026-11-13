--  Kernel of AMV.Image_Processing.Sobel_Edge: the Sobel edge tool
--  (CogSobelEdgeTool, whose run parameters are a CogSobelEdge and whose
--  result is a CogSobelEdgeResult). The C API is declared in
--  include/amv_image_processing.h.
--
--  Execute makes three new 8-bit images of the size of the input image
--  (VisionPro: EdgeMagnitudeImage, EdgeAngleImage, FinalMagnitudeImage).
--  Only the pixels the region contains are processed (the region is a
--  pixel region handle of AMV.Kernels.Regions; the Ada API passes the
--  whole image for an empty Region); every other pixel is 0 in all three
--  images. A null region (the empty region) gives three images of zeros.
--
--  Gradients. The derivatives Dx, Dy of a region pixel are the 3 x 3 Sobel
--  derivatives of ks_real_image_sobel (AMV.Kernels.Image_Math) of the
--  whole image (its neighbours outside the region count, the image border
--  is replicated), in grey levels per pixel. The edge magnitude is the
--  grey level difference across the edge that the Sobel operator
--  measures, 2 * Sqrt (Dx**2 + Dy**2): a step of height H gives H on the
--  pixels on both sides of it. It is at most 255 * Sqrt (2) (Max_Magnitude
--  bounds it, a bound that never acts).
--
--  * EdgeMagnitudeImage: MagnitudeScale * magnitude, rounded to the
--    nearest integer and clamped to 255 (0.89 keeps every value of an
--    8-bit image below 256, so nothing is clamped).
--  * EdgeAngleImage: the direction of the gradient (towards brighter
--    pixels), measured from the +x axis towards +y (counter-clockwise as
--    seen in a y-down image, docs/DESIGN.md 5), as a binary angle: angle
--    * 256 / (2 Pi) rounded to the nearest integer modulo 256, so 0 is +x,
--    64 is +y (down), 128 is -x and 192 is -y. A pixel without gradient
--    gets 0. (The encoding is AMV's; VisionPro does not document one.)
--  * FinalMagnitudeImage, by PostProcessMode (CogSobelEdgePostProcess-
--    ModeConstants, the C codes are VisionPro's values):
--    - None (0, the default): a copy of EdgeMagnitudeImage.
--    - PeakDetect (1): whole-pixel non-maximum suppression. A region pixel
--      keeps its EdgeMagnitudeImage value M when M >= PeakDetectThreshold,
--      M >= the value of its neighbour against the gradient direction and
--      M > the value of its neighbour along it (the direction rounded to
--      one of 8 neighbours from the angle code; a neighbour outside the
--      image counts as 0); otherwise it is 0. The strict test on one side
--      keeps one pixel of a two-pixel plateau.
--    - HysteresisThreshold (2): a region pixel is a survivor when its
--      EdgeMagnitudeImage value is >= HysteresisThresholdHigh, or >=
--      HysteresisThresholdLow and 8-connected through such pixels of the
--      region to a survivor; survivors get HysteresisSurvivorPelValue,
--      the other region pixels HysteresisNonSurvivorPelValue.
--
--  Proved (docs/PROOF.md): absence of run-time errors for any handles and
--  parameters; no memory leaks; every image within its documented range:
--  every pixel outside the region is 0 in all three images; with None the
--  final image equals the magnitude image; with PeakDetect every final
--  pixel is 0 or the magnitude pixel; with HysteresisThreshold every final
--  pixel of the region is the survivor or the non-survivor value.
--
--  Trusted parts (SPARK_Mode Off bodies, listed in docs/PROOF.md): the
--  allocation of the hysteresis work stack.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Images;
with AMV.Kernels.Regions;

package AMV.Kernels.Sobel_Edge with SPARK_Mode, Preelaborate is

   package KI renames AMV.Kernels.Images;
   package KR renames AMV.Kernels.Regions;

   use type KI.Grey_8;
   use type KI.Grey_8_Matrix;
   use type KI.Ks_Image_8_Grey;

   ---------------------------------------------------------------------
   --  Run parameters (CogSobelEdge; C: ks_sobel_edge)
   ---------------------------------------------------------------------

   Post_Process_None                 : constant Int32 := 0;
   Post_Process_Peak_Detect          : constant Int32 := 1;
   Post_Process_Hysteresis_Threshold : constant Int32 := 2;
   --  CogSobelEdgePostProcessModeConstants (C:
   --  KS_SOBEL_EDGE_POST_PROCESS_MODE_*).

   Max_Magnitude_Scale : constant := 50.0;
   --  The largest MagnitudeScale (C: KS_SOBEL_EDGE_MAX_MAGNITUDE_SCALE).

   Max_Magnitude : constant := 361.0;
   --  Above the largest edge magnitude of an 8-bit image, 255 * Sqrt (2).

   Region_Mode_Pixel_Aligned_Bounding_Box : constant Int32 := 1;
   Region_Mode_Affine_Transform           : constant Int32 := 2;
   --  The CogRegionModeConstants that CogSobelEdge.RegionMode accepts (C:
   --  KS_REGION_MODE_*); PixelAlignedBoundingBoxAdjustMask (0) is not one
   --  of them.

   type Ks_Sobel_Edge is record
      Magnitude_Scale                   : Long_Float := 1.0;
      Post_Process_Mode                 : Int32 := Post_Process_None;
      Peak_Detect_Threshold             : Int32 := 20;
      Hysteresis_Threshold_Low          : Int32 := 10;
      Hysteresis_Threshold_High         : Int32 := 20;
      Hysteresis_Survivor_Pel_Value     : Int32 := 255;
      Hysteresis_Non_Survivor_Pel_Value : Int32 := 0;
      Region_Mode                       : Int32 :=
        Region_Mode_Pixel_Aligned_Bounding_Box;
   end record
     with Convention => C;
   --  C: ks_sobel_edge, with VisionPro's defaults. Region_Mode is read by
   --  the entry points of AMV.Kernels.Sobel_Edge.Region_Modes only; Execute
   --  below ignores it.

   for Ks_Sobel_Edge use record
      Magnitude_Scale                   at 0 range 0 .. 63;
      Post_Process_Mode                 at 8 range 0 .. 31;
      Peak_Detect_Threshold             at 12 range 0 .. 31;
      Hysteresis_Threshold_Low          at 16 range 0 .. 31;
      Hysteresis_Threshold_High         at 20 range 0 .. 31;
      Hysteresis_Survivor_Pel_Value     at 24 range 0 .. 31;
      Hysteresis_Non_Survivor_Pel_Value at 28 range 0 .. 31;
      Region_Mode                       at 32 range 0 .. 31;
   end record;
   for Ks_Sobel_Edge'Size use 40 * 8;
   --  As C pads the struct (its double aligns it on 8 bytes).

   function Valid_Params (Params : Ks_Sobel_Edge) return Boolean is
     (Params.Magnitude_Scale >= 0.0
      and then Params.Magnitude_Scale <= Max_Magnitude_Scale
      and then Params.Post_Process_Mode
                 in Post_Process_None .. Post_Process_Hysteresis_Threshold
      and then Params.Peak_Detect_Threshold in 0 .. 255
      and then Params.Hysteresis_Threshold_Low in 0 .. 255
      and then Params.Hysteresis_Threshold_High
                 in Params.Hysteresis_Threshold_Low .. 255
      and then Params.Hysteresis_Survivor_Pel_Value in 0 .. 255
      and then Params.Hysteresis_Non_Survivor_Pel_Value in 0 .. 255);
   --  Parameters Execute accepts (False for a NaN at run time).

   procedure Run_Params_Default (Params : out Ks_Sobel_Edge)
   with
     Export, Convention => C,
     External_Name => "ks_sobel_edge_run_params_default",
     Post => Params = (others => <>);
   --  The default run parameters. Cannot fail.

   ---------------------------------------------------------------------
   --  Entry point
   ---------------------------------------------------------------------

   function Same_Size
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Output : access constant KI.Ks_Image_8_Grey_Data) return Boolean
   is
     (KI.Valid_Image (Output)
      and then Output.Width = Image.Width
      and then Output.Height = Image.Height)
   with Pre => KI.Valid_Image (Image);
   --  Output is a valid image of the size of Image.

   function Zero_Outside
     (Region : access constant KR.Ks_Pixel_Region_Data;
      Output : access constant KI.Ks_Image_8_Grey_Data) return Boolean
   is
     (for all Y in Output.Pixels'Range (1)
      => (for all X in Output.Pixels'Range (2)
          => (if not KR.Contains (Region, Int32 (X), Int32 (Y))
              then Output.Pixels (Y, X) = 0)))
   with Ghost, Pre => KI.Valid_Image (Output);
   --  Every pixel of Output outside the region is 0.

   procedure Execute
     (Image                 : access constant KI.Ks_Image_8_Grey_Data;
      Region                : access constant KR.Ks_Pixel_Region_Data;
      Params                : Ks_Sobel_Edge;
      Edge_Magnitude_Image  : out KI.Ks_Image_8_Grey;
      Edge_Angle_Image      : out KI.Ks_Image_8_Grey;
      Final_Magnitude_Image : out KI.Ks_Image_8_Grey;
      Status                : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_sobel_edge_execute",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then KI.Valid_Image (Image)
                     and then Valid_Params (Params)
                     and then Same_Size (Image, Edge_Magnitude_Image)
                     and then Same_Size (Image, Edge_Angle_Image)
                     and then Same_Size (Image, Final_Magnitude_Image)
                     and then Zero_Outside (Region, Edge_Magnitude_Image)
                     and then Zero_Outside (Region, Edge_Angle_Image)
                     and then Zero_Outside (Region, Final_Magnitude_Image)
                     and then
                       (if Params.Post_Process_Mode = Post_Process_None
                        then Final_Magnitude_Image.Pixels.all
                               = Edge_Magnitude_Image.Pixels.all)
                     and then
                       (if Params.Post_Process_Mode
                             = Post_Process_Peak_Detect
                        then
                          (for all Y in Final_Magnitude_Image.Pixels'Range (1)
                           => (for all X in
                                 Final_Magnitude_Image.Pixels'Range (2)
                               => Final_Magnitude_Image.Pixels (Y, X) = 0
                                  or else Final_Magnitude_Image.Pixels (Y, X)
                                            = Edge_Magnitude_Image.Pixels
                                                (Y, X))))
                     and then
                       (if Params.Post_Process_Mode
                             = Post_Process_Hysteresis_Threshold
                        then
                          (for all Y in Final_Magnitude_Image.Pixels'Range (1)
                           => (for all X in
                                 Final_Magnitude_Image.Pixels'Range (2)
                               => (if KR.Contains (Region, Int32 (X),
                                                   Int32 (Y))
                                   then Int32 (Final_Magnitude_Image.Pixels
                                                 (Y, X))
                                          in Params
                                               .Hysteresis_Survivor_Pel_Value
                                           | Params
                                               .Hysteresis_Non_Survivor_Pel_Value))))
                else Edge_Magnitude_Image = null
                     and then Edge_Angle_Image = null
                     and then Final_Magnitude_Image = null);
   --  The three images (see above), new handles the caller owns; all null
   --  when the call fails. The checks, in order: the image
   --  (Image_No_Pixels "InputImage has no pixels", Bad_Parameter
   --  "InputImage is not a valid image handle"), the region (Bad_Parameter
   --  "Region is not a valid pixel region handle"), the parameters
   --  (Bad_Parameter: "RunParams.MagnitudeScale must be in 0 .. 50",
   --  "RunParams.PostProcessMode must be None (0), PeakDetect (1) or
   --  HysteresisThreshold (2)", "RunParams.PeakDetectThreshold must be in
   --  0 .. 255", likewise HysteresisThresholdLow, HysteresisThresholdHigh,
   --  HysteresisSurvivorPelValue and HysteresisNonSurvivorPelValue, and
   --  "RunParams.HysteresisThresholdHigh must be >= HysteresisThresholdLow"),
   --  then Out_Of_Memory.

   ---------------------------------------------------------------------
   --  For the Ada API only (not exported)
   ---------------------------------------------------------------------

   procedure Check_Input_Image
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Image_No_Pixels
                            | Failure_Bad_Parameter
                and then (if Succeeded (Status)
                          then KI.Valid_Image (Image));
   --  The image check of Execute, made by the Ada API before it
   --  rasterises the region.

   procedure Check_Run_Params
     (Params : Ks_Sobel_Edge;
      Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure in Failure_None | Failure_Bad_Parameter
                and then (if Succeeded (Status) then Valid_Params (Params));
   --  The parameter checks of Execute, alone (for the region modes).

end AMV.Kernels.Sobel_Edge;
