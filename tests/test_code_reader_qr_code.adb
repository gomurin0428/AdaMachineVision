--  Tests for the QR Code symbols of AMV.Code_Reader: from an image to
--  the texts and the corners of its symbols.
--
--  The symbols are built by AMV_Test_QR_Code, an encoder that shares
--  only the table of the blocks with the kernel that reads them
--  (tests/test_code_reader_qr_symbol.adb checks both against published
--  values and against each other, without an image), and painted by
--  AMV_Test_Data_Matrix. A test here paints a symbol between four known
--  corners, runs the tool and compares the text, the corners, the
--  centre and the angle with what was painted.
--
--  The rotations of a series are spread over the full turn in steps of
--  47 degrees, and every second symbol of a series is mirrored, as a
--  symbol is seen from behind a transparent material. The levels of
--  error correction and the masks change from one symbol of a series
--  to the next.

with Ada.Calendar;
with Ada.Numerics.Long_Elementary_Functions;
with Ada.Text_IO;

with AMV;                    use AMV;
with AMV.Code_Reader;        use AMV.Code_Reader;
with AMV.Coordinate_Spaces;  use AMV.Coordinate_Spaces;
with AMV.Images;             use AMV.Images;
with AMV.Kernels;
with AMV.Kernels.Code_Reader.QR_Code;
with AMV.Shapes;             use AMV.Shapes;
with AMV.Shapes.Region_Holders;
with AMV.Tools;              use AMV.Tools;
with AMV.Transforms;         use AMV.Transforms;
with AMV_Test_Barcodes;
with AMV_Test_Data_Matrix;
with AMV_Test_Images;
with AMV_Test_QR_Code;
with AMV_Test_Support;       use AMV_Test_Support;

procedure Test_Code_Reader_QR_Code is

   package BC renames AMV_Test_Barcodes;
   package EF renames Ada.Numerics.Long_Elementary_Functions;
   package Enc renames AMV_Test_QR_Code;
   package Paint renames AMV_Test_Data_Matrix;
   package QR renames AMV.Kernels.Code_Reader.QR_Code;
   package RH renames AMV.Shapes.Region_Holders;
   package TI renames AMV_Test_Images;

   use type AMV.Kernels.Int32;
   use type Enc.Bit_List;
   use type QR.Level;

   Pi : constant := Ada.Numerics.Pi;

   Defaults : constant Ks_Code_Reader := (others => <>);

   QR_Only : constant Ks_Code_Reader :=
     (Defaults with delta Symbologies => Code (QR_Code));

   Everything : constant Ks_Code_Reader :=
     (Defaults with delta Symbologies => All_Symbologies);

   Corner_Tolerance : constant := 2.0;
   Centre_Tolerance : constant := 2.0;
   Angle_Tolerance  : constant := 0.07;
   --  Pixels and radians, for symbols with modules of 3 pixels or more.

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
        (if From >= Tool.Results.Count or else From >= 8 then ""
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
      Params : Ks_Code_Reader := QR_Only) return Ks_Code_Reader_Tool;
   --  A tool that has run on Image with Params.

   function Run_On
     (Image  : Ks_Image_8_Grey;
      Params : Ks_Code_Reader := QR_Only) return Ks_Code_Reader_Tool is
   begin
      return Tool : Ks_Code_Reader_Tool do
         Tool.Input_Image := Image;
         Tool.Run_Params := Params;
         Tool.Run;
      end return;
   end Run_On;

   function Is_QR
     (Tool     : Ks_Code_Reader_Tool;
      Index    : Natural;
      Expected : String) return Boolean
   is (Index < Tool.Results.Count
       and then Tool.Results.Item (Index).Symbology = Code (QR_Code)
       and then Tool.Results.Item (Index).Length = Expected'Length
       and then Tool.Results.Item (Index).Num_Scan_Lines = 0
       and then Text (Tool.Results, Index) = Expected);
   --  Result Index is a QR Code symbol with that text.

   function Is_Only
     (Tool     : Ks_Code_Reader_Tool;
      Expected : String) return Boolean
   is (Tool.Run_Status.Result = Accept_Result
       and then Tool.Results.Count = 1
       and then Is_QR (Tool, 0, Expected));
   --  The run read that QR Code symbol and nothing else.

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
      --  The largest distance of a corner from the corner painted, in
      --  pixels.
      Centre  : Real := 0.0;
      --  The distance of the centre from where the diagonals of the
      --  symbol painted cross.
      Angle   : Real := 0.0;
      --  The angle to the upper side painted, in radians.
   end record;

   function Pose_Of
     (Result : Ks_Code_Reader_Result;
      Where  : Paint.Corners) return Pose_Errors;

   function Pose_Of
     (Result : Ks_Code_Reader_Result;
      Where  : Paint.Corners) return Pose_Errors
   is
      Middle : constant Paint.Place := Paint.Middle (Where);
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
              EF.Arctan (Where.Upper_Right.Y - Where.Upper_Left.Y,
                         Where.Upper_Right.X - Where.Upper_Left.X)));
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

   procedure Skew (Where : in out Paint.Corners; Share : Real);
   --  The symbol as it is seen at an angle: its upper right corner
   --  pulled towards its middle by Share of the way and its lower right
   --  one by half of that.

   procedure Skew (Where : in out Paint.Corners; Share : Real) is
      M : constant Paint.Place := Paint.Middle (Where);
   begin
      Where.Upper_Right :=
        (Where.Upper_Right.X + Share * (M.X - Where.Upper_Right.X),
         Where.Upper_Right.Y + Share * (M.Y - Where.Upper_Right.Y));
      Where.Lower_Right :=
        (Where.Lower_Right.X + 0.5 * Share * (M.X - Where.Lower_Right.X),
         Where.Lower_Right.Y + 0.5 * Share * (M.Y - Where.Lower_Right.Y));
   end Skew;

   ---------------------------------------------------------------------
   --  Symbols and where they are painted
   ---------------------------------------------------------------------

   function Capacity
     (Version : QR.Version_Number;
      Level   : QR.Level) return Positive
   is (Enc.Data_Count (Version, Level) - (if Version < 10 then 2 else 3));
   --  The bytes of the longest text of one segment of bytes.

   function Message
     (Text    : String;
      Version : QR.Version_Number;
      Level   : QR.Level := QR.M;
      Mask    : QR.Mask_Pattern := 0) return Enc.Module_Matrix
   is (Enc.Symbol (Enc.Segment (Enc.Bytes, Text, Version), Version, Level,
                   Mask));
   --  The symbol with the text as bytes.

   function Size_Of
     (Version : QR.Version_Number;
      Module  : Real) return Real
   is (Real (QR.Side (Version)) * Module);
   --  The side of a symbol in pixels.

   function Room (Size : Real) return Positive is
     (Positive (1.42 * Size) + 40);
   --  The side of an image that holds a symbol of Size pixels a side,
   --  however it is turned, with a margin of 20 pixels.

   function Centred
     (Version  : QR.Version_Number;
      Module   : Real;
      Rotation : Real := 0.0;
      Mirror   : Boolean := False) return Paint.Corners;
   --  Where a symbol lies in the image of Room: its middle a little off
   --  the middle of the image, so that the modules do not fall on the
   --  pixels.

   function Centred
     (Version  : QR.Version_Number;
      Module   : Real;
      Rotation : Real := 0.0;
      Mirror   : Boolean := False) return Paint.Corners
   is
      Size : constant Real := Size_Of (Version, Module);
      Side : constant Real := Real (Room (Size));
   begin
      return Paint.Placed
        (Side / 2.0 + 0.3, Side / 2.0 - 0.2, Size, Size, Rotation, Mirror);
   end Centred;

   procedure Put_Symbol
     (Image    : in out Ks_Image_8_Grey;
      Symbol   : Enc.Module_Matrix;
      X, Y     : Real;
      Module   : Real;
      Where    : out Paint.Corners;
      Rotation : Real := 0.0;
      Mirror   : Boolean := False;
      Dark     : Grey_8 := 0);
   --  Paints the symbol with its middle at (X, Y) and modules of Module
   --  pixels. Where: its corners.

   procedure Put_Symbol
     (Image    : in out Ks_Image_8_Grey;
      Symbol   : Enc.Module_Matrix;
      X, Y     : Real;
      Module   : Real;
      Where    : out Paint.Corners;
      Rotation : Real := 0.0;
      Mirror   : Boolean := False;
      Dark     : Grey_8 := 0) is
   begin
      Where := Paint.Placed (X, Y, Real (Symbol'Length (2)) * Module,
                             Real (Symbol'Length (1)) * Module, Rotation,
                             Mirror);
      Paint.Draw (Image, Symbol, Where, Dark);
   end Put_Symbol;

   type Version_List is array (Positive range <>) of QR.Version_Number;

   Some_Versions : constant Version_List := [1, 2, 4, 7, 10, 15, 22];
   --  21 x 21 to 105 x 105 modules: without an alignment pattern, with
   --  one, with six and more, and with the version information.

   Small_Versions : constant Version_List := [1, 2, 3, 5, 7];

   Levels : constant array (0 .. 3) of QR.Level := [QR.L, QR.M, QR.Q, QR.H];

   procedure Check_Series
     (Name     : String;
      Versions : Version_List;
      Module   : Real;
      Turns    : Positive := 8;
      Step     : Real := 47.0;
      Params   : Ks_Code_Reader := QR_Only;
      Dark     : Grey_8 := 0;
      Light    : Grey_8 := 255;
      Skewed   : Real := 0.0;
      Spoil    : access procedure
        (Image : in out Ks_Image_8_Grey;
         Seed  : Positive) := null);
   --  Reads a symbol of every version of Versions at Turns rotations,
   --  Step degrees apart (every second one mirrored), with modules of
   --  Module pixels, painted with the level Dark on the level Light and
   --  then changed by Spoil. The text fills the symbol. Checks that
   --  every symbol is read with its text and nothing else is, and that
   --  the corners, the centre and the angle are those painted.

   procedure Check_Series
     (Name     : String;
      Versions : Version_List;
      Module   : Real;
      Turns    : Positive := 8;
      Step     : Real := 47.0;
      Params   : Ks_Code_Reader := QR_Only;
      Dark     : Grey_8 := 0;
      Light    : Grey_8 := 255;
      Skewed   : Real := 0.0;
      Spoil    : access procedure
        (Image : in out Ks_Image_8_Grey;
         Seed  : Positive) := null)
   is
      Total, Read, Wrong : Natural := 0;
      Worst              : Pose_Errors;
   begin
      for Version of Versions loop
         for Turn in 0 .. Turns - 1 loop
            declare
               Level  : constant QR.Level := Levels ((Version + Turn) mod 4);
               Expect : constant String :=
                 Some_Text (Capacity (Version, Level), Turn);
               Side   : constant Positive :=
                 Room (Size_Of (Version, Module));
               Where  : Paint.Corners :=
                 Centred (Version, Module, Real (Turn) * Step * Pi / 180.0,
                          Turn mod 2 = 1);
               Image  : Ks_Image_8_Grey := TI.Blank (Side, Side, Light);
               Tool   : Ks_Code_Reader_Tool;
            begin
               Skew (Where, Skewed);
               Paint.Draw
                 (Image,
                  Message (Expect, Version, Level, (Version + 3 * Turn) mod 8),
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
                    ("  " & Name & ", version" & Version'Image & ", turn"
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
   --  Every version, level and mask
   ---------------------------------------------------------------------

   procedure Test_Versions is
      All_Versions : Version_List (1 .. 40);
   begin
      Section ("CodeReader: QR Code symbols of every version");
      for I in All_Versions'Range loop
         All_Versions (I) := I;
      end loop;
      --  With the linear barcodes and Data Matrix looked for as well: no
      --  part of a QR Code symbol is read as one of them.
      Check_Series ("the 40 versions, 21 x 21 to 177 x 177 modules",
                    All_Versions, Module => 3.0, Params => Everything);
   end Test_Versions;

   procedure Test_Levels is
      Versions    : constant Version_List := [3, 7];
      Module      : constant := 4.0;
      Total, Read : Natural := 0;
      Worst       : Pose_Errors;
   begin
      Section ("CodeReader: QR Code levels of error correction and masks");
      for Version of Versions loop
         for Level of Levels loop
            for Mask in QR.Mask_Pattern loop
               declare
                  Expect : constant String :=
                    Some_Text (Capacity (Version, Level), Mask);
                  Side   : constant Positive :=
                    Room (Size_Of (Version, Module));
                  Where  : constant Paint.Corners :=
                    Centred (Version, Module, 0.3 + 0.7 * Real (Mask),
                             Mask mod 2 = 1);
                  Image  : Ks_Image_8_Grey := TI.Blank (Side, Side, 255);
                  Tool   : Ks_Code_Reader_Tool;
               begin
                  Paint.Draw (Image, Message (Expect, Version, Level, Mask),
                              Where);
                  Tool := Run_On (Image);
                  Total := Total + 1;
                  if Is_Only (Tool, Expect) then
                     Read := Read + 1;
                     Worst :=
                       Worse (Worst,
                              Pose_Of (Tool.Results.Item (0), Where));
                  else
                     Ada.Text_IO.Put_Line
                       ("  version" & Version'Image & ", level "
                        & Level'Image & ", mask" & Mask'Image & ":"
                        & Found (Tool));
                  end if;
               end;
            end loop;
         end loop;
      end loop;
      Check (Read = Total,
             "the four levels with the eight masks, versions 3 and 7 "
             & "(read" & Read'Image & " of" & Total'Image & ")");
      Check (Pose_OK (Worst),
             "the corners, the centre and the angle" & Img (Worst));
   end Test_Levels;

   ---------------------------------------------------------------------
   --  The size of the modules
   ---------------------------------------------------------------------

   procedure Test_Modules is

      procedure Blur_Slightly
        (Image : in out Ks_Image_8_Grey; Seed : Positive);

      procedure Blur_Slightly
        (Image : in out Ks_Image_8_Grey; Seed : Positive)
      is
         pragma Unreferenced (Seed);
      begin
         BC.Blur (Image, 0.4);
      end Blur_Slightly;
   begin
      Section ("CodeReader: QR Code modules of 2 to 20 pixels");
      Check_Series ("modules of 2 pixels, sharp", Small_Versions, 2.0);
      Check_Series ("modules of 2 pixels, blurred by 0.4 pixels",
                    Small_Versions, 2.0, Spoil => Blur_Slightly'Access);
      Check_Series ("modules of 2.5 pixels", Some_Versions, 2.5);
      Check_Series ("modules of 3 pixels", Some_Versions, 3.0);
      Check_Series ("modules of 3.5 pixels", Some_Versions, 3.5);
      Check_Series ("modules of 5 pixels", Some_Versions, 5.0);
      Check_Series ("modules of 6.3 pixels", Some_Versions, 6.3);
      Check_Series ("modules of 9 pixels", Small_Versions, 9.0);
      Check_Series ("modules of 20 pixels", Small_Versions, 20.0);
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
      Section ("CodeReader: QR Code symbols in images of less quality");
      Check_Series ("modules of 4 pixels, blurred by 0.7 pixels",
                    Some_Versions, 4.0, Spoil => Blur_Little'Access);
      Check_Series ("modules of 6 pixels, blurred by 1.2 pixels",
                    Some_Versions, 6.0, Spoil => Blur_More'Access);
      Check_Series ("noise of 20 levels", Some_Versions, 4.0,
                    Spoil => Noise'Access);
      Check_Series ("the levels 100 on 130", Some_Versions, 4.0,
                    Dark => 100, Light => 130);
      Check_Series ("the right side of the image at 0.4 of the light",
                    Some_Versions, 4.0, Spoil => Shading'Access);
   end Test_Quality;

   ---------------------------------------------------------------------
   --  A symbol seen at an angle
   ---------------------------------------------------------------------

   procedure Test_Perspective is
      With_Alignment : constant Version_List := [2, 4, 7, 10, 15, 22];
   begin
      Section ("CodeReader: QR Code symbols seen at an angle");
      Check_Series ("a corner 10 % nearer to the middle", With_Alignment,
                    4.0, Skewed => 0.1);
      Check_Series ("a corner 20 % nearer to the middle", With_Alignment,
                    4.0, Skewed => 0.2);
      Check_Series ("a corner 30 % nearer to the middle, modules of 6 "
                    & "pixels", With_Alignment, 6.0, Skewed => 0.3);
   end Test_Perspective;


   ---------------------------------------------------------------------
   --  The texts
   ---------------------------------------------------------------------

   function Fitting
     (Bits  : Enc.Bit_List;
      Level : QR.Level := QR.M) return QR.Version_Number;
   --  The smallest of the versions 1 to 9 that holds the bits (the
   --  counts of the segments have the same lengths in these versions).

   function Fitting
     (Bits  : Enc.Bit_List;
      Level : QR.Level := QR.M) return QR.Version_Number is
   begin
      for Version in QR.Version_Number range 1 .. 9 loop
         if 8 * Enc.Data_Count (Version, Level) >= Bits'Length then
            return Version;
         end if;
      end loop;
      raise Constraint_Error with "more bits than version 9 holds";
   end Fitting;

   function Text_Image
     (Bits     : Enc.Bit_List;
      Version  : QR.Version_Number;
      Level    : QR.Level := QR.M;
      Module   : Real := 4.0;
      Rotation : Real := 0.2) return Ks_Image_8_Grey;
   --  An image of the symbol of that version and level with the bits
   --  Bits, with modules of Module pixels, turned by Rotation.

   function Text_Image
     (Bits     : Enc.Bit_List;
      Version  : QR.Version_Number;
      Level    : QR.Level := QR.M;
      Module   : Real := 4.0;
      Rotation : Real := 0.2) return Ks_Image_8_Grey
   is
      Side : constant Positive := Room (Size_Of (Version, Module));
   begin
      return Image : Ks_Image_8_Grey := TI.Blank (Side, Side, 255) do
         Paint.Draw (Image,
                     Enc.Symbol (Bits, Version, Level, Version mod 8),
                     Centred (Version, Module, Rotation));
      end return;
   end Text_Image;

   procedure Check_Text
     (Bits        : Enc.Bit_List;
      Expected    : String;
      Description : String);
   --  The smallest symbol of the level M with the bits Bits (segments
   --  for the versions 1 to 9) is read as Expected.

   procedure Check_Text
     (Bits        : Enc.Bit_List;
      Expected    : String;
      Description : String) is
   begin
      Check_Only (Run_On (Text_Image (Bits, Fitting (Bits))), Expected,
                  Description);
   end Check_Text;

   procedure Test_Texts is
      GS      : constant Character := Character'Val (29);
      Kanji   : constant String :=
        Character'Val (16#93#) & Character'Val (16#5F#)
        & Character'Val (16#E4#) & Character'Val (16#AA#);
      --  Two characters, as Shift JIS has them.
      Nothing : constant Enc.Bit_List (1 .. 0) := [others => False];
      Every   : String (1 .. 256);
      Number  : String (1 .. 7089);
      Long    : String (1 .. 2953);
      Version : QR.Version_Number;
      Tool    : Ks_Code_Reader_Tool;

      function Seg (Kind : Enc.Mode; Text : String) return Enc.Bit_List is
        (Enc.Segment (Kind, Text, 1));
      --  A segment for the versions 1 to 9.
   begin
      Section ("CodeReader: the texts of QR Code symbols");
      for I in Every'Range loop
         Every (I) := Character'Val (I - 1);
      end loop;
      for I in Number'Range loop
         Number (I) := Character'Val (48 + (I * 7 + I / 10) mod 10);
      end loop;
      for I in Long'Range loop
         Long (I) := Character'Val ((I * 37 + I / 256) mod 256);
      end loop;

      Check_Text (Seg (Enc.Numeric, "0123456789012345"),
                  "0123456789012345", "the numeric mode");
      Check_Text (Seg (Enc.Alphanumeric, "AMV CODE-READER $%*+./:"),
                  "AMV CODE-READER $%*+./:", "the alphanumeric mode");
      Check_Text (Seg (Enc.Bytes, "Hello, world!"), "Hello, world!",
                  "the byte mode");
      Check_Text (Seg (Enc.Bytes, Every (120 .. 140)), Every (120 .. 140),
                  "bytes above 127, as they are encoded");
      Check_Text (Seg (Enc.Kanji, Kanji), Kanji,
                  "the Kanji mode: the two bytes of each character, as "
                  & "Shift JIS has them");
      Check_Text (Seg (Enc.Numeric, "0123") & Seg (Enc.Alphanumeric, "AB C")
                  & Seg (Enc.Bytes, "xyz") & Seg (Enc.Kanji, Kanji),
                  "0123AB Cxyz" & Kanji,
                  "a segment of every mode in one symbol");

      --  What stands for more than itself, and what is passed over.
      Check_Text (Enc.FNC1_First & Seg (Enc.Numeric, "0109501101530003")
                  & Seg (Enc.Alphanumeric, "10AB12%2112345"),
                  "010950110153000310AB12" & GS & "2112345",
                  "FNC1 in the first position: % is GS");
      Check_Text (Enc.FNC1_First & Seg (Enc.Alphanumeric, "A%%B"), "A%B",
                  "and %% is %");
      Check_Text (Enc.FNC1_Second (165) & Seg (Enc.Alphanumeric, "X%Y"),
                  "AX" & GS & "Y",
                  "FNC1 in the second position: its application "
                  & "indicator, a letter, comes first");
      Check_Text (Enc.FNC1_Second (37) & Seg (Enc.Numeric, "123"), "37123",
                  "an application indicator of two digits");
      Check_Text (Enc.ECI (26) & Seg (Enc.Bytes, "abc"), "abc",
                  "an extended channel interpretation is passed over");
      Check_Text (Enc.Structured_Append (1, 3, 85)
                  & Seg (Enc.Bytes, "part"), "part",
                  "the header of a structured append is passed over");

      --  More characters than a result record holds.
      Version := Enc.Smallest_Version (Enc.Bytes, Every, QR.L);
      Tool := Run_On
        (Text_Image (Enc.Segment (Enc.Bytes, Every, Version), Version,
                     QR.L));
      Check_Only (Tool, Every, "a text of 256 characters, every character");
      if Tool.Results.Count = 1 then
         Check (Tool.Results.Item (0).Length = 256
                and then Text (Tool.Results.Item (0)) = Every (1 .. 255),
                "its record has the length and the first 255 characters");
      end if;
      Tool := Run_On
        (Text_Image (Enc.Segment (Enc.Numeric, Number, 40), 40, QR.L, 3.0));
      Check_Only (Tool, Number,
                  "7089 digits, the most that a symbol holds");
      Tool := Run_On
        (Text_Image (Enc.Segment (Enc.Bytes, Long, 40), 40, QR.L, 3.0));
      Check_Only (Tool, Long, "2953 bytes, the most that a symbol holds");
      Check_Only (Run_On (Text_Image (Seg (Enc.Bytes, "A"), 1)), "A",
                  "one character");
      Check_None (Run_On (Text_Image (Nothing, 1)),
                  "a symbol without a segment is not reported");
   end Test_Texts;

   ---------------------------------------------------------------------
   --  Several symbols
   ---------------------------------------------------------------------

   function Is_Linear
     (Tool     : Ks_Code_Reader_Tool;
      Index    : Natural;
      Symbol   : Ks_Code_Reader_Symbology_Constants;
      Expected : String) return Boolean
   is (Index < Tool.Results.Count
       and then Tool.Results.Item (Index).Symbology = Code (Symbol)
       and then Tool.Results.Item (Index).Num_Scan_Lines >= 2
       and then Text (Tool.Results, Index) = Expected);
   --  Result Index is a linear barcode of that symbology and text.

   function Is_Matrix
     (Tool     : Ks_Code_Reader_Tool;
      Index    : Natural;
      Expected : String) return Boolean
   is (Index < Tool.Results.Count
       and then Tool.Results.Item (Index).Symbology = Code (Data_Matrix)
       and then Text (Tool.Results, Index) = Expected);
   --  Result Index is a Data Matrix symbol with that text.

   procedure Test_Several is
      Image      : Ks_Image_8_Grey := TI.Blank (640, 480, 230);
      First      : constant Enc.Module_Matrix := Message ("AMV-1", 1);
      Second     : constant Enc.Module_Matrix :=
        Message ("SECOND SYMBOL 0002", 2, QR.Q, 3);
      Third      : constant Enc.Module_Matrix :=
        Message ("THE THIRD ONE, VERSION 3", 3, QR.L, 6);
      Matrix     : constant Enc.Module_Matrix :=
        Paint.Symbol (Paint.ASCII ("MATRIX 12"));
      W1, W2, W3 : Paint.Corners;
      WM         : Paint.Corners;
      Tool       : Ks_Code_Reader_Tool;
      Twice      : Ks_Image_8_Grey := TI.Blank (300, 160, 255);
   begin
      Section ("CodeReader: QR Code symbols with other symbols in one "
               & "image");

      --  Three QR Code symbols, the first above the second and the
      --  second above the third, a Data Matrix symbol and two barcodes
      --  between them.
      Put_Symbol (Image, First, 110.0, 80.0, 5.0, W1, 0.3);
      Put_Symbol (Image, Second, 540.0, 190.0, 4.0, W2, -1.1,
                  Mirror => True, Dark => 40);
      Put_Symbol (Image, Third, 120.0, 390.0, 4.0, W3, 0.1);
      Put_Symbol (Image, Matrix, 330.0, 80.0, 5.0, WM, 0.2);
      BC.Draw (Image, BC.EAN_13 ("5901234123457"), 320.0, 240.0, 2.0, 60.0);
      BC.Draw (Image, BC.Code_128_B ("AMV-1"), 420.0, 400.0, 2.0, 50.0);

      Tool := Run_On (Image, Everything);
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Count = 6,
             "all symbologies: six symbols" & Found (Tool));
      Check ((Is_Linear (Tool, 0, EAN_13, "5901234123457")
              and then Is_Linear (Tool, 1, Code_128, "AMV-1"))
             or else (Is_Linear (Tool, 0, Code_128, "AMV-1")
                      and then Is_Linear (Tool, 1, EAN_13,
                                          "5901234123457")),
             "the two barcodes first" & Found (Tool));
      Check (Is_Matrix (Tool, 2, "MATRIX 12"),
             "then the Data Matrix symbol" & Found (Tool));
      Check (Is_QR (Tool, 3, "AMV-1")
             and then Is_QR (Tool, 4, "SECOND SYMBOL 0002")
             and then Is_QR (Tool, 5, "THE THIRD ONE, VERSION 3"),
             "then the QR Code symbols, from the top of the image"
             & Found (Tool));
      if Tool.Results.Count = 6 then
         Check (Pose_OK (Pose_Of (Tool.Results.Item (2), WM)),
                "the Data Matrix symbol is where it was drawn"
                & Img (Pose_Of (Tool.Results.Item (2), WM)));
         Check (Pose_OK (Pose_Of (Tool.Results.Item (3), W1)),
                "the first QR Code symbol is where it was drawn"
                & Img (Pose_Of (Tool.Results.Item (3), W1)));
         Check (Pose_OK (Pose_Of (Tool.Results.Item (4), W2)),
                "the second one, mirrored and dark grey on light grey"
                & Img (Pose_Of (Tool.Results.Item (4), W2)));
         Check (Pose_OK (Pose_Of (Tool.Results.Item (5), W3)),
                "the third one"
                & Img (Pose_Of (Tool.Results.Item (5), W3)));
      end if;

      Tool := Run_On (Image);
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Count = 3
             and then Is_QR (Tool, 0, "AMV-1")
             and then Is_QR (Tool, 1, "SECOND SYMBOL 0002")
             and then Is_QR (Tool, 2, "THE THIRD ONE, VERSION 3"),
             "QR Code only: the three symbols" & Found (Tool));

      Tool := Run_On (Image, Defaults);
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Count = 2
             and then Tool.Results.Item (0).Num_Scan_Lines >= 2
             and then Tool.Results.Item (1).Num_Scan_Lines >= 2,
             "the default symbologies: the two barcodes" & Found (Tool));

      Tool := Run_On
        (Image, (Defaults with delta
                   Symbologies => Code (QR_Code) + Code (Data_Matrix)));
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Count = 4
             and then Is_Matrix (Tool, 0, "MATRIX 12")
             and then Is_QR (Tool, 1, "AMV-1")
             and then Is_QR (Tool, 3, "THE THIRD ONE, VERSION 3"),
             "QR Code and Data Matrix: four symbols" & Found (Tool));

      --  The same symbol twice is two symbols.
      Put_Symbol (Twice, First, 80.0, 80.0, 4.0, W1, 0.2);
      Put_Symbol (Twice, First, 220.0, 80.0, 4.0, W2, -0.4);
      Tool := Run_On (Twice);
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Count = 2
             and then Is_QR (Tool, 0, "AMV-1")
             and then Is_QR (Tool, 1, "AMV-1"),
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
      Pitch : constant := 80;
      --  Symbols of 21 x 21 modules of 3 pixels, 17 pixels apart.

      function Name (Index : Natural) return String is
        (['S', Character'Val (48 + Index / 100 mod 10),
          Character'Val (48 + Index / 10 mod 10),
          Character'Val (48 + Index mod 10)]);

      procedure Read_Grid
        (Columns : Positive;
         Spoilt  : Boolean;
         Label   : String;
         Tool    : out Ks_Code_Reader_Tool;
         Right   : out Natural;
         Ordered : out Boolean;
         Whole   : Integer := -1);
      --  Runs the tool on an image with five rows of Columns symbols
      --  with the texts Name (0), Name (1) and so on, row after row,
      --  and prints the time of the run. Spoilt: with most of the data
      --  of every symbol but the symbol Whole the other way round, so
      --  that none of them can be read. Right: the results with the
      --  text of the symbol at their centre. Ordered: result I is
      --  symbol I, for every result.

      procedure Read_Grid
        (Columns : Positive;
         Spoilt  : Boolean;
         Label   : String;
         Tool    : out Ks_Code_Reader_Tool;
         Right   : out Natural;
         Ordered : out Boolean;
         Whole   : Integer := -1)
      is
         Image  : Ks_Image_8_Grey :=
           TI.Blank (Columns * Pitch, 5 * Pitch, 255);
         Where  : Paint.Corners;
         Start  : Ada.Calendar.Time;
         Passed : Duration;
      begin
         for Row in 0 .. 4 loop
            for Column in 0 .. Columns - 1 loop
               declare
                  Index  : constant Natural := Row * Columns + Column;
                  Symbol : Enc.Module_Matrix :=
                    Message (Name (Index), 1, Levels (Index mod 4),
                             Index mod 8);
               begin
                  if Spoilt and then Index /= Whole then
                     for R in 9 .. 20 loop
                        for C in 9 .. 20 loop
                           Symbol (R, C) := not Symbol (R, C);
                        end loop;
                     end loop;
                  end if;
                  Put_Symbol (Image, Symbol, Real (Column * Pitch) + 39.5,
                              Real (Row * Pitch) + 39.5, 3.0, Where);
               end;
            end loop;
         end loop;
         Tool.Input_Image := Image;
         Tool.Run_Params := QR_Only;
         Start := Ada.Calendar.Clock;
         Tool.Run;
         Passed := Ada.Calendar."-" (Ada.Calendar.Clock, Start);
         Ada.Text_IO.Put_Line
           ("  " & Label & ":" & Duration'Image (Passed * 1000.0) & " ms");
         Right := 0;
         Ordered := True;
         for I in 0 .. Tool.Results.Count - 1 loop
            declare
               Item  : constant Ks_Code_Reader_Result :=
                 Tool.Results.Item (I);
               Index : constant Integer :=
                 Integer (Real'Floor (Item.Center_Y / Real (Pitch)))
                 * Columns
                 + Integer (Real'Floor (Item.Center_X / Real (Pitch)));
            begin
               if Index >= 0 and then Is_QR (Tool, I, Name (Index)) then
                  Right := Right + 1;
               end if;
               Ordered := Ordered and then Index = I;
            end;
         end loop;
      end Read_Grid;

      Tool    : Ks_Code_Reader_Tool;
      Right   : Natural;
      Ordered : Boolean;
   begin
      Section ("CodeReader: as many QR Code symbols as a run finds");

      --  85 symbols have the 255 finder patterns that a run holds.
      Read_Grid (17, False, "85 symbols", Tool, Right, Ordered);
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Count = 85 and then Right = 85,
             "85 symbols, each with its text (found"
             & Tool.Results.Count'Image & ", right" & Right'Image & ", "
             & Tool.Run_Status.Result'Image & " "
             & Message (Tool.Run_Status) & ")");
      Check (Ordered, "in the order of their rows, and from the left in "
             & "a row");

      --  More finder patterns than a run holds: the symbols whose
      --  three patterns are among the first 256 are read.
      Read_Grid (18, False, "90 symbols", Tool, Right, Ordered);
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Count in 72 .. 85
             and then Right = Tool.Results.Count,
             "90 symbols: those whose patterns the run holds, each with "
             & "its text (found" & Tool.Results.Count'Image & ", right"
             & Right'Image & ", " & Tool.Run_Status.Result'Image & " "
             & Message (Tool.Run_Status) & ")");

      --  Finder patterns whose symbols cannot be read: each is tried
      --  with the pairs of those nearest to it, as far as the kernel
      --  goes (its header), and the run comes to an end in good time.
      Read_Grid (17, True, "85 symbols that cannot be read", Tool, Right,
                 Ordered);
      Check_None (Tool, "85 symbols with too many wrong modules");

      --  One symbol among them that can be read: the patterns of the
      --  others around it do not hide it.
      Read_Grid (17, True, "one symbol among 84 that cannot be read",
                 Tool, Right, Ordered, Whole => 42);
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Count = 1 and then Right = 1,
             "one symbol among 84 with too many wrong modules (found"
             & Tool.Results.Count'Image & ", right" & Right'Image & ")");
   end Test_Many;

   ---------------------------------------------------------------------
   --  The region
   ---------------------------------------------------------------------

   procedure Test_Region is
      Image     : Ks_Image_8_Grey := TI.Blank (640, 480, 255);
      Left      : constant Enc.Module_Matrix := Message ("LEFT 0001", 2);
      Right     : constant Enc.Module_Matrix :=
        Message ("RIGHT 0002", 2, QR.Q, 5);
      WL, WR    : Paint.Corners;
      Tool      : Ks_Code_Reader_Tool;
      Rectangle : Ks_Rectangle;
      Circle    : Ks_Circle;
   begin
      Section ("CodeReader: QR Code symbols and the region");

      --  Two symbols of 25 x 25 modules of 4 pixels: an upright one on
      --  the left (x in 110 .. 210, y in 190 .. 290) and a turned one on
      --  the right.
      Put_Symbol (Image, Left, 160.0, 240.0, 4.0, WL);
      Put_Symbol (Image, Right, 480.0, 240.0, 4.0, WR, 0.5);
      Tool.Input_Image := Image;
      Tool.Run_Params := QR_Only;
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Count = 2
             and then Is_QR (Tool, 0, "RIGHT 0002")
             and then Is_QR (Tool, 1, "LEFT 0001"),
             "no region: both symbols, first the one whose finder "
             & "pattern in the corner reaches higher" & Found (Tool));

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

      Rectangle.Set_XY_Width_Height (100.0, 180.0, 120.0, 120.0);
      Tool.Region := RH.To_Holder (Rectangle);
      Tool.Run;
      Check_Only (Tool, "LEFT 0001",
                  "a rectangle around the symbol and a margin");

      --  The pixels outside the region are light: the symbol needs no
      --  margin within it.
      Rectangle.Set_XY_Width_Height (109.5, 189.5, 101.0, 101.0);
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
      Symbol : constant Enc.Module_Matrix := Message ("PARAMS 12", 2);
      Image  : Ks_Image_8_Grey := TI.Blank (200, 160, 255);
      Faint  : Ks_Image_8_Grey := TI.Blank (200, 160, 130);
      Where  : Paint.Corners;
   begin
      Section ("CodeReader: QR Code symbols and the run parameters");
      Put_Symbol (Image, Symbol, 100.0, 80.0, 4.0, Where, 0.4);
      Put_Symbol (Faint, Symbol, 100.0, 80.0, 4.0, Where, 0.4, Dark => 100);

      Check (Code (QR_Code) = 256
             and then Defaults.Symbologies + Code (Data_Matrix)
                        + Code (QR_Code) = Everything.Symbologies,
             "the codes: QR Code is 256 and not among the defaults");
      Check_None (Run_On (Image, Defaults),
                  "the default symbologies do not read a QR Code symbol");
      Check_Only (Run_On (Image, Everything), "PARAMS 12",
                  "all symbologies do");
      Check_Only (Run_On (Image), "PARAMS 12", "QR Code alone does");
      Check_None
        (Run_On (Image,
                 (Defaults with delta
                    Symbologies => All_Symbologies - Code (QR_Code))),
         "all but QR Code do not");

      --  The parameters of the scan lines are not those of QR Code.
      Check_Only
        (Run_On (Image,
                 (QR_Only with delta Num_Directions => 1,
                  First_Direction => 1.0, Line_Spacing => 1000.0,
                  Min_Scan_Lines => 1000)),
         "PARAMS 12", "one direction, one scan line, 1000 lines asked");

      --  The contrast: levels of 100 on 130.
      Check_Only (Run_On (Faint), "PARAMS 12",
                  "30 grey levels of contrast, the default threshold");
      Check_Only
        (Run_On (Faint, (QR_Only with delta Contrast_Threshold => 15)),
         "PARAMS 12", "a threshold of 15, half the contrast");
      Check_None
        (Run_On (Faint, (QR_Only with delta Contrast_Threshold => 16)),
         "a threshold of 16");
      Check_Only
        (Run_On (Image, (QR_Only with delta Contrast_Threshold => 255)),
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
      Symbol    : constant Enc.Module_Matrix := Message ("FIXTURE 2026", 2);
      Wide      : constant Real := Real (Symbol'Length (2)) * 3.0;
      High      : constant Real := Real (Symbol'Length (1)) * 3.0;
      In_Units  : constant Paint.Corners :=
        Paint.Placed (176.0, 45.0, Wide, High, 0.7);
      --  The symbol in the fixture: modules of 3 units, 6 pixels. In
      --  pixels it lies near the middle of the image.
      In_Pixels : Paint.Corners;
      Tool      : Ks_Code_Reader_Tool;
      Rectangle : Ks_Rectangle;
      E         : Pose_Errors;

      function Units_OK (E : Pose_Errors) return Boolean is
        (E.Corners <= Corner_Tolerance / Scale
         and then E.Centre <= Centre_Tolerance / Scale
         and then E.Angle <= Angle_Tolerance);
   begin
      Section ("CodeReader: QR Code symbols in fixture space");
      Tool.Input_Image := TI.Blank (640, 480, 255);
      Tool.Run_Params := QR_Only;
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
      Paint.Draw (Tool.Input_Image, Symbol, In_Pixels);

      Tool.Run;
      Check_Only (Tool, "FIXTURE 2026",
                  "a symbol in an image with a fixture");
      if Tool.Results.Count = 1 then
         E := Pose_Of (Tool.Results.Item (0), In_Units);
         Check (Units_OK (E), "its pose in fixture units" & Img (E));
      end if;

      --  A region in the fixture.
      Rectangle.Set_XY_Width_Height (120.0, -10.0, 112.0, 110.0);
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
      Where : Paint.Corners;
   begin
      return Image : Ks_Image_8_Grey := TI.Blank (240, 240, Light) do
         Put_Symbol (Image, Symbol, 120.3, 119.8, Module, Where, Rotation,
                     Dark => Dark);
      end return;
   end Alone;

   procedure Test_Damage is
      Expect  : constant String := Some_Text (Capacity (3, QR.H), 5);
      Whole   : constant Enc.Module_Matrix := Message (Expect, 3, QR.H, 2);
      --  29 x 29 modules: two blocks of 13 data codewords and 22 check
      --  codewords, of which 11 wrong ones are corrected in each.
      Without : Enc.Module_Matrix := Whole;
      Image   : Ks_Image_8_Grey := TI.Blank (16, 16);
      Where   : Paint.Corners;
   begin
      Section ("CodeReader: damaged QR Code symbols");
      Check_Only (Run_On (Alone (Whole)), Expect, "the whole symbol");
      Check_Only (Run_On (Alone (Flipped (Whole, 10, 10, 4, 4))), Expect,
                  "a block of 4 x 4 modules the other way round");
      Check_Only (Run_On (Alone (Flipped (Whole, 9, 15, 6, 5))), Expect,
                  "a block of 6 x 5 modules the other way round");
      Check_None (Run_On (Alone (Flipped (Whole, 9, 9, 16, 16))),
                  "a block of 16 x 16 modules the other way round: more "
                  & "wrong codewords than are corrected");

      --  A stain and a scratch on the data.
      Image := Alone (Whole, Rotation => 0.0);
      TI.Draw_Rectangle (Image, 130.0, 110.0, 20.0, 16.0, 0.5, 0);
      Check_Only (Run_On (Image), Expect, "a dark stain on the data");
      Image := Alone (Whole, Rotation => 0.0);
      TI.Draw_Rectangle (Image, 125.0, 115.0, 60.0, 3.0, 0.8, 255);
      Check_Only (Run_On (Image), Expect, "a light scratch on the data");

      --  The timing patterns: the modules 8 to 20 of the row 6 and of
      --  the column 6, from x = 81.3 to x = 159.3 at y = 71.8 and from
      --  y = 80.8 to y = 158.8 at x = 72.3. One of the two is enough.
      Check_Only
        (Run_On
           (Alone (Flipped (Flipped (Whole, 6, 10, 1, 2), 10, 6, 2, 1))),
         Expect,
         "two modules of either timing pattern the other way round");
      Image := Alone (Whole, Rotation => 0.0);
      TI.Draw_Rectangle (Image, 120.3, 71.8, 78.0, 18.0, 0.0, 255);
      Check_Only (Run_On (Image), Expect,
                  "the upper timing pattern covered, with the modules "
                  & "above and below it");
      Image := Alone (Whole, Rotation => 0.0);
      TI.Draw_Rectangle (Image, 72.3, 119.8, 18.0, 78.0, 0.0, 0);
      Check_Only (Run_On (Image), Expect,
                  "the left timing pattern under something dark");
      TI.Draw_Rectangle (Image, 120.3, 71.8, 78.0, 18.0, 0.0, 255);
      Check_None (Run_On (Image),
                  "a symbol with both timing patterns covered is not "
                  & "read");

      --  What the method needs (the header of the kernel).
      Check_None (Run_On (Alone (Whole, Dark => 255, Light => 0)),
                  "a symbol printed light on dark is not read");
      for R in 22 .. 28 loop
         for C in 0 .. 6 loop
            Without (R, C) := False;
         end loop;
      end loop;
      Check_None (Run_On (Alone (Without)),
                  "a symbol without one of its finder patterns is not "
                  & "read");
      Image := Alone (Whole, Rotation => 0.0);
      TI.Draw_Rectangle (Image, 16.65, 120.0, 33.3, 200.0, 0.0, 0);
      Check_None (Run_On (Image),
                  "a symbol whose finder patterns touch something dark is "
                  & "not read");
      Image := Alone (Whole, Rotation => 0.0);
      TI.Draw_Rectangle (Image, 13.65, 120.0, 27.3, 200.0, 0.0, 0);
      Check_Only (Run_On (Image), Expect,
                  "a gap of one module between them and something dark");

      --  The border of the image is light.
      Image := TI.Blank (174, 174, 255);
      Put_Symbol (Image, Whole, 87.0, 87.0, 6.0, Where);
      Check_Only (Run_On (Image), Expect,
                  "a symbol that fills its image, without a margin");
      Image := TI.Blank (174, 174, 255);
      Put_Symbol (Image, Whole, 87.0, 117.0, 6.0, Where);
      Check_None (Run_On (Image), "a symbol partly outside its image");
   end Test_Damage;

   procedure Test_No_Symbols is
      Image    : Ks_Image_8_Grey := TI.Blank (320, 240, 128);
      Tool     : Ks_Code_Reader_Tool;
      Found    : Natural := 0;
      Pattern  : Enc.Module_Matrix (0 .. 6, 0 .. 6) :=
        [others => [others => True]];
      Patterns : Enc.Module_Matrix (0 .. 20, 0 .. 20) :=
        [others => [others => False]];
   begin
      Section ("CodeReader: images without a QR Code symbol");
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

      --  Dark shapes: a square, a frame, a finder pattern alone, and
      --  three of them around nothing.
      Image := TI.Blank (320, 240, 255);
      TI.Draw_Rectangle (Image, 160.0, 120.0, 90.0, 90.0, 0.3, 0);
      Check_None (Run_On (Image, Everything), "a dark square");
      TI.Draw_Rectangle (Image, 160.0, 120.0, 78.0, 78.0, 0.3, 255);
      Check_None (Run_On (Image, Everything), "a dark frame");
      for I in 1 .. 5 loop
         Pattern (1, I) := False;
         Pattern (5, I) := False;
         Pattern (I, 1) := False;
         Pattern (I, 5) := False;
      end loop;
      Check_None (Run_On (Alone (Pattern), Everything),
                  "a finder pattern alone");
      for R in Pattern'Range (1) loop
         for C in Pattern'Range (2) loop
            Patterns (R, C) := Pattern (R, C);
            Patterns (R, C + 14) := Pattern (R, C);
            Patterns (R + 14, C) := Pattern (R, C);
         end loop;
      end loop;
      Check_None (Run_On (Alone (Patterns), Everything),
                  "three finder patterns around nothing");
      Check_None (Run_On (Alone (Enc.Function_Modules (2)), Everything),
                  "the finder, timing and alignment patterns of a symbol "
                  & "around nothing");
   end Test_No_Symbols;

   ---------------------------------------------------------------------
   --  Timing
   ---------------------------------------------------------------------

   procedure Test_Timing is
      Expect : constant String := Some_Text (Capacity (5, QR.M), 2);
      Symbol : constant Enc.Module_Matrix := Message (Expect, 5, QR.M, 4);
      Image  : Ks_Image_8_Grey := TI.Blank (640, 480, 255);
      Where  : Paint.Corners;
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
         Check_Only (Tool, Expect, Name);
         Ada.Text_IO.Put_Line
           ("  a 640 x 480 image, " & Name & ":"
            & Duration'Image (Total / Runs * 1000.0) & " ms per run");
      end Time;
   begin
      Section ("CodeReader: timing of QR Code");
      Put_Symbol (Image, Symbol, 320.0, 240.0, 6.0, Where, 0.3);
      Time (QR_Only, "QR Code only");
      Time (Everything, "all symbologies");
   end Test_Timing;

   procedure Run_All is
   begin
      Test_Versions;
      Test_Levels;
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
      Test_Timing;
   end Run_All;

   procedure Main is new AMV_Test_Support.Standalone (Run_All);

begin
   Main;
end Test_Code_Reader_QR_Code;
