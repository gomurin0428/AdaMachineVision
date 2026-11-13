pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Numerics.Long_Elementary_Functions;

with AMV.Kernels.Numerics;

package body AMV.Kernels.CNL_Search.Correlation with SPARK_Mode is

   package N renames AMV.Kernels.Numerics;

   use type KI.Grey_8;

   ---------------------------------------------------------------------
   --  The score
   ---------------------------------------------------------------------

   function Cross_Sum
     (Image   : KL.Grey_8_Matrix;
      I_Geo   : Level_Geometry;
      X, Y    : Natural;
      Pattern : KL.Grey_8_Matrix;
      P_Geo   : Level_Geometry) return Cross_Value
   is
      Row_Limit : constant := 65025 * Max_Pattern_Side;
      Total     : Int64 := 0;
   begin
      for V in 0 .. P_Geo.Height - 1 loop
         declare
            Image_Row   : constant Natural := I_Geo.Row + Y + V;
            Pattern_Row : constant Natural := P_Geo.Row + V;
            Row_Sum     : Int32 := 0;
         begin
            for U in 0 .. P_Geo.Width - 1 loop
               Row_Sum := Row_Sum
                 + Int32 (Pattern (Pattern_Row, U))
                   * Int32 (Image (Image_Row, X + U));
               pragma Loop_Invariant (Row_Sum in 0 .. 65025 * Int32 (U + 1));
            end loop;
            pragma Assert (Row_Sum <= Row_Limit);
            Total := Total + Int64 (Row_Sum);
         end;
         pragma Loop_Invariant (Total in 0 .. Row_Limit * Int64 (V + 1));
      end loop;
      return Total;
   end Cross_Sum;

   function Window_Fits
     (Image : KL.Grey_8_Matrix;
      I_Geo : Level_Geometry;
      X, Y  : Natural;
      Care  : KL.Grey_8_Matrix;
      P_Geo : Level_Geometry) return Boolean
   is
     (KL.Indexed_From_Zero (Image)
      and then KL.Indexed_From_Zero (Care)
      and then KL.Stacked (I_Geo, KL.Rows_Of (Image), KL.Columns_Of (Image))
      and then KL.Stacked (P_Geo, KL.Rows_Of (Care), KL.Columns_Of (Care))
      and then P_Geo.Width <= Max_Pattern_Side
      and then P_Geo.Height <= Max_Pattern_Side
      and then P_Geo.Width <= I_Geo.Width
      and then X <= I_Geo.Width - P_Geo.Width
      and then P_Geo.Height <= I_Geo.Height
      and then Y <= I_Geo.Height - P_Geo.Height);
   --  The pattern level P_Geo (of the care flags) and the window at (X, Y)
   --  of the image level I_Geo lie in their stacks, as in Cross_Sum.

   procedure Masked_Sums
     (Image   : KL.Grey_8_Matrix;
      I_Geo   : Level_Geometry;
      X, Y    : Natural;
      Pattern : KL.Grey_8_Matrix;
      Care    : KL.Grey_8_Matrix;
      P_Geo   : Level_Geometry;
      Cross   : out Cross_Value;
      Sum     : out KL.Grey_Sum;
      Square  : out KL.Square_Sum)
   with
     Pre => Window_Fits (Image, I_Geo, X, Y, Care, P_Geo)
            and then KL.Same_Shape (Pattern, Care);
   --  Over the cared-for pixels of the pattern level P_Geo, and the pixels
   --  of the window at (X, Y) of the image level I_Geo at their positions:
   --  Sum (p w), Sum w and Sum w**2.

   procedure Masked_Sums
     (Image   : KL.Grey_8_Matrix;
      I_Geo   : Level_Geometry;
      X, Y    : Natural;
      Pattern : KL.Grey_8_Matrix;
      Care    : KL.Grey_8_Matrix;
      P_Geo   : Level_Geometry;
      Cross   : out Cross_Value;
      Sum     : out KL.Grey_Sum;
      Square  : out KL.Square_Sum)
   is
      Row_Limit    : constant := 65025 * Max_Pattern_Side;
      Total_Cross  : Int64 := 0;
      Total_Sum    : Int64 := 0;
      Total_Square : Int64 := 0;
   begin
      for V in 0 .. P_Geo.Height - 1 loop
         declare
            Image_Row   : constant Natural := I_Geo.Row + Y + V;
            Pattern_Row : constant Natural := P_Geo.Row + V;
            Row_Cross   : Int32 := 0;
            Row_Sum     : Int32 := 0;
            Row_Square  : Int32 := 0;
         begin
            for U in 0 .. P_Geo.Width - 1 loop
               if Care (Pattern_Row, U) /= 0 then
                  declare
                     W : constant Int32 := Int32 (Image (Image_Row, X + U));
                  begin
                     Row_Cross := Row_Cross
                       + Int32 (Pattern (Pattern_Row, U)) * W;
                     Row_Sum := Row_Sum + W;
                     Row_Square := Row_Square + W * W;
                  end;
               end if;
               pragma Loop_Invariant
                 (Row_Cross in 0 .. 65025 * Int32 (U + 1)
                  and then Row_Sum in 0 .. 255 * Int32 (U + 1)
                  and then Row_Square in 0 .. 65025 * Int32 (U + 1));
            end loop;
            pragma Assert (Row_Cross <= Row_Limit
                           and then Row_Sum <= 255 * Max_Pattern_Side
                           and then Row_Square <= Row_Limit);
            Total_Cross := Total_Cross + Int64 (Row_Cross);
            Total_Sum := Total_Sum + Int64 (Row_Sum);
            Total_Square := Total_Square + Int64 (Row_Square);
         end;
         pragma Loop_Invariant
           (Total_Cross in 0 .. Row_Limit * Int64 (V + 1)
            and then Total_Sum in 0 .. 255 * Max_Pattern_Side * Int64 (V + 1)
            and then Total_Square in 0 .. Row_Limit * Int64 (V + 1));
      end loop;
      Cross := Total_Cross;
      Sum := Total_Sum;
      Square := Total_Square;
   end Masked_Sums;

   procedure Masked_Window_Sums
     (Image  : KL.Grey_8_Matrix;
      I_Geo  : Level_Geometry;
      X, Y   : Natural;
      Care   : KL.Grey_8_Matrix;
      P_Geo  : Level_Geometry;
      Sum    : out KL.Grey_Sum;
      Square : out KL.Square_Sum)
   with
     Pre => Window_Fits (Image, I_Geo, X, Y, Care, P_Geo);
   --  Sum w and Sum w**2 over the pixels of the window at (X, Y) of the
   --  image level I_Geo under the cared-for pixels of the pattern level
   --  P_Geo (Masked_Sums without the cross sum).

   procedure Masked_Window_Sums
     (Image  : KL.Grey_8_Matrix;
      I_Geo  : Level_Geometry;
      X, Y   : Natural;
      Care   : KL.Grey_8_Matrix;
      P_Geo  : Level_Geometry;
      Sum    : out KL.Grey_Sum;
      Square : out KL.Square_Sum)
   is
      Row_Limit    : constant := 65025 * Max_Pattern_Side;
      Total_Sum    : Int64 := 0;
      Total_Square : Int64 := 0;
   begin
      for V in 0 .. P_Geo.Height - 1 loop
         declare
            Image_Row  : constant Natural := I_Geo.Row + Y + V;
            Care_Row   : constant Natural := P_Geo.Row + V;
            Row_Sum    : Int32 := 0;
            Row_Square : Int32 := 0;
         begin
            for U in 0 .. P_Geo.Width - 1 loop
               if Care (Care_Row, U) /= 0 then
                  declare
                     W : constant Int32 := Int32 (Image (Image_Row, X + U));
                  begin
                     Row_Sum := Row_Sum + W;
                     Row_Square := Row_Square + W * W;
                  end;
               end if;
               pragma Loop_Invariant
                 (Row_Sum in 0 .. 255 * Int32 (U + 1)
                  and then Row_Square in 0 .. 65025 * Int32 (U + 1));
            end loop;
            pragma Assert (Row_Sum <= 255 * Max_Pattern_Side
                           and then Row_Square <= Row_Limit);
            Total_Sum := Total_Sum + Int64 (Row_Sum);
            Total_Square := Total_Square + Int64 (Row_Square);
         end;
         pragma Loop_Invariant
           (Total_Sum in 0 .. 255 * Max_Pattern_Side * Int64 (V + 1)
            and then Total_Square in 0 .. Row_Limit * Int64 (V + 1));
      end loop;
      Sum := Total_Sum;
      Square := Total_Square;
   end Masked_Window_Sums;

   Max_Product : constant := 65025 * 2**40;
   --  Bounds Count * Cross, Sum * Sum and Count * Square (below 2**56).

   function Count_Times
     (Count : KL.Count_Value;
      Value : Int64) return Int64
   with
     Pre  => Value in 0 .. Max_Cross,
     Post => Count_Times'Result in 0 .. Max_Product
             and then Count_Times'Result = Count * Value;
   --  Count * Value (a cross sum or a sum of squares).

   function Count_Times
     (Count : KL.Count_Value;
      Value : Int64) return Int64
   is
   begin
      pragma Assert (Count * Value <= KL.Max_Pattern_Pixels * Value);
      return Count * Value;
   end Count_Times;

   function Sum_Times (A, B : KL.Grey_Sum) return Int64
   with Post => Sum_Times'Result in 0 .. Max_Product
                and then Sum_Times'Result = A * B;
   --  A * B for two sums of grey levels.

   function Sum_Times (A, B : KL.Grey_Sum) return Int64 is
   begin
      pragma Assert (A * B <= Max_Grey_Sum * B);
      return A * B;
   end Sum_Times;

   Limit_56 : constant := 2.0 ** 56;

   function Squared_Ratio (M, P, W : Long_Float) return Score_Value
   with Pre => M in 1.0 .. Limit_56 and then P in 1.0 .. Limit_56
               and then W in 1.0 .. Limit_56;
   --  M**2 / (P W) limited to [0, 1] (it lies there for the sums of a
   --  correlation, by the Cauchy-Schwarz inequality, up to rounding).

   function Squared_Ratio (M, P, W : Long_Float) return Score_Value is
      Square      : constant Long_Float := N.Square_Within (M, Limit_56);
      Denominator : constant Long_Float := N.Mul_Within (P, W, Limit_56,
                                                         Limit_56);
   begin
      if Denominator < 1.0 then
         --  Never: both factors are at least 1.
         return 0.0;
      elsif Square >= Denominator then
         return 1.0;
      else
         return N.Clamp_Unit (N.Unit_Ratio (Square, Denominator));
      end if;
   end Squared_Ratio;

   function Score_Of
     (Count           : KL.Count_Value;
      Cross           : Cross_Value;
      Pattern_Sum     : KL.Grey_Sum;
      Pattern_Spread  : KL.Positive_Spread;
      Window_Sum      : KL.Grey_Sum;
      Window_Square   : KL.Square_Sum;
      Ignore_Polarity : Boolean) return Score_Value
   is
      Numerator : constant Int64 :=
        Count_Times (Count, Cross) - Sum_Times (Pattern_Sum, Window_Sum);
      Spread    : constant KL.Spread_Value :=
        KL.Spread_Of (Count, Window_Sum, Window_Square);
      Magnitude : Int64;
   begin
      if Spread <= 0 then
         return 0.0;
      elsif Numerator > 0 then
         Magnitude := Numerator;
      elsif Ignore_Polarity and then Numerator < 0 then
         Magnitude := -Numerator;
      else
         return 0.0;
      end if;
      return Squared_Ratio (Long_Float (Magnitude), Long_Float (Pattern_Spread),
                            Long_Float (Spread));
   end Score_Of;

   function Inner_Score
     (Plan            : KL.Valid_Search_Plan;
      Image           : KL.Grey_8_Matrix;
      Sums            : KL.Sum_Matrix;
      Pattern         : KL.Grey_8_Matrix;
      Care            : KL.Grey_8_Matrix;
      L               : Natural;
      Ignore_Polarity : Boolean;
      X, Y            : Natural) return Score_Value
   with
     Pre => KL.Matches (Plan, Image, Sums, Pattern, Care)
            and then L < Plan.Levels
            and then KL.Level_OK (Plan, L)
            and then X <= Plan.Image (L).Width - Plan.Pattern (L).Geometry.Width
            and then Y <= Plan.Image (L).Height
                          - Plan.Pattern (L).Geometry.Height;
   --  The score of the window whose first pixel lies at (X, Y) of level L,
   --  inside the level.

   function Inner_Score
     (Plan            : KL.Valid_Search_Plan;
      Image           : KL.Grey_8_Matrix;
      Sums            : KL.Sum_Matrix;
      Pattern         : KL.Grey_8_Matrix;
      Care            : KL.Grey_8_Matrix;
      L               : Natural;
      Ignore_Polarity : Boolean;
      X, Y            : Natural) return Score_Value
   is
      P      : constant KL.Pattern_Level := Plan.Pattern (L);
      G      : constant Level_Geometry := Plan.Image (L);
      Cross  : Cross_Value;
      Sum    : KL.Grey_Sum;
      Square : KL.Square_Sum;
   begin
      pragma Assert (KL.Stacked (G, KL.Rows_Of (Image), KL.Columns_Of (Image))
                     and then KL.Stacked (P.Geometry, KL.Rows_Of (Pattern),
                                          KL.Columns_Of (Pattern)));
      if Plan.Masked then
         Masked_Sums (Image, G, X, Y, Pattern, Care, P.Geometry, Cross, Sum,
                      Square);
      else
         Cross := Cross_Sum (Image, G, X, Y, Pattern, P.Geometry);
         KL.Window_Sums (Sums, Plan.Base (L), X, Y, P.Geometry.Width,
                         P.Geometry.Height, Sum, Square);
      end if;
      return Score_Of (P.Count, Cross, P.Sum, P.Spread, Sum, Square,
                       Ignore_Polarity);
   end Inner_Score;

   ---------------------------------------------------------------------
   --  Partial windows
   ---------------------------------------------------------------------

   type Span is record
      Pattern_First : Natural := 0;
      Image_First   : Natural := 0;
      Length        : Natural := 0;
   end record;
   --  The part of a partial window that lies inside its level, along one
   --  axis: the pattern's columns (rows) Pattern_First .. Pattern_First +
   --  Length - 1 lie over the level's columns (rows) Image_First ..
   --  Image_First + Length - 1.

   function Clip_Along
     (P      : Natural;
      Before : KL.Margin;
      Size   : KL.Side;
      Extent : Positive) return Span
   with
     Pre  => Size <= Extent and then Extent <= Max_Search_Pixels
             and then 2 * Before <= Size
             and then P < Extent + Before,
     Post => Clip_Along'Result.Length in 1 .. Size
             and then Clip_Along'Result.Pattern_First
                        <= Size - Clip_Along'Result.Length
             and then Clip_Along'Result.Image_First
                        <= Extent - Clip_Along'Result.Length;
   --  The part inside a level of Extent pixels of the window of Size
   --  pixels at position P, whose first pixel lies at P - Before (Before:
   --  the limit before the level), before the level's end.

   function Clip_Along
     (P      : Natural;
      Before : KL.Margin;
      Size   : KL.Side;
      Extent : Positive) return Span
   is
   begin
      if P < Before then
         return (Pattern_First => Before - P,
                 Image_First   => 0,
                 Length        => Size - (Before - P));
      elsif P - Before <= Extent - Size then
         return (Pattern_First => 0,
                 Image_First   => P - Before,
                 Length        => Size);
      else
         return (Pattern_First => 0,
                 Image_First   => P - Before,
                 Length        => Extent - (P - Before));
      end if;
   end Clip_Along;

   function Clip_Fits
     (Matrix     : KL.Grey_8_Matrix;
      G          : Level_Geometry;
      Cols, Rows : Span) return Boolean
   is
     (KL.Indexed_From_Zero (Matrix)
      and then KL.Stacked (G, KL.Rows_Of (Matrix), KL.Columns_Of (Matrix))
      and then G.Width <= Max_Pattern_Side
      and then G.Height <= Max_Pattern_Side
      and then Cols.Length in 1 .. G.Width
      and then Cols.Pattern_First <= G.Width - Cols.Length
      and then Rows.Length in 1 .. G.Height
      and then Rows.Pattern_First <= G.Height - Rows.Length);
   --  The pattern level G of Matrix (the pattern or its care flags) holds
   --  the clipped part Cols x Rows.

   function Image_Fits
     (Image      : KL.Grey_8_Matrix;
      I_Geo      : Level_Geometry;
      Cols, Rows : Span) return Boolean
   is
     (KL.Indexed_From_Zero (Image)
      and then KL.Stacked (I_Geo, KL.Rows_Of (Image), KL.Columns_Of (Image))
      and then Cols.Length <= I_Geo.Width
      and then Cols.Image_First <= I_Geo.Width - Cols.Length
      and then Rows.Length <= I_Geo.Height
      and then Rows.Image_First <= I_Geo.Height - Rows.Length);
   --  The image level I_Geo holds the clipped part Cols x Rows.

   subtype Grey_Value is Int32 range 0 .. 255;
   subtype Grey_Product is Int32 range 0 .. 65025;

   function Product (A, B : Grey_Value) return Grey_Product;
   --  A * B for two grey levels, the only product of the clipped sums; its
   --  body is hidden from the callers, so that their loops stay linear.

   function Product (A, B : Grey_Value) return Grey_Product is
   begin
      pragma Assert (A * B <= 255 * B);
      return A * B;
   end Product;

   procedure Clipped_Pattern_Sums
     (Pattern : KL.Grey_8_Matrix;
      Care    : KL.Grey_8_Matrix;
      Masked  : Boolean;
      P_Geo   : Level_Geometry;
      Cols    : Span;
      Rows    : Span;
      Count   : out KL.Cared_Count;
      Sum     : out KL.Grey_Sum;
      Square  : out KL.Square_Sum)
   with
     Pre => Clip_Fits (Pattern, P_Geo, Cols, Rows)
            and then (if Masked then KL.Same_Shape (Care, Pattern));
   --  Over the pixels of the clipped part Cols x Rows of the pattern level
   --  P_Geo (with Masked, its cared-for pixels only): their number, Sum p
   --  and Sum p**2.

   procedure Clipped_Pattern_Sums
     (Pattern : KL.Grey_8_Matrix;
      Care    : KL.Grey_8_Matrix;
      Masked  : Boolean;
      P_Geo   : Level_Geometry;
      Cols    : Span;
      Rows    : Span;
      Count   : out KL.Cared_Count;
      Sum     : out KL.Grey_Sum;
      Square  : out KL.Square_Sum)
   is
      Row_Limit : constant := 65025 * Max_Pattern_Side;
      Number    : Int64 := 0;
      Total     : Int64 := 0;
      Squares   : Int64 := 0;
   begin
      for V in 0 .. Rows.Length - 1 loop
         declare
            Row        : constant Natural := P_Geo.Row + Rows.Pattern_First + V;
            Row_Count  : Int32 := 0;
            Row_Sum    : Int32 := 0;
            Row_Square : Int32 := 0;
         begin
            for U in 0 .. Cols.Length - 1 loop
               if not Masked or else Care (Row, Cols.Pattern_First + U) /= 0
               then
                  declare
                     P : constant Grey_Value :=
                       Grey_Value (Pattern (Row, Cols.Pattern_First + U));
                  begin
                     Row_Count := Row_Count + 1;
                     Row_Sum := Row_Sum + P;
                     Row_Square := Row_Square + Product (P, P);
                  end;
               end if;
               pragma Loop_Invariant
                 (Row_Count in 0 .. Int32 (U + 1)
                  and then Row_Sum in 0 .. 255 * Int32 (U + 1)
                  and then Row_Square in 0 .. 65025 * Int32 (U + 1));
            end loop;
            pragma Assert (Row_Count <= Max_Pattern_Side
                           and then Row_Sum <= 255 * Max_Pattern_Side
                           and then Row_Square <= Row_Limit);
            Number := Number + Int64 (Row_Count);
            Total := Total + Int64 (Row_Sum);
            Squares := Squares + Int64 (Row_Square);
         end;
         pragma Loop_Invariant
           (Number in 0 .. Max_Pattern_Side * Int64 (V + 1)
            and then Total in 0 .. 255 * Max_Pattern_Side * Int64 (V + 1)
            and then Squares in 0 .. Row_Limit * Int64 (V + 1));
      end loop;
      Count := Number;
      Sum := Total;
      Square := Squares;
   end Clipped_Pattern_Sums;

   procedure Clipped_Window_Sums
     (Image   : KL.Grey_8_Matrix;
      I_Geo   : Level_Geometry;
      Pattern : KL.Grey_8_Matrix;
      Care    : KL.Grey_8_Matrix;
      Masked  : Boolean;
      P_Geo   : Level_Geometry;
      Cols    : Span;
      Rows    : Span;
      Cross   : out Cross_Value;
      Sum     : out KL.Grey_Sum;
      Square  : out KL.Square_Sum)
   with
     Pre => Clip_Fits (Pattern, P_Geo, Cols, Rows)
            and then (if Masked then KL.Same_Shape (Care, Pattern))
            and then Image_Fits (Image, I_Geo, Cols, Rows);
   --  Over the pixels of the clipped part Cols x Rows of the pattern level
   --  P_Geo (with Masked, its cared-for pixels only) and the pixels of the
   --  image level I_Geo under them: Sum (p w), Sum w and Sum w**2.

   procedure Clipped_Window_Sums
     (Image   : KL.Grey_8_Matrix;
      I_Geo   : Level_Geometry;
      Pattern : KL.Grey_8_Matrix;
      Care    : KL.Grey_8_Matrix;
      Masked  : Boolean;
      P_Geo   : Level_Geometry;
      Cols    : Span;
      Rows    : Span;
      Cross   : out Cross_Value;
      Sum     : out KL.Grey_Sum;
      Square  : out KL.Square_Sum)
   is
      Row_Limit    : constant := 65025 * Max_Pattern_Side;
      Total_Cross  : Int64 := 0;
      Total_Sum    : Int64 := 0;
      Total_Square : Int64 := 0;
   begin
      for V in 0 .. Rows.Length - 1 loop
         declare
            Pattern_Row : constant Natural :=
              P_Geo.Row + Rows.Pattern_First + V;
            Image_Row   : constant Natural :=
              I_Geo.Row + Rows.Image_First + V;
            Row_Cross   : Int32 := 0;
            Row_Sum     : Int32 := 0;
            Row_Square  : Int32 := 0;
         begin
            for U in 0 .. Cols.Length - 1 loop
               if not Masked
                 or else Care (Pattern_Row, Cols.Pattern_First + U) /= 0
               then
                  declare
                     W : constant Grey_Value :=
                       Grey_Value (Image (Image_Row, Cols.Image_First + U));
                     P : constant Grey_Value :=
                       Grey_Value
                         (Pattern (Pattern_Row, Cols.Pattern_First + U));
                  begin
                     Row_Cross := Row_Cross + Product (P, W);
                     Row_Sum := Row_Sum + W;
                     Row_Square := Row_Square + Product (W, W);
                  end;
               end if;
               pragma Loop_Invariant
                 (Row_Cross in 0 .. 65025 * Int32 (U + 1)
                  and then Row_Sum in 0 .. 255 * Int32 (U + 1)
                  and then Row_Square in 0 .. 65025 * Int32 (U + 1));
            end loop;
            pragma Assert (Row_Cross <= Row_Limit
                           and then Row_Sum <= 255 * Max_Pattern_Side
                           and then Row_Square <= Row_Limit);
            Total_Cross := Total_Cross + Int64 (Row_Cross);
            Total_Sum := Total_Sum + Int64 (Row_Sum);
            Total_Square := Total_Square + Int64 (Row_Square);
         end;
         pragma Loop_Invariant
           (Total_Cross in 0 .. Row_Limit * Int64 (V + 1)
            and then Total_Sum in 0 .. 255 * Max_Pattern_Side * Int64 (V + 1)
            and then Total_Square in 0 .. Row_Limit * Int64 (V + 1));
      end loop;
      Cross := Total_Cross;
      Sum := Total_Sum;
      Square := Total_Square;
   end Clipped_Window_Sums;

   type Partial_Part is record
      Count    : KL.Cared_Count := 0;
      P_Sum    : KL.Grey_Sum := 0;
      P_Square : KL.Square_Sum := 0;
      Cross    : Cross_Value := 0;
      W_Sum    : KL.Grey_Sum := 0;
      W_Square : KL.Square_Sum := 0;
   end record;
   --  The sums of a partial window over its clipped part: the number N_in
   --  of the pattern's (cared-for) pixels there, Sum p, Sum p**2,
   --  Sum (p w), Sum w and Sum w**2.

   function Pattern_Matches
     (Plan    : KL.Search_Plan;
      Image   : KL.Grey_8_Matrix;
      Pattern : KL.Grey_8_Matrix;
      Care    : KL.Grey_8_Matrix) return Boolean
   is
     (KL.Image_Matches (Plan, Image)
      and then Pattern'First (1) = 0 and then Pattern'First (2) = 0
      and then Plan.Pattern_Rows >= 1 and then Plan.Pattern_Columns >= 1
      and then Pattern'Last (1) = Plan.Pattern_Rows - 1
      and then Pattern'Last (2) = Plan.Pattern_Columns - 1
      and then KL.Care_Matches (Plan, Care));
   --  KL.Matches without the integral images.

   procedure Partial_Sums
     (Plan    : KL.Valid_Search_Plan;
      Image   : KL.Grey_8_Matrix;
      Pattern : KL.Grey_8_Matrix;
      Care    : KL.Grey_8_Matrix;
      L       : Natural;
      X, Y    : Natural;
      Part    : out Partial_Part)
   with
     Pre => Pattern_Matches (Plan, Image, Pattern, Care)
            and then L < Plan.Levels
            and then X <= KL.Last_X (Plan, L)
            and then Y <= KL.Last_Y (Plan, L);
   --  The sums of the window at position (X, Y) of level L over the part
   --  that lies inside the level (all of it for a window inside).

   procedure Partial_Sums
     (Plan    : KL.Valid_Search_Plan;
      Image   : KL.Grey_8_Matrix;
      Pattern : KL.Grey_8_Matrix;
      Care    : KL.Grey_8_Matrix;
      L       : Natural;
      X, Y    : Natural;
      Part    : out Partial_Part)
   is
      P    : constant Level_Geometry := Plan.Pattern (L).Geometry;
      G    : constant Level_Geometry := Plan.Image (L);
      Cols : Span;
      Rows : Span;
   begin
      pragma Assert (KL.Level_OK (Plan, L));
      Cols := Clip_Along (X, Plan.Left, P.Width, G.Width);
      Rows := Clip_Along (Y, Plan.Up, P.Height, G.Height);
      pragma Assert (KL.Rows_Of (Pattern) = Plan.Pattern_Rows
                     and then KL.Columns_Of (Pattern) = Plan.Pattern_Columns
                     and then KL.Rows_Of (Image) = Plan.Stack_Rows
                     and then KL.Columns_Of (Image) = Plan.Stack_Columns);
      Clipped_Pattern_Sums (Pattern, Care, Plan.Masked, P, Cols, Rows,
                            Part.Count, Part.P_Sum, Part.P_Square);
      Clipped_Window_Sums (Image, G, Pattern, Care, Plan.Masked, P, Cols,
                           Rows, Part.Cross, Part.W_Sum, Part.W_Square);
   end Partial_Sums;

   function Partial_Score
     (Part            : Partial_Part;
      Total           : KL.Count_Value;
      Reduce          : Boolean;
      Ignore_Polarity : Boolean) return Score_Value;
   --  The score of a partial window from its sums (Total: the pattern
   --  level's count N): 0 when 4 N_in < N or the clipped pattern is flat,
   --  multiplied by N_in / N with Reduce.

   function Partial_Score
     (Part            : Partial_Part;
      Total           : KL.Count_Value;
      Reduce          : Boolean;
      Ignore_Polarity : Boolean) return Score_Value
   is
      Spread : KL.Spread_Value;
      Score  : Score_Value;
   begin
      if Part.Count < 1 or else 4 * Part.Count < Total then
         return 0.0;
      end if;
      Spread := KL.Spread_Of (Part.Count, Part.P_Sum, Part.P_Square);
      if Spread <= 0 then
         return 0.0;
      end if;
      Score := Score_Of (Part.Count, Part.Cross, Part.P_Sum, Spread,
                         Part.W_Sum, Part.W_Square, Ignore_Polarity);
      if Reduce and then Part.Count < Total then
         Score := N.Times_Unit
           (Score,
            N.Clamp_Unit (N.Unit_Ratio (Long_Float (Part.Count),
                                        Long_Float (Total))));
      end if;
      return Score;
   end Partial_Score;

   function Score_At
     (Plan            : KL.Valid_Search_Plan;
      Image           : KL.Grey_8_Matrix;
      Sums            : KL.Sum_Matrix;
      Pattern         : KL.Grey_8_Matrix;
      Care            : KL.Grey_8_Matrix;
      L               : Natural;
      Ignore_Polarity : Boolean;
      X, Y            : Natural) return Score_Value
   is
   begin
      pragma Assert (KL.Level_OK (Plan, L));
      if KL.Inside (Plan, L, X, Y) then
         return Inner_Score (Plan, Image, Sums, Pattern, Care, L,
                             Ignore_Polarity, X - Plan.Left, Y - Plan.Up);
      end if;
      declare
         Part : Partial_Part;
      begin
         Partial_Sums (Plan, Image, Pattern, Care, L, X, Y, Part);
         return Partial_Score (Part, Plan.Pattern (L).Count, Plan.Reduce,
                               Ignore_Polarity);
      end;
   end Score_At;

   function Contrast_Of
     (Window_Spread  : KL.Spread_Value;
      Pattern_Spread : KL.Positive_Spread) return Contrast_Value;
   --  The square root of Window_Spread / Pattern_Spread (0 for a flat
   --  window).

   function Contrast_Of
     (Window_Spread  : KL.Spread_Value;
      Pattern_Spread : KL.Positive_Spread) return Contrast_Value
   is
      Ratio : Long_Float;
      Fits  : Boolean;
   begin
      if Window_Spread <= 0 then
         return 0.0;
      end if;
      N.Ratio_Within (Long_Float (Window_Spread), Long_Float (Pattern_Spread),
                      Limit_56, Ratio, Fits);
      if not Fits then
         --  Never: the pattern's spread is at least 1.
         return 2.0 ** 28;
      end if;
      declare
         Root : constant Long_Float :=
           Ada.Numerics.Long_Elementary_Functions.Sqrt (Ratio);
      begin
         --  The root of at most 2**56 is at most 2**28; the runtime's
         --  Sqrt has no upper bound in its contract.
         return (if Root <= 2.0 ** 28 then Root else 2.0 ** 28);
      end;
   end Contrast_Of;

   function Inner_Contrast
     (Plan  : KL.Valid_Search_Plan;
      Image : KL.Grey_8_Matrix;
      Sums  : KL.Sum_Matrix;
      Care  : KL.Grey_8_Matrix;
      L     : Natural;
      X, Y  : Natural) return Contrast_Value
   with
     Pre => KL.Image_Matches (Plan, Image)
            and then KL.Sums_From_Zero (Sums)
            and then Sums'Last (1) = Plan.Sum_Rows - 1
            and then Sums'Last (2) = Plan.Sum_Columns - 1
            and then KL.Care_Matches (Plan, Care)
            and then L < Plan.Levels
            and then KL.Level_OK (Plan, L)
            and then X <= Plan.Image (L).Width - Plan.Pattern (L).Geometry.Width
            and then Y <= Plan.Image (L).Height
                          - Plan.Pattern (L).Geometry.Height;
   --  The contrast of the window whose first pixel lies at (X, Y) of
   --  level L, inside the level.

   function Inner_Contrast
     (Plan  : KL.Valid_Search_Plan;
      Image : KL.Grey_8_Matrix;
      Sums  : KL.Sum_Matrix;
      Care  : KL.Grey_8_Matrix;
      L     : Natural;
      X, Y  : Natural) return Contrast_Value
   is
      P      : constant KL.Pattern_Level := Plan.Pattern (L);
      Sum    : KL.Grey_Sum;
      Square : KL.Square_Sum;
   begin
      if Plan.Masked then
         pragma Assert
           (KL.Stacked (Plan.Image (L), KL.Rows_Of (Image),
                        KL.Columns_Of (Image))
            and then KL.Stacked (P.Geometry, KL.Rows_Of (Care),
                                 KL.Columns_Of (Care)));
         Masked_Window_Sums (Image, Plan.Image (L), X, Y, Care, P.Geometry,
                             Sum, Square);
      else
         KL.Window_Sums (Sums, Plan.Base (L), X, Y, P.Geometry.Width,
                         P.Geometry.Height, Sum, Square);
      end if;
      return Contrast_Of (KL.Spread_Of (P.Count, Sum, Square), P.Spread);
   end Inner_Contrast;

   function Contrast_At
     (Plan    : KL.Valid_Search_Plan;
      Image   : KL.Grey_8_Matrix;
      Sums    : KL.Sum_Matrix;
      Pattern : KL.Grey_8_Matrix;
      Care    : KL.Grey_8_Matrix;
      L       : Natural;
      X, Y    : Natural) return Contrast_Value
   is
   begin
      pragma Assert (KL.Level_OK (Plan, L));
      if KL.Inside (Plan, L, X, Y) then
         return Inner_Contrast (Plan, Image, Sums, Care, L, X - Plan.Left,
                                Y - Plan.Up);
      end if;
      declare
         Part   : Partial_Part;
         Spread : KL.Spread_Value;
      begin
         Partial_Sums (Plan, Image, Pattern, Care, L, X, Y, Part);
         if Part.Count < 1 or else 4 * Part.Count < Plan.Pattern (L).Count
         then
            return 0.0;
         end if;
         Spread := KL.Spread_Of (Part.Count, Part.P_Sum, Part.P_Square);
         if Spread <= 0 then
            return 0.0;
         end if;
         return Contrast_Of
           (KL.Spread_Of (Part.Count, Part.W_Sum, Part.W_Square), Spread);
      end;
   end Contrast_At;

   ---------------------------------------------------------------------
   --  The sub-pixel peak
   ---------------------------------------------------------------------

   function Parabola_Offset (Left, Centre, Right : Score_Value) return Offset
   is
      Curve      : constant Long_Float := (Centre - Left) + (Centre - Right);
      Difference : constant Long_Float := Right - Left;
   begin
      if Curve <= 0.0 then
         --  Not a maximum along this axis.
         return 0.0;
      elsif Difference >= Curve then
         return 0.5;
      elsif Difference <= -Curve then
         return -0.5;
      else
         return N.Unit_Ratio (Difference, Curve) / 2.0;
      end if;
   end Parabola_Offset;
   --  The vertex of the parabola through (-1, Left), (0, Centre), (1,
   --  Right): (Right - Left) / (2 (2 Centre - Left - Right)), limited to
   --  half a pixel; 0 when the parabola has no maximum.

   --  The quadratic fit. Along each axis the samples are either the three
   --  positions -1 .. 1 (Shift 0, centred on the peak position) or four
   --  positions, -1 .. 2 (Shift 1) or -2 .. 1 (Shift -1), centred half a
   --  pixel away on the side of the peak. With U the sample coordinate
   --  relative to that centre, the polynomials 1, U and U**2 - Mean (U**2)
   --  are orthogonal over the samples of an axis, and so are their
   --  products over the grid; the least-squares surface
   --
   --     f = A + Bx U + By V + Cx (U**2 - Mx) + Cy (V**2 - My) + E U V
   --
   --  then has every coefficient as a ratio of one weighted sum of the
   --  scores and a constant: Bx = Sum (S U) / (Ny Sum U**2), Cx = Sum (S
   --  (U**2 - Mx)) / (Ny Sum (U**2 - Mx)**2), E = Sum (S U V) / (Sum U**2
   --  Sum V**2), and the same for y. Its stationary point solves
   --  2 Cx U + E V = -Bx, E U + 2 Cy V = -By.

   subtype Axis_Shift is Integer range -1 .. 1;

   function First_Of (Shift : Axis_Shift) return Integer is
     (if Shift = -1 then -2 else -1);
   function Last_Of (Shift : Axis_Shift) return Integer is
     (if Shift = 1 then 2 else 1);
   --  The sample positions of an axis.

   subtype Sample_Coordinate is Long_Float range -1.5 .. 1.5;
   subtype Centred_Range is Long_Float range -1.25 .. 1.0;

   function Coordinate_Of (K : Integer; Shift : Axis_Shift)
      return Sample_Coordinate
   is
     (Long_Float (K) - Long_Float (Shift) / 2.0)
   with Pre => K in First_Of (Shift) .. Last_Of (Shift);
   --  U of the sample at K.

   function Centred_Square (U : Sample_Coordinate; Shift : Axis_Shift)
      return Centred_Range
   is
     (if Shift = 0 then U * U - 2.0 / 3.0 else U * U - 1.25)
   with Pre => (if Shift = 0 then abs U <= 1.0);
   --  U**2 - Mean (U**2) (2/3 for three samples, 1.25 for four).

   function Centre_Of (Shift : Axis_Shift) return Long_Float is
     (if Shift = -1 then -0.5 elsif Shift = 1 then 0.5 else 0.0);
   --  The centre of the samples of an axis.

   function Linear_Divisor (Along, Across : Axis_Shift) return Long_Float is
     (if Along = 0 then (if Across = 0 then 6.0 else 8.0)
      else (if Across = 0 then 15.0 else 20.0));
   --  The number of samples across times Sum U**2 along (2 for three
   --  samples, 5 for four): the divisor of a linear coefficient.

   function Centred_Divisor (Along, Across : Axis_Shift) return Long_Float
   is
     (if Along = 0 then (if Across = 0 then 2.0 else 8.0 / 3.0)
      else (if Across = 0 then 12.0 else 16.0));
   --  The number of samples across times Sum (U**2 - Mean (U**2))**2
   --  along (2/3 for three samples, 4 for four): the divisor of a
   --  quadratic coefficient.

   function Cross_Divisor (Shift_X, Shift_Y : Axis_Shift) return Long_Float
   is
     (if Shift_X = 0 then (if Shift_Y = 0 then 4.0 else 10.0)
      else (if Shift_Y = 0 then 10.0 else 25.0));
   --  Sum U**2 times Sum V**2: the divisor of the coefficient of U V.

   subtype Term is Long_Float range -2.25 .. 2.25;
   --  A term of the weighted sums (a score times U, V, U V or a centred
   --  square).

   Sum_Limit : constant := 64.0;

   subtype Bounded_Sum is Long_Float range -Sum_Limit .. Sum_Limit;

   function Accumulate (Sum : Bounded_Sum; T : Term) return Bounded_Sum is
     (N.Clamp (Sum + T, Sum_Limit));
   --  Sum + T, limited to Sum_Limit: a sum of at most 16 terms of at most
   --  2.25 never reaches it.

   subtype Coefficient is Long_Float range -16.0 .. 16.0;

   function Scaled (Sum : Bounded_Sum; Divisor : Long_Float)
      return Coefficient
   is
     (N.Clamp (Sum / Divisor, 16.0))
   with Pre => Divisor >= 2.0 and then Divisor <= 25.0;
   --  Sum / Divisor, limited to 16 (each coefficient is at most 2 in
   --  magnitude for scores in [0, 1]; the limit never acts).

   type Weighted_Sums is record
      BX, BY, CX, CY, E : Bounded_Sum := 0.0;
   end record;
   --  The weighted sums of the scores: by U, by V, by the centred squares
   --  of U and V, and by U V.

   procedure Add_Sample
     (Sums   : in out Weighted_Sums;
      V      : Score_Value;
      U, W   : Sample_Coordinate;
      CU, CW : Centred_Range);
   --  Adds the terms of one sample (score V at U, W).

   procedure Add_Sample
     (Sums   : in out Weighted_Sums;
      V      : Score_Value;
      U, W   : Sample_Coordinate;
      CU, CW : Centred_Range)
   is
      UW : constant Term := N.Mul_Within (U, W, 1.5, 1.5);
   begin
      Sums.BX := Accumulate (Sums.BX, N.Times_Unit (U, V));
      Sums.BY := Accumulate (Sums.BY, N.Times_Unit (W, V));
      Sums.CX := Accumulate (Sums.CX, N.Times_Unit (CU, V));
      Sums.CY := Accumulate (Sums.CY, N.Times_Unit (CW, V));
      Sums.E := Accumulate (Sums.E, N.Times_Unit (UW, V));
   end Add_Sample;

   function Shifted (Centre : Long_Float; Ratio : Long_Float)
      return Long_Float
   is
     (Centre + Ratio)
   with Pre  => Centre in -0.5 .. 0.5 and then Ratio in -1.0 .. 1.0,
        Post => Shifted'Result in -1.5 .. 1.5;
   --  The peak's coordinate from the centre of the samples.

   procedure Solve
     (BX, BY, CX, CY, E  : Coefficient;
      Centre_X, Centre_Y : Long_Float;
      Found              : out Boolean;
      OX, OY             : out Offset)
   with
     Pre  => Centre_X in -0.5 .. 0.5 and then Centre_Y in -0.5 .. 0.5,
     Post => (if not Found then OX = 0.0 and then OY = 0.0);
   --  The stationary point of the surface with these coefficients (see
   --  above), when it is a maximum within one pixel of the position.

   procedure Solve
     (BX, BY, CX, CY, E  : Coefficient;
      Centre_X, Centre_Y : Long_Float;
      Found              : out Boolean;
      OX, OY             : out Offset)
   is
      Det : constant Long_Float :=
        4.0 * N.Mul_Within (CX, CY, 16.0, 16.0) - N.Square_Within (E, 16.0);
      NU  : constant Long_Float :=
        N.Mul_Within (E, BY, 16.0, 16.0)
        - 2.0 * N.Mul_Within (CY, BX, 16.0, 16.0);
      NV  : constant Long_Float :=
        N.Mul_Within (E, BX, 16.0, 16.0)
        - 2.0 * N.Mul_Within (CX, BY, 16.0, 16.0);
   begin
      Found := False;
      OX := 0.0;
      OY := 0.0;
      if CX < 0.0 and then Det > 1.0E-12
        and then abs NU <= Det and then abs NV <= Det
      then
         declare
            PX : constant Long_Float :=
              Shifted (Centre_X, N.Unit_Ratio (NU, Det));
            PY : constant Long_Float :=
              Shifted (Centre_Y, N.Unit_Ratio (NV, Det));
         begin
            if abs PX <= 1.0 and then abs PY <= 1.0 then
               Found := True;
               OX := PX;
               OY := PY;
            end if;
         end;
      end if;
   end Solve;

   procedure Grid_Peak
     (S        : Neighbourhood;
      Shift_X  : Axis_Shift;
      Shift_Y  : Axis_Shift;
      Found    : out Boolean;
      OX, OY   : out Offset)
   with Post => (if not Found then OX = 0.0 and then OY = 0.0);
   --  The maximum of the least-squares quadratic over the samples the
   --  shifts select (see above), as an offset from the centre position,
   --  when the surface has a maximum within one pixel of it along both
   --  axes.

   procedure Grid_Peak
     (S        : Neighbourhood;
      Shift_X  : Axis_Shift;
      Shift_Y  : Axis_Shift;
      Found    : out Boolean;
      OX, OY   : out Offset)
   is
      Sums : Weighted_Sums;
   begin
      for L in First_Of (Shift_Y) .. Last_Of (Shift_Y) loop
         for K in First_Of (Shift_X) .. Last_Of (Shift_X) loop
            declare
               U : constant Sample_Coordinate := Coordinate_Of (K, Shift_X);
               W : constant Sample_Coordinate := Coordinate_Of (L, Shift_Y);
            begin
               Add_Sample (Sums, S (L, K), U, W, Centred_Square (U, Shift_X),
                           Centred_Square (W, Shift_Y));
            end;
         end loop;
      end loop;
      Solve
        (BX       => Scaled (Sums.BX, Linear_Divisor (Shift_X, Shift_Y)),
         BY       => Scaled (Sums.BY, Linear_Divisor (Shift_Y, Shift_X)),
         CX       => Scaled (Sums.CX, Centred_Divisor (Shift_X, Shift_Y)),
         CY       => Scaled (Sums.CY, Centred_Divisor (Shift_Y, Shift_X)),
         E        => Scaled (Sums.E, Cross_Divisor (Shift_X, Shift_Y)),
         Centre_X => Centre_Of (Shift_X),
         Centre_Y => Centre_Of (Shift_Y),
         Found    => Found,
         OX       => OX,
         OY       => OY);
   end Grid_Peak;

   function All_Present
     (Present          : Presence;
      Shift_X, Shift_Y : Axis_Shift) return Boolean
   is
     (for all L in First_Of (Shift_Y) .. Last_Of (Shift_Y) =>
        (for all K in First_Of (Shift_X) .. Last_Of (Shift_X) =>
           Present (L, K)));
   --  Every sample the shifts select is a position.

   function Shift_Toward (O : Offset) return Axis_Shift is
     (if O > 0.25 then 1 elsif O < -0.25 then -1 else 0);
   --  The samples for a peak O away from the position: centred on it when
   --  it is within a quarter pixel, otherwise centred half a pixel toward
   --  it.

   procedure Peak_Offset
     (Scores   : Neighbourhood;
      Present  : Presence;
      Accuracy : Int32;
      OX, OY   : out Offset)
   is
      Found  : Boolean;
      PX, PY : Offset;
   begin
      OX := 0.0;
      OY := 0.0;
      if Accuracy = Accuracy_Coarse then
         return;
      end if;
      if Accuracy = Accuracy_Very_Fine and then All_Present (Present, 0, 0)
      then
         Grid_Peak (Scores, 0, 0, Found, OX, OY);
         if Found then
            declare
               SX : constant Axis_Shift := Shift_Toward (OX);
               SY : constant Axis_Shift := Shift_Toward (OY);
            begin
               if (SX /= 0 or else SY /= 0)
                 and then All_Present (Present, SX, SY)
               then
                  Grid_Peak (Scores, SX, SY, Found, PX, PY);
                  if Found then
                     OX := PX;
                     OY := PY;
                  end if;
               end if;
            end;
            return;
         end if;
      end if;
      if Present (0, -1) and then Present (0, 1) then
         OX := Parabola_Offset (Scores (0, -1), Scores (0, 0), Scores (0, 1));
      end if;
      if Present (-1, 0) and then Present (1, 0) then
         OY := Parabola_Offset (Scores (-1, 0), Scores (0, 0), Scores (1, 0));
      end if;
   end Peak_Offset;

end AMV.Kernels.CNL_Search.Correlation;
