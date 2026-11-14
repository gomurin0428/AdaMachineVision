--  Drawing for the examples: a colour picture made from a grey image (all
--  of it or a part, enlarged or reduced) on which an example draws what
--  the tools found, to be written to a file and looked at.
--
--  Positions and lengths are given in the grey image's pixel space (the
--  centre of pixel (X, Y) is at (X, Y)), so a result is drawn as the tool
--  reports it whatever the picture's scale; line widths, mark sizes and
--  text sizes are in picture pixels. Lines are anti-aliased.
--
--  This is plain Ada for the examples only: AMV itself models geometry,
--  not graphics.

with AMV;
with AMV.Images;
with AMV.Shapes;

package Example_Draw is

   subtype Real is AMV.Real;

   type Colour is record
      R, G, B : AMV.Images.Grey_8;
   end record;

   Green   : constant Colour := (60, 230, 80);
   Red     : constant Colour := (255, 70, 60);
   Yellow  : constant Colour := (255, 220, 40);
   Cyan    : constant Colour := (60, 210, 255);
   Magenta : constant Colour := (255, 90, 230);
   Orange  : constant Colour := (255, 150, 30);
   White   : constant Colour := (255, 255, 255);

   type Picture is private;

   function Create
     (Image : AMV.Images.Ks_Image_8_Grey;
      Scale : Real := 1.0) return Picture;
   --  The whole image, Scale picture pixels for each image pixel. A scale
   --  below 1 averages the image pixels under each picture pixel; a scale
   --  above 1 repeats them, so that single pixels stay visible.

   function Create
     (Image         : AMV.Images.Ks_Image_8_Grey;
      X, Y          : Integer;
      Width, Height : Positive;
      Scale         : Real := 1.0) return Picture;
   --  The part of the image that is Width x Height pixels from pixel
   --  (X, Y) on; what lies outside the image is black.

   procedure Line
     (Onto           : in out Picture;
      X0, Y0, X1, Y1 : Real;
      Ink            : Colour;
      Width          : Real := 1.5);

   procedure Circle
     (Onto                     : in out Picture;
      Center_X, Center_Y, Radius : Real;
      Ink                      : Colour;
      Width                    : Real := 1.5);

   procedure Dot
     (Onto : in out Picture;
      X, Y : Real;
      Ink  : Colour;
      Size : Real := 2.0);
   --  A filled disc of radius Size.

   procedure Cross
     (Onto  : in out Picture;
      X, Y  : Real;
      Ink   : Colour;
      Size  : Real := 6.0;
      Width : Real := 1.5);
   --  A + whose arms are Size long.

   procedure Outline
     (Onto  : in out Picture;
      Shape : AMV.Shapes.Ks_Polygon;
      Ink   : Colour;
      Width : Real := 1.5);

   procedure Outline
     (Onto  : in out Picture;
      Shape : AMV.Shapes.Ks_Rectangle_Affine;
      Ink   : Colour;
      Width : Real := 1.5);

   procedure Outline
     (Onto  : in out Picture;
      Shape : AMV.Shapes.Ks_Circle;
      Ink   : Colour;
      Width : Real := 1.5);

   procedure Text
     (Onto   : in out Picture;
      X, Y   : Real;
      Item   : String;
      Ink    : Colour;
      Size   : Positive := 2;
      DX, DY : Integer := 0);
   --  Item in a 5 x 7 dot font (capitals, digits and a few signs; small
   --  letters are drawn as capitals), each dot Size picture pixels wide,
   --  on a dark box. The text's top left corner is at (X, Y), moved by
   --  (DX, DY) picture pixels; it is kept inside the picture.

   procedure Caption
     (Onto : in out Picture;
      Row  : Natural;
      Item : String;
      Ink  : Colour := White;
      Size : Positive := 2);
   --  Item in the picture's top left corner, on text row Row (0 is the
   --  first).

   function Beside
     (Left, Right : Picture; Gap : Natural := 6) return Picture;
   function Above
     (Top, Bottom : Picture; Gap : Natural := 6) return Picture;
   --  The two pictures next to each other, Gap picture pixels apart, for
   --  a picture that shows several steps or several images. What is drawn
   --  on the result afterwards is placed as on the first picture.

   function Width (Item : Picture) return Positive;
   function Height (Item : Picture) return Positive;
   --  The size in picture pixels.

   procedure Write (Item : Picture; File_Name : String);
   --  Writes the picture (a .bmp or .ppm name).

private

   type Picture is record
      Pixels : AMV.Images.Ks_Image_24_Planar_Color;
      Left   : Real := -0.5;
      Top    : Real := -0.5;
      --  The image coordinates of the picture's top left corner.
      Scale  : Real := 1.0;
   end record;

end Example_Draw;
