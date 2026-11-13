--  Kernel of AMV.Image_Processing.Polar_Unwrap: the polar unwrap tool
--  (CogPolarUnwrapTool, whose run parameters are a CogPolarUnwrap). The C
--  API is declared in include/amv_ip_geometry.h.
--
--  Execute resamples a circular annulus section (Region, a
--  CogCircularAnnulusSection; VisionPro also accepts an elliptical one)
--  of an 8-bit image into a new upright image: output x runs along the
--  angle, from AngleStart through AngleStart + AngleSpan, and output y
--  along the radius, from the start arc (Radius) to the end arc (Radius *
--  RadialScale; inwards when RadialScale < 1). The section must have
--  Radius > 0, RadialScale > 0 and not 1, and AngleSpan not 0 (several
--  turns are allowed).
--
--  Size. With S the scale of Pixel_From_Region (the square root of the
--  absolute value of its determinant: exactly the scale of a
--  similarity), Width = round (ScalingX * abs AngleSpan * (Radius +
--  Radius * RadialScale) / 2 * S), the length of the middle arc in
--  pixels, and Height = round (ScalingY * abs (Radius * RadialScale -
--  Radius) * S), the radial extent in pixels (halves away from zero). So
--  the defaults (1.0) give about one output pixel per input pixel. A size
--  below 1 or above Max_Output_Side (32767) fails with Bad_Parameter, as
--  in VisionPro. ScalingX and ScalingY must lie in 0.001 .. 1000 (AMV's
--  bounds; VisionPro only requires them to be positive).
--
--  Mapping. The output pixel (X, Y) (centre at (X, Y)) samples the input
--  at the point of the region's space with angle AngleStart + (X + 0.5)
--  / Width * AngleSpan and radius Radius + (Y + 0.5) / Height * (Radius *
--  RadialScale - Radius) about the centre, mapped into pixel space by
--  Pixel_From_Region. The mapping is not affine, so the output image gets
--  a fresh coordinate space tree whose root is its pixel space (the Ada
--  API leaves the default tree); ks_polar_unwrap_get_input_point_from_
--  output_point maps a point of the output (root or pixel space) back to
--  the input image's selected space with the same formulas (X and Y may
--  be anywhere in the output image's area), and ks_polar_unwrap_get_
--  output_point_from_input_point maps the other way.
--
--  Sampling (SamplingMode, CogPolarUnwrapSamplingModeConstants with
--  VisionPro's values): BilinearInterpolation (0, the default) or
--  NearestNeighbor (1), as in AMV.Kernels.Image_Sampling. As in VisionPro,
--  a sample point outside the area the input pixels cover fails the run
--  with Bad_Parameter ("Region lies partly outside InputImage").
--
--  Proved (docs/PROOF.md): absence of run-time errors for any image
--  handle that is null or came from the image kernel and any region,
--  transform, parameter and point values, non-finite ones included; no
--  sample ever indexes outside the input image; no memory leaks; Gold: the
--  output size is exactly the documented one, in 1 .. 32767; with
--  NearestNeighbor every output pixel is an input pixel (exactly the one
--  nearest to its sample point); the points the two mapping entry points
--  return lie within 1.0E150.

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

package AMV.Kernels.Polar_Unwrap with SPARK_Mode, Preelaborate is

   package KI renames AMV.Kernels.Images;
   package KS renames AMV.Kernels.Shapes;
   package KT renames AMV.Kernels.Transforms;

   use type KI.Grey_8;
   use type KI.Ks_Image_8_Grey;

   ---------------------------------------------------------------------
   --  Run parameters (CogPolarUnwrap; C: ks_polar_unwrap)
   ---------------------------------------------------------------------

   Sampling_Mode_Bilinear_Interpolation : constant Int32 := 0;
   Sampling_Mode_Nearest_Neighbor       : constant Int32 := 1;
   --  CogPolarUnwrapSamplingModeConstants (C:
   --  KS_POLAR_UNWRAP_SAMPLING_MODE_*).

   Min_Scaling : constant := 0.001;
   Max_Scaling : constant := 1000.0;
   --  The range of ScalingX and ScalingY (C: KS_POLAR_UNWRAP_MIN_SCALING,
   --  KS_POLAR_UNWRAP_MAX_SCALING).

   Max_Output_Side : constant := 32_767;
   --  The largest output width and height (C:
   --  KS_POLAR_UNWRAP_MAX_OUTPUT_SIDE).

   type Ks_Polar_Unwrap is record
      Scaling_X     : Long_Float := 1.0;
      Scaling_Y     : Long_Float := 1.0;
      Sampling_Mode : Int32 := Sampling_Mode_Bilinear_Interpolation;
   end record
     with Convention => C;
   --  C: ks_polar_unwrap, with VisionPro's defaults.

   for Ks_Polar_Unwrap use record
      Scaling_X     at 0 range 0 .. 63;
      Scaling_Y     at 8 range 0 .. 63;
      Sampling_Mode at 16 range 0 .. 31;
   end record;

   procedure Run_Params_Default (Params : out Ks_Polar_Unwrap)
   with
     Export, Convention => C,
     External_Name => "ks_polar_unwrap_run_params_default",
     Post => Params = (others => <>);
   --  The default run parameters. Cannot fail.

   function Valid_Params (Params : Ks_Polar_Unwrap) return Boolean is
     (Params.Scaling_X >= Min_Scaling and then Params.Scaling_X <= Max_Scaling
      and then Params.Scaling_Y >= Min_Scaling
      and then Params.Scaling_Y <= Max_Scaling
      and then Params.Sampling_Mode
                 in Sampling_Mode_Bilinear_Interpolation
                  | Sampling_Mode_Nearest_Neighbor);

   function Valid_Section (Section : KS.Ks_Circular_Annulus_Section)
      return Boolean
   is
     (KS.Valid_Circular_Annulus_Section (Section)
      and then Section.Radius > 0.0
      and then Section.Radial_Scale > 0.0
      and then Section.Radial_Scale /= 1.0
      and then Section.Angle_Span /= 0.0);
   --  A section that can be unwrapped.

   ---------------------------------------------------------------------
   --  The output size (Gold)
   ---------------------------------------------------------------------

   Max_Pixel_Length : constant := 2.0 ** 1000;
   --  A bound of the lengths in pixels below (a larger one reads as this).

   function Pixel_Scale (T : KT.Ks_Transform_2D_Linear) return Long_Float
   with
     Pre  => KT.Bounded (T),
     Post => Pixel_Scale'Result >= 0.0
             and then Pixel_Scale'Result <= 2.0 ** 511;
   --  Sqrt (abs (A D - B C)): the factor by which T scales lengths (for a
   --  similarity; the geometric mean of its scalings otherwise).

   function Arc_Length
     (Section           : KS.Ks_Circular_Annulus_Section;
      Pixel_From_Region : KT.Ks_Transform_2D_Linear) return Long_Float
   with
     Pre  => Valid_Section (Section) and then KT.Bounded (Pixel_From_Region),
     Post => Arc_Length'Result >= 0.0
             and then Arc_Length'Result <= Max_Pixel_Length;
   --  abs AngleSpan * (Radius + Radius * RadialScale) / 2 * S, the middle
   --  arc in pixels (any value beyond 2**500 reads as 2**1000).

   function Radial_Length
     (Section           : KS.Ks_Circular_Annulus_Section;
      Pixel_From_Region : KT.Ks_Transform_2D_Linear) return Long_Float
   with
     Pre  => Valid_Section (Section) and then KT.Bounded (Pixel_From_Region),
     Post => Radial_Length'Result >= 0.0
             and then Radial_Length'Result <= Max_Pixel_Length;
   --  abs (Radius * RadialScale - Radius) * S, the radial extent in pixels.

   function Output_Length (Scaling, Length : Long_Float) return Int32
   with
     Pre  => Scaling >= Min_Scaling and then Scaling <= Max_Scaling
             and then Length >= 0.0 and then Length <= Max_Pixel_Length,
     Post => Output_Length'Result in 0 .. Max_Output_Side + 1;
   --  Scaling * Length rounded to the nearest integer (halves away from
   --  zero); Max_Output_Side + 1 for any larger value.

   function Output_Width
     (Section           : KS.Ks_Circular_Annulus_Section;
      Pixel_From_Region : KT.Ks_Transform_2D_Linear;
      Params            : Ks_Polar_Unwrap) return Int32
   is
     (Output_Length (Params.Scaling_X,
                     Arc_Length (Section, Pixel_From_Region)))
   with Pre => Valid_Section (Section) and then KT.Bounded (Pixel_From_Region)
               and then Valid_Params (Params);

   function Output_Height
     (Section           : KS.Ks_Circular_Annulus_Section;
      Pixel_From_Region : KT.Ks_Transform_2D_Linear;
      Params            : Ks_Polar_Unwrap) return Int32
   is
     (Output_Length (Params.Scaling_Y,
                     Radial_Length (Section, Pixel_From_Region)))
   with Pre => Valid_Section (Section) and then KT.Bounded (Pixel_From_Region)
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
   --  Entry points
   ---------------------------------------------------------------------

   procedure Execute
     (Image             : access constant KI.Ks_Image_8_Grey_Data;
      Region            : KS.Ks_Circular_Annulus_Section;
      Pixel_From_Region : KT.Ks_Transform_2D_Linear;
      Params            : Ks_Polar_Unwrap;
      Output            : out KI.Ks_Image_8_Grey;
      Status            : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_polar_unwrap_execute",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then KI.Valid_Image (Image)
                     and then Valid_Section (Region)
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
                     and then
                       (if Params.Sampling_Mode
                             = Sampling_Mode_Nearest_Neighbor
                        then (for all Y in Output.Pixels'Range (1)
                              => (for all X in Output.Pixels'Range (2)
                                  => Is_Input_Pixel (Image,
                                                     Output.Pixels (Y, X)))))
                else Output = null);
   --  Unwraps Region of Image (see above); Region is in the space that
   --  Pixel_From_Region maps to pixel space. The checks, in order: the
   --  image (Image_No_Pixels "InputImage has no pixels", Bad_Parameter
   --  "InputImage is not a valid image handle"), the region
   --  ("Region.CenterX must be finite and within 1.0E150", ...,
   --  "Region.Radius must be > 0", "Region.RadialScale must be > 0 and not
   --  1", "Region.AngleSpan must not be 0"), the transform, the run
   --  parameters ("RunParams.ScalingX must be in 0.001 .. 1000",
   --  "RunParams.SamplingMode must be BilinearInterpolation (0) or
   --  NearestNeighbor (1)"), the output size ("the output image would be
   --  less than 1 pixel wide (RunParams.ScalingX times the middle arc of
   --  Region in pixels)", ...), Out_Of_Memory, then the clipping ("Region
   --  lies partly outside InputImage"). Output is a new handle the caller
   --  owns, null when the call fails.

   procedure Get_Input_Point_From_Output_Point
     (Region               : KS.Ks_Circular_Annulus_Section;
      Pixel_From_Region    : KT.Ks_Transform_2D_Linear;
      Selected_From_Region : KT.Ks_Transform_2D_Linear;
      Params               : Ks_Polar_Unwrap;
      Output_Point_X       : Long_Float;
      Output_Point_Y       : Long_Float;
      Input_Point_X        : out Long_Float;
      Input_Point_Y        : out Long_Float;
      Status               : out Ks_Status)
   with
     Export, Convention => C,
     External_Name =>
       "ks_polar_unwrap_get_input_point_from_output_point",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then KT.Bounded (Input_Point_X)
                            and then KT.Bounded (Input_Point_Y)
                       else Input_Point_X = 0.0
                            and then Input_Point_Y = 0.0);
   --  GetInputPointFromOutputPoint: the point of the input image's selected
   --  space that the output point (Output_Point_X, Output_Point_Y) (output
   --  pixel or root coordinates) samples; Selected_From_Region maps the
   --  region's space to the input's selected space. The output size is
   --  that of Execute. The checks: the region, the transforms and the run
   --  parameters as in Execute, the output size, the output point (within
   --  the output image's area, "OutputPointX must be in -0.5 .. 99.5"),
   --  and a result beyond 1.0E150 ("the input point exceeds 1.0E150").

   procedure Get_Output_Point_From_Input_Point
     (Region               : KS.Ks_Circular_Annulus_Section;
      Pixel_From_Region    : KT.Ks_Transform_2D_Linear;
      Region_From_Selected : KT.Ks_Transform_2D_Linear;
      Params               : Ks_Polar_Unwrap;
      Input_Point_X        : Long_Float;
      Input_Point_Y        : Long_Float;
      Revolution           : Int32;
      Output_Point_X       : out Long_Float;
      Output_Point_Y       : out Long_Float;
      Status               : out Ks_Status)
   with
     Export, Convention => C,
     External_Name =>
       "ks_polar_unwrap_get_output_point_from_input_point",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then KT.Bounded (Output_Point_X)
                            and then KT.Bounded (Output_Point_Y)
                       else Output_Point_X = 0.0
                            and then Output_Point_Y = 0.0);
   --  GetOutputPointFromInputPoint: the output point (pixel or root
   --  coordinates) that samples the input point (Input_Point_X,
   --  Input_Point_Y) of the input's selected space; Region_From_Selected
   --  maps the selected space to the region's space. The angle of the
   --  point is measured from AngleStart in the sense of AngleSpan, in
   --  [0, 2 Pi), plus Revolution whole turns (for a span of more than one
   --  turn). Points outside the section give points outside the output
   --  image. The checks: as for the other mapping, the input point
   --  (finite and within 1.0E150, and not the centre of the section: "the
   --  centre of Region has no output point"), and a result beyond 1.0E150
   --  ("the output point exceeds 1.0E150").

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

end AMV.Kernels.Polar_Unwrap;
