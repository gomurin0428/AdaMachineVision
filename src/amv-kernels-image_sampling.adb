pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

package body AMV.Kernels.Image_Sampling with SPARK_Mode is

   procedure Check_Image
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Role   : Image_Role;
      Status : out Ks_Status) is
   begin
      if Image = null then
         case Role is
            when Input_Image =>
               Set_Failure (Status, Failure_Image_No_Pixels,
                            "InputImage has no pixels");
            when Input_Image_A =>
               Set_Failure (Status, Failure_Image_No_Pixels,
                            "InputImageA has no pixels");
            when Input_Image_B =>
               Set_Failure (Status, Failure_Image_No_Pixels,
                            "InputImageB has no pixels");
         end case;
      elsif not Usable_Image (Image) then
         case Role is
            when Input_Image =>
               Set_Failure (Status, Failure_Bad_Parameter,
                            "InputImage is not a valid image handle");
            when Input_Image_A =>
               Set_Failure (Status, Failure_Bad_Parameter,
                            "InputImageA is not a valid image handle");
            when Input_Image_B =>
               Set_Failure (Status, Failure_Bad_Parameter,
                            "InputImageB is not a valid image handle");
         end case;
      else
         Set_Success (Status);
      end if;
   end Check_Image;

   function Map_X
     (T    : KT.Ks_Transform_2D_Linear;
      X, Y : Long_Float) return Long_Float is
   begin
      return N.Mul (T.A, X) + N.Mul (T.B, Y) + T.Translation_X;
   end Map_X;

   function Map_Y
     (T    : KT.Ks_Transform_2D_Linear;
      X, Y : Long_Float) return Long_Float is
   begin
      return N.Mul (T.C, X) + N.Mul (T.D, Y) + T.Translation_Y;
   end Map_Y;

   function Nearest_Index (P : Long_Float; Size : Int32) return Natural is
      F : constant Long_Float := Long_Float'Floor (P + 0.5);
      I : Int64;
   begin
      if F <= 0.0 then
         return 0;
      elsif F >= Long_Float (Size - 1) then
         return Natural (Size - 1);
      end if;
      --  F is a whole number in (0, Size - 1), so the conversion is exact;
      --  the limits below never act (docs/PROOF.md) and spare the prover
      --  the rounding of the conversion.
      I := Int64 (F);
      if I <= 0 then
         return 0;
      elsif I >= Int64 (Size - 1) then
         return Natural (Size - 1);
      else
         return Natural (I);
      end if;
   end Nearest_Index;

   procedure Locate
     (Value    : Long_Float;
      High     : Natural;
      I0, I1   : out Natural;
      Fraction : out Long_Float)
   with
     Pre  => High < Natural'Last,
     Post => I0 <= High and then I1 <= High
             and then Fraction >= 0.0 and then Fraction <= 1.0;
   --  Limits Value to [0, High] and splits it into the index of the pixel
   --  centre at or before it (I0), the next one (I1, never beyond High) and
   --  the fraction of the way from I0 to I1.

   procedure Locate
     (Value    : Long_Float;
      High     : Natural;
      I0, I1   : out Natural;
      Fraction : out Long_Float)
   is
      Top : constant Long_Float := Long_Float (High);
      C   : constant Long_Float :=
        (if not (Value > 0.0) then 0.0
         elsif not (Value < Top) then Top
         else Value);
      F   : constant Long_Float := Long_Float'Floor (C);
   begin
      I0 := Natural (F);
      if I0 > High then
         I0 := High;
      end if;
      --  C - I0 lies in [0, 1); the limit states it for the prover.
      Fraction := N.Clamp_Unit (C - Long_Float (I0));
      I1 := (if I0 < High then I0 + 1 else High);
   end Locate;

   subtype Grey_Real is Long_Float range 0.0 .. 255.0;

   function Read_Grey (X : Long_Float) return Grey_Real is
     (if X >= 0.0 then (if X <= 255.0 then X else 255.0) else 0.0);
   --  X limited to [0, 255]. An interpolation between grey levels lies in
   --  that range, so the limit never changes a value; it states the range
   --  for the prover (docs/PROOF.md).

   function Between (P0, P1 : Grey_Real; F : Long_Float) return Grey_Real
   is (Read_Grey (P0 + N.Times_Unit (P1 - P0, F)))
   with Pre => F >= 0.0 and then F <= 1.0;
   --  The value the fraction F of the way from P0 to P1.

   function Bilinear_Sample
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      PX, PY : Long_Float;
      Fill   : KI.Grey_8) return KI.Grey_8 is
   begin
      if not Inside_Area (Image, PX, PY) then
         return Fill;
      end if;
      declare
         X0, X1, Y0, Y1 : Natural;
         FX, FY         : Long_Float;
      begin
         Locate (PX, Natural (Image.Width - 1), X0, X1, FX);
         Locate (PY, Natural (Image.Height - 1), Y0, Y1, FY);
         declare
            Top    : constant Grey_Real :=
              Between (Long_Float (Image.Pixels (Y0, X0)),
                       Long_Float (Image.Pixels (Y0, X1)), FX);
            Bottom : constant Grey_Real :=
              Between (Long_Float (Image.Pixels (Y1, X0)),
                       Long_Float (Image.Pixels (Y1, X1)), FX);
         begin
            return To_Grey (Between (Top, Bottom, FY));
         end;
      end;
   end Bilinear_Sample;

end AMV.Kernels.Image_Sampling;
