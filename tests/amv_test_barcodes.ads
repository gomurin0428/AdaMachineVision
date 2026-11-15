--  Synthetic barcodes with known contents for the code reader tests.
--
--  The encoders here are written from the symbology definitions and share
--  nothing with the decoders of AMV.Kernels.Code_Reader: the EAN/UPC
--  digits are the module patterns of the three number sets, Code 39 and
--  Interleaved 2 of 5 are built from their two-of-five structure, and
--  Code 128 uses its own copy of the pattern table. A symbol is a list of
--  run widths in modules (bar, space, bar, ..., bar), which Draw paints
--  with AMV_Test_Images at any centre, module size and rotation.
--
--  The encoders check nothing about their input beyond what they need to
--  encode it, so that tests can also build symbols with a wrong check
--  digit. Characters or lengths a symbology cannot encode raise
--  Constraint_Error.

with AMV;
with AMV.Images;

package AMV_Test_Barcodes is

   use AMV;

   type Width_List is array (Positive range <>) of Real;
   --  The runs of a symbol in modules, without its light margins: bar,
   --  space, bar, ..., bar (an odd number of runs).

   function Total (Widths : Width_List) return Real;
   --  The length of the symbol in modules.

   ---------------------------------------------------------------------
   --  EAN and UPC
   ---------------------------------------------------------------------

   function Check_Digit (Digit_Text : String) return Character;
   --  The modulo 10 check digit that follows the digits of Digit_Text
   --  (weights 3, 1, 3, ... from the last digit): for the first 12 digits
   --  of an EAN-13 symbol, the first 7 of EAN-8, the first 11 of UPC-A
   --  and the digits of an ITF symbol.

   function EAN_13 (Digit_Text : String) return Width_List;
   --  13 digits, the last one being the check digit (encoded as given).

   function EAN_8 (Digit_Text : String) return Width_List;
   --  8 digits.

   function UPC_A (Digit_Text : String) return Width_List;
   --  12 digits.

   function UPC_E_Check_Digit (Digit_Text : String) return Character;
   --  The check digit of a UPC-E symbol with the number system (0 or 1)
   --  and the six digits of Digit_Text: that of the UPC-A number the
   --  seven digits stand for.

   function UPC_E (Digit_Text : String) return Width_List;
   --  8 digits: the number system (0 or 1), six digits and the check
   --  digit (which selects the parities, as given).

   ---------------------------------------------------------------------
   --  Code 128
   ---------------------------------------------------------------------

   type Value_List is array (Positive range <>) of Natural;
   --  Symbol values, 0 .. 105.

   Start_A : constant := 103;
   Start_B : constant := 104;
   Start_C : constant := 105;
   Code_A  : constant := 101;   --  in code sets B and C
   Code_B  : constant := 100;   --  in code sets A and C
   Code_C  : constant := 99;    --  in code sets A and B
   Shift   : constant := 98;    --  in code sets A and B
   FNC_1   : constant := 102;
   FNC_2   : constant := 97;    --  in code sets A and B
   FNC_3   : constant := 96;    --  in code sets A and B
   FNC_4_A : constant := 101;   --  in code set A
   FNC_4_B : constant := 100;   --  in code set B

   function Code_128
     (Values      : Value_List;
      Check_Error : Natural := 0) return Width_List;
   --  The symbol with the values of Values (the start character first),
   --  followed by its check character and the stop character.
   --  Check_Error is added to the check character (modulo 103), for
   --  symbols that must not be read.

   function Code_128_B (Text : String) return Width_List;
   --  Text (characters 32 .. 127) in code set B.

   function Code_128_C (Digit_Text : String) return Width_List;
   --  An even number of digits in code set C.

   ---------------------------------------------------------------------
   --  Code 39 and Interleaved 2 of 5
   ---------------------------------------------------------------------

   function Code_39_Check (Text : String) return Character;
   --  The modulo 43 check character of Text.

   function Code_39 (Text : String; Ratio : Real := 3.0) return Width_List;
   --  Text between the start and stop characters, wide runs Ratio modules
   --  wide, the gap between characters one module.

   function ITF (Digit_Text : String; Ratio : Real := 3.0) return Width_List;
   --  An even number of digits between the start and stop patterns.

   ---------------------------------------------------------------------
   --  Drawing
   ---------------------------------------------------------------------

   procedure Draw
     (Image              : in out AMV.Images.Ks_Image_8_Grey;
      Widths             : Width_List;
      Center_X, Center_Y : Real;
      Module             : Real;
      Height             : Real;
      Rotation           : Real := 0.0;
      Dark               : AMV.Images.Grey_8 := 0;
      Bar_Growth         : Real := 0.0);
   --  Paints the bars of the symbol with value Dark: the symbol is
   --  Total (Widths) * Module pixels long and Height pixels tall, centred
   --  on (Center_X, Center_Y), and runs from its first bar to its last
   --  along the direction Rotation (radians). Bar_Growth widens every bar
   --  by that many pixels (half on each side) at the cost of the spaces:
   --  ink spread, or ink loss when negative. The light margins are
   --  whatever the image holds around the symbol.

   procedure Blur
     (Image : in out AMV.Images.Ks_Image_8_Grey;
      Sigma : Real);
   --  Smooths the image with a Gaussian of standard deviation Sigma
   --  pixels (cut at three Sigma; the border pixels are repeated outside
   --  the image). Sigma <= 0.0 changes nothing.

   procedure Sharpen
     (Image  : in out AMV.Images.Ks_Image_8_Grey;
      Sigma  : Real;
      Amount : Real);
   --  An unsharp mask, as cameras and photo software apply: adds to
   --  every level Amount times what it differs from the image smoothed
   --  with Blur (Image, Sigma), which puts an overshoot on both sides of
   --  every edge (the levels stay in 0 .. 255).

   procedure Shade
     (Image       : in out AMV.Images.Ks_Image_8_Grey;
      Left, Right : Real);
   --  Scales the levels by a factor that goes linearly from Left at the
   --  first column to Right at the last: uneven lighting.

end AMV_Test_Barcodes;
