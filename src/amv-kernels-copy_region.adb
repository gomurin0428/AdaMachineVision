pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Image_Sampling;

package body AMV.Kernels.Copy_Region with SPARK_Mode is

   package SM renames AMV.Kernels.Image_Sampling;

   procedure Run_Params_Default (Params : out Ks_Copy_Region) is
   begin
      Params := (others => <>);
   end Run_Params_Default;

   procedure Check_Region
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Status : out Ks_Status)
   with
     Pre  => KI.Valid_Image (Image),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Usable_Input (Image, Region));

   procedure Check_Region
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Status : out Ks_Status) is
   begin
      if Region = null then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "Region covers no pixel of InputImage");
      elsif not KR.Valid_Region (Region) then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "Region is not a valid pixel region handle");
      elsif not KR.In_Image (Region, Image.Width, Image.Height) then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "Region does not lie in InputImage");
      else
         Set_Success (Status);
      end if;
   end Check_Region;

   procedure Check_Params
     (Params : Ks_Copy_Region;
      Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status) then Valid_Params (Params));

   procedure Check_Params
     (Params : Ks_Copy_Region;
      Status : out Ks_Status) is
   begin
      if Params.Fill_Bounding_Box not in 0 .. 1 then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "RunParams.FillBoundingBox must be 0 or 1");
      elsif Params.Fill_Bounding_Box_Value not in 0 .. 255 then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "RunParams.FillBoundingBoxValue must be in 0 .. 255");
      elsif Params.Fill_Region not in 0 .. 1 then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "RunParams.FillRegion must be 0 or 1");
      elsif Params.Fill_Region_Value not in 0 .. 255 then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "RunParams.FillRegionValue must be in 0 .. 255");
      elsif Params.Region_Mode = Region_Mode_Affine_Transform then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "RunParams.RegionMode AffineTransform is not "
                      & "implemented");
      elsif Params.Region_Mode
              not in Region_Mode_Pixel_Aligned_Bounding_Box_Adjust_Mask
                   | Region_Mode_Pixel_Aligned_Bounding_Box
      then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "RunParams.RegionMode must be "
                      & "PixelAlignedBoundingBoxAdjustMask (0) or "
                      & "PixelAlignedBoundingBox (1)");
      else
         Set_Success (Status);
      end if;
   end Check_Params;

   procedure Check_Input_Image
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Status : out Ks_Status) is
   begin
      SM.Check_Image (Image, SM.Input_Image, Status);
   end Check_Input_Image;

   procedure Execute
     (Image                  : access constant KI.Ks_Image_8_Grey_Data;
      Region                 : access constant KR.Ks_Pixel_Region_Data;
      Pixel_From_Root        : KT.Ks_Transform_2D_Linear;
      Params                 : Ks_Copy_Region;
      Output                 : out KI.Ks_Image_8_Grey;
      Output_Pixel_From_Root : out KT.Ks_Transform_2D_Linear;
      Status                 : out Ks_Status) is
   begin
      Output := null;
      Output_Pixel_From_Root := (others => <>);
      SM.Check_Image (Image, SM.Input_Image, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Region (Image, Region, Status);
      if not Succeeded (Status) then
         return;
      end if;
      if not KT.Bounded (Pixel_From_Root) then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "InputImage.PixelFromRootTransform must be finite and "
                      & "within 1.0E150");
         return;
      end if;
      Check_Params (Params, Status);
      if not Succeeded (Status) then
         return;
      end if;

      --  The output's pixel space is the input's shifted by the corner of
      --  the bounding box.
      KT.Compose
        ((A             => 1.0,
          B             => 0.0,
          C             => 0.0,
          D             => 1.0,
          Translation_X => -Long_Float (Region.X_Min),
          Translation_Y => -Long_Float (Region.Y_Min)),
         Pixel_From_Root, Output_Pixel_From_Root, Status);
      if not Succeeded (Status) then
         Output_Pixel_From_Root := (others => <>);
         Set_Failure (Status, Failure_Bad_Parameter,
                      "the pixel-from-root transform of the output image "
                      & "exceeds 1.0E150");
         return;
      end if;
      --  The output image must accept it (an inverse within the bound).
      declare
         Inverse : KT.Ks_Transform_2D_Linear;
      begin
         KT.Invert (Output_Pixel_From_Root, Inverse, Status);
         --  Only whether the inverse exists matters here.
         pragma Assert (if Succeeded (Status) then KT.Bounded (Inverse));
      end;
      if not Succeeded (Status) then
         Output_Pixel_From_Root := (others => <>);
         Set_Failure (Status, Failure_Transform_Singular,
                      "the pixel-from-root transform of the output image has "
                      & "no inverse within 1.0E150");
         return;
      end if;

      KI.Create (Region.Width, Region.Height, 0, Output, Status);
      if not Succeeded (Status) then
         Output_Pixel_From_Root := (others => <>);
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "CopyRegion: not enough memory for the output image");
         return;
      end if;
      for Y in Output.Pixels'Range (1) loop
         for X in Output.Pixels'Range (2) loop
            Output.Pixels (Y, X) := Copied_Pixel (Image, Region, Params, X, Y);
            pragma Loop_Invariant
              (KI.Valid_Image (Output)
               and then Output.Width = Region.Width
               and then Output.Height = Region.Height);
            pragma Loop_Invariant
              (for all J in 0 .. Y - 1
               => (for all I in Output.Pixels'Range (2)
                   => Output.Pixels (J, I)
                        = Copied_Pixel (Image, Region, Params, I, J)));
            pragma Loop_Invariant
              (for all I in 0 .. X
               => Output.Pixels (Y, I)
                    = Copied_Pixel (Image, Region, Params, I, Y));
         end loop;
         pragma Loop_Invariant
           (KI.Valid_Image (Output)
            and then Output.Width = Region.Width
            and then Output.Height = Region.Height);
         pragma Loop_Invariant
           (for all J in 0 .. Y
            => (for all I in Output.Pixels'Range (2)
                => Output.Pixels (J, I)
                     = Copied_Pixel (Image, Region, Params, I, J)));
      end loop;
      Set_Success (Status);
   end Execute;

end AMV.Kernels.Copy_Region;
