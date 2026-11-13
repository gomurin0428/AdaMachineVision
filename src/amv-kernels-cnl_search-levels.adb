pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

package body AMV.Kernels.CNL_Search.Levels with SPARK_Mode is

   use type KI.Grey_8;

   ---------------------------------------------------------------------
   --  Values
   ---------------------------------------------------------------------

   function Pixel_Count (Width, Height : Side) return Count_Value is
   begin
      pragma Assert (Int64 (Width) * Int64 (Height)
                       <= Int64 (Width) * Max_Pattern_Side);
      return Int64 (Width) * Int64 (Height);
   end Pixel_Count;

   function Spread_Of
     (Count  : Count_Value;
      Sum    : Grey_Sum;
      Square : Square_Sum) return Spread_Value
   is
   begin
      pragma Assert (Count * Square <= Max_Pattern_Pixels * Square);
      pragma Assert (Sum * Sum <= Max_Grey_Sum * Sum);
      return Count * Square - Sum * Sum;
   end Spread_Of;

   ---------------------------------------------------------------------
   --  Stacked levels
   ---------------------------------------------------------------------

   procedure Plan_Levels
     (Width, Height : Positive;
      Wanted        : Positive;
      Min_Side      : Positive;
      Table         : out Geometry_Table;
      Levels        : out Positive;
      Rows          : out Positive)
   is
   begin
      Table := [others => (0, 0, 0)];
      Table (0) := (Row => 0, Width => Width, Height => Height);
      Levels := 1;
      Rows := Height;
      for L in 1 .. Wanted - 1 loop
         pragma Loop_Invariant (Levels = L);
         pragma Loop_Invariant
           (Rows = Table (L - 1).Row + Table (L - 1).Height
            and then Rows + Table (L - 1).Height <= 2 * Height
            and then Rows >= Height);
         pragma Loop_Invariant
           (Table (0) = (Row => 0, Width => Width, Height => Height));
         pragma Loop_Invariant
           (for all K in 0 .. L - 1 =>
              Table (K).Width in 1 .. Width
              and then Table (K).Height in 1 .. Height
              and then Stacked (Table (K), Rows, Width));
         pragma Loop_Invariant
           (for all K in 1 .. L - 1 =>
              Table (K).Width = Table (K - 1).Width / 2
              and then Table (K).Height = Table (K - 1).Height / 2
              and then Table (K).Width >= Min_Side
              and then Table (K).Height >= Min_Side);
         exit when Table (L - 1).Width / 2 < Min_Side
           or else Table (L - 1).Height / 2 < Min_Side;
         Table (L) := (Row    => Rows,
                       Width  => Table (L - 1).Width / 2,
                       Height => Table (L - 1).Height / 2);
         Rows := Rows + Table (L).Height;
         Levels := L + 1;
      end loop;
   end Plan_Levels;

   procedure Copy_Box
     (Source : Grey_8_Matrix;
      X0, Y0 : Natural;
      Target : in out Grey_8_Matrix;
      G      : Level_Geometry)
   is
   begin
      for Y in 0 .. G.Height - 1 loop
         for X in 0 .. G.Width - 1 loop
            Target (G.Row + Y, X) := Source (Y0 + Y, X0 + X);
         end loop;
      end loop;
   end Copy_Box;

   procedure Downsample
     (Pixels   : in out Grey_8_Matrix;
      From, To : Level_Geometry)
   is
   begin
      for Y in 0 .. To.Height - 1 loop
         for X in 0 .. To.Width - 1 loop
            declare
               R0 : constant Natural := From.Row + 2 * Y;
               C0 : constant Natural := 2 * X;
               Total : constant Natural :=
                 Natural (Pixels (R0, C0)) + Natural (Pixels (R0, C0 + 1))
                 + Natural (Pixels (R0 + 1, C0))
                 + Natural (Pixels (R0 + 1, C0 + 1)) + 2;
            begin
               Pixels (To.Row + Y, X) := KI.Grey_8 (Total / 4);
            end;
         end loop;
      end loop;
   end Downsample;

   procedure Statistics
     (Pixels : Grey_8_Matrix;
      G      : Level_Geometry;
      Sum    : out Grey_Sum;
      Square : out Square_Sum)
   is
      Row_Limit : constant := 65025 * Max_Pattern_Side;
      Total     : Int64 := 0;
      Squares   : Int64 := 0;
   begin
      for Y in 0 .. G.Height - 1 loop
         declare
            Row_Sum    : Int64 := 0;
            Row_Square : Int64 := 0;
         begin
            for X in 0 .. G.Width - 1 loop
               declare
                  P : constant Int64 := Int64 (Pixels (G.Row + Y, X));
               begin
                  Row_Sum := Row_Sum + P;
                  Row_Square := Row_Square + P * P;
               end;
               pragma Loop_Invariant
                 (Row_Sum in 0 .. 255 * Int64 (X + 1)
                  and then Row_Square in 0 .. 65025 * Int64 (X + 1));
            end loop;
            pragma Assert (Row_Sum <= 255 * Max_Pattern_Side
                           and then Row_Square <= Row_Limit);
            Total := Total + Row_Sum;
            Squares := Squares + Row_Square;
         end;
         pragma Loop_Invariant
           (Total in 0 .. 255 * Max_Pattern_Side * Int64 (Y + 1)
            and then Squares in 0 .. Row_Limit * Int64 (Y + 1));
      end loop;
      Sum := Total;
      Square := Squares;
   end Statistics;

   ---------------------------------------------------------------------
   --  Care flags
   ---------------------------------------------------------------------

   function Dont_Care
     (Mask : access constant KI.Ks_Image_8_Grey_Data;
      U, V : Int64) return Boolean
   is
     (U in 0 .. Int64 (Mask.Width) - 1
      and then V in 0 .. Int64 (Mask.Height) - 1
      and then Mask.Pixels (Natural (V), Natural (U)) = 0)
   with Pre => KI.Valid_Image (Mask);
   --  Mask pixel (U, V) exists and marks its train pixel "don't care".

   procedure Copy_Care
     (Mask             : access constant KI.Ks_Image_8_Grey_Data;
      Shift_X, Shift_Y : Int64;
      Target           : in out Grey_8_Matrix;
      G                : Level_Geometry)
   is
   begin
      for Y in 0 .. G.Height - 1 loop
         for X in 0 .. G.Width - 1 loop
            Target (G.Row + Y, X) :=
              (if Dont_Care (Mask, Int64 (X) + Shift_X, Int64 (Y) + Shift_Y)
               then 0 else 1);
         end loop;
      end loop;
   end Copy_Care;

   procedure Downsample_Care
     (Care     : in out Grey_8_Matrix;
      From, To : Level_Geometry)
   is
   begin
      for Y in 0 .. To.Height - 1 loop
         for X in 0 .. To.Width - 1 loop
            declare
               R0 : constant Natural := From.Row + 2 * Y;
               C0 : constant Natural := 2 * X;
            begin
               Care (To.Row + Y, X) :=
                 (if Care (R0, C0) /= 0 and then Care (R0, C0 + 1) /= 0
                    and then Care (R0 + 1, C0) /= 0
                    and then Care (R0 + 1, C0 + 1) /= 0
                  then 1 else 0);
            end;
         end loop;
      end loop;
   end Downsample_Care;

   procedure Masked_Statistics
     (Pixels : Grey_8_Matrix;
      Care   : Grey_8_Matrix;
      G      : Level_Geometry;
      Count  : out Cared_Count;
      Sum    : out Grey_Sum;
      Square : out Square_Sum)
   is
      Row_Limit : constant := 65025 * Max_Pattern_Side;
      Number    : Int64 := 0;
      Total     : Int64 := 0;
      Squares   : Int64 := 0;
   begin
      for Y in 0 .. G.Height - 1 loop
         declare
            Row_Count  : Int64 := 0;
            Row_Sum    : Int64 := 0;
            Row_Square : Int64 := 0;
         begin
            for X in 0 .. G.Width - 1 loop
               if Care (G.Row + Y, X) /= 0 then
                  declare
                     P : constant Int64 := Int64 (Pixels (G.Row + Y, X));
                  begin
                     Row_Count := Row_Count + 1;
                     Row_Sum := Row_Sum + P;
                     Row_Square := Row_Square + P * P;
                  end;
               end if;
               pragma Loop_Invariant
                 (Row_Count in 0 .. Int64 (X + 1)
                  and then Row_Sum in 0 .. 255 * Int64 (X + 1)
                  and then Row_Square in 0 .. 65025 * Int64 (X + 1));
            end loop;
            pragma Assert (Row_Count <= Max_Pattern_Side
                           and then Row_Sum <= 255 * Max_Pattern_Side
                           and then Row_Square <= Row_Limit);
            Number := Number + Row_Count;
            Total := Total + Row_Sum;
            Squares := Squares + Row_Square;
         end;
         pragma Loop_Invariant
           (Number in 0 .. Max_Pattern_Side * Int64 (Y + 1)
            and then Total in 0 .. 255 * Max_Pattern_Side * Int64 (Y + 1)
            and then Squares in 0 .. Row_Limit * Int64 (Y + 1));
      end loop;
      Count := Number;
      Sum := Total;
      Square := Squares;
   end Masked_Statistics;

   ---------------------------------------------------------------------
   --  Integral images
   ---------------------------------------------------------------------

   procedure Allocate_Sums
     (Rows, Columns : Positive;
      Sums          : out Sum_Matrix_Access)
     with SPARK_Mode => Off
   is
   begin
      Sums := new Sum_Matrix (0 .. Rows - 1, 0 .. Columns - 1);
   exception
      when Storage_Error =>
         Sums := null;
   end Allocate_Sums;

   function Add_Sum (Above : Box_Sum; Run : Int64) return Box_Sum is
     (if Above + Run <= Max_Box_Sum then Above + Run else Max_Box_Sum)
   with Pre => Run in 0 .. Max_Box_Sum;
   --  Above + Run limited to Max_Box_Sum, which it never exceeds: an entry
   --  of an integral image sums at most Max_Search_Pixels grey levels.

   function Add_Square (Above : Box_Square; Run : Int64) return Box_Square is
     (if Above + Run <= Max_Box_Square then Above + Run else Max_Box_Square)
   with Pre => Run in 0 .. Max_Box_Square;
   --  The same for the squares.

   procedure Build_Sums
     (Pixels : Grey_8_Matrix;
      G      : Level_Geometry;
      Base   : Natural;
      Sums   : in out Sum_Matrix)
   is
   begin
      for X in 0 .. G.Width loop
         Sums (Base, X) := (S => 0, S2 => 0);
      end loop;
      for Y in 0 .. G.Height - 1 loop
         declare
            Run_S  : Int64 := 0;
            Run_S2 : Int64 := 0;
         begin
            Sums (Base + Y + 1, 0) := (S => 0, S2 => 0);
            for X in 0 .. G.Width - 1 loop
               declare
                  P : constant Int64 := Int64 (Pixels (G.Row + Y, X));
               begin
                  Run_S := Run_S + P;
                  Run_S2 := Run_S2 + P * P;
               end;
               pragma Loop_Invariant
                 (Run_S in 0 .. 255 * Int64 (X + 1)
                  and then Run_S2 in 0 .. 65025 * Int64 (X + 1));
               declare
                  Above : constant Sum_Pair := Sums (Base + Y, X + 1);
               begin
                  Sums (Base + Y + 1, X + 1) :=
                    (S  => Add_Sum (Above.S, Run_S),
                     S2 => Add_Square (Above.S2, Run_S2));
               end;
            end loop;
         end;
      end loop;
   end Build_Sums;

   function Window_Total (A, B, C, D : Int64) return Int64 is
     (A - B - C + D)
   with
     Pre  => A in 0 .. Max_Box_Square and then B in 0 .. Max_Box_Square
             and then C in 0 .. Max_Box_Square
             and then D in 0 .. Max_Box_Square,
     Post => Window_Total'Result in -2 * Max_Box_Square .. 2 * Max_Box_Square;

   procedure Window_Sums
     (Sums      : Sum_Matrix;
      Base      : Natural;
      X, Y      : Natural;
      Width     : Side;
      Height    : Side;
      Sum       : out Grey_Sum;
      Square    : out Square_Sum)
   is
      Top    : constant Natural := Base + Y;
      Bottom : constant Natural := Top + Height;
      Right  : constant Natural := X + Width;
      S  : constant Int64 :=
        Window_Total (Sums (Bottom, Right).S, Sums (Top, Right).S,
                      Sums (Bottom, X).S, Sums (Top, X).S);
      S2 : constant Int64 :=
        Window_Total (Sums (Bottom, Right).S2, Sums (Top, Right).S2,
                      Sums (Bottom, X).S2, Sums (Top, X).S2);
   begin
      --  The limits never act: the window has at most 2**20 pixels.
      Sum := (if S < 0 then 0 elsif S > Max_Grey_Sum then Max_Grey_Sum
              else S);
      Square := (if S2 < 0 then 0
                 elsif S2 > Square_Sum'Last then Square_Sum'Last else S2);
   end Window_Sums;

   ---------------------------------------------------------------------
   --  The plan of a search
   ---------------------------------------------------------------------

   function Level_OK (Plan : Search_Plan; L : Natural) return Boolean is
     (Level_Facts (Plan, L));

   function Last_X (Plan : Valid_Search_Plan; L : Natural) return Natural
   is
   begin
      pragma Assert (Level_OK (Plan, L));
      return Plan.Image (L).Width - Plan.Pattern (L).Geometry.Width
        + Plan.Left + Plan.Right;
   end Last_X;

   function Last_Y (Plan : Valid_Search_Plan; L : Natural) return Natural
   is
   begin
      pragma Assert (Level_OK (Plan, L));
      return Plan.Image (L).Height - Plan.Pattern (L).Geometry.Height
        + Plan.Up + Plan.Down;
   end Last_Y;

end AMV.Kernels.CNL_Search.Levels;
