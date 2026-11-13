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

package body AMV.Kernels.Polar_Unwrap with SPARK_Mode is

   pragma Unevaluated_Use_Of_Old (Allow);
   --  Postconditions keep the size of an image through the total ghost
   --  function Size_Of (contracts are proved, never executed).

   package EF renames Ada.Numerics.Long_Elementary_Functions;
   package SM renames AMV.Kernels.Image_Sampling;
   package N renames AMV.Kernels.Numerics;

   use type KI.Image_Size;

   procedure Run_Params_Default (Params : out Ks_Polar_Unwrap) is
   begin
      Params := (others => <>);
   end Run_Params_Default;

   ---------------------------------------------------------------------
   --  The output size
   ---------------------------------------------------------------------

   function Pixel_Scale (T : KT.Ks_Transform_2D_Linear) return Long_Float is
      --  At most 2**1021: each product is at most 2**1020.
      Det  : constant Long_Float := abs (N.Mul (T.A, T.D) - N.Mul (T.B, T.C));
      Root : constant Long_Float := EF.Sqrt (Det);
   begin
      --  The root of at most 2**1021 is below 2**511; the runtime's Sqrt
      --  has no upper bound in its contract, so the limit states it (it
      --  never acts; docs/PROOF.md).
      if Root > 2.0 ** 511 then
         return 2.0 ** 511;
      end if;
      return Root;
   end Pixel_Scale;

   function Saturating_Product (X, Y : Long_Float) return Long_Float
   with
     Pre  => X >= 0.0 and then X <= Max_Pixel_Length
             and then Y >= 0.0 and then Y <= Max_Pixel_Length,
     Post => Saturating_Product'Result >= 0.0
             and then Saturating_Product'Result <= Max_Pixel_Length;
   --  X * Y, or 2**1000 when the product exceeds 2**500 and both factors
   --  exceed 1 (a length far beyond any output size).

   function Saturating_Product (X, Y : Long_Float) return Long_Float is
   begin
      if X <= 1.0 then
         return N.Times_Unit (Y, X);
      elsif Y <= 1.0 then
         return N.Times_Unit (X, Y);
      elsif X <= 2.0 ** 500 and then Y <= 2.0 ** 500 then
         return abs N.Mul_Within (X, Y, 2.0 ** 500, 2.0 ** 500);
      else
         return Max_Pixel_Length;
      end if;
   end Saturating_Product;

   function Outer (Section : KS.Ks_Circular_Annulus_Section) return Long_Float
   is (Section.Radius * Section.Radial_Scale)
   with Pre  => Valid_Section (Section),
        Post => Outer'Result >= 0.0 and then Outer'Result <= KS.Max_Length;
   --  The radius of the end arc.

   function Arc_Length
     (Section           : KS.Ks_Circular_Annulus_Section;
      Pixel_From_Region : KT.Ks_Transform_2D_Linear) return Long_Float
   is
      Middle : constant Long_Float := (Section.Radius + Outer (Section)) / 2.0;
   begin
      return Saturating_Product
        (Saturating_Product (abs Section.Angle_Span, Middle),
         Pixel_Scale (Pixel_From_Region));
   end Arc_Length;

   function Radial_Length
     (Section           : KS.Ks_Circular_Annulus_Section;
      Pixel_From_Region : KT.Ks_Transform_2D_Linear) return Long_Float is
   begin
      return Saturating_Product (abs (Outer (Section) - Section.Radius),
                                 Pixel_Scale (Pixel_From_Region));
   end Radial_Length;

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
   --  The mapping of output points
   ---------------------------------------------------------------------

   Max_Region_Point : constant := 1.0E151;
   --  A bound of the points of the region's space that the mapping gives:
   --  the centre (1.0E150) plus a radius of at most 8.0E150.

   function Pixel_Fraction (X : Natural; Size : Int32) return Long_Float
   is (N.Clamp_Unit ((Long_Float (X) + 0.5) / Long_Float (Size)))
   with Pre  => Size in 1 .. Max_Output_Side and then X <= Max_Output_Side,
        Post => Pixel_Fraction'Result >= 0.0
                and then Pixel_Fraction'Result <= 1.0;
   --  (X + 0.5) / Size: where the centre of pixel X lies along an output
   --  axis of Size pixels, in [0, 1] for X < Size (the limit never acts).

   function Point_Fraction (P : Long_Float; Size : Int32) return Long_Float
   is (N.Clamp_Unit ((P + 0.5) / Long_Float (Size)))
   with Pre  => Size in 1 .. Max_Output_Side
                and then P >= -0.5 and then P <= Long_Float (Size) - 0.5,
        Post => Point_Fraction'Result >= 0.0
                and then Point_Fraction'Result <= 1.0;
   --  (P + 0.5) / Size for an output coordinate P within the output image,
   --  which lies in [0, 1] (the limit never acts).

   function Angle_At
     (Section : KS.Ks_Circular_Annulus_Section;
      FX      : Long_Float) return Long_Float
   is (Section.Angle_Start + N.Times_Unit (Section.Angle_Span, FX))
   with Pre  => Valid_Section (Section)
                and then FX >= 0.0 and then FX <= 1.0,
        Post => abs Angle_At'Result <= 2.0E150;
   --  The angle the fraction FX of the way along the span.

   function Radius_At
     (Section : KS.Ks_Circular_Annulus_Section;
      FY      : Long_Float) return Long_Float
   is (Section.Radius
       + N.Times_Unit (Outer (Section) - Section.Radius, FY))
   with Pre  => Valid_Section (Section)
                and then FY >= 0.0 and then FY <= 1.0,
        Post => abs Radius_At'Result <= 8.0E150;
   --  The radius the fraction FY of the way from the start arc to the end
   --  arc.

   function Region_X
     (Section : KS.Ks_Circular_Annulus_Section;
      FX, FY  : Long_Float) return Long_Float
   with Pre  => Valid_Section (Section)
                and then FX >= 0.0 and then FX <= 1.0
                and then FY >= 0.0 and then FY <= 1.0,
        Post => abs Region_X'Result <= Max_Region_Point;
   --  The x coordinate, in the region's space, of the point at the
   --  fractions FX (angle) and FY (radius) of the section.

   function Region_X
     (Section : KS.Ks_Circular_Annulus_Section;
      FX, FY  : Long_Float) return Long_Float is
   begin
      return Section.Center_X
        + N.Times_Unit (Radius_At (Section, FY),
                        EF.Cos (Angle_At (Section, FX)));
   end Region_X;

   function Region_Y
     (Section : KS.Ks_Circular_Annulus_Section;
      FX, FY  : Long_Float) return Long_Float
   with Pre  => Valid_Section (Section)
                and then FX >= 0.0 and then FX <= 1.0
                and then FY >= 0.0 and then FY <= 1.0,
        Post => abs Region_Y'Result <= Max_Region_Point;
   --  The y coordinate of that point.

   function Region_Y
     (Section : KS.Ks_Circular_Annulus_Section;
      FX, FY  : Long_Float) return Long_Float is
   begin
      return Section.Center_Y
        + N.Times_Unit (Radius_At (Section, FY),
                        EF.Sin (Angle_At (Section, FX)));
   end Region_Y;

   function Sample_X
     (Section           : KS.Ks_Circular_Annulus_Section;
      Pixel_From_Region : KT.Ks_Transform_2D_Linear;
      Width, Height     : Int32;
      X, Y              : Natural) return Long_Float
   with Pre  => Valid_Section (Section)
                and then KT.Bounded (Pixel_From_Region)
                and then Width in 1 .. Max_Output_Side
                and then Height in 1 .. Max_Output_Side
                and then X <= Max_Output_Side and then Y <= Max_Output_Side,
        Post => abs Sample_X'Result <= SM.Point_Limit;
   --  The x coordinate, in pixel space, of the sample point of output
   --  pixel (X, Y).

   function Sample_X
     (Section           : KS.Ks_Circular_Annulus_Section;
      Pixel_From_Region : KT.Ks_Transform_2D_Linear;
      Width, Height     : Int32;
      X, Y              : Natural) return Long_Float
   is
      FX : constant Long_Float := Pixel_Fraction (X, Width);
      FY : constant Long_Float := Pixel_Fraction (Y, Height);
   begin
      return SM.Map_X (Pixel_From_Region, Region_X (Section, FX, FY),
                       Region_Y (Section, FX, FY));
   end Sample_X;

   function Sample_Y
     (Section           : KS.Ks_Circular_Annulus_Section;
      Pixel_From_Region : KT.Ks_Transform_2D_Linear;
      Width, Height     : Int32;
      X, Y              : Natural) return Long_Float
   with Pre  => Valid_Section (Section)
                and then KT.Bounded (Pixel_From_Region)
                and then Width in 1 .. Max_Output_Side
                and then Height in 1 .. Max_Output_Side
                and then X <= Max_Output_Side and then Y <= Max_Output_Side,
        Post => abs Sample_Y'Result <= SM.Point_Limit;
   --  The y coordinate of that point.

   function Sample_Y
     (Section           : KS.Ks_Circular_Annulus_Section;
      Pixel_From_Region : KT.Ks_Transform_2D_Linear;
      Width, Height     : Int32;
      X, Y              : Natural) return Long_Float
   is
      FX : constant Long_Float := Pixel_Fraction (X, Width);
      FY : constant Long_Float := Pixel_Fraction (Y, Height);
   begin
      return SM.Map_Y (Pixel_From_Region, Region_X (Section, FX, FY),
                       Region_Y (Section, FX, FY));
   end Sample_Y;

   ---------------------------------------------------------------------
   --  Resampling
   ---------------------------------------------------------------------

   function Sample_Inside
     (Image             : access constant KI.Ks_Image_8_Grey_Data;
      Section           : KS.Ks_Circular_Annulus_Section;
      Pixel_From_Region : KT.Ks_Transform_2D_Linear;
      Width, Height     : Int32;
      X, Y              : Natural) return Boolean
   is
     (SM.Inside_Area
        (Image,
         Sample_X (Section, Pixel_From_Region, Width, Height, X, Y),
         Sample_Y (Section, Pixel_From_Region, Width, Height, X, Y)))
   with Pre => KI.Valid_Image (Image)
               and then Valid_Section (Section)
               and then KT.Bounded (Pixel_From_Region)
               and then Width in 1 .. Max_Output_Side
               and then Height in 1 .. Max_Output_Side
               and then X < Natural (Width) and then Y < Natural (Height);
   --  The sample point of output pixel (X, Y) lies in the input image.

   function Nearest_At
     (Image             : access constant KI.Ks_Image_8_Grey_Data;
      Section           : KS.Ks_Circular_Annulus_Section;
      Pixel_From_Region : KT.Ks_Transform_2D_Linear;
      Width, Height     : Int32;
      X, Y              : Natural) return KI.Grey_8
   is
     (SM.Nearest_Sample
        (Image,
         Sample_X (Section, Pixel_From_Region, Width, Height, X, Y),
         Sample_Y (Section, Pixel_From_Region, Width, Height, X, Y), 0))
   with Pre => KI.Valid_Image (Image)
               and then Valid_Section (Section)
               and then KT.Bounded (Pixel_From_Region)
               and then Width in 1 .. Max_Output_Side
               and then Height in 1 .. Max_Output_Side
               and then X < Natural (Width) and then Y < Natural (Height);
   --  The nearest-neighbour sample of output pixel (X, Y).

   procedure Resample
     (Image             : access constant KI.Ks_Image_8_Grey_Data;
      Section           : KS.Ks_Circular_Annulus_Section;
      Pixel_From_Region : KT.Ks_Transform_2D_Linear;
      Nearest           : Boolean;
      Output            : KI.Ks_Image_8_Grey;
      Clipped           : out Boolean)
   with
     Pre  => KI.Valid_Image (Image)
             and then Valid_Section (Section)
             and then KT.Bounded (Pixel_From_Region)
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
                               = Nearest_At (Image, Section,
                                             Pixel_From_Region,
                                             Output.Width, Output.Height,
                                             X, Y))))
             and then
               (if not Clipped
                then (for all Y in Output.Pixels'Range (1)
                      => (for all X in Output.Pixels'Range (2)
                          => Sample_Inside (Image, Section,
                                            Pixel_From_Region,
                                            Output.Width, Output.Height,
                                            X, Y))));
   --  Fills Output with the samples of Image; Clipped tells whether a
   --  sample point lay outside the image (those pixels get 0).

   procedure Resample
     (Image             : access constant KI.Ks_Image_8_Grey_Data;
      Section           : KS.Ks_Circular_Annulus_Section;
      Pixel_From_Region : KT.Ks_Transform_2D_Linear;
      Nearest           : Boolean;
      Output            : KI.Ks_Image_8_Grey;
      Clipped           : out Boolean)
   is
      Width  : constant Int32 := Output.Width;
      Height : constant Int32 := Output.Height;
   begin
      Clipped := False;
      for Y in Output.Pixels'Range (1) loop
         for X in Output.Pixels'Range (2) loop
            declare
               PX : constant Long_Float :=
                 Sample_X (Section, Pixel_From_Region, Width, Height, X, Y);
               PY : constant Long_Float :=
                 Sample_Y (Section, Pixel_From_Region, Width, Height, X, Y);
            begin
               if not SM.Inside_Area (Image, PX, PY) then
                  Clipped := True;
               end if;
               if Nearest then
                  Output.Pixels (Y, X) := SM.Nearest_Sample (Image, PX, PY, 0);
               else
                  Output.Pixels (Y, X) :=
                    SM.Bilinear_Sample (Image, PX, PY, 0);
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
                              = Nearest_At (Image, Section,
                                            Pixel_From_Region, Width,
                                            Height, I, J))));
            pragma Loop_Invariant
              (if Nearest
               then (for all I in 0 .. X
                     => Output.Pixels (Y, I)
                          = Nearest_At (Image, Section, Pixel_From_Region,
                                        Width, Height, I, Y)));
            pragma Loop_Invariant
              (if not Clipped
               then (for all J in 0 .. Y - 1
                     => (for all I in Output.Pixels'Range (2)
                         => Sample_Inside (Image, Section,
                                           Pixel_From_Region, Width,
                                           Height, I, J))));
            pragma Loop_Invariant
              (if not Clipped
               then (for all I in 0 .. X
                     => Sample_Inside (Image, Section, Pixel_From_Region,
                                       Width, Height, I, Y)));
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
                           = Nearest_At (Image, Section, Pixel_From_Region,
                                         Width, Height, I, J))));
         pragma Loop_Invariant
           (if not Clipped
            then (for all J in 0 .. Y
                  => (for all I in Output.Pixels'Range (2)
                      => Sample_Inside (Image, Section, Pixel_From_Region,
                                        Width, Height, I, J))));
      end loop;
   end Resample;

   procedure Lemma_Inside_Is_Input
     (Image             : access constant KI.Ks_Image_8_Grey_Data;
      Section           : KS.Ks_Circular_Annulus_Section;
      Pixel_From_Region : KT.Ks_Transform_2D_Linear;
      Width, Height     : Int32;
      X, Y              : Natural)
   with
     Ghost,
     Pre  => KI.Valid_Image (Image)
             and then Valid_Section (Section)
             and then KT.Bounded (Pixel_From_Region)
             and then Width in 1 .. Max_Output_Side
             and then Height in 1 .. Max_Output_Side
             and then X < Natural (Width) and then Y < Natural (Height)
             and then Sample_Inside (Image, Section, Pixel_From_Region, Width,
                                     Height, X, Y),
     Post => Is_Input_Pixel
               (Image, Nearest_At (Image, Section, Pixel_From_Region, Width,
                                   Height, X, Y));
   --  The nearest-neighbour sample of a point inside the image is an input
   --  pixel.

   procedure Lemma_Inside_Is_Input
     (Image             : access constant KI.Ks_Image_8_Grey_Data;
      Section           : KS.Ks_Circular_Annulus_Section;
      Pixel_From_Region : KT.Ks_Transform_2D_Linear;
      Width, Height     : Int32;
      X, Y              : Natural)
   is
      PX : constant Long_Float :=
        Sample_X (Section, Pixel_From_Region, Width, Height, X, Y);
      PY : constant Long_Float :=
        Sample_Y (Section, Pixel_From_Region, Width, Height, X, Y);
   begin
      pragma Assert (SM.Inside_Area (Image, PX, PY));
      pragma Assert
        (Nearest_At (Image, Section, Pixel_From_Region, Width, Height, X, Y)
           = Image.Pixels (SM.Nearest_Index (PY, Image.Height),
                           SM.Nearest_Index (PX, Image.Width)));
   end Lemma_Inside_Is_Input;

   procedure Lemma_Nearest_Output
     (Image             : access constant KI.Ks_Image_8_Grey_Data;
      Section           : KS.Ks_Circular_Annulus_Section;
      Pixel_From_Region : KT.Ks_Transform_2D_Linear;
      Output            : access constant KI.Ks_Image_8_Grey_Data)
   with
     Ghost,
     Pre  => KI.Valid_Image (Image)
             and then Valid_Section (Section)
             and then KT.Bounded (Pixel_From_Region)
             and then KI.Valid_Image (Output)
             and then Output.Width <= Max_Output_Side
             and then Output.Height <= Max_Output_Side
             and then (for all Y in Output.Pixels'Range (1)
                       => (for all X in Output.Pixels'Range (2)
                           => Output.Pixels (Y, X)
                                = Nearest_At (Image, Section,
                                              Pixel_From_Region,
                                              Output.Width, Output.Height,
                                              X, Y)))
             and then (for all Y in Output.Pixels'Range (1)
                       => (for all X in Output.Pixels'Range (2)
                           => Sample_Inside (Image, Section,
                                             Pixel_From_Region,
                                             Output.Width, Output.Height,
                                             X, Y))),
     Post => (for all Y in Output.Pixels'Range (1)
              => (for all X in Output.Pixels'Range (2)
                  => Is_Input_Pixel (Image, Output.Pixels (Y, X))));
   --  A nearest-neighbour output without clipping holds input pixels only.

   procedure Lemma_Nearest_Output
     (Image             : access constant KI.Ks_Image_8_Grey_Data;
      Section           : KS.Ks_Circular_Annulus_Section;
      Pixel_From_Region : KT.Ks_Transform_2D_Linear;
      Output            : access constant KI.Ks_Image_8_Grey_Data)
   is
      Width  : constant Int32 := Output.Width;
      Height : constant Int32 := Output.Height;
   begin
      for Y in Output.Pixels'Range (1) loop
         for X in Output.Pixels'Range (2) loop
            Lemma_Inside_Is_Input (Image, Section, Pixel_From_Region, Width,
                                   Height, X, Y);
            pragma Loop_Invariant
              (for all J in 0 .. Y - 1
               => (for all I in Output.Pixels'Range (2)
                   => Is_Input_Pixel (Image, Output.Pixels (J, I))));
            pragma Loop_Invariant
              (for all I in 0 .. X
               => Is_Input_Pixel (Image, Output.Pixels (Y, I)));
         end loop;
         pragma Loop_Invariant
           (for all J in 0 .. Y
            => (for all I in Output.Pixels'Range (2)
                => Is_Input_Pixel (Image, Output.Pixels (J, I))));
      end loop;
   end Lemma_Nearest_Output;

   ---------------------------------------------------------------------
   --  Checks
   ---------------------------------------------------------------------

   procedure Check_Section
     (Section : KS.Ks_Circular_Annulus_Section;
      Status  : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status) then Valid_Section (Section));

   procedure Check_Section
     (Section : KS.Ks_Circular_Annulus_Section;
      Status  : out Ks_Status) is
   begin
      if not KS.Bounded (Section.Center_X) then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "Region.CenterX must be finite and within 1.0E150");
      elsif not KS.Bounded (Section.Center_Y) then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "Region.CenterY must be finite and within 1.0E150");
      elsif not KS.Bounded (Section.Angle_Start) then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "Region.AngleStart must be finite and within 1.0E150");
      elsif not KS.Bounded (Section.Angle_Span) then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "Region.AngleSpan must be finite and within 1.0E150");
      elsif not (Section.Radius > 0.0
                 and then Section.Radius <= KS.Max_Length)
      then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "Region.Radius must be > 0 and at most 4.0E150");
      elsif not (Section.Radial_Scale > 0.0
                 and then Section.Radial_Scale <= KS.Max_Value
                 and then Section.Radial_Scale /= 1.0)
      then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "Region.RadialScale must be > 0, at most 1.0E150 and "
                      & "not 1");
      elsif not (Section.Radius * Section.Radial_Scale <= KS.Max_Length) then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "Region.Radius * Region.RadialScale must be at most "
                      & "4.0E150");
      elsif Section.Angle_Span = 0.0 then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "Region.AngleSpan must not be 0");
      else
         Set_Success (Status);
      end if;
   end Check_Section;

   procedure Check_Unwrap
     (Section           : KS.Ks_Circular_Annulus_Section;
      Pixel_From_Region : KT.Ks_Transform_2D_Linear;
      Params            : Ks_Polar_Unwrap;
      Width, Height     : out Int32;
      Status            : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then
               (if Succeeded (Status)
                then Valid_Section (Section)
                     and then KT.Bounded (Pixel_From_Region)
                     and then Valid_Params (Params)
                     and then Width
                                = Output_Width (Section, Pixel_From_Region,
                                                Params)
                     and then Height
                                = Output_Height (Section, Pixel_From_Region,
                                                 Params)
                     and then Width in 1 .. Max_Output_Side
                     and then Height in 1 .. Max_Output_Side);
   --  The checks of the region, the transform and the run parameters,
   --  and the output size.

   procedure Check_Unwrap
     (Section           : KS.Ks_Circular_Annulus_Section;
      Pixel_From_Region : KT.Ks_Transform_2D_Linear;
      Params            : Ks_Polar_Unwrap;
      Width, Height     : out Int32;
      Status            : out Ks_Status) is
   begin
      Width := 0;
      Height := 0;
      Check_Section (Section, Status);
      if not Succeeded (Status) then
         return;
      elsif not KT.Bounded (Pixel_From_Region) then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "the transform from Region's space to pixel space "
                      & "must be finite and within 1.0E150");
         return;
      elsif not (Params.Scaling_X >= Min_Scaling
                 and then Params.Scaling_X <= Max_Scaling)
      then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "RunParams.ScalingX must be in 0.001 .. 1000");
         return;
      elsif not (Params.Scaling_Y >= Min_Scaling
                 and then Params.Scaling_Y <= Max_Scaling)
      then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "RunParams.ScalingY must be in 0.001 .. 1000");
         return;
      elsif Params.Sampling_Mode
              not in Sampling_Mode_Bilinear_Interpolation
                   | Sampling_Mode_Nearest_Neighbor
      then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "RunParams.SamplingMode must be BilinearInterpolation "
                      & "(0) or NearestNeighbor (1)");
         return;
      end if;
      Width := Output_Width (Section, Pixel_From_Region, Params);
      Height := Output_Height (Section, Pixel_From_Region, Params);
      if Width < 1 then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "the output image would be less than 1 pixel wide "
                      & "(RunParams.ScalingX times the middle arc of Region "
                      & "in pixels)");
      elsif Width > Max_Output_Side then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "the output image would be more than 32767 pixels "
                      & "wide (RunParams.ScalingX times the middle arc of "
                      & "Region in pixels)");
      elsif Height < 1 then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "the output image would be less than 1 pixel high "
                      & "(RunParams.ScalingY times the radial extent of "
                      & "Region in pixels)");
      elsif Height > Max_Output_Side then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "the output image would be more than 32767 pixels "
                      & "high (RunParams.ScalingY times the radial extent of "
                      & "Region in pixels)");
      end if;
   end Check_Unwrap;

   ---------------------------------------------------------------------
   --  Entry points
   ---------------------------------------------------------------------

   procedure Check_Input_Image
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Status : out Ks_Status) is
   begin
      SM.Check_Image (Image, SM.Input_Image, Status);
   end Check_Input_Image;

   procedure Unwrap
     (Image             : access constant KI.Ks_Image_8_Grey_Data;
      Region            : KS.Ks_Circular_Annulus_Section;
      Pixel_From_Region : KT.Ks_Transform_2D_Linear;
      Nearest           : Boolean;
      Width, Height     : Int32;
      Output            : out KI.Ks_Image_8_Grey;
      Status            : out Ks_Status)
   with
     Pre  => KI.Valid_Image (Image)
             and then Valid_Section (Region)
             and then KT.Bounded (Pixel_From_Region)
             and then Width in 1 .. Max_Output_Side
             and then Height in 1 .. Max_Output_Side,
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then KI.Valid_Image (Output)
                     and then Output.Width = Width
                     and then Output.Height = Height
                     and then
                       (if Nearest
                        then (for all Y in Output.Pixels'Range (1)
                              => (for all X in Output.Pixels'Range (2)
                                  => Is_Input_Pixel (Image,
                                                     Output.Pixels (Y, X)))))
                else Output = null);
   --  The output image of Width x Height pixels for a checked region,
   --  transform and size; Bad_Parameter when a sample is clipped.

   procedure Unwrap
     (Image             : access constant KI.Ks_Image_8_Grey_Data;
      Region            : KS.Ks_Circular_Annulus_Section;
      Pixel_From_Region : KT.Ks_Transform_2D_Linear;
      Nearest           : Boolean;
      Width, Height     : Int32;
      Output            : out KI.Ks_Image_8_Grey;
      Status            : out Ks_Status)
   is
      Clipped : Boolean;
      Ignored : Ks_Status;
   begin
      KI.Create (Width, Height, 0, Output, Status);
      if not Succeeded (Status) then
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "PolarUnwrap: not enough memory for the output image");
         return;
      end if;
      Resample (Image, Region, Pixel_From_Region, Nearest, Output, Clipped);
      if Clipped then
         KI.Destroy (Output, Ignored);
         Set_Failure (Status, Failure_Bad_Parameter,
                      "Region lies partly outside InputImage");
         return;
      end if;
      if Nearest then
         Lemma_Nearest_Output (Image, Region, Pixel_From_Region, Output);
      end if;
      Set_Success (Status);
   end Unwrap;

   procedure Execute
     (Image             : access constant KI.Ks_Image_8_Grey_Data;
      Region            : KS.Ks_Circular_Annulus_Section;
      Pixel_From_Region : KT.Ks_Transform_2D_Linear;
      Params            : Ks_Polar_Unwrap;
      Output            : out KI.Ks_Image_8_Grey;
      Status            : out Ks_Status)
   is
      Width, Height : Int32;
   begin
      Output := null;
      SM.Check_Image (Image, SM.Input_Image, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Unwrap (Region, Pixel_From_Region, Params, Width, Height, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Unwrap (Image, Region, Pixel_From_Region,
              Params.Sampling_Mode = Sampling_Mode_Nearest_Neighbor, Width,
              Height, Output, Status);
   end Execute;

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
   is
      Width, Height : Int32;
   begin
      Input_Point_X := 0.0;
      Input_Point_Y := 0.0;
      Check_Unwrap (Region, Pixel_From_Region, Params, Width, Height, Status);
      if not Succeeded (Status) then
         return;
      elsif not KT.Bounded (Selected_From_Region) then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "the transform from Region's space to InputImage's "
                      & "selected space must be finite and within 1.0E150");
         return;
      elsif not (Output_Point_X >= -0.5
                 and then Output_Point_X <= Long_Float (Width) - 0.5)
      then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "OutputPointX must lie in the output image (-0.5 .. "
                      & "width - 0.5)");
         return;
      elsif not (Output_Point_Y >= -0.5
                 and then Output_Point_Y <= Long_Float (Height) - 0.5)
      then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "OutputPointY must lie in the output image (-0.5 .. "
                      & "height - 0.5)");
         return;
      end if;
      declare
         FX : constant Long_Float :=
           Point_Fraction (Output_Point_X, Width);
         FY : constant Long_Float :=
           Point_Fraction (Output_Point_Y, Height);
         RX : constant Long_Float := Region_X (Region, FX, FY);
         RY : constant Long_Float := Region_Y (Region, FX, FY);
         IX : constant Long_Float := SM.Map_X (Selected_From_Region, RX, RY);
         IY : constant Long_Float := SM.Map_Y (Selected_From_Region, RX, RY);
      begin
         if not (KT.Bounded (IX) and then KT.Bounded (IY)) then
            Set_Failure (Status, Failure_Bad_Parameter,
                         "the input point exceeds 1.0E150");
            return;
         end if;
         Input_Point_X := IX;
         Input_Point_Y := IY;
      end;
      Set_Success (Status);
   end Get_Input_Point_From_Output_Point;

   function Turned_Angle
     (Relative : Long_Float;
      Positive : Boolean) return Long_Float
   is (if Positive
       then (if Relative >= 0.0 then Relative else Relative + N.Two_Pi)
       else (if Relative <= 0.0 then -Relative else N.Two_Pi - Relative))
   with Pre  => Relative > -N.Pi and then Relative <= N.Pi,
        Post => Turned_Angle'Result >= 0.0
                and then Turned_Angle'Result <= 7.0;
   --  The angle Relative (in (-Pi, Pi]) as a turn from 0 in the positive
   --  (counter-clockwise in a y-down image) or negative sense, in
   --  [0, 2 Pi).

   function Turns
     (Relative   : Long_Float;
      Positive   : Boolean;
      Revolution : Int32) return Long_Float
   is (Turned_Angle (Relative, Positive)
       + N.Mul_Within (Long_Float (Revolution), N.Two_Pi, 2.0 ** 31, 7.0))
   with Pre  => Relative > -N.Pi and then Relative <= N.Pi,
        Post => abs Turns'Result <= 2.0 ** 35;
   --  The angle Relative as a turn from 0 (see Turned_Angle) plus
   --  Revolution whole turns.

   procedure Signed_Ratio
     (X, Y   : Long_Float;
      Result : out Long_Float;
      Fits   : out Boolean)
   with
     Pre  => abs X <= 1.0E152 and then Y /= 0.0 and then abs Y <= 1.0E152,
     Post => (if Fits then abs Result <= 1.0E140 else Result = 0.0);
   --  X / Y when its magnitude is at most 1.0E140.

   procedure Signed_Ratio
     (X, Y   : Long_Float;
      Result : out Long_Float;
      Fits   : out Boolean)
   is
      Q : Long_Float;
   begin
      N.Ratio_Within (abs X, abs Y, 1.0E140, Q, Fits);
      Result := (if (X < 0.0) /= (Y < 0.0) then -Q else Q);
   end Signed_Ratio;

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
   is
      Width, Height : Int32;
   begin
      Output_Point_X := 0.0;
      Output_Point_Y := 0.0;
      Check_Unwrap (Region, Pixel_From_Region, Params, Width, Height, Status);
      if not Succeeded (Status) then
         return;
      elsif not KT.Bounded (Region_From_Selected) then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "the transform from InputImage's selected space to "
                      & "Region's space must be finite and within 1.0E150");
         return;
      elsif not KT.Bounded (Input_Point_X) then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "InputPointX must be finite and within 1.0E150");
         return;
      elsif not KT.Bounded (Input_Point_Y) then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "InputPointY must be finite and within 1.0E150");
         return;
      end if;
      declare
         RX : constant Long_Float :=
           SM.Map_X (Region_From_Selected, Input_Point_X, Input_Point_Y);
         RY : constant Long_Float :=
           SM.Map_Y (Region_From_Selected, Input_Point_X, Input_Point_Y);
      begin
         if not (KT.Bounded (RX) and then KT.Bounded (RY)) then
            Set_Failure (Status, Failure_Bad_Parameter,
                         "the input point lies beyond 1.0E150 in Region's "
                         & "space");
            return;
         end if;
         declare
            DX       : constant Long_Float := RX - Region.Center_X;
            DY       : constant Long_Float := RY - Region.Center_Y;
         begin
            if DX = 0.0 and then DY = 0.0 then
               Set_Failure (Status, Failure_Bad_Parameter,
                            "the centre of Region has no output point");
               return;
            end if;
            declare
               Distance : constant Long_Float := N.Hypot (DX, DY);
               Relative : constant Long_Float :=
                 N.Reduce_Two_Pi (N.Direction (DY, DX) - Region.Angle_Start);
               Turned   : constant Long_Float :=
                 Turns (Relative, Region.Angle_Span > 0.0, Revolution);
               Along    : constant Long_Float :=
                 (if Region.Angle_Span > 0.0 then Turned else -Turned);
               --  The angle from the start, signed like the span.
               QX, QY   : Long_Float;
               Fits_X   : Boolean;
               Fits_Y   : Boolean;
            begin
               Signed_Ratio (Along, Region.Angle_Span, QX, Fits_X);
               if Outer (Region) = Region.Radius then
                  QY := 0.0;
                  Fits_Y := False;
               else
                  Signed_Ratio (Distance - Region.Radius,
                                Outer (Region) - Region.Radius, QY, Fits_Y);
               end if;
               if not (Fits_X and then Fits_Y) then
                  Set_Failure (Status, Failure_Bad_Parameter,
                               "the output point exceeds 1.0E150");
                  return;
               end if;
               Output_Point_X :=
                 N.Mul_Within (QX, Long_Float (Width), 1.0E140,
                               Long_Float (Max_Output_Side))
                 - 0.5;
               Output_Point_Y :=
                 N.Mul_Within (QY, Long_Float (Height), 1.0E140,
                               Long_Float (Max_Output_Side))
                 - 0.5;
            end;
         end;
      end;
      Set_Success (Status);
   end Get_Output_Point_From_Input_Point;

end AMV.Kernels.Polar_Unwrap;
