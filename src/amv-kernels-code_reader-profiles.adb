pragma Validity_Checks ("F");
with AMV.Kernels.Numerics;

package body AMV.Kernels.Code_Reader.Profiles with SPARK_Mode is

   package N renames AMV.Kernels.Numerics;

   -----------------
   -- Sample_Line --
   -----------------

   One  : constant := 2 ** 28;
   Half : constant := One / 2;
   --  A pixel and half a pixel, in the units of the positions along a
   --  line.

   Full : constant := 2 ** 16;
   Part : constant := One / Full;
   --  The weights of the interpolation have 16 bits.

   Fixed_Limit : constant := 2 ** 61;
   --  Coordinate_Limit in those units.

   subtype Fixed_Origin is Int64 range -Fixed_Limit .. Fixed_Limit;
   subtype Fixed_Step is Int64 range -One .. One;

   function To_Fixed (X : Long_Float) return Fixed_Origin is
     (Fixed_Origin
        (N.Clamp (X * Long_Float (One), Long_Float (Fixed_Limit))))
   with Pre => abs X <= Coordinate_Limit;
   --  X in units of 1 / One pixel, rounded (the limit never acts).

   function To_Step (D : Long_Float) return Fixed_Step is
     (Fixed_Step (N.Clamp (D * Long_Float (One), Long_Float (One))))
   with Pre => abs D <= 1.0;

   subtype Weight is Int64 range 0 .. Full;
   subtype Row is Int64 range 0 .. 255 * Full;
   --  A grey level times the weights of a row of two pixels.

   subtype Grey_64 is Int64 range 0 .. 255;

   --  The two functions below are not expression functions, so that the
   --  proof of the caller gets their bounds, which are linear in W, and
   --  not the products.

   function Weighted_Grey (Value : Grey_64; W : Weight) return Int64
   with Post => Weighted_Grey'Result >= 0
                and then Weighted_Grey'Result <= 255 * W;
   --  Value * W.

   function Weighted_Grey (Value : Grey_64; W : Weight) return Int64 is
   begin
      return Value * W;
   end Weighted_Grey;

   function Weighted (Value : Row; W : Weight) return Int64
   with Post => Weighted'Result >= 0
                and then Weighted'Result <= 255 * Full * W;
   --  Value * W.

   function Weighted (Value : Row; W : Weight) return Int64 is
   begin
      return Value * W;
   end Weighted;

   function Level_At
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      CX, CY : Int64) return Level
   with
     Pre => KI.Valid_Image (Image)
            and then CX in 0 .. (Int64 (Image.Width) - 1) * One
            and then CY in 0 .. (Int64 (Image.Height) - 1) * One;
   --  The level at (CX, CY), a point between the pixel centres:
   --  interpolated between the four nearest ones and rounded to the
   --  nearest grey level (halves up).

   function Level_At
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      CX, CY : Int64) return Level
   is
      X  : constant Natural := Natural (CX / One);
      Y  : constant Natural := Natural (CY / One);
      X1 : constant Natural :=
        (if X < Natural (Image.Width - 1) then X + 1 else X);
      Y1 : constant Natural :=
        (if Y < Natural (Image.Height - 1) then Y + 1 else Y);
      FX : constant Weight := (CX mod One) / Part;
      FY : constant Weight := (CY mod One) / Part;

      P00 : constant Grey_64 := Grey_64 (Image.Pixels (Y, X));
      P01 : constant Grey_64 := Grey_64 (Image.Pixels (Y, X1));
      P10 : constant Grey_64 := Grey_64 (Image.Pixels (Y1, X));
      P11 : constant Grey_64 := Grey_64 (Image.Pixels (Y1, X1));

      Top    : constant Row :=
        Weighted_Grey (P00, Full - FX) + Weighted_Grey (P01, FX);
      Bottom : constant Row :=
        Weighted_Grey (P10, Full - FX) + Weighted_Grey (P11, FX);

      subtype Sum is Int64 range 0 .. 255 * Full * Full;
      V : constant Sum := Weighted (Top, Full - FY) + Weighted (Bottom, FY);
   begin
      return Level ((V + Full * Full / 2) / (Full * Full));
   end Level_At;

   procedure Sample_Line
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      X0, Y0 : Long_Float;
      DX, DY : Long_Float;
      Count  : Natural;
      Levels : in out Level_Array)
   is
      --  The centres of the last column and of the last row.
      X_Top : constant Int64 := (Int64 (Image.Width) - 1) * One;
      Y_Top : constant Int64 := (Int64 (Image.Height) - 1) * One;

      SX : constant Fixed_Step := To_Step (DX);
      SY : constant Fixed_Step := To_Step (DY);
      PX : Int64 := To_Fixed (X0);
      PY : Int64 := To_Fixed (Y0);
      --  The point of sample I.
   begin
      for I in 0 .. Count - 1 loop
         pragma Loop_Invariant (abs PX <= Fixed_Limit + Int64 (I) * One);
         pragma Loop_Invariant (abs PY <= Fixed_Limit + Int64 (I) * One);
         if PX >= -Half and then PX <= X_Top + Half
           and then PY >= -Half and then PY <= Y_Top + Half
         then
            declare
               --  The point limited to the pixel centres.
               CX : constant Int64 := Int64'Min (Int64'Max (PX, 0), X_Top);
               CY : constant Int64 := Int64'Min (Int64'Max (PY, 0), Y_Top);
            begin
               if Region = null
                 or else KR.Contains
                           (Region,
                            Int32 ((CX + Half) / One),
                            Int32 ((CY + Half) / One))
               then
                  Levels (I) := Level_At (Image, CX, CY);
               else
                  Levels (I) := No_Sample;
               end if;
            end;
         else
            Levels (I) := No_Sample;
         end if;
         PX := PX + SX;
         PY := PY + SY;
      end loop;
   end Sample_Line;

   ----------------
   -- Find_Edges --
   ----------------

   Steps_Reach : constant := 2 * Envelope_Reach + 1;
   --  The extremes within Envelope_Reach of an extreme, and itself.

   Swing_Num : constant := 1;
   Swing_Den : constant := 4;
   --  See Find_Edges: the extremes that stay.

   procedure Find_Edges
     (Levels    : Level_Array;
      First     : Natural;
      Last      : Natural;
      Threshold : Positive;
      Extremes  : in out Extreme_Array;
      Edges     : in out L.Position_Array;
      Edge_Last : out Natural)
   is
      function Value (I : Natural) return Grey is
        (if Levels (I) >= 0 then Integer (Levels (I)) else 0)
      with Pre => I in Levels'Range;

      Total : constant Int64 := Int64 (Last - First) * 256;
      --  The end of the segment.

      type Mode_Kind is (Unknown, Rising, Falling);

      Mode   : Mode_Kind := Unknown;
      Hi     : Grey;
      Lo     : Grey;
      Hi_Pos : Natural := First;
      Lo_Pos : Natural := First;
      --  The highest and the lowest level since the last extreme (since
      --  the start of the segment while Mode is Unknown), and where.
      Prev   : Grey;
      --  The level of the last extreme: a maximum while Mode is Falling,
      --  a minimum while it is Rising.
      Found  : Natural := 0;
      --  Extremes (0 .. Found - 1) are set.
      Count  : Natural := 0;
      --  Edges (0 .. Count) are set.
      V      : Grey;

      type Step_Ring is array (0 .. Steps_Reach - 1) of Grey;

      Steps  : Step_Ring := [others => 0];
      --  Steps (J mod Steps_Reach) is the steepest step on the way from
      --  the extreme J - 1 to the extreme J, for the J within
      --  Envelope_Reach of the extreme looked at.
      Steep  : Grey;
      --  The steepest of them.
      Kept   : Natural := 0;
      --  Extremes (0 .. Kept - 1) are the extremes that stay.
      Cand   : Extreme;
      Is_Max : Boolean;
      --  The last extreme that may stay, and its kind.
      Raw    : Extreme;
      Swing  : Integer;

      --  Add and Emit have no contract: they are proved where they are
      --  called, with what is known of the segment there.

      procedure Add (Pos : Natural; Level : Grey);
      --  The next extreme. A limit that never acts: a segment has no
      --  more extremes than samples.

      procedure Add (Pos : Natural; Level : Grey) is
      begin
         if Found <= Extremes'Last then
            Extremes (Found) := (Pos => Pos, Value => Level);
            Found := Found + 1;
         end if;
      end Add;

      procedure Measure (K : Natural);
      --  Steps (K mod Steps_Reach) := the largest difference of two
      --  samples next to each other from the extreme K - 1 to the
      --  extreme K; 0 where there is no such extreme.

      procedure Measure (K : Natural) is
         Most : Grey := 0;
      begin
         --  The second and the third condition are limits that never
         --  act: the extremes are samples of the segment.
         if K in 1 .. Found - 1
           and then Extremes (K - 1).Pos in First .. Last
           and then Extremes (K).Pos in First .. Last
         then
            for I in Extremes (K - 1).Pos .. Extremes (K).Pos - 1 loop
               Most :=
                 Integer'Max (Most, abs (Value (I + 1) - Value (I)));
            end loop;
         end if;
         Steps (K mod Steps_Reach) := Most;
      end Measure;

      procedure Emit (P, Q : Natural; VP, VQ : Grey; Light, Dark : Grey);
      --  The edge between the extremes at P and Q (P before Q, both in
      --  First .. Last), of the levels VP and VQ, where the light and the
      --  dark level are Light and Dark.

      procedure Emit (P, Q : Natural; VP, VQ : Grey; Light, Dark : Grey) is
         Rise : constant Boolean := VQ > VP;
         Low  : constant Grey := Integer'Min (VP, VQ);
         High : constant Grey := Integer'Max (VP, VQ);
         Keep : constant Integer := (High - Low) / 2;
         --  A quarter of the way from one extreme to the other, in half
         --  levels.
         M2   : constant Integer :=
           Integer'Max (2 * Low + Keep,
                        Integer'Min (2 * High - Keep, Light + Dark));
         --  Twice the crossing level.
         Pos  : Int64 := Int64 (Q - First) * 256;
         A    : Integer;
         B    : Integer;
      begin
         for I in P .. Q - 1 loop
            A := 2 * Value (I);
            B := 2 * Value (I + 1);
            if (Rise and then B >= M2 and then B > A and then A <= M2)
              or else
               (not Rise and then B <= M2 and then B < A and then A >= M2)
            then
               Pos := Int64 (I - First) * 256
                      + Int64 (abs (M2 - A) * 256 / abs (B - A));
               exit;
            end if;
         end loop;

         --  Limits that never act: the positions never decrease and
         --  stay in the segment, and the array has room for every edge.
         if Count <= Edges'Last - 4 then
            if Count = 0 and then Rise then
               --  The segment starts dark: a light run of no width
               --  first.
               Count := 1;
               Edges (1) := 0;
            end if;
            Pos := Int64'Max (Pos, Int64 (Edges (Count)));
            Pos := Int64'Min (Pos, Total);
            Pos := Int64'Max (Pos, 0);
            Count := Count + 1;
            Edges (Count) := L.Position (Pos);
         end if;
      end Emit;

   begin
      Edges (0) := 0;
      Hi := Value (First);
      Lo := Hi;
      Prev := Hi;

      --  The extremes.
      for I in First + 1 .. Last loop
         pragma Loop_Invariant (Found <= Extremes'Last + 1);
         pragma Loop_Invariant
           (Hi_Pos in First .. Last and then Lo_Pos in First .. Last);
         V := Value (I);
         case Mode is
            when Unknown =>
               if V > Hi then
                  Hi := V;
                  Hi_Pos := I;
               end if;
               if V < Lo then
                  Lo := V;
                  Lo_Pos := I;
               end if;
               if Hi - Lo >= Threshold then
                  if Hi_Pos < Lo_Pos then
                     Add (Hi_Pos, Hi);
                     Prev := Hi;
                     Mode := Falling;
                  else
                     Add (Lo_Pos, Lo);
                     Prev := Lo;
                     Mode := Rising;
                  end if;
               end if;

            when Falling =>
               if V < Lo then
                  Lo := V;
                  Lo_Pos := I;
               elsif V - Lo >= Threshold then
                  --  The minimum is an extreme.
                  Add (Lo_Pos, Lo);
                  Prev := Lo;
                  Hi := V;
                  Hi_Pos := I;
                  Mode := Rising;
               end if;

            when Rising =>
               if V > Hi then
                  Hi := V;
                  Hi_Pos := I;
               elsif Hi - V >= Threshold then
                  --  The maximum is an extreme.
                  Add (Hi_Pos, Hi);
                  Prev := Hi;
                  Lo := V;
                  Lo_Pos := I;
                  Mode := Falling;
               end if;
         end case;
      end loop;

      --  The levels after the last extreme.
      if Mode = Falling and then Prev - Lo >= Threshold then
         Add (Lo_Pos, Lo);
      elsif Mode = Rising and then Hi - Prev >= Threshold then
         Add (Hi_Pos, Hi);
      end if;

      --  The extremes that stay: a maximum and the minimum after it
      --  differ by Swing_Num / Swing_Den of the steepest step nearby.
      --  The same search as above, among the extremes. They are written
      --  over the first ones, each after it was read.
      if Found >= 2 then
         Cand := Extremes (0);
         Is_Max := Extremes (0).Value > Extremes (1).Value;
         for K in 1 .. Natural'Min (Found - 1, Envelope_Reach) loop
            Measure (K);
         end loop;
         for K in 1 .. Found - 1 loop
            pragma Loop_Invariant (Kept <= K - 1);
            Raw := Extremes (K);
            if K <= Found - 1 - Envelope_Reach then
               Measure (K + Envelope_Reach);
            else
               Steps ((K mod Steps_Reach + Envelope_Reach)
                      mod Steps_Reach) := 0;
            end if;
            Steep := 0;
            for J in Steps'Range loop
               Steep := Integer'Max (Steep, Steps (J));
            end loop;
            Swing := Steep * Swing_Num / Swing_Den;

            if Is_Max then
               if Raw.Value >= Cand.Value then
                  Cand := Raw;
               elsif Cand.Value - Raw.Value >= Swing then
                  Extremes (Kept) := Cand;
                  Kept := Kept + 1;
                  Cand := Raw;
                  Is_Max := False;
               end if;
            else
               if Raw.Value <= Cand.Value then
                  Cand := Raw;
               elsif Raw.Value - Cand.Value >= Swing then
                  Extremes (Kept) := Cand;
                  Kept := Kept + 1;
                  Cand := Raw;
                  Is_Max := True;
               end if;
            end if;
         end loop;
         Extremes (Kept) := Cand;
         Found := Kept + 1;
      end if;

      --  The edges: one between every two extremes.
      if Found >= 2 then
         for K in 0 .. Found - 2 loop
            pragma Loop_Invariant (Count <= Edges'Last - 2);
            declare
               From  : constant Natural :=
                 (if K >= Envelope_Reach then K - Envelope_Reach else 0);
               To    : constant Natural :=
                 Natural'Min (Found - 1, K + 1 + Envelope_Reach);
               Light : Grey := Extremes (K).Value;
               Dark  : Grey := Extremes (K).Value;
            begin
               for J in From .. To loop
                  Light := Integer'Max (Light, Extremes (J).Value);
                  Dark := Integer'Min (Dark, Extremes (J).Value);
               end loop;
               --  Limits that never act: the extremes are samples of
               --  the segment.
               if Extremes (K).Pos in First .. Last
                 and then Extremes (K + 1).Pos in First .. Last
               then
                  Emit (Extremes (K).Pos, Extremes (K + 1).Pos,
                        Extremes (K).Value, Extremes (K + 1).Value,
                        Light, Dark);
               end if;
            end;
         end loop;
      end if;

      --  The end of the segment. Falls have odd indices and rises even
      --  ones: after a rise the last run is light, after a fall it is
      --  dark and a light run of no width follows.
      if Count mod 2 = 0 then
         Count := Count + 1;
         Edges (Count) := L.Position (Total);
      else
         Edges (Count + 1) := L.Position (Total);
         Edges (Count + 2) := L.Position (Total);
         Count := Count + 2;
      end if;
      Edge_Last := Count;
   end Find_Edges;

end AMV.Kernels.Code_Reader.Profiles;
