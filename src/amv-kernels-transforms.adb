pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Numerics.Long_Elementary_Functions;

with AMV.Kernels.Numerics;

package body AMV.Kernels.Transforms with SPARK_Mode is

   package EF renames Ada.Numerics.Long_Elementary_Functions;
   package N renames AMV.Kernels.Numerics;

   ---------------------------------------------------------------------
   --  Argument checks
   ---------------------------------------------------------------------

   function Value_OK (X : Long_Float) return Boolean is
     (N.In_Range (X, Max_Value));

   function Scaling_OK (X : Long_Float) return Boolean is
     (N.In_Range (X, Max_Scaling));

   function Transform_OK (T : Ks_Transform_2D_Linear) return Boolean is
     (Value_OK (T.A) and then Value_OK (T.B) and then Value_OK (T.C)
      and then Value_OK (T.D) and then Value_OK (T.Translation_X)
      and then Value_OK (T.Translation_Y));

   procedure Bad
     (Status : out Ks_Status; Message : String)
   with
     Pre  => Message'First = 1 and then Message'Length <= 150,
     Post => Valid (Status) and then Status.Failure = Failure_Bad_Parameter;

   procedure Bad
     (Status : out Ks_Status; Message : String) is
   begin
      Set_Failure (Status, Failure_Bad_Parameter, Message);
   end Bad;

   procedure Bad_Argument
     (Status : out Ks_Status; Name : String; Limit : String)
   with
     Pre  => Name'First = 1 and then Name'Length <= 40
             and then Limit'First = 1 and then Limit'Length <= 10,
     Post => Valid (Status) and then Status.Failure = Failure_Bad_Parameter;
   --  "<Name> must be finite and within +/-<Limit>".

   procedure Bad_Argument
     (Status : out Ks_Status; Name : String; Limit : String) is
   begin
      Bad (Status, Name & " must be finite and within +/-" & Limit);
   end Bad_Argument;

   Value_Limit   : constant String := "1.0E150";
   Scaling_Limit : constant String := "2.0E150";

   procedure Out_Of_Range (Status : out Ks_Status; What : String)
   with
     Pre  => What'First = 1 and then What'Length <= 60,
     Post => Valid (Status) and then Status.Failure = Failure_Bad_Parameter;
   --  "<What> would exceed the supported range".

   procedure Out_Of_Range (Status : out Ks_Status; What : String) is
   begin
      Bad (Status, What & " would exceed the supported range");
   end Out_Of_Range;

   ---------------------------------------------------------------------
   --  Internal operations (bounded arguments)
   ---------------------------------------------------------------------

   subtype Angle is Long_Float;

   procedure Decompose_Bounded
     (T      : Ks_Transform_2D_Linear;
      Result : out Ks_Decomposition)
   with
     Pre  => Bounded (T),
     Post => Result.Scaling_X in 0.0 .. Max_Scaling
             and then Result.Scaling_Y in 0.0 .. Max_Scaling
             and then Result.Rotation_X > -Pi
             and then Result.Rotation_X <= Pi
             and then Result.Rotation_Y > -Pi
             and then Result.Rotation_Y <= Pi
             and then Result.Skew > -Pi
             and then Result.Skew <= Pi;

   procedure Decompose_Bounded
     (T      : Ks_Transform_2D_Linear;
      Result : out Ks_Decomposition)
   is
      SX : constant Long_Float := N.Hypot (T.A, T.C);
      SY : constant Long_Float := N.Hypot (T.B, T.D);
      RX : Angle := 0.0;
      RY : Angle := 0.0;
   begin
      --  Hypot is zero only for a zero column; such a column has
      --  rotation 0.0.
      if T.A /= 0.0 or else T.C /= 0.0 then
         RX := N.Direction (T.C, T.A);
      end if;
      if T.B /= 0.0 or else T.D /= 0.0 then
         RY := N.Direction (-T.B, T.D);
      end if;
      Result := (Scaling_X  => SX,
                 Scaling_Y  => SY,
                 Rotation_X => RX,
                 Rotation_Y => RY,
                 Skew       => N.Reduce_Two_Pi (RY - RX));
   end Decompose_Bounded;

   procedure Recompose_Bounded
     (Scaling_X, Scaling_Y, Rotation_X, Rotation_Y : Long_Float;
      Translation_X, Translation_Y                 : Long_Float;
      Result                                       : out Ks_Transform_2D_Linear;
      Status                                       : out Ks_Status)
   with
     Pre  => Scaling_X in -Max_Scaling .. Max_Scaling
             and then Scaling_Y in -Max_Scaling .. Max_Scaling
             and then Rotation_X in -2.0 * Max_Value .. 2.0 * Max_Value
             and then Rotation_Y in -2.0 * Max_Value .. 2.0 * Max_Value
             and then Bounded (Translation_X)
             and then Bounded (Translation_Y),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status) then Bounded (Result));
   --  The transform of the given decomposition; Bad_Parameter when an
   --  entry would exceed Max_Value.

   procedure Recompose_Bounded
     (Scaling_X, Scaling_Y, Rotation_X, Rotation_Y : Long_Float;
      Translation_X, Translation_Y                 : Long_Float;
      Result                                       : out Ks_Transform_2D_Linear;
      Status                                       : out Ks_Status)
   is
      A : constant Long_Float := N.Times_Unit (Scaling_X, EF.Cos (Rotation_X));
      C : constant Long_Float := N.Times_Unit (Scaling_X, EF.Sin (Rotation_X));
      B : constant Long_Float :=
        -N.Times_Unit (Scaling_Y, EF.Sin (Rotation_Y));
      D : constant Long_Float := N.Times_Unit (Scaling_Y, EF.Cos (Rotation_Y));
   begin
      Result := (others => <>);
      if not (Bounded (A) and then Bounded (B) and then Bounded (C)
              and then Bounded (D))
      then
         Out_Of_Range (Status, "an entry of the transform");
         return;
      end if;
      Result := (A => A, B => B, C => C, D => D,
                 Translation_X => Translation_X,
                 Translation_Y => Translation_Y);
      Set_Success (Status);
   end Recompose_Bounded;

   function Max_Abs_Entry (T : Ks_Transform_2D_Linear) return Long_Float is
     (Long_Float'Max (Long_Float'Max (abs T.A, abs T.B),
                      Long_Float'Max (abs T.C, abs T.D)))
   with
     Pre  => Bounded (T),
     Post => Max_Abs_Entry'Result in 0.0 .. Max_Value;

   ---------------------------------------------------------------------
   --  Entry points
   ---------------------------------------------------------------------

   procedure Decompose
     (Transform : Ks_Transform_2D_Linear;
      Result    : out Ks_Decomposition;
      Status    : out Ks_Status) is
   begin
      Result := (others => <>);
      if not Transform_OK (Transform) then
         Bad_Argument (Status, "Transform", Value_Limit);
         return;
      end if;
      Decompose_Bounded (Transform, Result);
      Set_Success (Status);
   end Decompose;

   procedure Aspect
     (Transform : Ks_Transform_2D_Linear;
      Result    : out Long_Float;
      Status    : out Ks_Status)
   is
      D : Ks_Decomposition;
   begin
      Result := 0.0;
      if not Transform_OK (Transform) then
         Bad_Argument (Status, "Transform", Value_Limit);
         return;
      end if;
      Decompose_Bounded (Transform, D);
      if D.Scaling_X = 0.0 then
         Set_Success (Status);
      else
         declare
            Fits : Boolean;
         begin
            N.Ratio_Within (D.Scaling_Y, D.Scaling_X, Max_Value, Result, Fits);
            if Fits then
               Set_Success (Status);
            else
               Out_Of_Range (Status, "Aspect");
            end if;
         end;
      end if;
   end Aspect;

   procedure Recompose
     (Scaling_X, Scaling_Y, Rotation_X, Rotation_Y : Long_Float;
      Translation_X, Translation_Y                 : Long_Float;
      Result                                       : out Ks_Transform_2D_Linear;
      Status                                       : out Ks_Status) is
   begin
      Result := (others => <>);
      if not Scaling_OK (Scaling_X) then
         Bad_Argument (Status, "Scaling_X", Scaling_Limit);
      elsif not Scaling_OK (Scaling_Y) then
         Bad_Argument (Status, "Scaling_Y", Scaling_Limit);
      elsif not Value_OK (Rotation_X) then
         Bad_Argument (Status, "Rotation_X", Value_Limit);
      elsif not Value_OK (Rotation_Y) then
         Bad_Argument (Status, "Rotation_Y", Value_Limit);
      elsif not Value_OK (Translation_X) then
         Bad_Argument (Status, "Translation_X", Value_Limit);
      elsif not Value_OK (Translation_Y) then
         Bad_Argument (Status, "Translation_Y", Value_Limit);
      else
         Recompose_Bounded
           (Scaling_X, Scaling_Y, Rotation_X, Rotation_Y,
            Translation_X, Translation_Y, Result, Status);
      end if;
   end Recompose;

   procedure Recompose_Scaling_Aspect
     (Scaling, Aspect, Rotation, Skew : Long_Float;
      Translation_X, Translation_Y    : Long_Float;
      Result                          : out Ks_Transform_2D_Linear;
      Status                          : out Ks_Status) is
   begin
      Result := (others => <>);
      if not Scaling_OK (Scaling) then
         Bad_Argument (Status, "Scaling", Scaling_Limit);
      elsif not Value_OK (Aspect) then
         Bad_Argument (Status, "Aspect", Value_Limit);
      elsif not Value_OK (Rotation) then
         Bad_Argument (Status, "Rotation", Value_Limit);
      elsif not Value_OK (Skew) then
         Bad_Argument (Status, "Skew", Value_Limit);
      elsif not Value_OK (Translation_X) then
         Bad_Argument (Status, "Translation_X", Value_Limit);
      elsif not Value_OK (Translation_Y) then
         Bad_Argument (Status, "Translation_Y", Value_Limit);
      else
         declare
            Scaling_Y : constant Long_Float := N.Mul (Scaling, Aspect);
         begin
            if not Scaling_OK (Scaling_Y) then
               Out_Of_Range (Status, "Scaling * Aspect");
               return;
            end if;
            Recompose_Bounded
              (Scaling, Scaling_Y, Rotation, Rotation + Skew,
               Translation_X, Translation_Y, Result, Status);
         end;
      end if;
   end Recompose_Scaling_Aspect;

   procedure Set_Property
     (Transform : Ks_Transform_2D_Linear;
      Property  : Int32;
      Value     : Long_Float;
      Result    : out Ks_Transform_2D_Linear;
      Status    : out Ks_Status)
   is
      D  : Ks_Decomposition;
      SX : Long_Float;
      SY : Long_Float;
      RX : Long_Float;
      RY : Long_Float;
   begin
      Result := (others => <>);
      if not Transform_OK (Transform) then
         Bad_Argument (Status, "Transform", Value_Limit);
         return;
      elsif Property not in Property_Rotation .. Property_Rotation_Y then
         Bad (Status, "Property must be a ks_transform_2d_linear_property "
              & "code (0 .. 7)");
         return;
      elsif Property in Property_Scaling | Property_Scaling_X
                      | Property_Scaling_Y
      then
         if not Scaling_OK (Value) then
            Bad_Argument (Status, "Value", Scaling_Limit);
            return;
         end if;
      elsif not Value_OK (Value) then
         Bad_Argument (Status, "Value", Value_Limit);
         return;
      end if;

      Decompose_Bounded (Transform, D);
      SX := D.Scaling_X;
      SY := D.Scaling_Y;
      RX := D.Rotation_X;
      RY := D.Rotation_Y;
      case Property is
         when Property_Rotation =>
            --  Both axes turn together, keeping the skew.
            RX := Value;
            RY := Value + D.Skew;
         when Property_Skew =>
            RY := D.Rotation_X + Value;
         when Property_Scaling =>
            --  Both scalings change together, keeping the aspect (0.0
            --  when Scaling_X is zero, so that Scaling_Y becomes zero).
            if D.Scaling_X = 0.0 then
               SY := 0.0;
            else
               declare
                  Aspect : Long_Float;
                  Fits   : Boolean;
               begin
                  N.Ratio_Within
                    (D.Scaling_Y, D.Scaling_X, Max_Value, Aspect, Fits);
                  if not Fits then
                     Out_Of_Range (Status, "Aspect");
                     return;
                  end if;
                  SY := N.Mul (Value, Aspect);
               end;
            end if;
            SX := Value;
         when Property_Aspect =>
            SY := N.Mul (D.Scaling_X, Value);
         when Property_Scaling_X =>
            SX := Value;
         when Property_Scaling_Y =>
            SY := Value;
         when Property_Rotation_X =>
            RX := Value;
         when others =>
            RY := Value;
      end case;
      if not (Scaling_OK (SX) and then Scaling_OK (SY)) then
         Out_Of_Range (Status, "a scaling of the transform");
         return;
      end if;
      Recompose_Bounded
        (SX, SY, RX, RY, Transform.Translation_X, Transform.Translation_Y,
         Result, Status);
   end Set_Property;

   procedure Create_Similarity
     (Scaling, Rotation, Translation_X, Translation_Y : Long_Float;
      Result : out Ks_Transform_2D_Linear;
      Status : out Ks_Status) is
   begin
      Result := (others => <>);
      if not Value_OK (Scaling) then
         Bad_Argument (Status, "Scaling", Value_Limit);
      elsif not Value_OK (Rotation) then
         Bad_Argument (Status, "Rotation", Value_Limit);
      elsif not Value_OK (Translation_X) then
         Bad_Argument (Status, "Translation_X", Value_Limit);
      elsif not Value_OK (Translation_Y) then
         Bad_Argument (Status, "Translation_Y", Value_Limit);
      else
         declare
            Cos_R : constant Long_Float := EF.Cos (Rotation);
            Sin_R : constant Long_Float := EF.Sin (Rotation);
            AD    : constant Long_Float := N.Times_Unit (Scaling, Cos_R);
            CB    : constant Long_Float := N.Times_Unit (Scaling, Sin_R);
         begin
            Result := (A => AD, B => -CB, C => CB, D => AD,
                       Translation_X => Translation_X,
                       Translation_Y => Translation_Y);
            Set_Success (Status);
         end;
      end if;
   end Create_Similarity;

   procedure Map
     (T                  : Ks_Transform_2D_Linear;
      X, Y               : Long_Float;
      With_Translation   : Boolean;
      Mapped_X, Mapped_Y : out Long_Float;
      Status             : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Bounded (Mapped_X) and then Bounded (Mapped_Y));
   --  Map_Point (With_Translation) or Map_Vector.

   procedure Map
     (T                  : Ks_Transform_2D_Linear;
      X, Y               : Long_Float;
      With_Translation   : Boolean;
      Mapped_X, Mapped_Y : out Long_Float;
      Status             : out Ks_Status) is
   begin
      Mapped_X := 0.0;
      Mapped_Y := 0.0;
      if not Transform_OK (T) then
         Bad_Argument (Status, "Transform", Value_Limit);
      elsif not Value_OK (X) then
         Bad_Argument (Status, "X", Value_Limit);
      elsif not Value_OK (Y) then
         Bad_Argument (Status, "Y", Value_Limit);
      else
         declare
            MX : Long_Float := N.Mul (T.A, X) + N.Mul (T.B, Y);
            MY : Long_Float := N.Mul (T.C, X) + N.Mul (T.D, Y);
         begin
            if With_Translation then
               MX := MX + T.Translation_X;
               MY := MY + T.Translation_Y;
            end if;
            if Bounded (MX) and then Bounded (MY) then
               Mapped_X := MX;
               Mapped_Y := MY;
               Set_Success (Status);
            else
               Out_Of_Range (Status, "the mapped point");
            end if;
         end;
      end if;
   end Map;

   procedure Map_Point
     (Transform          : Ks_Transform_2D_Linear;
      X, Y               : Long_Float;
      Mapped_X, Mapped_Y : out Long_Float;
      Status             : out Ks_Status) is
   begin
      Map (Transform, X, Y, True, Mapped_X, Mapped_Y, Status);
   end Map_Point;

   procedure Map_Vector
     (Transform          : Ks_Transform_2D_Linear;
      X, Y               : Long_Float;
      Mapped_X, Mapped_Y : out Long_Float;
      Status             : out Ks_Status) is
   begin
      Map (Transform, X, Y, False, Mapped_X, Mapped_Y, Status);
   end Map_Vector;

   procedure Map_Angle
     (Transform : Ks_Transform_2D_Linear;
      Angle     : Long_Float;
      Result    : out Long_Float;
      Status    : out Ks_Status) is
   begin
      Result := 0.0;
      if not Transform_OK (Transform) then
         Bad_Argument (Status, "Transform", Value_Limit);
         return;
      elsif not Value_OK (Angle) then
         Bad_Argument (Status, "Angle", Value_Limit);
         return;
      end if;
      declare
         Largest : constant Long_Float := Max_Abs_Entry (Transform);
      begin
         if Largest = 0.0 then
            Set_Failure
              (Status, Failure_Transform_Singular,
               "Map_Angle: the transform's linear part is zero");
            return;
         end if;
         declare
            --  Dividing by the largest entry leaves the direction
            --  unchanged and keeps every value in [-2, 2], so nothing can
            --  overflow or underflow to a spurious zero.
            A     : constant Long_Float :=
              N.Unit_Ratio (Transform.A, Largest);
            B     : constant Long_Float :=
              N.Unit_Ratio (Transform.B, Largest);
            C     : constant Long_Float :=
              N.Unit_Ratio (Transform.C, Largest);
            D     : constant Long_Float :=
              N.Unit_Ratio (Transform.D, Largest);
            Cos_A : constant Long_Float := EF.Cos (Angle);
            Sin_A : constant Long_Float := EF.Sin (Angle);
            VX    : constant Long_Float :=
              N.Times_Unit (A, Cos_A) + N.Times_Unit (B, Sin_A);
            VY    : constant Long_Float :=
              N.Times_Unit (C, Cos_A) + N.Times_Unit (D, Sin_A);
         begin
            if abs VX <= Map_Angle_Zero_Tolerance
              and then abs VY <= Map_Angle_Zero_Tolerance
            then
               Set_Failure
                 (Status, Failure_Transform_Singular,
                  "Map_Angle: the direction maps to a zero vector");
               return;
            end if;
            Result := N.Direction (VY, VX);
            Set_Success (Status);
         end;
      end;
   end Map_Angle;

   procedure Quotient
     (Numerator, Denominator : Long_Float;
      Result                 : out Long_Float;
      Fits                   : out Boolean)
   with
     Pre  => Bounded (Numerator) and then Denominator /= 0.0
             and then abs Denominator <= 2.0 ** 1021,
     Post => (if Fits then Bounded (Result));
   --  Result := Numerator / Denominator when that is within Max_Value;
   --  Fits is False (and Result 0.0) otherwise. Nothing overflows.

   procedure Quotient
     (Numerator, Denominator : Long_Float;
      Result                 : out Long_Float;
      Fits                   : out Boolean) is
   begin
      Result := 0.0;
      Fits := False;
      --  With abs Denominator >= 1 the quotient is at most abs Numerator;
      --  below 1, Max_Value * abs Denominator cannot overflow, and the
      --  test keeps the quotient near Max_Value at most.
      if abs Denominator >= 1.0
        or else abs Numerator <= Max_Value * abs Denominator
      then
         declare
            Q : constant Long_Float := Numerator / Denominator;
         begin
            if Bounded (Q) then
               Result := Q;
               Fits := True;
            end if;
         end;
      end if;
   end Quotient;

   procedure Invert
     (Transform : Ks_Transform_2D_Linear;
      Result    : out Ks_Transform_2D_Linear;
      Status    : out Ks_Status) is
   begin
      Result := (others => <>);
      if not Transform_OK (Transform) then
         Bad_Argument (Status, "Transform", Value_Limit);
         return;
      end if;
      declare
         T   : Ks_Transform_2D_Linear renames Transform;
         --  At most 2 * Max_Value**2 = 2.0E300 in magnitude. A matrix
         --  whose inverse is within Max_Value has a determinant of at
         --  least 1 / (4 Max_Value**2) = 2.5E-301 in magnitude, so the
         --  products below keep full precision wherever the inverse is
         --  accepted.
         Det : constant Long_Float := N.Mul (T.A, T.D) - N.Mul (T.B, T.C);
         IA, IB, IC, ID : Long_Float;
         OK_A, OK_B, OK_C, OK_D : Boolean;
      begin
         if Det = 0.0 then
            Set_Failure
              (Status, Failure_Transform_Singular,
               "Invert: the determinant is zero");
            return;
         end if;
         Quotient (T.D, Det, IA, OK_A);
         Quotient (-T.B, Det, IB, OK_B);
         Quotient (-T.C, Det, IC, OK_C);
         Quotient (T.A, Det, ID, OK_D);
         if not (OK_A and then OK_B and then OK_C and then OK_D) then
            Set_Failure
              (Status, Failure_Transform_Singular,
               "Invert: the inverse exceeds the supported range (1.0E150)");
            return;
         end if;
         declare
            TX : constant Long_Float :=
              -(N.Mul (IA, T.Translation_X) + N.Mul (IB, T.Translation_Y));
            TY : constant Long_Float :=
              -(N.Mul (IC, T.Translation_X) + N.Mul (ID, T.Translation_Y));
         begin
            if not (Bounded (TX) and then Bounded (TY)) then
               Set_Failure
                 (Status, Failure_Transform_Singular,
                  "Invert: the translation of the inverse exceeds the "
                  & "supported range (1.0E150)");
               return;
            end if;
            Result := (A => IA, B => IB, C => IC, D => ID,
                       Translation_X => TX, Translation_Y => TY);
            Set_Success (Status);
         end;
      end;
   end Invert;

   procedure Compose
     (Transform, Other : Ks_Transform_2D_Linear;
      Result           : out Ks_Transform_2D_Linear;
      Status           : out Ks_Status) is
   begin
      Result := (others => <>);
      if not Transform_OK (Transform) then
         Bad_Argument (Status, "Transform", Value_Limit);
         return;
      elsif not Transform_OK (Other) then
         Bad_Argument (Status, "Other", Value_Limit);
         return;
      end if;
      declare
         T : Ks_Transform_2D_Linear renames Transform;
         O : Ks_Transform_2D_Linear renames Other;
         R : constant Ks_Transform_2D_Linear :=
           (A  => N.Mul (T.A, O.A) + N.Mul (T.B, O.C),
            B  => N.Mul (T.A, O.B) + N.Mul (T.B, O.D),
            C  => N.Mul (T.C, O.A) + N.Mul (T.D, O.C),
            D  => N.Mul (T.C, O.B) + N.Mul (T.D, O.D),
            Translation_X =>
              N.Mul (T.A, O.Translation_X) + N.Mul (T.B, O.Translation_Y)
              + T.Translation_X,
            Translation_Y =>
              N.Mul (T.C, O.Translation_X) + N.Mul (T.D, O.Translation_Y)
              + T.Translation_Y);
      begin
         if not Bounded (R) then
            Out_Of_Range (Status, "the composed transform");
            return;
         end if;
         Result := R;
         Set_Success (Status);
      end;
   end Compose;

   function Determinant_Of (T : Ks_Transform_2D_Linear) return Long_Float is
     (N.Mul (T.A, T.D) - N.Mul (T.B, T.C))
   with
     Pre  => Bounded (T),
     Post => abs Determinant_Of'Result <= 2.0 ** 1021;
   --  A * D - B * C, evaluated as written. The bound the prover sees
   --  (the sum of the bounds of Mul) is far above the true one,
   --  2 Max_Value**2.

   procedure Matrix_Determinant
     (Transform : Ks_Transform_2D_Linear;
      Result    : out Long_Float;
      Status    : out Ks_Status) is
   begin
      Result := 0.0;
      if not Transform_OK (Transform) then
         Bad_Argument (Status, "Transform", Value_Limit);
         return;
      end if;
      Result := Determinant_Of (Transform);
      Set_Success (Status);
   end Matrix_Determinant;

   procedure Map_Area
     (Transform : Ks_Transform_2D_Linear;
      Area      : Long_Float;
      Result    : out Long_Float;
      Status    : out Ks_Status) is
   begin
      Result := 0.0;
      if not Transform_OK (Transform) then
         Bad_Argument (Status, "Transform", Value_Limit);
         return;
      elsif not Value_OK (Area) then
         Bad_Argument (Status, "Area", Value_Limit);
         return;
      end if;
      declare
         Scale  : constant Long_Float := abs Determinant_Of (Transform);
         Mapped : Long_Float;
      begin
         --  With abs Area <= 1 the product is at most Scale (at most
         --  2 Max_Value**2), so it cannot overflow. With abs Area > 1 it
         --  can only be within Max_Value when Scale is, and then both
         --  factors are within Max_Value.
         if abs Area <= 1.0 then
            Mapped := N.Times_Unit (Scale, Area);
         elsif Scale <= Max_Value then
            Mapped := N.Mul (Scale, Area);
         else
            Out_Of_Range (Status, "the mapped area");
            return;
         end if;
         if not Bounded (Mapped) then
            Out_Of_Range (Status, "the mapped area");
            return;
         end if;
         Result := Mapped;
         Set_Success (Status);
      end;
   end Map_Area;

   procedure Check_Element_Arguments
     (Transform   : Ks_Transform_2D_Linear;
      Row, Column : Int32;
      OK          : out Boolean;
      Status      : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Row not in 0 .. 1 or else Column not in 0 .. 1
                       then not OK
                            and then Status.Failure = Failure_Bad_Parameter)
             and then (if OK then Bounded (Transform)
                                  and then Row in 0 .. 1
                                  and then Column in 0 .. 1
                                  and then Succeeded (Status)
                       else Status.Failure = Failure_Bad_Parameter);
   --  The checks shared by Get_Matrix_Element and Set_Matrix_Element, in
   --  their order: the transform, then Row, then Column.

   procedure Check_Element_Arguments
     (Transform   : Ks_Transform_2D_Linear;
      Row, Column : Int32;
      OK          : out Boolean;
      Status      : out Ks_Status) is
   begin
      OK := False;
      if not Transform_OK (Transform) then
         Bad_Argument (Status, "Transform", Value_Limit);
      elsif Row not in 0 .. 1 then
         Bad (Status, "Row must be 0 or 1");
      elsif Column not in 0 .. 1 then
         Bad (Status, "Column must be 0 or 1");
      else
         OK := True;
         Set_Success (Status);
      end if;
   end Check_Element_Arguments;

   procedure Get_Matrix_Element
     (Transform   : Ks_Transform_2D_Linear;
      Row, Column : Int32;
      Result      : out Long_Float;
      Status      : out Ks_Status)
   is
      OK : Boolean;
   begin
      Result := 0.0;
      Check_Element_Arguments (Transform, Row, Column, OK, Status);
      if OK then
         Result := Matrix_Element (Transform, Row, Column);
      end if;
   end Get_Matrix_Element;

   procedure Set_Matrix_Element
     (Transform   : Ks_Transform_2D_Linear;
      Row, Column : Int32;
      Value       : Long_Float;
      Result      : out Ks_Transform_2D_Linear;
      Status      : out Ks_Status)
   is
      OK : Boolean;
   begin
      Result := (others => <>);
      Check_Element_Arguments (Transform, Row, Column, OK, Status);
      if not OK then
         return;
      elsif not Value_OK (Value) then
         Bad_Argument (Status, "Value", Value_Limit);
         return;
      end if;
      Result := Transform;
      if Row = 0 then
         if Column = 0 then
            Result.A := Value;
         else
            Result.B := Value;
         end if;
      elsif Column = 0 then
         Result.C := Value;
      else
         Result.D := Value;
      end if;
   end Set_Matrix_Element;

   function To_Int (Flag : Boolean) return Int32 is
     (if Flag then True_Value else False_Value);

   procedure Check_Classify_Arguments
     (Transform : Ks_Transform_2D_Linear;
      Tolerance : Long_Float;
      OK        : out Boolean;
      Status    : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if OK then Bounded (Transform)
                                  and then Tolerance in 0.0 .. Max_Value);

   procedure Check_Classify_Arguments
     (Transform : Ks_Transform_2D_Linear;
      Tolerance : Long_Float;
      OK        : out Boolean;
      Status    : out Ks_Status) is
   begin
      OK := False;
      if not Transform_OK (Transform) then
         Bad_Argument (Status, "Transform", Value_Limit);
      elsif not Value_OK (Tolerance) or else Tolerance < 0.0 then
         Bad (Status, "Tolerance must be finite, >= 0 and within 1.0E150");
      else
         OK := True;
         Set_Success (Status);
      end if;
   end Check_Classify_Arguments;

   function Matrix_Near_Identity
     (T : Ks_Transform_2D_Linear; Tolerance : Long_Float) return Boolean
   is (abs (T.A - 1.0) <= Tolerance and then abs T.B <= Tolerance
       and then abs T.C <= Tolerance and then abs (T.D - 1.0) <= Tolerance)
   with Pre => Bounded (T);
   --  The 2x2 part is within Tolerance of the identity, element by
   --  element.

   procedure Identity
     (Transform : Ks_Transform_2D_Linear;
      Tolerance : Long_Float;
      Result    : out Int32;
      Status    : out Ks_Status)
   is
      OK : Boolean;
      T  : Ks_Transform_2D_Linear renames Transform;
   begin
      Result := False_Value;
      Check_Classify_Arguments (Transform, Tolerance, OK, Status);
      if OK then
         Result := To_Int
           (Matrix_Near_Identity (T, Tolerance)
            and then abs T.Translation_X <= Tolerance
            and then abs T.Translation_Y <= Tolerance);
      end if;
   end Identity;

   procedure Matrix_Identity
     (Transform : Ks_Transform_2D_Linear;
      Tolerance : Long_Float;
      Result    : out Int32;
      Status    : out Ks_Status)
   is
      OK : Boolean;
   begin
      Result := False_Value;
      Check_Classify_Arguments (Transform, Tolerance, OK, Status);
      if OK then
         Result := To_Int (Matrix_Near_Identity (Transform, Tolerance));
      end if;
   end Matrix_Identity;

   procedure Singular
     (Transform : Ks_Transform_2D_Linear;
      Tolerance : Long_Float;
      Result    : out Int32;
      Status    : out Ks_Status)
   is
      OK : Boolean;
   begin
      Result := False_Value;
      Check_Classify_Arguments (Transform, Tolerance, OK, Status);
      if OK then
         Result := To_Int (abs Determinant_Of (Transform) <= Tolerance);
      end if;
   end Singular;

   procedure Is_Similarity
     (Transform : Ks_Transform_2D_Linear;
      Tolerance : Long_Float;
      Result    : out Int32;
      Status    : out Ks_Status)
   is
      OK : Boolean;
      T  : Ks_Transform_2D_Linear renames Transform;
   begin
      Result := False_Value;
      Check_Classify_Arguments (Transform, Tolerance, OK, Status);
      if OK then
         declare
            Largest : constant Long_Float := Max_Abs_Entry (T);
         begin
            if Largest = 0.0 then
               return;  --  The determinant is zero.
            end if;
            declare
               --  The matrix divided by its largest entry: the test does
               --  not depend on the scale, and the determinant of tiny
               --  entries does not underflow to zero.
               A : constant Long_Float := N.Unit_Ratio (T.A, Largest);
               B : constant Long_Float := N.Unit_Ratio (T.B, Largest);
               C : constant Long_Float := N.Unit_Ratio (T.C, Largest);
               D : constant Long_Float := N.Unit_Ratio (T.D, Largest);
            begin
               Result := To_Int
                 (abs (A - D) <= Tolerance and then abs (B + C) <= Tolerance
                  and then N.Times_Unit (A, D) - N.Times_Unit (B, C) > 0.0);
            end;
         end;
      end if;
   end Is_Similarity;

   procedure Is_Axis_Aligned
     (Transform : Ks_Transform_2D_Linear;
      Tolerance : Long_Float;
      Result    : out Int32;
      Status    : out Ks_Status)
   is
      OK : Boolean;
      T  : Ks_Transform_2D_Linear renames Transform;
   begin
      Result := False_Value;
      Check_Classify_Arguments (Transform, Tolerance, OK, Status);
      if OK then
         declare
            Limit : constant Long_Float :=
              N.Mul (Tolerance, Max_Abs_Entry (T));
         begin
            Result := To_Int (abs T.B <= Limit and then abs T.C <= Limit);
         end;
      end if;
   end Is_Axis_Aligned;

end AMV.Kernels.Transforms;
