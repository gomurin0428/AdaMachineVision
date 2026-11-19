--  The finder patterns of the QR Code finder kernel
--  (AMV.Kernels.Code_Reader.QR_Code.Finder.Find_Patterns) on small
--  maps of dark pixels that are made here pixel by pixel: exact
--  patterns, patterns whose rings have uneven widths, patterns with
--  single pixels changed, patterns at the edge of the map and a table
--  of patterns that is full; and a symbol drawn in perspective.
--
--  The symbols that the other tests of the finder paint are whole and
--  even, so they do not show where the limits of the search are: how
--  far five runs may be from 1 : 1 : 3 : 1 : 1, how far a column may
--  be from its row, what the diagonals must show, where the pixels of
--  the middle put the centre, which patterns a full table keeps. The
--  maps here are made for those limits, by hand or by a search for
--  maps on which a change of one operator or of one number in the body
--  of the finder changes what is found.
--
--  What is expected of a map is what the finder gives for it: the
--  centre, the width of a module and the number of rows the pattern
--  was found in. Where the reason is plain it is in a comment. So
--  these checks do not say that every result is the right one; they
--  say that none of them changes unseen.

with Ada.Unchecked_Deallocation;

with AMV.Images;             use AMV.Images;
with AMV.Images.Kernel_Images;
with AMV.Kernels.Code_Reader.Dark_Areas;
with AMV.Kernels.Code_Reader.QR_Code.Finder;
with AMV.Kernels.Images;
with AMV_Test_Data_Matrix;
with AMV_Test_Images;
with AMV_Test_QR_Code;
with AMV_Test_Support;       use AMV_Test_Support;

procedure Test_Code_Reader_QR_Patterns is

   package DA renames AMV.Kernels.Code_Reader.Dark_Areas;
   package FN renames AMV.Kernels.Code_Reader.QR_Code.Finder;

   use type DA.Mark;

   subtype Real is Long_Float;

   Near : constant := 1.0E-9;

   type Widths is array (1 .. 5) of Positive;
   --  The widths of the five runs of a pattern in pixels: dark, light,
   --  dark, light and dark.

   function Even (Module : Positive) return Widths is
     [Module, Module, 3 * Module, Module, Module];

   type Pixel is record
      X, Y : Natural;
   end record;

   type Pixel_Array is array (Positive range <>) of Pixel;

   type Found is record
      X, Y, Module : Real;
      Seen         : Natural;
   end record;
   --  A pattern as the finder gives it: its centre, the width of a
   --  module and the number of rows it was found in.

   type Found_Array is array (Positive range <>) of Found;

   ---------------------------------------------------------------------
   --  Maps
   ---------------------------------------------------------------------

   function Blank (Width, Height : Positive) return DA.Mark_Map is
     [0 .. Height - 1 => [0 .. Width - 1 => DA.Light]];

   procedure Box
     (Map            : in out DA.Mark_Map;
      X0, Y0, X1, Y1 : Natural;
      To             : DA.Mark);
   --  The pixels X0 .. X1 of the rows Y0 .. Y1.

   procedure Box
     (Map            : in out DA.Mark_Map;
      X0, Y0, X1, Y1 : Natural;
      To             : DA.Mark) is
   begin
      for Y in Y0 .. Y1 loop
         for X in X0 .. X1 loop
            Map (Y, X) := To;
         end loop;
      end loop;
   end Box;

   function Sum (W : Widths) return Positive is
     (W (1) + W (2) + W (3) + W (4) + W (5));

   procedure Rings
     (Map       : in out DA.Mark_Map;
      Left, Top : Natural;
      Across    : Widths;
      Down      : Widths);
   --  A pattern with its upper left corner at the pixel (Left, Top): a
   --  dark rectangle, a light one in it and a dark one in that, with
   --  the widths Across from left to right and Down from top to
   --  bottom.

   procedure Rings
     (Map       : in out DA.Mark_Map;
      Left, Top : Natural;
      Across    : Widths;
      Down      : Widths)
   is
      A     : Widths renames Across;
      D     : Widths renames Down;
      Right : constant Natural := Left + Sum (A) - 1;
      Below : constant Natural := Top + Sum (D) - 1;
   begin
      Box (Map, Left, Top, Right, Below, DA.Dark);
      Box (Map, Left + A (1), Top + D (1),
           Right - A (5), Below - D (5), DA.Light);
      Box (Map, Left + A (1) + A (2), Top + D (1) + D (2),
           Right - A (5) - A (4), Below - D (5) - D (4), DA.Dark);
   end Rings;

   procedure Flip (Map : in out DA.Mark_Map; Pixels : Pixel_Array);
   --  Makes the dark ones of the pixels light and the light ones dark.

   procedure Flip (Map : in out DA.Mark_Map; Pixels : Pixel_Array) is
   begin
      for P of Pixels loop
         Map (P.Y, P.X) :=
           (if Map (P.Y, P.X) = DA.Light then DA.Dark else DA.Light);
      end loop;
   end Flip;

   function Drawn (Width : Positive; Rows : String) return DA.Mark_Map;
   --  The map with the rows Rows, one after the other, each of Width
   --  pixels: '#' is a dark pixel.

   function Drawn (Width : Positive; Rows : String) return DA.Mark_Map is
      Map   : DA.Mark_Map := Blank (Width, Rows'Length / Width);
      Place : Natural;
   begin
      for I in Rows'Range loop
         if Rows (I) = '#' then
            Place := I - Rows'First;
            Map (Place / Width, Place mod Width) := DA.Dark;
         end if;
      end loop;
      return Map;
   end Drawn;

   ---------------------------------------------------------------------
   --  What the finder gives
   ---------------------------------------------------------------------

   function Image (N : Natural) return String is
     (N'Image (2 .. N'Image'Last));

   function Image (W : Widths) return String is
     (Image (W (1)) & W (2)'Image & W (3)'Image & W (4)'Image
      & W (5)'Image);

   function Image (Pixels : Pixel_Array) return String is
     (if Pixels'Length = 0 then ""
      else " (" & Image (Pixels (Pixels'First).X) & ","
           & Pixels (Pixels'First).Y'Image & ")"
           & Image (Pixels (Pixels'First + 1 .. Pixels'Last)));

   procedure Check_Found
     (Name  : String;
      Map   : DA.Mark_Map;
      Want  : Found_Array;
      Table : Positive := 8);
   --  The finder, with room for Table patterns, gives the patterns
   --  Want for the map, in their order.

   procedure Check_Found
     (Name  : String;
      Map   : DA.Mark_Map;
      Want  : Found_Array;
      Table : Positive := 8)
   is
      Patterns : FN.Pattern_Array (1 .. Table);
      Count    : Natural;
   begin
      FN.Find_Patterns (Map, Patterns, Count);
      Check (Count = Want'Length, Name & ": the number of patterns");
      for I in 1 .. Natural'Min (Count, Want'Length) loop
         declare
            P : FN.Pattern renames Patterns (I);
            W : Found renames Want (Want'First + I - 1);
         begin
            Check (abs (P.Centre.X - W.X) <= Near
                   and then abs (P.Centre.Y - W.Y) <= Near,
                   Name & ": centre" & I'Image);
            Check (abs (P.Module - W.Module) <= Near,
                   Name & ": module" & I'Image);
            Check (P.Seen = W.Seen, Name & ": rows" & I'Image);
         end;
      end loop;
   end Check_Found;

   procedure Check_Pattern
     (Margin : Natural;
      Across : Widths;
      Down   : Widths;
      Flips  : Pixel_Array;
      Want   : Found_Array);
   --  A pattern with Margin light pixels on each side of it and the
   --  pixels Flips of the map changed.

   procedure Check_Pattern
     (Margin : Natural;
      Across : Widths;
      Down   : Widths;
      Flips  : Pixel_Array;
      Want   : Found_Array)
   is
      Map : DA.Mark_Map :=
        Blank (Sum (Across) + 2 * Margin, Sum (Down) + 2 * Margin);
   begin
      Rings (Map, Margin, Margin, Across, Down);
      Flip (Map, Flips);
      Check_Found
        (Image (Across) & " by " & Image (Down) & ", margin"
         & Margin'Image & Image (Flips),
         Map, Want);
   end Check_Pattern;

   ---------------------------------------------------------------------
   --  Exact patterns
   ---------------------------------------------------------------------

   procedure Test_Exact is
   begin
      Section ("QR patterns: exact patterns");

      --  The centre is the middle of the pattern and the module its
      --  width, exactly; the pattern is found in every row of its
      --  middle.
      Check_Pattern (3, Even (1), Even (1), [], [(6.5, 6.5, 1.0, 3)]);
      Check_Pattern (3, Even (2), Even (2), [], [(10.0, 10.0, 2.0, 6)]);
      Check_Pattern (3, Even (3), Even (3), [], [(13.5, 13.5, 3.0, 9)]);

      --  A map that is no larger than the pattern: the outer ring is
      --  in the first and the last row and column.
      Check_Pattern (0, Even (1), Even (1), [], [(3.5, 3.5, 1.0, 3)]);
      Check_Pattern (0, Even (2), Even (2), [], [(7.0, 7.0, 2.0, 6)]);
   end Test_Exact;

   ---------------------------------------------------------------------
   --  Rings of uneven widths
   ---------------------------------------------------------------------

   procedure Test_Uneven is
   begin
      Section ("QR patterns: rings of uneven widths");

      --  A narrow run of two pixels where the five are seven is at the
      --  limit: 2 x |7 x 2 - 7| = 7 + 7.
      Check_Pattern
        (3, [1, 2, 2, 1, 1], [1, 2, 2, 1, 1], [], [(7.0, 7.0, 1.0, 2)]);

      --  A column whose wide run is two of twelve pixels is past it:
      --  2 x |7 x 2 - 3 x 12| = 44, and 3 x 12 + 7 = 43.
      Check_Pattern (3, Even (2), [2, 3, 2, 2, 3], [], []);

      --  So is a row whose first run is one of 22 pixels:
      --  2 x |7 x 1 - 22| = 30, and 22 + 7 = 29.
      Check_Pattern (3, [1, 1, 12, 4, 4], Even (2), [], []);

      --  A middle no wider than the rings.
      Check_Pattern (3, [2, 2, 2, 1, 2], [2, 2, 2, 1, 2], [], []);

      --  A column of 19 pixels is like a row of 14 (5 x 5 < 2 x 14),
      --  and its runs are in proportion. The middle is 12 pixels high
      --  where it is 6 wide. The column is walked up and down from the
      --  row of the search, and neither way may it stay in the middle
      --  for more pixels than the row has there: the pattern is found
      --  in the two rows that have six pixels of the middle at most
      --  above them and six at most below them.
      Check_Pattern
        (3, Even (2), [1, 1, 12, 1, 4], [],
         [(10.0, 11.0, 33.0 / 14.0, 2)]);

      --  A column of 6 pixels, in proportion, is not like a row of 14:
      --  5 x 8 is not less than 2 x 14.
      Check_Pattern (3, Even (2), [1, 1, 2, 1, 1], [], []);
   end Test_Uneven;

   ---------------------------------------------------------------------
   --  Pixels changed
   ---------------------------------------------------------------------

   procedure Test_Changed is
   begin
      Section ("QR patterns: pixels changed");

      --  With pixels of the middle or of the rings changed, a pattern
      --  is found in fewer rows, by other columns and rows than those
      --  through its middle, or not at all; and the centre goes where
      --  the dark pixels of the middle that are left have theirs, if
      --  that is within a module of where the rows found it.
      --
      --  Patterns of one and of two pixels a module that fill the map.
      Check_Pattern
        (0, Even (1), Even (1), [(1, 3), (2, 4)], [(4.0, 3.5, 1.0, 2)]);
      Check_Pattern
        (0, Even (1), Even (1), [(1, 2), (5, 2)], [(3.5, 3.5, 1.0, 2)]);
      Check_Pattern
        (0, Even (1), Even (1), [(1, 4), (2, 5)], [(3.5, 3.5, 1.0, 2)]);
      Check_Pattern
        (0, Even (2), Even (2), [(8, 6), (6, 7)],
         [(101.0 / 15.0, 209.0 / 30.0, 58.0 / 35.0, 5)]);
      Check_Pattern
        (0, Even (2), Even (2), [(8, 5), (6, 6)],
         [(7.0, 8.5, 58.0 / 35.0, 5)]);
      Check_Pattern
        (0, Even (2), Even (2), [(8, 5), (5, 9)],
         [(7.0, 6.9375, 2.0, 4)]);

      --  Patterns with three light pixels around them.
      Check_Pattern
        (3, Even (1), Even (1), [(7, 5), (5, 6), (6, 7)],
         [(6.5, 6.0, 1.0, 2)]);
      Check_Pattern
        (3, Even (1), Even (1), [(5, 5), (3, 6), (4, 6), (5, 7)],
         [(6.0, 6.5, 1.0, 2)]);
      Check_Pattern
        (3, Even (1), Even (1), [(7, 7), (5, 8), (7, 9)],
         [(153.0 / 26.0, 7.5, 1.0, 3)]);
      Check_Pattern
        (3, Even (1), Even (1), [(7, 5), (9, 6), (5, 7)],
         [(6.5, 6.5, 1.0, 2)]);
      Check_Pattern
        (3, Even (2), Even (2), [(9, 8), (11, 11)],
         [(108.0 / 11.0, 241.0 / 22.0, 66.0 / 35.0, 5)]);
      Check_Pattern
        (3, Even (2), Even (2), [(10, 7), (10, 10)],
         [(10.0, 12.0, 23.0 / 14.0, 2)]);
      Check_Pattern
        (3, Even (2), Even (2), [(9, 4), (11, 9), (9, 10)],
         [(9.0, 10.0, 12.0 / 7.0, 4)]);
      Check_Pattern (3, Even (2), Even (2), [(7, 9), (9, 9)], []);
      Check_Pattern
        (3, Even (2), Even (2), [(10, 9), (11, 11), (12, 12)], []);
   end Test_Changed;

   ---------------------------------------------------------------------
   --  The diagonals
   ---------------------------------------------------------------------

   procedure Test_Diagonals is
   begin
      Section ("QR patterns: the diagonals");

      --  The five runs along a diagonal are three tenths of those of
      --  the row at least. With pixels of the middle made light on
      --  both diagonals the runs are 1, 1, 3, 1 and 1 pixels: 7, where
      --  the row has 21.
      Check_Pattern
        (3, Even (3), Even (3),
         [(11, 11), (15, 15), (11, 15), (15, 11),
          (9, 9), (17, 17), (9, 17), (17, 9)],
         [(13.5, 13.5, 3.0, 5)]);

      --  Runs of 1, 1, 2, 1 and 1 on one diagonal: 6 of 21 are too
      --  few.
      Check_Pattern
        (3, Even (3), Even (3), [(12, 12), (10, 10), (15, 15), (17, 17)],
         []);

      --  The same runs with a middle of eight pixels: 6 of 20 are just
      --  enough.
      Check_Pattern
        (3, [3, 3, 8, 3, 3], [3, 3, 8, 3, 3],
         [(11, 11), (9, 9), (14, 14), (16, 16)],
         [(13.0, 13.0, 20.0 / 7.0, 6)]);
   end Test_Diagonals;

   ---------------------------------------------------------------------
   --  A full table
   ---------------------------------------------------------------------

   procedure Check_Table
     (Top   : Natural;
      Table : Positive;
      Want  : Found_Array);
   --  A pattern of two pixels a module whose left ring is whole in one
   --  row of the middle only, the row 9, so that it is found once: its
   --  centre is (10, 10). Another, of one pixel a module, has its
   --  upper edge in the row Top, to the right of the first and below
   --  it.

   procedure Check_Table
     (Top   : Natural;
      Table : Positive;
      Want  : Found_Array)
   is
      Map : DA.Mark_Map := Blank (32, 26);
   begin
      Rings (Map, 3, 3, Even (2), Even (2));
      Box (Map, 3, 7, 4, 8, DA.Light);
      Box (Map, 3, 10, 4, 12, DA.Light);
      Rings (Map, 22, Top, Even (1), Even (1));
      Check_Found
        ("a table of" & Table'Image & ", second pattern from the row"
         & Top'Image,
         Map, Want, Table);
   end Check_Table;

   procedure Test_Table is
   begin
      Section ("QR patterns: a full table");

      --  A pattern found in one row holds its place in a full table as
      --  far as three of its modules and a pixel below its centre:
      --  here to the row 10 + 3 x 2 + 1 = 17. The second pattern has
      --  the rows of its middle from Top + 2 on. In a table of one
      --  pattern it is found in the rows after the row 17 only, and a
      --  pattern found in one row is not given.
      Check_Table (14, 1, []);
      Check_Table (15, 1, [(25.5, 18.5, 1.0, 2)]);
      Check_Table (16, 1, [(25.5, 19.5, 1.0, 3)]);

      --  With room for both, the second is found in all its rows.
      Check_Table (14, 2, [(25.5, 17.5, 1.0, 3)]);
   end Test_Table;

   procedure Test_Again is
   begin
      Section ("QR patterns: found again far below");

      --  The figure at the right is a pattern in the row 9: runs of
      --  1, 1, 3, 1 and 1 pixels in the row and in the column of the
      --  pixel (20, 9), with the centre (21.5, 10.5). In the row 15 it
      --  has eight dark pixels with one more on each side, and the
      --  column of the pixel (21, 15) is a bar of nine pixels up to
      --  the row 7 with dark pixels above it and below it: a pattern
      --  again, with the centre (21.5, 11.5), a module from the first
      --  one. The row 15 is more than three modules and a pixel below
      --  the first centre (10.5 + 3 + 1), and the pattern at the left
      --  is put into the table in that row, before the figure is come
      --  to. The table is not full, so nothing is taken out of it: the
      --  two are one pattern, found in two rows.
      Check_Found
        ("a figure found in the rows 9 and 15",
         Drawn
           (30,
            ".............................." &
            ".............................." &
            ".............................." &
            ".............................." &
            ".....................#........" &
            ".....................#........" &
            ".............................." &
            ".................#######.#...." &
            ".................#...#.#......" &
            ".................#.###.#......" &
            "..................#.###.#....." &
            ".................##.###.#....." &
            "..................#..#..#....." &
            ".#######..........#######....." &
            ".#.....#.............#........" &
            ".#.###.#.......#.########.#..." &
            ".#.###.#......................" &
            ".#.###.#.............#........" &
            ".#.....#.............#........" &
            ".#######......................" &
            ".............................." &
            ".............................." &
            ".............................."),
         [(21.5, 11.0, 37.0 / 28.0, 2), (4.5, 16.5, 1.0, 3)],
         Table => 3);
   end Test_Again;

   ---------------------------------------------------------------------
   --  The edges of the map
   ---------------------------------------------------------------------

   procedure Test_Edges is
      Map : DA.Mark_Map := Blank (10, 8);
   begin
      Section ("QR patterns: at the edges of the map");

      --  Patterns in the first rows and columns of a map, with pixels
      --  changed: what is followed from the middle comes to the edge
      --  of the map.
      Rings (Map, 1, 0, Even (1), Even (1));
      Flip (Map, [(6, 0), (5, 1), (6, 2)]);
      Check_Found
        ("a pattern from the first row", Map, [(4.5, 3.5, 1.0, 2)]);
      Check_Pattern
        (0, Even (1), Even (1), [(5, 4), (4, 5), (2, 6)],
         [(4.25, 4.5, 1.0, 2)]);
   end Test_Edges;

   ---------------------------------------------------------------------
   --  Maps that are not square
   ---------------------------------------------------------------------

   procedure Test_Oblong is
      High : DA.Mark_Map := Blank (9, 30);
      Wide : DA.Mark_Map := Blank (30, 9);
   begin
      Section ("QR patterns: maps that are not square");

      --  A pattern whose rows are further down than the map is wide,
      --  and one whose columns are further to the right than the map
      --  is high.
      Rings (High, 1, 21, Even (1), Even (1));
      Check_Found
        ("a pattern low in a high map", High, [(4.5, 24.5, 1.0, 3)]);
      Rings (Wide, 21, 1, Even (1), Even (1));
      Check_Found
        ("a pattern at the right of a wide map", Wide,
         [(24.5, 4.5, 1.0, 3)]);
   end Test_Oblong;

   ---------------------------------------------------------------------
   --  A row beside the middle
   ---------------------------------------------------------------------

   procedure Test_Beside is
   begin
      Section ("QR patterns: a row beside the middle");

      --  The row below the middle has a dark pixel in the light ring,
      --  so that five of its runs, of which the first is a light one,
      --  are 3, 2, 8, 1 and 1 pixels: in proportion, within what is
      --  allowed, and the column through the middle of the third is
      --  the one of the pattern. Runs that begin with a light one are
      --  not looked at: the pattern is found in the six rows of its
      --  middle and in no other.
      Check_Pattern
        (3, Even (2), Even (2), [(13, 13)], [(10.0, 10.0, 2.0, 6)]);
   end Test_Beside;

   ---------------------------------------------------------------------
   --  Dark pixels that go on from the middle
   ---------------------------------------------------------------------

   procedure Test_Tail is
      Tail : constant Pixel_Array :=
        [(10, 14), (10, 15), (9, 16), (12, 16), (9, 17), (12, 17),
         (10, 18), (10, 19)];
   begin
      Section ("QR patterns: dark pixels that go on from the middle");

      --  The middle of a pattern of two pixels a module, in the rows
      --  8 to 13, goes on below as a line of dark pixels through the
      --  rings. The dark rows are followed from the row of the centre,
      --  the row 11, for ten rows at most (two rows and four modules).
      --  A line to the row 19 ends within them, and the centre is the
      --  one of all the dark pixels that were followed. With a line to
      --  the row 20 the tenth row is still dark: the pixels are not
      --  followed to their end, and the centre stays where the rows
      --  and the columns have it.
      Check_Pattern
        (4, Even (2), Even (2), Tail,
         [(241.0 / 22.0, 133.0 / 11.0, 2.0, 6)]);
      Check_Pattern
        (4, Even (2), Even (2), Tail & Pixel'(10, 20),
         [(11.0, 11.0, 2.0, 6)]);
   end Test_Tail;

   ---------------------------------------------------------------------
   --  A symbol in perspective
   ---------------------------------------------------------------------

   procedure Test_Drawn is
      package QR renames AMV.Kernels.Code_Reader.QR_Code;
      package Enc renames AMV_Test_QR_Code;
      package KI renames AMV.Kernels.Images;

      type Map_Access is access DA.Mark_Map;
      procedure Free is
        new Ada.Unchecked_Deallocation (DA.Mark_Map, Map_Access);

      Symbol : Enc.Module_Matrix :=
        Enc.Symbol (Enc.Segment (Enc.Bytes, "search", 3), 3, QR.M, 5);
      Image  : Ks_Image_8_Grey := AMV_Test_Images.Blank (170, 170, 255);
      Map    : Map_Access;
   begin
      Section ("QR patterns: a symbol in perspective");
      --  A symbol of version 3 with two modules changed, drawn in
      --  perspective, its dark pixels as the tool finds them; found by
      --  a search. Besides its three finder patterns, two figures of
      --  its modules are found in two rows each. In the rows of the
      --  one at (53.5, 56.75) the widths of a module differ by more
      --  than a pixel and less than a module: the two are one pattern,
      --  found in two rows, and it is kept.
      Symbol (11, 25) := not Symbol (11, 25);
      Symbol (15, 3) := not Symbol (15, 3);
      AMV_Test_Data_Matrix.Draw
        (Image, Symbol,
         (Upper_Left  => (21.5, 34.5), Upper_Right => (108.0, 17.5),
          Lower_Right => (100.0, 111.0), Lower_Left => (18.0, 111.0)));
      declare
         Handle : constant access constant KI.Ks_Image_8_Grey_Data :=
           AMV.Images.Kernel_Images.Kernel_Handle (Image);
         Lows   : KI.Grey_8_Matrix (0 .. 169 / DA.Block, 0 .. 169 / DA.Block)
           := [others => [others => 0]];
         Highs  : KI.Grey_8_Matrix (0 .. 169 / DA.Block, 0 .. 169 / DA.Block)
           := [others => [others => 0]];
      begin
         Map := new DA.Mark_Map'(0 .. 169 => [0 .. 169 => DA.Light]);
         DA.Binarise (Handle.Pixels.all, 0, 0, 12, Lows, Highs, Map.all);
      end;
      Check_Found
        ("version 3, two modules changed",
         Map.all,
         [(95.0157894736842, 31.8578947368421, 29.0 / 9.0, 9),
          (30.1129032258065, 43.0967741935484, 37.0 / 14.0, 8),
          (53.5, 56.75, 29.0 / 7.0, 2),
          (33.4148936170213, 73.8829787234042, 17.0 / 7.0, 2),
          (27.5, 102.5, 2.5, 7)]);
      Free (Map);
   end Test_Drawn;

   procedure Run_All is
   begin
      Test_Exact;
      Test_Uneven;
      Test_Changed;
      Test_Diagonals;
      Test_Table;
      Test_Again;
      Test_Edges;
      Test_Oblong;
      Test_Beside;
      Test_Tail;
      Test_Drawn;
   end Run_All;

   procedure Main is new AMV_Test_Support.Standalone (Run_All);

begin
   Main;
end Test_Code_Reader_QR_Patterns;
