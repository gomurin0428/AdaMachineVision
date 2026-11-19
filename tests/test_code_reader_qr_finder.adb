--  The QR Code finder kernel (AMV.Kernels.Code_Reader.QR_Code.Finder):
--  symbols of the tests' own encoder (AMV_Test_QR_Code) are painted
--  into images, the images are made maps of dark pixels as the tool
--  makes them, and the finder patterns, the symbols placed on three of
--  them and the modules sampled are compared with what was painted;
--  the modules are read by the kernel that the test of the symbols
--  checks by itself.

with Ada.Numerics;
with Ada.Text_IO;
with Ada.Unchecked_Deallocation;

with AMV.Images;             use AMV.Images;
with AMV.Images.Kernel_Images;
with AMV.Kernels.Code_Reader.Dark_Areas;
with AMV.Kernels.Code_Reader.QR_Code.Finder;
with AMV.Kernels.Code_Reader.Reed_Solomon;
with AMV.Kernels.Images;
with AMV_Test_Barcodes;
with AMV_Test_Data_Matrix;
with AMV_Test_Images;
with AMV_Test_QR_Code;
with AMV_Test_Support;       use AMV_Test_Support;

procedure Test_Code_Reader_QR_Finder is

   package BC renames AMV_Test_Barcodes;
   package DA renames AMV.Kernels.Code_Reader.Dark_Areas;
   package Enc renames AMV_Test_QR_Code;
   package KI renames AMV.Kernels.Images;
   package Paint renames AMV_Test_Data_Matrix;
   package QR renames AMV.Kernels.Code_Reader.QR_Code;
   package FN renames AMV.Kernels.Code_Reader.QR_Code.Finder;
   package RS renames AMV.Kernels.Code_Reader.Reed_Solomon;
   package TI renames AMV_Test_Images;

   use type FN.Corner;
   use type FN.Placement;

   subtype Real is Long_Float;

   Pi : constant := Ada.Numerics.Pi;

   Field : constant RS.Field := RS.Make_Field (RS.QR_Code_Polynomial);

   ---------------------------------------------------------------------
   --  From an image to the symbols in it
   ---------------------------------------------------------------------

   type Map_Access is access DA.Mark_Map;

   procedure Free is
     new Ada.Unchecked_Deallocation (DA.Mark_Map, Map_Access);

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

   Max_Text : constant := 120;

   type Reading is record
      Text     : String (1 .. Max_Text) := [others => ' '];
      Length   : Natural := 0;
      Version  : Natural := 0;
      Mirrored : Boolean := False;
      Shape    : FN.Outline;
      Centre   : FN.Corner;
   end record;

   type Reading_List is array (1 .. 8) of Reading;

   type Outcome is record
      Patterns : Natural := 0;
      Count    : Natural := 0;
      Symbols  : Reading_List;
   end record;

   Version_Steps : constant array (1 .. 5) of Integer := [0, -1, 1, -2, 2];

   function Read (Image : Ks_Image_8_Grey) return Outcome;
   --  The symbols of the image: every three finder patterns that Place
   --  takes for those of a symbol, with the version it gives and the
   --  two before and after it, with either mapping first, as they are
   --  and seen from behind. A pattern belongs to one symbol.

   function Read (Image : Ks_Image_8_Grey) return Outcome is
      Map      : Map_Access := Map_Of (Image);
      Patterns : FN.Pattern_Array (1 .. 64);
      Used     : array (Patterns'Range) of Boolean := [others => False];
      Result   : Outcome;

      procedure Keep
        (Item    : in out Reading;
         Text    : QR.Text_Buffer;
         Version : QR.Version_Number;
         Mirror  : Boolean);

      procedure Keep
        (Item    : in out Reading;
         Text    : QR.Text_Buffer;
         Version : QR.Version_Number;
         Mirror  : Boolean) is
      begin
         Item.Text (1 .. Item.Length) := String (Text (1 .. Item.Length));
         Item.Version := Version;
         Item.Mirrored := Mirror;
         if Mirror then
            Item.Shape :=
              (Upper_Left  => Item.Shape.Upper_Left,
               Upper_Right => Item.Shape.Lower_Left,
               Lower_Right => Item.Shape.Lower_Right,
               Lower_Left  => Item.Shape.Upper_Right);
         end if;
         if Result.Count < Result.Symbols'Last then
            Result.Count := Result.Count + 1;
            Result.Symbols (Result.Count) := Item;
         end if;
      end Keep;

      procedure Try (I, J, K : Positive);

      procedure Try (I, J, K : Positive) is
         Symbol  : FN.Placement;
         Found   : Boolean;
         Version : Integer;
         Grid    : QR.Module_Grid;
         Item    : Reading;
         Text    : QR.Text_Buffer (1 .. Max_Text);
         Unused  : Natural;
         OK      : Boolean;
      begin
         FN.Place
           (Map.all, Patterns (I), Patterns (J), Patterns (K), Symbol,
            Found);
         if not Found then
            return;
         end if;
         for Again in Boolean loop
            for Step of Version_Steps loop
               Version := Symbol.Version + Step;
               if Version in QR.Version_Number then
                  FN.Sample (Map.all, Symbol, Version, Again, Grid,
                             Item.Shape, Item.Centre, OK);
                  if OK then
                     for Mirror in Boolean loop
                        QR.Decode (Grid, Version, Mirror, Field, Text,
                                   Item.Length, Unused, OK);
                        if OK and then Item.Length > 0 then
                           Keep (Item, Text, Version, Mirror);
                           Used (I) := True;
                           Used (J) := True;
                           Used (K) := True;
                           return;
                        end if;
                     end loop;
                  end if;
               end if;
            end loop;
         end loop;
      end Try;
   begin
      FN.Find_Patterns (Map.all, Patterns, Result.Patterns);
      for I in 1 .. Result.Patterns loop
         for J in 1 .. Result.Patterns loop
            for K in J + 1 .. Result.Patterns loop
               if I /= J and then I /= K and then not Used (I)
                 and then not Used (J) and then not Used (K)
               then
                  Try (I, J, K);
               end if;
            end loop;
         end loop;
      end loop;
      Free (Map);
      return Result;
   end Read;

   ---------------------------------------------------------------------
   --  Painting and comparing
   ---------------------------------------------------------------------

   function Message
     (Text    : String;
      Version : QR.Version_Number;
      Level   : QR.Level := QR.M;
      Mask    : QR.Mask_Pattern := 0) return Enc.Module_Matrix
   is (Enc.Symbol (Enc.Segment (Enc.Bytes, Text, Version), Version, Level,
                   Mask));

   function Text_Of (Item : Reading) return String is
     (Item.Text (1 .. Item.Length));

   function Near
     (Corner : FN.Corner;
      Where  : Paint.Place;
      Within : Real) return Boolean
   is (abs (Corner.X - (Where.X + 0.5)) <= Within
       and then abs (Corner.Y - (Where.Y + 0.5)) <= Within);
   --  A point of a map (the pixel (X, Y) covers X .. X + 1) is within
   --  Within pixels of a point of an image (the middle of the pixel
   --  (X, Y) is at (X, Y)).

   function Fits
     (Item   : Reading;
      Where  : Paint.Corners;
      Within : Real) return Boolean
   is (Near (Item.Shape.Upper_Left, Where.Upper_Left, Within)
       and then Near (Item.Shape.Upper_Right, Where.Upper_Right, Within)
       and then Near (Item.Shape.Lower_Right, Where.Lower_Right, Within)
       and then Near (Item.Shape.Lower_Left, Where.Lower_Left, Within)
       and then Near (Item.Centre, Paint.Middle (Where), Within));

   function Has
     (Found    : Outcome;
      Text     : String;
      Version  : QR.Version_Number;
      Where    : Paint.Corners;
      Within   : Real;
      Mirrored : Boolean := False) return Boolean
   is (for some I in 1 .. Found.Count =>
         Text_Of (Found.Symbols (I)) = Text
         and then Found.Symbols (I).Version = Version
         and then Found.Symbols (I).Mirrored = Mirrored
         and then Fits (Found.Symbols (I), Where, Within));
   --  One of the symbols found has that text and version, where it
   --  was painted.

   procedure Report (Found : Outcome; Where : Paint.Corners);

   procedure Report (Found : Outcome; Where : Paint.Corners) is
      use Ada.Text_IO;
   begin
      Put_Line ("  patterns" & Found.Patterns'Image
                & ", symbols" & Found.Count'Image);
      Put_Line ("  painted:" & Where.Upper_Left.X'Image
                & Where.Upper_Left.Y'Image & Where.Upper_Right.X'Image
                & Where.Upper_Right.Y'Image & Where.Lower_Right.X'Image
                & Where.Lower_Right.Y'Image & Where.Lower_Left.X'Image
                & Where.Lower_Left.Y'Image);
      for I in 1 .. Found.Count loop
         declare
            S : constant FN.Outline := Found.Symbols (I).Shape;
         begin
            Put_Line ("  found """ & Text_Of (Found.Symbols (I)) & """ v"
                      & Found.Symbols (I).Version'Image & " "
                      & Found.Symbols (I).Mirrored'Image & ":"
                      & S.Upper_Left.X'Image & S.Upper_Left.Y'Image
                      & S.Upper_Right.X'Image & S.Upper_Right.Y'Image
                      & S.Lower_Right.X'Image & S.Lower_Right.Y'Image
                      & S.Lower_Left.X'Image & S.Lower_Left.Y'Image);
         end;
      end loop;
   end Report;

   procedure Check_One
     (Image       : Ks_Image_8_Grey;
      Text        : String;
      Version     : QR.Version_Number;
      Where       : Paint.Corners;
      Within      : Real;
      Description : String;
      Mirrored    : Boolean := False);
   --  The image has one symbol, with that text and version, where it
   --  was painted.

   procedure Check_One
     (Image       : Ks_Image_8_Grey;
      Text        : String;
      Version     : QR.Version_Number;
      Where       : Paint.Corners;
      Within      : Real;
      Description : String;
      Mirrored    : Boolean := False)
   is
      Found : constant Outcome := Read (Image);
      Good  : constant Boolean :=
        Found.Count = 1
        and then Has (Found, Text, Version, Where, Within, Mirrored);
   begin
      Check (Good, Description);
      if not Good then
         Report (Found, Where);
      end if;
   end Check_One;

   function Canvas (Side : Positive) return Ks_Image_8_Grey is
     (TI.Blank (Side, Side, 255));

   function Size_Of
     (Version : QR.Version_Number;
      Module  : Real) return Real
   is (Real (QR.Side (Version)) * Module);

   function Room (Size : Real) return Positive is
     (Positive (1.42 * Size) + 40);
   --  The side of an image that holds a symbol of Size pixels a side,
   --  however it is turned.

   function Turned
     (Side     : Positive;
      Size     : Real;
      Rotation : Real;
      Shift_X  : Real := 0.0;
      Shift_Y  : Real := 0.0;
      Mirror   : Boolean := False) return Paint.Corners
   is (Paint.Placed
         (Real (Side) / 2.0 + Shift_X, Real (Side) / 2.0 + Shift_Y,
          Size, Size, Rotation, Mirror));
   --  A symbol of Size pixels a side about the middle of an image of
   --  Side pixels a side.

   ---------------------------------------------------------------------
   --  The three steps, one by one
   ---------------------------------------------------------------------

   procedure Test_Steps is
      Version : constant QR.Version_Number := 3;
      Module  : constant Real := 4.0;
      Side    : constant Positive := QR.Side (Version);
      Size    : constant Real := Size_Of (Version, Module);
      Left    : constant Real := 40.0;
      Top     : constant Real := 50.0;
      --  The upper left corner of the symbol in the map: its modules
      --  are four pixels each, exactly.

      Where   : constant Paint.Corners :=
        (Upper_Left  => (Left - 0.5, Top - 0.5),
         Upper_Right => (Left - 0.5 + Size, Top - 0.5),
         Lower_Right => (Left - 0.5 + Size, Top - 0.5 + Size),
         Lower_Left  => (Left - 0.5, Top - 0.5 + Size));
      Symbol  : constant Enc.Module_Matrix := Message ("steps", Version);
      Painted : constant QR.Module_Grid := Enc.Grid (Symbol);
      Far     : constant Real := Real (Side) - 3.5;

      Image    : Ks_Image_8_Grey := Canvas (220);
      Map      : Map_Access;
      Patterns : FN.Pattern_Array (1 .. 16);
      Two      : FN.Pattern_Array (1 .. 2);
      None     : FN.Pattern_Array (1 .. 0);
      Count    : Natural;
      Placed   : FN.Placement;
      Other    : FN.Placement;
      Found    : Boolean;
      Grid     : QR.Module_Grid;
      Shape    : FN.Outline;
      Centre   : FN.Corner;
      OK       : Boolean;

      function Is_At (Point : FN.Corner; X, Y : Real) return Boolean is
        (abs (Point.X - X) <= 0.5 and then abs (Point.Y - Y) <= 0.5);

      function At_Module
        (Item        : FN.Pattern;
         Row, Column : Real) return Boolean
      is (Is_At (Item.Centre, Left + Column * Module, Top + Row * Module)
          and then abs (Item.Module - Module) <= 0.25
          and then Item.Seen >= 2);

      Last : constant QR.Module_Index := QR.Module_Index (Side - 1);

      function Same (Transposed : Boolean) return Boolean is
        (for all R in 0 .. Last =>
           (for all C in 0 .. Last =>
              Grid (R, C)
              = (if Transposed then Painted (C, R) else Painted (R, C))));

      function Outlined return Boolean is
        (Is_At (Shape.Upper_Left, Left, Top)
         and then Is_At (Shape.Upper_Right, Left + Size, Top)
         and then Is_At (Shape.Lower_Right, Left + Size, Top + Size)
         and then Is_At (Shape.Lower_Left, Left, Top + Size)
         and then Is_At (Centre, Left + Size / 2.0, Top + Size / 2.0));
   begin
      Section ("QR finder: patterns, placing and sampling");
      Paint.Draw (Image, Symbol, Where);
      Map := Map_Of (Image);

      FN.Find_Patterns (Map.all, Patterns, Count);
      Check (Count = 3, "three finder patterns (found" & Count'Image & ")");
      if Count /= 3 then
         Free (Map);
         return;
      end if;
      Check (At_Module (Patterns (1), 3.5, 3.5), "the upper left pattern");
      Check (At_Module (Patterns (2), 3.5, Far), "the upper right pattern");
      Check (At_Module (Patterns (3), Far, 3.5), "the lower left pattern");

      FN.Find_Patterns (Map.all, Two, Count);
      Check (Count = 2 and then At_Module (Two (1), 3.5, 3.5)
             and then At_Module (Two (2), 3.5, Far),
             "no more patterns than the table holds");
      FN.Find_Patterns (Map.all, None, Count);
      Check (Count = 0, "a table without room");

      FN.Place
        (Map.all, Patterns (1), Patterns (2), Patterns (3), Placed, Found);
      Check (Found and then Placed.Version = Version
             and then Placed.Upper_Left = Patterns (1).Centre
             and then Placed.Upper_Right = Patterns (2).Centre
             and then Placed.Lower_Left = Patterns (3).Centre
             and then abs Placed.Across <= 0.05
             and then abs Placed.Down <= 0.05,
             "the symbol on the three patterns");
      FN.Place
        (Map.all, Patterns (1), Patterns (3), Patterns (2), Other, Found);
      Check (Found and then Other = Placed,
             "the two other patterns in either order");
      FN.Place
        (Map.all, Patterns (2), Patterns (1), Patterns (3), Other, Found);
      Check (not Found, "the upper right pattern is not the corner");
      FN.Place
        (Map.all, Patterns (3), Patterns (1), Patterns (2), Other, Found);
      Check (not Found, "the lower left pattern is not the corner");
      FN.Place
        (Map.all, Patterns (1), Patterns (1), Patterns (1), Other, Found);
      Check (not Found, "one pattern three times");

      FN.Sample (Map.all, Placed, Version, False, Grid, Shape, Centre, OK);
      Check (OK and then Same (Transposed => False), "the modules");
      Check (OK and then Outlined, "the corners and the middle");
      FN.Sample (Map.all, Placed, Version, True, Grid, Shape, Centre, OK);
      Check (OK and then Same (Transposed => False) and then Outlined,
             "the modules with the other mapping first");
      FN.Sample (Map.all, Placed, 7, False, Grid, Shape, Centre, OK);
      Check (not OK, "the finder patterns of another version do not fit");
      Free (Map);

      --  Seen from behind: the same patterns, and rows for columns.
      Image := Canvas (220);
      Paint.Draw (Image, Enc.Transposed (Symbol), Where);
      Map := Map_Of (Image);
      FN.Find_Patterns (Map.all, Patterns, Count);
      if Count = 3 then
         FN.Place
           (Map.all, Patterns (1), Patterns (2), Patterns (3), Placed,
            Found);
         FN.Sample
           (Map.all, Placed, Version, False, Grid, Shape, Centre, OK);
         Check (Found and then OK and then Same (Transposed => True)
                and then Outlined,
                "the modules of a symbol seen from behind");
      else
         Check (False, "three patterns from behind (found" & Count'Image
                & ")");
      end if;
      Free (Map);
   end Test_Steps;

   ---------------------------------------------------------------------
   --  Symbols of every kind
   ---------------------------------------------------------------------

   procedure Test_Versions is
   begin
      Section ("QR finder: every version");
      for Version in QR.Version_Number loop
         declare
            Size  : constant Real := Size_Of (Version, 3.0);
            Side  : constant Positive := Room (Size);
            Image : Ks_Image_8_Grey := Canvas (Side);
            Where : constant Paint.Corners :=
              Turned (Side, Size, 0.2, 0.3, -0.2);
            Text  : constant String := "version" & Version'Image;
         begin
            Paint.Draw (Image, Message (Text, Version), Where);
            Check_One (Image, Text, Version, Where, 1.0,
                       "version" & Version'Image & ", modules of 3 pixels");
         end;
      end loop;
   end Test_Versions;

   procedure Test_Turned is
   begin
      Section ("QR finder: turned symbols");
      for Step in 0 .. 23 loop
         declare
            Version : constant QR.Version_Number := 1 + Step mod 4 * 2;
            Size    : constant Real := Size_Of (Version, 4.0);
            Side    : constant Positive := Room (Size);
            Image   : Ks_Image_8_Grey := Canvas (Side);
            Where   : constant Paint.Corners :=
              Turned (Side, Size, Real (Step) * Pi / 12.0 + 0.03);
            Text    : constant String := "turn" & Step'Image;
         begin
            Paint.Draw (Image, Message (Text, Version, QR.Q, Step mod 8),
                        Where);
            Check_One (Image, Text, Version, Where, 1.0,
                       "version" & Version'Image & " turned by"
                       & Integer'Image (Step * 15) & " degrees");
         end;
      end loop;
   end Test_Turned;

   procedure Test_Modules is
      Widths : constant array (1 .. 6) of Real :=
        [2.0, 2.5, 3.3, 5.0, 8.3, 12.0];
   begin
      Section ("QR finder: modules of several widths");
      for Width of Widths loop
         for Version in 1 .. 5 loop
            declare
               Size  : constant Real := Size_Of (Version, Width);
               Side  : constant Positive := Room (Size);
               Image : Ks_Image_8_Grey := Canvas (Side);
               Where : constant Paint.Corners :=
                 Turned (Side, Size, 0.1 * Real (Version), 0.4);
               Text  : constant String := "w" & Version'Image;
            begin
               Paint.Draw (Image, Message (Text, Version), Where);
               Check_One (Image, Text, Version, Where,
                          Real'Max (1.25, 0.3 * Width),
                          "version" & Version'Image & ", modules of"
                          & Integer'Image (Integer (Width * 10.0))
                          & " tenths of a pixel");
            end;
         end loop;
      end loop;
   end Test_Modules;

   procedure Test_Narrow is
      Versions : constant array (1 .. 3) of QR.Version_Number := [1, 2, 7];
   begin
      Section ("QR finder: modules of two pixels, turned");
      for Version of Versions loop
         for Step in 0 .. 23 loop
            declare
               Size  : constant Real := Size_Of (Version, 2.0);
               Side  : constant Positive := Room (Size);
               Image : Ks_Image_8_Grey := Canvas (Side);
               Where : constant Paint.Corners :=
                 Turned (Side, Size, Real (Step) * Pi / 12.0 + 0.03,
                         0.3 * Real (Step mod 4), -0.2 * Real (Step mod 3));
               Text  : constant String := "x" & Version'Image;
            begin
               Paint.Draw (Image, Message (Text, Version), Where);
               Check_One (Image, Text, Version, Where, 1.25,
                          "version" & Version'Image & " turned by"
                          & Integer'Image (Step * 15) & " degrees");
            end;
         end loop;
      end loop;
   end Test_Narrow;

   procedure Test_Mirrored is
   begin
      Section ("QR finder: symbols seen from behind");
      for Version in 1 .. 8 loop
         declare
            Size  : constant Real := Size_Of (Version, 4.0);
            Side  : constant Positive := Room (Size);
            Image : Ks_Image_8_Grey := Canvas (Side);
            Where : constant Paint.Corners :=
              Turned (Side, Size, 0.7 * Real (Version), Mirror => True);
            Text  : constant String := "behind" & Version'Image;
         begin
            Paint.Draw (Image, Message (Text, Version), Where);
            Check_One (Image, Text, Version, Where, 1.0,
                       "version" & Version'Image & " from behind",
                       Mirrored => True);
         end;
      end loop;
   end Test_Mirrored;

   procedure Test_Angle is
      Module : constant Real := 5.0;
      Leans  : constant array (1 .. 4) of Real := [0.0, 0.04, 0.08, 0.12];
   begin
      Section ("QR finder: symbols seen at an angle");
      for Part of Leans loop
         for Version in 1 .. 12 loop
            declare
               Size  : constant Real := Size_Of (Version, Module);
               Side  : constant Positive := Positive (Size) + 80;
               Image : Ks_Image_8_Grey := Canvas (Side);
               Lean  : constant Real := Part * Size;
               Where : constant Paint.Corners :=
                 (Upper_Left  => (30.0 + Lean, 30.0),
                  Upper_Right => (30.0 + Size - Lean, 34.0),
                  Lower_Right => (38.0 + Size, 30.0 + Size),
                  Lower_Left  => (26.0, 32.0 + Size));
               Text  : constant String := "angle" & Version'Image;
            begin
               --  Version 1 has no alignment pattern: its fourth
               --  corner is where the widths of the modules put it.
               Paint.Draw (Image, Message (Text, Version), Where);
               Check_One (Image, Text, Version, Where,
                          (if Version = 1 then Module else 2.0),
                          "version" & Version'Image
                          & ", the upper side shorter by"
                          & Integer'Image (Integer (200.0 * Part))
                          & " hundredths");
            end;
         end loop;
      end loop;
   end Test_Angle;

   procedure Test_Quality is
      Versions : constant array (1 .. 3) of QR.Version_Number := [2, 5, 9];
   begin
      Section ("QR finder: images of less quality");
      for Version in 1 .. 6 loop
         declare
            Size  : constant Real := Size_Of (Version, 4.0);
            Side  : constant Positive := Room (Size);
            Image : Ks_Image_8_Grey := Canvas (Side);
            Where : constant Paint.Corners :=
              Turned (Side, Size, 0.25 * Real (Version));
            Text  : constant String := "blur" & Version'Image;
         begin
            Paint.Draw (Image, Message (Text, Version), Where);
            BC.Blur (Image, 1.0);
            Check_One (Image, Text, Version, Where, 1.5,
                       "version" & Version'Image
                       & " blurred by a pixel");
         end;
      end loop;
      for Version of Versions loop
         declare
            Size  : constant Real := Size_Of (Version, 4.0);
            Side  : constant Positive := Room (Size);
            Where : constant Paint.Corners :=
              Turned (Side, Size, 0.4 * Real (Version), 0.25, 0.5);
            Text  : constant String := "quality" & Version'Image;
            Image : Ks_Image_8_Grey := Canvas (Side);
         begin
            Paint.Draw (Image, Message (Text, Version), Where);
            BC.Blur (Image, 0.5);
            TI.Add_Noise (Image, 20.0, Version);
            Check_One (Image, Text, Version, Where, 1.5,
                       "version" & Version'Image & " with noise");

            Image := Canvas (Side);
            Paint.Draw (Image, Message (Text, Version), Where);
            BC.Blur (Image, 0.5);
            BC.Shade (Image, 1.0, 0.4);
            Check_One (Image, Text, Version, Where, 1.5,
                       "version" & Version'Image & " in uneven light");

            Image := TI.Blank (Side, Side, 170);
            Paint.Draw (Image, Message (Text, Version), Where, Dark => 120);
            BC.Blur (Image, 0.5);
            Check_One (Image, Text, Version, Where, 1.5,
                       "version" & Version'Image & " with little contrast");
         end;
      end loop;
   end Test_Quality;

   procedure Test_Several is
      Image  : Ks_Image_8_Grey := TI.Blank (420, 420, 255);
      First  : constant Paint.Corners :=
        Paint.Placed (110.0, 110.0, 100.0, 100.0, 0.3);
      Second : constant Paint.Corners :=
        Paint.Placed (300.0, 130.0, 111.0, 111.0, 2.0);
      Third  : constant Paint.Corners :=
        Paint.Placed (200.0, 310.0, 105.0, 105.0, 4.0, Mirror => True);
      Found  : Outcome;
   begin
      Section ("QR finder: several symbols in an image");
      Paint.Draw (Image, Message ("one", 2), First);
      Paint.Draw (Image, Message ("two", 5, QR.H, 3), Second);
      Paint.Draw (Image, Message ("three", 1, QR.L, 5), Third);
      Found := Read (Image);
      Check (Found.Count = 3, "three symbols (found" & Found.Count'Image
             & ")");
      Check (Has (Found, "one", 2, First, 1.0), "the first");
      Check (Has (Found, "two", 5, Second, 1.0), "the second");
      Check (Has (Found, "three", 1, Third, 1.0, Mirrored => True),
             "the third, seen from behind");
      if Found.Count /= 3 then
         Report (Found, First);
      end if;
   end Test_Several;

   procedure Test_Nothing is
      Version : constant QR.Version_Number := 4;
      Side    : constant Positive := QR.Side (Version);
      Symbol  : Enc.Module_Matrix := Message ("nothing", Version);
      Image   : Ks_Image_8_Grey := TI.Blank (320, 240, 128);
      Found   : Natural := 0;
   begin
      Section ("QR finder: images without a symbol");
      Check (Read (Image).Patterns = 0, "one grey level");
      Check (Read (TI.Blank (320, 240, 0)).Patterns = 0, "black");
      Check (Read (TI.Blank (1, 1, 0)).Patterns = 0, "one pixel");
      Check (Read (TI.Blank (7, 3, 255)).Patterns = 0,
             "less than a block of pixels");

      for Seed in 1 .. 4 loop
         Image := TI.Blank (320, 240, 128);
         TI.Add_Noise (Image, 100.0, Seed);
         Found := Found + Read (Image).Count;
         BC.Blur (Image, 1.5);
         Found := Found + Read (Image).Count;
      end loop;
      Check (Found = 0, "noise gives no symbol (found" & Found'Image & ")");

      Found := 0;
      for Turn in 0 .. 5 loop
         TI.Checkerboard (Image, 13.3, 7.1, 3.0 + Real (Turn),
                          Rotation => 0.2 * Real (Turn));
         Found := Found + Read (Image).Count;
      end loop;
      Check (Found = 0, "squares give no symbol (found" & Found'Image
             & ")");

      --  A symbol without its lower left finder pattern.
      for R in Side - 8 .. Side - 1 loop
         for C in 0 .. 7 loop
            Symbol (R, C) := False;
         end loop;
      end loop;
      Image := TI.Blank (320, 240, 255);
      Paint.Draw (Image, Symbol, Paint.Placed (160.0, 120.0, 132.0, 132.0));
      Check (Read (Image).Count = 0, "two finder patterns");
   end Test_Nothing;

   procedure Run_All is
   begin
      Test_Steps;
      Test_Versions;
      Test_Turned;
      Test_Modules;
      Test_Narrow;
      Test_Mirrored;
      Test_Angle;
      Test_Quality;
      Test_Several;
      Test_Nothing;
   end Run_All;

   procedure Main is new AMV_Test_Support.Standalone (Run_All);

begin
   Main;
end Test_Code_Reader_QR_Finder;
