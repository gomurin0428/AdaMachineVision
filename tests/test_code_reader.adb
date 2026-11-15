--  Tests for AMV.Code_Reader and its kernel AMV.Kernels.Code_Reader.
--
--  The symbols are built by AMV_Test_Barcodes, whose encoders are written
--  from the symbology definitions and share nothing with the decoders
--  (Test_Encoders checks them against published values), and are drawn
--  with AMV_Test_Images at known centres, module sizes and rotations. A
--  test reads the image back and compares the text, the centre, the
--  angle and the corners with what was drawn.
--
--  The rotations of a series are spread over the full turn in steps that
--  are not a multiple of the 15 degrees between the default scan
--  directions, so that the symbols lie at every angle to the scan lines.

pragma Validity_Checks ("F");
--  The parameter tests build NaNs on purpose.

with Ada.Calendar;
with Ada.Numerics.Long_Elementary_Functions;
with Ada.Text_IO;

with AMV;                    use AMV;
with AMV.Code_Reader;        use AMV.Code_Reader;
with AMV.Coordinate_Spaces;  use AMV.Coordinate_Spaces;
with AMV.Images;             use AMV.Images;
with AMV.Images.Kernel_Images;
with AMV.Kernels;
with AMV.Kernels.Images;
with AMV.Kernels.Regions;
with AMV.Kernels.Transforms;
with AMV.Shapes;              use AMV.Shapes;
with AMV.Shapes.Region_Holders;
with AMV.Tools;              use AMV.Tools;
with AMV.Transforms;         use AMV.Transforms;
with AMV_Test_Barcodes;
with AMV_Test_Images;
with AMV_Test_Support;       use AMV_Test_Support;

procedure Test_Code_Reader is

   package BC renames AMV_Test_Barcodes;
   package EF renames Ada.Numerics.Long_Elementary_Functions;
   package K renames AMV.Kernels;
   package KI renames AMV.Kernels.Images;
   package KR renames AMV.Kernels.Regions;
   package KT renames AMV.Kernels.Transforms;
   package RH renames AMV.Shapes.Region_Holders;
   package TI renames AMV_Test_Images;
   --  KC is AMV.Kernels.Code_Reader (renamed in AMV.Code_Reader).

   use type K.Int32;
   use type KC.Ks_Code_Reader_Results;
   use type KC.Ks_Code_Reader_Run_Params;
   use type BC.Width_List;

   Pi : constant := Ada.Numerics.Pi;

   Zero : constant Real := Real'Value ("0.0");

   W : constant := 640;
   H : constant := 480;
   --  The default scene; a symbol is drawn at its centre, (320, 240).

   subtype Kind is Ks_Code_Reader_Symbology_Constants;

   Defaults : constant Ks_Code_Reader := (others => <>);

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

   function Status_Is
     (Tool                : Ks_Code_Reader_Tool;
      Exception_Name_Part : String;
      Message             : String) return Boolean
   is (Tool.Run_Status.Result = Error
       and then AMV.Tools.Exception_Name (Tool.Run_Status)
                  = "AMV." & Exception_Name_Part
       and then AMV.Tools.Message (Tool.Run_Status) = Message);

   function Found (Tool : Ks_Code_Reader_Tool) return String;
   --  What a run gave, for the description of a failed check.

   function Found (Tool : Ks_Code_Reader_Tool) return String is
      function List (From : Natural) return String is
        (if From >= Tool.Results.Count then ""
         else " " & Symbology (Tool.Results.Item (From))'Image & " ["
              & Text (Tool.Results.Item (From)) & "]"
              & Tool.Results.Item (From).Num_Scan_Lines'Image
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
      Params : Ks_Code_Reader := Defaults) return Ks_Code_Reader_Tool;
   --  A tool that has run on Image with Params.

   function Run_On
     (Image  : Ks_Image_8_Grey;
      Params : Ks_Code_Reader := Defaults) return Ks_Code_Reader_Tool is
   begin
      return Tool : Ks_Code_Reader_Tool do
         Tool.Input_Image := Image;
         Tool.Run_Params := Params;
         Tool.Run;
      end return;
   end Run_On;

   function Index_Of
     (Tool     : Ks_Code_Reader_Tool;
      Symbol   : Kind;
      Expected : String) return Integer;
   --  The first result with that symbology and text; -1 when there is
   --  none.

   function Index_Of
     (Tool     : Ks_Code_Reader_Tool;
      Symbol   : Kind;
      Expected : String) return Integer is
   begin
      for I in 0 .. Tool.Results.Count - 1 loop
         if Tool.Results.Item (I).Symbology = Code (Symbol)
           and then Text (Tool.Results.Item (I)) = Expected
         then
            return I;
         end if;
      end loop;
      return -1;
   end Index_Of;

   function Is_Only
     (Tool     : Ks_Code_Reader_Tool;
      Symbol   : Kind;
      Expected : String) return Boolean
   is (Tool.Run_Status.Result = Accept_Result
       and then Tool.Results.Count = 1
       and then Index_Of (Tool, Symbol, Expected) = 0);
   --  The run read that symbol and nothing else.

   procedure Check_Only
     (Tool        : Ks_Code_Reader_Tool;
      Symbol      : Kind;
      Expected    : String;
      Description : String);

   procedure Check_Only
     (Tool        : Ks_Code_Reader_Tool;
      Symbol      : Kind;
      Expected    : String;
      Description : String) is
   begin
      Check (Is_Only (Tool, Symbol, Expected), Description & Found (Tool));
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

   function Scene
     (Width  : Positive := W;
      Height : Positive := H) return Ks_Image_8_Grey
   is (TI.Blank (Width, Height, 255));
   --  A white image.

   function Symbol_Image
     (Widths   : BC.Width_List;
      Module   : Real := 3.0;
      Rotation : Real := 0.0;
      Height   : Real := 80.0;
      Size_X   : Positive := W;
      Size_Y   : Positive := H) return Ks_Image_8_Grey;
   --  A white image of Size_X x Size_Y pixels with the symbol in black at
   --  its centre, (Size_X / 2, Size_Y / 2).

   function Symbol_Image
     (Widths   : BC.Width_List;
      Module   : Real := 3.0;
      Rotation : Real := 0.0;
      Height   : Real := 80.0;
      Size_X   : Positive := W;
      Size_Y   : Positive := H) return Ks_Image_8_Grey is
   begin
      return Image : Ks_Image_8_Grey := Scene (Size_X, Size_Y) do
         BC.Draw (Image, Widths, Real (Size_X / 2), Real (Size_Y / 2),
                  Module, Height, Rotation);
      end return;
   end Symbol_Image;

   type Pose_Errors is record
      Centre : Real := 0.0;
      --  The distance of the centre from the centre drawn, in pixels.
      Angle  : Real := 0.0;
      --  The angle to the rotation drawn, in radians.
      Ends   : Real := 0.0;
      --  The largest distance, along the symbol, of a corner from the end
      --  of the symbol it lies on.
   end record;

   function Pose_Of
     (R                  : Ks_Code_Reader_Result;
      Center_X, Center_Y : Real;
      Rotation           : Real;
      Length             : Real) return Pose_Errors;
   --  The errors of a result for a symbol of Length pixels drawn at that
   --  centre and rotation. The corners lie on the scan lines, which need
   --  not be parallel to the symbol, so only their position along the
   --  symbol is compared: corners 0 and 3 are at its start, 1 and 2 at
   --  its end.

   function Pose_Of
     (R                  : Ks_Code_Reader_Result;
      Center_X, Center_Y : Real;
      Rotation           : Real;
      Length             : Real) return Pose_Errors
   is
      C : constant Real := EF.Cos (Rotation);
      S : constant Real := EF.Sin (Rotation);

      function Along (X, Y : Real) return Real is
        ((X - Center_X) * C + (Y - Center_Y) * S);
   begin
      return
        (Centre => EF.Sqrt ((R.Center_X - Center_X) ** 2
                            + (R.Center_Y - Center_Y) ** 2),
         Angle  => Angle_Difference (R.Angle, Rotation),
         Ends   => Real'Max
           (Real'Max
              (abs (Along (R.Corner_0_X, R.Corner_0_Y) + Length / 2.0),
               abs (Along (R.Corner_3_X, R.Corner_3_Y) + Length / 2.0)),
            Real'Max
              (abs (Along (R.Corner_1_X, R.Corner_1_Y) - Length / 2.0),
               abs (Along (R.Corner_2_X, R.Corner_2_Y) - Length / 2.0))));
   end Pose_Of;

   Centre_Tolerance : constant := 3.0;
   Angle_Tolerance  : constant := 0.01;
   Ends_Tolerance   : constant := 1.0;
   --  What the reader keeps on clean symbols with modules of 1.5 pixels
   --  or more (largest errors seen: 2.2 pixels, 0.006 radians, 0.6
   --  pixels). The centre is that of the area between the first and the
   --  last scan line that read the symbol, which are up to a line spacing
   --  (4 pixels) away from the ends of the bars.

   function Pose_OK (E : Pose_Errors) return Boolean is
     (E.Centre <= Centre_Tolerance and then E.Angle <= Angle_Tolerance
      and then E.Ends <= Ends_Tolerance);

   function Img (E : Pose_Errors) return String is
     (" (centre off" & Img (E.Centre) & ", angle off"
      & Img (E.Angle * 180.0 / Pi) & " degrees, ends off" & Img (E.Ends)
      & ")");

   procedure Check_Symbol
     (Widths      : BC.Width_List;
      Symbol      : Kind;
      Expected    : String;
      Description : String;
      Module      : Real := 3.0;
      Rotation    : Real := 0.0;
      Params      : Ks_Code_Reader := Defaults);
   --  The symbol, drawn at the centre of the default scene, is the only
   --  result, with the pose it was drawn with.

   procedure Check_Symbol
     (Widths      : BC.Width_List;
      Symbol      : Kind;
      Expected    : String;
      Description : String;
      Module      : Real := 3.0;
      Rotation    : Real := 0.0;
      Params      : Ks_Code_Reader := Defaults)
   is
      Tool : constant Ks_Code_Reader_Tool :=
        Run_On (Symbol_Image (Widths, Module, Rotation), Params);
      E    : Pose_Errors;
   begin
      Check_Only (Tool, Symbol, Expected, Description);
      if Is_Only (Tool, Symbol, Expected) then
         E := Pose_Of (Tool.Results.Item (0), 320.0, 240.0, Rotation,
                       BC.Total (Widths) * Module);
         Check (Pose_OK (E), Description & ": pose" & Img (E));
      end if;
   end Check_Symbol;

   procedure Check_Unread
     (Widths      : BC.Width_List;
      Description : String;
      Module      : Real := 3.0;
      Params      : Ks_Code_Reader := Defaults);
   --  The symbol, drawn at the centre of the default scene, gives no
   --  result.

   procedure Check_Unread
     (Widths      : BC.Width_List;
      Description : String;
      Module      : Real := 3.0;
      Params      : Ks_Code_Reader := Defaults) is
   begin
      Check_None (Run_On (Symbol_Image (Widths, Module), Params),
                  Description);
   end Check_Unread;

   function Worse (A, B : Pose_Errors) return Pose_Errors is
     (Centre => Real'Max (A.Centre, B.Centre),
      Angle  => Real'Max (A.Angle, B.Angle),
      Ends   => Real'Max (A.Ends, B.Ends));

   function High (C : Character) return Character is
     (Character'Val (Character'Pos (C) + 128));
   --  The character 128 positions after C (Code 128 with FNC4).

   ---------------------------------------------------------------------
   --  Defaults
   ---------------------------------------------------------------------

   procedure Test_Defaults is
      Tool   : Ks_Code_Reader_Tool;
      Params : KC.Ks_Code_Reader_Run_Params;
      Status : K.Ks_Status;

      procedure Item_Of_None;

      procedure Item_Of_None is
         R : constant Ks_Code_Reader_Result := Tool.Results.Item (0);
      begin
         Check (R.Length = 0, "not reached");
      end Item_Of_None;

      procedure Check_Item_Of_None is new Check_Raises_Exactly
        (Item_Of_None, Constraint_Error'Identity);
   begin
      Section ("CodeReader: defaults");
      Check (Tool.Run_Params.Symbologies = 127
             and then Tool.Run_Params.Num_Directions = 12
             and then Tool.Run_Params.First_Direction = 0.0
             and then Tool.Run_Params.Line_Spacing = 4.0
             and then Tool.Run_Params.Contrast_Threshold = 12
             and then Tool.Run_Params.Min_Scan_Lines = 2
             and then Tool.Run_Params.Code_39_Check_Digit = 0
             and then Tool.Run_Params.ITF_Check_Digit = 0
             and then Tool.Run_Params.ITF_Min_Digits = 6,
             "the defaults of the run parameters");
      Params.Num_Directions := 99;
      KC.Run_Params_Default (Params, Status);
      Check (Status.Failure = K.Failure_None and then Params = Defaults,
             "ks_code_reader_run_params_default gives the same values");
      Check (Code (EAN_13) = 1 and then Code (EAN_8) = 2
             and then Code (UPC_A) = 4 and then Code (UPC_E) = 8
             and then Code (Code_128) = 16 and then Code (Code_39) = 32
             and then Code (ITF) = 64,
             "the symbology codes are one bit each");
      declare
         Sum : Int32 := 0;
      begin
         for Value in Kind loop
            Sum := Sum + Code (Value);
         end loop;
         Check (Sum = All_Linear_Symbologies
                and then Sum = Defaults.Symbologies,
                "AllLinearSymbologies is the sum of the codes");
      end;
      Check (Tool.Results.Count = 0, "no results before a run");
      Check_Item_Of_None ("Item of empty results raises Constraint_Error");
   end Test_Defaults;

   ---------------------------------------------------------------------
   --  The encoders of the tests
   ---------------------------------------------------------------------

   procedure Test_Encoders is
      E13 : constant BC.Width_List := BC.EAN_13 ("5901234123457");
      F   : constant Positive := E13'First;

      type Bad_Input is
        (Short_EAN, Letter_In_EAN, UPC_E_System, Odd_Code_128_C,
         Lower_Case_Code_39, Odd_ITF);

      function Rejected (Input : Bad_Input) return Boolean;
      --  The encoder raises Constraint_Error for that input.

      function Rejected (Input : Bad_Input) return Boolean is
         Runs : Natural;
      begin
         Runs :=
           (case Input is
               when Short_EAN          => BC.EAN_13 ("590123412345")'Length,
               when Letter_In_EAN      => BC.EAN_8 ("9638507A")'Length,
               when UPC_E_System       => BC.UPC_E ("21234565")'Length,
               when Odd_Code_128_C     => BC.Code_128_C ("123")'Length,
               when Lower_Case_Code_39 => BC.Code_39 ("amv")'Length,
               when Odd_ITF            => BC.ITF ("123")'Length);
         return Runs = 0;
      exception
         when Constraint_Error =>
            return True;
      end Rejected;
   begin
      Section ("CodeReader: the encoders of the tests");

      --  Check digits of published symbols.
      Check (BC.Check_Digit ("590123412345") = '7'
             and then BC.Check_Digit ("400638133393") = '1',
             "EAN-13 check digits");
      Check (BC.Check_Digit ("9638507") = '4', "EAN-8 check digit");
      Check (BC.Check_Digit ("03600029145") = '2', "UPC-A check digit");
      Check (BC.UPC_E_Check_Digit ("0123456") = '5',
             "UPC-E check digit: that of UPC-A 012345000065");
      Check (BC.Check_Digit ("1234567") = '0', "ITF check digit");
      Check (BC.Code_39_Check ("CODE 39") = 'R',
             "Code 39 check character: 113 mod 43 = 27");

      --  Lengths in modules.
      Check (BC.Total (E13) = 95.0 and then E13'Length = 59,
             "EAN-13: 95 modules in 59 runs");
      Check (BC.Total (BC.EAN_8 ("96385074")) = 67.0,
             "EAN-8: 67 modules");
      Check (BC.Total (BC.UPC_A ("036000291452")) = 95.0,
             "UPC-A: 95 modules");
      Check (BC.Total (BC.UPC_E ("01234565")) = 51.0,
             "UPC-E: 51 modules");
      Check (BC.Total (BC.Code_128_B ("Ada 2022!")) = 11.0 * 11.0 + 13.0,
             "Code 128: 11 modules a character and 13 for the stop");
      Check (BC.Total (BC.Code_128_C ("0123456789")) = 11.0 * 7.0 + 13.0,
             "Code 128 C: two digits a character");
      Check (BC.Total (BC.Code_39 ("AMV-39")) = 16.0 * 8.0 - 1.0
             and then BC.Total (BC.Code_39 ("AMV-39", 2.0))
                        = 13.0 * 8.0 - 1.0,
             "Code 39: three wide and six narrow runs and a gap");
      Check (BC.Total (BC.ITF ("0123456789")) = 4.0 + 5.0 * 18.0 + 5.0
             and then BC.Total (BC.ITF ("0123456789", 2.0))
                        = 4.0 + 5.0 * 14.0 + 4.0,
             "ITF: four wide and six narrow runs for two digits");

      --  The first runs of EAN-13 5901234123457: the guard, then 9 in
      --  number set A (0001011) and 0 in number set B (0100111).
      Check (E13 (F .. F + 2) = BC.Width_List'[1.0, 1.0, 1.0],
             "EAN-13: the start guard");
      Check (E13 (F + 3 .. F + 6) = BC.Width_List'[3.0, 1.0, 1.0, 2.0],
             "EAN-13: 9 in number set A");
      Check (E13 (F + 7 .. F + 10) = BC.Width_List'[1.0, 1.0, 2.0, 3.0],
             "EAN-13: 0 in number set B");
      Check (BC.UPC_A ("036000291452") = BC.EAN_13 ("0036000291452"),
             "UPC-A is EAN-13 with a leading 0");

      for Input in Bad_Input loop
         Check (Rejected (Input),
                "Constraint_Error for input that cannot be encoded: "
                & Input'Image);
      end loop;
   end Test_Encoders;

   ---------------------------------------------------------------------
   --  Every symbology
   ---------------------------------------------------------------------

   procedure Test_Symbologies is
   begin
      Section ("CodeReader: every symbology");
      Check_Symbol (BC.EAN_13 ("5901234123457"), EAN_13, "5901234123457",
                    "EAN-13");
      Check_Symbol (BC.EAN_13 ("4006381333931"), EAN_13, "4006381333931",
                    "another EAN-13");
      Check_Symbol (BC.EAN_8 ("96385074"), EAN_8, "96385074", "EAN-8");
      Check_Symbol (BC.UPC_A ("036000291452"), UPC_A, "036000291452",
                    "UPC-A");
      Check_Symbol (BC.UPC_E ("01234565"), UPC_E, "01234565",
                    "UPC-E, number system 0");
      Check_Symbol (BC.UPC_E ("11234562"), UPC_E, "11234562",
                    "UPC-E, number system 1");

      --  UPC-E does not draw its number system and its check digit: they
      --  are in the choice of number sets of the six digits. Every one of
      --  the twenty choices: the second digit, which has weight 1 in the
      --  check digit, takes it through the ten values.
      declare
         Seen : array (Character range '0' .. '1',
                       Character range '0' .. '9') of Boolean :=
           [others => [others => False]];
      begin
         for System in Seen'Range (1) loop
            for Second in Seen'Range (2) loop
               declare
                  Seven : constant String := System & Second & "23456";
                  Last  : constant Character :=
                    BC.UPC_E_Check_Digit (Seven);
               begin
                  Seen (System, Last) := True;
                  Check_Symbol
                    (BC.UPC_E (Seven & Last), UPC_E, Seven & Last,
                     "UPC-E, number system " & System & ", check digit "
                     & Last);
               end;
            end loop;
         end loop;
         Check ((for all S in Seen'Range (1) =>
                   (for all C in Seen'Range (2) => Seen (S, C))),
                "UPC-E: both number systems drawn with every check digit");
      end;
      Check_Symbol (BC.Code_128_B ("Ada 2022!"), Code_128, "Ada 2022!",
                    "Code 128, code set B");
      Check_Symbol (BC.Code_128_C ("0123456789"), Code_128, "0123456789",
                    "Code 128, code set C");
      Check_Symbol (BC.Code_39 ("AMV-39"), Code_39, "AMV-39", "Code 39");
      Check_Symbol (BC.ITF ("0123456789"), ITF, "0123456789", "ITF");

      --  Upside down: the text is the same, the angle is that of the
      --  symbol, from its first bar to its last.
      Check_Symbol (BC.EAN_13 ("5901234123457"), EAN_13, "5901234123457",
                    "EAN-13 turned by half a turn", Rotation => Pi);
      Check_Symbol (BC.Code_128_B ("Ada 2022!"), Code_128, "Ada 2022!",
                    "Code 128 turned by half a turn", Rotation => Pi);
      Check_Symbol (BC.Code_39 ("AMV-39"), Code_39, "AMV-39",
                    "Code 39 turned by half a turn", Rotation => Pi);
      Check_Symbol (BC.ITF ("0123456789"), ITF, "0123456789",
                    "ITF turned by half a turn", Rotation => Pi);
      Check_Symbol (BC.UPC_E ("01234565"), UPC_E, "01234565",
                    "UPC-E turned by half a turn", Rotation => Pi);

      --  The record of a horizontal symbol in full: 285 pixels long from
      --  x = 177.5 and 80 pixels tall, read by the horizontal scan lines,
      --  which are 4 pixels apart.
      declare
         Tool : constant Ks_Code_Reader_Tool :=
           Run_On (Symbol_Image (BC.EAN_13 ("5901234123457")));
         R    : Ks_Code_Reader_Result;
      begin
         if Is_Only (Tool, EAN_13, "5901234123457") then
            R := Tool.Results.Item (0);
            Check (R.Symbology = Code (EAN_13)
                   and then Symbology (R) = EAN_13 and then R.Length = 13
                   and then Text (R) = "5901234123457",
                   "Symbology, Length and Text");
            Check (R.Text (14) = Character'Val (0),
                   "a NUL follows the text");
            Check_Near (R.Center_X, 320.0, 1.0, "CenterX");
            Check_Near (R.Center_Y, 240.0, 2.5, "CenterY");
            Check_Angle_Near (R.Angle, 0.0, 0.01, "Angle");
            Check (R.Num_Scan_Lines in 19 .. 21,
                   "80 pixels of bars are crossed by about 20 scan lines:"
                   & R.Num_Scan_Lines'Image);
            Check_Near (R.Corner_0_X, 177.5, 1.0, "corner 0: the start");
            Check_Near (R.Corner_1_X, 462.5, 1.0, "corner 1: the end");
            Check_Near (R.Corner_2_X, 462.5, 1.0, "corner 2: the end");
            Check_Near (R.Corner_3_X, 177.5, 1.0, "corner 3: the start");
            Check_Near (R.Corner_1_Y, R.Corner_0_Y, 1.0E-9,
                        "corners 0 and 1 lie on one scan line");
            Check_Near (R.Corner_3_Y, R.Corner_2_Y, 1.0E-9,
                        "corners 2 and 3 lie on one scan line");
            Check_Near (abs (R.Corner_3_Y - R.Corner_0_Y),
                        4.0 * Real (R.Num_Scan_Lines - 1), 1.0E-9,
                        "the first and the last scan line are"
                        & " NumScanLines - 1 spacings apart");
            Check (Real'Min (R.Corner_0_Y, R.Corner_3_Y) in 200.0 .. 204.0
                   and then Real'Max (R.Corner_0_Y, R.Corner_3_Y)
                              in 276.0 .. 280.0,
                   "the two scan lines are the outermost on the bars");
         else
            Fail ("EAN-13, for its record" & Found (Tool));
         end if;
      end;
   end Test_Symbologies;

   ---------------------------------------------------------------------
   --  Rotations
   ---------------------------------------------------------------------

   procedure Test_Rotations is
      Steps : constant := 36;

      procedure Series
        (Widths   : BC.Width_List;
         Symbol   : Kind;
         Expected : String;
         Name     : String);
      --  The symbol at 36 rotations, 10 degrees apart.

      procedure Series
        (Widths   : BC.Width_List;
         Symbol   : Kind;
         Expected : String;
         Name     : String)
      is
         Read   : Natural := 0;
         Worst  : Pose_Errors;
         Fewest : K.Int32 := K.Int32'Last;
      begin
         for Step in 0 .. Steps - 1 loop
            declare
               Rotation : constant Real :=
                 Real (Step) * 2.0 * Pi / Real (Steps) + 0.05;
               Tool     : constant Ks_Code_Reader_Tool :=
                 Run_On (Symbol_Image (Widths, 3.0, Rotation));
            begin
               if Is_Only (Tool, Symbol, Expected) then
                  Read := Read + 1;
                  Worst := Worse
                    (Worst,
                     Pose_Of (Tool.Results.Item (0), 320.0, 240.0, Rotation,
                              BC.Total (Widths) * 3.0));
                  Fewest := K.Int32'Min
                    (Fewest, Tool.Results.Item (0).Num_Scan_Lines);
               else
                  Ada.Text_IO.Put_Line
                    ("   " & Name & " at" & Img (Rotation) & ":"
                     & Found (Tool));
               end if;
            end;
         end loop;
         Ada.Text_IO.Put_Line
           ("   " & Name & ":" & Read'Image & " of" & Integer'Image (Steps)
            & " read, at least" & Fewest'Image & " scan lines"
            & Img (Worst));
         Check (Read = Steps, Name & ": read at every rotation");
         Check (Pose_OK (Worst), Name & ": the pose at every rotation"
                & Img (Worst));
      end Series;
   begin
      Section ("CodeReader: rotations");
      Series (BC.EAN_13 ("5901234123457"), EAN_13, "5901234123457",
              "EAN-13");
      Series (BC.Code_128_B ("Ada 2022!"), Code_128, "Ada 2022!",
              "Code 128");
      Series (BC.Code_39 ("AMV-39"), Code_39, "AMV-39", "Code 39");
      Series (BC.ITF ("0123456789"), ITF, "0123456789", "ITF");
   end Test_Rotations;

   ---------------------------------------------------------------------
   --  Several symbols in one image
   ---------------------------------------------------------------------

   procedure Test_Several is
      Image : Ks_Image_8_Grey := Scene;
      Tool  : Ks_Code_Reader_Tool;

      procedure Check_Pose
        (Symbol             : Kind;
         Expected           : String;
         Center_X, Center_Y : Real;
         Rotation           : Real;
         Length             : Real);
      --  That symbol is among the results, with the pose it was drawn
      --  with.

      procedure Check_Pose
        (Symbol             : Kind;
         Expected           : String;
         Center_X, Center_Y : Real;
         Rotation           : Real;
         Length             : Real)
      is
         Index : constant Integer := Index_Of (Tool, Symbol, Expected);
         E     : Pose_Errors;
      begin
         Check (Index >= 0, Symbol'Image & " " & Expected & " is read"
                & Found (Tool));
         if Index >= 0 then
            E := Pose_Of (Tool.Results.Item (Index), Center_X, Center_Y,
                          Rotation, Length);
            Check (Pose_OK (E), Symbol'Image & " " & Expected & ": pose"
                   & Img (E));
         end if;
      end Check_Pose;
   begin
      Section ("CodeReader: several symbols in one image");

      --  Four symbologies at four rotations.
      BC.Draw (Image, BC.EAN_13 ("4006381333931"), 130.0, 80.0, 2.0, 60.0);
      BC.Draw (Image, BC.Code_128_B ("AMV-128"), 430.0, 110.0, 2.0, 60.0,
               0.4);
      BC.Draw (Image, BC.Code_39 ("KS 7"), 150.0, 320.0, 2.0, 60.0,
               Pi / 2.0);
      BC.Draw (Image, BC.ITF ("00123456"), 450.0, 350.0, 2.0, 60.0, -0.9);
      Tool := Run_On (Image);
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Count = 4,
             "four symbols give four results" & Found (Tool));
      Check_Pose (EAN_13, "4006381333931", 130.0, 80.0, 0.0, 190.0);
      Check_Pose (Code_128, "AMV-128", 430.0, 110.0, 0.4, 224.0);
      Check_Pose (Code_39, "KS 7", 150.0, 320.0, Pi / 2.0, 190.0);
      Check_Pose (ITF, "00123456", 450.0, 350.0, -0.9, 162.0);
      for I in 1 .. Tool.Results.Count - 1 loop
         Check (Tool.Results.Item (I - 1).Num_Scan_Lines
                >= Tool.Results.Item (I).Num_Scan_Lines,
                "the symbols read by the most scan lines come first:"
                & I'Image);
      end loop;

      --  Two symbols with the same text are two results: side by side on
      --  the same scan lines, and one above the other.
      Image := Scene;
      BC.Draw (Image, BC.EAN_8 ("96385074"), 160.0, 240.0, 2.0, 80.0);
      BC.Draw (Image, BC.EAN_8 ("96385074"), 480.0, 240.0, 2.0, 80.0);
      Tool := Run_On (Image);
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Count = 2
             and then Text (Tool.Results.Item (0)) = "96385074"
             and then Text (Tool.Results.Item (1)) = "96385074"
             and then abs (Tool.Results.Item (0).Center_X
                           - Tool.Results.Item (1).Center_X) in 318.0 .. 322.0,
             "two equal symbols side by side" & Found (Tool));
      Image := Scene;
      BC.Draw (Image, BC.EAN_8 ("96385074"), 320.0, 150.0, 2.0, 80.0);
      BC.Draw (Image, BC.EAN_8 ("96385074"), 320.0, 330.0, 2.0, 80.0);
      Tool := Run_On (Image);
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Count = 2
             and then Text (Tool.Results.Item (0)) = "96385074"
             and then Text (Tool.Results.Item (1)) = "96385074"
             and then abs (Tool.Results.Item (0).Center_Y
                           - Tool.Results.Item (1).Center_Y) in 177.0 .. 183.0,
             "two equal symbols one above the other" & Found (Tool));

      --  Nothing to read.
      Check_None (Run_On (Scene), "a white image");
      Check_None (Run_On (TI.Blank (W, H, 0)), "a black image");
      Image := Scene;
      TI.Draw_Rectangle (Image, 320.0, 240.0, 200.0, 100.0, 0.3, 0);
      Check_None (Run_On (Image), "a black rectangle");
      Check_None (Run_On (Scene (1, 1)), "an image of one pixel");
      Check_None (Run_On (Scene (300, 1)), "an image of one row");
   end Test_Several;

   ---------------------------------------------------------------------
   --  The region
   ---------------------------------------------------------------------

   procedure Test_Region is
      Image     : Ks_Image_8_Grey := Scene;
      Tool      : Ks_Code_Reader_Tool;
      Rectangle : Ks_Rectangle;
      Circle    : Ks_Circle;
   begin
      Section ("CodeReader: the region");

      --  An EAN-8 symbol on the left (x in 93 .. 227) and a Code 128
      --  symbol on the right (x in 392 .. 568).
      BC.Draw (Image, BC.EAN_8 ("96385074"), 160.0, 240.0, 2.0, 80.0);
      BC.Draw (Image, BC.Code_128_B ("AMV-1"), 480.0, 240.0, 2.0, 80.0);
      Tool.Input_Image := Image;
      Tool.Run;
      Check (Tool.Results.Count = 2
             and then Index_Of (Tool, EAN_8, "96385074") >= 0
             and then Index_Of (Tool, Code_128, "AMV-1") >= 0,
             "no region: both symbols" & Found (Tool));

      Rectangle.Set_XY_Width_Height (0.0, 0.0, 320.0, 480.0);
      Tool.Region := RH.To_Holder (Rectangle);
      Tool.Run;
      Check_Only (Tool, EAN_8, "96385074", "the left half of the image");

      Rectangle.Set_XY_Width_Height (320.0, 0.0, 320.0, 480.0);
      Tool.Region := RH.To_Holder (Rectangle);
      Tool.Run;
      Check_Only (Tool, Code_128, "AMV-1", "the right half of the image");

      Rectangle.Set_XY_Width_Height (60.0, 190.0, 200.0, 100.0);
      Tool.Region := RH.To_Holder (Rectangle);
      Tool.Run;
      Check_Only (Tool, EAN_8, "96385074",
                  "a rectangle around the symbol and its margins");

      Rectangle.Set_XY_Width_Height (0.0, 0.0, 160.0, 480.0);
      Tool.Region := RH.To_Holder (Rectangle);
      Tool.Run;
      Check_None (Tool, "a region with half of a symbol");

      Rectangle.Set_XY_Width_Height (100.0, 0.0, 120.0, 480.0);
      Tool.Region := RH.To_Holder (Rectangle);
      Tool.Run;
      Check_None (Tool, "a region without the light margins of the symbol");

      Rectangle.Set_XY_Width_Height (700.0, 500.0, 50.0, 50.0);
      Tool.Region := RH.To_Holder (Rectangle);
      Tool.Run;
      Check_None (Tool, "a region outside the image");

      Rectangle.Set_XY_Width_Height (-500.0, -500.0, 820.0, 2000.0);
      Tool.Region := RH.To_Holder (Rectangle);
      Tool.Run;
      Check_Only (Tool, EAN_8, "96385074",
                  "a region that reaches beyond the image");

      Circle.Set_Center_Radius (160.0, 240.0, 110.0);
      Tool.Region := RH.To_Holder (Circle);
      Tool.Run;
      Check_Only (Tool, EAN_8, "96385074", "a circle around a symbol");

      Circle.Set_Center_Radius (160.0, 240.0, 60.0);
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
   --  The symbologies to read
   ---------------------------------------------------------------------

   procedure Test_Symbology_Mask is

      function Only (Symbologies : Int32) return Ks_Code_Reader is
        ((Defaults with delta Symbologies => Symbologies));

      procedure Check_Alone
        (Widths   : BC.Width_List;
         Symbol   : Kind;
         Expected : String;
         Module   : Real := 3.0);
      --  The symbol is read when its symbology is the only one enabled
      --  and gives nothing when it is the only one disabled.

      procedure Check_Alone
        (Widths   : BC.Width_List;
         Symbol   : Kind;
         Expected : String;
         Module   : Real := 3.0)
      is
         Image : constant Ks_Image_8_Grey := Symbol_Image (Widths, Module);
      begin
         Check_Only (Run_On (Image, Only (Code (Symbol))), Symbol, Expected,
                     Symbol'Image & " alone");
         Check_None
           (Run_On (Image, Only (All_Linear_Symbologies - Code (Symbol))),
            "every symbology but " & Symbol'Image);
      end Check_Alone;

      UPC   : constant Ks_Image_8_Grey :=
        Symbol_Image (BC.UPC_A ("036000291452"));
      EAN   : constant Ks_Image_8_Grey :=
        Symbol_Image (BC.EAN_13 ("5901234123457"));
   begin
      Section ("CodeReader: the symbologies to read");
      Check_Alone (BC.EAN_13 ("5901234123457"), EAN_13, "5901234123457");
      Check_Alone (BC.EAN_8 ("96385074"), EAN_8, "96385074");
      Check_Alone (BC.UPC_E ("01234565"), UPC_E, "01234565");
      Check_Alone (BC.Code_128_B ("Ada 2022!"), Code_128, "Ada 2022!");
      Check_Alone (BC.Code_39 ("AMV-39"), Code_39, "AMV-39");
      Check_Alone (BC.ITF ("0123456789"), ITF, "0123456789");

      Check_Only (Run_On (EAN, Only (Code (EAN_13) + Code (Code_128))),
                  EAN_13, "5901234123457", "a sum of two codes");
      Check_None (Run_On (EAN, Only (Code (EAN_8) + Code (UPC_E)
                                     + Code (Code_39) + Code (ITF))),
                  "a sum of four other codes");

      --  A UPC-A symbol is an EAN-13 symbol with a leading 0: it is
      --  reported as UPC-A when UPC-A is enabled, else as EAN-13 with
      --  its 13 digits.
      Check_Only (Run_On (UPC), UPC_A, "036000291452",
                  "UPC-A with every symbology");
      Check_Only (Run_On (UPC, Only (Code (UPC_A))), UPC_A, "036000291452",
                  "UPC-A alone");
      Check_Only (Run_On (UPC, Only (Code (UPC_A) + Code (EAN_13))),
                  UPC_A, "036000291452", "UPC-A and EAN-13");
      Check_Only (Run_On (UPC, Only (Code (EAN_13))),
                  EAN_13, "0036000291452",
                  "a UPC-A symbol with EAN-13 alone: 13 digits");
      Check_Only
        (Run_On (UPC, Only (All_Linear_Symbologies - Code (UPC_A))),
         EAN_13, "0036000291452",
         "a UPC-A symbol with every symbology but UPC-A");
      Check_None
        (Run_On (UPC, Only (All_Linear_Symbologies - Code (UPC_A)
                            - Code (EAN_13))),
         "a UPC-A symbol with neither UPC-A nor EAN-13");
      Check_None (Run_On (EAN, Only (Code (UPC_A))),
                  "an EAN-13 symbol that does not start with 0, UPC-A"
                  & " alone");
   end Test_Symbology_Mask;

   ---------------------------------------------------------------------
   --  Check digits
   ---------------------------------------------------------------------

   procedure Test_Check_Digits is
      With_39  : constant Ks_Code_Reader :=
        (Defaults with delta Code_39_Check_Digit => 1);
      With_ITF : constant Ks_Code_Reader :=
        (Defaults with delta ITF_Check_Digit => 1);
   begin
      Section ("CodeReader: check digits");

      --  EAN and UPC: always checked.
      Check_Unread (BC.EAN_13 ("5901234123456"), "EAN-13, wrong check digit");
      Check_Unread (BC.EAN_13 ("5901234123467"), "EAN-13, one digit changed");
      Check_Unread (BC.EAN_8 ("96385075"), "EAN-8, wrong check digit");
      Check_Unread (BC.UPC_A ("036000291453"), "UPC-A, wrong check digit");
      Check_Unread (BC.UPC_E ("01234566"), "UPC-E, wrong check digit");

      --  Code 128: the check character is not part of the text.
      Check_Unread
        (BC.Code_128 ([BC.Start_B, 33, 34, 35], Check_Error => 1),
         "Code 128, wrong check character");
      Check_Unread
        (BC.Code_128 ([BC.Start_B, 33, 34, 35], Check_Error => 57),
         "Code 128, another wrong check character");
      Check_Symbol (BC.Code_128 ([BC.Start_B, 33, 34, 35]), Code_128, "ABC",
                    "Code 128, right check character");

      --  Code 39: checked on request; the check character stays in the
      --  text.
      Check_Symbol (BC.Code_39 ("CODE 39R"), Code_39, "CODE 39R",
                    "Code 39 with its check character, checked",
                    Module => 2.0, Params => With_39);
      Check_Symbol (BC.Code_39 ("CODE 39R"), Code_39, "CODE 39R",
                    "Code 39 with its check character, not checked",
                    Module => 2.0);
      Check_Unread (BC.Code_39 ("CODE 39X"),
                    "Code 39 with a wrong check character, checked",
                    Module => 2.0, Params => With_39);
      Check_Symbol (BC.Code_39 ("CODE 39X"), Code_39, "CODE 39X",
                    "Code 39 with a wrong check character, not checked",
                    Module => 2.0);
      Check_Symbol (BC.Code_39 ("0"), Code_39, "0",
                    "Code 39 with one character, not checked");
      Check_Unread (BC.Code_39 ("0"),
                    "Code 39 with one character, checked: no room for"
                    & " data before the check character",
                    Params => With_39);

      --  ITF: checked on request; the check digit stays in the text.
      Check_Symbol (BC.ITF ("12345670"), ITF, "12345670",
                    "ITF with its check digit, checked",
                    Params => With_ITF);
      Check_Unread (BC.ITF ("12345671"),
                    "ITF with a wrong check digit, checked",
                    Params => With_ITF);
      Check_Symbol (BC.ITF ("12345671"), ITF, "12345671",
                    "ITF with a wrong check digit, not checked");

      --  ITF has no start or stop pattern to speak of, so short symbols
      --  are easily seen in other patterns: ITFMinDigits.
      Check_Unread (BC.ITF ("1234"), "ITF with 4 digits, at least 6 asked");
      Check_Symbol (BC.ITF ("1234"), ITF, "1234",
                    "ITF with 4 digits, at least 4 asked",
                    Params => (Defaults with delta ITF_Min_Digits => 4));
      Check_Symbol (BC.ITF ("12"), ITF, "12",
                    "ITF with 2 digits, at least 2 asked",
                    Params => (Defaults with delta ITF_Min_Digits => 2));
      Check_Symbol (BC.ITF ("123456"), ITF, "123456",
                    "ITF with 6 digits, at least 6 asked");
      Check_Unread (BC.ITF ("0123456789"),
                    "ITF with 10 digits, at least 12 asked",
                    Params => (Defaults with delta ITF_Min_Digits => 12));
      Check_Symbol (BC.ITF ("012345678901"), ITF, "012345678901",
                    "ITF with 12 digits, at least 12 asked",
                    Params => (Defaults with delta ITF_Min_Digits => 12));
   end Test_Check_Digits;

   ---------------------------------------------------------------------
   --  Code 128: code sets and function characters
   ---------------------------------------------------------------------

   procedure Test_Code_128_Sets is
      HT : constant Character := Character'Val (9);
      LF : constant Character := Character'Val (10);
      CR : constant Character := Character'Val (13);
      GS : constant Character := Character'Val (29);

      procedure Check_Values
        (Values      : BC.Value_List;
         Expected    : String;
         Description : String);
      --  The symbol with those values gives that text.

      procedure Check_Values
        (Values      : BC.Value_List;
         Expected    : String;
         Description : String) is
      begin
         Check_Symbol (BC.Code_128 (Values), Code_128, Expected, Description,
                       Module => 2.0);
      end Check_Values;
   begin
      Section ("CodeReader: Code 128 code sets and function characters");

      --  Code set A: values 0 .. 63 are the characters 32 .. 95, values
      --  64 .. 95 the control characters 0 .. 31.
      Check_Values ([BC.Start_A, 33, 34, 73, 35], "AB" & HT & "C",
                    "code set A with a control character");
      Check_Values ([BC.Start_A, 33, 64, 34], "A" & Character'Val (0) & "B",
                    "code set A with NUL: the length counts it");
      Check_Values ([BC.Start_A, 0, 63, 95], " _" & Character'Val (31),
                    "code set A: the ends of its ranges");

      --  Code set B: values 0 .. 95 are the characters 32 .. 127.
      Check_Values ([BC.Start_B, 0, 65, 94, 95],
                    " a~" & Character'Val (127),
                    "code set B: the ends of its range");

      --  Changes of code set.
      Check_Values ([BC.Start_B, 41, 36, BC.Code_C, 12, 34, 56,
                     BC.Code_B, 1],
                    "ID123456!", "code set B, C and B again");
      Check_Values ([BC.Start_C, 98, 76, 54, BC.Code_A, 33, 77],
                    "987654A" & CR, "code set C, then A");
      Check_Values ([BC.Start_A, 33, BC.Code_B, 65, BC.Code_A, 74],
                    "Aa" & LF, "code set A, B and A again");
      Check_Values ([BC.Start_C, 0, 99],
                    "0099", "code set C: 00 and 99");

      --  Shift: one character of the other of the sets A and B.
      Check_Values ([BC.Start_B, 65, BC.Shift, 74, 66], "a" & LF & "b",
                    "Shift in code set B");
      Check_Values ([BC.Start_A, 33, BC.Shift, 65, 34], "AaB",
                    "Shift in code set A");

      --  FNC1: nothing in the first position, the separator GS later.
      Check_Values ([BC.Start_C, BC.FNC_1, 0, 12, 34, 56], "00123456",
                    "FNC1 first adds nothing");
      Check_Values ([BC.Start_B, 33, BC.FNC_1, 34], "A" & GS & "B",
                    "FNC1 later is GS");
      Check_Values ([BC.Start_C, BC.FNC_1, 10, 12, BC.FNC_1, 21, 34],
                    "1012" & GS & "2134", "FNC1 first and later");

      --  FNC2 and FNC3 add nothing.
      Check_Values ([BC.Start_B, 33, BC.FNC_2, 34, BC.FNC_3, 35], "ABC",
                    "FNC2 and FNC3");

      --  FNC4: once for the next character, twice to switch for the
      --  characters that follow; the characters are 128 higher.
      Check_Values ([BC.Start_B, 33, BC.FNC_4_B, 33, 34],
                    "A" & High ('A') & "B", "FNC4 once in code set B");
      Check_Values ([BC.Start_A, BC.FNC_4_A, 33], [1 => High ('A')],
                    "FNC4 once in code set A");
      Check_Values ([BC.Start_B, BC.FNC_4_B, BC.FNC_4_B, 33, 34,
                     BC.FNC_4_B, 35, 36, BC.FNC_4_B, BC.FNC_4_B, 37],
                    High ('A') & High ('B') & "C" & High ('D') & "E",
                    "FNC4 twice, once within, and twice again");

      --  A symbol must hold text.
      Check_Unread (BC.Code_128 ([1 => BC.Start_B]),
                    "Code 128 without data");
      Check_Unread (BC.Code_128 ([BC.Start_C, BC.FNC_1]),
                    "Code 128 with FNC1 only");

      --  A long symbol: 30 digits in 15 characters, 400 pixels.
      Check_Symbol (BC.Code_128_C ("123456789012345678901234567890"),
                    Code_128, "123456789012345678901234567890",
                    "30 digits in code set C", Module => 2.0);
      Check_Symbol (BC.Code_128_B ("Hello, World! 123"), Code_128,
                    "Hello, World! 123", "17 characters in code set B",
                    Module => 2.0);
   end Test_Code_128_Sets;

   ---------------------------------------------------------------------
   --  Code 39 and ITF: characters and ratios
   ---------------------------------------------------------------------

   procedure Test_Code_39_And_ITF is
      Ratios : constant array (1 .. 5) of Real := [2.0, 2.25, 2.5, 2.75, 3.0];
   begin
      Section ("CodeReader: Code 39 and ITF, characters and ratios");

      --  The 43 characters of Code 39.
      Check_Symbol (BC.Code_39 ("0123456789"), Code_39, "0123456789",
                    "Code 39: the digits", Module => 2.0);
      Check_Symbol (BC.Code_39 ("ABCDEFGHIJKLM"), Code_39, "ABCDEFGHIJKLM",
                    "Code 39: A to M", Module => 2.0);
      Check_Symbol (BC.Code_39 ("NOPQRSTUVWXYZ"), Code_39, "NOPQRSTUVWXYZ",
                    "Code 39: N to Z", Module => 2.0);
      Check_Symbol (BC.Code_39 ("-. $/+%"), Code_39, "-. $/+%",
                    "Code 39: the other seven", Module => 2.0);

      --  The ten digits of ITF in both positions of a pair.
      Check_Symbol (BC.ITF ("0123456789"), ITF, "0123456789",
                    "ITF: the digits in bars and spaces", Module => 2.0);
      Check_Symbol (BC.ITF ("1032547698"), ITF, "1032547698",
                    "ITF: the digits in spaces and bars", Module => 2.0);
      Check_Symbol (BC.ITF ("9876543210"), ITF, "9876543210",
                    "ITF: the digits backwards", Module => 2.0);

      --  Wide runs of 2 to 3 modules.
      for Ratio of Ratios loop
         Check_Symbol (BC.Code_39 ("AMV-39", Ratio), Code_39, "AMV-39",
                       "Code 39, wide runs of" & Img (Ratio) & " modules",
                       Module => 2.0);
         Check_Symbol (BC.ITF ("0123456789", Ratio), ITF, "0123456789",
                       "ITF, wide runs of" & Img (Ratio) & " modules",
                       Module => 2.0);
         Check_Symbol (BC.Code_39 ("AMV-39", Ratio), Code_39, "AMV-39",
                       "Code 39 rotated, wide runs of" & Img (Ratio)
                       & " modules",
                       Module => 2.0, Rotation => 2.2);
         Check_Symbol (BC.ITF ("0123456789", Ratio), ITF, "0123456789",
                       "ITF rotated, wide runs of" & Img (Ratio)
                       & " modules",
                       Module => 2.0, Rotation => 0.6);
      end loop;
   end Test_Code_39_And_ITF;

   ---------------------------------------------------------------------
   --  Image quality
   ---------------------------------------------------------------------

   procedure Test_Quality is
      Size  : constant := 400;
      Turns : constant := 7;
      --  Four symbols at seven rotations each, in images of 400 x 400
      --  pixels: 28 images for every condition.

      type Condition is record
         Module    : Real := 3.0;
         Blur      : Real := 0.0;
         --  The standard deviation of the blur, in pixels.
         Growth    : Real := 0.0;
         --  What the bars gain in width, in pixels.
         Dark      : Grey_8 := 0;
         Light     : Grey_8 := 255;
         Shade_To  : Real := 1.0;
         --  The lighting at the right border, as a part of that at the
         --  left border.
         Sharpen   : Real := 0.0;
         --  The amount of an unsharp mask of one pixel, after the blur.
         Noise     : Real := 0.0;
         --  The amplitude of the noise, in grey levels.
         Threshold : Int32 := 12;
         --  ContrastThreshold.
      end record;

      Clean : constant Condition := (others => <>);

      function Widths (Symbol : Positive) return BC.Width_List is
        (case Symbol is
            when 1      => BC.EAN_13 ("5901234123457"),
            when 2      => BC.Code_128_B ("AMV 12"),
            when 3      => BC.Code_39 ("K-7"),
            when others => BC.ITF ("12345678"));

      function Expected (Symbol : Positive) return String is
        (case Symbol is
            when 1      => "5901234123457",
            when 2      => "AMV 12",
            when 3      => "K-7",
            when others => "12345678");

      function Kind_Of (Symbol : Positive) return Kind is
        (case Symbol is
            when 1      => EAN_13,
            when 2      => Code_128,
            when 3      => Code_39,
            when others => ITF);

      procedure Series
        (C           : Condition;
         Name        : String;
         Exactly_One : Boolean := True);
      --  Every image of the series is read, with no other text; with
      --  Exactly_One, there is one result per image.

      procedure Series
        (C           : Condition;
         Name        : String;
         Exactly_One : Boolean := True)
      is
         Read  : Natural := 0;
         Wrong : Natural := 0;
         Extra : Natural := 0;
         Seed  : Natural := 0;
      begin
         for Symbol in 1 .. 4 loop
            for Turn in 0 .. Turns - 1 loop
               declare
                  Rotation : constant Real :=
                    Real (Turn) * 2.0 * Pi / Real (Turns)
                    + 0.1 * Real (Symbol);
                  Image    : Ks_Image_8_Grey :=
                    TI.Blank (Size, Size, C.Light);
                  Tool     : Ks_Code_Reader_Tool;
                  Matches  : Natural := 0;
               begin
                  BC.Draw (Image, Widths (Symbol), Real (Size / 2),
                           Real (Size / 2), C.Module, 80.0, Rotation,
                           C.Dark, C.Growth);
                  BC.Blur (Image, C.Blur);
                  if C.Sharpen > 0.0 then
                     BC.Sharpen (Image, 1.0, C.Sharpen);
                  end if;
                  if C.Shade_To /= 1.0 then
                     BC.Shade (Image, 1.0, C.Shade_To);
                  end if;
                  if C.Noise > 0.0 then
                     Seed := Seed + 1;
                     TI.Add_Noise (Image, C.Noise, Seed);
                  end if;
                  Tool := Run_On
                    (Image,
                     (Defaults with delta Contrast_Threshold => C.Threshold));
                  for I in 0 .. Tool.Results.Count - 1 loop
                     if Tool.Results.Item (I).Symbology
                          = Code (Kind_Of (Symbol))
                       and then Text (Tool.Results.Item (I))
                                  = Expected (Symbol)
                     then
                        Matches := Matches + 1;
                     else
                        Wrong := Wrong + 1;
                     end if;
                  end loop;
                  if Matches >= 1 then
                     Read := Read + 1;
                     Extra := Extra + Matches - 1;
                  end if;
                  if Matches = 0 or else Tool.Results.Count /= 1 then
                     Ada.Text_IO.Put_Line
                       ("   " & Name & ": " & Kind_Of (Symbol)'Image & " at"
                        & Img (Rotation) & Found (Tool));
                  end if;
               end;
            end loop;
         end loop;
         Check (Read = 4 * Turns and then Wrong = 0,
                Name & ": every symbol read, no other text (read"
                & Read'Image & " of" & Integer'Image (4 * Turns) & ", wrong"
                & Wrong'Image & ")");
         if Exactly_One then
            Check (Extra = 0, Name & ": one result per symbol (extra"
                   & Extra'Image & ")");
         end if;
      end Series;
   begin
      Section ("CodeReader: image quality");
      Series (Clean, "clean");
      Series ((Clean with delta Module => 2.0), "modules of 2 pixels");
      Series ((Clean with delta Module => 1.5), "modules of 1.5 pixels");

      --  Blur: out of focus.
      Series ((Clean with delta Blur => 1.0), "blur 1.0");
      Series ((Clean with delta Blur => 1.5), "blur 1.5");
      Series ((Clean with delta Blur => 2.0), "blur 2.0");
      Series ((Clean with delta Module => 2.0, Blur => 1.0),
              "modules of 2 pixels, blur 1.0", Exactly_One => False);

      --  Ink spread and ink loss: the bars one pixel wider or narrower.
      Series ((Clean with delta Growth => 1.0), "bars 1 pixel wider");
      Series ((Clean with delta Growth => -1.0), "bars 1 pixel narrower");
      Series ((Clean with delta Growth => 1.0, Blur => 1.0),
              "bars 1 pixel wider, blur 1.0");

      --  A sharpened image: an overshoot of about a fifth of the contrast
      --  on both sides of every edge, which dips in the middle of a wide
      --  space and of a wide bar. Such a dip is no edge beside the jump of
      --  the levels at a bar. A symbol may be reported twice here, for
      --  the dips still break some scan lines.
      Series ((Clean with delta Dark => 60, Light => 180, Sharpen => 0.75),
              "sharpened by 0.75", Exactly_One => False);
      Series ((Clean with delta Module => 2.0, Dark => 60, Light => 180,
               Sharpen => 0.75),
              "modules of 2 pixels, sharpened by 0.75",
              Exactly_One => False);
      Series ((Clean with delta Blur => 0.5, Dark => 60, Light => 180,
               Sharpen => 1.0),
              "blur 0.5, sharpened by 1.0", Exactly_One => False);

      --  Low contrast: 40 grey levels between bars and spaces.
      Series ((Clean with delta Dark => 100, Light => 140),
              "contrast 40");
      Series ((Clean with delta Dark => 100, Light => 140, Noise => 5.0),
              "contrast 40, noise 5");

      --  Uneven lighting: the right border at 30 % of the left one.
      Series ((Clean with delta Shade_To => 0.3), "shading to 30 %");

      --  Noise: the threshold must be above its swing.
      Series ((Clean with delta Noise => 20.0, Threshold => 60),
              "noise 20, ContrastThreshold 60");
      Series ((Clean with delta Noise => 40.0, Threshold => 100),
              "noise 40, ContrastThreshold 100");
      Series ((Clean with delta Blur => 1.0, Noise => 20.0, Threshold => 60),
              "blur 1.0, noise 20, ContrastThreshold 60");

      --  All of it: dark 20, light 230, blur, shading to 40 %, noise.
      Series ((Module => 3.0, Blur => 1.0, Growth => 0.0, Dark => 20,
               Light => 230, Shade_To => 0.4, Sharpen => 0.0, Noise => 10.0,
               Threshold => 30),
              "blur, shading and noise, ContrastThreshold 30");
   end Test_Quality;

   ---------------------------------------------------------------------
   --  Bars that gained or lost width (EAN and UPC)
   ---------------------------------------------------------------------

   procedure Test_Bar_Gain is
      Size  : constant := 500;
      Turns : constant := 7;
      --  Four symbols at seven rotations each: 28 images for every
      --  condition.
      --
      --  The digits 1 and 7, and 2 and 8, of EAN and UPC have the same
      --  distances between edges of the same kind and differ only in how
      --  wide their bars and spaces are, which is what ink spread, ink
      --  loss or a bright exposure change. The symbols here have these
      --  four digits only (but for the number system of UPC-E), in every
      --  number set, with bars more than half a module wider or narrower
      --  than they should be: without the correction by the widths of
      --  the guard patterns every symbol would be read as another number
      --  or not at all.

      function Digit_Text (Symbol : Positive) return String is
        (case Symbol is
            when 1      => "712817281278" & BC.Check_Digit ("712817281278"),
            when 2      => "7128172" & BC.Check_Digit ("7128172"),
            when 3      => "72817218271" & BC.Check_Digit ("72817218271"),
            when others => "0172817" & BC.UPC_E_Check_Digit ("0172817"));

      function Widths (Symbol : Positive) return BC.Width_List is
        (case Symbol is
            when 1      => BC.EAN_13 (Digit_Text (1)),
            when 2      => BC.EAN_8 (Digit_Text (2)),
            when 3      => BC.UPC_A (Digit_Text (3)),
            when others => BC.UPC_E (Digit_Text (4)));

      function Kind_Of (Symbol : Positive) return Kind is
        (case Symbol is
            when 1      => EAN_13,
            when 2      => EAN_8,
            when 3      => UPC_A,
            when others => UPC_E);

      procedure Series
        (Module : Real;
         Gain   : Real;
         Blur   : Real;
         Name   : String);
      --  Modules of Module pixels, every bar Gain modules wider, then a
      --  blur of standard deviation Blur pixels: every symbol is read,
      --  once, and nothing else is.

      procedure Series
        (Module : Real;
         Gain   : Real;
         Blur   : Real;
         Name   : String)
      is
         Read  : Natural := 0;
         Wrong : Natural := 0;
         Extra : Natural := 0;
      begin
         for Symbol in 1 .. 4 loop
            for Turn in 0 .. Turns - 1 loop
               declare
                  Rotation : constant Real :=
                    Real (Turn) * 2.0 * Pi / Real (Turns)
                    + 0.1 * Real (Symbol);
                  Image    : Ks_Image_8_Grey := TI.Blank (Size, Size, 255);
                  Tool     : Ks_Code_Reader_Tool;
                  Matches  : Natural := 0;
               begin
                  BC.Draw (Image, Widths (Symbol), Real (Size / 2),
                           Real (Size / 2), Module, 80.0, Rotation,
                           Bar_Growth => Gain * Module);
                  BC.Blur (Image, Blur);
                  Tool := Run_On (Image);
                  for I in 0 .. Tool.Results.Count - 1 loop
                     if Tool.Results.Item (I).Symbology
                          = Code (Kind_Of (Symbol))
                       and then Text (Tool.Results.Item (I))
                                  = Digit_Text (Symbol)
                     then
                        Matches := Matches + 1;
                     else
                        Wrong := Wrong + 1;
                     end if;
                  end loop;
                  if Matches >= 1 then
                     Read := Read + 1;
                     Extra := Extra + Matches - 1;
                  end if;
                  if Matches = 0 or else Tool.Results.Count /= 1 then
                     Ada.Text_IO.Put_Line
                       ("   " & Name & ": " & Kind_Of (Symbol)'Image & " at"
                        & Img (Rotation) & Found (Tool));
                  end if;
               end;
            end loop;
         end loop;
         Check (Read = 4 * Turns and then Wrong = 0,
                Name & ": every symbol read, no other text (read"
                & Read'Image & " of" & Integer'Image (4 * Turns) & ", wrong"
                & Wrong'Image & ")");
         Check (Extra = 0, Name & ": one result per symbol (extra"
                & Extra'Image & ")");
      end Series;
   begin
      Section ("CodeReader: bars that gained or lost width");
      Check (Digit_Text (1) = "7128172812788"
             and then Digit_Text (2) = "71281728"
             and then Digit_Text (3) = "728172182712"
             and then Digit_Text (4) = "01728170",
             "the digits of the symbols are 1, 2, 7 and 8");
      Series (3.0, 0.0, 0.0, "bars as they should be");
      Series (3.0, 0.6, 0.0, "bars 0.6 module wider");
      Series (3.0, -0.6, 0.0, "bars 0.6 module narrower");
      Series (3.0, 0.6, 1.0, "bars 0.6 module wider, blur 1.0");
      Series (3.0, -0.6, 1.0, "bars 0.6 module narrower, blur 1.0");
      Series (4.0, 0.7, 0.0, "modules of 4 pixels, bars 0.7 module wider");
      Series (4.0, -0.7, 0.0,
              "modules of 4 pixels, bars 0.7 module narrower");
      Series (2.0, 0.5, 0.0, "modules of 2 pixels, bars 0.5 module wider");
      Series (2.0, -0.5, 0.0,
              "modules of 2 pixels, bars 0.5 module narrower");
   end Test_Bar_Gain;

   ---------------------------------------------------------------------
   --  Small modules
   ---------------------------------------------------------------------

   procedure Test_Small_Modules is
      Widths : constant BC.Width_List := BC.EAN_13 ("5901234123457");
      One    : constant Ks_Code_Reader :=
        (Defaults with delta Num_Directions => 1);
      Read   : Natural := 0;
      Runs   : Natural := 0;
      Worst  : Pose_Errors;
   begin
      Section ("CodeReader: small modules");

      --  Modules of 1.25 to 2.5 pixels in steps of an eighth, each at
      --  four positions a quarter of a pixel apart, along the pixel rows.
      for Eighths in 10 .. 20 loop
         for Phase in 0 .. 3 loop
            declare
               Module : constant Real := Real (Eighths) / 8.0;
               X      : constant Real := 320.0 + Real (Phase) / 4.0;
               Image  : Ks_Image_8_Grey := Scene;
               Tool   : Ks_Code_Reader_Tool;
            begin
               BC.Draw (Image, Widths, X, 240.0, Module, 80.0);
               Tool := Run_On (Image, One);
               Runs := Runs + 1;
               if Is_Only (Tool, EAN_13, "5901234123457") then
                  Read := Read + 1;
                  Worst := Worse
                    (Worst,
                     Pose_Of (Tool.Results.Item (0), X, 240.0, 0.0,
                              95.0 * Module));
               else
                  Ada.Text_IO.Put_Line
                    ("   module" & Img (Module) & " at" & Img (X) & ":"
                     & Found (Tool));
               end if;
            end;
         end loop;
      end loop;
      Check (Read = Runs,
             "EAN-13 with modules of 1.25 to 2.5 pixels along the rows:"
             & Read'Image & " of" & Runs'Image);
      Check (Pose_OK (Worst), "their pose" & Img (Worst));

      --  At any rotation the modules must be somewhat larger: 1.5 pixels
      --  are read (Test_Quality).
   end Test_Small_Modules;

   ---------------------------------------------------------------------
   --  The shape of a symbol and the number of directions
   ---------------------------------------------------------------------

   procedure Test_Aspect is

      procedure Series
        (Widths     : BC.Width_List;
         Symbol     : Kind;
         Expected   : String;
         Directions : Positive;
         Rotations  : Positive;
         Part       : Real;
         Name       : String);
      --  The symbol, with bars Part of its length tall, at Rotations
      --  rotations that lie halfway between two scan directions: as far
      --  from a scan direction as a symbol can be.

      procedure Series
        (Widths     : BC.Width_List;
         Symbol     : Kind;
         Expected   : String;
         Directions : Positive;
         Rotations  : Positive;
         Part       : Real;
         Name       : String)
      is
         Length : constant Real := BC.Total (Widths) * 3.0;
         Step   : constant Real := Pi / Real (Directions);
         Read   : Natural := 0;
      begin
         for Turn in 0 .. Rotations - 1 loop
            declare
               Rotation : constant Real :=
                 (Real (Turn * (2 * Directions / Rotations)) + 0.5) * Step;
               Tool     : constant Ks_Code_Reader_Tool :=
                 Run_On
                   (Symbol_Image (Widths, 3.0, Rotation, Part * Length),
                    (Defaults with delta
                       Num_Directions => Int32 (Directions)));
            begin
               if Is_Only (Tool, Symbol, Expected) then
                  Read := Read + 1;
               else
                  Ada.Text_IO.Put_Line
                    ("   " & Name & " at" & Img (Rotation) & ":"
                     & Found (Tool));
               end if;
            end;
         end loop;
         Check (Read = Rotations,
                Name & ":" & Read'Image & " of" & Rotations'Image);
      end Series;
   begin
      Section ("CodeReader: the shape of a symbol");

      --  A scan line must cross all the bars. The nearest scan direction
      --  is at most 90 / NumDirections degrees from the symbol, so the
      --  bars must be about tan (90 / NumDirections) of the length tall,
      --  and some scan lines more: 13 % for 12 directions, 27 % for 6
      --  and 7 % for 24.
      Series (BC.EAN_13 ("5901234123457"), EAN_13, "5901234123457",
              12, 24, 0.2,
              "EAN-13, bars a fifth of the length, 12 directions");
      Series (BC.Code_128_B ("Ada 2022!"), Code_128, "Ada 2022!",
              12, 24, 0.2,
              "Code 128, bars a fifth of the length, 12 directions");
      Series (BC.Code_39 ("AMV-39"), Code_39, "AMV-39",
              12, 24, 0.2,
              "Code 39, bars a fifth of the length, 12 directions");
      Series (BC.ITF ("0123456789"), ITF, "0123456789",
              12, 24, 0.2,
              "ITF, bars a fifth of the length, 12 directions");
      Series (BC.EAN_13 ("5901234123457"), EAN_13, "5901234123457",
              24, 24, 0.1,
              "EAN-13, bars a tenth of the length, 24 directions");
      Series (BC.EAN_13 ("5901234123457"), EAN_13, "5901234123457",
              6, 12, 0.3,
              "EAN-13, bars three tenths of the length, 6 directions");
   end Test_Aspect;

   ---------------------------------------------------------------------
   --  Scan directions
   ---------------------------------------------------------------------

   procedure Test_Directions is
      Widths : constant BC.Width_List := BC.EAN_13 ("5901234123457");
      Flat   : constant Ks_Image_8_Grey := Symbol_Image (Widths);
      Up     : constant Ks_Image_8_Grey :=
        Symbol_Image (Widths, Rotation => Pi / 2.0);
      Tilted : constant Ks_Image_8_Grey :=
        Symbol_Image (Widths, Rotation => 0.3);
      One    : constant Ks_Code_Reader :=
        (Defaults with delta Num_Directions => 1);
      Tool   : Ks_Code_Reader_Tool;
   begin
      Section ("CodeReader: scan directions");

      --  One direction: along the rows.
      Check_Only (Run_On (Flat, One), EAN_13, "5901234123457",
                  "one direction: a symbol along the rows");
      Check_None (Run_On (Up, One),
                  "one direction: a symbol along the columns");
      Check_None (Run_On (Tilted, One),
                  "one direction: a symbol at 0.3 radians");

      --  FirstDirection turns the directions.
      Tool := Run_On (Up, (One with delta First_Direction => Pi / 2.0));
      Check_Only (Tool, EAN_13, "5901234123457",
                  "FirstDirection Pi / 2: a symbol along the columns");
      if Tool.Results.Count = 1 then
         Check_Angle_Near (Tool.Results.Item (0).Angle, Pi / 2.0, 0.01,
                           "its angle");
      end if;
      Check_None (Run_On (Flat, (One with delta First_Direction => Pi / 2.0)),
                  "FirstDirection Pi / 2: a symbol along the rows");

      --  The angle is that of the symbol, whichever way the lines run.
      Tool := Run_On (Up, (One with delta First_Direction => -Pi / 2.0));
      Check_Only (Tool, EAN_13, "5901234123457",
                  "FirstDirection -Pi / 2: a symbol along the columns");
      if Tool.Results.Count = 1 then
         Check_Angle_Near (Tool.Results.Item (0).Angle, Pi / 2.0, 0.01,
                           "its angle is that of the symbol");
      end if;
      Tool := Run_On (Tilted, (One with delta First_Direction => 0.3 + Pi));
      Check_Only (Tool, EAN_13, "5901234123457",
                  "FirstDirection 0.3 + Pi: a symbol at 0.3 radians");
      if Tool.Results.Count = 1 then
         Check_Angle_Near (Tool.Results.Item (0).Angle, 0.3, 0.01,
                           "its angle is that of the symbol");
      end if;

      --  Two directions: rows and columns.
      Check_Only (Run_On (Flat, (Defaults with delta Num_Directions => 2)),
                  EAN_13, "5901234123457",
                  "two directions: a symbol along the rows");
      Check_Only (Run_On (Up, (Defaults with delta Num_Directions => 2)),
                  EAN_13, "5901234123457",
                  "two directions: a symbol along the columns");

      --  Any finite direction is taken modulo a full turn.
      Check_Only (Run_On (Flat, (One with delta
                                   First_Direction => 200.0 * Pi)),
                  EAN_13, "5901234123457", "FirstDirection of 100 turns");
      Check_Only (Run_On (Tilted, (Defaults with delta
                                     First_Direction => -1.0E6)),
                  EAN_13, "5901234123457", "FirstDirection -1.0E6");

      --  The most directions: one a degree. The readings along
      --  neighbouring directions are one result.
      declare
         Small : constant Ks_Image_8_Grey :=
           Symbol_Image (BC.EAN_8 ("96385074"), 2.0, 0.2, 80.0, 240, 200);
      begin
         Check_Only (Run_On (Small, (Defaults with delta
                                       Num_Directions => 180)),
                     EAN_8, "96385074", "180 directions");
      end;
   end Test_Directions;

   ---------------------------------------------------------------------
   --  Scan lines
   ---------------------------------------------------------------------

   procedure Test_Scan_Lines is
      Widths : constant BC.Width_List := BC.EAN_13 ("5901234123457");
      Image  : constant Ks_Image_8_Grey := Symbol_Image (Widths);
      One    : constant Ks_Code_Reader :=
        (Defaults with delta Num_Directions => 1);

      procedure Check_Lines
        (Spacing     : Real;
         First, Last : Int32);
      --  With that LineSpacing the bars, 80 pixels tall, are crossed by
      --  First .. Last scan lines.

      procedure Check_Lines
        (Spacing     : Real;
         First, Last : Int32)
      is
         Tool : constant Ks_Code_Reader_Tool :=
           Run_On (Image, (One with delta Line_Spacing => Spacing));
      begin
         Check (Is_Only (Tool, EAN_13, "5901234123457")
                and then Tool.Results.Item (0).Num_Scan_Lines
                           in First .. Last,
                "LineSpacing" & Img (Spacing) & Found (Tool));
      end Check_Lines;

      Lines : Int32 := 0;
      Tool  : Ks_Code_Reader_Tool;
      R     : Ks_Code_Reader_Result;
   begin
      Section ("CodeReader: scan lines");
      Check_Lines (4.0, 19, 21);
      Check_Lines (8.0, 9, 11);
      Check_Lines (1.0, 79, 81);
      Check_Lines (2.5, 31, 33);
      Check_Lines (20.0, 3, 5);

      --  MinScanLines: a symbol is reported when that many lines read it.
      Tool := Run_On (Image, One);
      if Tool.Results.Count = 1 then
         Lines := Tool.Results.Item (0).Num_Scan_Lines;
      end if;
      Check_Only (Run_On (Image, (One with delta Min_Scan_Lines => Lines)),
                  EAN_13, "5901234123457",
                  "MinScanLines equal to the lines that read the symbol");
      Check_None (Run_On (Image, (One with delta
                                    Min_Scan_Lines => Lines + 1)),
                  "MinScanLines one more than that");

      --  One scan line: with lines 30 pixels apart one of them lies at
      --  y = 224.5 (the lines are placed evenly about the middle of the
      --  image), across bars 24 pixels tall.
      declare
         Low : Ks_Image_8_Grey := Scene;
      begin
         BC.Draw (Low, Widths, 320.0, 225.0, 3.0, 24.0);
         Check_None (Run_On (Low, (One with delta Line_Spacing => 30.0)),
                     "one line reads the symbol, MinScanLines 2");
         Check_None (Run_On (Low, (One with delta Line_Spacing => 30.0,
                                   Min_Scan_Lines => 3)),
                     "one line reads the symbol, MinScanLines 3");
         Tool := Run_On (Low, (One with delta Line_Spacing => 30.0,
                               Min_Scan_Lines => 1));
         Check_Only (Tool, EAN_13, "5901234123457",
                     "one line reads the symbol, MinScanLines 1");
         if Tool.Results.Count = 1 then
            R := Tool.Results.Item (0);
            Check (R.Num_Scan_Lines = 1, "NumScanLines 1");
            Check (R.Corner_0_X = R.Corner_3_X
                   and then R.Corner_0_Y = R.Corner_3_Y
                   and then R.Corner_1_X = R.Corner_2_X
                   and then R.Corner_1_Y = R.Corner_2_Y,
                   "the corners are the two ends on that line");
            Check_Near (R.Center_X, 320.0, 1.0, "CenterX on that line");
            Check_Near (R.Center_Y, 224.5, 1.0E-9, "CenterY on that line");
            Check_Near (R.Corner_0_Y, 224.5, 1.0E-9, "the corners too");
            Check_Angle_Near (R.Angle, 0.0, 1.0E-9,
                              "the angle is that of the line");
         end if;
      end;

      --  A scratch along the symbol. The lines, 4 pixels apart, lie at
      --  y = 1.5, 5.5, ..., 20 of them across the bars. A white band
      --  over the rows 236 .. 243 hides the symbol from two of them,
      --  which the candidate bridges; a band over the rows 236 .. 247
      --  hides it from three, which leaves a candidate on either side.
      declare
         Scratched : Ks_Image_8_Grey := Symbol_Image (Widths);
      begin
         TI.Draw_Rectangle (Scratched, 320.0, 239.5, 700.0, 8.0);
         Tool := Run_On (Scratched, One);
         Check (Is_Only (Tool, EAN_13, "5901234123457")
                and then Tool.Results.Item (0).Num_Scan_Lines = 18,
                "two unread lines in the middle: one result of 18 lines"
                & Found (Tool));
         TI.Draw_Rectangle (Scratched, 320.0, 241.5, 700.0, 12.0);
         Tool := Run_On (Scratched, One);
         Check (Tool.Run_Status.Result = Accept_Result
                and then Tool.Results.Count = 2
                and then Text (Tool.Results.Item (0)) = "5901234123457"
                and then Text (Tool.Results.Item (1)) = "5901234123457"
                and then Tool.Results.Item (0).Num_Scan_Lines = 9
                and then Tool.Results.Item (1).Num_Scan_Lines = 8,
                "three unread lines in the middle: a result for each part,"
                & " of 9 and 8 lines" & Found (Tool));
      end;
   end Test_Scan_Lines;


   ---------------------------------------------------------------------
   --  Coordinate spaces
   ---------------------------------------------------------------------

   procedure Test_Fixture is
      Alpha     : constant Real := 0.4;
      Scale     : constant Real := 2.0;
      Fix       : constant Ks_Transform_2D_Linear :=
        Create (Scale * EF.Cos (Alpha), -Scale * EF.Sin (Alpha),
                Scale * EF.Sin (Alpha), Scale * EF.Cos (Alpha), 30.0, 20.0);
      --  Fixture (u, v) to root (= pixel) coordinates: 2 pixels per unit.
      Tree      : Ks_Coordinate_Space_Tree;
      Widths    : constant BC.Width_List := BC.EAN_13 ("5901234123457");
      Phi       : constant Real := 0.7;
      U0        : constant Real := 176.0;
      V0        : constant Real := 45.0;
      Length    : constant Real := BC.Total (Widths) * 3.0;
      --  The symbol in the fixture: centre (U0, V0), rotation Phi,
      --  Length / Scale units long. In pixels it lies near the middle of
      --  the image.
      PX, PY    : Real;
      Tool      : Ks_Code_Reader_Tool;
      Rectangle : Ks_Rectangle;
      E         : Pose_Errors;
   begin
      Section ("CodeReader: fixture space");
      Tool.Input_Image := Scene;
      Tree.Add_Space ("@", "Fixture", Fix);
      Tool.Input_Image.Set_Coordinate_Space_Tree (Tree);
      Tool.Input_Image.Set_Selected_Space_Name ("@\Fixture");
      Fix.Map_Point (U0, V0, PX, PY);
      BC.Draw (Tool.Input_Image, Widths, PX, PY, 3.0, 80.0, Phi + Alpha);

      Tool.Run;
      Check_Only (Tool, EAN_13, "5901234123457",
                  "a symbol in an image with a fixture");
      if Tool.Results.Count = 1 then
         E := Pose_Of (Tool.Results.Item (0), U0, V0, Phi, Length / Scale);
         Check (E.Centre <= Centre_Tolerance / Scale
                and then E.Angle <= Angle_Tolerance
                and then E.Ends <= Ends_Tolerance / Scale,
                "its pose in fixture units" & Img (E));
      end if;

      --  A region in the fixture.
      Rectangle.Set_XY_Width_Height (90.0, -30.0, 172.0, 150.0);
      Tool.Region := RH.To_Holder (Rectangle);
      Tool.Run;
      Check_Only (Tool, EAN_13, "5901234123457",
                  "a region in the fixture around the symbol");
      Rectangle.Set_XY_Width_Height (0.0, 0.0, 60.0, 60.0);
      Tool.Region := RH.To_Holder (Rectangle);
      Tool.Run;
      Check_None (Tool, "a region in the fixture beside the symbol");

      --  A region in pixel space, results in the fixture.
      Rectangle.Set_Selected_Space_Name ("#");
      Rectangle.Set_XY_Width_Height (0.0, 0.0, Real (W), Real (H));
      Tool.Region := RH.To_Holder (Rectangle);
      Tool.Run;
      Check_Only (Tool, EAN_13, "5901234123457",
                  "a region in pixel space around the symbol");
      if Tool.Results.Count = 1 then
         E := Pose_Of (Tool.Results.Item (0), U0, V0, Phi, Length / Scale);
         Check (E.Centre <= Centre_Tolerance / Scale
                and then E.Angle <= Angle_Tolerance
                and then E.Ends <= Ends_Tolerance / Scale,
                "the pose is still in fixture units" & Img (E));
      end if;
      Rectangle.Set_XY_Width_Height (0.0, 0.0, 100.0, 100.0);
      Tool.Region := RH.To_Holder (Rectangle);
      Tool.Run;
      Check_None (Tool, "a region in pixel space beside the symbol");

      --  The root space selected: the pose in pixels.
      Tool.Region.Clear;
      Tool.Input_Image.Set_Selected_Space_Name ("@");
      Tool.Run;
      Check_Only (Tool, EAN_13, "5901234123457",
                  "the root space selected");
      if Tool.Results.Count = 1 then
         E := Pose_Of (Tool.Results.Item (0), PX, PY, Phi + Alpha, Length);
         Check (Pose_OK (E), "the pose in pixels" & Img (E));
      end if;
   end Test_Fixture;

   ---------------------------------------------------------------------
   --  Run parameters
   ---------------------------------------------------------------------

   procedure Test_Parameters is
      Image : constant Ks_Image_8_Grey :=
        Symbol_Image (BC.EAN_8 ("96385074"), 2.0, 0.0, 60.0, 240, 160);
      NaN   : constant Real := Zero / Zero;
      Inf   : constant Real := 1.0 / Zero;

      procedure Check_Bad
        (Params      : Ks_Code_Reader;
         Message     : String;
         Description : String);
      --  A run with Params fails with Ks_Bad_Parameter_Exception and that
      --  message, and has no results.

      procedure Check_Bad
        (Params      : Ks_Code_Reader;
         Message     : String;
         Description : String)
      is
         Tool : constant Ks_Code_Reader_Tool := Run_On (Image, Params);
      begin
         Check (Status_Is (Tool, "KS_BAD_PARAMETER_EXCEPTION", Message)
                and then Tool.Results.Count = 0,
                Description & Found (Tool));
      end Check_Bad;

      procedure Check_Good
        (Params      : Ks_Code_Reader;
         Description : String);
      --  A run with Params reads the symbol.

      procedure Check_Good
        (Params      : Ks_Code_Reader;
         Description : String) is
      begin
         Check_Only (Run_On (Image, Params), EAN_8, "96385074",
                     Description);
      end Check_Good;

      Symbologies : constant String :=
        "RunParams.Symbologies must be a sum of"
        & " KS_CODE_READER_SYMBOLOGY_*, in 1 .. 127";
      Directions  : constant String :=
        "RunParams.NumDirections must be in 1 .. 180";
      First       : constant String :=
        "RunParams.FirstDirection must be finite and within +/-1.0E150";
      Spacing     : constant String :=
        "RunParams.LineSpacing must be in 1.0 .. 1000.0";
      Contrast    : constant String :=
        "RunParams.ContrastThreshold must be in 1 .. 255";
      Lines       : constant String :=
        "RunParams.MinScanLines must be in 1 .. 1000";
      Check_39    : constant String :=
        "RunParams.Code39CheckDigit must be 0 or 1";
      Check_ITF   : constant String :=
        "RunParams.ITFCheckDigit must be 0 or 1";
      Digits_ITF  : constant String :=
        "RunParams.ITFMinDigits must be in 2 .. 254";

      Tool  : Ks_Code_Reader_Tool;
      Empty : Ks_Image_8_Grey;
   begin
      Section ("CodeReader: run parameters");
      Check_Good (Defaults, "the defaults");

      Check_Bad ((Defaults with delta Symbologies => 0), Symbologies,
                 "Symbologies 0");
      Check_Bad ((Defaults with delta Symbologies => 128), Symbologies,
                 "Symbologies 128");
      Check_Bad ((Defaults with delta Symbologies => -1), Symbologies,
                 "Symbologies -1");
      Check_Good ((Defaults with delta Symbologies => Code (EAN_8)),
                  "Symbologies: EAN-8 alone");

      Check_Bad ((Defaults with delta Num_Directions => 0), Directions,
                 "NumDirections 0");
      Check_Bad ((Defaults with delta Num_Directions => 181), Directions,
                 "NumDirections 181");
      Check_Bad ((Defaults with delta Num_Directions => -1), Directions,
                 "NumDirections -1");
      Check_Good ((Defaults with delta Num_Directions => 1),
                  "NumDirections 1");
      Check_Good ((Defaults with delta Num_Directions => 180),
                  "NumDirections 180");

      Check_Bad ((Defaults with delta First_Direction => NaN), First,
                 "FirstDirection NaN");
      Check_Bad ((Defaults with delta First_Direction => Inf), First,
                 "FirstDirection +Inf");
      Check_Bad ((Defaults with delta First_Direction => -Inf), First,
                 "FirstDirection -Inf");
      Check_Bad ((Defaults with delta First_Direction => 1.0E151), First,
                 "FirstDirection 1.0E151");
      Check_Good ((Defaults with delta First_Direction => 1.0E150),
                  "FirstDirection 1.0E150");
      Check_Good ((Defaults with delta First_Direction => -1.0E150),
                  "FirstDirection -1.0E150");

      Check_Bad ((Defaults with delta Line_Spacing => 0.5), Spacing,
                 "LineSpacing 0.5");
      Check_Bad ((Defaults with delta Line_Spacing => 1000.5), Spacing,
                 "LineSpacing 1000.5");
      Check_Bad ((Defaults with delta Line_Spacing => NaN), Spacing,
                 "LineSpacing NaN");
      Check_Bad ((Defaults with delta Line_Spacing => 0.0), Spacing,
                 "LineSpacing 0");
      Check_Bad ((Defaults with delta Line_Spacing => -4.0), Spacing,
                 "LineSpacing -4");
      Check_Good ((Defaults with delta Line_Spacing => 1.0),
                  "LineSpacing 1.0");
      --  Lines that far apart: one line of each direction, through the
      --  middle of the image.
      Check_Good ((Defaults with delta Line_Spacing => 1000.0,
                   Min_Scan_Lines => 1),
                  "LineSpacing 1000.0");

      Check_Bad ((Defaults with delta Contrast_Threshold => 0), Contrast,
                 "ContrastThreshold 0");
      Check_Bad ((Defaults with delta Contrast_Threshold => 256), Contrast,
                 "ContrastThreshold 256");
      Check_Good ((Defaults with delta Contrast_Threshold => 1),
                  "ContrastThreshold 1");
      --  Black on white is a rise of 255 levels.
      Check_Good ((Defaults with delta Contrast_Threshold => 255),
                  "ContrastThreshold 255");

      Check_Bad ((Defaults with delta Min_Scan_Lines => 0), Lines,
                 "MinScanLines 0");
      Check_Bad ((Defaults with delta Min_Scan_Lines => 1001), Lines,
                 "MinScanLines 1001");
      Check_Good ((Defaults with delta Min_Scan_Lines => 1),
                  "MinScanLines 1");
      Check_None (Run_On (Image, (Defaults with delta
                                    Min_Scan_Lines => 1000)),
                  "MinScanLines 1000: more lines than cross the symbol");

      Check_Bad ((Defaults with delta Code_39_Check_Digit => 2), Check_39,
                 "Code39CheckDigit 2");
      Check_Bad ((Defaults with delta Code_39_Check_Digit => -1), Check_39,
                 "Code39CheckDigit -1");
      Check_Good ((Defaults with delta Code_39_Check_Digit => 1),
                  "Code39CheckDigit 1");
      Check_Bad ((Defaults with delta ITF_Check_Digit => 2), Check_ITF,
                 "ITFCheckDigit 2");
      Check_Bad ((Defaults with delta ITF_Check_Digit => -1), Check_ITF,
                 "ITFCheckDigit -1");
      Check_Good ((Defaults with delta ITF_Check_Digit => 1),
                  "ITFCheckDigit 1");
      Check_Bad ((Defaults with delta ITF_Min_Digits => 1), Digits_ITF,
                 "ITFMinDigits 1");
      Check_Bad ((Defaults with delta ITF_Min_Digits => 0), Digits_ITF,
                 "ITFMinDigits 0");
      Check_Bad ((Defaults with delta ITF_Min_Digits => 255), Digits_ITF,
                 "ITFMinDigits 255");
      Check_Good ((Defaults with delta ITF_Min_Digits => 2),
                  "ITFMinDigits 2");
      Check_Good ((Defaults with delta ITF_Min_Digits => 254),
                  "ITFMinDigits 254");

      --  The first bad parameter is the one reported.
      Check_Bad ((Defaults with delta Symbologies => 0, Line_Spacing => NaN,
                  ITF_Min_Digits => 0),
                 Symbologies, "several bad parameters: the first is named");

      --  A failed run leaves no results.
      Tool := Run_On (Image);
      Check (Tool.Results.Count = 1, "a run with a result");
      Tool.Run_Params.Num_Directions := 0;
      Tool.Run;
      Check (Tool.Run_Status.Result = Error
             and then Tool.Results.Count = 0,
             "a failed run clears the results of the run before");

      --  An image without pixels; the image is looked at before the
      --  parameters.
      Tool.Input_Image := Empty;
      Tool.Run;
      Check (Status_Is (Tool, "KS_IMAGE_NO_PIXELS_EXCEPTION",
                        "InputImage has no pixels"),
             "an unallocated image" & Found (Tool));
   end Test_Parameters;

   ---------------------------------------------------------------------
   --  The kernel
   ---------------------------------------------------------------------

   procedure Test_Kernel is
      Picture : constant Ks_Image_8_Grey :=
        Symbol_Image (BC.EAN_8 ("96385074"), 2.0, 0.0, 60.0, 240, 160);
      --  The symbol covers columns 53 .. 186 of rows 50 .. 109.
      Handle  : constant access constant KI.Ks_Image_8_Grey_Data :=
        AMV.Images.Kernel_Images.Kernel_Handle (Picture);
      Id      : constant KT.Ks_Transform_2D_Linear := (others => <>);
      NaN     : constant Real := Zero / Zero;
      Params  : constant KC.Ks_Code_Reader_Run_Params := (others => <>);
      One     : constant KC.Ks_Code_Reader_Run_Params :=
        (Params with delta Num_Directions => 1);
      Region  : KR.Ks_Pixel_Region;
      Part    : KR.Ks_Pixel_Region;
      Results : KC.Ks_Code_Reader_Results;
      Item    : KC.Ks_Code_Reader_Result;
      Moved   : KC.Ks_Code_Reader_Result;
      Count   : K.Int32;
      Status  : K.Ks_Status;
      S       : K.Ks_Status;
      Long    : KI.Ks_Image_8_Grey;

      function Message return String is
        (String (Status.Message) (1 .. Natural (Status.Length)));

      function Bad (Text : String) return Boolean is
        (Status.Failure = K.Failure_Bad_Parameter and then Results = null
         and then Message = Text);

      procedure Run_With
        (Transform : KT.Ks_Transform_2D_Linear;
         Result    : out KC.Ks_Code_Reader_Result);
      --  The only result of a run on the whole picture with that
      --  transform (No_Result when there is not exactly one).

      procedure Run_With
        (Transform : KT.Ks_Transform_2D_Linear;
         Result    : out KC.Ks_Code_Reader_Result) is
      begin
         Result := KC.No_Result;
         KC.Execute (Handle, Region, Params, Transform, Results, Status);
         KC.Results_Count (Results, Count, S);
         if Status.Failure = K.Failure_None and then Count = 1 then
            KC.Results_Item (Results, 0, Result, S);
         end if;
         KC.Results_Destroy (Results);
      end Run_With;
   begin
      Section ("CodeReader: kernel");
      Check (KC.Ks_Code_Reader_Result'Object_Size = 360 * 8
             and then KC.Ks_Code_Reader_Run_Params'Object_Size = 48 * 8,
             "the records have the sizes of the C header");

      --  Null handles.
      KC.Execute (null, null, Params, Id, Results, Status);
      Check (Status.Failure = K.Failure_Image_No_Pixels
             and then Results = null
             and then Message = "InputImage has no pixels",
             "a null image");
      KC.Execute (Handle, null, Params, Id, Results, Status);
      Check (Status.Failure = K.Failure_None and then Results /= null,
             "a null region is the empty region");
      KC.Results_Count (Results, Count, Status);
      Check (Status.Failure = K.Failure_None and then Count = 0,
             "which gives no results");
      KC.Results_Item (Results, 0, Item, Status);
      Check (Status.Failure = K.Failure_Index_Out_Of_Range
             and then Message = "Item: index outside the results",
             "Item (0) of no results");
      KC.Results_Destroy (Results);
      Check (Results = null, "Destroy sets the handle to null");
      KC.Results_Destroy (Results);
      Check (Results = null, "Destroy of null does nothing");
      KC.Results_Count (null, Count, Status);
      Check (Status.Failure = K.Failure_None and then Count = 0,
             "the count of null is 0");
      KC.Results_Item (null, 0, Item, Status);
      Check (Status.Failure = K.Failure_Index_Out_Of_Range,
             "Item (0) of null");

      --  The whole image.
      KR.Whole_Image (240, 160, Region, S);
      KC.Execute (Handle, Region, Params, Id, Results, Status);
      KC.Results_Count (Results, Count, S);
      Check (Status.Failure = K.Failure_None and then Count = 1,
             "the whole image: one symbol");
      KC.Results_Item (Results, 0, Item, Status);
      Check (Status.Failure = K.Failure_None
             and then Item.Symbology = KC.Symbology_EAN_8
             and then Item.Length = 8
             and then String (Item.Text (1 .. 8)) = "96385074",
             "its symbology and text");
      Check ((for all I in 9 .. Item.Text'Last =>
                Item.Text (I) = ASCII.NUL),
             "NUL after the text");
      Check_Near (Item.Center_X, 119.5, 1.0, "CenterX");
      Check_Near (Item.Center_Y, 79.5, 2.5, "CenterY");
      Check_Angle_Near (Item.Angle, 0.0, 0.01, "Angle");
      KC.Results_Item (Results, 1, Moved, Status);
      Check (Status.Failure = K.Failure_Index_Out_Of_Range
             and then Message = "Item: index outside the results",
             "Item (1) of one result");
      KC.Results_Item (Results, -1, Moved, Status);
      Check (Status.Failure = K.Failure_Index_Out_Of_Range, "Item (-1)");
      KC.Results_Destroy (Results);

      --  Selected_From_Pixel.
      KC.Execute (Handle, Region, Params, (Id with delta A => NaN),
                  Results, Status);
      Check (Bad ("Selected_From_Pixel must be finite and within"
                  & " +/-1.0E150"),
             "a NaN in the transform");
      KC.Execute (Handle, Region, Params,
                  (Id with delta Translation_Y => -1.0E151),
                  Results, Status);
      Check (Bad ("Selected_From_Pixel must be finite and within"
                  & " +/-1.0E150"),
             "a translation beyond the bound");
      KC.Execute (Handle, Region, (Params with delta Num_Directions => 0),
                  (Id with delta A => NaN), Results, Status);
      Check (Bad ("RunParams.NumDirections must be in 1 .. 180"),
             "the run parameters are checked before the transform");

      Run_With ((A => 0.5, B => 0.0, C => 0.0, D => 0.5,
                 Translation_X => 10.0, Translation_Y => -20.0), Moved);
      Check (Moved.Length = 8
             and then abs (Moved.Center_X - (0.5 * Item.Center_X + 10.0))
                        < 1.0E-9
             and then abs (Moved.Center_Y - (0.5 * Item.Center_Y - 20.0))
                        < 1.0E-9
             and then abs (Moved.Corner_2_X
                           - (0.5 * Item.Corner_2_X + 10.0)) < 1.0E-9
             and then abs (Moved.Corner_2_Y
                           - (0.5 * Item.Corner_2_Y - 20.0)) < 1.0E-9
             and then abs (Moved.Angle - Item.Angle) < 1.0E-9,
             "a scaling and a translation move the centre and the corners");
      Run_With ((A => 0.0, B => -1.0, C => 1.0, D => 0.0,
                 Translation_X => 0.0, Translation_Y => 0.0), Moved);
      Check (Moved.Length = 8
             and then abs (Moved.Center_X + Item.Center_Y) < 1.0E-9
             and then abs (Moved.Center_Y - Item.Center_X) < 1.0E-9
             and then abs (Moved.Corner_0_X + Item.Corner_0_Y) < 1.0E-9
             and then abs (Moved.Corner_0_Y - Item.Corner_0_X) < 1.0E-9,
             "a quarter turn moves the centre and the corners");
      Check_Angle_Near (Moved.Angle, Item.Angle + Pi / 2.0, 1.0E-9,
                        "and turns the angle");
      Run_With ((A => 0.0, B => 0.0, C => 0.0, D => 0.0,
                 Translation_X => 5.0, Translation_Y => 7.0), Moved);
      Check (Moved.Length = 8
             and then Moved.Center_X = 5.0 and then Moved.Center_Y = 7.0
             and then Moved.Corner_0_X = 5.0 and then Moved.Corner_0_Y = 7.0
             and then Moved.Corner_2_X = 5.0 and then Moved.Corner_2_Y = 7.0
             and then Moved.Angle = 0.0,
             "a transform that maps everything to one point: angle 0");

      --  Regions.
      KR.Rasterize_Rectangle
        (240, 160, Id, (X => 20.0, Y => 30.0, Width => 200.0,
                        Height => 100.0), Part, S);
      KC.Execute (Handle, Part, Params, Id, Results, Status);
      KC.Results_Count (Results, Count, S);
      Check (Status.Failure = K.Failure_None and then Count = 1,
             "a rectangle around the symbol");
      KC.Results_Destroy (Results);
      KR.Destroy (Part, S);
      KR.Rasterize_Rectangle
        (240, 160, Id, (X => 0.0, Y => 0.0, Width => 120.0,
                        Height => 160.0), Part, S);
      KC.Execute (Handle, Part, Params, Id, Results, Status);
      KC.Results_Count (Results, Count, S);
      Check (Status.Failure = K.Failure_None and then Count = 0,
             "a rectangle over half of the symbol");
      KC.Results_Destroy (Results);
      KR.Destroy (Part, S);
      KR.Destroy (Region, S);

      --  The longest scan line: the width plus the height of the area to
      --  scan is at most 1048576.
      KI.Create (1048574, 2, 255, Long, S);
      Check (S.Failure = K.Failure_None, "an image of 1048574 x 2 pixels");
      KR.Whole_Image (1048574, 2, Region, S);
      KC.Execute (Long, Region, One, Id, Results, Status);
      KC.Results_Count (Results, Count, S);
      Check (Status.Failure = K.Failure_None and then Count = 0,
             "width plus height 1048576 is scanned");
      KC.Results_Destroy (Results);
      KR.Destroy (Region, S);
      KI.Destroy (Long, S);

      KI.Create (1048575, 2, 255, Long, S);
      Check (S.Failure = K.Failure_None, "an image of 1048575 x 2 pixels");
      KR.Whole_Image (1048575, 2, Region, S);
      KC.Execute (Long, Region, One, Id, Results, Status);
      Check (Bad ("CodeReader: the width plus the height of the area to"
                  & " scan must not exceed 1048576"),
             "width plus height 1048577 is not");
      KR.Destroy (Region, S);
      KR.Rasterize_Rectangle
        (1048575, 2, Id, (X => 100.0, Y => 0.0, Width => 300.0,
                          Height => 2.0), Region, S);
      KC.Execute (Long, Region, One, Id, Results, Status);
      KC.Results_Count (Results, Count, S);
      Check (Status.Failure = K.Failure_None and then Count = 0,
             "a small region of that image is scanned");
      KC.Results_Destroy (Results);
      KR.Destroy (Region, S);
      KI.Destroy (Long, S);

      --  More candidates than a run can hold. Every row of the image is
      --  a line of 11 UPC-E symbols, and the rows go through five lines
      --  with different texts in turn, so that with one direction, a scan
      --  line on every row and MinScanLines 1 each of the 401 x 11
      --  readings is a candidate of its own.
      declare
         Wide   : constant := 1380;
         Pitch  : constant := 124;
         Strip  : Ks_Image_8_Grey := Scene (Wide, 45);
         Crowd  : Ks_Image_8_Grey := Scene (Wide, 401);
         Texts  : constant array (0 .. 4) of String (1 .. 7) :=
           ["0123456", "0654321", "0111111", "0246802", "0975319"];
         Dense  : constant Ks_Code_Reader :=
           (Defaults with delta Num_Directions => 1, Line_Spacing => 1.0,
            Min_Scan_Lines => 1);
         Tool   : Ks_Code_Reader_Tool;
      begin
         for T in Texts'Range loop
            for Column in 0 .. 10 loop
               BC.Draw (Strip,
                        BC.UPC_E (Texts (T)
                                  & BC.UPC_E_Check_Digit (Texts (T))),
                        Real (70 + Pitch * Column), Real (9 * T) + 4.5,
                        2.0, 9.0);
            end loop;
         end loop;
         for Y in 0 .. 400 loop
            for X in 0 .. Wide - 1 loop
               Crowd.Set_Pixel (X, Y, Strip.Get_Pixel (X, 9 * (Y mod 5) + 4));
            end loop;
         end loop;

         Tool := Run_On (Strip, (Dense with delta Min_Scan_Lines => 5));
         Check (Tool.Run_Status.Result = Accept_Result
                and then Tool.Results.Count = 55,
                "five lines of 11 symbols" & Found (Tool));
         Tool := Run_On (Crowd, Dense);
         Check (Status_Is (Tool, "KS_EXCEPTION",
                           "CodeReader: more than 4096 candidates")
                and then Tool.Results.Count = 0,
                "4411 readings that do not join" & Found (Tool));
         --  With MinScanLines 2 a reading that no later line can join is
         --  dropped as the scan goes on.
         Check_None (Run_On (Crowd, (Dense with delta Min_Scan_Lines => 2)),
                     "the same image with MinScanLines 2");
      end;
   end Test_Kernel;

   ---------------------------------------------------------------------
   --  Results
   ---------------------------------------------------------------------

   procedure Test_Results is
      Image  : constant Ks_Image_8_Grey :=
        Symbol_Image (BC.EAN_8 ("96385074"), 2.0, 0.0, 60.0, 240, 160);
      Tool   : Ks_Code_Reader_Tool := Run_On (Image);
      Copy   : Ks_Code_Reader_Tool;
      Shared : Ks_Code_Reader_Results;
      Odd    : Ks_Code_Reader_Result;

      procedure Item_Beyond;
      procedure Long_Text;
      procedure Negative_Length;
      procedure No_Symbology;

      procedure Item_Beyond is
         R : constant Ks_Code_Reader_Result :=
           Shared.Item (Shared.Count);
      begin
         Check (R.Length = 0, "not reached");
      end Item_Beyond;

      procedure Long_Text is
      begin
         Check (Text (Odd)'Length = 0, "not reached");
      end Long_Text;

      procedure Negative_Length is
      begin
         Check (Text (Odd)'Length = 0, "not reached");
      end Negative_Length;

      procedure No_Symbology is
      begin
         Check (Symbology (Odd) = EAN_13, "not reached");
      end No_Symbology;

      procedure Check_Item_Beyond is new Check_Raises_Exactly
        (Item_Beyond, Constraint_Error'Identity);
      procedure Check_Long_Text is new Check_Raises_Exactly
        (Long_Text, AMV.Ks_Bad_Parameter_Exception'Identity);
      procedure Check_Negative_Length is new Check_Raises_Exactly
        (Negative_Length, AMV.Ks_Bad_Parameter_Exception'Identity);
      procedure Check_No_Symbology is new Check_Raises_Exactly
        (No_Symbology, AMV.Ks_Bad_Parameter_Exception'Identity);
   begin
      Section ("CodeReader: results");
      Check_Only (Tool, EAN_8, "96385074", "a run with one result");
      Shared := Tool.Results;
      Copy := Tool;

      --  Copies share the results; the next run of one tool replaces its
      --  own.
      Tool.Run_Params.Symbologies := Code (Code_39);
      Tool.Run;
      Check_None (Tool, "the next run reads nothing");
      Check (Shared.Count = 1 and then Copy.Results.Count = 1
             and then Text (Shared.Item (0)) = "96385074"
             and then Text (Copy.Results.Item (0)) = "96385074",
             "copies of the results and of the tool keep the earlier run");
      Copy.Reset_Results;
      Check (Copy.Results.Count = 0 and then Shared.Count = 1,
             "ResetResults empties the results of that tool only");
      Check_Item_Beyond ("Item (Count) raises Constraint_Error");

      --  Records that no run makes.
      Check (Text (KC.No_Result) = "", "the text of No_Result is empty");
      Check (Symbology (KC.No_Result) = EAN_13,
             "the symbology of No_Result");
      Odd := Shared.Item (0);
      Odd.Length := 300;
      Check_Long_Text
        ("Text with Length 300 raises Ks_Bad_Parameter_Exception");
      Odd.Length := -1;
      Check_Negative_Length
        ("Text with Length -1 raises Ks_Bad_Parameter_Exception");
      Odd.Length := 3;
      Check (Text (Odd) = "963", "Text is the first Length characters");
      Odd.Symbology := 3;
      Check_No_Symbology
        ("Symbology of a code that is none raises"
         & " Ks_Bad_Parameter_Exception");
      for Value in Kind loop
         Odd.Symbology := Code (Value);
         Check (Symbology (Odd) = Value,
                "Symbology gives back " & Value'Image);
      end loop;
   end Test_Results;

   ---------------------------------------------------------------------
   --  Timing
   ---------------------------------------------------------------------

   procedure Test_Timing is
      Image : constant Ks_Image_8_Grey :=
        Symbol_Image (BC.EAN_13 ("5901234123457"), Rotation => 0.3);
      Runs  : constant := 10;

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
         Check_Only (Tool, EAN_13, "5901234123457", Name);
         Ada.Text_IO.Put_Line
           ("  a 640 x 480 image, " & Name & ":"
            & Duration'Image (Total / Runs * 1000.0) & " ms per run");
      end Time;
   begin
      Section ("CodeReader: timing");
      Time (Defaults, "12 directions");
      Time ((Defaults with delta Num_Directions => 1,
             First_Direction => 0.3), "1 direction");
   end Test_Timing;

   procedure Run_All is
   begin
      Test_Defaults;
      Test_Encoders;
      Test_Symbologies;
      Test_Rotations;
      Test_Several;
      Test_Region;
      Test_Symbology_Mask;
      Test_Check_Digits;
      Test_Code_128_Sets;
      Test_Code_39_And_ITF;
      Test_Quality;
      Test_Bar_Gain;
      Test_Small_Modules;
      Test_Aspect;
      Test_Directions;
      Test_Scan_Lines;
      Test_Fixture;
      Test_Parameters;
      Test_Kernel;
      Test_Results;
      Test_Timing;
   end Run_All;

   procedure Main is new AMV_Test_Support.Standalone (Run_All);
begin
   Main;
end Test_Code_Reader;
