pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Unchecked_Deallocation;

package body AMV.Kernels.CNL_Search.Region_Modes with SPARK_Mode is

   use type KI.Grey_8;
   use type KR.Flag_Matrix_Access;

   procedure Free is new Ada.Unchecked_Deallocation
     (KI.Grey_8_Matrix, KI.Grey_8_Pixels);
   procedure Free is new Ada.Unchecked_Deallocation
     (KI.Ks_Image_8_Grey_Data, KI.Ks_Image_8_Grey);
   procedure Free is new Ada.Unchecked_Deallocation
     (KR.Flag_Matrix, KR.Flag_Matrix_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (KR.Ks_Pixel_Region_Data, KR.Ks_Pixel_Region);

   Identity : constant KT.Ks_Transform_2D_Linear := (others => <>);

   Care_Sampling : constant KA.Ks_Affine_Transform :=
     (Sampling_Mode   => KA.Sampling_Mode_Nearest_Neighbor,
      Clip_Mode       => KA.Clip_Mode_Fill,
      Clip_Fill_Value => 255,
      others          => <>);
   --  The resampling of the train image mask: nearest neighbour, 255
   --  ("care") where the mask does not reach.

   procedure Bad (Status : out Ks_Status; Message : String)
   with Post => Valid (Status) and then Status.Failure = Failure_Bad_Parameter;

   procedure Bad (Status : out Ks_Status; Message : String) is
   begin
      Set_Failure (Status, Failure_Bad_Parameter, Message);
   end Bad;

   procedure Check_Affine_Train_Region
     (Kind   : Int32;
      Status : out Ks_Status) is
   begin
      if Kind = KSH.Shape_Rectangle_Affine then
         Set_Success (Status);
      else
         Bad (Status, "TrainRegion must be an affine rectangle for "
              & "TrainRegionMode AffineTransform");
      end if;
   end Check_Affine_Train_Region;

   procedure Check_Rectangle
     (Region : KSH.Ks_Rectangle_Affine;
      Name   : String;
      Status : out Ks_Status)
   with
     Pre  => Name'First = 1 and then Name'Length <= 20,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then KSH.Valid_Rectangle_Affine (Region));
   --  Every value of the affine rectangle Name finite and within the
   --  bounds of AMV.Kernels.Shapes.

   procedure Check_Rectangle
     (Region : KSH.Ks_Rectangle_Affine;
      Name   : String;
      Status : out Ks_Status) is
   begin
      if not KSH.Bounded (Region.Center_X) then
         Bad (Status, Name & ".CenterX must be finite and within 1.0E150");
      elsif not KSH.Bounded (Region.Center_Y) then
         Bad (Status, Name & ".CenterY must be finite and within 1.0E150");
      elsif not KSH.Length_Bounded (Region.Side_X_Length) then
         Bad (Status, Name & ".SideXLength must be in 0 .. 4.0E150");
      elsif not KSH.Length_Bounded (Region.Side_Y_Length) then
         Bad (Status, Name & ".SideYLength must be in 0 .. 4.0E150");
      elsif not KSH.Bounded (Region.Rotation) then
         Bad (Status, Name & ".Rotation must be finite and within 1.0E150");
      elsif not KSH.Bounded (Region.Skew) then
         Bad (Status, Name & ".Skew must be finite and within 1.0E150");
      else
         Set_Success (Status);
      end if;
   end Check_Rectangle;

   function All_Inside
     (Mask : access constant KI.Ks_Image_8_Grey_Data) return Boolean
   with Pre => KI.Valid_Image (Mask);
   --  No pixel of the resampling's output image mask is 0: every sample
   --  point lay in the input image.

   function All_Inside
     (Mask : access constant KI.Ks_Image_8_Grey_Data) return Boolean is
   begin
      for Y in Mask.Pixels'Range (1) loop
         for X in Mask.Pixels'Range (2) loop
            if Mask.Pixels (Y, X) = 0 then
               return False;
            end if;
         end loop;
      end loop;
      return True;
   end All_Inside;

   ---------------------------------------------------------------------
   --  Training
   ---------------------------------------------------------------------

   procedure Train_Affine
     (Pattern             : in out Ks_CNL_Search_Pattern;
      Image               : access constant KI.Ks_Image_8_Grey_Data;
      Region              : KSH.Ks_Rectangle_Affine;
      Pixel_From_Region   : KT.Ks_Transform_2D_Linear;
      Pixel_From_Selected : KT.Ks_Transform_2D_Linear;
      Mask                : access constant KI.Ks_Image_8_Grey_Data;
      Mask_Offset_X       : Int32;
      Mask_Offset_Y       : Int32;
      Status              : out Ks_Status)
   is
      Width, Height         : Int32;
      Sampled               : KI.Ks_Image_8_Grey;
      Inside                : KI.Ks_Image_8_Grey;
      Care                  : KI.Ks_Image_8_Grey;
      No_Mask               : KI.Ks_Image_8_Grey;
      Pattern_From_Selected : KT.Ks_Transform_2D_Linear;
      Mask_From_Region      : KT.Ks_Transform_2D_Linear;
      Unused                : KT.Ks_Transform_2D_Linear;
      OX, OY                : Long_Float;
   begin
      --  Untrained first (an inconsistent pattern is reset).
      Pattern_Untrain (Pattern, Status);
      if not Succeeded (Status) then
         return;
      elsif Pattern = null
        or else Pattern.Params.Train_Region_Mode
                  /= Region_Mode_Affine_Transform
      then
         Bad (Status, "Pattern.TrainRegionMode must be AffineTransform (2) "
              & "for ks_cnl_search_pattern_train_affine");
         return;
      end if;
      Check_Train_Image (Image, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Rectangle (Region, "TrainRegion", Status);
      if not Succeeded (Status) then
         return;
      elsif not KT.Bounded (Pixel_From_Region) then
         Bad (Status, "the transform from TrainRegion's space to pixel space "
              & "must be finite and within 1.0E150");
         return;
      elsif not KT.Bounded (Pixel_From_Selected) then
         Bad (Status, "Pixel_From_Selected must be finite and within "
              & "1.0E150");
         return;
      elsif Mask /= null and then not KI.Valid_Image (Mask) then
         Bad (Status, "TrainImageMask is not a valid image handle");
         return;
      end if;
      Width := Resampled_Width (Region, Pixel_From_Region);
      Height := Resampled_Height (Region, Pixel_From_Region);
      if Width < Min_Pattern_Side or else Height < Min_Pattern_Side then
         Bad (Status, "TrainRegion must span at least 8 x 8 pixels");
         return;
      elsif Width > Max_Pattern_Side or else Height > Max_Pattern_Side then
         Bad (Status, "TrainRegion must span at most 1024 x 1024 pixels");
         return;
      end if;

      --  The pattern: the rectangle resampled, with its pixel-from-
      --  selected transform and the mask of the samples inside the image.
      KA.Execute (Image, Region, Pixel_From_Region, Pixel_From_Selected,
                  Resampling, True_Value, Sampled, Inside,
                  Pattern_From_Selected, Status);
      if not Succeeded (Status) then
         return;
      end if;
      pragma Assert (Sampled.Width = Width and then Sampled.Height = Height);
      if not All_Inside (Inside) then
         Free (Sampled.Pixels);
         Free (Sampled);
         Free (Inside.Pixels);
         Free (Inside);
         Bad (Status, "TrainRegion must lie entirely in TrainImage for "
              & "TrainRegionMode AffineTransform");
         return;
      end if;
      Free (Inside.Pixels);
      Free (Inside);

      --  The origin in the pattern's pixels.
      KT.Map_Point (Pattern_From_Selected, Pattern.Params.Origin_X,
                    Pattern.Params.Origin_Y, OX, OY, Status);
      if not Succeeded (Status)
        or else OX < -Max_Origin or else OX > Max_Origin
        or else OY < -Max_Origin or else OY > Max_Origin
      then
         Free (Sampled.Pixels);
         Free (Sampled);
         Bad (Status, "Pattern.OriginX, OriginY lie more than 1.0E140 "
              & "pixels from TrainRegion");
         return;
      end if;

      --  The care flags: the mask resampled with the same rectangle (mask
      --  pixel coordinates are train image pixel coordinates minus the
      --  offsets).
      if Mask /= null then
         KT.Compose
           ((A             => 1.0,
             B             => 0.0,
             C             => 0.0,
             D             => 1.0,
             Translation_X => -Long_Float (Mask_Offset_X),
             Translation_Y => -Long_Float (Mask_Offset_Y)),
            Pixel_From_Region, Mask_From_Region, Status);
         if not Succeeded (Status) then
            Free (Sampled.Pixels);
            Free (Sampled);
            Bad (Status, "TrainImageMaskOffsetX, TrainImageMaskOffsetY move "
                 & "TrainRegion beyond 1.0E150");
            return;
         end if;
         KA.Execute (Mask, Region, Mask_From_Region, Identity, Care_Sampling,
                     False_Value, Care, No_Mask, Unused, Status);
         if not Succeeded (Status) then
            Free (Sampled.Pixels);
            Free (Sampled);
            return;
         end if;
         pragma Assert (No_Mask = null);
         --  Only the translation differs: the same size (checked).
         if Care.Width /= Sampled.Width or else Care.Height /= Sampled.Height
         then
            Free (Sampled.Pixels);
            Free (Sampled);
            Free (Care.Pixels);
            Free (Care);
            Bad (Status, "TrainImageMask cannot be resampled with "
                 & "TrainRegion");
            return;
         end if;
      end if;

      Restore_Trained (Pattern, Sampled, Care, OX, OY, Status);
      pragma Assert
        (if Succeeded (Status)
         then Int64 (Pattern.Info (0).Geometry.Width) = Int64 (Width)
              and then Int64 (Pattern.Info (0).Geometry.Height)
                         = Int64 (Height));
      pragma Assert
        (if Succeeded (Status) and then Mask = null
         then Pattern.Care = null);
      Free (Sampled.Pixels);
      Free (Sampled);
      if Care /= null then
         Free (Care.Pixels);
      end if;
      Free (Care);
   end Train_Affine;

   ---------------------------------------------------------------------
   --  Searching
   ---------------------------------------------------------------------

   procedure Execute_Affine
     (Image               : access constant KI.Ks_Image_8_Grey_Data;
      Region              : KSH.Ks_Rectangle_Affine;
      Pixel_From_Region   : KT.Ks_Transform_2D_Linear;
      Pattern             : access constant Ks_CNL_Search_Pattern_Data;
      Params              : Ks_CNL_Search_Run_Params;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Results             : out Ks_CNL_Search_Results;
      Status              : out Ks_Status)
   is
      Width, Height         : Int32;
      Sampled               : KI.Ks_Image_8_Grey;
      No_Mask               : KI.Ks_Image_8_Grey;
      Sampled_From_Pixel    : KT.Ks_Transform_2D_Linear;
      Pixel_From_Sampled    : KT.Ks_Transform_2D_Linear;
      Selected_From_Sampled : KT.Ks_Transform_2D_Linear;
      Whole                 : KR.Ks_Pixel_Region;
   begin
      Results := null;
      Check_Input_Image (Image, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Search (Pattern, Params, Status);
      if not Succeeded (Status) then
         return;
      elsif Params.Search_Region_Mode /= Region_Mode_Affine_Transform then
         Bad (Status, "RunParams.SearchRegionMode PixelAlignedBoundingBox "
              & "needs a pixel region (ks_cnl_search_execute)");
         return;
      end if;
      Check_Rectangle (Region, "SearchRegion", Status);
      if not Succeeded (Status) then
         return;
      elsif not KT.Bounded (Pixel_From_Region) then
         Bad (Status, "the transform from SearchRegion's space to pixel "
              & "space must be finite and within 1.0E150");
         return;
      elsif not KT.Bounded (Selected_From_Pixel) then
         Bad (Status, "Selected_From_Pixel must be finite and within "
              & "1.0E150");
         return;
      end if;
      Width := Resampled_Width (Region, Pixel_From_Region);
      Height := Resampled_Height (Region, Pixel_From_Region);
      if Int64 (Width) < Int64 (Pattern.Info (0).Geometry.Width)
        or else Int64 (Height) < Int64 (Pattern.Info (0).Geometry.Height)
      then
         --  No position: no results (the empty region).
         Execute (Image, null, Pattern, Params, Selected_From_Pixel, Results,
                  Status);
         return;
      elsif Int64 (Width) * Int64 (Height) > Max_Search_Pixels then
         Bad (Status, "SearchRegion: the resampled rectangle must have at "
              & "most 16777216 pixels");
         return;
      end if;

      --  The rectangle resampled, and the transform from its pixels to
      --  the input image's selected space.
      KA.Execute (Image, Region, Pixel_From_Region, Identity, Resampling,
                  False_Value, Sampled, No_Mask, Sampled_From_Pixel, Status);
      if not Succeeded (Status) then
         return;
      end if;
      pragma Assert (No_Mask = null);
      pragma Assert (Sampled.Width = Width and then Sampled.Height = Height);
      KT.Invert (Sampled_From_Pixel, Pixel_From_Sampled, Status);
      if not Succeeded (Status) then
         Free (Sampled.Pixels);
         Free (Sampled);
         Set_Failure (Status, Failure_Transform_Singular,
                      "SearchRegion is too flat: the resampled image has no "
                      & "transform to pixel space within 1.0E150");
         return;
      end if;
      KT.Compose (Selected_From_Pixel, Pixel_From_Sampled,
                  Selected_From_Sampled, Status);
      if not Succeeded (Status) then
         Free (Sampled.Pixels);
         Free (Sampled);
         Bad (Status, "the transform from the resampled SearchRegion to the "
              & "selected space exceeds 1.0E150");
         return;
      end if;
      KR.Whole_Image (Sampled.Width, Sampled.Height, Whole, Status);
      if not Succeeded (Status) then
         Free (Sampled.Pixels);
         Free (Sampled);
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "CNL search: out of memory");
         return;
      end if;

      Execute (Sampled, Whole, Pattern, Params, Selected_From_Sampled,
               Results, Status);
      pragma Assert
        (if Succeeded (Status) and then Results.Count > 0
         then Area_In_Image (Results, Width, Height));
      Free (Whole.Flags);
      Free (Whole);
      Free (Sampled.Pixels);
      Free (Sampled);
   end Execute_Affine;

end AMV.Kernels.CNL_Search.Region_Modes;
