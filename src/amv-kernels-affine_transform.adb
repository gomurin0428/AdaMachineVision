pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Numerics.Long_Elementary_Functions;

with AMV.Kernels.Image_Sampling;
with AMV.Kernels.Numerics;

package body AMV.Kernels.Affine_Transform with SPARK_Mode is

   pragma Unevaluated_Use_Of_Old (Allow);
   --  Postconditions keep the size of an image through the total ghost
   --  function Size_Of (contracts are proved, never executed).

   package EF renames Ada.Numerics.Long_Elementary_Functions;
   package SM renames AMV.Kernels.Image_Sampling;
   package N renames AMV.Kernels.Numerics;

   use type KI.Image_Size;

   procedure Run_Params_Default (Params : out Ks_Affine_Transform) is
   begin
      Params := (others => <>);
   end Run_Params_Default;

   ---------------------------------------------------------------------
   --  The output size
   ---------------------------------------------------------------------

   function Pixel_Side_Length
     (Region            : KS.Ks_Rectangle_Affine;
      Pixel_From_Region : KT.Ks_Transform_2D_Linear;
      Side_Y            : Boolean) return Long_Float
   is
      Angle  : constant Long_Float :=
        (if Side_Y then Region.Rotation + Region.Skew else Region.Rotation);
      Length : constant Long_Float :=
        (if Side_Y then Region.Side_Y_Length else Region.Side_X_Length);
      Cos_A  : constant Long_Float := EF.Cos (Angle);
      Sin_A  : constant Long_Float := EF.Sin (Angle);
      --  The side vector in the region's space.
      VX     : constant Long_Float :=
        (if Side_Y then -N.Times_Unit (Length, Sin_A)
         else N.Times_Unit (Length, Cos_A));
      VY     : constant Long_Float :=
        (if Side_Y then N.Times_Unit (Length, Cos_A)
         else N.Times_Unit (Length, Sin_A));
      --  Mapped into pixel space (each term at most 4.0E300).
      PX     : constant Long_Float :=
        N.Mul_Within (Pixel_From_Region.A, VX, KT.Max_Value, KS.Max_Length)
        + N.Mul_Within (Pixel_From_Region.B, VY, KT.Max_Value,
                        KS.Max_Length);
      PY     : constant Long_Float :=
        N.Mul_Within (Pixel_From_Region.C, VX, KT.Max_Value, KS.Max_Length)
        + N.Mul_Within (Pixel_From_Region.D, VY, KT.Max_Value,
                        KS.Max_Length);
   begin
      return N.Hypot (PX, PY);
   end Pixel_Side_Length;

   function Output_Length (Scaling, Length : Long_Float) return Int32 is
   begin
      --  Beyond 4.0E7 pixels the product exceeds Max_Output_Side + 0.5
      --  whatever the scaling (at least 0.001).
      if Length >= 4.0E7 then
         return Max_Output_Side + 1;
      end if;
      declare
         V : constant Long_Float := Scaling * Length;
      begin
         if V < 0.5 then
            return 0;
         elsif V >= Long_Float (Max_Output_Side) + 0.5 then
            return Max_Output_Side + 1;
         else
            return Int32 (V);
         end if;
      end;
   end Output_Length;

   ---------------------------------------------------------------------
   --  Resampling
   ---------------------------------------------------------------------

   function Nearest_At
     (Image : access constant KI.Ks_Image_8_Grey_Data;
      Map   : KT.Ks_Transform_2D_Linear;
      Fill  : KI.Grey_8;
      X, Y  : Natural) return KI.Grey_8
   is
     (SM.Nearest_Sample
        (Image, SM.Map_X (Map, Long_Float (X), Long_Float (Y)),
         SM.Map_Y (Map, Long_Float (X), Long_Float (Y)), Fill))
   with Pre => KI.Valid_Image (Image) and then KT.Bounded (Map)
               and then X <= Max_Output_Side and then Y <= Max_Output_Side;
   --  The nearest-neighbour sample of output pixel (X, Y), Map mapping
   --  output pixels to input pixels.

   function Mask_At
     (Image : access constant KI.Ks_Image_8_Grey_Data;
      Map   : KT.Ks_Transform_2D_Linear;
      X, Y  : Natural) return KI.Grey_8
   is
     (if SM.Inside_Area
           (Image, SM.Map_X (Map, Long_Float (X), Long_Float (Y)),
            SM.Map_Y (Map, Long_Float (X), Long_Float (Y)))
      then 255 else 0)
   with Pre => KI.Valid_Image (Image) and then KT.Bounded (Map)
               and then X <= Max_Output_Side and then Y <= Max_Output_Side;
   --  The output image mask at (X, Y): 255 when the sample point lies in
   --  the input image, 0 when it is clipped.

   procedure Lemma_Nearest_Is_Input
     (Image : access constant KI.Ks_Image_8_Grey_Data;
      Map   : KT.Ks_Transform_2D_Linear;
      Fill  : KI.Grey_8;
      X, Y  : Natural)
   with
     Ghost,
     Pre  => KI.Valid_Image (Image) and then KT.Bounded (Map)
             and then X <= Max_Output_Side and then Y <= Max_Output_Side,
     Post => Nearest_At (Image, Map, Fill, X, Y) = Fill
             or else Is_Input_Pixel (Image, Nearest_At (Image, Map, Fill, X, Y));
   --  A nearest-neighbour sample is the fill value or an input pixel.

   procedure Lemma_Nearest_Is_Input
     (Image : access constant KI.Ks_Image_8_Grey_Data;
      Map   : KT.Ks_Transform_2D_Linear;
      Fill  : KI.Grey_8;
      X, Y  : Natural)
   is
      PX : constant Long_Float :=
        SM.Map_X (Map, Long_Float (X), Long_Float (Y));
      PY : constant Long_Float :=
        SM.Map_Y (Map, Long_Float (X), Long_Float (Y));
   begin
      if SM.Inside_Area (Image, PX, PY) then
         pragma Assert
           (Image.Pixels (SM.Nearest_Index (PY, Image.Height),
                          SM.Nearest_Index (PX, Image.Width))
              = Nearest_At (Image, Map, Fill, X, Y));
      end if;
   end Lemma_Nearest_Is_Input;

   procedure Resample
     (Image   : access constant KI.Ks_Image_8_Grey_Data;
      Map     : KT.Ks_Transform_2D_Linear;
      Nearest : Boolean;
      Fill    : KI.Grey_8;
      Output  : KI.Ks_Image_8_Grey;
      Clipped : out Boolean)
   with
     Pre  => KI.Valid_Image (Image) and then KT.Bounded (Map)
             and then KI.Valid_Image (Output)
             and then Output.Width <= Max_Output_Side
             and then Output.Height <= Max_Output_Side,
     Post => KI.Valid_Image (Output)
             and then KI.Size_Of (Output) = KI.Size_Of (Output)'Old
             and then
               (if Nearest
                then (for all Y in Output.Pixels'Range (1)
                      => (for all X in Output.Pixels'Range (2)
                          => Output.Pixels (Y, X)
                               = Nearest_At (Image, Map, Fill, X, Y))));
   --  Fills Output with the samples of Image at the points Map gives for
   --  its pixel centres. Clipped tells whether a sample point lay outside
   --  the image.

   procedure Resample
     (Image   : access constant KI.Ks_Image_8_Grey_Data;
      Map     : KT.Ks_Transform_2D_Linear;
      Nearest : Boolean;
      Fill    : KI.Grey_8;
      Output  : KI.Ks_Image_8_Grey;
      Clipped : out Boolean)
   is
      Width  : constant Int32 := Output.Width with Ghost;
      Height : constant Int32 := Output.Height with Ghost;
   begin
      Clipped := False;
      for Y in Output.Pixels'Range (1) loop
         for X in Output.Pixels'Range (2) loop
            declare
               PX : constant Long_Float :=
                 SM.Map_X (Map, Long_Float (X), Long_Float (Y));
               PY : constant Long_Float :=
                 SM.Map_Y (Map, Long_Float (X), Long_Float (Y));
            begin
               if not SM.Inside_Area (Image, PX, PY) then
                  Clipped := True;
               end if;
               if Nearest then
                  Output.Pixels (Y, X) :=
                    SM.Nearest_Sample (Image, PX, PY, Fill);
               else
                  Output.Pixels (Y, X) :=
                    SM.Bilinear_Sample (Image, PX, PY, Fill);
               end if;
            end;
            pragma Loop_Invariant
              (KI.Valid_Image (Output)
               and then Output.Width = Width
               and then Output.Height = Height);
            pragma Loop_Invariant
              (if Nearest
               then (for all J in 0 .. Y - 1
                     => (for all I in Output.Pixels'Range (2)
                         => Output.Pixels (J, I)
                              = Nearest_At (Image, Map, Fill, I, J))));
            pragma Loop_Invariant
              (if Nearest
               then (for all I in 0 .. X
                     => Output.Pixels (Y, I)
                          = Nearest_At (Image, Map, Fill, I, Y)));
         end loop;
         pragma Loop_Invariant
           (KI.Valid_Image (Output)
            and then Output.Width = Width
            and then Output.Height = Height);
         pragma Loop_Invariant
           (if Nearest
            then (for all J in 0 .. Y
                  => (for all I in Output.Pixels'Range (2)
                      => Output.Pixels (J, I)
                           = Nearest_At (Image, Map, Fill, I, J))));
      end loop;
   end Resample;

   procedure Lemma_Nearest_Output
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Map    : KT.Ks_Transform_2D_Linear;
      Fill   : KI.Grey_8;
      Output : access constant KI.Ks_Image_8_Grey_Data)
   with
     Ghost,
     Pre  => KI.Valid_Image (Image) and then KT.Bounded (Map)
             and then KI.Valid_Image (Output)
             and then Output.Width <= Max_Output_Side
             and then Output.Height <= Max_Output_Side
             and then (for all Y in Output.Pixels'Range (1)
                       => (for all X in Output.Pixels'Range (2)
                           => Output.Pixels (Y, X)
                                = Nearest_At (Image, Map, Fill, X, Y))),
     Post => (for all Y in Output.Pixels'Range (1)
              => (for all X in Output.Pixels'Range (2)
                  => Output.Pixels (Y, X) = Fill
                     or else Is_Input_Pixel (Image, Output.Pixels (Y, X))));
   --  Every pixel of a nearest-neighbour output is the fill value or an
   --  input pixel.

   procedure Lemma_Nearest_Output
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Map    : KT.Ks_Transform_2D_Linear;
      Fill   : KI.Grey_8;
      Output : access constant KI.Ks_Image_8_Grey_Data) is
   begin
      for Y in Output.Pixels'Range (1) loop
         for X in Output.Pixels'Range (2) loop
            Lemma_Nearest_Is_Input (Image, Map, Fill, X, Y);
            pragma Loop_Invariant
              (for all J in 0 .. Y - 1
               => (for all I in Output.Pixels'Range (2)
                   => Output.Pixels (J, I) = Fill
                      or else Is_Input_Pixel (Image, Output.Pixels (J, I))));
            pragma Loop_Invariant
              (for all I in 0 .. X
               => Output.Pixels (Y, I) = Fill
                  or else Is_Input_Pixel (Image, Output.Pixels (Y, I)));
         end loop;
         pragma Loop_Invariant
           (for all J in 0 .. Y
            => (for all I in Output.Pixels'Range (2)
                => Output.Pixels (J, I) = Fill
                   or else Is_Input_Pixel (Image, Output.Pixels (J, I))));
      end loop;
   end Lemma_Nearest_Output;

   procedure Fill_Mask
     (Image : access constant KI.Ks_Image_8_Grey_Data;
      Map   : KT.Ks_Transform_2D_Linear;
      Mask  : KI.Ks_Image_8_Grey)
   with
     Pre  => KI.Valid_Image (Image) and then KT.Bounded (Map)
             and then KI.Valid_Image (Mask)
             and then Mask.Width <= Max_Output_Side
             and then Mask.Height <= Max_Output_Side,
     Post => KI.Valid_Image (Mask)
             and then KI.Size_Of (Mask) = KI.Size_Of (Mask)'Old
             and then (for all Y in Mask.Pixels'Range (1)
                       => (for all X in Mask.Pixels'Range (2)
                           => Mask.Pixels (Y, X) = Mask_At (Image, Map, X, Y)));
   --  The output image mask.

   procedure Fill_Mask
     (Image : access constant KI.Ks_Image_8_Grey_Data;
      Map   : KT.Ks_Transform_2D_Linear;
      Mask  : KI.Ks_Image_8_Grey)
   is
      Width  : constant Int32 := Mask.Width with Ghost;
      Height : constant Int32 := Mask.Height with Ghost;
   begin
      for Y in Mask.Pixels'Range (1) loop
         for X in Mask.Pixels'Range (2) loop
            Mask.Pixels (Y, X) := Mask_At (Image, Map, X, Y);
            pragma Loop_Invariant
              (KI.Valid_Image (Mask)
               and then Mask.Width = Width and then Mask.Height = Height);
            pragma Loop_Invariant
              (for all J in 0 .. Y - 1
               => (for all I in Mask.Pixels'Range (2)
                   => Mask.Pixels (J, I) = Mask_At (Image, Map, I, J)));
            pragma Loop_Invariant
              (for all I in 0 .. X
               => Mask.Pixels (Y, I) = Mask_At (Image, Map, I, Y));
         end loop;
         pragma Loop_Invariant
           (KI.Valid_Image (Mask)
            and then Mask.Width = Width and then Mask.Height = Height);
         pragma Loop_Invariant
           (for all J in 0 .. Y
            => (for all I in Mask.Pixels'Range (2)
                => Mask.Pixels (J, I) = Mask_At (Image, Map, I, J)));
      end loop;
   end Fill_Mask;

   ---------------------------------------------------------------------
   --  Checks
   ---------------------------------------------------------------------

   procedure Check_Region
     (Region : KS.Ks_Rectangle_Affine;
      Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then KS.Valid_Rectangle_Affine (Region));
   --  Every property of Region finite and within the bounds of
   --  AMV.Kernels.Shapes.

   procedure Check_Region
     (Region : KS.Ks_Rectangle_Affine;
      Status : out Ks_Status) is
   begin
      if not KS.Bounded (Region.Center_X) then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "Region.CenterX must be finite and within 1.0E150");
      elsif not KS.Bounded (Region.Center_Y) then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "Region.CenterY must be finite and within 1.0E150");
      elsif not KS.Length_Bounded (Region.Side_X_Length) then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "Region.SideXLength must be in 0 .. 4.0E150");
      elsif not KS.Length_Bounded (Region.Side_Y_Length) then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "Region.SideYLength must be in 0 .. 4.0E150");
      elsif not KS.Bounded (Region.Rotation) then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "Region.Rotation must be finite and within 1.0E150");
      elsif not KS.Bounded (Region.Skew) then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "Region.Skew must be finite and within 1.0E150");
      else
         Set_Success (Status);
      end if;
   end Check_Region;

   procedure Check_Params
     (Params      : Ks_Affine_Transform;
      Create_Mask : Int32;
      Status      : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Valid_Params (Params)
                            and then Create_Mask in 0 .. 1);

   procedure Check_Params
     (Params      : Ks_Affine_Transform;
      Create_Mask : Int32;
      Status      : out Ks_Status) is
   begin
      if not (Params.Scaling_X >= Min_Scaling
              and then Params.Scaling_X <= Max_Scaling)
      then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "RunParams.ScalingX must be in 0.001 .. 1000");
      elsif not (Params.Scaling_Y >= Min_Scaling
                 and then Params.Scaling_Y <= Max_Scaling)
      then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "RunParams.ScalingY must be in 0.001 .. 1000");
      elsif Params.Sampling_Mode = Sampling_Mode_High_Precision then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "RunParams.SamplingMode HighPrecision is not "
                      & "implemented");
      elsif Params.Sampling_Mode
              not in Sampling_Mode_Nearest_Neighbor
                   | Sampling_Mode_Bilinear_Interpolation
                   | Sampling_Mode_Bilinear_Accurate
      then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "RunParams.SamplingMode must be NearestNeighbor (1), "
                      & "BilinearInterpolation (2) or BilinearAccurate (4)");
      elsif Params.Clip_Mode not in Clip_Mode_Zeroes .. Clip_Mode_Error then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "RunParams.ClipMode must be Zeroes (0), Fill (1) or "
                      & "Error (2)");
      elsif Params.Clip_Fill_Value not in 0 .. 255 then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "RunParams.ClipFillValue must be in 0 .. 255");
      elsif Create_Mask not in 0 .. 1 then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "CreateOutputImageMask must be 0 or 1");
      else
         Set_Success (Status);
      end if;
   end Check_Params;

   procedure Check_Size
     (Width, Height : Int32;
      Status        : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Width in 1 .. Max_Output_Side
                            and then Height in 1 .. Max_Output_Side);
   --  The size limits of VisionPro (an output of at least 1 and at most
   --  32767 pixels along each axis).

   procedure Check_Size
     (Width, Height : Int32;
      Status        : out Ks_Status) is
   begin
      if Width < 1 then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "the output image would be less than 1 pixel wide "
                      & "(RunParams.ScalingX times Region.SideXLength in "
                      & "pixels)");
      elsif Width > Max_Output_Side then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "the output image would be more than 32767 pixels "
                      & "wide (RunParams.ScalingX times Region.SideXLength "
                      & "in pixels)");
      elsif Height < 1 then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "the output image would be less than 1 pixel high "
                      & "(RunParams.ScalingY times Region.SideYLength in "
                      & "pixels)");
      elsif Height > Max_Output_Side then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "the output image would be more than 32767 pixels "
                      & "high (RunParams.ScalingY times Region.SideYLength "
                      & "in pixels)");
      else
         Set_Success (Status);
      end if;
   end Check_Size;

   procedure Sampling_Map
     (Region            : KS.Ks_Rectangle_Affine;
      Pixel_From_Region : KT.Ks_Transform_2D_Linear;
      Pixel_From_Root   : KT.Ks_Transform_2D_Linear;
      Width, Height     : Int32;
      Map               : out KT.Ks_Transform_2D_Linear;
      Output_From_Root  : out KT.Ks_Transform_2D_Linear;
      Status            : out Ks_Status)
   with
     Pre  => KS.Valid_Rectangle_Affine (Region)
             and then KT.Bounded (Pixel_From_Region)
             and then KT.Bounded (Pixel_From_Root)
             and then Width in 1 .. Max_Output_Side
             and then Height in 1 .. Max_Output_Side,
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Transform_Singular
             and then (if Succeeded (Status)
                       then KT.Bounded (Map)
                            and then KT.Bounded (Output_From_Root));
   --  Map: the transform from output pixels to input pixels (the region's
   --  frame scaled to the output size, with the half-pixel offset of the
   --  pixel centres, mapped into pixel space); Output_From_Root: the
   --  output's pixel-from-root transform, Invert (Map) composed with
   --  Pixel_From_Root, whose own inverse is within the bound too (so that
   --  an image accepts it).

   procedure Sampling_Map
     (Region            : KS.Ks_Rectangle_Affine;
      Pixel_From_Region : KT.Ks_Transform_2D_Linear;
      Pixel_From_Root   : KT.Ks_Transform_2D_Linear;
      Width, Height     : Int32;
      Map               : out KT.Ks_Transform_2D_Linear;
      Output_From_Root  : out KT.Ks_Transform_2D_Linear;
      Status            : out Ks_Status)
   is
      Frame     : KT.Ks_Transform_2D_Linear;
      Pixel_Map : KT.Ks_Transform_2D_Linear;
      Inverse   : KT.Ks_Transform_2D_Linear;
      --  The steps between output pixel centres in the region's frame.
      Step_X    : constant Long_Float :=
        Region.Side_X_Length / Long_Float (Width);
      Step_Y    : constant Long_Float :=
        Region.Side_Y_Length / Long_Float (Height);
   begin
      Map := (others => <>);
      Output_From_Root := (others => <>);
      if not (Step_X <= KT.Max_Value and then Step_Y <= KT.Max_Value) then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "Region: the step between output pixels exceeds "
                      & "1.0E150 in Region's space");
         return;
      end if;
      KS.Get_Parent_From_Child_Transform (Region, Frame, Status);
      if not Succeeded (Status) then
         return;
      end if;
      KT.Compose (Pixel_From_Region, Frame, Pixel_Map, Status);
      if Succeeded (Status) then
         KT.Compose
           (Pixel_Map,
            (A             => Step_X,
             B             => 0.0,
             C             => 0.0,
             D             => Step_Y,
             Translation_X => 0.5 * Step_X,
             Translation_Y => 0.5 * Step_Y),
            Map, Status);
      end if;
      if not Succeeded (Status) then
         Map := (others => <>);
         Set_Failure (Status, Failure_Bad_Parameter,
                      "Region: the transform from output to input pixels "
                      & "exceeds 1.0E150");
         return;
      end if;
      KT.Invert (Map, Inverse, Status);
      if not Succeeded (Status) then
         Set_Failure (Status, Failure_Transform_Singular,
                      "Region is too flat: the output image has no "
                      & "pixel-from-root transform within 1.0E150");
         return;
      end if;
      KT.Compose (Inverse, Pixel_From_Root, Output_From_Root, Status);
      if not Succeeded (Status) then
         Output_From_Root := (others => <>);
         Set_Failure (Status, Failure_Bad_Parameter,
                      "the pixel-from-root transform of the output image "
                      & "exceeds 1.0E150");
         return;
      end if;
      --  The output image must accept it (an inverse within the bound).
      declare
         Root_From_Output : KT.Ks_Transform_2D_Linear;
      begin
         KT.Invert (Output_From_Root, Root_From_Output, Status);
         --  Only whether the inverse exists matters here.
         pragma Assert
           (if Succeeded (Status) then KT.Bounded (Root_From_Output));
      end;
      if not Succeeded (Status) then
         Output_From_Root := (others => <>);
         Set_Failure (Status, Failure_Transform_Singular,
                      "the pixel-from-root transform of the output image has "
                      & "no inverse within 1.0E150");
      end if;
   end Sampling_Map;

   ---------------------------------------------------------------------
   --  Entry point
   ---------------------------------------------------------------------

   procedure Check_Input_Image
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Status : out Ks_Status) is
   begin
      SM.Check_Image (Image, SM.Input_Image, Status);
   end Check_Input_Image;

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
   is
      Width, Height : Int32;
      Map           : KT.Ks_Transform_2D_Linear;
      Clipped       : Boolean;
      Ignored       : Ks_Status;
   begin
      Output := null;
      Output_Mask := null;
      Output_Pixel_From_Root := (others => <>);
      SM.Check_Image (Image, SM.Input_Image, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Region (Region, Status);
      if not Succeeded (Status) then
         return;
      end if;
      if not KT.Bounded (Pixel_From_Region) then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "the transform from Region's space to pixel space "
                      & "must be finite and within 1.0E150");
         return;
      elsif not KT.Bounded (Pixel_From_Root) then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "InputImage.PixelFromRootTransform must be finite and "
                      & "within 1.0E150");
         return;
      end if;
      Check_Params (Params, Create_Mask, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Width := Output_Width (Region, Pixel_From_Region, Params);
      Height := Output_Height (Region, Pixel_From_Region, Params);
      Check_Size (Width, Height, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Sampling_Map (Region, Pixel_From_Region, Pixel_From_Root, Width,
                    Height, Map, Output_Pixel_From_Root, Status);
      if not Succeeded (Status) then
         Output_Pixel_From_Root := (others => <>);
         return;
      end if;

      KI.Create (Width, Height, 0, Output, Status);
      if not Succeeded (Status) then
         Output_Pixel_From_Root := (others => <>);
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "AffineTransform: not enough memory for the output "
                      & "image");
         return;
      end if;
      Resample (Image, Map,
                Params.Sampling_Mode = Sampling_Mode_Nearest_Neighbor,
                Fill_Value (Params), Output, Clipped);
      if Params.Sampling_Mode = Sampling_Mode_Nearest_Neighbor then
         Lemma_Nearest_Output (Image, Map, Fill_Value (Params), Output);
      end if;
      if Clipped and then Params.Clip_Mode = Clip_Mode_Error then
         KI.Destroy (Output, Ignored);
         Output_Pixel_From_Root := (others => <>);
         Set_Failure (Status, Failure_Bad_Parameter,
                      "Region lies partly outside InputImage "
                      & "(RunParams.ClipMode is Error)");
         return;
      end if;

      if Create_Mask = True_Value then
         KI.Create (Width, Height, 0, Output_Mask, Status);
         if not Succeeded (Status) then
            KI.Destroy (Output, Ignored);
            Output_Pixel_From_Root := (others => <>);
            Set_Failure (Status, Failure_Out_Of_Memory,
                         "AffineTransform: not enough memory for the output "
                         & "image mask");
            return;
         end if;
         Fill_Mask (Image, Map, Output_Mask);
      end if;
      Set_Success (Status);
   end Execute;

end AMV.Kernels.Affine_Transform;
