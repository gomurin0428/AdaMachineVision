--  Kernel of AMV.Image_Processing.Affine_Transform: the affine transform
--  tool (CogAffineTransformTool, whose run parameters are a
--  CogAffineTransform). The C API is declared in include/amv_ip_geometry.h.
--
--  Execute resamples the parallelogram Region (a CogRectangleAffine) of an
--  8-bit image into a new upright image: output x runs along the region's
--  side X (from its corner origin to its corner X), output y along side Y.
--  The output size follows from the lengths of the two sides measured in
--  input pixels and the scalings: Width = round (ScalingX * L_X) and
--  Height = round (ScalingY * L_Y) (halves away from zero), where L_X is
--  the length of side X after it is mapped into pixel space by
--  Pixel_From_Region (and L_Y that of side Y). A size below 1 or above
--  Max_Output_Side (32767) fails with Bad_Parameter, as VisionPro rejects
--  such outputs. The output pixels tile the region: output pixel (I, J)
--  covers the part of the region whose child coordinates (see
--  ks_rectangle_affine_get_parent_from_child_transform) lie in
--  [I, I + 1] * Side_X_Length / Width by [J, J + 1] * Side_Y_Length /
--  Height, and samples the input at the centre of that part.
--
--  Sampling (SamplingMode, CogAffineTransformSamplingModeConstants with
--  VisionPro's values): BilinearInterpolation (2) and BilinearAccurate (4,
--  the default) both interpolate bilinearly between the four nearest pixel
--  centres; NearestNeighbor (1) is an AMV addition (VisionPro has no such
--  mode for this tool) that copies the nearest input pixel; HighPrecision
--  (3) is not implemented (Bad_Parameter). A sample point outside the area
--  the input pixels cover ([-0.5, Width - 0.5] x [-0.5, Height - 0.5]) is
--  clipped (ClipMode, CogAffineTransformClipModeConstants): Zeroes (0, the
--  default) gives 0, Fill (1) gives ClipFillValue, and Error (2) fails the
--  run with Bad_Parameter when any output pixel is clipped. Within the
--  outer half pixel the border pixels are repeated (the sampling rules of
--  AMV.Kernels.Image_Sampling).
--
--  Coordinates. The output gets the input's coordinate space tree and
--  selected space (the Ada API copies them) and the pixel-from-root
--  transform Output_Pixel_From_Root that Execute returns:
--  Invert (Input_Pixel_From_Output) composed with the input's
--  Pixel_From_Root, so that a root-space ("@") position names the same
--  physical place in both images, and so does every space of the tree.
--  Execute fails with Transform_Singular when the region is so flat that
--  this inverse leaves the bound of AMV.Kernels.Transforms.
--
--  The output image mask (CreateOutputImageMask) is a second image of the
--  output's size: 255 where the output pixel was sampled from the input,
--  0 where it was clipped.
--
--  Bounds: the region and the transforms as in AMV.Kernels.Shapes and
--  AMV.Kernels.Transforms (1.0E150), ScalingX and ScalingY in
--  0.001 .. 1000 (VisionPro's range), ClipFillValue in 0 .. 255.
--
--  Proved (docs/PROOF.md): absence of run-time errors for any image
--  handle that is null or came from the image kernel and any region,
--  transform and parameter values, non-finite ones included; no sample
--  ever indexes outside the input image; no memory leaks; Gold: the output
--  size is exactly the documented one (from the side lengths in pixels
--  and the scalings, in 1 .. 32767); with NearestNeighbor every output
--  pixel is exactly the input pixel nearest to its sample point or the
--  fill value; the mask is 255 exactly where the sample point lies in the
--  input image.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Images;
with AMV.Kernels.Shapes;
with AMV.Kernels.Transforms;

package AMV.Kernels.Affine_Transform with SPARK_Mode, Preelaborate is

   package KI renames AMV.Kernels.Images;
   package KS renames AMV.Kernels.Shapes;
   package KT renames AMV.Kernels.Transforms;

   use type KI.Grey_8;
   use type KI.Ks_Image_8_Grey;

   ---------------------------------------------------------------------
   --  Run parameters (CogAffineTransform; C: ks_affine_transform)
   ---------------------------------------------------------------------

   Sampling_Mode_Nearest_Neighbor       : constant Int32 := 1;
   Sampling_Mode_Bilinear_Interpolation : constant Int32 := 2;
   Sampling_Mode_High_Precision         : constant Int32 := 3;
   Sampling_Mode_Bilinear_Accurate      : constant Int32 := 4;
   --  CogAffineTransformSamplingModeConstants (C:
   --  KS_AFFINE_TRANSFORM_SAMPLING_MODE_*); NearestNeighbor is AMV's.

   Clip_Mode_Zeroes : constant Int32 := 0;
   Clip_Mode_Fill   : constant Int32 := 1;
   Clip_Mode_Error  : constant Int32 := 2;
   --  CogAffineTransformClipModeConstants (C:
   --  KS_AFFINE_TRANSFORM_CLIP_MODE_*).

   Min_Scaling : constant := 0.001;
   Max_Scaling : constant := 1000.0;
   --  The range of ScalingX and ScalingY (C: KS_AFFINE_TRANSFORM_MIN_SCALING,
   --  KS_AFFINE_TRANSFORM_MAX_SCALING).

   Max_Output_Side : constant := 32_767;
   --  The largest output width and height (C:
   --  KS_AFFINE_TRANSFORM_MAX_OUTPUT_SIDE).

   type Ks_Affine_Transform is record
      Scaling_X       : Long_Float := 1.0;
      Scaling_Y       : Long_Float := 1.0;
      Sampling_Mode   : Int32 := Sampling_Mode_Bilinear_Accurate;
      Clip_Mode       : Int32 := Clip_Mode_Zeroes;
      Clip_Fill_Value : Int32 := 0;
   end record
     with Convention => C;
   --  C: ks_affine_transform, with VisionPro's defaults.

   for Ks_Affine_Transform use record
      Scaling_X       at 0 range 0 .. 63;
      Scaling_Y       at 8 range 0 .. 63;
      Sampling_Mode   at 16 range 0 .. 31;
      Clip_Mode       at 20 range 0 .. 31;
      Clip_Fill_Value at 24 range 0 .. 31;
   end record;

   procedure Run_Params_Default (Params : out Ks_Affine_Transform)
   with
     Export, Convention => C,
     External_Name => "ks_affine_transform_run_params_default",
     Post => Params = (others => <>);
   --  The default run parameters. Cannot fail.

   function Valid_Params (Params : Ks_Affine_Transform) return Boolean is
     (Params.Scaling_X >= Min_Scaling and then Params.Scaling_X <= Max_Scaling
      and then Params.Scaling_Y >= Min_Scaling
      and then Params.Scaling_Y <= Max_Scaling
      and then Params.Sampling_Mode
                 in Sampling_Mode_Nearest_Neighbor
                  | Sampling_Mode_Bilinear_Interpolation
                  | Sampling_Mode_Bilinear_Accurate
      and then Params.Clip_Mode in Clip_Mode_Zeroes .. Clip_Mode_Error
      and then Params.Clip_Fill_Value in 0 .. 255);
   --  Run parameters Execute accepts (False for a NaN at run time).

   function Fill_Value (Params : Ks_Affine_Transform) return KI.Grey_8 is
     (if Params.Clip_Mode = Clip_Mode_Fill
      then KI.Grey_8 (Params.Clip_Fill_Value) else 0)
   with Pre => Params.Clip_Fill_Value in 0 .. 255;
   --  The value of a clipped output pixel.

   ---------------------------------------------------------------------
   --  The output size (Gold)
   ---------------------------------------------------------------------

   Max_Pixel_Length : constant := 2.0 ** 1001;
   --  A bound of a side length in pixels: each component of a side of at
   --  most 4.0E150 mapped by a transform within 1.0E150 is at most 8.0E300,
   --  and Numerics.Hypot gives at most twice the larger one.

   function Pixel_Side_Length
     (Region            : KS.Ks_Rectangle_Affine;
      Pixel_From_Region : KT.Ks_Transform_2D_Linear;
      Side_Y            : Boolean) return Long_Float
   with
     Pre  => KS.Valid_Rectangle_Affine (Region)
             and then KT.Bounded (Pixel_From_Region),
     Post => Pixel_Side_Length'Result >= 0.0
             and then Pixel_Side_Length'Result <= Max_Pixel_Length;
   --  The length of side X (side Y when Side_Y) of Region in pixels: the
   --  length of the side vector, Side_X_Length * (cos Rotation, sin
   --  Rotation) (Side_Y_Length * (-sin (Rotation + Skew), cos (Rotation +
   --  Skew))), mapped by the linear part of Pixel_From_Region.

   function Output_Length (Scaling, Length : Long_Float) return Int32
   with
     Pre  => Scaling >= Min_Scaling and then Scaling <= Max_Scaling
             and then Length >= 0.0 and then Length <= Max_Pixel_Length,
     Post => Output_Length'Result in 0 .. Max_Output_Side + 1;
   --  Scaling * Length rounded to the nearest integer (halves away from
   --  zero); Max_Output_Side + 1 for any larger value. Execute fails unless
   --  it is in 1 .. Max_Output_Side.

   function Output_Width
     (Region            : KS.Ks_Rectangle_Affine;
      Pixel_From_Region : KT.Ks_Transform_2D_Linear;
      Params            : Ks_Affine_Transform) return Int32
   is
     (Output_Length (Params.Scaling_X,
                     Pixel_Side_Length (Region, Pixel_From_Region, False)))
   with Pre => KS.Valid_Rectangle_Affine (Region)
               and then KT.Bounded (Pixel_From_Region)
               and then Valid_Params (Params);

   function Output_Height
     (Region            : KS.Ks_Rectangle_Affine;
      Pixel_From_Region : KT.Ks_Transform_2D_Linear;
      Params            : Ks_Affine_Transform) return Int32
   is
     (Output_Length (Params.Scaling_Y,
                     Pixel_Side_Length (Region, Pixel_From_Region, True)))
   with Pre => KS.Valid_Rectangle_Affine (Region)
               and then KT.Bounded (Pixel_From_Region)
               and then Valid_Params (Params);

   function Is_Input_Pixel
     (Image : access constant KI.Ks_Image_8_Grey_Data;
      Value : KI.Grey_8) return Boolean
   is
     (for some Y in Image.Pixels'Range (1)
      => (for some X in Image.Pixels'Range (2)
          => Image.Pixels (Y, X) = Value))
   with Ghost, Pre => KI.Valid_Image (Image);
   --  Value is the value of some pixel of Image.

   ---------------------------------------------------------------------
   --  Entry point
   ---------------------------------------------------------------------

   procedure Execute
     (Image                  : access constant KI.Ks_Image_8_Grey_Data;
      Region                 : KS.Ks_Rectangle_Affine;
      Pixel_From_Region      : KT.Ks_Transform_2D_Linear;
      Pixel_From_Root        : KT.Ks_Transform_2D_Linear;
      Params                 : Ks_Affine_Transform;
      Create_Mask            : Int32;
      Output                 : out KI.Ks_Image_8_Grey;
      Output_Mask            : out KI.Ks_Image_8_Grey;
      Output_Pixel_From_Root : out KT.Ks_Transform_2D_Linear;
      Status                 : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_affine_transform_execute",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Transform_Singular
                         | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then KI.Valid_Image (Image)
                     and then KS.Valid_Rectangle_Affine (Region)
                     and then KT.Bounded (Pixel_From_Region)
                     and then Valid_Params (Params)
                     and then KI.Valid_Image (Output)
                     and then Output.Width
                                = Output_Width (Region, Pixel_From_Region,
                                                Params)
                     and then Output.Height
                                = Output_Height (Region, Pixel_From_Region,
                                                 Params)
                     and then Output.Width in 1 .. Max_Output_Side
                     and then Output.Height in 1 .. Max_Output_Side
                     and then KT.Bounded (Output_Pixel_From_Root)
                     and then
                       (if Params.Sampling_Mode
                             = Sampling_Mode_Nearest_Neighbor
                        then (for all Y in Output.Pixels'Range (1)
                              => (for all X in Output.Pixels'Range (2)
                                  => Output.Pixels (Y, X)
                                       = Fill_Value (Params)
                                     or else Is_Input_Pixel
                                               (Image,
                                                Output.Pixels (Y, X)))))
                     and then
                       (if Create_Mask = True_Value
                        then KI.Valid_Image (Output_Mask)
                             and then Output_Mask.Width = Output.Width
                             and then Output_Mask.Height = Output.Height
                             and then
                               (for all Y in Output_Mask.Pixels'Range (1)
                                => (for all X in Output_Mask.Pixels'Range (2)
                                    => Output_Mask.Pixels (Y, X) in 0 | 255))
                        else Output_Mask = null)
                else Output = null and then Output_Mask = null);
   --  Resamples Region of Image (see above). Region is in the space that
   --  Pixel_From_Region maps to pixel space; Pixel_From_Root is the input
   --  image's pixel-from-root transform; Create_Mask (0 or 1) asks for the
   --  output image mask. Output, Output_Mask (null unless asked for) and
   --  Output_Pixel_From_Root are the results; the caller owns the images.
   --  The checks, in order: the image (Image_No_Pixels "InputImage has no
   --  pixels", Bad_Parameter "InputImage is not a valid image handle"), the
   --  region (the messages of ks_rectangle_affine_get_parent_from_child_
   --  transform), the transforms ("PixelFromRegion ..." and
   --  "PixelFromRoot ... must be finite and within 1.0E150"), the run
   --  parameters ("RunParams.ScalingX must be in 0.001 .. 1000", ...,
   --  "RunParams.SamplingMode HighPrecision is not implemented"),
   --  Create_Mask, the output size ("the output image would be less than 1
   --  pixel wide (Region.SideXLength in pixels times RunParams.ScalingX)",
   --  "... more than 32767 pixels ..."), the transforms of the result
   --  (Bad_Parameter or Transform_Singular), Out_Of_Memory, and with
   --  ClipMode Error the clipping ("Region lies partly outside InputImage
   --  (RunParams.ClipMode is Error)").

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
   --  The image check of Execute, made by the Ada API before it computes
   --  the transforms of the region (whose space may be unknown).

end AMV.Kernels.Affine_Transform;
