--  Tests for the Data Matrix symbols of AMV.Code_Reader: from an image
--  to the texts and the corners of its symbols.
--
--  The symbols are built and drawn by AMV_Test_Data_Matrix, an encoder
--  that shares only the table of the sizes with the kernel that reads
--  them (tests/test_code_reader_2d.adb checks both against published
--  values and against each other, without an image). A test here draws a
--  symbol between four known corners, runs the tool and compares the
--  text, the corners, the centre and the angle with what was drawn.
--
--  The rotations of a series are spread over the full turn in steps of
--  23 or 47 degrees, and every second symbol of a series is mirrored, as
--  a symbol is seen from behind a transparent material.

with Ada.Calendar;
with Ada.Numerics.Long_Elementary_Functions;
with Ada.Text_IO;

with AMV;                    use AMV;
with AMV.Code_Reader;        use AMV.Code_Reader;
with AMV.Coordinate_Spaces;  use AMV.Coordinate_Spaces;
with AMV.Images;             use AMV.Images;
with AMV.Images.Kernel_Images;
with AMV.Kernels;
with AMV.Kernels.Code_Reader.Data_Matrix;
with AMV.Kernels.Images;
with AMV.Kernels.Regions;
with AMV.Kernels.Transforms;
with AMV.Shapes;              use AMV.Shapes;
with AMV.Shapes.Region_Holders;
with AMV.Tools;              use AMV.Tools;
with AMV.Transforms;         use AMV.Transforms;
with AMV_Test_Barcodes;
with AMV_Test_Data_Matrix;
with AMV_Test_Images;
with AMV_Test_Support;       use AMV_Test_Support;

procedure Test_Code_Reader_Data_Matrix is

   package BC renames AMV_Test_Barcodes;
   package DM renames AMV.Kernels.Code_Reader.Data_Matrix;
   package EF renames Ada.Numerics.Long_Elementary_Functions;
   package Enc renames AMV_Test_Data_Matrix;
   package K renames AMV.Kernels;
   package KI renames AMV.Kernels.Images;
   package KR renames AMV.Kernels.Regions;
   package KT renames AMV.Kernels.Transforms;
   package RH renames AMV.Shapes.Region_Holders;
   package TI renames AMV_Test_Images;
   --  KC is AMV.Kernels.Code_Reader (renamed in AMV.Code_Reader).

   use type K.Int32;

   Pi : constant := Ada.Numerics.Pi;

   Defaults : constant Ks_Code_Reader := (others => <>);

   Matrix_Only : constant Ks_Code_Reader :=
     (Defaults with delta Symbologies => Code (Data_Matrix));

   Everything : constant Ks_Code_Reader :=
     (Defaults with delta Symbologies => All_Symbologies);

   Corner_Tolerance : constant := 2.0;
   Centre_Tolerance : constant := 2.0;
   Angle_Tolerance  : constant := 0.07;
   --  Pixels and radians, for symbols with modules of 3 pixels or more:
   --  a corner of a rotated symbol is cut off by the pixels, and the
   --  upper right corner, whose module is light, is where the lines of
   --  the two alternating sides meet.

   ---------------------------------------------------------------------
   --  Helpers
   ---------------------------------------------------------------------

   function Img (X : Real) return String;
   --  X with two decimals.

   function Img (X : Real) return String is
      Hundredths : constant Long_Long_Integer :=
        Long_Long_Integer (Real'Rounding (abs X * 100.0));
      Units      : constant String := Long_Long_Integer'Image
        (Hundredths / 100);
      Cents      : constant String := Long_Long_Integer'Image
        (100 + Hundredths mod 100);
   begin
      return (if X < 0.0 then " -" else " ")
        & Units (Units'First + 1 .. Units'Last) & "."
        & Cents (Cents'Last - 1 .. Cents'Last);
   end Img;

   function Some_Text (Length : Positive; Seed : Natural) return String;
   --  Length capital letters that differ from one seed to the next.

   function Some_Text (Length : Positive; Seed : Natural) return String is
      Result : String (1 .. Length);
   begin
      for I in Result'Range loop
         Result (I) :=
           Character'Val (65 + (Seed * 7 + I * 11 + I / 7) mod 26);
      end loop;
      return Result;
   end Some_Text;

   function Shown (Text : String) return String;
   --  The text, or its beginning, without control characters.

   function Shown (Text : String) return String is
      Last   : constant Natural :=
        Natural'Min (Text'Last, Text'First + 23);
      Result : String := Text (Text'First .. Last);
   begin
      for C of Result loop
         if C not in ' ' .. '~' then
            C := '?';
         end if;
      end loop;
      return Result & (if Last < Text'Last then "..." else "");
   end Shown;

   function Found (Tool : Ks_Code_Reader_Tool) return String;
   --  What a run gave, for the description of a failed check.

   function Found (Tool : Ks_Code_Reader_Tool) return String is
      function List (From : Natural) return String is
        (if From >= Tool.Results.Count then ""
         else " " & Symbology (Tool.Results.Item (From))'Image & " ["
              & Shown (Text (Tool.Results, From)) & "]"
              & List (From + 1));
   begin
      if Tool.Run_Status.Result /= Accept_Result then
         return " (" & Tool.Run_Status.Result'Image & " "
           & Exception_Name (Tool.Run_Status) & " "
           & Message (Tool.Run_Status) & ")";
      else
         return " (found" & Tool.Results.Count'Image & ":" & List (0) & ")";
      end if;
   end Found;

   function Run_On
     (Image  : Ks_Image_8_Grey;
      Params : Ks_Code_Reader := Matrix_Only) return Ks_Code_Reader_Tool;
   --  A tool that has run on Image with Params.

   function Run_On
     (Image  : Ks_Image_8_Grey;
      Params : Ks_Code_Reader := Matrix_Only) return Ks_Code_Reader_Tool is
   begin
      return Tool : Ks_Code_Reader_Tool do
         Tool.Input_Image := Image;
         Tool.Run_Params := Params;
         Tool.Run;
      end return;
   end Run_On;

   function Is_Matrix
     (Tool     : Ks_Code_Reader_Tool;
      Index    : Natural;
      Expected : String) return Boolean
   is (Index < Tool.Results.Count
       and then Tool.Results.Item (Index).Symbology = Code (Data_Matrix)
       and then Tool.Results.Item (Index).Length = Expected'Length
       and then Tool.Results.Item (Index).Num_Scan_Lines = 0
       and then Text (Tool.Results, Index) = Expected);
   --  Result Index is a Data Matrix symbol with that text.

   function Is_Only
     (Tool     : Ks_Code_Reader_Tool;
      Expected : String) return Boolean
   is (Tool.Run_Status.Result = Accept_Result
       and then Tool.Results.Count = 1
       and then Is_Matrix (Tool, 0, Expected));
   --  The run read that Data Matrix symbol and nothing else.

   procedure Check_Only
     (Tool        : Ks_Code_Reader_Tool;
      Expected    : String;
      Description : String);

   procedure Check_Only
     (Tool        : Ks_Code_Reader_Tool;
      Expected    : String;
      Description : String) is
   begin
      Check (Is_Only (Tool, Expected), Description & Found (Tool));
   end Check_Only;

   procedure Check_None
     (Tool        : Ks_Code_Reader_Tool;
      Description : String);
   --  The run succeeded and read nothing.

   procedure Check_None
     (Tool        : Ks_Code_Reader_Tool;
      Description : String) is
   begin
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Count = 0,
             Description & Found (Tool));
   end Check_None;

   function Status_Is
     (Tool                : Ks_Code_Reader_Tool;
      Exception_Name_Part : String;
      Message             : String) return Boolean
   is (Tool.Run_Status.Result = Error
       and then AMV.Tools.Exception_Name (Tool.Run_Status)
                  = "AMV." & Exception_Name_Part
       and then AMV.Tools.Message (Tool.Run_Status) = Message);

   function Angle_Difference (A, B : Real) return Real;
   --  The size of the angle between the directions A and B, in 0 .. Pi.

   function Angle_Difference (A, B : Real) return Real is
      D : Real := abs (A - B);
   begin
      while D > Pi loop
         D := abs (D - 2.0 * Pi);
      end loop;
      return D;
   end Angle_Difference;

   function Distance (X1, Y1, X2, Y2 : Real) return Real is
     (EF.Sqrt ((X1 - X2) ** 2 + (Y1 - Y2) ** 2));

   type Pose_Errors is record
      Corners : Real := 0.0;
      --  The largest distance of a corner from the corner drawn, in
      --  pixels.
      Centre  : Real := 0.0;
      --  The distance of the centre from where the diagonals of the
      --  symbol drawn cross.
      Angle   : Real := 0.0;
      --  The angle to the lower side drawn, in radians.
   end record;

   function Pose_Of
     (Result : Ks_Code_Reader_Result;
      Where  : Enc.Corners) return Pose_Errors;

   function Pose_Of
     (Result : Ks_Code_Reader_Result;
      Where  : Enc.Corners) return Pose_Errors
   is
      Middle : constant Enc.Place := Enc.Middle (Where);
   begin
      return
        (Corners =>
           Real'Max
             (Real'Max
                (Distance (Result.Corner_0_X, Result.Corner_0_Y,
                           Where.Upper_Left.X, Where.Upper_Left.Y),
                 Distance (Result.Corner_1_X, Result.Corner_1_Y,
                           Where.Upper_Right.X, Where.Upper_Right.Y)),
              Real'Max
                (Distance (Result.Corner_2_X, Result.Corner_2_Y,
                           Where.Lower_Right.X, Where.Lower_Right.Y),
                 Distance (Result.Corner_3_X, Result.Corner_3_Y,
                           Where.Lower_Left.X, Where.Lower_Left.Y))),
         Centre  =>
           Distance (Result.Center_X, Result.Center_Y, Middle.X, Middle.Y),
         Angle   =>
           Angle_Difference
             (Result.Angle,
              EF.Arctan (Where.Lower_Right.Y - Where.Lower_Left.Y,
                         Where.Lower_Right.X - Where.Lower_Left.X)));
   end Pose_Of;

   function Pose_OK (E : Pose_Errors) return Boolean is
     (E.Corners <= Corner_Tolerance and then E.Centre <= Centre_Tolerance
      and then E.Angle <= Angle_Tolerance);

   function Img (E : Pose_Errors) return String is
     (" (corners" & Img (E.Corners) & ", centre" & Img (E.Centre)
      & " pixels, angle" & Img (E.Angle * 1000.0) & " mrad)");

   function Worse (A, B : Pose_Errors) return Pose_Errors is
     (Corners => Real'Max (A.Corners, B.Corners),
      Centre  => Real'Max (A.Centre, B.Centre),
      Angle   => Real'Max (A.Angle, B.Angle));

   procedure Skew (Where : in out Enc.Corners; Share : Real);
   --  The symbol as it is seen at an angle: its upper right corner
   --  pulled towards its middle by Share of the way and its lower right
   --  one by half of that.

   procedure Skew (Where : in out Enc.Corners; Share : Real) is
      M : constant Enc.Place := Enc.Middle (Where);
   begin
      Where.Upper_Right :=
        (Where.Upper_Right.X + Share * (M.X - Where.Upper_Right.X),
         Where.Upper_Right.Y + Share * (M.Y - Where.Upper_Right.Y));
      Where.Lower_Right :=
        (Where.Lower_Right.X + 0.5 * Share * (M.X - Where.Lower_Right.X),
         Where.Lower_Right.Y + 0.5 * Share * (M.Y - Where.Lower_Right.Y));
   end Skew;

   function Side_Of (Size : DM.Size_Index; Module : Real) return Positive;
   --  The side of a square image that holds a symbol of that size with
   --  modules of Module pixels at any rotation, with a margin of 20
   --  pixels.

   function Side_Of (Size : DM.Size_Index; Module : Real) return Positive is
      Wide : constant Real := Real (DM.Sizes (Size).Columns) * Module;
      High : constant Real := Real (DM.Sizes (Size).Rows) * Module;
   begin
      return Positive (EF.Sqrt (Wide ** 2 + High ** 2)) + 40;
   end Side_Of;

   function Centred
     (Size     : DM.Size_Index;
      Module   : Real;
      Rotation : Real := 0.0;
      Mirror   : Boolean := False) return Enc.Corners;
   --  Where a symbol lies in the image of Side_Of: its middle a little
   --  off the middle of the image, so that the modules do not fall on
   --  the pixels.

   function Centred
     (Size     : DM.Size_Index;
      Module   : Real;
      Rotation : Real := 0.0;
      Mirror   : Boolean := False) return Enc.Corners
   is
      Side : constant Real := Real (Side_Of (Size, Module));
   begin
      return Enc.Placed
        (Side / 2.0 + 0.3, Side / 2.0 - 0.2,
         Real (DM.Sizes (Size).Columns) * Module,
         Real (DM.Sizes (Size).Rows) * Module, Rotation, Mirror);
   end Centred;

   type Size_List is array (Positive range <>) of DM.Size_Index;

   Some_Sizes : constant Size_List := [1, 3, 6, 10, 14, 18, 24, 25, 28, 30];
   --  10 x 10, 14 x 14, 20 x 20, 32 x 32, 48 x 48, 80 x 80, 144 x 144,
   --  8 x 18, 12 x 36 and 16 x 48.

   Small_Sizes : constant Size_List := [1, 3, 6, 10, 25, 28];

   procedure Check_Series
     (Name   : String;
      Sizes  : Size_List;
      Module : Real;
      Turns  : Positive := 8;
      Step   : Real := 47.0;
      Params : Ks_Code_Reader := Matrix_Only;
      Dark   : Grey_8 := 0;
      Light  : Grey_8 := 255;
      Skewed : Real := 0.0;
      Spoil  : access procedure
        (Image : in out Ks_Image_8_Grey;
         Seed  : Positive) := null);
   --  Reads a symbol of every size of Sizes at Turns rotations, Step
   --  degrees apart (every second one mirrored), with modules of Module
   --  pixels, drawn with the level Dark on the level Light and then
   --  changed by Spoil. Checks that every symbol is read with its text
   --  and nothing else is, and that the corners, the centre and the
   --  angle are those drawn.

   procedure Check_Series
     (Name   : String;
      Sizes  : Size_List;
      Module : Real;
      Turns  : Positive := 8;
      Step   : Real := 47.0;
      Params : Ks_Code_Reader := Matrix_Only;
      Dark   : Grey_8 := 0;
      Light  : Grey_8 := 255;
      Skewed : Real := 0.0;
      Spoil  : access procedure
        (Image : in out Ks_Image_8_Grey;
         Seed  : Positive) := null)
   is
      Total, Read, Wrong : Natural := 0;
      Worst              : Pose_Errors;
   begin
      for Size of Sizes loop
         for Turn in 0 .. Turns - 1 loop
            declare
               Expect : constant String :=
                 Some_Text (DM.Sizes (Size).Data - 1, Turn);
               Side   : constant Positive := Side_Of (Size, Module);
               Where  : Enc.Corners :=
                 Centred (Size, Module, Real (Turn) * Step * Pi / 180.0,
                          Turn mod 2 = 1);
               Image  : Ks_Image_8_Grey := TI.Blank (Side, Side, Light);
               Tool   : Ks_Code_Reader_Tool;
            begin
               Skew (Where, Skewed);
               Enc.Draw (Image, Enc.Symbol (Enc.ASCII (Expect), Size),
                         Where, Dark);
               if Spoil /= null then
                  Spoil (Image, Turn + 1);
               end if;
               Tool := Run_On (Image, Params);
               Total := Total + 1;
               if Is_Only (Tool, Expect) then
                  Read := Read + 1;
                  Worst :=
                    Worse (Worst, Pose_Of (Tool.Results.Item (0), Where));
               else
                  if Tool.Run_Status.Result /= Accept_Result
                    or else Tool.Results.Count > 0
                  then
                     Wrong := Wrong + 1;
                  end if;
                  Ada.Text_IO.Put_Line
                    ("  " & Name & ", size" & Size'Image & ", turn"
                     & Turn'Image & ":" & Found (Tool));
               end if;
            end;
         end loop;
      end loop;
      Check (Read = Total and then Wrong = 0,
             Name & ": every symbol read, no other text (read" & Read'Image
             & " of" & Total'Image & ", wrong" & Wrong'Image & ")");
      Check (Pose_OK (Worst),
             Name & ": the corners, the centre and the angle" & Img (Worst));
   end Check_Series;

   ---------------------------------------------------------------------
   --  Every size
   ---------------------------------------------------------------------

   procedure Test_Sizes is
      Squares    : Size_List (1 .. 24);
      Rectangles : Size_List (1 .. 6);
      Extended   : Size_List (1 .. 18);
   begin
      Section ("CodeReader: Data Matrix symbols of every size");
      for I in Squares'Range loop
         Squares (I) := I;
      end loop;
      for I in Rectangles'Range loop
         Rectangles (I) := 24 + I;
      end loop;
      for I in Extended'Range loop
         Extended (I) := 30 + I;
      end loop;
      --  With the linear barcodes looked for as well: no part of a Data
      --  Matrix symbol is read as one.
      Check_Series ("the 24 square sizes, 10 x 10 to 144 x 144", Squares,
                    Module => 4.0, Turns => 16, Step => 23.0,
                    Params => Everything);
      Check_Series ("the 6 rectangular sizes, 8 x 18 to 16 x 48",
                    Rectangles, Module => 4.0, Turns => 16, Step => 23.0,
                    Params => Everything);
      Check_Series ("the 18 sizes of the rectangular extension, 8 x 48 to "
                    & "26 x 64",
                    Extended, Module => 4.0, Turns => 16, Step => 23.0,
                    Params => Everything);
   end Test_Sizes;

   ---------------------------------------------------------------------
   --  The size of the modules
   ---------------------------------------------------------------------

   procedure Test_Modules is
   begin
      Section ("CodeReader: Data Matrix modules of 3 to 20 pixels");
      Check_Series ("modules of 3 pixels", Some_Sizes, 3.0);
      Check_Series ("modules of 3.5 pixels", Some_Sizes, 3.5);
      Check_Series ("modules of 5 pixels", Some_Sizes, 5.0);
      Check_Series ("modules of 6.3 pixels", Some_Sizes, 6.3);
      Check_Series ("modules of 9 pixels", Small_Sizes, 9.0);
      Check_Series ("modules of 20 pixels", Small_Sizes, 20.0);
   end Test_Modules;

   ---------------------------------------------------------------------
   --  Image quality
   ---------------------------------------------------------------------

   procedure Test_Quality is

      procedure Blur_Little (Image : in out Ks_Image_8_Grey; Seed : Positive);
      procedure Blur_More (Image : in out Ks_Image_8_Grey; Seed : Positive);
      procedure Noise (Image : in out Ks_Image_8_Grey; Seed : Positive);
      procedure Shading (Image : in out Ks_Image_8_Grey; Seed : Positive);

      procedure Blur_Little
        (Image : in out Ks_Image_8_Grey; Seed : Positive)
      is
         pragma Unreferenced (Seed);
      begin
         BC.Blur (Image, 0.7);
      end Blur_Little;

      procedure Blur_More (Image : in out Ks_Image_8_Grey; Seed : Positive)
      is
         pragma Unreferenced (Seed);
      begin
         BC.Blur (Image, 1.2);
      end Blur_More;

      procedure Noise (Image : in out Ks_Image_8_Grey; Seed : Positive) is
      begin
         BC.Blur (Image, 0.5);
         TI.Add_Noise (Image, 20.0, Seed);
      end Noise;

      procedure Shading (Image : in out Ks_Image_8_Grey; Seed : Positive)
      is
         pragma Unreferenced (Seed);
      begin
         BC.Blur (Image, 0.5);
         BC.Shade (Image, 1.0, 0.4);
      end Shading;
   begin
      Section ("CodeReader: Data Matrix symbols in images of less quality");
      Check_Series ("modules of 4 pixels, blurred by 0.7 pixels",
                    Some_Sizes, 4.0, Spoil => Blur_Little'Access);
      Check_Series ("modules of 6 pixels, blurred by 1.2 pixels",
                    Some_Sizes, 6.0, Spoil => Blur_More'Access);
      Check_Series ("noise of 20 levels", Some_Sizes, 4.0,
                    Spoil => Noise'Access);
      Check_Series ("the levels 100 on 130", Some_Sizes, 4.0,
                    Dark => 100, Light => 130);
      Check_Series ("the right side of the image at 0.4 of the light",
                    Some_Sizes, 4.0, Spoil => Shading'Access);
   end Test_Quality;

   ---------------------------------------------------------------------
   --  A symbol seen at an angle
   ---------------------------------------------------------------------

   procedure Test_Perspective is
   begin
      Section ("CodeReader: Data Matrix symbols seen at an angle");
      Check_Series ("a corner 10 % nearer to the middle", Some_Sizes, 4.0,
                    Skewed => 0.1);
      Check_Series ("a corner 20 % nearer to the middle", Some_Sizes, 4.0,
                    Skewed => 0.2);
      Check_Series ("a corner 30 % nearer to the middle, modules of 6 "
                    & "pixels", Some_Sizes, 6.0, Skewed => 0.3);
   end Test_Perspective;

   ---------------------------------------------------------------------
   --  The texts
   ---------------------------------------------------------------------

   function Text_Image
     (Data     : Enc.Byte_List;
      Module   : Real := 4.0;
      Rotation : Real := 0.2) return Ks_Image_8_Grey;
   --  An image of the smallest symbol with the data codewords Data,
   --  with modules of Module pixels, turned by Rotation.

   function Text_Image
     (Data     : Enc.Byte_List;
      Module   : Real := 4.0;
      Rotation : Real := 0.2) return Ks_Image_8_Grey
   is
      Symbol : constant Enc.Module_Matrix := Enc.Symbol (Data);
      Wide   : constant Real := Real (Symbol'Length (2)) * Module;
      High   : constant Real := Real (Symbol'Length (1)) * Module;
      Side   : constant Positive :=
        Positive (EF.Sqrt (Wide ** 2 + High ** 2)) + 40;
   begin
      return Image : Ks_Image_8_Grey := TI.Blank (Side, Side, 255) do
         Enc.Draw (Image, Symbol,
                   Enc.Placed (Real (Side) / 2.0 + 0.3,
                               Real (Side) / 2.0 - 0.2, Wide, High,
                               Rotation));
      end return;
   end Text_Image;

   procedure Check_Text
     (Data        : Enc.Byte_List;
      Expected    : String;
      Description : String);
   --  The symbol with the data codewords Data is read as Expected.

   procedure Check_Text
     (Data        : Enc.Byte_List;
      Expected    : String;
      Description : String) is
   begin
      Check_Only (Run_On (Text_Image (Data)), Expected, Description);
   end Check_Text;

   procedure Test_Texts is
      use type Enc.Byte_List;
      GS     : constant Character := Character'Val (29);
      RS     : constant Character := Character'Val (30);
      EOT    : constant Character := Character'Val (4);
      Every  : String (1 .. 256);
      Number : String (1 .. 3116);
      Tool   : Ks_Code_Reader_Tool;
   begin
      Section ("CodeReader: the texts of Data Matrix symbols");
      for I in Every'Range loop
         Every (I) := Character'Val (I - 1);
      end loop;
      for I in Number'Range loop
         Number (I) := Character'Val (48 + (I * 7 + I / 10) mod 10);
      end loop;

      Check_Text (Enc.ASCII ("Hello, world!"), "Hello, world!",
                  "the ASCII encodation");
      Check_Text (Enc.ASCII ("0123456789012345"), "0123456789012345",
                  "pairs of digits");
      Check_Text (Enc.ASCII (Every (120 .. 140)), Every (120 .. 140),
                  "characters above 127 (upper shift)");
      Check_Text (Enc.C40 ("AMV CODE READER 2026"), "AMV CODE READER 2026",
                  "the C40 encodation");
      Check_Text (Enc.Lower ("data matrix, ecc 200"), "data matrix, ecc 200",
                  "the Text encodation");
      Check_Text (Enc.X12 ("X12*AMV>CODE 12345"), "X12*AMV>CODE 12345",
                  "the ANSI X12 encodation");
      Check_Text (Enc.EDIFACT ("EDIFACT (A+B)*C=42?") & Enc.ASCII ("ok"),
                  "EDIFACT (A+B)*C=42?ok", "the EDIFACT encodation");
      Check_Text (Enc.Base_256 (Every (1 .. 40)), Every (1 .. 40),
                  "the Base 256 encodation");
      Check_Text (Enc.C40 ("PART") & Enc.ASCII ("-17/") & Enc.Lower ("rev")
                  & Enc.ASCII ("2"), "PART-17/rev2",
                  "several encodations in one symbol");

      --  The characters that stand for more than themselves.
      Check_Text ([1 => 232] & Enc.ASCII ("010950110153000310AB12")
                  & [1 => 232] & Enc.ASCII ("2112345"),
                  "010950110153000310AB12" & GS & "2112345",
                  "FNC1: nothing for the first, GS for a later one");
      Check_Text ([1 => 236] & Enc.ASCII ("ABC"),
                  "[)>" & RS & "05" & GS & "ABC" & RS & EOT,
                  "the macro 05");
      Check_Text ([1 => 237] & Enc.ASCII ("ABC"),
                  "[)>" & RS & "06" & GS & "ABC" & RS & EOT,
                  "the macro 06");

      --  More characters than a result record holds.
      Tool := Run_On (Text_Image (Enc.Base_256 (Every)));
      Check_Only (Tool, Every, "a text of 256 characters, every character");
      if Tool.Results.Count = 1 then
         Check (Tool.Results.Item (0).Length = 256
                and then Text (Tool.Results.Item (0)) = Every (1 .. 255),
                "its record has the length and the first 255 characters");
      end if;
      Tool := Run_On (Text_Image (Enc.ASCII (Number), 3.0));
      Check_Only (Tool, Number,
                  "3116 digits, the most that a symbol holds");
      Tool := Run_On (Text_Image (Enc.ASCII (Every (66 .. 66))));
      Check_Only (Tool, "A", "one character");
   end Test_Texts;

   ---------------------------------------------------------------------
   --  Several symbols
   ---------------------------------------------------------------------

   procedure Put_Symbol
     (Image    : in out Ks_Image_8_Grey;
      Symbol   : Enc.Module_Matrix;
      X, Y     : Real;
      Module   : Real;
      Where    : out Enc.Corners;
      Rotation : Real := 0.0;
      Mirror   : Boolean := False;
      Dark     : Grey_8 := 0);
   --  Draws the symbol with its middle at (X, Y) and modules of Module
   --  pixels. Where: its corners.

   procedure Put_Symbol
     (Image    : in out Ks_Image_8_Grey;
      Symbol   : Enc.Module_Matrix;
      X, Y     : Real;
      Module   : Real;
      Where    : out Enc.Corners;
      Rotation : Real := 0.0;
      Mirror   : Boolean := False;
      Dark     : Grey_8 := 0) is
   begin
      Where := Enc.Placed (X, Y, Real (Symbol'Length (2)) * Module,
                           Real (Symbol'Length (1)) * Module, Rotation,
                           Mirror);
      Enc.Draw (Image, Symbol, Where, Dark);
   end Put_Symbol;

   function Index_Of
     (Tool     : Ks_Code_Reader_Tool;
      Expected : String) return Integer;
   --  The index of the first Data Matrix result with that text, -1 if
   --  there is none.

   function Index_Of
     (Tool     : Ks_Code_Reader_Tool;
      Expected : String) return Integer is
   begin
      for I in 0 .. Tool.Results.Count - 1 loop
         if Is_Matrix (Tool, I, Expected) then
            return I;
         end if;
      end loop;
      return -1;
   end Index_Of;

   function Is_Linear
     (Tool     : Ks_Code_Reader_Tool;
      Index    : Natural;
      Symbol   : Ks_Code_Reader_Symbology_Constants;
      Expected : String) return Boolean
   is (Index < Tool.Results.Count
       and then Tool.Results.Item (Index).Symbology = Code (Symbol)
       and then Tool.Results.Item (Index).Num_Scan_Lines >= 2
       and then Text (Tool.Results, Index) = Expected
       and then Text (Tool.Results.Item (Index)) = Expected);
   --  Result Index is a linear barcode of that symbology and text.

   procedure Test_Several is
      Image      : Ks_Image_8_Grey := TI.Blank (640, 480, 230);
      First      : constant Enc.Module_Matrix :=
        Enc.Symbol (Enc.ASCII ("AMV-1"));
      Second     : constant Enc.Module_Matrix :=
        Enc.Symbol (Enc.C40 ("SECOND SYMBOL 0002"));
      Third      : constant Enc.Module_Matrix :=
        Enc.Symbol (Enc.ASCII ("RECT 8x32"), 26);
      W1, W2, W3 : Enc.Corners;
      Tool       : Ks_Code_Reader_Tool;
      Twice      : Ks_Image_8_Grey := TI.Blank (300, 160, 255);
   begin
      Section ("CodeReader: Data Matrix symbols and barcodes in one image");

      --  Three symbols, the first above the second and the second above
      --  the third, and two barcodes between them.
      Put_Symbol (Image, First, 110.0, 80.0, 5.0, W1, 0.3);
      Put_Symbol (Image, Second, 500.0, 190.0, 4.0, W2, -1.1,
                  Mirror => True, Dark => 40);
      Put_Symbol (Image, Third, 200.0, 400.0, 5.0, W3, 0.1);
      BC.Draw (Image, BC.EAN_13 ("5901234123457"), 150.0, 220.0, 2.0, 60.0);
      BC.Draw (Image, BC.Code_128_B ("AMV-1"), 460.0, 330.0, 2.0, 50.0);

      Tool := Run_On (Image, Everything);
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Count = 5,
             "all symbologies: five symbols" & Found (Tool));
      Check ((Is_Linear (Tool, 0, EAN_13, "5901234123457")
              and then Is_Linear (Tool, 1, Code_128, "AMV-1"))
             or else (Is_Linear (Tool, 0, Code_128, "AMV-1")
                      and then Is_Linear (Tool, 1, EAN_13,
                                          "5901234123457")),
             "the two barcodes first" & Found (Tool));
      Check (Is_Matrix (Tool, 2, "AMV-1")
             and then Is_Matrix (Tool, 3, "SECOND SYMBOL 0002")
             and then Is_Matrix (Tool, 4, "RECT 8x32"),
             "then the Data Matrix symbols, from the top of the image"
             & Found (Tool));
      if Tool.Results.Count = 5 then
         Check (Pose_OK (Pose_Of (Tool.Results.Item (2), W1)),
                "the first symbol is where it was drawn"
                & Img (Pose_Of (Tool.Results.Item (2), W1)));
         Check (Pose_OK (Pose_Of (Tool.Results.Item (3), W2)),
                "the second one, mirrored and dark grey on light grey"
                & Img (Pose_Of (Tool.Results.Item (3), W2)));
         Check (Pose_OK (Pose_Of (Tool.Results.Item (4), W3)),
                "the third one, 8 x 32 modules"
                & Img (Pose_Of (Tool.Results.Item (4), W3)));
      end if;

      Tool := Run_On (Image, Matrix_Only);
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Count = 3
             and then Is_Matrix (Tool, 0, "AMV-1")
             and then Is_Matrix (Tool, 1, "SECOND SYMBOL 0002")
             and then Is_Matrix (Tool, 2, "RECT 8x32"),
             "Data Matrix only: the three symbols" & Found (Tool));

      Tool := Run_On (Image, Defaults);
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Count = 2
             and then Index_Of (Tool, "AMV-1") < 0,
             "the default symbologies: the two barcodes" & Found (Tool));

      Tool := Run_On
        (Image, (Defaults with delta
                   Symbologies => Code (Data_Matrix) + Code (EAN_13)));
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Count = 4
             and then Is_Linear (Tool, 0, EAN_13, "5901234123457")
             and then Is_Matrix (Tool, 1, "AMV-1"),
             "Data Matrix and EAN-13: four symbols" & Found (Tool));

      --  The same symbol twice is two symbols.
      Put_Symbol (Twice, First, 80.0, 80.0, 6.0, W1, 0.2);
      Put_Symbol (Twice, First, 220.0, 80.0, 6.0, W2, -0.4);
      Tool := Run_On (Twice);
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Count = 2
             and then Is_Matrix (Tool, 0, "AMV-1")
             and then Is_Matrix (Tool, 1, "AMV-1"),
             "two symbols with the same text" & Found (Tool));
      if Tool.Results.Count = 2 then
         Check ((Pose_OK (Pose_Of (Tool.Results.Item (0), W1))
                 and then Pose_OK (Pose_Of (Tool.Results.Item (1), W2)))
                or else
                  (Pose_OK (Pose_Of (Tool.Results.Item (0), W2))
                   and then Pose_OK (Pose_Of (Tool.Results.Item (1), W1))),
                "each where it was drawn");
      end if;
   end Test_Several;

   procedure Test_Many is
      Pitch  : constant := 36;
      Symbol : constant Enc.Module_Matrix := Enc.Symbol (Enc.ASCII ("ANY"));
      --  10 x 10 modules of 3 pixels, 6 pixels apart.
      Image  : Ks_Image_8_Grey := TI.Blank (65 * Pitch, 64 * Pitch, 255);
      Where  : Enc.Corners;
      Tool   : Ks_Code_Reader_Tool;
      Good   : Boolean := True;
   begin
      Section ("CodeReader: as many Data Matrix symbols as a run holds");
      Check (Symbol'Length (1) = 10 and then Symbol'Length (2) = 10,
             "the symbol of the test has 10 x 10 modules");
      for Row in 0 .. 63 loop
         for Column in 0 .. 63 loop
            Put_Symbol (Image, Symbol, Real (Column * Pitch) + 17.5,
                        Real (Row * Pitch) + 17.5, 3.0, Where);
         end loop;
      end loop;
      Tool := Run_On (Image);
      for I in 0 .. Tool.Results.Count - 1 loop
         Good := Good and then Is_Matrix (Tool, I, "ANY");
      end loop;
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Count = 4096 and then Good,
             "4096 symbols (found" & Tool.Results.Count'Image & ", "
             & Tool.Run_Status.Result'Image & " "
             & Message (Tool.Run_Status) & ")");
      if Tool.Results.Count = 4096 then
         Check_Near (Tool.Results.Item (4095).Center_X,
                     Real (63 * Pitch) + 17.5, 1.0,
                     "the last one is the one at the lower right: x");
         Check_Near (Tool.Results.Item (4095).Center_Y,
                     Real (63 * Pitch) + 17.5, 1.0,
                     "the last one is the one at the lower right: y");
      end if;

      Put_Symbol (Image, Symbol, Real (64 * Pitch) + 17.5, 17.5, 3.0,
                  Where);
      Tool := Run_On (Image);
      Check (Status_Is (Tool, "KS_EXCEPTION",
                        "CodeReader: more than 4096 candidates")
             and then Tool.Results.Count = 0,
             "4097 symbols: the run fails and says why (found"
             & Tool.Results.Count'Image & ", "
             & Tool.Run_Status.Result'Image & " "
             & Message (Tool.Run_Status) & ")");
   end Test_Many;

   ---------------------------------------------------------------------
   --  The region
   ---------------------------------------------------------------------

   procedure Test_Region is
      Image     : Ks_Image_8_Grey := TI.Blank (640, 480, 255);
      Left      : constant Enc.Module_Matrix :=
        Enc.Symbol (Enc.ASCII ("LEFT 0001"));
      Right     : constant Enc.Module_Matrix :=
        Enc.Symbol (Enc.ASCII ("RIGHT 0002"));
      WL, WR    : Enc.Corners;
      Tool      : Ks_Code_Reader_Tool;
      Rectangle : Ks_Rectangle;
      Circle    : Ks_Circle;
   begin
      Section ("CodeReader: Data Matrix symbols and the region");

      --  Two symbols of 14 x 14 modules of 6 pixels: an upright one on
      --  the left (x in 118 .. 202, y in 198 .. 282) and a turned one on
      --  the right.
      Put_Symbol (Image, Left, 160.0, 240.0, 6.0, WL);
      Put_Symbol (Image, Right, 480.0, 240.0, 6.0, WR, 0.5);
      Tool.Input_Image := Image;
      Tool.Run_Params := Matrix_Only;
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Count = 2
             and then Is_Matrix (Tool, 0, "RIGHT 0002")
             and then Is_Matrix (Tool, 1, "LEFT 0001"),
             "no region: both symbols, first the one that reaches higher"
             & Found (Tool));

      Rectangle.Set_XY_Width_Height (0.0, 0.0, 320.0, 480.0);
      Tool.Region := RH.To_Holder (Rectangle);
      Tool.Run;
      Check_Only (Tool, "LEFT 0001", "the left half of the image");
      if Tool.Results.Count = 1 then
         Check (Pose_OK (Pose_Of (Tool.Results.Item (0), WL)),
                "the symbol is where it was drawn"
                & Img (Pose_Of (Tool.Results.Item (0), WL)));
      end if;

      Rectangle.Set_XY_Width_Height (320.0, 0.0, 320.0, 480.0);
      Tool.Region := RH.To_Holder (Rectangle);
      Tool.Run;
      Check_Only (Tool, "RIGHT 0002", "the right half of the image");
      if Tool.Results.Count = 1 then
         Check (Pose_OK (Pose_Of (Tool.Results.Item (0), WR)),
                "the symbol is where it was drawn"
                & Img (Pose_Of (Tool.Results.Item (0), WR)));
      end if;

      Rectangle.Set_XY_Width_Height (108.0, 188.0, 104.0, 104.0);
      Tool.Region := RH.To_Holder (Rectangle);
      Tool.Run;
      Check_Only (Tool, "LEFT 0001",
                  "a rectangle around the symbol and a margin");

      --  The pixels outside the region are light: the symbol needs no
      --  margin within it.
      Rectangle.Set_XY_Width_Height (116.5, 196.5, 87.0, 87.0);
      Tool.Region := RH.To_Holder (Rectangle);
      Tool.Run;
      Check_Only (Tool, "LEFT 0001",
                  "a rectangle around the symbol without a margin");

      Rectangle.Set_XY_Width_Height (0.0, 0.0, 160.0, 480.0);
      Tool.Region := RH.To_Holder (Rectangle);
      Tool.Run;
      Check_None (Tool, "a region with half of a symbol");

      Rectangle.Set_XY_Width_Height (700.0, 500.0, 50.0, 50.0);
      Tool.Region := RH.To_Holder (Rectangle);
      Tool.Run;
      Check_None (Tool, "a region outside the image");

      Rectangle.Set_XY_Width_Height (-500.0, -500.0, 820.0, 2000.0);
      Tool.Region := RH.To_Holder (Rectangle);
      Tool.Run;
      Check_Only (Tool, "LEFT 0001",
                  "a region that reaches beyond the image");

      Circle.Set_Center_Radius (160.0, 240.0, 75.0);
      Tool.Region := RH.To_Holder (Circle);
      Tool.Run;
      Check_Only (Tool, "LEFT 0001", "a circle around a symbol");

      Circle.Set_Center_Radius (160.0, 240.0, 40.0);
      Tool.Region := RH.To_Holder (Circle);
      Tool.Run;
      Check_None (Tool, "a circle smaller than the symbol");

      Tool.Region.Clear;
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Count = 2,
             "the region cleared: both symbols again" & Found (Tool));
   end Test_Region;

   ---------------------------------------------------------------------
   --  The run parameters
   ---------------------------------------------------------------------

   procedure Test_Run_Params is
      Symbol : constant Enc.Module_Matrix :=
        Enc.Symbol (Enc.ASCII ("PARAMS 12"));
      Image  : Ks_Image_8_Grey := TI.Blank (200, 160, 255);
      Faint  : Ks_Image_8_Grey := TI.Blank (200, 160, 130);
      Where  : Enc.Corners;
   begin
      Section ("CodeReader: Data Matrix symbols and the run parameters");
      Put_Symbol (Image, Symbol, 100.0, 80.0, 5.0, Where, 0.4);
      Put_Symbol (Faint, Symbol, 100.0, 80.0, 5.0, Where, 0.4, Dark => 100);

      Check (Code (Data_Matrix) = 128
             and then Defaults.Symbologies + Code (Data_Matrix)
                        = Everything.Symbologies,
             "the codes: Data Matrix is 128 and not among the defaults");
      Check_None (Run_On (Image, Defaults),
                  "the default symbologies do not read a Data Matrix "
                  & "symbol");
      Check_Only (Run_On (Image, Everything), "PARAMS 12",
                  "all symbologies do");
      Check_Only (Run_On (Image, Matrix_Only), "PARAMS 12",
                  "Data Matrix alone does");
      Check_None
        (Run_On (Image,
                 (Defaults with delta
                    Symbologies => All_Symbologies - Code (Data_Matrix))),
         "all but Data Matrix do not");

      --  The parameters of the scan lines are not those of Data Matrix.
      Check_Only
        (Run_On (Image,
                 (Matrix_Only with delta Num_Directions => 1,
                  First_Direction => 1.0, Line_Spacing => 1000.0,
                  Min_Scan_Lines => 1000)),
         "PARAMS 12", "one direction, one scan line, 1000 lines asked");

      --  The contrast: levels of 100 on 130.
      Check_Only (Run_On (Faint, Matrix_Only), "PARAMS 12",
                  "30 grey levels of contrast, the default threshold");
      Check_Only
        (Run_On (Faint, (Matrix_Only with delta Contrast_Threshold => 30)),
         "PARAMS 12", "a threshold of 30");
      Check_None
        (Run_On (Faint, (Matrix_Only with delta Contrast_Threshold => 31)),
         "a threshold of 31");
      Check_Only
        (Run_On (Image, (Matrix_Only with delta Contrast_Threshold => 255)),
         "PARAMS 12", "black on white, a threshold of 255");
   end Test_Run_Params;

   ---------------------------------------------------------------------
   --  Fixture space
   ---------------------------------------------------------------------

   procedure Test_Fixture is
      Alpha     : constant Real := 0.4;
      Scale     : constant Real := 2.0;
      Fix       : constant Ks_Transform_2D_Linear :=
        Create (Scale * EF.Cos (Alpha), -Scale * EF.Sin (Alpha),
                Scale * EF.Sin (Alpha), Scale * EF.Cos (Alpha), 30.0, 20.0);
      --  Fixture (u, v) to root (= pixel) coordinates: 2 pixels per unit.
      Tree      : Ks_Coordinate_Space_Tree;
      Symbol    : constant Enc.Module_Matrix :=
        Enc.Symbol (Enc.ASCII ("FIXTURE 2026"));
      Wide      : constant Real := Real (Symbol'Length (2)) * 3.0;
      High      : constant Real := Real (Symbol'Length (1)) * 3.0;
      In_Units  : constant Enc.Corners :=
        Enc.Placed (176.0, 45.0, Wide, High, 0.7);
      --  The symbol in the fixture: modules of 3 units, 6 pixels. In
      --  pixels it lies near the middle of the image.
      In_Pixels : Enc.Corners;
      Tool      : Ks_Code_Reader_Tool;
      Rectangle : Ks_Rectangle;
      E         : Pose_Errors;

      function Units_OK (E : Pose_Errors) return Boolean is
        (E.Corners <= Corner_Tolerance / Scale
         and then E.Centre <= Centre_Tolerance / Scale
         and then E.Angle <= Angle_Tolerance);
   begin
      Section ("CodeReader: Data Matrix symbols in fixture space");
      Tool.Input_Image := TI.Blank (640, 480, 255);
      Tool.Run_Params := Matrix_Only;
      Tree.Add_Space ("@", "Fixture", Fix);
      Tool.Input_Image.Set_Coordinate_Space_Tree (Tree);
      Tool.Input_Image.Set_Selected_Space_Name ("@\Fixture");
      Fix.Map_Point (In_Units.Upper_Left.X, In_Units.Upper_Left.Y,
                     In_Pixels.Upper_Left.X, In_Pixels.Upper_Left.Y);
      Fix.Map_Point (In_Units.Upper_Right.X, In_Units.Upper_Right.Y,
                     In_Pixels.Upper_Right.X, In_Pixels.Upper_Right.Y);
      Fix.Map_Point (In_Units.Lower_Right.X, In_Units.Lower_Right.Y,
                     In_Pixels.Lower_Right.X, In_Pixels.Lower_Right.Y);
      Fix.Map_Point (In_Units.Lower_Left.X, In_Units.Lower_Left.Y,
                     In_Pixels.Lower_Left.X, In_Pixels.Lower_Left.Y);
      Enc.Draw (Tool.Input_Image, Symbol, In_Pixels);

      Tool.Run;
      Check_Only (Tool, "FIXTURE 2026",
                  "a symbol in an image with a fixture");
      if Tool.Results.Count = 1 then
         E := Pose_Of (Tool.Results.Item (0), In_Units);
         Check (Units_OK (E), "its pose in fixture units" & Img (E));
      end if;

      --  A region in the fixture.
      Rectangle.Set_XY_Width_Height (140.0, 10.0, 72.0, 70.0);
      Tool.Region := RH.To_Holder (Rectangle);
      Tool.Run;
      Check_Only (Tool, "FIXTURE 2026",
                  "a region in the fixture around the symbol");
      Rectangle.Set_XY_Width_Height (0.0, 0.0, 60.0, 60.0);
      Tool.Region := RH.To_Holder (Rectangle);
      Tool.Run;
      Check_None (Tool, "a region in the fixture beside the symbol");

      --  A region in pixel space, results in the fixture.
      Rectangle.Set_Selected_Space_Name ("#");
      Rectangle.Set_XY_Width_Height (0.0, 0.0, 640.0, 480.0);
      Tool.Region := RH.To_Holder (Rectangle);
      Tool.Run;
      Check_Only (Tool, "FIXTURE 2026",
                  "a region in pixel space around the symbol");
      if Tool.Results.Count = 1 then
         E := Pose_Of (Tool.Results.Item (0), In_Units);
         Check (Units_OK (E), "the pose is still in fixture units" & Img (E));
      end if;
      Rectangle.Set_XY_Width_Height (0.0, 0.0, 100.0, 100.0);
      Tool.Region := RH.To_Holder (Rectangle);
      Tool.Run;
      Check_None (Tool, "a region in pixel space beside the symbol");

      --  The root space selected: the pose in pixels.
      Tool.Region.Clear;
      Tool.Input_Image.Set_Selected_Space_Name ("@");
      Tool.Run;
      Check_Only (Tool, "FIXTURE 2026", "the root space selected");
      if Tool.Results.Count = 1 then
         E := Pose_Of (Tool.Results.Item (0), In_Pixels);
         Check (Pose_OK (E), "the pose in pixels" & Img (E));
      end if;
   end Test_Fixture;

   ---------------------------------------------------------------------
   --  Damaged symbols, and what is no symbol
   ---------------------------------------------------------------------

   function Flipped
     (Symbol        : Enc.Module_Matrix;
      Row, Column   : Natural;
      Rows, Columns : Positive) return Enc.Module_Matrix;
   --  The symbol with the modules of the block of Rows by Columns
   --  modules at (Row, Column) the other way round.

   function Flipped
     (Symbol        : Enc.Module_Matrix;
      Row, Column   : Natural;
      Rows, Columns : Positive) return Enc.Module_Matrix is
   begin
      return Result : Enc.Module_Matrix := Symbol do
         for R in Row .. Row + Rows - 1 loop
            for C in Column .. Column + Columns - 1 loop
               Result (R, C) := not Symbol (R, C);
            end loop;
         end loop;
      end return;
   end Flipped;

   function Dots (Symbol : Enc.Module_Matrix) return Enc.Module_Matrix;
   --  The symbol as separate dots: every module is four modules, and
   --  only the first of them is dark where the module is.

   function Dots (Symbol : Enc.Module_Matrix) return Enc.Module_Matrix is
   begin
      return Result : Enc.Module_Matrix
        (0 .. 2 * Symbol'Length (1) - 1, 0 .. 2 * Symbol'Length (2) - 1) :=
          [others => [others => False]]
      do
         for R in Symbol'Range (1) loop
            for C in Symbol'Range (2) loop
               Result (2 * R, 2 * C) := Symbol (R, C);
            end loop;
         end loop;
      end return;
   end Dots;

   function Alone
     (Symbol   : Enc.Module_Matrix;
      Module   : Real := 6.0;
      Rotation : Real := 0.3;
      Dark     : Grey_8 := 0;
      Light    : Grey_8 := 255) return Ks_Image_8_Grey;
   --  An image of 240 x 240 pixels with the symbol in its middle.

   function Alone
     (Symbol   : Enc.Module_Matrix;
      Module   : Real := 6.0;
      Rotation : Real := 0.3;
      Dark     : Grey_8 := 0;
      Light    : Grey_8 := 255) return Ks_Image_8_Grey
   is
      Where : Enc.Corners;
   begin
      return Image : Ks_Image_8_Grey := TI.Blank (240, 240, Light) do
         Put_Symbol (Image, Symbol, 120.3, 119.8, Module, Where, Rotation,
                     Dark => Dark);
      end return;
   end Alone;

   procedure Test_Damage is
      Expect : constant String := Some_Text (30, 5);
      Whole  : constant Enc.Module_Matrix :=
        Enc.Symbol (Enc.ASCII (Expect), 8);
      --  24 x 24 modules: 36 data codewords and 24 check codewords, of
      --  which 12 wrong ones are corrected.
      Image  : Ks_Image_8_Grey := TI.Blank (16, 16);
      Where  : Enc.Corners;
   begin
      Section ("CodeReader: damaged Data Matrix symbols");
      Check_Only (Run_On (Alone (Whole)), Expect, "the whole symbol");
      Check_Only (Run_On (Alone (Flipped (Whole, 9, 9, 4, 4))), Expect,
                  "a block of 4 x 4 modules the other way round");
      Check_Only (Run_On (Alone (Flipped (Whole, 3, 14, 6, 5))), Expect,
                  "a block of 6 x 5 modules the other way round");
      Check_None (Run_On (Alone (Flipped (Whole, 4, 4, 16, 16))),
                  "a block of 16 x 16 modules the other way round: more "
                  & "wrong codewords than are corrected");

      --  A stain and a scratch on the data.
      Image := Alone (Whole, Rotation => 0.0);
      TI.Draw_Rectangle (Image, 130.0, 110.0, 20.0, 16.0, 0.5, 0);
      Check_Only (Run_On (Image), Expect, "a dark stain on the data");
      Image := Alone (Whole, Rotation => 0.0);
      TI.Draw_Rectangle (Image, 125.0, 115.0, 60.0, 3.0, 0.8, 255);
      Check_Only (Run_On (Image), Expect, "a light scratch on the data");

      --  What the method needs (the header of the kernel).
      Check_None (Run_On (Alone (Whole, Dark => 255, Light => 0)),
                  "a symbol printed light on dark is not read");
      Check_None (Run_On (Alone (Dots (Whole), Module => 3.0)),
                  "a symbol of separate dots is not read");
      Image := Alone (Whole, Rotation => 0.0);
      TI.Draw_Rectangle (Image, 30.0, 120.0, 36.0, 200.0, 0.0, 0);
      Check_None (Run_On (Image),
                  "a symbol whose L touches something dark is not read");
      Image := Alone (Whole, Rotation => 0.0);
      TI.Draw_Rectangle (Image, 26.5, 120.0, 37.0, 200.0, 0.0, 0);
      Check_Only (Run_On (Image), Expect,
                  "a gap of three pixels between the L and something dark");

      --  The border of the image is light.
      Image := TI.Blank (144, 144, 255);
      Put_Symbol (Image, Whole, 71.5, 71.5, 6.0, Where);
      Check_Only (Run_On (Image), Expect,
                  "a symbol that fills its image, without a margin");
      Image := TI.Blank (144, 144, 255);
      Put_Symbol (Image, Whole, 71.5, 101.5, 6.0, Where);
      Check_None (Run_On (Image), "a symbol partly outside its image");
   end Test_Damage;

   procedure Test_No_Symbols is
      Image : Ks_Image_8_Grey := TI.Blank (320, 240, 128);
      Tool  : Ks_Code_Reader_Tool;
      Found : Natural := 0;
      Lone  : Enc.Module_Matrix (0 .. 15, 0 .. 15) :=
        [others => [others => False]];
   begin
      Section ("CodeReader: images without a Data Matrix symbol");
      Check_None (Run_On (Image, Everything), "one grey level");
      Check_None (Run_On (TI.Blank (320, 240, 0), Everything), "black");
      Check_None (Run_On (TI.Blank (1, 1, 0), Everything), "one pixel");
      Check_None (Run_On (TI.Blank (7, 3, 255), Everything),
                  "less than a block of pixels");

      --  Noise, and noise with large grains.
      for Seed in 1 .. 8 loop
         Image := TI.Blank (320, 240, 128);
         TI.Add_Noise (Image, 100.0, Seed);
         Tool := Run_On (Image, Everything);
         Found := Found + Tool.Results.Count;
         BC.Blur (Image, 1.5);
         Tool := Run_On (Image, (Everything with delta
                                   Contrast_Threshold => 4));
         Found := Found + Tool.Results.Count;
      end loop;
      Check (Found = 0, "noise gives no symbol (found" & Found'Image & ")");

      --  Regular patterns.
      Found := 0;
      for Turn in 0 .. 5 loop
         TI.Checkerboard (Image, 13.3, 7.1, 6.0 + Real (Turn),
                          Real (Turn) * 0.3);
         Tool := Run_On (Image, Everything);
         Found := Found + Tool.Results.Count;
      end loop;
      Check (Found = 0,
             "checkerboards give no symbol (found" & Found'Image & ")");

      --  Dark shapes: a square, a frame and an L alone.
      Image := TI.Blank (320, 240, 255);
      TI.Draw_Rectangle (Image, 160.0, 120.0, 90.0, 90.0, 0.3, 0);
      Check_None (Run_On (Image, Everything), "a dark square");
      TI.Draw_Rectangle (Image, 160.0, 120.0, 78.0, 78.0, 0.3, 255);
      Check_None (Run_On (Image, Everything), "a dark frame");
      for I in Lone'Range (1) loop
         Lone (I, 0) := True;
         Lone (15, I) := True;
      end loop;
      Check_None (Run_On (Alone (Lone), Everything), "an L alone");
      for I in Lone'Range (1) loop
         Lone (0, I) := I mod 2 = 0;
         Lone (I, 15) := I mod 2 = 1;
      end loop;
      Check_None (Run_On (Alone (Lone), Everything),
                  "the L and the alternating sides around nothing");
   end Test_No_Symbols;

   ---------------------------------------------------------------------
   --  The kernel
   ---------------------------------------------------------------------

   procedure Test_Kernel is
      function Long return String;
      --  600 characters, every character among them.

      function Long return String is
      begin
         return Result : String (1 .. 600) do
            for I in Result'Range loop
               Result (I) := Character'Val ((I * 37 + I / 256) mod 256);
            end loop;
         end return;
      end Long;

      Expect  : constant String := Long;
      Picture : constant Ks_Image_8_Grey :=
        Text_Image (Enc.Base_256 (Expect));
      Handle  : constant access constant KI.Ks_Image_8_Grey_Data :=
        AMV.Images.Kernel_Images.Kernel_Handle (Picture);
      Id      : constant KT.Ks_Transform_2D_Linear := (others => <>);
      Params  : constant KC.Ks_Code_Reader_Run_Params :=
        (Symbologies => KC.Symbology_Data_Matrix, others => <>);
      Region  : KR.Ks_Pixel_Region;
      Results : KC.Ks_Code_Reader_Results;
      Item    : KC.Ks_Code_Reader_Result;
      Moved   : KC.Ks_Code_Reader_Result;
      Part    : KC.Code_Text;
      Length  : K.Int32;
      Count   : K.Int32;
      Status  : K.Ks_Status;
      S       : K.Ks_Status;

      function Message return String is
        (String (Status.Message) (1 .. Natural (Status.Length)));

      function Part_Is (Expected : String) return Boolean is
        (Status.Failure = K.Failure_None
         and then Natural (Length) = Expected'Length
         and then String (Part (1 .. Expected'Length)) = Expected
         and then (for all I in Expected'Length + 1 .. Part'Last =>
                     Part (I) = ASCII.NUL));
      --  The last call of Results_Text gave Expected, and NUL after it.

      procedure Run_With
        (Transform : KT.Ks_Transform_2D_Linear;
         Result    : out KC.Ks_Code_Reader_Result);
      --  The only result of a run on the whole picture with that
      --  transform (No_Result when there is not exactly one).

      procedure Run_With
        (Transform : KT.Ks_Transform_2D_Linear;
         Result    : out KC.Ks_Code_Reader_Result)
      is
         Found : KC.Ks_Code_Reader_Results;
         N     : K.Int32;
      begin
         Result := KC.No_Result;
         KC.Execute (Handle, Region, Params, Transform, Found, Status);
         KC.Results_Count (Found, N, S);
         if Status.Failure = K.Failure_None and then N = 1 then
            KC.Results_Item (Found, 0, Result, S);
         end if;
         KC.Results_Destroy (Found);
      end Run_With;
   begin
      Section ("CodeReader: the kernel and Data Matrix symbols");
      KR.Whole_Image (K.Int32 (Width (Picture)), K.Int32 (Height (Picture)),
                      Region, S);
      KC.Execute (Handle, Region, Params, Id, Results, Status);
      KC.Results_Count (Results, Count, S);
      Check (Status.Failure = K.Failure_None and then Count = 1,
             "the whole image: one symbol");
      KC.Results_Item (Results, 0, Item, Status);
      Check (Status.Failure = K.Failure_None
             and then Item.Symbology = KC.Symbology_Data_Matrix
             and then Item.Length = 600
             and then Item.Num_Scan_Lines = 0
             and then String (Item.Text (1 .. 255)) = Expect (1 .. 255)
             and then Item.Text (256) = ASCII.NUL,
             "its record: the length of the text and its first 255 "
             & "characters");

      --  The text in parts.
      KC.Results_Text (Results, 0, 0, Part, Length, Status);
      Check (Part_Is (Expect (1 .. 255)), "Text from 0: 255 characters");
      KC.Results_Text (Results, 0, 255, Part, Length, Status);
      Check (Part_Is (Expect (256 .. 510)), "Text from 255: the next 255");
      KC.Results_Text (Results, 0, 510, Part, Length, Status);
      Check (Part_Is (Expect (511 .. 600)), "Text from 510: the last 90");
      KC.Results_Text (Results, 0, 7, Part, Length, Status);
      Check (Part_Is (Expect (8 .. 262)), "Text from 7");
      KC.Results_Text (Results, 0, 599, Part, Length, Status);
      Check (Part_Is (Expect (600 .. 600)), "Text from 599: one character");
      KC.Results_Text (Results, 0, 600, Part, Length, Status);
      Check (Part_Is (""), "Text from the length: no character");
      KC.Results_Text (Results, 0, 601, Part, Length, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then Length = 0
             and then Message
                        = "Text: First must be in 0 .. the length of the "
                          & "text",
             "Text from beyond the length");
      KC.Results_Text (Results, 0, -1, Part, Length, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter and then Length = 0,
             "Text from -1");
      KC.Results_Text (Results, 1, 0, Part, Length, Status);
      Check (Status.Failure = K.Failure_Index_Out_Of_Range
             and then Length = 0
             and then Message = "Text: index outside the results",
             "Text (1) of one result");
      KC.Results_Text (Results, -1, 0, Part, Length, Status);
      Check (Status.Failure = K.Failure_Index_Out_Of_Range,
             "Text (-1)");
      KC.Results_Text (null, 0, 0, Part, Length, Status);
      Check (Status.Failure = K.Failure_Index_Out_Of_Range
             and then Length = 0
             and then (for all C of Part => C = ASCII.NUL),
             "Text (0) of null");

      --  The whole text (what the Ada API reads).
      declare
         Buffer : String (1 .. 700);
         Short  : String (1 .. 599);
         Whole  : Natural;
      begin
         KC.Results_Whole_Text (Results, 0, Buffer, Whole, Status);
         Check (Status.Failure = K.Failure_None and then Whole = 600
                and then Buffer (1 .. 600) = Expect
                and then (for all I in 601 .. 700 =>
                            Buffer (I) = ASCII.NUL),
                "the whole text: 600 characters, and NUL after them");
         KC.Results_Whole_Text (Results, 0, Short, Whole, Status);
         Check (Status.Failure = K.Failure_Bad_Parameter and then Whole = 0
                and then Message
                           = "Text: the buffer is shorter than the text",
                "the whole text in a buffer of 599 characters");
         KC.Results_Whole_Text (Results, 1, Buffer, Whole, Status);
         Check (Status.Failure = K.Failure_Index_Out_Of_Range
                and then Whole = 0
                and then Message = "Text: index outside the results",
                "the whole text of item 1 of one result");
         KC.Results_Whole_Text (null, 0, Buffer, Whole, Status);
         Check (Status.Failure = K.Failure_Index_Out_Of_Range
                and then Whole = 0,
                "the whole text of null");
      end;
      KC.Results_Destroy (Results);

      --  Selected_From_Pixel.
      Run_With ((A => 0.5, B => 0.0, C => 0.0, D => 0.5,
                 Translation_X => 10.0, Translation_Y => -20.0), Moved);
      Check (Moved.Length = 600
             and then abs (Moved.Center_X - (0.5 * Item.Center_X + 10.0))
                        < 1.0E-9
             and then abs (Moved.Center_Y - (0.5 * Item.Center_Y - 20.0))
                        < 1.0E-9
             and then abs (Moved.Corner_1_X
                           - (0.5 * Item.Corner_1_X + 10.0)) < 1.0E-9
             and then abs (Moved.Corner_1_Y
                           - (0.5 * Item.Corner_1_Y - 20.0)) < 1.0E-9
             and then abs (Moved.Angle - Item.Angle) < 1.0E-9,
             "a scaling and a translation move the centre and the corners");
      Run_With ((A => 1.0, B => 0.0, C => 0.0, D => -1.0,
                 Translation_X => 0.0, Translation_Y => 0.0), Moved);
      Check (Moved.Length = 600
             and then abs (Moved.Corner_3_X - Item.Corner_3_X) < 1.0E-9
             and then abs (Moved.Corner_3_Y + Item.Corner_3_Y) < 1.0E-9
             and then abs (Moved.Center_Y + Item.Center_Y) < 1.0E-9,
             "a mirroring transform mirrors the centre and the corners");
      Check_Angle_Near (Moved.Angle, -Item.Angle, 1.0E-9,
                        "and the angle");
      Run_With ((A => 0.0, B => 0.0, C => 0.0, D => 0.0,
                 Translation_X => 5.0, Translation_Y => 7.0), Moved);
      Check (Moved.Length = 600
             and then Moved.Center_X = 5.0 and then Moved.Center_Y = 7.0
             and then Moved.Corner_0_X = 5.0 and then Moved.Corner_0_Y = 7.0
             and then Moved.Corner_2_X = 5.0 and then Moved.Corner_2_Y = 7.0
             and then Moved.Angle = 0.0,
             "a transform that maps everything to one point: angle 0");
      KR.Destroy (Region, S);
   end Test_Kernel;

   ---------------------------------------------------------------------
   --  Timing
   ---------------------------------------------------------------------

   procedure Test_Timing is
      Symbol : constant Enc.Module_Matrix :=
        Enc.Symbol (Enc.ASCII (Some_Text (30, 2)), 8);
      Image  : Ks_Image_8_Grey := TI.Blank (640, 480, 255);
      Where  : Enc.Corners;
      Runs   : constant := 10;

      procedure Time
        (Params : Ks_Code_Reader;
         Name   : String);

      procedure Time
        (Params : Ks_Code_Reader;
         Name   : String)
      is
         Tool  : Ks_Code_Reader_Tool;
         Start : Ada.Calendar.Time;
         Total : Duration;
      begin
         Tool.Input_Image := Image;
         Tool.Run_Params := Params;
         Start := Ada.Calendar.Clock;
         for I in 1 .. Runs loop
            Tool.Run;
         end loop;
         Total := Ada.Calendar."-" (Ada.Calendar.Clock, Start);
         Check_Only (Tool, Some_Text (30, 2), Name);
         Ada.Text_IO.Put_Line
           ("  a 640 x 480 image, " & Name & ":"
            & Duration'Image (Total / Runs * 1000.0) & " ms per run");
      end Time;
   begin
      Section ("CodeReader: timing of Data Matrix");
      Put_Symbol (Image, Symbol, 320.0, 240.0, 6.0, Where, 0.3);
      Time (Matrix_Only, "Data Matrix only");
      Time (Everything, "all symbologies");
   end Test_Timing;

   procedure Run_All is
   begin
      Test_Sizes;
      Test_Modules;
      Test_Quality;
      Test_Perspective;
      Test_Texts;
      Test_Several;
      Test_Many;
      Test_Region;
      Test_Run_Params;
      Test_Fixture;
      Test_Damage;
      Test_No_Symbols;
      Test_Kernel;
      Test_Timing;
   end Run_All;

   procedure Main is new AMV_Test_Support.Standalone (Run_All);
begin
   Main;
end Test_Code_Reader_Data_Matrix;
