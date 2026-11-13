pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Image_Sampling;
with AMV.Kernels.Numerics;

package body AMV.Kernels.Image_Convert with SPARK_Mode is

   package SM renames AMV.Kernels.Image_Sampling;
   package N renames AMV.Kernels.Numerics;

   procedure Run_Params_Default (Params : out Ks_Image_Convert_Run_Params) is
   begin
      Params := (others => <>);
   end Run_Params_Default;

   function Weighted_Intensity
     (Params  : Ks_Image_Convert_Run_Params;
      R, G, B : KI.Grey_8) return KI.Grey_8
   is
   begin
      --  Each term is at most 255 * 1.0E150 in magnitude.
      return SM.To_Grey
        (N.Mul_Within (Params.Intensity_From_Weighted_RGB_Red_Weight,
                       Long_Float (R), Max_Weight, 255.0)
         + N.Mul_Within (Params.Intensity_From_Weighted_RGB_Green_Weight,
                         Long_Float (G), Max_Weight, 255.0)
         + N.Mul_Within (Params.Intensity_From_Weighted_RGB_Blue_Weight,
                         Long_Float (B), Max_Weight, 255.0));
   end Weighted_Intensity;

   ---------------------------------------------------------------------
   --  Checks
   ---------------------------------------------------------------------

   type Input_Kind is (Kind_8_Grey, Kind_16_Grey, Kind_Colour);

   procedure Check_Input
     (Grey_8           : access constant KI.Ks_Image_8_Grey_Data;
      Grey_16          : access constant KI.Ks_Image_16_Grey_Data;
      Red, Green, Blue : access constant KI.Ks_Image_8_Grey_Data;
      Kind             : out Input_Kind;
      Status           : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter
             and then
               (if Succeeded (Status)
                then (case Kind is
                         when Kind_8_Grey =>
                            Grey_8 /= null and then SM.Usable_Image (Grey_8),
                         when Kind_16_Grey =>
                            Grey_8 = null and then Grey_16 /= null
                            and then SM.Usable_Image (Grey_16),
                         when Kind_Colour =>
                            Grey_8 = null and then Grey_16 = null
                            and then Same_Planes (Red, Green, Blue)
                            and then SM.Usable_Image (Red)));
   --  Exactly one kind of input image, valid.

   procedure Check_Input
     (Grey_8           : access constant KI.Ks_Image_8_Grey_Data;
      Grey_16          : access constant KI.Ks_Image_16_Grey_Data;
      Red, Green, Blue : access constant KI.Ks_Image_8_Grey_Data;
      Kind             : out Input_Kind;
      Status           : out Ks_Status)
   is
      Has_8      : constant Boolean := Grey_8 /= null;
      Has_16     : constant Boolean := Grey_16 /= null;
      Has_Colour : constant Boolean :=
        Red /= null or else Green /= null or else Blue /= null;
   begin
      Kind := Kind_8_Grey;
      if not (Has_8 or else Has_16 or else Has_Colour) then
         Set_Failure (Status, Failure_Image_No_Pixels,
                      "InputImage has no pixels");
      elsif (Has_8 and then (Has_16 or else Has_Colour))
        or else (Has_16 and then Has_Colour)
      then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "InputImage must be one image: an 8-bit, a 16-bit or "
                      & "a colour image");
      elsif Has_8 then
         if SM.Usable_Image (Grey_8) then
            Set_Success (Status);
         else
            Set_Failure (Status, Failure_Bad_Parameter,
                         "InputImage is not a valid image handle");
         end if;
      elsif Has_16 then
         Kind := Kind_16_Grey;
         if SM.Usable_Image (Grey_16) then
            Set_Success (Status);
         else
            Set_Failure (Status, Failure_Bad_Parameter,
                         "InputImage is not a valid image handle");
         end if;
      else
         Kind := Kind_Colour;
         if Same_Planes (Red, Green, Blue) and then SM.Usable_Image (Red)
         then
            Set_Success (Status);
         else
            Set_Failure (Status, Failure_Bad_Parameter,
                         "InputImage: Red, Green and Blue must be planes of "
                         & "the same size");
         end if;
      end if;
   end Check_Input;

   function Mode_Name (Mode : Int32) return String
   with Post => Mode_Name'Result'First = 1
                and then Mode_Name'Result'Length <= 24;
   --  VisionPro's name of a run mode ("" for an unknown code).

   function Mode_Name (Mode : Int32) return String is
   begin
      case Mode is
         when Run_Mode_Intensity                   =>
            return "Intensity";
         when Run_Mode_HSI                         =>
            return "HSI";
         when Run_Mode_Intensity_From_Bayer        =>
            return "IntensityFromBayer";
         when Run_Mode_RGB_From_Bayer              =>
            return "RGBFromBayer";
         when Run_Mode_HSI_From_Bayer              =>
            return "HSIFromBayer";
         when Run_Mode_Plane_0                     =>
            return "Plane0";
         when Run_Mode_Plane_1                     =>
            return "Plane1";
         when Run_Mode_Plane_2                     =>
            return "Plane2";
         when Run_Mode_RGB                         =>
            return "RGB";
         when Run_Mode_Intensity_From_Weighted_RGB =>
            return "IntensityFromWeightedRGB";
         when Run_Mode_Pixel_From_Range            =>
            return "PixelFromRange";
         when Run_Mode_Mask_From_Range             =>
            return "MaskFromRange";
         when others                               =>
            return "";
      end case;
   end Mode_Name;

   procedure Check_Params
     (Params : Ks_Image_Convert_Run_Params;
      Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Valid_Weights (Params)
                            and then Params.Run_Mode
                                       in Run_Mode_Intensity
                                        | Run_Mode_Plane_0
                                        | Run_Mode_Plane_1
                                        | Run_Mode_Plane_2
                                        | Run_Mode_Intensity_From_Weighted_RGB);

   procedure Check_Params
     (Params : Ks_Image_Convert_Run_Params;
      Status : out Ks_Status)
   is
      Fault : Natural := 0;
      --  The first parameter out of range (0 for none).
   begin
      if Params.Run_Mode not in Run_Mode_Intensity .. Run_Mode_Mask_From_Range
      then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "RunParams.RunMode must be a "
                      & "CogImageConvertRunModeConstants value (1 .. 12)");
         return;
      elsif Params.Run_Mode
              not in Run_Mode_Intensity | Run_Mode_Plane_0 | Run_Mode_Plane_1
                   | Run_Mode_Plane_2 | Run_Mode_Intensity_From_Weighted_RGB
      then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "RunParams.RunMode " & Mode_Name (Params.Run_Mode)
                      & " is not implemented");
         return;
      end if;
      if Params.Bayer_Type not in Bayer_Type_GR .. Bayer_Type_GB then
         Fault := 1;
      elsif Params.Share_Pels_If_Possible not in 0 .. 1 then
         Fault := 2;
      elsif not Bounded_Weight (Params.Intensity_From_Weighted_RGB_Red_Weight)
      then
         Fault := 3;
      elsif not Bounded_Weight
                  (Params.Intensity_From_Weighted_RGB_Green_Weight)
      then
         Fault := 4;
      elsif not Bounded_Weight
                  (Params.Intensity_From_Weighted_RGB_Blue_Weight)
      then
         Fault := 5;
      elsif not Bounded_Weight (Params.Intensity_From_Bayer_Red_Weight) then
         Fault := 6;
      elsif not Bounded_Weight (Params.Intensity_From_Bayer_Green_Weight)
      then
         Fault := 7;
      elsif not Bounded_Weight (Params.Intensity_From_Bayer_Blue_Weight) then
         Fault := 8;
      elsif not Bounded_Weight (Params.Color_From_Bayer_Red_Scale) then
         Fault := 9;
      elsif not Bounded_Weight (Params.Color_From_Bayer_Green_Scale) then
         Fault := 10;
      elsif not Bounded_Weight (Params.Color_From_Bayer_Blue_Scale) then
         Fault := 11;
      end if;
      case Fault is
         when 0 =>
            Set_Success (Status);
         when 1 =>
            Set_Failure (Status, Failure_Bad_Parameter,
                         "RunParams.BayerType must be in 0 .. 3");
         when 2 =>
            Set_Failure (Status, Failure_Bad_Parameter,
                         "RunParams.SharePelsIfPossible must be 0 or 1");
         when 3 =>
            Set_Failure (Status, Failure_Bad_Parameter,
                         "RunParams.IntensityFromWeightedRGBRedWeight must "
                         & "be finite and within 1.0E150");
         when 4 =>
            Set_Failure (Status, Failure_Bad_Parameter,
                         "RunParams.IntensityFromWeightedRGBGreenWeight must "
                         & "be finite and within 1.0E150");
         when 5 =>
            Set_Failure (Status, Failure_Bad_Parameter,
                         "RunParams.IntensityFromWeightedRGBBlueWeight must "
                         & "be finite and within 1.0E150");
         when 6 =>
            Set_Failure (Status, Failure_Bad_Parameter,
                         "RunParams.IntensityFromBayerRedWeight must be "
                         & "finite and within 1.0E150");
         when 7 =>
            Set_Failure (Status, Failure_Bad_Parameter,
                         "RunParams.IntensityFromBayerGreenWeight must be "
                         & "finite and within 1.0E150");
         when 8 =>
            Set_Failure (Status, Failure_Bad_Parameter,
                         "RunParams.IntensityFromBayerBlueWeight must be "
                         & "finite and within 1.0E150");
         when 9 =>
            Set_Failure (Status, Failure_Bad_Parameter,
                         "RunParams.ColorFromBayerRedScale must be finite "
                         & "and within 1.0E150");
         when 10 =>
            Set_Failure (Status, Failure_Bad_Parameter,
                         "RunParams.ColorFromBayerGreenScale must be finite "
                         & "and within 1.0E150");
         when others =>
            Set_Failure (Status, Failure_Bad_Parameter,
                         "RunParams.ColorFromBayerBlueScale must be finite "
                         & "and within 1.0E150");
      end case;
   end Check_Params;

   ---------------------------------------------------------------------
   --  Conversions
   ---------------------------------------------------------------------

   procedure Convert_16
     (Image  : access constant KI.Ks_Image_16_Grey_Data;
      Output : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Pre  => SM.Usable_Image (Image),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then KI.Valid_Image (Output)
                     and then Output.Width = Image.Width
                     and then Output.Height = Image.Height
                     and then
                       (for all Y in Output.Pixels'Range (1)
                        => (for all X in Output.Pixels'Range (2)
                            => Output.Pixels (Y, X)
                                 = High_Byte (Image.Pixels (Y, X))))
                else Output = null);
   --  The high bytes of a 16-bit image.

   procedure Convert_16
     (Image  : access constant KI.Ks_Image_16_Grey_Data;
      Output : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status) is
   begin
      KI.Create (Image.Width, Image.Height, 0, Output, Status);
      if not Succeeded (Status) then
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "ImageConvert: not enough memory for the output image");
         return;
      end if;
      for Y in Output.Pixels'Range (1) loop
         for X in Output.Pixels'Range (2) loop
            Output.Pixels (Y, X) := High_Byte (Image.Pixels (Y, X));
            pragma Loop_Invariant
              (KI.Valid_Image (Output)
               and then Output.Width = Image.Width
               and then Output.Height = Image.Height);
            pragma Loop_Invariant
              (for all J in 0 .. Y - 1
               => (for all I in Output.Pixels'Range (2)
                   => Output.Pixels (J, I)
                        = High_Byte (Image.Pixels (J, I))));
            pragma Loop_Invariant
              (for all I in 0 .. X
               => Output.Pixels (Y, I) = High_Byte (Image.Pixels (Y, I)));
         end loop;
         pragma Loop_Invariant
           (KI.Valid_Image (Output)
            and then Output.Width = Image.Width
            and then Output.Height = Image.Height);
         pragma Loop_Invariant
           (for all J in 0 .. Y
            => (for all I in Output.Pixels'Range (2)
                => Output.Pixels (J, I) = High_Byte (Image.Pixels (J, I))));
      end loop;
      Set_Success (Status);
   end Convert_16;

   procedure Convert_Colour
     (Red, Green, Blue : access constant KI.Ks_Image_8_Grey_Data;
      Params           : Ks_Image_Convert_Run_Params;
      Output           : out KI.Ks_Image_8_Grey;
      Status           : out Ks_Status)
   with
     Pre  => Same_Planes (Red, Green, Blue) and then SM.Usable_Image (Red)
             and then Valid_Weights (Params),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then KI.Valid_Image (Output)
                     and then Output.Width = Red.Width
                     and then Output.Height = Red.Height
                     and then
                       (for all Y in Output.Pixels'Range (1)
                        => (for all X in Output.Pixels'Range (2)
                            => Output.Pixels (Y, X)
                                 = Colour_Pixel (Params,
                                                 Red.Pixels (Y, X),
                                                 Green.Pixels (Y, X),
                                                 Blue.Pixels (Y, X))))
                else Output = null);
   --  The conversion of a colour image.

   procedure Convert_Colour
     (Red, Green, Blue : access constant KI.Ks_Image_8_Grey_Data;
      Params           : Ks_Image_Convert_Run_Params;
      Output           : out KI.Ks_Image_8_Grey;
      Status           : out Ks_Status) is
   begin
      KI.Create (Red.Width, Red.Height, 0, Output, Status);
      if not Succeeded (Status) then
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "ImageConvert: not enough memory for the output image");
         return;
      end if;
      for Y in Output.Pixels'Range (1) loop
         for X in Output.Pixels'Range (2) loop
            Output.Pixels (Y, X) :=
              Colour_Pixel (Params, Red.Pixels (Y, X), Green.Pixels (Y, X),
                            Blue.Pixels (Y, X));
            pragma Loop_Invariant
              (KI.Valid_Image (Output)
               and then Output.Width = Red.Width
               and then Output.Height = Red.Height);
            pragma Loop_Invariant
              (for all J in 0 .. Y - 1
               => (for all I in Output.Pixels'Range (2)
                   => Output.Pixels (J, I)
                        = Colour_Pixel (Params, Red.Pixels (J, I),
                                        Green.Pixels (J, I),
                                        Blue.Pixels (J, I))));
            pragma Loop_Invariant
              (for all I in 0 .. X
               => Output.Pixels (Y, I)
                    = Colour_Pixel (Params, Red.Pixels (Y, I),
                                    Green.Pixels (Y, I),
                                    Blue.Pixels (Y, I)));
         end loop;
         pragma Loop_Invariant
           (KI.Valid_Image (Output)
            and then Output.Width = Red.Width
            and then Output.Height = Red.Height);
         pragma Loop_Invariant
           (for all J in 0 .. Y
            => (for all I in Output.Pixels'Range (2)
                => Output.Pixels (J, I)
                     = Colour_Pixel (Params, Red.Pixels (J, I),
                                     Green.Pixels (J, I),
                                     Blue.Pixels (J, I))));
      end loop;
      Set_Success (Status);
   end Convert_Colour;

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
   is
      Kind : Input_Kind;
   begin
      Output := null;
      Check_Input (Grey_8, Grey_16, Red, Green, Blue, Kind, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Params (Params, Status);
      if not Succeeded (Status) then
         return;
      end if;
      if Kind /= Kind_Colour and then Params.Run_Mode /= Run_Mode_Intensity
      then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "RunParams.RunMode " & Mode_Name (Params.Run_Mode)
                      & " needs a colour InputImage");
         return;
      end if;
      case Kind is
         when Kind_8_Grey =>
            KI.Duplicate (Grey_8, Output, Status);
            if not Succeeded (Status) then
               Set_Failure (Status, Failure_Out_Of_Memory,
                            "ImageConvert: not enough memory for the output "
                            & "image");
            end if;
         when Kind_16_Grey =>
            Convert_16 (Grey_16, Output, Status);
         when Kind_Colour =>
            Convert_Colour (Red, Green, Blue, Params, Output, Status);
      end case;
   end Execute;

end AMV.Kernels.Image_Convert;
