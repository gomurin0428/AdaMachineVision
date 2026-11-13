pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Numerics.Long_Elementary_Functions;

with AMV.Kernels.Numerics;

package body AMV.Kernels.PM_Align.Poses with SPARK_Mode is

   package EF renames Ada.Numerics.Long_Elementary_Functions;
   package N renames AMV.Kernels.Numerics;

   ---------------------------------------------------------------------
   --  Matrices and rotations
   ---------------------------------------------------------------------

   function Rotation_Of (Theta : Long_Float) return Rotation is
      C : constant Unit := EF.Cos (Theta);
      S : constant Unit := EF.Sin (Theta);
   begin
      return (Cos_T => C, Sin_T => S);
   end Rotation_Of;

   function Linear_Of (T : KT.Ks_Transform_2D_Linear) return Linear is
     ((A => T.A, B => T.B, C => T.C, D => T.D));

   function Largest_Entry (M : Linear) return Long_Float is
     (Long_Float'Max (Long_Float'Max (abs M.A, abs M.B),
                      Long_Float'Max (abs M.C, abs M.D)))
   with Post => Largest_Entry'Result in 0.0 .. Max_Value
                and then abs M.A <= Largest_Entry'Result
                and then abs M.B <= Largest_Entry'Result
                and then abs M.C <= Largest_Entry'Result
                and then abs M.D <= Largest_Entry'Result;

   function Scaled (M : Linear; Big : Long_Float) return Unit_Linear is
     ((A => N.Unit_Ratio (M.A, Big), B => N.Unit_Ratio (M.B, Big),
       C => N.Unit_Ratio (M.C, Big), D => N.Unit_Ratio (M.D, Big)))
   with Pre => Big > 0.0
               and then abs M.A <= Big and then abs M.B <= Big
               and then abs M.C <= Big and then abs M.D <= Big;
   --  M / Big.

   function Determinant (U : Unit_Linear) return Long_Float is
     (N.Times_Unit (U.A, U.D) - N.Times_Unit (U.B, U.C))
   with Post => abs Determinant'Result <= 2.0;

   function Normal_Map (M : Linear) return Unit_Linear is
      Big : constant Long_Float := Largest_Entry (M);
   begin
      if Big <= 0.0 then
         return (others => 0.0);
      end if;
      declare
         U : constant Unit_Linear := Scaled (M, Big);
      begin
         if Determinant (U) < 0.0 then
            return (A => -U.D, B => U.C, C => U.B, D => -U.A);
         else
            return (A => U.D, B => -U.C, C => -U.B, D => U.A);
         end if;
      end;
   end Normal_Map;

   procedure Largest_Stretch
     (M      : Linear;
      Sigma  : out Long_Float;
      Lambda : out Long_Float)
   is
      Big : constant Long_Float := Largest_Entry (M);
   begin
      Lambda := Big;
      Sigma := 0.0;
      if Big <= 0.0 then
         return;
      end if;
      declare
         U    : constant Unit_Linear := Scaled (M, Big);
         F2   : constant Long_Float :=
           N.Times_Unit (U.A, U.A) + N.Times_Unit (U.B, U.B)
           + N.Times_Unit (U.C, U.C) + N.Times_Unit (U.D, U.D);
         Det  : constant Long_Float := Determinant (U);
         Disc : constant Long_Float :=
           N.Times_Small (F2, F2) - 4.0 * N.Times_Small (Det, Det);
         Root : Long_Float;
         Half : Long_Float;
      begin
         --  F2 <= 4 and abs Det <= 2; the singular values are the roots
         --  of (F2 +/- Sqrt (F2**2 - 4 Det**2)) / 2.
         if Disc > 0.0 then
            Root := Long_Float'Min (EF.Sqrt (Long_Float'Min (Disc, 16.0)),
                                    4.0);
         else
            Root := 0.0;
         end if;
         Half := (Long_Float'Max (F2, 0.0) + Root) / 2.0;
         if Half > 0.0 then
            Sigma := Long_Float'Min (EF.Sqrt (Long_Float'Min (Half, 4.0)),
                                     2.0);
         end if;
      end;
   end Largest_Stretch;

   ---------------------------------------------------------------------
   --  Levels
   ---------------------------------------------------------------------

   function Level_Factor (Level : Level_Index) return Long_Float is
     (case Level is
         when 0 => 1.0,
         when 1 => 0.5,
         when 2 => 0.25,
         when 3 => 0.125,
         when 4 => 0.0625,
         when 5 => 0.03125);

   function Level_Size (Level : Level_Index) return Long_Float is
     (case Level is
         when 0 => 1.0,
         when 1 => 2.0,
         when 2 => 4.0,
         when 3 => 8.0,
         when 4 => 16.0,
         when 5 => 32.0);

   function Half_Gap (Level : Level_Index) return Long_Float is
     ((Level_Size (Level) - 1.0) / 2.0)
   with Post => Half_Gap'Result >= 0.0 and then Half_Gap'Result <= 15.5;
   --  (2**Level - 1) / 2, the level-0 coordinate of the centre of pixel 0
   --  of Level.

   function To_Level (X0 : Position; Level : Level_Index) return Position is
     (N.Clamp (N.Times_Unit (X0 - Half_Gap (Level), Level_Factor (Level)),
               Max_Position));

   function From_Level (XL : Position; Level : Level_Index) return Position
   is (N.Clamp (N.Times_Small (XL, Level_Size (Level) / 8.0) * 8.0
                + Half_Gap (Level), Max_Position));

   ---------------------------------------------------------------------
   --  Mapped features
   ---------------------------------------------------------------------

   Max_Rotated : constant := 2.0 * Max_Relative;
   Max_Scaled  : constant := Max_Rotated * Max_Zone_Scale;

   procedure Map_Offset
     (F      : Frame;
      R      : Rotation;
      S      : Scale_Value;
      Level  : Level_Index;
      RX, RY : Relative;
      DX, DY : out Offset)
   is
      WX : constant Long_Float :=
        N.Times_Unit (RX, R.Cos_T) - N.Times_Unit (RY, R.Sin_T);
      WY : constant Long_Float :=
        N.Times_Unit (RX, R.Sin_T) + N.Times_Unit (RY, R.Cos_T);
      SX : constant Long_Float :=
        N.Mul_Within (WX, S, Max_Rotated, Max_Zone_Scale);
      SY : constant Long_Float :=
        N.Mul_Within (WY, S, Max_Rotated, Max_Zone_Scale);
      PX : constant Long_Float :=
        N.Mul_Within (F.L.A, SX, Max_Value, Max_Scaled)
        + N.Mul_Within (F.L.B, SY, Max_Value, Max_Scaled);
      PY : constant Long_Float :=
        N.Mul_Within (F.L.C, SX, Max_Value, Max_Scaled)
        + N.Mul_Within (F.L.D, SY, Max_Value, Max_Scaled);
      Factor : constant Long_Float := Level_Factor (Level);
   begin
      DX := N.Clamp (N.Times_Unit (PX, Factor), Max_Offset);
      DY := N.Clamp (N.Times_Unit (PY, Factor), Max_Offset);
   end Map_Offset;

   function Ratio_Of (X, H : Long_Float) return Unit is
     (if abs X <= H then N.Unit_Ratio (X, H)
      elsif X > 0.0 then 1.0
      else -1.0)
   with Pre => H > 0.0;
   --  X / H for abs X <= H (the components of a vector over its length);
   --  +/-1 should rounding make abs X exceed H.

   procedure Normalise
     (VX, VY : Long_Float;
      UX, UY : out Unit)
   is
      H : constant Long_Float := N.Hypot (VX, VY);
   begin
      if H < 1.0E-9 then
         UX := 0.0;
         UY := 0.0;
      else
         UX := Ratio_Of (VX, H);
         UY := Ratio_Of (VY, H);
      end if;
   end Normalise;

   procedure Map_Normal
     (F      : Frame;
      R      : Rotation;
      NX, NY : Unit;
      UX, UY : out Unit)
   is
      WX : constant Long_Float :=
        N.Times_Unit (NX, R.Cos_T) - N.Times_Unit (NY, R.Sin_T);
      WY : constant Long_Float :=
        N.Times_Unit (NX, R.Sin_T) + N.Times_Unit (NY, R.Cos_T);
      VX : constant Long_Float :=
        N.Times_Unit (WX, F.N.A) + N.Times_Unit (WY, F.N.B);
      VY : constant Long_Float :=
        N.Times_Unit (WX, F.N.C) + N.Times_Unit (WY, F.N.D);
   begin
      Normalise (VX, VY, UX, UY);
   end Map_Normal;

   function Pixel_Radius_Of
     (F     : Frame;
      S     : Scale_Value;
      Level : Level_Index) return Pixel_Radius
   is
      Scaled_Radius : constant Long_Float :=
        N.Mul_Within (F.Radius, S, Max_Radius, Max_Zone_Scale);
      Stretched     : constant Long_Float :=
        N.Mul_Within (Scaled_Radius, F.Sigma, Max_Radius * Max_Zone_Scale,
                      2.0);
      Pixels        : constant Long_Float :=
        N.Mul_Within (Stretched, F.Lambda, 2.0 * Max_Radius * Max_Zone_Scale,
                      Max_Value);
      At_Level      : constant Long_Float :=
        N.Times_Unit (Pixels, Level_Factor (Level));
   begin
      if At_Level <= 1.0 then
         return 1.0;
      elsif At_Level >= Max_Offset then
         return Max_Offset;
      else
         return At_Level;
      end if;
   end Pixel_Radius_Of;

   procedure Centroid
     (Model  : Model_Level;
      CX, CY : out Pattern_Coordinate)
   is
      subtype Sum is Long_Float range -2.0 ** 42 .. 2.0 ** 42;
      SX, SY : Sum := 0.0;
   begin
      CX := 0.0;
      CY := 0.0;
      if Model.Count = 0 then
         return;
      end if;
      --  At most Max_Features terms of at most Max_Pattern_Coordinate:
      --  below 2**42, so the limits never act.
      for I in 0 .. Model.Count - 1 loop
         SX := N.Clamp (SX + Model.Features (I).X, 2.0 ** 42);
         SY := N.Clamp (SY + Model.Features (I).Y, 2.0 ** 42);
      end loop;
      CX := N.Clamp (SX / Long_Float (Model.Count), Max_Pattern_Coordinate);
      CY := N.Clamp (SY / Long_Float (Model.Count), Max_Pattern_Coordinate);
   end Centroid;

   function Pattern_Radius
     (Model  : Model_Level;
      CX, CY : Pattern_Coordinate) return Pattern_Length
   is
      Result : Pattern_Length := 0.0;
   begin
      for I in 0 .. Model.Count - 1 loop
         declare
            D : constant Long_Float :=
              N.Hypot (Model.Features (I).X - CX, Model.Features (I).Y - CY);
         begin
            if D > Result then
               Result := D;
            end if;
         end;
      end loop;
      return Result;
   end Pattern_Radius;

   ---------------------------------------------------------------------
   --  The quantised model
   ---------------------------------------------------------------------

   function Quantum_Of (U : Unit) return Quantum is
     (Quantum (127.0 * U));

   procedure Quantise
     (Model : Model_Level;
      F     : Frame;
      Level : Level_Index;
      R     : Rotation;
      S     : Scale_Value;
      Q     : out Quantised_Model)
   is
      DX, DY : Offset;
      UX, UY : Unit;
   begin
      Q.Count := Model.Count;
      Q.Items := [others => (0, 0, 0, 0)];
      for I in 0 .. Model.Count - 1 loop
         Map_Offset (F, R, S, Level,
                     Model.Features (I).X - F.Centroid_X,
                     Model.Features (I).Y - F.Centroid_Y, DX, DY);
         Map_Normal (F, R, Model.Features (I).NX, Model.Features (I).NY,
                     UX, UY);
         Q.Items (I) := (OX => Grid_Offset (DX), OY => Grid_Offset (DY),
                         QX => Quantum_Of (UX), QY => Quantum_Of (UY));
         pragma Loop_Invariant (Q.Count = Model.Count);
      end loop;
   end Quantise;

   ---------------------------------------------------------------------
   --  Zones
   ---------------------------------------------------------------------

   function Clamp_To
     (X, Low, High : Long_Float) return Long_Float
   is (if X < Low then Low elsif X > High then High else X)
   with Pre  => Low <= High,
        Post => Clamp_To'Result >= Low and then Clamp_To'Result <= High;

   function Angle_In_Zone
     (Theta : Long_Float;
      Zone  : Ks_PM_Align_Zone_Angle) return Zone_Angle_Value is
   begin
      if Zone.Configuration /= Zone_Low_High then
         return Zone.Nominal;
      elsif Zone.High - Zone.Low >= Two_Pi then
         return Clamp_To
           (Zone.Low + Pi + N.Reduce_Two_Pi (Theta - Zone.Low - Pi),
            Zone.Low, Zone.High);
      else
         return Clamp_To (Theta, Zone.Low, Zone.High);
      end if;
   end Angle_In_Zone;

   function Scale_In_Zone
     (S    : Long_Float;
      Zone : Ks_PM_Align_Zone_Scale) return Scale_Value is
   begin
      if Zone.Configuration /= Zone_Low_High then
         return Zone.Nominal;
      else
         return Clamp_To (S, Zone.Low, Zone.High);
      end if;
   end Scale_In_Zone;

   function Angle_Distance (A, B : Zone_Angle_Value) return Long_Float is
     (abs N.Reduce_Two_Pi (A - B));

end AMV.Kernels.PM_Align.Poses;
