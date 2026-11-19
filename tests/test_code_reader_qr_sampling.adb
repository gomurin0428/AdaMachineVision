--  The sampling of a symbol by the QR Code finder kernel
--  (AMV.Kernels.Code_Reader.QR_Code.Finder.Sample), on maps of dark
--  pixels on which the modules of a symbol are painted as squares of
--  pixels, with some of them changed, and with placings whose values
--  are given by hand.
--
--  The symbols that the other tests of the finder paint are whole, so
--  their finder patterns, timing patterns and alignment patterns are
--  always where they should be. The maps here are made for the limits:
--  how many modules of the finder patterns may be amiss, how far the
--  changes of colour along the timing patterns may be from their
--  number, where the alignment pattern is looked for and how it is
--  taken, and which of the two mappings that a placing gives is used.
--  Some maps were found by a search for maps on which a change of one
--  operator or of one number in the body of the finder changes the
--  sampling.
--
--  What is expected of a map is what the finder gives for it. Where the
--  reason is plain it is in a comment. So these checks do not say that
--  every result is the right one; they say that none of them changes
--  unseen.

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

procedure Test_Code_Reader_QR_Sampling is

   package DA renames AMV.Kernels.Code_Reader.Dark_Areas;
   package QR renames AMV.Kernels.Code_Reader.QR_Code;
   package FN renames AMV.Kernels.Code_Reader.QR_Code.Finder;
   package Enc renames AMV_Test_QR_Code;
   package KI renames AMV.Kernels.Images;
   package Paint renames AMV_Test_Data_Matrix;
   package TI renames AMV_Test_Images;

   subtype Real is Long_Float;

   Near : constant := 1.0E-6;

   type Point is record
      X, Y : Real;
   end record;

   type Module is record
      Row, Column : Natural;
   end record;

   type Module_List is array (Positive range <>) of Module;

   No_Modules : constant Module_List (1 .. 0) := [others => (0, 0)];

   type Move is record
      Rows, Columns : Integer;
   end record;

   type Matrix_Access is access Enc.Module_Matrix;

   procedure Free is
     new Ada.Unchecked_Deallocation (Enc.Module_Matrix, Matrix_Access);

   type Map_Access is access DA.Mark_Map;

   procedure Free is
     new Ada.Unchecked_Deallocation (DA.Mark_Map, Map_Access);

   ---------------------------------------------------------------------
   --  Symbols and maps
   ---------------------------------------------------------------------

   function Symbol_Of
     (Version : QR.Version_Number;
      Mask    : QR.Mask_Pattern) return Matrix_Access
   is (new Enc.Module_Matrix'
         (Enc.Symbol
            (Enc.Segment (Enc.Bytes, "search", Version), Version, QR.M,
             Mask)));
   --  A symbol of the version with the message "search", level M.

   procedure Change
     (Symbol  : in out Enc.Module_Matrix;
      Modules : Module_List;
      Shift   : Move;
      Erase   : Boolean);
   --  Makes the dark ones of the modules light and the light ones dark;
   --  then, if Shift is not (0, 0), paints the alignment pattern of
   --  the lower right corner that many rows and columns further, the
   --  modules where it was light; or, if Erase, makes those modules
   --  light and paints it nowhere.

   procedure Change
     (Symbol  : in out Enc.Module_Matrix;
      Modules : Module_List;
      Shift   : Move;
      Erase   : Boolean)
   is
      Last : constant Natural := Symbol'Last (1);
      Home : constant Natural := Last - 6;
   begin
      for M of Modules loop
         Symbol (M.Row, M.Column) := not Symbol (M.Row, M.Column);
      end loop;
      if Erase or else Shift /= (0, 0) then
         for R in Home - 2 .. Home + 2 loop
            for C in Home - 2 .. Home + 2 loop
               Symbol (R, C) := False;
            end loop;
         end loop;
      end if;
      if not Erase and then Shift /= (0, 0) then
         for R in -2 .. 2 loop
            for C in -2 .. 2 loop
               Symbol (Home + Shift.Rows + R, Home + Shift.Columns + C) :=
                 Integer'Max (abs R, abs C) /= 1;
            end loop;
         end loop;
      end if;
   end Change;

   function Painted
     (Symbol : Enc.Module_Matrix;
      Pixels : Positive) return Map_Access;
   --  The symbol with each module a square of Pixels by Pixels pixels,
   --  and four modules of light pixels around it.

   function Painted
     (Symbol : Enc.Module_Matrix;
      Pixels : Positive) return Map_Access
   is
      Margin : constant Natural := 4 * Pixels;
      Side   : constant Positive :=
        Symbol'Length (1) * Pixels + 2 * Margin;
      Map    : constant Map_Access :=
        new DA.Mark_Map'(0 .. Side - 1 => [0 .. Side - 1 => DA.Light]);
   begin
      for R in Symbol'Range (1) loop
         for C in Symbol'Range (2) loop
            if Symbol (R, C) then
               for Y in 0 .. Pixels - 1 loop
                  for X in 0 .. Pixels - 1 loop
                     Map (Margin + R * Pixels + Y, Margin + C * Pixels + X)
                       := DA.Dark;
                  end loop;
               end loop;
            end if;
         end loop;
      end loop;
      return Map;
   end Painted;

   function Map_Of (Image : Ks_Image_8_Grey) return Map_Access;
   --  The dark pixels of the image, as the tool finds them with its
   --  contrast threshold as it is at first.

   function Map_Of (Image : Ks_Image_8_Grey) return Map_Access is
      Handle : constant access constant KI.Ks_Image_8_Grey_Data :=
        AMV.Images.Kernel_Images.Kernel_Handle (Image);
      H      : constant Positive := Height (Image);
      W      : constant Positive := Width (Image);
      Map    : constant Map_Access :=
        new DA.Mark_Map'(0 .. H - 1 => [0 .. W - 1 => DA.Light]);
      Lows   : KI.Grey_8_Matrix
        (0 .. (H - 1) / DA.Block, 0 .. (W - 1) / DA.Block) :=
          [others => [others => 0]];
      Highs  : KI.Grey_8_Matrix
        (0 .. (H - 1) / DA.Block, 0 .. (W - 1) / DA.Block) :=
          [others => [others => 0]];
   begin
      DA.Binarise (Handle.Pixels.all, 0, 0, 12, Lows, Highs, Map.all);
      return Map;
   end Map_Of;

   function Placing
     (Size    : Positive;
      Pixels  : Positive;
      Version : QR.Version_Number;
      Across  : Real;
      Down    : Real) return FN.Placement;
   --  The middles of the three finder patterns of a symbol of Size
   --  modules a side painted as Painted paints it, with the version
   --  and the changes of width given.

   function Placing
     (Size    : Positive;
      Pixels  : Positive;
      Version : QR.Version_Number;
      Across  : Real;
      Down    : Real) return FN.Placement
   is
      Near_Side : constant Real := Real (4 * Pixels) + 3.5 * Real (Pixels);
      Far_Side  : constant Real :=
        Real (4 * Pixels) + (Real (Size) - 3.5) * Real (Pixels);
   begin
      return (Upper_Left  => (Near_Side, Near_Side),
              Upper_Right => (Far_Side, Near_Side),
              Lower_Left  => (Near_Side, Far_Side),
              Version     => Version,
              Across      => Across,
              Down        => Down);
   end Placing;

   ---------------------------------------------------------------------
   --  What the finder gives
   ---------------------------------------------------------------------

   type Outcome is record
      OK          : Boolean;
      Wrong       : Natural := 0;
      Upper_Left  : Point := (0.0, 0.0);
      Lower_Right : Point := (0.0, 0.0);
      Centre      : Point := (0.0, 0.0);
   end record;
   --  OK, and if OK: the modules of the grid that are not those that
   --  were painted, two corners of the symbol and its middle.

   function Square (Size, Pixels : Positive) return Outcome is
     (OK          => True,
      Wrong       => 0,
      Upper_Left  => (Real (4 * Pixels), Real (4 * Pixels)),
      Lower_Right =>
        (Real (4 * Pixels + Size * Pixels),
         Real (4 * Pixels + Size * Pixels)),
      Centre      =>
        (Real (4 * Pixels) + Real (Size * Pixels) / 2.0,
         Real (4 * Pixels) + Real (Size * Pixels) / 2.0));
   --  The symbol as it was painted, every module read.

   Not_OK : constant Outcome := (OK => False, others => <>);

   function Is_At (C : FN.Corner; P : Point) return Boolean is
     (abs (C.X - P.X) <= Near and then abs (C.Y - P.Y) <= Near);

   procedure Check_Sample
     (Name    : String;
      Version : QR.Version_Number;
      Want    : Outcome;
      Modules : Module_List := No_Modules;
      Shift   : Move := (0, 0);
      Erase   : Boolean := False;
      Pixels  : Positive := 3;
      Mask    : QR.Mask_Pattern := 0;
      Across  : Real := 0.0;
      Down    : Real := 0.0;
      Asked   : Natural := 0;
      Again   : Boolean := False);
   --  Sample on the symbol of the version, changed as Change changes
   --  it and painted as Painted paints it, with the placing of its
   --  finder patterns, gives Want. Asked: the version asked for (if
   --  not 0; else the version of the symbol).

   procedure Check_Read
     (Name   : String;
      Map    : DA.Mark_Map;
      Symbol : Enc.Module_Matrix;
      Placed : FN.Placement;
      Read   : QR.Version_Number;
      Again  : Boolean;
      Want   : Outcome);
   --  Sample on the map with the placing gives Want; its modules are
   --  compared with those of the symbol.

   procedure Check_Read
     (Name   : String;
      Map    : DA.Mark_Map;
      Symbol : Enc.Module_Matrix;
      Placed : FN.Placement;
      Read   : QR.Version_Number;
      Again  : Boolean;
      Want   : Outcome)
   is
      Size   : constant Positive := Symbol'Length (1);
      Grid   : QR.Module_Grid;
      Shape  : FN.Outline;
      Centre : FN.Corner;
      OK     : Boolean;
      Wrong  : Natural := 0;
   begin
      FN.Sample (Map, Placed, Read, Again, Grid, Shape, Centre, OK);
      Check (OK = Want.OK, Name & ": OK");
      if OK and then Want.OK then
         for R in 0 .. Natural'Min (QR.Side (Read), Size) - 1 loop
            for C in 0 .. Natural'Min (QR.Side (Read), Size) - 1 loop
               if Grid (QR.Module_Index (R), QR.Module_Index (C))
                 /= Symbol (R, C)
               then
                  Wrong := Wrong + 1;
               end if;
            end loop;
         end loop;
         Check (Wrong = Want.Wrong,
                Name & ": modules not read as painted:" & Wrong'Image);
         Check (Is_At (Shape.Upper_Left, Want.Upper_Left),
                Name & ": the upper left corner (got"
                & Shape.Upper_Left.X'Image & Shape.Upper_Left.Y'Image
                & ")");
         Check (Is_At (Shape.Lower_Right, Want.Lower_Right),
                Name & ": the lower right corner (got"
                & Shape.Lower_Right.X'Image & Shape.Lower_Right.Y'Image
                & ")");
         Check (Is_At (Centre, Want.Centre),
                Name & ": the middle (got" & Centre.X'Image
                & Centre.Y'Image & ")");
      end if;
   end Check_Read;

   procedure Check_Sample
     (Name    : String;
      Version : QR.Version_Number;
      Want    : Outcome;
      Modules : Module_List := No_Modules;
      Shift   : Move := (0, 0);
      Erase   : Boolean := False;
      Pixels  : Positive := 3;
      Mask    : QR.Mask_Pattern := 0;
      Across  : Real := 0.0;
      Down    : Real := 0.0;
      Asked   : Natural := 0;
      Again   : Boolean := False)
   is
      Symbol : Matrix_Access := Symbol_Of (Version, Mask);
      Size   : constant Positive := Symbol'Length (1);
      Map    : Map_Access;
   begin
      Change (Symbol.all, Modules, Shift, Erase);
      Map := Painted (Symbol.all, Pixels);
      Check_Read
        (Name, Map.all, Symbol.all,
         Placing (Size, Pixels, Version, Across, Down),
         (if Asked = 0 then Version else Asked), Again, Want);
      Free (Map);
      Free (Symbol);
   end Check_Sample;

   procedure Check_Drawn
     (Name    : String;
      Version : QR.Version_Number;
      Want    : Outcome;
      Where   : Paint.Corners;
      Side    : Positive;
      Modules : Module_List := No_Modules;
      Shift   : Move := (0, 0);
      Erase   : Boolean := False;
      Mask    : QR.Mask_Pattern := 0;
      Widths  : Boolean := False;
      Across  : Real := 0.0;
      Down    : Real := 0.0;
      Asked   : Natural := 0;
      Again   : Boolean := False);
   --  As Check_Sample, with the symbol drawn in perspective between the
   --  corners Where on an image of Side by Side pixels, its dark pixels
   --  as the tool finds them, and the placing that the finder gives for
   --  its finder patterns (with the first of the three as the corner
   --  that gives one); with the changes of width Across and Down in
   --  place of those of the placing if Widths.

   procedure Check_Drawn
     (Name    : String;
      Version : QR.Version_Number;
      Want    : Outcome;
      Where   : Paint.Corners;
      Side    : Positive;
      Modules : Module_List := No_Modules;
      Shift   : Move := (0, 0);
      Erase   : Boolean := False;
      Mask    : QR.Mask_Pattern := 0;
      Widths  : Boolean := False;
      Across  : Real := 0.0;
      Down    : Real := 0.0;
      Asked   : Natural := 0;
      Again   : Boolean := False)
   is
      Symbol   : Matrix_Access := Symbol_Of (Version, Mask);
      Image    : Ks_Image_8_Grey := TI.Blank (Side, Side, 255);
      Map      : Map_Access;
      Patterns : FN.Pattern_Array (1 .. 8);
      Count    : Natural;
      Placed   : FN.Placement;
      Found    : Boolean := False;
   begin
      Change (Symbol.all, Modules, Shift, Erase);
      Paint.Draw (Image, Symbol.all, Where);
      Map := Map_Of (Image);
      FN.Find_Patterns (Map.all, Patterns, Count);
      if Count >= 3 then
         for Turn in 0 .. 2 loop
            FN.Place
              (Map.all, Patterns (1 + Turn), Patterns (1 + (Turn + 1) mod 3),
               Patterns (1 + (Turn + 2) mod 3), Placed, Found);
            exit when Found;
         end loop;
      end if;
      Check (Found, Name & ": the finder patterns placed");
      if Found then
         if Widths then
            Placed.Across := Across;
            Placed.Down := Down;
         end if;
         Check_Read
           (Name, Map.all, Symbol.all, Placed,
            (if Asked = 0 then Version else Asked), Again, Want);
      end if;
      Free (Map);
      Free (Symbol);
   end Check_Drawn;

   ---------------------------------------------------------------------
   --  The finder patterns
   ---------------------------------------------------------------------

   procedure Test_Finder_Patterns is
      --  The modules of a finder pattern that are looked at are the
      --  seven across its middle and the seven down it. Those that are
      --  changed here are not its middle, which is looked at twice, nor
      --  on a timing pattern.
      UL_1 : constant Module_List := [(3, 0), (3, 1)];
      UL_2 : constant Module_List := [(0, 3), (1, 3), (3, 5)];
      UR_1 : constant Module_List := [(3, 14), (3, 15)];
      UR_2 : constant Module_List := [(0, 17), (1, 17), (3, 19)];
      LL_1 : constant Module_List := [(17, 0), (17, 1)];
      LL_2 : constant Module_List := [(14, 3), (15, 3), (17, 5)];
   begin
      Section ("QR sampling: modules of the finder patterns amiss");
      --  Four of the 42 modules may be amiss, not five.
      Check_Sample
        ("two amiss in the upper left pattern and two in the upper "
         & "right one",
         1, Square (21, 3), UL_1 & UR_1);
      Check_Sample
        ("five amiss in the upper left pattern", 1, Not_OK, UL_1 & UL_2);
      Check_Sample
        ("five amiss in the upper right pattern", 1, Not_OK, UR_1 & UR_2);
      Check_Sample
        ("five amiss in the lower left pattern", 1, Not_OK, LL_1 & LL_2);
      Check_Sample
        ("five amiss in all three", 1, Not_OK, UL_1 & UR_1 & LL_2 (1 .. 1));
   end Test_Finder_Patterns;

   ---------------------------------------------------------------------
   --  The timing patterns
   ---------------------------------------------------------------------

   procedure Test_Timing_Patterns is
   begin
      Section ("QR sampling: the timing patterns");
      --  Version 1: from the finder pattern of the corner to the next,
      --  along the seventh row and the seventh column, dark and light
      --  change 8 times, and may change 2 times more or less. A module
      --  of a timing pattern that is changed joins its two neighbours:
      --  2 changes less. The first module of the finder pattern at the
      --  end, changed, is not a change: 1 less.
      Check_Sample
        ("a module changed along each", 1, Square (21, 3),
         [(6, 10), (10, 6)]);
      Check_Sample
        ("two modules changed along one", 1, Square (21, 3),
         [(6, 9), (6, 11)]);
      Check_Sample
        ("a module changed along each, and the end of each", 1, Not_OK,
         [(6, 10), (6, 14), (10, 6), (14, 6)]);
      --  Version 2: 12 changes, and 3 more or less.
      Check_Sample
        ("three changes less along each", 2, Square (25, 3),
         [(6, 10), (6, 18), (10, 6), (18, 6)]);
      --  Version 3: 16 changes, and 4 more or less. The lines end in
      --  the finder patterns, whose modules beyond them are not looked
      --  at.
      Check_Sample
        ("four changes less along each", 3, Square (29, 3),
         [(6, 10), (6, 14), (10, 6), (14, 6)]);
      Check_Sample
        ("five changes less along each", 3, Not_OK,
         [(6, 10), (6, 14), (6, 22), (10, 6), (14, 6), (22, 6)]);
   end Test_Timing_Patterns;

   ---------------------------------------------------------------------
   --  The alignment pattern
   ---------------------------------------------------------------------

   procedure Test_Alignment is
   begin
      Section ("QR sampling: the alignment pattern");
      --  Version 3: the alignment pattern is looked for as far as 8
      --  modules from where it should be, up and to the left. There it
      --  is on the line from the upper right finder pattern to the lower
      --  left one: no perspective can be taken from it, and the mapping
      --  is the one of the finder patterns.
      Check_Sample
        ("an alignment pattern between the upper right and the lower "
         & "left finder pattern",
         3, Square (29, 3), Shift => (-8, -8));
      --  Version 5: nine modules up it is not looked for, and the
      --  mapping is the one of the finder patterns.
      Check_Sample
        ("an alignment pattern nine modules up", 5, Square (37, 3),
         Shift => (-9, 0));
      --  Version 3: an alignment pattern found eight modules up and seven
      --  to the left of where it should be, or seven and seven, tilts
      --  the mapping so far that the lower right corner of the symbol
      --  is not on the plane of the image.
      Check_Sample
        ("an alignment pattern eight modules up and seven to the left",
         3, Not_OK, Shift => (-8, -7));
      Check_Sample
        ("an alignment pattern seven modules up and seven to the left",
         3, Not_OK, Shift => (-7, -7));
   end Test_Alignment;

   ---------------------------------------------------------------------
   --  The two mappings
   ---------------------------------------------------------------------

   procedure Test_Mappings is
   begin
      Section ("QR sampling: which mapping is tried first");
      --  Version 1, painted upright: the placing says that the widths
      --  change across the symbol by 0.06 and not down it. From a
      --  change of 0.05 on, across or down, the symbol is taken as
      --  leaning, and the mapping with the changes is tried first. Its
      --  finder patterns and timing patterns are within their limits, so
      --  it is taken, with corners that are not those of the upright
      --  symbol and 31 modules read wrongly.
      Check_Sample
        ("widths changing by 0.06 across and 0 down",
         1, (True, 31, (11.200507614, 11.840101523),
         (74.26744186, 71.337209302), (44.111650485, 42.888349515)),
         Across => 0.06);
   end Test_Mappings;

   ---------------------------------------------------------------------
   --  Maps found by the search
   ---------------------------------------------------------------------

   procedure Test_Found is
   begin
      Section ("QR sampling: symbols found by the search");
      --  Symbols of the versions 1 to 8 painted with modules of two or
      --  three pixels, with modules changed in their finder patterns,
      --  timing patterns and alignment pattern or anywhere, with the
      --  alignment pattern moved or taken away, and placings with other
      --  changes of width or another version. What each gives is what
      --  the finder gives, modules read wrongly included.
      Check_Sample
        ("version 5: 7 modules changed",
         5, (True, 0, (8.0, 8.0), (82.0, 82.0), (45.0, 45.0)),
         Modules => [(21, 6), (6, 11), (26, 6), (15, 6), (32, 32), (31, 31),
         (30, 28)], Pixels => 2, Mask => 4);
      Check_Sample
        ("version 6: the alignment pattern moved by (-2, -1)",
         6, (True, 406, (10.963047744, 11.347612819),
         (128.978873239, 125.429577465), (74.36440678, 72.63559322)),
         Shift => (-2, -1), Mask => 4);
      Check_Sample
        ("version 5: 3 modules changed, read as version 4, the other mapping "
         & "first",
         5, (True, 520, (10.384615385, 10.384615385),
         (124.615384615, 124.615384615), (67.5, 67.5)), Modules => [(32, 28),
         (31, 28), (32, 29)], Asked => 4, Again => True);
      Check_Sample
        ("version 5: 8 modules changed, widths changing by 0.03 and -0.0625",
         5, (True, 0, (7.970857495, 7.983772621), (81.845681004, 81.722860851),
         (45.027585871, 44.972414129)), Modules => [(23, 6), (27, 6), (6, 17),
         (22, 6), (28, 30), (32, 32), (28, 30), (28, 32)], Pixels => 2,
         Mask => 3, Across => 0.03, Down => -0.0625);
      Check_Sample
        ("version 5: no alignment pattern, widths changing by 0.0625 and "
         & "0.0625, read as version 4, the other mapping first",
         5, (True, 509, (6.923076923, 6.923076923),
         (83.076923077, 83.076923077), (45.0, 45.0)), Erase => True,
         Pixels => 2, Mask => 7, Across => 0.0625, Down => 0.0625, Asked => 4,
         Again => True);
      Check_Drawn
        ("in perspective, version 5: 2 modules changed, no alignment pattern, "
         & "the other mapping first",
         5, Not_OK, ((19.0, 18.0), (127.0, 13.0), (130.0, 133.0),
         (34.0, 124.0)), 163, Modules => [(25, 6), (6, 16)], Erase => True,
         Mask => 5, Again => True);
      Check_Sample
        ("version 6: no alignment pattern, widths changing by 0.05 and 0, "
         & "read as version 7",
         6, (True, 832, (9.034060907, 6.845497713),
         (71.387106011, 92.07232303), (43.730253353, 54.269746647)),
         Erase => True, Pixels => 2, Mask => 5, Across => 0.05, Asked => 7);
      Check_Sample
        ("version 5: 3 modules changed, no alignment pattern, widths changing "
         & "by -0.05 and 0",
         5, (True, 207, (12.582850041, 12.06089478),
         (123.620917917, 128.943071492), (66.346153846, 68.653846154)),
         Modules => [(22, 6), (15, 6), (6, 9)], Erase => True, Mask => 3,
         Across => -0.05);
      Check_Sample
        ("version 5: 9 modules changed, widths changing by -0.05 and 0.0625",
         5, (True, 8, (12.175205716, 11.872242493),
         (121.771627279, 124.68458141), (66.849322929, 68.150677071)),
         Modules => [(2, 3), (0, 2), (3, 32), (35, 6), (6, 31), (32, 0),
         (32, 29), (28, 32), (30, 29)], Mask => 6, Across => -0.05,
         Down => 0.0625);
      Check_Sample
        ("version 2: 15 modules changed, widths changing by 0.0625 and "
         & "-0.0625",
         2, (True, 20, (11.633355089, 12.070712315),
         (87.422468765, 84.809490146), (50.05450237, 48.94549763)),
         Modules => [(20, 9), (15, 4), (1, 11), (20, 20), (14, 11), (16, 3),
         (24, 15), (8, 13), (12, 24), (7, 10), (6, 3), (20, 10), (5, 20),
         (23, 12), (13, 11)], Mask => 7, Across => 0.0625, Down => -0.0625);
      Check_Sample
        ("version 7: widths changing by 0.03 and 0.03, the other mapping "
         & "first",
         7, (True, 0, (11.987471359, 11.987471359),
         (146.851799782, 146.851799782), (79.5, 79.5)), Mask => 5,
         Across => 0.03, Down => 0.03, Again => True);
      Check_Sample
        ("version 7: widths changing by 0.05 and 0.5",
         7, (True, 0, (8.0, 8.0), (98.0, 98.0), (53.0, 53.0)), Pixels => 2,
         Mask => 7, Across => 0.05, Down => 0.5);
      Check_Drawn
        ("in perspective, version 4: 1 module changed, widths changing by "
         & "0.05 and -0.05, the other mapping first",
         4, (True, 0, (18.966091172, 22.180513401),
         (138.019347267, 114.959444983), (70.975335138, 62.711635739)),
         ((18.5, 21.5), (108.5, 24.5), (137.5, 114.5), (22.5, 109.5)), 148,
         Modules => [1 => (30, 5)], Widths => True, Across => 0.05,
         Down => -0.05, Again => True);
      Check_Sample
        ("version 6: the alignment pattern moved by (2, 0), widths changing "
         & "by 0.03 and 0.5",
         6, (True, 499, (8.51547492, 8.097118463),
         (91.140350877, 96.052631579), (47.9375, 50.0625)), Shift => (2, 0),
         Pixels => 2, Mask => 4, Across => 0.03, Down => 0.5);
      Check_Sample
        ("version 5: 4 modules changed, widths changing by 0.25 and -0.0625",
         5, (True, 0, (8.0, 8.0), (82.0, 82.0), (45.0, 45.0)),
         Modules => [(6, 22), (6, 8), (26, 6), (6, 24)], Pixels => 2,
         Mask => 6, Across => 0.25, Down => -0.0625);
      Check_Sample
        ("version 4: the alignment pattern moved by (0, 1)",
         4, (True, 138, (8.09352518, 8.381294964),
         (77.447629548, 74.845644983), (41.553191489, 40.446808511)),
         Shift => (0, 1), Pixels => 2, Mask => 5);
      Check_Sample
        ("version 5: no alignment pattern, widths changing by -0.05 and 0.25",
         5, (True, 0, (12.0, 12.0), (123.0, 123.0), (67.5, 67.5)),
         Erase => True, Mask => 3, Across => -0.05, Down => 0.25);
      Check_Sample
        ("version 5: the alignment pattern moved by (1, -2), widths changing "
         & "by 0.25 and 0.05, the other mapping first",
         5, Not_OK, Shift => (1, -2), Pixels => 2, Mask => 6, Across => 0.25,
         Down => 0.05, Again => True);
      Check_Sample
        ("version 6: 3 modules changed, widths changing by 0 and 0.05, the "
         & "other mapping first",
         6, (True, 0, (12.0, 12.0), (135.0, 135.0), (73.5, 73.5)),
         Modules => [(32, 34), (33, 35), (32, 33)], Mask => 6, Down => 0.05,
         Again => True);
      Check_Drawn
        ("in perspective, version 1: 4 modules changed, the other mapping "
         & "first",
         1, (True, 10, (9.982549484, 10.090192408),
         (64.454156922, 61.764245954), (37.899437538, 36.573324374)),
         ((9.5, 9.5), (56.5, 19.5), (62.5, 60.5), (19.5, 51.5)), 69,
         Modules => [(6, 12), (9, 6), (6, 8), (10, 6)], Mask => 5,
         Again => True);
      Check_Drawn
        ("in perspective, version 5: 1 module changed around the alignment "
         & "pattern",
         5, (True, 0, (20.952989688, 21.719762052),
         (160.878532878, 162.547814652), (92.057192822, 93.28258204)),
         ((20.5, 21.5), (154.0, 25.5), (160.0, 162.0), (31.5, 157.5)), 241,
         Modules => [1 => (31, 32)], Mask => 6);
      Check_Drawn
        ("in perspective, version 4: 4 modules changed around the alignment "
         & "pattern",
         4, (True, 6, (26.855136914, 30.680976934),
         (128.224598086, 128.485115391), (77.10294712, 79.161492957)),
         ((26.0, 30.0), (133.5, 21.5), (126.0, 128.0), (28.0, 127.5)), 202,
         Modules => [(29, 27), (26, 23), (26, 27), (28, 28)], Mask => 6);
   end Test_Found;

   procedure Run_All is
   begin
      Test_Finder_Patterns;
      Test_Timing_Patterns;
      Test_Alignment;
      Test_Mappings;
      Test_Found;
   end Run_All;

   procedure Main is new AMV_Test_Support.Standalone (Run_All);

begin
   Main;
end Test_Code_Reader_QR_Sampling;
