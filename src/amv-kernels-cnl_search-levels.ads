--  The pyramid levels of the CNL search (private to the kernel): how the
--  levels of a pattern or of a search box are stacked in one 8-bit image,
--  the halving from one level to the next, the care flags of a pattern
--  trained with a mask (stacked the same way), the statistics of a
--  pattern level, the integral images (sums and sums of squares in 64-bit
--  integers) of the search levels, and the plan that ties the levels of
--  the image, of its integral images and of the pattern together.
--
--  Stacking: level 0 occupies rows 0 .. Height - 1 of the stack, and
--  every further level the rows after the previous one, from column 0
--  (Level_Geometry). The integral image of level L of a search box is
--  Height_L + 1 rows of Width_L + 1 sums starting at row Base_L of a sum
--  matrix: entry (Base_L + J, I) holds the sum of the level's pixels in
--  rows 0 .. J - 1 and columns 0 .. I - 1 (and the same for the squares).

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

private package AMV.Kernels.CNL_Search.Levels
  with SPARK_Mode, Preelaborate
is

   subtype Grey_8_Matrix is KI.Grey_8_Matrix;

   ---------------------------------------------------------------------
   --  Values
   ---------------------------------------------------------------------

   Max_Pattern_Pixels : constant := Max_Pattern_Side * Max_Pattern_Side;
   --  2**20.

   subtype Count_Value is Int64 range 1 .. Max_Pattern_Pixels;
   subtype Cared_Count is Int64 range 0 .. Max_Pattern_Pixels;
   subtype Grey_Sum is Int64 range 0 .. Max_Grey_Sum;
   subtype Square_Sum is Int64 range 0 .. 65025 * Max_Pattern_Pixels;
   subtype Spread_Value is Int64 range -Max_Spread .. Max_Spread;
   subtype Positive_Spread is Int64 range 1 .. Max_Spread;
   --  The pixel count, grey level sums and spreads of a window as large
   --  as a pattern (at most 2**20 pixels).

   subtype Side is Natural range 1 .. Max_Pattern_Side;

   function Pixel_Count (Width, Height : Side) return Count_Value
   with Post => Pixel_Count'Result = Int64 (Width) * Int64 (Height);
   --  Width * Height.

   function Spread_Of
     (Count  : Count_Value;
      Sum    : Grey_Sum;
      Square : Square_Sum) return Spread_Value
   with Post => Spread_Of'Result = Count * Square - Sum * Sum;
   --  Count Square - Sum**2: N Sum x**2 - (Sum x)**2 for N grey levels x
   --  (never negative for real data, 0 for a flat window).

   ---------------------------------------------------------------------
   --  Stacked levels
   ---------------------------------------------------------------------

   function Stacked
     (G             : Level_Geometry;
      Rows, Columns : Natural) return Boolean
   is
     (G.Width >= 1 and then G.Height >= 1
      and then G.Width <= Columns
      and then G.Row <= Rows and then G.Height <= Rows - G.Row);
   --  The level lies in a stack of Rows rows of Columns pixels.

   function Indexed_From_Zero (M : Grey_8_Matrix) return Boolean is
     (M'First (1) = 0 and then M'First (2) = 0
      and then M'Last (1) >= 0 and then M'Last (2) >= 0
      and then M'Last (1) < Natural'Last and then M'Last (2) < Natural'Last);
   --  A non-empty matrix indexed from 0.

   function Rows_Of (M : Grey_8_Matrix) return Natural is
     (M'Last (1) + 1)
   with Pre => Indexed_From_Zero (M);

   function Columns_Of (M : Grey_8_Matrix) return Natural is
     (M'Last (2) + 1)
   with Pre => Indexed_From_Zero (M);

   type Geometry_Table is array (0 .. Max_Levels - 1) of Level_Geometry;

   procedure Plan_Levels
     (Width, Height : Positive;
      Wanted        : Positive;
      Min_Side      : Positive;
      Table         : out Geometry_Table;
      Levels        : out Positive;
      Rows          : out Positive)
   with
     Pre  => Wanted <= Max_Levels and then Height <= 2**29,
     Post => Levels <= Wanted
             and then Rows >= Height and then Rows <= 2 * Height
             and then Table (0) = (Row => 0, Width => Width, Height => Height)
             and then (for all L in 0 .. Levels - 1 =>
                         Table (L).Width in 1 .. Width
                         and then Table (L).Height in 1 .. Height
                         and then Stacked (Table (L), Rows, Width))
             and then (for all L in 1 .. Levels - 1 =>
                         Table (L).Width = Table (L - 1).Width / 2
                         and then Table (L).Height = Table (L - 1).Height / 2
                         and then Table (L).Width >= Min_Side
                         and then Table (L).Height >= Min_Side);
   --  The levels of a Width x Height level 0, halved while both sides of
   --  the next level are at least Min_Side, up to Wanted levels; Rows is
   --  the height of the stack.

   procedure Copy_Box
     (Source : Grey_8_Matrix;
      X0, Y0 : Natural;
      Target : in out Grey_8_Matrix;
      G      : Level_Geometry)
   with
     Pre  => Indexed_From_Zero (Source) and then Indexed_From_Zero (Target)
             and then Stacked (G, Rows_Of (Target), Columns_Of (Target))
             and then X0 <= Source'Last (2)
             and then G.Width - 1 <= Source'Last (2) - X0
             and then Y0 <= Source'Last (1)
             and then G.Height - 1 <= Source'Last (1) - Y0;
   --  Copies the G.Width x G.Height pixels of Source from (X0, Y0) into
   --  level G of Target.

   procedure Downsample
     (Pixels   : in out Grey_8_Matrix;
      From, To : Level_Geometry)
   with
     Pre => Indexed_From_Zero (Pixels)
            and then Stacked (From, Rows_Of (Pixels), Columns_Of (Pixels))
            and then Stacked (To, Rows_Of (Pixels), Columns_Of (Pixels))
            and then To.Width = From.Width / 2
            and then To.Height = From.Height / 2;
   --  Level To from level From: each pixel the rounded mean of a 2 x 2
   --  block ((A + B + C + D + 2) / 4).

   procedure Statistics
     (Pixels : Grey_8_Matrix;
      G      : Level_Geometry;
      Sum    : out Grey_Sum;
      Square : out Square_Sum)
   with
     Pre => Indexed_From_Zero (Pixels)
            and then Stacked (G, Rows_Of (Pixels), Columns_Of (Pixels))
            and then G.Width <= Max_Pattern_Side
            and then G.Height <= Max_Pattern_Side;
   --  The sums of the grey levels and of their squares over level G.

   ---------------------------------------------------------------------
   --  Care flags (a pattern trained with a mask)
   ---------------------------------------------------------------------

   --  The care flags of a pattern are a matrix of the size of its stacked
   --  pixels, with the same levels: 1 for a cared-for pixel, 0 for a
   --  don't-care one (any value other than 0 counts as cared for).

   function Same_Shape (A, B : Grey_8_Matrix) return Boolean is
     (A'First (1) = B'First (1) and then A'First (2) = B'First (2)
      and then A'Last (1) = B'Last (1) and then A'Last (2) = B'Last (2));

   Max_Shift : constant := 2**33;

   procedure Copy_Care
     (Mask             : access constant KI.Ks_Image_8_Grey_Data;
      Shift_X, Shift_Y : Int64;
      Target           : in out Grey_8_Matrix;
      G                : Level_Geometry)
   with
     Pre => KI.Valid_Image (Mask)
            and then Indexed_From_Zero (Target)
            and then Stacked (G, Rows_Of (Target), Columns_Of (Target))
            and then Shift_X in -Max_Shift .. Max_Shift
            and then Shift_Y in -Max_Shift .. Max_Shift;
   --  The flags of level G of Target from a train image mask: pixel
   --  (X, Y) of the level lies under mask pixel (X + Shift_X, Y +
   --  Shift_Y); its flag is 0 when that mask pixel exists and is 0, and 1
   --  otherwise.

   procedure Downsample_Care
     (Care     : in out Grey_8_Matrix;
      From, To : Level_Geometry)
   with
     Pre => Indexed_From_Zero (Care)
            and then Stacked (From, Rows_Of (Care), Columns_Of (Care))
            and then Stacked (To, Rows_Of (Care), Columns_Of (Care))
            and then To.Width = From.Width / 2
            and then To.Height = From.Height / 2;
   --  The flags of level To from those of level From (as Downsample
   --  halves the pixels): 1 when the four flags of the 2 x 2 block are
   --  all cared for, 0 otherwise.

   procedure Masked_Statistics
     (Pixels : Grey_8_Matrix;
      Care   : Grey_8_Matrix;
      G      : Level_Geometry;
      Count  : out Cared_Count;
      Sum    : out Grey_Sum;
      Square : out Square_Sum)
   with
     Pre => Indexed_From_Zero (Pixels) and then Same_Shape (Care, Pixels)
            and then Stacked (G, Rows_Of (Pixels), Columns_Of (Pixels))
            and then G.Width <= Max_Pattern_Side
            and then G.Height <= Max_Pattern_Side;
   --  The number of cared-for pixels of level G, and the sums of their
   --  grey levels and of their squares.

   ---------------------------------------------------------------------
   --  Integral images
   ---------------------------------------------------------------------

   Max_Box_Sum    : constant := 255 * Max_Search_Pixels;
   Max_Box_Square : constant := 65025 * Max_Search_Pixels;

   subtype Box_Sum is Int64 range 0 .. Max_Box_Sum;
   subtype Box_Square is Int64 range 0 .. Max_Box_Square;

   type Sum_Pair is record
      S  : Box_Sum := 0;
      S2 : Box_Square := 0;
   end record;
   --  The sums of the grey levels and of their squares over a rectangle
   --  of at most Max_Search_Pixels pixels.

   type Sum_Matrix is array (Natural range <>, Natural range <>) of Sum_Pair;
   type Sum_Matrix_Access is access Sum_Matrix;

   procedure Allocate_Sums
     (Rows, Columns : Positive;
      Sums          : out Sum_Matrix_Access)
   with
     Global => null,
     Post   => (if Sums /= null
                then Sums'First (1) = 0 and then Sums'Last (1) = Rows - 1
                     and then Sums'First (2) = 0
                     and then Sums'Last (2) = Columns - 1);
   --  A new sum matrix of Rows x Columns zero pairs, or null when the
   --  memory cannot be allocated. Trusted: the allocator raises
   --  Storage_Error, which SPARK cannot express.

   function Sums_From_Zero (Sums : Sum_Matrix) return Boolean is
     (Sums'First (1) = 0 and then Sums'First (2) = 0
      and then Sums'Last (1) >= 0 and then Sums'Last (2) >= 0
      and then Sums'Last (1) < Natural'Last
      and then Sums'Last (2) < Natural'Last);

   procedure Build_Sums
     (Pixels : Grey_8_Matrix;
      G      : Level_Geometry;
      Base   : Natural;
      Sums   : in out Sum_Matrix)
   with
     Pre => Indexed_From_Zero (Pixels)
            and then Stacked (G, Rows_Of (Pixels), Columns_Of (Pixels))
            and then Sums_From_Zero (Sums)
            and then G.Width <= Sums'Last (2)
            and then G.Width <= Max_Search_Pixels
            and then Base <= Sums'Last (1)
            and then G.Height <= Sums'Last (1) - Base;
   --  The integral image of level G, in rows Base .. Base + G.Height,
   --  columns 0 .. G.Width of Sums. Every entry is limited to the bounds
   --  of Sum_Pair, which it never exceeds when G has at most
   --  Max_Search_Pixels pixels (docs/PROOF.md).

   procedure Window_Sums
     (Sums      : Sum_Matrix;
      Base      : Natural;
      X, Y      : Natural;
      Width     : Side;
      Height    : Side;
      Sum       : out Grey_Sum;
      Square    : out Square_Sum)
   with
     Pre => Sums_From_Zero (Sums)
            and then X <= Sums'Last (2) and then Width <= Sums'Last (2) - X
            and then Base <= Sums'Last (1)
            and then Y <= Sums'Last (1) - Base
            and then Height <= Sums'Last (1) - Base - Y;
   --  The sums over the Width x Height window at (X, Y) of the level whose
   --  integral image starts at row Base (four entries each), limited to
   --  the bounds of a window of at most 2**20 pixels (which they never
   --  exceed).

   ---------------------------------------------------------------------
   --  The plan of a search
   ---------------------------------------------------------------------

   type Pattern_Level is record
      Geometry : Level_Geometry;
      Count    : Count_Value := 1;
      Sum      : Grey_Sum := 0;
      Spread   : Positive_Spread := 1;
   end record;
   --  A pattern level as the search uses it.

   type Base_Table is array (0 .. Max_Levels - 1) of Natural;
   type Pattern_Table is array (0 .. Max_Levels - 1) of Pattern_Level;

   subtype Margin is Natural range 0 .. Max_Pattern_Side / 2;
   --  A partial match limit: the pattern's columns or rows that may lie
   --  outside the search area on one side.

   type Search_Plan is record
      Levels          : Natural := 0;
      Masked          : Boolean := False;
      Stack_Rows      : Natural := 0;
      Stack_Columns   : Natural := 0;
      Sum_Rows        : Natural := 0;
      Sum_Columns     : Natural := 0;
      Pattern_Rows    : Natural := 0;
      Pattern_Columns : Natural := 0;
      Image           : Geometry_Table := [others => (0, 0, 0)];
      Base            : Base_Table := [others => 0];
      Pattern         : Pattern_Table :=
        [others => ((0, 0, 0), 1, 0, 1)];
      Left, Right     : Margin := 0;
      Up, Down        : Margin := 0;
      Reduce          : Boolean := False;
   end record;
   --  The levels of a search: Levels levels, each with its place in the
   --  stacked image (Stack_Rows x Stack_Columns), the first row of its
   --  integral image (Sum_Rows x Sum_Columns) and the pattern level
   --  searched there (in the pattern's stack, Pattern_Rows x
   --  Pattern_Columns, with Count its cared-for pixels). Masked: the
   --  pattern has care flags (a matrix of the size of its stack), and the
   --  sums of the score are taken over its cared-for pixels. Left, Right,
   --  Up and Down: the partial match limits, the pattern's columns or rows
   --  that may lie outside the level on each side (0 for a search without
   --  partial matches, and at every level of a pyramid search); the
   --  positions of a level are offset by Left and Up, so that position
   --  (X, Y) is the window whose first pixel lies at (X - Left, Y - Up) of
   --  the level. Reduce: PartialMatchReduceScore.

   function Level_Facts (Plan : Search_Plan; L : Natural) return Boolean is
     (L < Max_Levels
      and then Stacked (Plan.Image (L), Plan.Stack_Rows, Plan.Stack_Columns)
      and then Plan.Image (L).Width < Plan.Sum_Columns
      and then Plan.Image (L).Width <= Max_Search_Pixels
      and then Plan.Image (L).Height <= Max_Search_Pixels
      and then Plan.Base (L) < Plan.Sum_Rows
      and then Plan.Image (L).Height < Plan.Sum_Rows - Plan.Base (L)
      and then Stacked (Plan.Pattern (L).Geometry, Plan.Pattern_Rows,
                        Plan.Pattern_Columns)
      and then Plan.Pattern (L).Geometry.Width <= Max_Pattern_Side
      and then Plan.Pattern (L).Geometry.Height <= Max_Pattern_Side
      and then Plan.Pattern (L).Geometry.Width <= Plan.Image (L).Width
      and then Plan.Pattern (L).Geometry.Height <= Plan.Image (L).Height
      and then 2 * Plan.Left <= Plan.Pattern (L).Geometry.Width
      and then 2 * Plan.Right <= Plan.Pattern (L).Geometry.Width
      and then 2 * Plan.Up <= Plan.Pattern (L).Geometry.Height
      and then 2 * Plan.Down <= Plan.Pattern (L).Geometry.Height);
   --  Level L lies in the stack, its integral image in the sums, its
   --  pattern level in the pattern's stack, the pattern fits in it, and
   --  each partial match limit is at most half the pattern's side.

   function Level_OK (Plan : Search_Plan; L : Natural) return Boolean
   with Post => Level_OK'Result = Level_Facts (Plan, L);
   --  Level_Facts as an ordinary function, so that the quantified fact of
   --  Valid_Plan is matched by Level_OK (Plan, L) instead of being taken
   --  apart into its conjuncts (docs/PROOF.md, proof notes).

   function Valid_Plan (Plan : Search_Plan) return Boolean is
     (Plan.Levels in 1 .. Max_Levels
      and then Plan.Stack_Rows >= 1 and then Plan.Stack_Columns >= 1
      and then Plan.Sum_Rows >= 1 and then Plan.Sum_Columns >= 1
      and then Plan.Pattern_Rows >= 1 and then Plan.Pattern_Columns >= 1
      and then Plan.Stack_Rows < Natural'Last
      and then Plan.Stack_Columns < Natural'Last
      and then (for all L in 0 .. Plan.Levels - 1 => Level_OK (Plan, L)));

   subtype Valid_Search_Plan is Search_Plan
     with Dynamic_Predicate => Valid_Plan (Valid_Search_Plan);
   --  Internal subprograms take this subtype: the predicate is proved at
   --  each call and not executed (docs/DESIGN.md 9.2).

   function Image_Matches
     (Plan  : Search_Plan;
      Image : Grey_8_Matrix) return Boolean
   is
     (Image'First (1) = 0 and then Image'First (2) = 0
      and then Plan.Stack_Rows >= 1 and then Plan.Stack_Columns >= 1
      and then Image'Last (1) = Plan.Stack_Rows - 1
      and then Image'Last (2) = Plan.Stack_Columns - 1);
   --  Image is the stack the plan was made for.

   function Care_Matches
     (Plan : Search_Plan;
      Care : Grey_8_Matrix) return Boolean
   is
     (if Plan.Masked
      then Care'First (1) = 0 and then Care'First (2) = 0
           and then Plan.Pattern_Rows >= 1 and then Plan.Pattern_Columns >= 1
           and then Care'Last (1) = Plan.Pattern_Rows - 1
           and then Care'Last (2) = Plan.Pattern_Columns - 1);
   --  Care has the size of the pattern's stack when the plan is Masked.

   function Matches
     (Plan    : Search_Plan;
      Image   : Grey_8_Matrix;
      Sums    : Sum_Matrix;
      Pattern : Grey_8_Matrix;
      Care    : Grey_8_Matrix) return Boolean
   is
     (Image'First (1) = 0 and then Image'First (2) = 0
      and then Plan.Stack_Rows >= 1 and then Plan.Stack_Columns >= 1
      and then Image'Last (1) = Plan.Stack_Rows - 1
      and then Image'Last (2) = Plan.Stack_Columns - 1
      and then Sums'First (1) = 0 and then Sums'First (2) = 0
      and then Plan.Sum_Rows >= 1 and then Plan.Sum_Columns >= 1
      and then Sums'Last (1) = Plan.Sum_Rows - 1
      and then Sums'Last (2) = Plan.Sum_Columns - 1
      and then Pattern'First (1) = 0 and then Pattern'First (2) = 0
      and then Plan.Pattern_Rows >= 1 and then Plan.Pattern_Columns >= 1
      and then Pattern'Last (1) = Plan.Pattern_Rows - 1
      and then Pattern'Last (2) = Plan.Pattern_Columns - 1
      and then Care_Matches (Plan, Care));
   --  The arrays have the sizes the plan was made for (Care is not used
   --  when the plan is not Masked).

   function Last_X (Plan : Valid_Search_Plan; L : Natural) return Natural
   with Pre  => L < Plan.Levels,
        Post => Last_X'Result
                  = Plan.Image (L).Width - Plan.Pattern (L).Geometry.Width
                    + Plan.Left + Plan.Right
                and then Last_X'Result <= Plan.Image (L).Width
                and then Last_X'Result <= Max_Search_Pixels
                and then Level_OK (Plan, L);
   function Last_Y (Plan : Valid_Search_Plan; L : Natural) return Natural
   with Pre  => L < Plan.Levels,
        Post => Last_Y'Result
                  = Plan.Image (L).Height
                    - Plan.Pattern (L).Geometry.Height
                    + Plan.Up + Plan.Down
                and then Last_Y'Result <= Plan.Image (L).Height
                and then Last_Y'Result <= Max_Search_Pixels
                and then Level_OK (Plan, L);
   --  The last window position along each axis at level L (positions
   --  start at 0; see Left and Up).

   function Inside
     (Plan : Valid_Search_Plan;
      L    : Natural;
      X, Y : Natural) return Boolean
   is
     (X >= Plan.Left and then Y >= Plan.Up
      and then X - Plan.Left
                 <= Plan.Image (L).Width - Plan.Pattern (L).Geometry.Width
      and then Y - Plan.Up
                 <= Plan.Image (L).Height - Plan.Pattern (L).Geometry.Height)
   with Pre => L < Plan.Levels;
   --  The window at position (X, Y) of level L lies inside the level (it
   --  is not a partial window).

end AMV.Kernels.CNL_Search.Levels;
