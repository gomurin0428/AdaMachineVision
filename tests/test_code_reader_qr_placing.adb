--  The placing of a symbol on three finder patterns by the QR Code
--  finder kernel (AMV.Kernels.Code_Reader.QR_Code.Finder.Place), on
--  small maps of dark pixels that are made here pixel by pixel, with
--  patterns whose centres and widths of a module are given by hand.
--
--  The symbols that the other tests of the finder paint are whole, so
--  their patterns are always far enough apart, at a right angle and of
--  one width. The maps here are made for the limits: how long the two
--  arms from the corner must be and how far they may differ, how far
--  the angle between them may be from a right one, how the width of a
--  module is measured along an arm, and what is done when one end of
--  an arm, or both, shows no pattern. Some maps were found by a search
--  for maps on which a change of one operator or of one number in the
--  body of the finder changes the placing.
--
--  What is expected of a map is what the finder gives for it. Where the
--  reason is plain it is in a comment. So these checks do not say that
--  every result is the right one; they say that none of them changes
--  unseen.

with Ada.Numerics.Long_Elementary_Functions;

with AMV.Kernels.Code_Reader.Dark_Areas;
with AMV.Kernels.Code_Reader.QR_Code.Finder;
with AMV_Test_Support;       use AMV_Test_Support;

procedure Test_Code_Reader_QR_Placing is

   package DA renames AMV.Kernels.Code_Reader.Dark_Areas;
   package FN renames AMV.Kernels.Code_Reader.QR_Code.Finder;
   package EF renames Ada.Numerics.Long_Elementary_Functions;

   subtype Real is Long_Float;

   Near : constant := 1.0E-9;

   type Point is record
      X, Y : Real;
   end record;

   type Three_Points is array (0 .. 2) of Point;
   --  The centres of the patterns: the corner, the one along the first
   --  arm and the one along the second. The second arm is to the right
   --  of the first as the image is seen, as in a symbol that is not
   --  seen from behind: the first pattern is the upper left one, the
   --  second the upper right one and the third the lower left one.

   type Three_Flags is array (0 .. 2) of Boolean;

   type Three_Widths is array (0 .. 2) of Real;
   --  The widths of a module that the three patterns are given.

   type Pixel is record
      X, Y : Natural;
   end record;

   type Pixel_Array is array (Positive range <>) of Pixel;

   ---------------------------------------------------------------------
   --  Maps
   ---------------------------------------------------------------------

   function Blank (Width, Height : Positive) return DA.Mark_Map is
     [0 .. Height - 1 => [0 .. Width - 1 => DA.Light]];

   procedure Rings
     (Map    : in out DA.Mark_Map;
      Centre : Point;
      Module : Positive);
   --  An exact pattern of Module pixels a module about the centre: a
   --  dark square of seven modules a side, a light one of five in it
   --  and a dark one of three in that.

   procedure Rings
     (Map    : in out DA.Mark_Map;
      Centre : Point;
      Module : Positive)
   is
      Left : constant Integer :=
        Integer (Centre.X - 3.5 * Real (Module));
      Top  : constant Integer :=
        Integer (Centre.Y - 3.5 * Real (Module));
      Last : constant Natural := 7 * Module - 1;
   begin
      for Y in 0 .. Last loop
         for X in 0 .. Last loop
            declare
               Edge : constant Natural :=
                 Natural'Min (Natural'Min (X, Last - X),
                              Natural'Min (Y, Last - Y));
            begin
               if Edge / Module /= 1 then
                  Map (Top + Y, Left + X) := DA.Dark;
               end if;
            end;
         end loop;
      end loop;
   end Rings;

   ---------------------------------------------------------------------
   --  What the finder gives
   ---------------------------------------------------------------------

   function Is_At (C : FN.Corner; P : Point) return Boolean is
     (abs (C.X - P.X) <= Near and then abs (C.Y - P.Y) <= Near);

   procedure Check_Placing
     (Name    : String;
      Map     : DA.Mark_Map;
      Centres : Three_Points;
      Widths  : Three_Widths;
      Want    : Natural;
      Across  : Real := 0.0;
      Down    : Real := 0.0);
   --  Place on the map with the patterns at Centres, given Widths,
   --  gives the symbol of the version Want (none if Want is 0) with
   --  the changes of width Across and Down; and so does Place with the
   --  second and the third pattern the other way round.

   procedure Check_Placing
     (Name    : String;
      Map     : DA.Mark_Map;
      Centres : Three_Points;
      Widths  : Three_Widths;
      Want    : Natural;
      Across  : Real := 0.0;
      Down    : Real := 0.0)
   is
      function Given (I : Natural) return FN.Pattern is
        (Centre => (X => Centres (I).X, Y => Centres (I).Y),
         Module => Widths (I),
         Seen   => 3);

      Symbol : FN.Placement;
      Found  : Boolean;
   begin
      for Turned in Boolean loop
         if Turned then
            FN.Place (Map, Given (0), Given (2), Given (1), Symbol, Found);
         else
            FN.Place (Map, Given (0), Given (1), Given (2), Symbol, Found);
         end if;
         declare
            Order : constant String :=
              (if Turned then " (the other order)" else "");
         begin
            Check (Found = (Want /= 0), Name & ": found" & Order);
            if Found and then Want /= 0 then
               Check (Symbol.Version = Want,
                      Name & ": the version" & Order & " (got"
                      & Symbol.Version'Image & ")");
               Check (Is_At (Symbol.Upper_Left, Centres (0))
                      and then Is_At (Symbol.Upper_Right, Centres (1))
                      and then Is_At (Symbol.Lower_Left, Centres (2)),
                      Name & ": the corners" & Order);
               Check (abs (Symbol.Across - Across) <= Near
                      and then abs (Symbol.Down - Down) <= Near,
                      Name & ": the changes of width" & Order & " (got"
                      & Symbol.Across'Image & Symbol.Down'Image & ")");
            end if;
         end;
      end loop;
   end Check_Placing;

   procedure Check_Three
     (Name    : String;
      Centres : Three_Points;
      Want    : Natural;
      Module  : Positive := 1;
      Given   : Real := 0.0;
      Drawn   : Three_Flags := [others => True];
      Across  : Real := 0.0;
      Down    : Real := 0.0);
   --  Check_Placing on a map with exact patterns of Module pixels a
   --  module at those of the centres that are Drawn, given the width
   --  Given (or Module if Given is 0.0). The map reaches five modules
   --  beyond the furthest centre.

   procedure Check_Three
     (Name    : String;
      Centres : Three_Points;
      Want    : Natural;
      Module  : Positive := 1;
      Given   : Real := 0.0;
      Drawn   : Three_Flags := [others => True];
      Across  : Real := 0.0;
      Down    : Real := 0.0)
   is
      Width : constant Real := (if Given = 0.0 then Real (Module)
                                else Given);
      Far_X : Real := 0.0;
      Far_Y : Real := 0.0;
   begin
      for C of Centres loop
         Far_X := Real'Max (Far_X, C.X);
         Far_Y := Real'Max (Far_Y, C.Y);
      end loop;
      declare
         Map : DA.Mark_Map :=
           Blank (Positive (Far_X) + 5 * Module,
                  Positive (Far_Y) + 5 * Module);
      begin
         for I in Centres'Range loop
            if Drawn (I) then
               Rings (Map, Centres (I), Module);
            end if;
         end loop;
         Check_Placing
           (Name, Map, Centres, [others => Width], Want, Across, Down);
      end;
   end Check_Three;

   ---------------------------------------------------------------------
   --  The arms
   ---------------------------------------------------------------------

   procedure Test_Lengths is
   begin
      Section ("QR placing: the lengths of the arms");
      --  An exact pattern of one pixel a module has a width of 3.25
      --  pixels ahead of its centre and 3.75 behind it along a row or
      --  a column (the half way to the third change of colour, in steps
      --  of half a pixel), so a module of 1.0 exactly: an arm of D
      --  pixels is D modules. The version is the one of the mean of
      --  the two arms, (mean - 10) / 4 rounded, at least 1.
      Check_Three
        ("arms of ten pixels",
         [(5.5, 5.5), (15.5, 5.5), (5.5, 15.5)], Want => 1);
      Check_Three
        ("arms of sixteen pixels",
         [(5.5, 5.5), (21.5, 5.5), (5.5, 21.5)], Want => 2);
      Check_Three
        ("arms of 176 pixels",
         [(5.5, 5.5), (181.5, 5.5), (5.5, 181.5)], Want => 40);
      Check_Three
        ("arms of 177 pixels",
         [(5.5, 5.5), (182.5, 5.5), (5.5, 182.5)], Want => 0);
      --  Two pixels a module: 6.75 and 7.25 pixels, a module of 2.0.
      Check_Three
        ("arms of eight modules",
         [(8.0, 8.0), (24.0, 8.0), (8.0, 24.0)], Want => 0, Module => 2);
      Check_Three
        ("arms of ten modules",
         [(8.0, 8.0), (28.0, 8.0), (8.0, 28.0)], Want => 1, Module => 2);

      Section ("QR placing: arms of unlike lengths");
      Check_Three
        ("one arm twice the other",
         [(5.5, 5.5), (25.5, 5.5), (5.5, 15.5)], Want => 1);
      Check_Three
        ("the other arm twice the one",
         [(5.5, 5.5), (15.5, 5.5), (5.5, 25.5)], Want => 1);
      Check_Three
        ("one arm more than twice the other",
         [(5.5, 5.5), (35.5, 5.5), (5.5, 17.5)], Want => 0);
      Check_Three
        ("the other arm more than twice the one",
         [(5.5, 5.5), (17.5, 5.5), (5.5, 35.5)], Want => 0);
   end Test_Lengths;

   procedure Test_Angle is
   begin
      Section ("QR placing: the angle between the arms");
      --  The arms (20, 0) and (-16, 10) are 148 degrees apart: their
      --  cosine is beyond -0.5.
      Check_Three
        ("an angle of more than 120 degrees",
         [(24.5, 6.5), (44.5, 6.5), (8.5, 16.5)], Want => 0);
      --  (20, 0) and (-5, 15): 108 degrees.
      Check_Three
        ("an angle of less than 120 degrees",
         [(24.5, 6.5), (44.5, 6.5), (19.5, 21.5)], Want => 2);
   end Test_Angle;

   procedure Test_Given_Widths is
   begin
      Section ("QR placing: the widths the patterns are given");
      --  A pattern is followed for 6 widths and 2 pixels each way:
      --  for patterns of two pixels a module given a width of 1.0 that
      --  is 8 pixels, and the third change of colour behind the centre
      --  is 7.5 pixels away.
      Check_Three
        ("patterns given half their width",
         [(8.0, 8.0), (28.0, 8.0), (8.0, 28.0)], Want => 1,
         Module => 2, Given => 1.0);
      --  Given a width of 0.8 they are followed for 7 pixels: the third
      --  change ahead of the centre, at 7 pixels, is reached, the one
      --  behind it is not. A width is measured both ways or not at all:
      --  no end of an arm has one.
      Check_Three
        ("patterns given 0.4 of their width",
         [(8.0, 8.0), (28.0, 8.0), (8.0, 28.0)], Want => 0,
         Module => 2, Given => 0.8);
      --  An arm must be 7 widths at least; patterns of one pixel a
      --  module given a width of 2.0.
      Check_Three
        ("arms of seven given widths",
         [(5.5, 5.5), (19.5, 5.5), (5.5, 19.5)], Want => 1,
         Given => 2.0);
      Check_Three
        ("a first arm of six given widths",
         [(5.5, 5.5), (17.5, 5.5), (5.5, 19.5)], Want => 0,
         Given => 2.0);
      Check_Three
        ("a second arm of six given widths",
         [(5.5, 5.5), (19.5, 5.5), (5.5, 17.5)], Want => 0,
         Given => 2.0);
      --  The width that the arms are measured by is the narrowest of
      --  the three: arms of 12 pixels are 7 widths of the pattern given
      --  1.0 and more, though fewer of the two given 2.0.
      declare
         Map : DA.Mark_Map := Blank (23, 23);
      begin
         Rings (Map, (5.5, 5.5), 1);
         Rings (Map, (17.5, 5.5), 1);
         Rings (Map, (5.5, 17.5), 1);
         Check_Placing
           ("arms of seven widths of the narrowest pattern only", Map,
            [(5.5, 5.5), (17.5, 5.5), (5.5, 17.5)], [2.0, 1.0, 2.0],
            Want => 1);
      end;
   end Test_Given_Widths;

   procedure Test_Ends is
   begin
      Section ("QR placing: ends of arms without a pattern");
      --  Where no pattern is drawn, nothing changes colour within the
      --  steps for which a pattern of the width it is given is
      --  followed: that end of the arm has no width, and the width of
      --  the arm is the one at its other end. The change of width
      --  along the arm is then not known and is zero.
      Check_Three
        ("no pattern at the corner",
         [(5.5, 5.5), (25.5, 5.5), (5.5, 25.5)], Want => 3,
         Drawn => [False, True, True]);
      Check_Three
        ("a pattern at the corner only",
         [(5.5, 5.5), (25.5, 5.5), (5.5, 25.5)], Want => 3,
         Drawn => [True, False, False]);
      --  An arm with no width at either end: no symbol, although the
      --  other arm, of 40 modules, would make a mean of 20 with an arm
      --  of none.
      Check_Three
        ("no pattern at either end of the first arm",
         [(5.5, 5.5), (25.5, 5.5), (5.5, 45.5)], Want => 0,
         Drawn => [False, False, True]);
      Check_Three
        ("no pattern at either end of the second arm",
         [(5.5, 5.5), (45.5, 5.5), (5.5, 25.5)], Want => 0,
         Drawn => [False, True, False]);
   end Test_Ends;

   procedure Test_Change is
      Map : DA.Mark_Map := Blank (62, 62);
   begin
      Section ("QR placing: the change of width along an arm");
      --  A pattern of five pixels a module in the corner and two of one
      --  pixel a module, all given a width of 3.0: the widths at the
      --  ends of each arm are 5.0 and 1.0, their mean 3.0. The ratio of
      --  the two is limited to 4, its root to 2, and the change of
      --  width to 1.
      Rings (Map, (20.5, 20.5), 5);
      Rings (Map, (56.5, 20.5), 1);
      Rings (Map, (20.5, 56.5), 1);
      Check_Placing
        ("widths of 5 and 1 at the ends of the arms", Map,
         [(20.5, 20.5), (56.5, 20.5), (20.5, 56.5)], [others => 3.0],
         Want => 1, Across => 1.0, Down => 1.0);
   end Test_Change;

   procedure Check_Pixels
     (Name    : String;
      Width   : Positive;
      Height  : Positive;
      Pixels  : Pixel_Array;
      Centres : Three_Points;
      Widths  : Three_Widths;
      Want    : Natural;
      Across  : Real := 0.0;
      Down    : Real := 0.0);
   --  Check_Placing on a map of Width by Height pixels whose dark ones
   --  are Pixels.

   procedure Check_Pixels
     (Name    : String;
      Width   : Positive;
      Height  : Positive;
      Pixels  : Pixel_Array;
      Centres : Three_Points;
      Widths  : Three_Widths;
      Want    : Natural;
      Across  : Real := 0.0;
      Down    : Real := 0.0)
   is
      Map : DA.Mark_Map := Blank (Width, Height);
   begin
      for P of Pixels loop
         Map (P.Y, P.X) := DA.Dark;
      end loop;
      Check_Placing (Name, Map, Centres, Widths, Want, Across, Down);
   end Check_Pixels;

   procedure Test_Found is
   begin
      Section ("QR placing: maps found by the search");
      --  A few dark pixels about where the patterns are said to be, and
      --  arms at a slant. Along a slant, a step of half a pixel may go
      --  into another pixel at every step but one, so that the half
      --  ways can be shorter than along a row: the widths of a module
      --  of half a pixel or less are seen here, which squares of pixels
      --  along a row or a column never give.

      --  The first arm is 9.06 pixels: too short, although the width at
      --  its far end, 1.07 pixels, and the second arm would make a mean
      --  of 12 modules.
      Check_Pixels
        ("an arm of nine pixels", 43, 56,
         [(32, 22), (20, 26), (26, 26), (32, 28)],
         [(32.5, 25.5), (23.5, 26.5), (31.5, 8.5)],
         [0.973958333333333, 0.959635416666667, 0.9453125], Want => 0);
      --  The middle of the corner pattern is on a light pixel. The
      --  colour there is not looked at: the first step is half a pixel
      --  from the middle. Ahead along the first arm there is no third
      --  change of colour, and the arm has a width at neither end.
      Check_Pixels
        ("a light pixel at the middle of the corner", 27, 63,
         [(22, 3), (25, 3), (16, 5), (24, 10)],
         [(23.0, 4.0), (18.0, -19.0), (56.0, -1.0)],
         [1.82291666666667, 1.69270833333333, 1.84895833333333],
         Want => 0);
      --  The width at the corner end of the first arm is 3/7 of a pixel,
      --  at its far end 1: the arm has the mean of the two, and no
      --  change of width is taken from them.
      Check_Pixels
        ("a width below half a pixel at one end of an arm", 36, 33,
         [(22, 11), (19, 17), (15, 24), (13, 25), (14, 26), (17, 27)],
         [(14.5, 25.5), (20.5, 14.5), (36.5, 37.5)],
         [0.80859375, 0.75, 0.80859375], Want => 4);
      --  The width at the corner end of the first arm is half a pixel
      --  exactly, at its far end 1: the change of width is the root of
      --  their ratio, less 1.
      Check_Pixels
        ("a width of half a pixel at the near end of an arm", 64, 53,
         [(18, 20), (24, 23), (30, 25), (32, 25), (32, 27), (29, 29)],
         [(31.5, 26.5), (21.5, 21.5), (37.5, 17.5)],
         [0.44921875, 0.442708333333333, 0.462239583333333], Want => 1,
         Across => EF.Sqrt (0.5) - 1.0);
      --  The width at the far end of the second arm is half a pixel
      --  exactly, at its corner end 7.5 / 7.
      Check_Pixels
        ("a width of half a pixel at the far end of an arm", 30, 28,
         [(6, 14), (8, 14), (27, 17), (23, 19), (29, 21), (25, 23)],
         [(26.5, 20.5), (15.5, 50.5), (7.5, 14.5)],
         [0.846354166666667, 0.846354166666667, 0.859375], Want => 4,
         Down => EF.Sqrt (15.0 / 7.0) - 1.0);
      --  The first arm has a width at its corner end only, 2.5 / 7: too
      --  narrow.
      Check_Pixels
        ("an arm whose only width is below half a pixel", 52, 34,
         [(15, 14), (11, 20), (1, 33), (3, 33)],
         [(2.5, 33.5), (13.5, 17.5), (-13.5, 25.5)],
         [1.23958333333333, 1.203125, 1.203125], Want => 0);
      --  The second arm has a width at its corner end only, half a pixel
      --  exactly.
      Check_Pixels
        ("an arm whose only width is half a pixel", 34, 52,
         [(29, 10), (29, 12), (2, 13), (8, 13)],
         [(29.5, 11.5), (5.5, 13.5), (30.5, -1.5)],
         [0.98828125, 0.973958333333333, 1.00260416666667], Want => 4);
   end Test_Found;

   procedure Run_All is
   begin
      Test_Lengths;
      Test_Angle;
      Test_Given_Widths;
      Test_Ends;
      Test_Change;
      Test_Found;
   end Run_All;

   procedure Main is new AMV_Test_Support.Standalone (Run_All);

begin
   Main;
end Test_Code_Reader_QR_Placing;
