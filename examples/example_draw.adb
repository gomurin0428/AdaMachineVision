with Ada.Characters.Handling;
with Ada.Numerics.Generic_Elementary_Functions;

with AMV.Image_File;

package body Example_Draw is

   use AMV.Images;

   package EF is new Ada.Numerics.Generic_Elementary_Functions (Real);

   ---------------------------------------------------------------------
   --  Picture coordinates
   ---------------------------------------------------------------------

   --  A picture pixel (I, J) has its centre at (I, J) in picture
   --  coordinates; the picture's top left corner (-0.5, -0.5) is the
   --  image position (Left, Top).

   function PX (Onto : Picture; X : Real) return Real is
     ((X - Onto.Left) * Onto.Scale - 0.5);

   function PY (Onto : Picture; Y : Real) return Real is
     ((Y - Onto.Top) * Onto.Scale - 0.5);

   procedure Blend
     (Onto  : in out Picture;
      I, J  : Integer;
      Ink   : Colour;
      Alpha : Real);
   --  Mixes Ink into picture pixel (I, J) (nothing outside the picture).

   procedure Blend
     (Onto  : in out Picture;
      I, J  : Integer;
      Ink   : Colour;
      Alpha : Real)
   is
      R, G, B : Grey_8;

      function Mix (Old, Value : Grey_8) return Grey_8 is
        (Grey_8 (Real (Old) + (Real (Value) - Real (Old)) * Alpha));
   begin
      if Alpha > 0.0
        and then I in 0 .. Onto.Pixels.Width - 1
        and then J in 0 .. Onto.Pixels.Height - 1
      then
         Onto.Pixels.Get_Pixel (I, J, R, G, B);
         Onto.Pixels.Set_Pixel
           (I, J, Mix (R, Ink.R), Mix (G, Ink.G), Mix (B, Ink.B));
      end if;
   end Blend;

   function Coverage (Distance, Half_Width : Real) return Real is
     (Real'Max (0.0, Real'Min (1.0, Half_Width + 0.5 - Distance)));
   --  How much of a pixel whose centre is Distance from a stroke's middle
   --  line the stroke covers (roughly: a one pixel ramp at its border).

   ---------------------------------------------------------------------
   --  Create
   ---------------------------------------------------------------------

   function Create
     (Image         : AMV.Images.Ks_Image_8_Grey;
      X, Y          : Integer;
      Width, Height : Positive;
      Scale         : Real := 1.0) return Picture
   is
      W      : constant Positive :=
        Positive'Max (1, Integer (Real'Floor (Real (Width) * Scale)));
      H      : constant Positive :=
        Positive'Max (1, Integer (Real'Floor (Real (Height) * Scale)));
      Result : Picture :=
        (Pixels => Create (W, H),
         Left   => Real (X) - 0.5,
         Top    => Real (Y) - 0.5,
         Scale  => Scale);

      function Grey (I, J : Natural) return Grey_8;
      --  The grey level of picture pixel (I, J): the mean of the image
      --  pixels whose centres lie under it, or the one under its centre.

      function Grey (I, J : Natural) return Grey_8 is
         X0    : constant Integer :=
           X + Integer (Real'Ceiling (Real (I) / Scale - 0.5));
         X1    : constant Integer :=
           X + Integer (Real'Ceiling (Real (I + 1) / Scale - 0.5)) - 1;
         Y0    : constant Integer :=
           Y + Integer (Real'Ceiling (Real (J) / Scale - 0.5));
         Y1    : constant Integer :=
           Y + Integer (Real'Ceiling (Real (J + 1) / Scale - 0.5)) - 1;
         Sum   : Natural := 0;
         Count : Natural := 0;
         CX    : Integer;
         CY    : Integer;
      begin
         if X1 >= X0 and then Y1 >= Y0 then
            for V in Y0 .. Y1 loop
               for U in X0 .. X1 loop
                  if U in 0 .. Image.Width - 1
                    and then V in 0 .. Image.Height - 1
                  then
                     Sum := Sum + Natural (Image.Get_Pixel (U, V));
                     Count := Count + 1;
                  end if;
               end loop;
            end loop;
            return (if Count = 0 then 0
                    else Grey_8 ((Sum + Count / 2) / Count));
         end if;
         CX := X + Integer (Real'Floor ((Real (I) + 0.5) / Scale));
         CY := Y + Integer (Real'Floor ((Real (J) + 0.5) / Scale));
         if CX in 0 .. Image.Width - 1 and then CY in 0 .. Image.Height - 1
         then
            return Image.Get_Pixel (CX, CY);
         end if;
         return 0;
      end Grey;

   begin
      for J in 0 .. H - 1 loop
         for I in 0 .. W - 1 loop
            declare
               Value : constant Grey_8 := Grey (I, J);
            begin
               Result.Pixels.Set_Pixel (I, J, Value, Value, Value);
            end;
         end loop;
      end loop;
      return Result;
   end Create;

   function Create
     (Image : AMV.Images.Ks_Image_8_Grey;
      Scale : Real := 1.0) return Picture
   is (Create (Image, 0, 0, Image.Width, Image.Height, Scale));

   ---------------------------------------------------------------------
   --  Strokes (in picture coordinates)
   ---------------------------------------------------------------------

   procedure Stroke
     (Onto           : in out Picture;
      AX, AY, BX, BY : Real;
      Ink            : Colour;
      Width          : Real);

   procedure Stroke
     (Onto           : in out Picture;
      AX, AY, BX, BY : Real;
      Ink            : Colour;
      Width          : Real)
   is
      Half   : constant Real := Width / 2.0;
      Reach  : constant Real := Half + 1.0;
      DX     : constant Real := BX - AX;
      DY     : constant Real := BY - AY;
      Length : constant Real := DX * DX + DY * DY;
      Last_X : constant Real := Real (Onto.Pixels.Width);
      Last_Y : constant Real := Real (Onto.Pixels.Height);
      I0, I1, J0, J1 : Integer;
      T, D   : Real;
   begin
      if Real'Max (AX, BX) < -Reach or else Real'Min (AX, BX) > Last_X + Reach
        or else Real'Max (AY, BY) < -Reach
        or else Real'Min (AY, BY) > Last_Y + Reach
      then
         return;
      end if;
      I0 := Integer (Real'Max (0.0, Real'Floor (Real'Min (AX, BX) - Reach)));
      I1 := Integer (Real'Min (Last_X - 1.0,
                               Real'Ceiling (Real'Max (AX, BX) + Reach)));
      J0 := Integer (Real'Max (0.0, Real'Floor (Real'Min (AY, BY) - Reach)));
      J1 := Integer (Real'Min (Last_Y - 1.0,
                               Real'Ceiling (Real'Max (AY, BY) + Reach)));
      for J in J0 .. J1 loop
         for I in I0 .. I1 loop
            T := (if Length = 0.0 then 0.0
                  else ((Real (I) - AX) * DX + (Real (J) - AY) * DY)
                       / Length);
            T := Real'Max (0.0, Real'Min (1.0, T));
            D := EF.Sqrt ((Real (I) - AX - T * DX) ** 2
                          + (Real (J) - AY - T * DY) ** 2);
            Blend (Onto, I, J, Ink, Coverage (D, Half));
         end loop;
      end loop;
   end Stroke;

   procedure Line
     (Onto           : in out Picture;
      X0, Y0, X1, Y1 : Real;
      Ink            : Colour;
      Width          : Real := 1.5) is
   begin
      Stroke (Onto, PX (Onto, X0), PY (Onto, Y0), PX (Onto, X1),
              PY (Onto, Y1), Ink, Width);
   end Line;

   procedure Ring
     (Onto         : in out Picture;
      CX, CY       : Real;
      Radius, Half : Real;
      Ink          : Colour;
      Filled       : Boolean);
   --  A circle line of half width Half, or a disc, in picture coordinates.

   procedure Ring
     (Onto         : in out Picture;
      CX, CY       : Real;
      Radius, Half : Real;
      Ink          : Colour;
      Filled       : Boolean)
   is
      Reach  : constant Real := Radius + Half + 1.0;
      Last_X : constant Real := Real (Onto.Pixels.Width);
      Last_Y : constant Real := Real (Onto.Pixels.Height);
      D      : Real;
   begin
      if CX + Reach < 0.0 or else CX - Reach > Last_X
        or else CY + Reach < 0.0 or else CY - Reach > Last_Y
      then
         return;
      end if;
      for J in Integer (Real'Max (0.0, Real'Floor (CY - Reach)))
        .. Integer (Real'Min (Last_Y - 1.0, Real'Ceiling (CY + Reach)))
      loop
         for I in Integer (Real'Max (0.0, Real'Floor (CX - Reach)))
           .. Integer (Real'Min (Last_X - 1.0, Real'Ceiling (CX + Reach)))
         loop
            D := EF.Sqrt ((Real (I) - CX) ** 2 + (Real (J) - CY) ** 2);
            Blend (Onto, I, J, Ink,
                   (if Filled then Coverage (D, Radius)
                    else Coverage (abs (D - Radius), Half)));
         end loop;
      end loop;
   end Ring;

   procedure Circle
     (Onto                     : in out Picture;
      Center_X, Center_Y, Radius : Real;
      Ink                      : Colour;
      Width                    : Real := 1.5) is
   begin
      Ring (Onto, PX (Onto, Center_X), PY (Onto, Center_Y),
            Radius * Onto.Scale, Width / 2.0, Ink, Filled => False);
   end Circle;

   procedure Dot
     (Onto : in out Picture;
      X, Y : Real;
      Ink  : Colour;
      Size : Real := 2.0) is
   begin
      Ring (Onto, PX (Onto, X), PY (Onto, Y), Size, 0.0, Ink,
            Filled => True);
   end Dot;

   procedure Cross
     (Onto  : in out Picture;
      X, Y  : Real;
      Ink   : Colour;
      Size  : Real := 6.0;
      Width : Real := 1.5)
   is
      CX : constant Real := PX (Onto, X);
      CY : constant Real := PY (Onto, Y);
   begin
      Stroke (Onto, CX - Size, CY, CX + Size, CY, Ink, Width);
      Stroke (Onto, CX, CY - Size, CX, CY + Size, Ink, Width);
   end Cross;

   procedure Outline
     (Onto  : in out Picture;
      Shape : AMV.Shapes.Ks_Polygon;
      Ink   : Colour;
      Width : Real := 1.5)
   is
      N : constant Natural := Shape.Num_Vertices;
   begin
      for K in 0 .. N - 1 loop
         Line (Onto, Shape.Get_Vertex_X (K), Shape.Get_Vertex_Y (K),
               Shape.Get_Vertex_X ((K + 1) mod N),
               Shape.Get_Vertex_Y ((K + 1) mod N), Ink, Width);
      end loop;
   end Outline;

   procedure Outline
     (Onto  : in out Picture;
      Shape : AMV.Shapes.Ks_Rectangle_Affine;
      Ink   : Colour;
      Width : Real := 1.5) is
   begin
      Line (Onto, Shape.Corner_Origin_X, Shape.Corner_Origin_Y,
            Shape.Corner_X_X, Shape.Corner_X_Y, Ink, Width);
      Line (Onto, Shape.Corner_X_X, Shape.Corner_X_Y,
            Shape.Corner_Opposite_X, Shape.Corner_Opposite_Y, Ink, Width);
      Line (Onto, Shape.Corner_Opposite_X, Shape.Corner_Opposite_Y,
            Shape.Corner_Y_X, Shape.Corner_Y_Y, Ink, Width);
      Line (Onto, Shape.Corner_Y_X, Shape.Corner_Y_Y,
            Shape.Corner_Origin_X, Shape.Corner_Origin_Y, Ink, Width);
   end Outline;

   procedure Outline
     (Onto  : in out Picture;
      Shape : AMV.Shapes.Ks_Circle;
      Ink   : Colour;
      Width : Real := 1.5) is
   begin
      Circle (Onto, Shape.Center_X, Shape.Center_Y, Shape.Radius, Ink,
              Width);
   end Outline;

   ---------------------------------------------------------------------
   --  Text
   ---------------------------------------------------------------------

   type Glyph is array (1 .. 7) of Natural;
   --  The rows from the top, the left dot being the bit of weight 16.

   Blank : constant Glyph := [others => 0];

   function Glyph_Of (C : Character) return Glyph is
     (case Ada.Characters.Handling.To_Upper (C) is
         when '0' => [14, 17, 19, 21, 25, 17, 14],
         when '1' => [4, 12, 4, 4, 4, 4, 14],
         when '2' => [14, 17, 1, 2, 4, 8, 31],
         when '3' => [31, 2, 4, 2, 1, 17, 14],
         when '4' => [2, 6, 10, 18, 31, 2, 2],
         when '5' => [31, 16, 30, 1, 1, 17, 14],
         when '6' => [6, 8, 16, 30, 17, 17, 14],
         when '7' => [31, 1, 2, 4, 8, 8, 8],
         when '8' => [14, 17, 17, 14, 17, 17, 14],
         when '9' => [14, 17, 17, 15, 1, 2, 12],
         when 'A' => [14, 17, 17, 31, 17, 17, 17],
         when 'B' => [30, 17, 17, 30, 17, 17, 30],
         when 'C' => [14, 17, 16, 16, 16, 17, 14],
         when 'D' => [28, 18, 17, 17, 17, 18, 28],
         when 'E' => [31, 16, 16, 30, 16, 16, 31],
         when 'F' => [31, 16, 16, 30, 16, 16, 16],
         when 'G' => [14, 17, 16, 23, 17, 17, 15],
         when 'H' => [17, 17, 17, 31, 17, 17, 17],
         when 'I' => [14, 4, 4, 4, 4, 4, 14],
         when 'J' => [7, 2, 2, 2, 2, 18, 12],
         when 'K' => [17, 18, 20, 24, 20, 18, 17],
         when 'L' => [16, 16, 16, 16, 16, 16, 31],
         when 'M' => [17, 27, 21, 21, 17, 17, 17],
         when 'N' => [17, 17, 25, 21, 19, 17, 17],
         when 'O' => [14, 17, 17, 17, 17, 17, 14],
         when 'P' => [30, 17, 17, 30, 16, 16, 16],
         when 'Q' => [14, 17, 17, 17, 21, 18, 13],
         when 'R' => [30, 17, 17, 30, 20, 18, 17],
         when 'S' => [15, 16, 16, 14, 1, 1, 30],
         when 'T' => [31, 4, 4, 4, 4, 4, 4],
         when 'U' => [17, 17, 17, 17, 17, 17, 14],
         when 'V' => [17, 17, 17, 17, 17, 10, 4],
         when 'W' => [17, 17, 17, 21, 21, 21, 10],
         when 'X' => [17, 17, 10, 4, 10, 17, 17],
         when 'Y' => [17, 17, 17, 10, 4, 4, 4],
         when 'Z' => [31, 1, 2, 4, 8, 16, 31],
         when '.' => [0, 0, 0, 0, 0, 12, 12],
         when ',' => [0, 0, 0, 0, 12, 4, 8],
         when '-' => [0, 0, 0, 31, 0, 0, 0],
         when '+' => [0, 4, 4, 31, 4, 4, 0],
         when ':' => [0, 12, 12, 0, 12, 12, 0],
         when '=' => [0, 0, 31, 0, 31, 0, 0],
         when '/' => [0, 1, 2, 4, 8, 16, 0],
         when '(' => [2, 4, 8, 8, 8, 4, 2],
         when ')' => [8, 4, 2, 2, 2, 4, 8],
         when '%' => [24, 25, 2, 4, 8, 19, 3],
         when '#' => [10, 10, 31, 10, 31, 10, 10],
         when others => Blank);

   Paper : constant Colour := (20, 20, 20);

   procedure Put
     (Onto   : in out Picture;
      Left   : Integer;
      Top    : Integer;
      Item   : String;
      Ink    : Colour;
      Size   : Positive);
   --  Item with the top left corner of its box at picture pixel
   --  (Left, Top), moved as far as needed to stay inside the picture.

   procedure Put
     (Onto   : in out Picture;
      Left   : Integer;
      Top    : Integer;
      Item   : String;
      Ink    : Colour;
      Size   : Positive)
   is
      Wide : constant Natural := (6 * Item'Length + 1) * Size;
      High : constant Positive := 9 * Size;
      X0   : constant Integer :=
        Integer'Max (0, Integer'Min (Left, Onto.Pixels.Width - Wide));
      Y0   : constant Integer :=
        Integer'Max (0, Integer'Min (Top, Onto.Pixels.Height - High));
      Rows : Glyph;
   begin
      for J in Y0 .. Y0 + High - 1 loop
         for I in X0 .. X0 + Wide - 1 loop
            Blend (Onto, I, J, Paper, 0.75);
         end loop;
      end loop;
      for K in Item'Range loop
         Rows := Glyph_Of (Item (K));
         for Row in Rows'Range loop
            for Column in 0 .. 4 loop
               if (Rows (Row) / 2 ** (4 - Column)) mod 2 = 1 then
                  for J in 0 .. Size - 1 loop
                     for I in 0 .. Size - 1 loop
                        Blend
                          (Onto,
                           X0 + (6 * (K - Item'First) + 1 + Column) * Size
                           + I,
                           Y0 + Row * Size + J, Ink, 1.0);
                     end loop;
                  end loop;
               end if;
            end loop;
         end loop;
      end loop;
   end Put;

   procedure Text
     (Onto   : in out Picture;
      X, Y   : Real;
      Item   : String;
      Ink    : Colour;
      Size   : Positive := 2;
      DX, DY : Integer := 0) is
   begin
      Put (Onto, Integer (PX (Onto, X)) + DX, Integer (PY (Onto, Y)) + DY,
           Item, Ink, Size);
   end Text;

   procedure Caption
     (Onto : in out Picture;
      Row  : Natural;
      Item : String;
      Ink  : Colour := White;
      Size : Positive := 2) is
   begin
      Put (Onto, 0, Row * 9 * Size, Item, Ink, Size);
   end Caption;

   ---------------------------------------------------------------------
   --  Joining
   ---------------------------------------------------------------------

   Gap_Grey : constant Grey_8 := 32;

   procedure Copy
     (From : Picture; Onto : in out Picture; Left, Top : Natural);
   --  Copies From into Onto with its top left corner at picture pixel
   --  (Left, Top).

   procedure Copy
     (From : Picture; Onto : in out Picture; Left, Top : Natural)
   is
      R, G, B : Grey_8;
   begin
      for J in 0 .. From.Pixels.Height - 1 loop
         for I in 0 .. From.Pixels.Width - 1 loop
            From.Pixels.Get_Pixel (I, J, R, G, B);
            Onto.Pixels.Set_Pixel (Left + I, Top + J, R, G, B);
         end loop;
      end loop;
   end Copy;

   function Beside
     (Left, Right : Picture; Gap : Natural := 6) return Picture
   is
      Result : Picture :=
        (Pixels => Create
           (Left.Pixels.Width + Gap + Right.Pixels.Width,
            Positive'Max (Left.Pixels.Height, Right.Pixels.Height),
            Gap_Grey, Gap_Grey, Gap_Grey),
         Left   => Left.Left,
         Top    => Left.Top,
         Scale  => Left.Scale);
   begin
      Copy (Left, Result, 0, 0);
      Copy (Right, Result, Left.Pixels.Width + Gap, 0);
      return Result;
   end Beside;

   function Above
     (Top, Bottom : Picture; Gap : Natural := 6) return Picture
   is
      Result : Picture :=
        (Pixels => Create
           (Positive'Max (Top.Pixels.Width, Bottom.Pixels.Width),
            Top.Pixels.Height + Gap + Bottom.Pixels.Height,
            Gap_Grey, Gap_Grey, Gap_Grey),
         Left   => Top.Left,
         Top    => Top.Top,
         Scale  => Top.Scale);
   begin
      Copy (Top, Result, 0, 0);
      Copy (Bottom, Result, 0, Top.Pixels.Height + Gap);
      return Result;
   end Above;

   function Width (Item : Picture) return Positive is (Item.Pixels.Width);

   function Height (Item : Picture) return Positive is (Item.Pixels.Height);

   procedure Write (Item : Picture; File_Name : String) is
   begin
      AMV.Image_File.Write_Image (File_Name, Item.Pixels);
   end Write;

end Example_Draw;
