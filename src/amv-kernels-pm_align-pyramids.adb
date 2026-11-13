pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Numerics;

package body AMV.Kernels.PM_Align.Pyramids with SPARK_Mode is

   package N renames AMV.Kernels.Numerics;

   ---------------------------------------------------------------------
   --  Releasing
   ---------------------------------------------------------------------

   procedure Release_Level (L : in out Level_Data)
   with Post => L.GX = null and then L.GY = null
                and then L.DX = null and then L.DY = null;

   procedure Release_Level (L : in out Level_Data) is
      Unused_Status : Ks_Status;
   begin
      KM.Destroy (L.GX, Unused_Status);
      KM.Destroy (L.GY, Unused_Status);
      KI.Destroy (L.DX, Unused_Status);
      KI.Destroy (L.DY, Unused_Status);
   end Release_Level;

   procedure Release (Pyr : in out Pyramid) is
      Unused_Status : Ks_Status;
   begin
      KM.Destroy (Pyr.Work_A, Unused_Status);
      KM.Destroy (Pyr.Work_B, Unused_Status);
      for K in Level_Index loop
         Release_Level (Pyr.Levels (K));
         pragma Loop_Invariant
           (for all J in Level_Index'First .. K =>
              Pyr.Levels (J).GX = null and then Pyr.Levels (J).GY = null
              and then Pyr.Levels (J).DX = null
              and then Pyr.Levels (J).DY = null);
      end loop;
      Pyr.Count := 0;
   end Release;

   ---------------------------------------------------------------------
   --  Regions
   ---------------------------------------------------------------------

   function Level_Pixel_In_Region
     (Region : access constant KR.Ks_Pixel_Region_Data;
      Area   : Window;
      Level  : Level_Index;
      I, J   : Natural) return Boolean
   is
      Size : constant Int64 :=
        (case Level is
            when 0 => 1, when 1 => 2, when 2 => 4, when 3 => 8,
            when 4 => 16, when 5 => 32);
      Half : constant Int64 := Size / 2;
      X    : constant Int64 :=
        Int64 (I) * Size + Half + Int64 (Area.X_Min);
      Y    : constant Int64 :=
        Int64 (J) * Size + Half + Int64 (Area.Y_Min);
   begin
      return Region /= null
        and then X in 0 .. Int64 (Int32'Last)
        and then Y in 0 .. Int64 (Int32'Last)
        and then KR.Contains (Region, Int32 (X), Int32 (Y));
   end Level_Pixel_In_Region;

   ---------------------------------------------------------------------
   --  Sampling
   ---------------------------------------------------------------------

   function Clamp_Into (X : Long_Float; High : Natural) return Long_Float is
     (if X <= 0.0 then 0.0
      elsif X >= Long_Float (High) then Long_Float (High)
      else X)
   with Post => Clamp_Into'Result >= 0.0
                and then Clamp_Into'Result <= Long_Float (High);

   function Floor_Index (X : Long_Float; High : Natural) return Natural is
     (Natural'Min (Natural (Long_Float'Floor (X)), High))
   with Pre  => X >= 0.0 and then X <= Long_Float (High),
        Post => Floor_Index'Result <= High
                and then Long_Float (Floor_Index'Result) <= X;

   function Bilinear
     (Img  : access constant KM.Ks_Real_Image_Data;
      X, Y : P.Position) return Grad_Value
   is
      Last_X : constant Natural := Img.Pixels'Last (2);
      Last_Y : constant Natural := Img.Pixels'Last (1);
      XC     : constant Long_Float := Clamp_Into (X, Last_X);
      YC     : constant Long_Float := Clamp_Into (Y, Last_Y);
      X0     : constant Natural := Floor_Index (XC, Last_X);
      Y0     : constant Natural := Floor_Index (YC, Last_Y);
      X1     : constant Natural := Natural'Min (X0 + 1, Last_X);
      Y1     : constant Natural := Natural'Min (Y0 + 1, Last_Y);
      FX     : constant Long_Float := N.Clamp_Unit (XC - Long_Float (X0));
      FY     : constant Long_Float := N.Clamp_Unit (YC - Long_Float (Y0));
      V00    : constant Grad_Value := Read (Img, X0, Y0);
      V10    : constant Grad_Value := Read (Img, X1, Y0);
      V01    : constant Grad_Value := Read (Img, X0, Y1);
      V11    : constant Grad_Value := Read (Img, X1, Y1);
      Top    : constant Long_Float := V00 + N.Times_Unit (V10 - V00, FX);
      Bottom : constant Long_Float := V01 + N.Times_Unit (V11 - V01, FX);
   begin
      --  A convex combination of the four values: the limit never acts.
      return Clamp_Grad (Top + N.Times_Unit (Bottom - Top, FY));
   end Bilinear;

   function Projected
     (L      : Level_Data;
      X, Y   : Long_Float;
      UX, UY : P.Unit;
      T      : Long_Float) return Long_Float
   is
      SX : constant P.Position := X + N.Times_Unit (T, UX);
      SY : constant P.Position := Y + N.Times_Unit (T, UY);
   begin
      return N.Times_Unit (Bilinear (L.GX, SX, SY), UX)
        + N.Times_Unit (Bilinear (L.GY, SX, SY), UY);
   end Projected;

   function Parabola_Peak (H_Minus, H_0, H_Plus : Long_Float)
      return Long_Float
   is
      Den : constant Long_Float := H_Minus - 2.0 * H_0 + H_Plus;
      Num : constant Long_Float := H_Plus - H_Minus;
   begin
      --  The vertex lies at Num / (-2 Den) for Den < 0; at a true peak
      --  (H_0 at least both neighbours) abs Num <= -Den.
      if Den >= 0.0 then
         return 0.0;
      elsif abs Num <= -Den then
         return N.Unit_Ratio (Num, -Den) / 2.0;
      elsif Num > 0.0 then
         return 0.5;
      else
         return -0.5;
      end if;
   end Parabola_Peak;

   ---------------------------------------------------------------------
   --  Edges
   ---------------------------------------------------------------------

   function Magnitude_Squared
     (L    : Level_Data;
      I, J : Natural) return Long_Float
   is (N.Square_Within (Read (L.GX, I, J), Grad_Limit)
       + N.Square_Within (Read (L.GY, I, J), Grad_Limit));

   Tan_22_5 : constant := 0.414_213_562_373_095;
   --  tan (Pi / 8): the boundary between the sectors of the gradient
   --  direction.

   function Is_Edge
     (L                 : Level_Data;
      I, J              : Natural;
      Threshold_Squared : Long_Float) return Boolean
   is
      M  : constant Long_Float := Magnitude_Squared (L, I, J);
      GX : constant Grad_Value := Read (L.GX, I, J);
      GY : constant Grad_Value := Read (L.GY, I, J);
      AX : constant Long_Float := abs GX;
      AY : constant Long_Float := abs GY;
      DI : Integer;
      DJ : Integer;
   begin
      if M <= 0.0 or else M < Threshold_Squared then
         return False;
      end if;
      if AY <= N.Times_Unit (AX, Tan_22_5) then
         DI := 1;
         DJ := 0;
      elsif AX <= N.Times_Unit (AY, Tan_22_5) then
         DI := 0;
         DJ := 1;
      elsif (GX > 0.0) = (GY > 0.0) then
         DI := 1;
         DJ := 1;
      else
         DI := 1;
         DJ := -1;
      end if;
      return M >= Magnitude_Squared (L, I + DI, J + DJ)
        and then M > Magnitude_Squared (L, I - DI, J - DJ);
   end Is_Edge;

   ---------------------------------------------------------------------
   --  Directions
   ---------------------------------------------------------------------

   function Direction_Code (U : P.Unit) return KI.Grey_8 is
     (KI.Grey_8 (Neutral + P.Quantum (127.0 * U)));
   --  Neutral + 127 U rounded: 0 .. 254.

   procedure Fill_Directions
     (L         : in out Level_Data;
      Level     : Level_Index;
      Region    : access constant KR.Ks_Pixel_Region_Data;
      Area      : Window;
      Threshold : Long_Float;
      Status    : out Ks_Status)
   with
     Pre  => Threshold >= 0.0,
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory;
   --  Makes the direction images of L (see Level_Data).

   procedure Fill_Directions
     (L         : in out Level_Data;
      Level     : Level_Index;
      Region    : access constant KR.Ks_Pixel_Region_Data;
      Area      : Window;
      Threshold : Long_Float;
      Status    : out Ks_Status)
   is
      Unused_Status : Ks_Status;
   begin
      KI.Destroy (L.DX, Unused_Status);
      KI.Destroy (L.DY, Unused_Status);
      if not Usable (L) then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "PMAlign: inconsistent pyramid level");
         return;
      end if;
      KI.Create (L.GX.Width, L.GX.Height, Neutral, L.DX, Status);
      if not Succeeded (Status) then
         return;
      end if;
      KI.Create (L.GX.Width, L.GX.Height, Neutral, L.DY, Status);
      if not Succeeded (Status) then
         return;
      end if;
      for J in 0 .. Natural (L.GX.Height) - 1 loop
         pragma Loop_Invariant
           (Has_Directions (L) and then Succeeded (Status));
         for I in 0 .. Natural (L.GX.Width) - 1 loop
            pragma Loop_Invariant
              (Has_Directions (L) and then Succeeded (Status));
            declare
               GX : constant Grad_Value := Read (L.GX, I, J);
               GY : constant Grad_Value := Read (L.GY, I, J);
               M  : constant Long_Float := N.Hypot (GX, GY);
               UX, UY : P.Unit;
            begin
               if M > 0.0 and then M >= Threshold
                 and then Level_Pixel_In_Region (Region, Area, Level, I, J)
               then
                  P.Normalise (GX / 16.0, GY / 16.0, UX, UY);
                  L.DX.Pixels (J, I) := Direction_Code (UX);
                  L.DY.Pixels (J, I) := Direction_Code (UY);
               end if;
            end;
         end loop;
      end loop;
   end Fill_Directions;

   ---------------------------------------------------------------------
   --  Building
   ---------------------------------------------------------------------

   procedure Build
     (Image      : access constant KI.Ks_Image_8_Grey_Data;
      Region     : access constant KR.Ks_Pixel_Region_Data;
      Area       : Window;
      Count      : Positive;
      Directions : Boolean;
      Threshold  : Long_Float;
      Pyr        : in out Pyramid;
      Status     : out Ks_Status)
   is
      Unused_Status : Ks_Status;
   begin
      Release (Pyr);
      Pyr.Area := Area;
      --  Work_A holds the smoothed image of the level being built,
      --  Work_B the image it comes from; both belong to Pyr, which the
      --  caller releases also when the call fails.
      KM.From_Grey_8_Window (Image, Area.X_Min, Area.Y_Min, Area.Width,
                             Area.Height, Pyr.Work_B, Status);
      if not Succeeded (Status) then
         return;
      end if;
      KM.Gaussian_Smooth (Pyr.Work_B, Smoothing_Sigma, Pyr.Work_A, Status);
      KM.Destroy (Pyr.Work_B, Unused_Status);
      if not Succeeded (Status) then
         return;
      end if;
      for K in 0 .. Count - 1 loop
         pragma Loop_Invariant
           (Pyr.Work_B = null
            and then Pyr.Count = K
            and then Succeeded (Status)
            and then (for all J in K .. Level_Index'Last =>
                        Pyr.Levels (J).GX = null
                        and then Pyr.Levels (J).GY = null
                        and then Pyr.Levels (J).DX = null
                        and then Pyr.Levels (J).DY = null));
         KM.Sobel (Pyr.Work_A, Pyr.Levels (K).GX, Pyr.Levels (K).GY, Status);
         if not Succeeded (Status) then
            return;
         end if;
         Pyr.Count := K + 1;
         if Directions then
            Fill_Directions (Pyr.Levels (K), K, Region, Area, Threshold,
                             Status);
            if not Succeeded (Status) then
               return;
            end if;
         end if;
         if K < Count - 1 then
            KM.Gaussian_Smooth (Pyr.Work_A, Smoothing_Sigma, Pyr.Work_B,
                                Status);
            KM.Destroy (Pyr.Work_A, Unused_Status);
            if not Succeeded (Status) then
               return;
            end if;
            KM.Downsample_2 (Pyr.Work_B, Pyr.Work_A, Status);
            KM.Destroy (Pyr.Work_B, Unused_Status);
            if not Succeeded (Status) then
               return;
            end if;
         end if;
      end loop;
      KM.Destroy (Pyr.Work_A, Unused_Status);
   end Build;

end AMV.Kernels.PM_Align.Pyramids;
