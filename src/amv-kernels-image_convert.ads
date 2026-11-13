--  Kernel of AMV.Image_Processing.Image_Convert: the image convert tool
--  (CogImageConvertTool, whose run parameters are a
--  CogImageConvertRunParams). The C API is declared in
--  include/amv_ip_geometry.h.
--
--  Execute converts an image of any type (ICogImage: an 8-bit grey image,
--  a 16-bit grey image or a colour image given as its three planes) into
--  a new 8-bit grey image of the same size. Exactly one kind of input is
--  given; the other handles are null. RunMode
--  (CogImageConvertRunModeConstants, VisionPro's values) selects the
--  conversion:
--
--  * Intensity (1, AMV's default; VisionPro states none): an 8-bit image
--    is copied; a 16-bit image gives its high byte (V / 256, rounded
--    down: VisionPro shifts by the image's encoding, and AMV's 16-bit
--    images use all 16 bits); a colour image gives
--    round (0.299 R + 0.587 G + 0.114 B), computed exactly as
--    (299 R + 587 G + 114 B + 500) / 1000 in integers (halves up).
--  * Plane0, Plane1, Plane2 (6, 7, 8): the red, green or blue plane of a
--    colour image.
--  * IntensityFromWeightedRGB (10): round (Wr R + Wg G + Wb B) with the
--    weights IntensityFromWeightedRGBRedWeight, ...GreenWeight and
--    ...BlueWeight (defaults 0.299, 0.587, 0.114, any value within
--    1.0E150), limited to 0 .. 255 (halves away from zero).
--  * HSI (2), IntensityFromBayer (3), RGBFromBayer (4), HSIFromBayer (5),
--    RGB (9), PixelFromRange (11) and MaskFromRange (12) are not
--    implemented (Bad_Parameter): their outputs are colour or range
--    images, or their inputs Bayer or range images, which AMV does not
--    have. Their parameters (the Bayer weights and scales, BayerType) are
--    kept in the record and checked for range only.
--
--  A mode that needs a colour image fails with Bad_Parameter for a grey
--  one. SharePelsIfPossible is accepted and ignored (the output is always
--  a new image; the Ada API shares nothing either).
--
--  Proved (docs/PROOF.md): absence of run-time errors for any image
--  handles that are null or came from the image kernel and any parameter
--  values, non-finite ones included; no memory leaks; Gold: the output
--  has the size of the input and every output pixel is exactly the
--  formula of the mode (the copy, the high byte, the integer intensity
--  formula, the plane, or the weighted formula), all within 0 .. 255.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Images;

package AMV.Kernels.Image_Convert with SPARK_Mode, Preelaborate is

   package KI renames AMV.Kernels.Images;

   use type KI.Grey_8;
   use type KI.Grey_16;
   use type KI.Ks_Image_8_Grey;
   use type KI.Grey_8_Matrix;

   ---------------------------------------------------------------------
   --  Run parameters (CogImageConvertRunParams; C:
   --  ks_image_convert_run_params)
   ---------------------------------------------------------------------

   Run_Mode_Intensity                   : constant Int32 := 1;
   Run_Mode_HSI                         : constant Int32 := 2;
   Run_Mode_Intensity_From_Bayer        : constant Int32 := 3;
   Run_Mode_RGB_From_Bayer              : constant Int32 := 4;
   Run_Mode_HSI_From_Bayer              : constant Int32 := 5;
   Run_Mode_Plane_0                     : constant Int32 := 6;
   Run_Mode_Plane_1                     : constant Int32 := 7;
   Run_Mode_Plane_2                     : constant Int32 := 8;
   Run_Mode_RGB                         : constant Int32 := 9;
   Run_Mode_Intensity_From_Weighted_RGB : constant Int32 := 10;
   Run_Mode_Pixel_From_Range            : constant Int32 := 11;
   Run_Mode_Mask_From_Range             : constant Int32 := 12;
   --  CogImageConvertRunModeConstants (C: KS_IMAGE_CONVERT_RUN_MODE_*).

   Bayer_Type_GR : constant Int32 := 0;
   Bayer_Type_RG : constant Int32 := 1;
   Bayer_Type_BG : constant Int32 := 2;
   Bayer_Type_GB : constant Int32 := 3;
   --  CogImageConvertBayerTypeConstants (C: KS_IMAGE_CONVERT_BAYER_TYPE_*).

   Max_Weight : constant := 1.0E150;
   --  The bound of every weight and scale.

   type Ks_Image_Convert_Run_Params is record
      Run_Mode                                : Int32 := Run_Mode_Intensity;
      Bayer_Type                              : Int32 := Bayer_Type_GR;
      Share_Pels_If_Possible                  : Int32 := False_Value;
      Intensity_From_Weighted_RGB_Red_Weight   : Long_Float := 0.299;
      Intensity_From_Weighted_RGB_Green_Weight : Long_Float := 0.587;
      Intensity_From_Weighted_RGB_Blue_Weight  : Long_Float := 0.114;
      Intensity_From_Bayer_Red_Weight          : Long_Float := 0.299;
      Intensity_From_Bayer_Green_Weight        : Long_Float := 0.587;
      Intensity_From_Bayer_Blue_Weight         : Long_Float := 0.114;
      Color_From_Bayer_Red_Scale               : Long_Float := 1.0;
      Color_From_Bayer_Green_Scale             : Long_Float := 1.0;
      Color_From_Bayer_Blue_Scale              : Long_Float := 1.0;
   end record
     with Convention => C;
   --  C: ks_image_convert_run_params. VisionPro states no defaults; these
   --  are AMV's (the weights are those VisionPro's CogImageConvert
   --  documents for its Bayer conversion).

   for Ks_Image_Convert_Run_Params use record
      Run_Mode                                 at 0 range 0 .. 31;
      Bayer_Type                               at 4 range 0 .. 31;
      Share_Pels_If_Possible                   at 8 range 0 .. 31;
      Intensity_From_Weighted_RGB_Red_Weight   at 16 range 0 .. 63;
      Intensity_From_Weighted_RGB_Green_Weight at 24 range 0 .. 63;
      Intensity_From_Weighted_RGB_Blue_Weight  at 32 range 0 .. 63;
      Intensity_From_Bayer_Red_Weight          at 40 range 0 .. 63;
      Intensity_From_Bayer_Green_Weight        at 48 range 0 .. 63;
      Intensity_From_Bayer_Blue_Weight         at 56 range 0 .. 63;
      Color_From_Bayer_Red_Scale               at 64 range 0 .. 63;
      Color_From_Bayer_Green_Scale             at 72 range 0 .. 63;
      Color_From_Bayer_Blue_Scale              at 80 range 0 .. 63;
   end record;

   procedure Run_Params_Default (Params : out Ks_Image_Convert_Run_Params)
   with
     Export, Convention => C,
     External_Name => "ks_image_convert_run_params_default",
     Post => Params = (others => <>);
   --  The default run parameters. Cannot fail.

   function Bounded_Weight (W : Long_Float) return Boolean is
     (W >= -Max_Weight and then W <= Max_Weight);

   function Valid_Weights (Params : Ks_Image_Convert_Run_Params)
      return Boolean
   is
     (Bounded_Weight (Params.Intensity_From_Weighted_RGB_Red_Weight)
      and then Bounded_Weight (Params.Intensity_From_Weighted_RGB_Green_Weight)
      and then Bounded_Weight (Params.Intensity_From_Weighted_RGB_Blue_Weight));

   ---------------------------------------------------------------------
   --  The conversions (Gold)
   ---------------------------------------------------------------------

   function Intensity_Of (R, G, B : KI.Grey_8) return KI.Grey_8 is
     (KI.Grey_8 ((299 * Natural (R) + 587 * Natural (G) + 114 * Natural (B)
                  + 500) / 1000));
   --  round (0.299 R + 0.587 G + 0.114 B), halves up, exactly.

   function High_Byte (V : KI.Grey_16) return KI.Grey_8 is
     (KI.Grey_8 (V / 256));
   --  The intensity of a 16-bit pixel.

   function Weighted_Intensity
     (Params  : Ks_Image_Convert_Run_Params;
      R, G, B : KI.Grey_8) return KI.Grey_8
   with Pre => Valid_Weights (Params);
   --  round (Wr R + Wg G + Wb B) with the IntensityFromWeightedRGB weights,
   --  limited to 0 .. 255.

   function Colour_Pixel
     (Params  : Ks_Image_Convert_Run_Params;
      R, G, B : KI.Grey_8) return KI.Grey_8
   is
     (case Params.Run_Mode is
         when Run_Mode_Plane_0 => R,
         when Run_Mode_Plane_1 => G,
         when Run_Mode_Plane_2 => B,
         when Run_Mode_Intensity_From_Weighted_RGB =>
            Weighted_Intensity (Params, R, G, B),
         when others => Intensity_Of (R, G, B))
   with Pre => Valid_Weights (Params);
   --  The output pixel for a colour input (Intensity for any other mode).

   function Same_Planes
     (Red, Green, Blue : access constant KI.Ks_Image_8_Grey_Data)
      return Boolean
   is
     (KI.Valid_Image (Red) and then KI.Valid_Image (Green)
      and then KI.Valid_Image (Blue)
      and then Green.Width = Red.Width and then Green.Height = Red.Height
      and then Blue.Width = Red.Width and then Blue.Height = Red.Height);
   --  Three valid planes of one size.

   ---------------------------------------------------------------------
   --  Entry point
   ---------------------------------------------------------------------

   procedure Execute
     (Grey_8           : access constant KI.Ks_Image_8_Grey_Data;
      Grey_16          : access constant KI.Ks_Image_16_Grey_Data;
      Red, Green, Blue : access constant KI.Ks_Image_8_Grey_Data;
      Params           : Ks_Image_Convert_Run_Params;
      Output           : out KI.Ks_Image_8_Grey;
      Status           : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_image_convert_execute",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Out_Of_Memory
             and then
               (if not Succeeded (Status) then Output = null
                elsif Grey_8 /= null
                then KI.Valid_Image (Grey_8)
                     and then Params.Run_Mode = Run_Mode_Intensity
                     and then KI.Valid_Image (Output)
                     and then Output.Width = Grey_8.Width
                     and then Output.Height = Grey_8.Height
                     and then Output.Pixels.all = Grey_8.Pixels.all
                elsif Grey_16 /= null
                then KI.Valid_Image (Grey_16)
                     and then Params.Run_Mode = Run_Mode_Intensity
                     and then KI.Valid_Image (Output)
                     and then Output.Width = Grey_16.Width
                     and then Output.Height = Grey_16.Height
                     and then
                       (for all Y in Output.Pixels'Range (1)
                        => (for all X in Output.Pixels'Range (2)
                            => Output.Pixels (Y, X)
                                 = High_Byte (Grey_16.Pixels (Y, X))))
                else Same_Planes (Red, Green, Blue)
                     and then Valid_Weights (Params)
                     and then Params.Run_Mode
                                in Run_Mode_Intensity | Run_Mode_Plane_0
                                 | Run_Mode_Plane_1 | Run_Mode_Plane_2
                                 | Run_Mode_Intensity_From_Weighted_RGB
                     and then KI.Valid_Image (Output)
                     and then Output.Width = Red.Width
                     and then Output.Height = Red.Height
                     and then
                       (for all Y in Output.Pixels'Range (1)
                        => (for all X in Output.Pixels'Range (2)
                            => Output.Pixels (Y, X)
                                 = Colour_Pixel (Params,
                                                 Red.Pixels (Y, X),
                                                 Green.Pixels (Y, X),
                                                 Blue.Pixels (Y, X)))));
   --  The converted image (see above). The checks, in order: the input
   --  (Image_No_Pixels "InputImage has no pixels" when every handle is
   --  null; Bad_Parameter "InputImage must be one image: an 8-bit, a
   --  16-bit or a colour image" for more than one kind, "InputImage:
   --  Red, Green and Blue must be planes of the same size", "InputImage is
   --  not a valid image handle"), the run parameters ("RunParams.RunMode
   --  must be a CogImageConvertRunModeConstants value (1 .. 12)",
   --  "RunParams.RunMode HSI is not implemented", "RunParams.BayerType
   --  must be in 0 .. 3", "RunParams.IntensityFromWeightedRGBRedWeight
   --  must be finite and within 1.0E150", ...), the mode against the
   --  input ("RunParams.RunMode Plane0 needs a colour InputImage"), then
   --  Out_Of_Memory. Output is a new handle the caller owns, null when the
   --  call fails.

end AMV.Kernels.Image_Convert;
