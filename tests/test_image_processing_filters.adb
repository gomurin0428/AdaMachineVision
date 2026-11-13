--  Tests for the image processing filters: the histogram, pixel map, Sobel
--  edge and image sharpness tools (AMV.Image_Processing.Histogram,
--  Pixel_Map, Sobel_Edge, Sharpness) through Run, and their kernels
--  (AMV.Kernels.Histogram, Pixel_Map, Sobel_Edge, Image_Sharpness) called
--  directly for what the Ada API cannot reach: null handles, bad codes,
--  non-finite values and the accessors of a missing result.
--
--  Results are checked against direct computations on drawn images and
--  regions (statistics, tables, edges whose magnitudes and directions are
--  known), and the timings of 640 x 480 runs are printed.

pragma Validity_Checks ("F");
--  The kernel tests build a NaN on purpose.

with Ada.Exceptions;
with Ada.Numerics.Long_Elementary_Functions;
with Ada.Text_IO;
with Interfaces;

with AMV;                    use AMV;
with AMV.Image_Math;
with AMV.Image_Processing.Affine_Transform;
with AMV.Image_Processing.Histogram;
with AMV.Image_Processing.Pixel_Map;
with AMV.Image_Processing.Sharpness;
with AMV.Image_Processing.Sobel_Edge;
with AMV.Images;             use AMV.Images;
with AMV.Kernels;
with AMV.Kernels.Histogram;
with AMV.Kernels.Image_Sharpness;
with AMV.Kernels.Images;
with AMV.Kernels.Pixel_Map;
with AMV.Kernels.Regions;
with AMV.Kernels.Sobel_Edge;
with AMV.Misc;
with AMV.Regions;
with AMV.Shapes;             use AMV.Shapes;
with AMV.Shapes.Region_Holders;
with AMV.Tools;              use AMV.Tools;
with AMV.Transforms;
with AMV_Test_Images;
with AMV_Test_Support;       use AMV_Test_Support;

procedure Test_Image_Processing_Filters is

   package EF renames Ada.Numerics.Long_Elementary_Functions;
   package RH renames AMV.Shapes.Region_Holders;
   package IH renames AMV.Image_Processing.Histogram;
   package IP renames AMV.Image_Processing.Pixel_Map;
   package SH renames AMV.Image_Processing.Sharpness;
   package IE renames AMV.Image_Processing.Sobel_Edge;
   package K renames AMV.Kernels;
   package KH renames AMV.Kernels.Histogram;
   package KP renames AMV.Kernels.Pixel_Map;
   package KE renames AMV.Kernels.Sobel_Edge;
   package KS renames AMV.Kernels.Image_Sharpness;
   package KI renames AMV.Kernels.Images;
   package KR renames AMV.Kernels.Regions;

   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_32;
   use type K.Int32;
   use type KH.Ks_Histogram;
   use type KH.Ks_Histogram_Result;
   use type KI.Ks_Image_8_Grey;
   use type KP.Pixel_Map_Table;
   use type KE.Ks_Sobel_Edge;
   use type KS.Ks_Image_Sharpness;

   Zero : constant Real := Real'Value ("0.0");
   --  Read at run time, so that Zero / Zero is not folded.

   No_Pixels_Name : constant String := "AMV.KS_IMAGE_NO_PIXELS_EXCEPTION";
   Bad_Name       : constant String := "AMV.KS_BAD_PARAMETER_EXCEPTION";

   function Message_Of (Status : K.Ks_Status) return String is
     (String (Status.Message (1 .. Natural (Status.Length))));

   ---------------------------------------------------------------------
   --  Test images
   ---------------------------------------------------------------------

   function Random_Image
     (Width, Height : Positive;
      Seed          : Interfaces.Unsigned_32) return Ks_Image_8_Grey;
   --  Pixels from a linear congruential generator.

   function Random_Image
     (Width, Height : Positive;
      Seed          : Interfaces.Unsigned_32) return Ks_Image_8_Grey
   is
      State  : Interfaces.Unsigned_32 := Seed;
      Result : Ks_Image_8_Grey := Create (Width, Height);
   begin
      for Y in 0 .. Height - 1 loop
         for X in 0 .. Width - 1 loop
            State := State * 1_664_525 + 1_013_904_223;
            Result.Set_Pixel
              (X, Y, Grey_8 (Interfaces.Shift_Right (State, 24)));
         end loop;
      end loop;
      return Result;
   end Random_Image;

   function Step_Image
     (Width, Height : Positive;
      Left, Right   : Grey_8;
      First_Right   : Natural) return Ks_Image_8_Grey;
   --  Left in the columns before First_Right, Right from it on.

   function Step_Image
     (Width, Height : Positive;
      Left, Right   : Grey_8;
      First_Right   : Natural) return Ks_Image_8_Grey
   is
      Result : Ks_Image_8_Grey := Create (Width, Height, Left);
   begin
      for Y in 0 .. Height - 1 loop
         for X in First_Right .. Width - 1 loop
            Result.Set_Pixel (X, Y, Right);
         end loop;
      end loop;
      return Result;
   end Step_Image;

   function Ramp_Edge
     (Width, Height : Positive;
      Low, High     : Real;
      Start, Length : Real) return Ks_Image_8_Grey;
   --  A blurred vertical edge: Low left of Start, High right of Start +
   --  Length, linear in between (rounded).

   function Ramp_Edge
     (Width, Height : Positive;
      Low, High     : Real;
      Start, Length : Real) return Ks_Image_8_Grey
   is
      Result : Ks_Image_8_Grey := Create (Width, Height);
   begin
      for X in 0 .. Width - 1 loop
         declare
            T : constant Real :=
              Real'Max (0.0, Real'Min (1.0, (Real (X) - Start) / Length));
            V : constant Grey_8 :=
              Grey_8 (Integer (Low + (High - Low) * T));
         begin
            for Y in 0 .. Height - 1 loop
               Result.Set_Pixel (X, Y, V);
            end loop;
         end;
      end loop;
      return Result;
   end Ramp_Edge;

   function Rectangle
     (X, Y, Width, Height : Real;
      Space               : String := ".") return RH.Holder;
   --  A rectangle region.

   function Rectangle
     (X, Y, Width, Height : Real;
      Space               : String := ".") return RH.Holder
   is
      R : Ks_Rectangle;
   begin
      R.Set_XY_Width_Height (X, Y, Width, Height);
      R.Set_Selected_Space_Name (Space);
      return RH.To_Holder (R);
   end Rectangle;

   function Circle (X, Y, Radius : Real) return RH.Holder;

   function Circle (X, Y, Radius : Real) return RH.Holder is
      C : Ks_Circle;
   begin
      C.Set_Center_Radius (X, Y, Radius);
      return RH.To_Holder (C);
   end Circle;

   procedure Add_Fixture (Image : in out Ks_Image_8_Grey);
   --  Adds the space "@\Fixture" (rotated by 0.3 rad and translated) and
   --  selects it.

   procedure Add_Fixture (Image : in out Ks_Image_8_Grey) is
   begin
      Image.Coordinate_Space_Tree.Add_Space
        ("@", "Fixture", AMV.Transforms.Create_Rigid (0.3, 12.0, 7.0));
      Image.Set_Selected_Space_Name ("@\Fixture");
   end Add_Fixture;

   function Same_Spaces (A, B : Ks_Image_8_Grey) return Boolean is
     (A.Selected_Space_Name = B.Selected_Space_Name
      and then AMV.Transforms."="
                 (A.Pixel_From_Root_Transform, B.Pixel_From_Root_Transform)
      and then AMV.Transforms."="
                 (A.Get_Transform (".", "#"), B.Get_Transform (".", "#")));
   --  The output keeps the input's coordinate state.

   ---------------------------------------------------------------------
   --  Histogram
   ---------------------------------------------------------------------

   type Level_Counts is array (0 .. 255) of Natural;

   type Expected_Statistics is record
      Count                  : Natural := 0;
      Levels                 : Level_Counts := [others => 0];
      Mean, Variance         : Real := 0.0;
      Minimum, Maximum       : Natural := 0;
      Median, Mode           : Natural := 0;
   end record;

   No_Mask : Ks_Image_8_Grey;
   --  Unallocated: no input image mask.

   function Dont_Care
     (Mask               : Ks_Image_8_Grey;
      Offset_X, Offset_Y : Integer;
      X, Y               : Integer) return Boolean
   is
     (Mask.Allocated
      and then X - Offset_X in 0 .. Mask.Width - 1
      and then Y - Offset_Y in 0 .. Mask.Height - 1
      and then Mask.Get_Pixel (X - Offset_X, Y - Offset_Y) = 0);
   --  A mask pixel of value 0 lies over pixel (X, Y) (offsets small
   --  enough not to overflow).

   function Expected
     (Image              : Ks_Image_8_Grey;
      Region             : RH.Holder;
      Mask               : Ks_Image_8_Grey := No_Mask;
      Offset_X, Offset_Y : Integer := 0) return Expected_Statistics;
   --  The statistics computed directly over the pixels of the rasterised
   --  region that Mask does not mark "don't care".

   function Expected
     (Image              : Ks_Image_8_Grey;
      Region             : RH.Holder;
      Mask               : Ks_Image_8_Grey := No_Mask;
      Offset_X, Offset_Y : Integer := 0) return Expected_Statistics
   is
      R      : constant AMV.Regions.Pixel_Region :=
        AMV.Regions.Rasterize (Image, Region);
      E      : Expected_Statistics;
      Sum    : Real := 0.0;
      Square : Real := 0.0;
      Cumul  : Natural := 0;
   begin
      for Y in 0 .. Image.Height - 1 loop
         for X in 0 .. Image.Width - 1 loop
            if R.Contains (X, Y)
              and then not Dont_Care (Mask, Offset_X, Offset_Y, X, Y)
            then
               declare
                  V : constant Natural := Natural (Image.Get_Pixel (X, Y));
               begin
                  E.Levels (V) := E.Levels (V) + 1;
                  E.Count := E.Count + 1;
                  Sum := Sum + Real (V);
               end;
            end if;
         end loop;
      end loop;
      if E.Count = 0 then
         return E;
      end if;
      E.Mean := Sum / Real (E.Count);
      for V in Level_Counts'Range loop
         Square := Square + Real (E.Levels (V)) * (Real (V) - E.Mean)**2;
      end loop;
      E.Variance := Square / Real (E.Count);
      E.Minimum := 255;
      for V in Level_Counts'Range loop
         if E.Levels (V) > 0 then
            E.Minimum := Natural'Min (E.Minimum, V);
            E.Maximum := V;
            if E.Levels (V) > E.Levels (E.Mode) or else E.Levels (E.Mode) = 0
            then
               E.Mode := V;
            end if;
         end if;
      end loop;
      for V in Level_Counts'Range loop
         Cumul := Cumul + E.Levels (V);
         if 2 * Cumul >= E.Count then
            E.Median := V;
            exit;
         end if;
      end loop;
      return E;
   end Expected;

   procedure Check_Statistics
     (Tool : IH.Ks_Histogram_Tool;
      E    : Expected_Statistics;
      What : String);
   --  Compares the tool's result with E (and the Auto histogram with the
   --  counts per level).

   procedure Check_Statistics
     (Tool : IH.Ks_Histogram_Tool;
      E    : Expected_Statistics;
      What : String)
   is
      Bins : constant IH.Ks_Histogram_Array := Tool.Result.Get_Histogram;
      Same : Boolean := Bins'First = 0 and then Bins'Last = 255;
   begin
      Check (Tool.Run_Status.Result = Accept_Result,
             What & ": Accept_Result (" & Tool.Run_Status.Message & ")");
      Check (Tool.Result.Num_Samples = E.Count,
             What & ": Num_Samples" & Natural'Image (Tool.Result.Num_Samples)
             & " =" & Natural'Image (E.Count));
      Check_Near (Tool.Result.Mean, E.Mean, 1.0E-9, What & ": Mean");
      Check_Near (Tool.Result.Variance, E.Variance, 1.0E-7,
                  What & ": Variance");
      Check_Near (Tool.Result.Standard_Deviation, EF.Sqrt (E.Variance),
                  1.0E-9, What & ": Standard_Deviation");
      Check (Tool.Result.Minimum = E.Minimum, What & ": Minimum");
      Check (Tool.Result.Maximum = E.Maximum, What & ": Maximum");
      Check (Tool.Result.Median = E.Median, What & ": Median");
      Check (Tool.Result.Mode = E.Mode, What & ": Mode");
      if Same then
         for V in Bins'Range loop
            Same := Same and then Bins (V) = E.Levels (V);
         end loop;
      end if;
      Check (Same, What & ": every bin holds the count of its grey level");
   end Check_Statistics;

   function Within_Group_Variance (Levels : Level_Counts; T : Natural)
      return Real;
   --  The sum over the samples of the squared difference from the mean of
   --  their group, the groups being the levels < T and >= T (brute force).

   function Within_Group_Variance (Levels : Level_Counts; T : Natural)
      return Real
   is
      N0, N1, S0, S1 : Real := 0.0;
      Result         : Real := 0.0;
   begin
      for V in Levels'Range loop
         if V < T then
            N0 := N0 + Real (Levels (V));
            S0 := S0 + Real (Levels (V)) * Real (V);
         else
            N1 := N1 + Real (Levels (V));
            S1 := S1 + Real (Levels (V)) * Real (V);
         end if;
      end loop;
      for V in Levels'Range loop
         declare
            M : constant Real :=
              (if V < T then (if N0 > 0.0 then S0 / N0 else 0.0)
               else (if N1 > 0.0 then S1 / N1 else 0.0));
         begin
            Result := Result + Real (Levels (V)) * (Real (V) - M) ** 2;
         end;
      end loop;
      return Result;
   end Within_Group_Variance;

   function Brute_WGV_Threshold (E : Expected_Statistics) return Natural;
   --  The T in 1 .. 255 with two non-empty groups whose within-group
   --  variance is smallest (the smallest T within a relative 1e-12 of the
   --  minimum); E.Minimum when no T splits the samples, 0 without any.

   function Brute_WGV_Threshold (E : Expected_Statistics) return Natural is
      Best   : Real := Real'Last;
      Best_T : Natural := 0;
      Below  : Natural := 0;
   begin
      for T in 1 .. 255 loop
         Below := Below + E.Levels (T - 1);
         if Below > 0 and then Below < E.Count then
            declare
               W : constant Real := Within_Group_Variance (E.Levels, T);
            begin
               if Best_T = 0 or else W < Best * (1.0 - 1.0E-12) then
                  Best := W;
                  Best_T := T;
               end if;
            end;
         end if;
      end loop;
      return (if Best_T = 0 then E.Minimum else Best_T);
   end Brute_WGV_Threshold;

   procedure Test_Histogram is
      Image : Ks_Image_8_Grey := AMV_Test_Images.Blank (64, 48, 10);
      Tool  : IH.Ks_Histogram_Tool;
   begin
      Section ("Histogram: whole image, default parameters");
      AMV_Test_Images.Draw_Rectangle (Image, 30.0, 20.0, 20.0, 12.0, 0.4, 200);
      AMV_Test_Images.Draw_Circle (Image, 45.0, 30.0, 8.0, 120);
      Tool.Input_Image := Image;
      Check (Tool.Run_Params = KH.Auto_Params,
             "the defaults are Auto with 256 bins");
      Tool.Run;
      Check_Statistics (Tool, Expected (Image, RH.Empty_Holder),
                        "whole image");
      Check (Tool.Result.Num_Samples = 64 * 48, "every pixel is a sample");

      Section ("Histogram: a circle region");
      Tool.Region := Circle (20.0, 20.0, 12.5);
      Tool.Run;
      Check_Statistics (Tool, Expected (Image, Tool.Region), "circle");
      Check (Tool.Result.Num_Samples
               = AMV.Regions.Rasterize (Image, Tool.Region).Pixel_Count,
             "Num_Samples is the pixel count of the region");

      Section ("Histogram: noise");
      Tool.Input_Image := Random_Image (50, 40, 7);
      Tool.Region := Rectangle (5.2, 3.7, 30.0, 25.0);
      Tool.Run;
      Check_Statistics
        (Tool, Expected (Tool.Input_Image, Tool.Region), "noise");

      Section ("Histogram: inverse cumulative grey level");
      declare
         E : constant Expected_Statistics :=
           Expected (Tool.Input_Image, Tool.Region);
         Cumul : Natural := 0;
         Level_90 : Natural := 0;
      begin
         for V in Level_Counts'Range loop
            Cumul := Cumul + E.Levels (V);
            if 100 * Cumul >= 90 * E.Count then
               Level_90 := V;
               exit;
            end if;
         end loop;
         Check (Tool.Result.Get_Inverse_Cumulative_Grey_Level (0)
                  = E.Minimum, "0 percent is the minimum");
         Check (Tool.Result.Get_Inverse_Cumulative_Grey_Level (100)
                  = E.Maximum, "100 percent is the maximum");
         Check (Tool.Result.Get_Inverse_Cumulative_Grey_Level (50)
                  = Tool.Result.Median, "50 percent is the median");
         Check (Tool.Result.Get_Inverse_Cumulative_Grey_Level (90)
                  = Level_90, "90 percent");
      end;
      declare
         procedure Bad_Percent is
            L : constant Natural :=
              Tool.Result.Get_Inverse_Cumulative_Grey_Level (101);
         begin
            Fail ("percent 101 was accepted:" & Natural'Image (L));
         end Bad_Percent;
         procedure Check_Bad_Percent is new Check_Raises_Exactly
           (Bad_Percent, Ks_Bad_Parameter_Exception'Identity);
      begin
         Check_Bad_Percent ("percent 101 raises Ks_Bad_Parameter_Exception");
      end;

      Section ("Histogram: minimum within-group variance threshold");
      declare
         E : constant Expected_Statistics :=
           Expected (Tool.Input_Image, Tool.Region);
         T : constant Natural := Tool.Result.Get_Minimum_WGV_Threshold;
      begin
         Check (T = Brute_WGV_Threshold (E),
                "noise: the threshold of the smallest within-group"
                & " variance (" & T'Image & " against"
                & Brute_WGV_Threshold (E)'Image & ")");
      end;
      declare
         Two   : Ks_Image_8_Grey := AMV_Test_Images.Blank (20, 10, 50);
         Probe : IH.Ks_Histogram_Tool;
      begin
         for Y in 0 .. 9 loop
            for X in 12 .. 19 loop
               Two.Set_Pixel (X, Y, 200);
            end loop;
         end loop;
         Probe.Input_Image := Two;
         Probe.Run;
         Check (Probe.Result.Get_Minimum_WGV_Threshold = 51,
                "two grey levels 50 and 200: every T in 51 .. 200 splits"
                & " them, the smallest wins ("
                & Probe.Result.Get_Minimum_WGV_Threshold'Image & ")");
         Probe.Input_Image := AMV_Test_Images.Blank (8, 8, 77);
         Probe.Run;
         Check (Probe.Result.Get_Minimum_WGV_Threshold = 77,
                "one grey level: the minimum");
         Probe.Input_Image := Image;
         Probe.Region := Circle (20.0, 20.0, 12.5);
         Probe.Run;
         Check (Probe.Result.Get_Minimum_WGV_Threshold
                  = Brute_WGV_Threshold (Expected (Image, Probe.Region)),
                "rectangle and circle in a circle region");
      end;
      for Seed in Interfaces.Unsigned_32 range 101 .. 120 loop
         declare
            Probe : IH.Ks_Histogram_Tool;
         begin
            Probe.Input_Image :=
              Random_Image (17 + Natural (Seed mod 7), 9, Seed);
            Probe.Run;
            Check (Probe.Result.Get_Minimum_WGV_Threshold
                     = Brute_WGV_Threshold
                         (Expected (Probe.Input_Image, RH.Empty_Holder)),
                   "random image" & Seed'Image & ": the brute-force"
                   & " threshold");
         end;
      end loop;

      Section ("Histogram: bin modes");
      declare
         E : constant Expected_Statistics :=
           Expected (Tool.Input_Image, Tool.Region);
      begin
         Tool.Run_Params := (Bin_Mode => IH.Compatibility, Num_Bins => 100);
         Tool.Run;
         declare
            Bins : constant IH.Ks_Histogram_Array :=
              Tool.Result.Get_Histogram;
            Last : Natural := 0;
            Same : Boolean := Bins'First = 0 and then Bins'Last = 99;
         begin
            Check (Same, "Compatibility: 100 bins");
            if Same then
               for V in 0 .. 98 loop
                  Same := Same and then Bins (V) = E.Levels (V);
               end loop;
               for V in 99 .. 255 loop
                  Last := Last + E.Levels (V);
               end loop;
               Check (Same and then Bins (99) = Last,
                      "Compatibility: grey levels >= 99 in the last bin");
            end if;
            Check_Near (Tool.Result.Mean, E.Mean, 1.0E-9,
                        "Compatibility: the statistics are of the levels");
         end;
         Tool.Run_Params := (Bin_Mode => IH.Compatibility, Num_Bins => 300);
         Tool.Run;
         declare
            Bins : constant IH.Ks_Histogram_Array :=
              Tool.Result.Get_Histogram;
         begin
            Check (Bins'Length = 300 and then Bins (255) = E.Levels (255)
                   and then Bins (299) = 0,
                   "Compatibility: bins above 255 are empty");
         end;
         Tool.Run_Params := (Bin_Mode => IH.Uniform, Num_Bins => 16);
         Tool.Run;
         declare
            Bins : constant IH.Ks_Histogram_Array :=
              Tool.Result.Get_Histogram;
            Same : Boolean := Bins'First = 0 and then Bins'Last = 15;
         begin
            if Same then
               for B in 0 .. 15 loop
                  declare
                     Sum : Natural := 0;
                  begin
                     for V in 16 * B .. 16 * B + 15 loop
                        Sum := Sum + E.Levels (V);
                     end loop;
                     Same := Same and then Bins (B) = Sum;
                  end;
               end loop;
            end if;
            Check (Same, "Uniform: 16 bins of 16 grey levels");
         end;
         Tool.Run_Params := (Bin_Mode => IH.Uniform, Num_Bins => 3);
         Tool.Run;
         declare
            Bins : constant IH.Ks_Histogram_Array :=
              Tool.Result.Get_Histogram;
            Sums : array (0 .. 2) of Natural := [others => 0];
         begin
            for V in Level_Counts'Range loop
               Sums (V * 3 / 256) := Sums (V * 3 / 256) + E.Levels (V);
            end loop;
            Check (Bins'Length = 3 and then Bins (0) = Sums (0)
                   and then Bins (1) = Sums (1) and then Bins (2) = Sums (2),
                   "Uniform: 3 bins of floor (V * 3 / 256)");
         end;
         Tool.Run_Params := (Bin_Mode => IH.Auto, Num_Bins => 7);
         Tool.Run;
         Check (Tool.Result.Get_Histogram'Length = 256,
                "Auto ignores Num_Bins");
      end;

      Section ("Histogram: parameter validation");
      declare
         procedure Expect_Bad (Params : IH.Ks_Histogram; Message : String) is
         begin
            Tool.Run_Params := Params;
            Tool.Run;
            Check (Tool.Run_Status.Result = Error
                   and then Tool.Run_Status.Exception_Name = Bad_Name
                   and then Tool.Run_Status.Message = Message,
                   "rejected: " & Message & " (got "
                   & Tool.Run_Status.Message & ")");
         end Expect_Bad;
      begin
         Expect_Bad ((IH.Auto, 0), "RunParams.NumBins must be in 1 .. 65536");
         Expect_Bad ((IH.Compatibility, 65_537),
                     "RunParams.NumBins must be in 1 .. 65536");
         Expect_Bad ((7, 10), "RunParams.BinMode must be Compatibility (1), "
                              & "Uniform (2) or Auto (3)");
         Expect_Bad ((IH.Uniform, 257),
                     "RunParams.NumBins must be at most 256 in Uniform mode");
      end;
      declare
         procedure No_Result is
            M : constant Real := Tool.Result.Mean;
         begin
            Fail ("a failed run left a result:" & Real'Image (M));
         end No_Result;
         procedure Check_No_Result is new Check_Raises_Exactly
           (No_Result, Ks_Exception'Identity);
      begin
         Check_No_Result ("the result of a failed run raises Ks_Exception");
      end;

      Section ("Histogram: empty region and unallocated image");
      Tool.Run_Params := (others => <>);
      Tool.Region := Rectangle (100.0, 100.0, 5.0, 5.0);
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Result.Num_Samples = 0
             and then Tool.Result.Mean = 0.0
             and then Tool.Result.Variance = 0.0
             and then Tool.Result.Minimum = 0
             and then Tool.Result.Maximum = 0
             and then Tool.Result.Median = 0
             and then Tool.Result.Get_Inverse_Cumulative_Grey_Level (70) = 0,
             "a region outside the image: no samples, statistics 0");
      declare
         Bins : constant IH.Ks_Histogram_Array := Tool.Result.Get_Histogram;
      begin
         Check (Bins'Length = 256 and then (for all B of Bins => B = 0),
                "a region outside the image: every bin 0");
      end;
      declare
         Unallocated : Ks_Image_8_Grey;
      begin
         Tool.Input_Image := Unallocated;
         Tool.Run;
         Check (Tool.Run_Status.Result = Error
                and then Tool.Run_Status.Exception_Name = No_Pixels_Name
                and then Tool.Run_Status.Message = "InputImage has no pixels",
                "an unallocated input: Error, InputImage has no pixels");
      end;

      Section ("Histogram: fixture space");
      Image := Random_Image (60, 50, 11);
      Add_Fixture (Image);
      Tool.Input_Image := Image;
      Tool.Region := Rectangle (3.0, 4.0, 20.0, 15.0);
      Tool.Run;
      Check_Statistics (Tool, Expected (Image, Tool.Region),
                        "a rectangle in the fixture space");
      declare
         --  The same rectangle given in pixel space covers other pixels.
         Pixel_Tool : IH.Ks_Histogram_Tool;
      begin
         Pixel_Tool.Input_Image := Image;
         Pixel_Tool.Region := Rectangle (3.0, 4.0, 20.0, 15.0, "#");
         Pixel_Tool.Run;
         --  Pixel centres 3 .. 23 by 4 .. 19 (the edges are inside).
         Check (Pixel_Tool.Result.Num_Samples = 21 * 16
                and then Tool.Result.Num_Samples
                           = AMV.Regions.Rasterize
                               (Image, Tool.Region).Pixel_Count
                and then Pixel_Tool.Result.Mean /= Tool.Result.Mean,
                "the region is mapped from its selected space");
      end;

      Section ("Histogram: input image mask");
      declare
         Known : Ks_Image_8_Grey := Create (30, 20, 10);
         Block : constant Ks_Image_8_Grey := Create (5, 5, 0);
         Mask  : Ks_Image_8_Grey := Create (12, 9, 255);
         Masked_Tool : IH.Ks_Histogram_Tool;

         function Level (B : Natural) return Natural is
           (Masked_Tool.Result.Get_Histogram (B));
      begin
         --  25 pixels of 200 at 5 .. 9 by 3 .. 7, three of 90 at
         --  20 .. 22 by 15, every other pixel 10.
         for Y in 3 .. 7 loop
            for X in 5 .. 9 loop
               Known.Set_Pixel (X, Y, 200);
            end loop;
         end loop;
         for X in 20 .. 22 loop
            Known.Set_Pixel (X, 15, 90);
         end loop;
         Masked_Tool.Input_Image := Known;
         Check (not Masked_Tool.Input_Image_Mask.Allocated
                and then Masked_Tool.Input_Image_Mask_Offset_X = 0
                and then Masked_Tool.Input_Image_Mask_Offset_Y = 0,
                "mask: the default is no mask at offset 0");
         Masked_Tool.Run;
         Check (Masked_Tool.Result.Num_Samples = 600
                and then Level (10) = 572 and then Level (90) = 3
                and then Level (200) = 25,
                "mask: the counts without a mask");

         --  A mask of 0 exactly over the block of 200.
         Masked_Tool.Input_Image_Mask := Block;
         Masked_Tool.Input_Image_Mask_Offset_X := 5;
         Masked_Tool.Input_Image_Mask_Offset_Y := 3;
         Masked_Tool.Run;
         Check (Masked_Tool.Run_Status.Result = Accept_Result
                and then Masked_Tool.Result.Num_Samples = 575
                and then Level (10) = 572 and then Level (90) = 3
                and then Level (200) = 0
                and then Masked_Tool.Result.Maximum = 90,
                "mask: the block of 200 is not counted");
         Check_Statistics
           (Masked_Tool,
            Expected (Known, RH.Empty_Holder, Block, 5, 3),
            "mask over the block");

         --  One pixel to the left: one column of 10 instead of 200.
         Masked_Tool.Input_Image_Mask_Offset_X := 4;
         Masked_Tool.Run;
         Check (Masked_Tool.Result.Num_Samples = 575
                and then Level (10) = 567 and then Level (200) = 5,
                "mask: offset one pixel to the left");

         --  A negative offset: only 3 x 3 pixels of the mask lie over the
         --  image (0 .. 2 by 0 .. 2, all 10).
         Masked_Tool.Input_Image_Mask_Offset_X := -2;
         Masked_Tool.Input_Image_Mask_Offset_Y := -2;
         Masked_Tool.Run;
         Check (Masked_Tool.Result.Num_Samples = 591
                and then Level (10) = 563 and then Level (200) = 25,
                "mask: a negative offset");

         --  Beyond the image: 2 x 1 mask pixels lie over 28 .. 29 by 19.
         Masked_Tool.Input_Image_Mask_Offset_X := 28;
         Masked_Tool.Input_Image_Mask_Offset_Y := 19;
         Masked_Tool.Run;
         Check (Masked_Tool.Result.Num_Samples = 598,
                "mask: partly beyond the image");
         Masked_Tool.Input_Image_Mask_Offset_X := 30;
         Masked_Tool.Run;
         Check (Masked_Tool.Result.Num_Samples = 600,
                "mask: wholly beyond the image");

         --  A pattern of 0 (and other values that count as "care") with
         --  a region.
         for Y in 0 .. 8 loop
            for X in 0 .. 11 loop
               if (X + 2 * Y) mod 3 = 0 then
                  Mask.Set_Pixel (X, Y, 0);
               elsif X mod 4 = 1 then
                  Mask.Set_Pixel (X, Y, 1);
               end if;
            end loop;
         end loop;
         Masked_Tool.Input_Image_Mask := Mask;
         Masked_Tool.Input_Image_Mask_Offset_X := 3;
         Masked_Tool.Input_Image_Mask_Offset_Y := 1;
         Masked_Tool.Region := Circle (9.0, 6.0, 5.5);
         Masked_Tool.Run;
         Check_Statistics
           (Masked_Tool, Expected (Known, Masked_Tool.Region, Mask, 3, 1),
            "a pattern over a circle");
         Check (Masked_Tool.Result.Num_Samples
                  < Expected (Known, Masked_Tool.Region).Count,
                "a pattern over a circle: fewer samples than unmasked");
         Masked_Tool.Input_Image := Random_Image (40, 30, 5);
         Masked_Tool.Input_Image_Mask_Offset_X := 25;
         Masked_Tool.Input_Image_Mask_Offset_Y := -4;
         Masked_Tool.Region := Rectangle (20.5, 0.0, 19.0, 12.0);
         Masked_Tool.Run;
         Check_Statistics
           (Masked_Tool,
            Expected (Masked_Tool.Input_Image, Masked_Tool.Region, Mask, 25,
                      -4),
            "a pattern over noise");

         --  A mask of 0 over the whole region: no samples.
         Masked_Tool.Input_Image := Known;
         Masked_Tool.Region := RH.Empty_Holder;
         Masked_Tool.Input_Image_Mask := Create (30, 20, 0);
         Masked_Tool.Input_Image_Mask_Offset_X := 0;
         Masked_Tool.Input_Image_Mask_Offset_Y := 0;
         Masked_Tool.Run;
         Check (Masked_Tool.Run_Status.Result = Accept_Result
                and then Masked_Tool.Result.Num_Samples = 0
                and then Masked_Tool.Result.Mean = 0.0
                and then Level (10) = 0,
                "mask: every pixel removed gives no samples");

         --  Back to no mask (offsets alone change nothing).
         Masked_Tool.Input_Image_Mask := No_Mask;
         Masked_Tool.Input_Image_Mask_Offset_X := 7;
         Masked_Tool.Input_Image_Mask_Offset_Y := -3;
         Masked_Tool.Run;
         Check_Statistics
           (Masked_Tool, Expected (Known, RH.Empty_Holder),
            "an unallocated mask");
         Check (Masked_Tool.Result.Num_Samples = 600
                and then Level (200) = 25,
                "an unallocated mask: every pixel counted");
      end;

      Section ("Histogram: region mode");
      declare
         Known  : Ks_Image_8_Grey := Create (30, 20, 10);
         Modes  : IH.Ks_Histogram_Tool;
         Circle : Ks_Circle;
         Rect   : Ks_Rectangle_Affine;

         function Level (B : Natural) return Natural is
           (Modes.Result.Get_Histogram (B));
      begin
         --  25 pixels of 200 at 5 .. 9 by 3 .. 7, every other pixel 10.
         for Y in 3 .. 7 loop
            for X in 5 .. 9 loop
               Known.Set_Pixel (X, Y, 200);
            end loop;
         end loop;
         Modes.Input_Image := Known;
         Check (Modes.Region_Mode = IH.Pixel_Aligned_Bounding_Box_Adjust_Mask,
                "region mode: AdjustMask by default (as VisionPro)");
         --  A circle of radius 2.5 about (7, 5) covers 21 pixel centres;
         --  its bounding box is the 5 x 5 block.
         Circle.Set_Center_Radius (7.0, 5.0, 2.5);
         Modes.Region := RH.To_Holder (Circle);
         Modes.Run;
         Check (Modes.Result.Num_Samples = 21 and then Level (200) = 21,
                "AdjustMask: the pixels the circle covers");
         Modes.Region_Mode := IH.Pixel_Aligned_Bounding_Box;
         Modes.Run;
         Check (Modes.Result.Num_Samples = 25 and then Level (200) = 25
                and then Level (10) = 0,
                "PixelAlignedBoundingBox: every pixel of the box");
         --  The mask applies after the box is taken.
         Modes.Input_Image_Mask := Create (1, 1, 0);
         Modes.Input_Image_Mask_Offset_X := 5;
         Modes.Input_Image_Mask_Offset_Y := 3;
         Modes.Run;
         Check (Modes.Result.Num_Samples = 24,
                "PixelAlignedBoundingBox: the mask removes a corner of the "
                & "box");
         Modes.Region_Mode := IH.Affine_Transform;
         Modes.Run;
         Check (Modes.Run_Status.Result = Error
                and then Modes.Run_Status.Message
                           = "Region must be an affine rectangle for "
                             & "RegionMode AffineTransform",
                "AffineTransform: a circle is rejected");
         Rect.Set_Center_Lengths_Rotation_Skew (7.0, 5.0, 5.0, 5.0, 0.0, 0.0);
         Modes.Region := RH.To_Holder (Rect);
         Modes.Run;
         Check (Modes.Run_Status.Result = Error
                and then Modes.Run_Status.Message
                           = "InputImageMask is not supported with "
                             & "RegionMode AffineTransform",
                "AffineTransform: a mask is rejected");
         Modes.Input_Image_Mask := No_Mask;
         Modes.Run;
         Check (Modes.Run_Status.Result = Accept_Result
                and then Modes.Result.Num_Samples = 25
                and then Level (200) = 25,
                "AffineTransform: the 5 x 5 rectangle resampled upright");
         --  Turned by 90 degrees about its centre: the same pixels.
         Rect.Set_Center_Lengths_Rotation_Skew
           (7.0, 5.0, 5.0, 5.0, AMV.Misc.Pi / 2.0, 0.0);
         Modes.Region := RH.To_Holder (Rect);
         Modes.Run;
         Check (Modes.Result.Num_Samples = 25
                and then Level (200) = 25,
                "AffineTransform: a turned rectangle");
         Modes.Region.Clear;
         Modes.Run;
         Check (Modes.Result.Num_Samples = 600,
                "AffineTransform without a region: the whole image");
         Modes.Region_Mode := 3;
         Modes.Run;
         Check (Modes.Run_Status.Result = Error
                and then Modes.Run_Status.Message
                           = "RegionMode must be "
                             & "PixelAlignedBoundingBoxAdjustMask (0), "
                             & "PixelAlignedBoundingBox (1) or "
                             & "AffineTransform (2)",
                "RegionMode 3 is rejected");
      end;
   end Test_Histogram;

   ---------------------------------------------------------------------
   --  Pixel map
   ---------------------------------------------------------------------

   procedure Test_Pixel_Map is
      Image : Ks_Image_8_Grey := Random_Image (40, 30, 3);
      Tool  : IP.Ks_Pixel_Map_Tool;
   begin
      Section ("Pixel map: identity");
      Tool.Input_Image := Image;
      Check (IP.Get_Map (Tool.Run_Params) = IP.Identity_Map,
             "the default map is the identity");
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result,
             "Accept_Result (" & Tool.Run_Status.Message & ")");
      Check (Tool.Output_Image.To_Matrix = Image.To_Matrix,
             "the identity map copies the image");
      Check (not Shares_Pixels (Tool.Output_Image, Image),
             "the output has pixels of its own");

      Section ("Pixel map: an inverting table in a circle");
      declare
         Map : IP.Pixel_Map_Table;
      begin
         for V in Map'Range loop
            Map (V) := 255 - V;
         end loop;
         IP.Set_Map (Tool.Run_Params, Map);
      end;
      Tool.Region := Circle (19.5, 14.5, 9.0);
      Tool.Run;
      declare
         R    : constant AMV.Regions.Pixel_Region :=
           AMV.Regions.Rasterize (Image, Tool.Region);
         Good : Boolean := Tool.Output_Image.Width = 40
                           and then Tool.Output_Image.Height = 30;
      begin
         if Good then
            for Y in 0 .. 29 loop
               for X in 0 .. 39 loop
                  Good := Good
                    and then Tool.Output_Image.Get_Pixel (X, Y)
                               = (if R.Contains (X, Y)
                                  then 255 - Image.Get_Pixel (X, Y)
                                  else Image.Get_Pixel (X, Y));
               end loop;
            end loop;
         end if;
         Check (Good, "region pixels mapped, the others copied");
         Check (R.Pixel_Count > 200, "the circle covers pixels");
      end;
      Tool.Run_Params.Map (0) := 77;
      Check (IP.Get_Map (Tool.Run_Params) (0) = 77,
             "the map is a public component");

      Section ("Pixel map: empty region, coordinate spaces");
      Tool.Region := Rectangle (-50.0, -50.0, 10.0, 10.0);
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Output_Image.To_Matrix = Image.To_Matrix,
             "a region outside the image leaves every pixel unchanged");
      Add_Fixture (Image);
      Image.Set_Pixel_From_Root_Transform
        (AMV.Transforms.Create_Rigid (0.0, 1.0, 2.0));
      Tool.Input_Image := Image;
      Tool.Region := Rectangle (0.0, 0.0, 10.0, 10.0);
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result
             and then Same_Spaces (Tool.Output_Image, Image)
             and then Tool.Output_Image.Selected_Space_Name = "@\Fixture",
             "the output keeps the tree, the selection and the "
             & "pixel-from-root transform");

      Section ("Pixel map: unallocated image");
      declare
         Unallocated : Ks_Image_8_Grey;
      begin
         Tool.Input_Image := Unallocated;
         Tool.Run;
         Check (Tool.Run_Status.Result = Error
                and then Tool.Run_Status.Exception_Name = No_Pixels_Name
                and then not Tool.Output_Image.Allocated,
                "Error, and no output image");
      end;
   end Test_Pixel_Map;

   ---------------------------------------------------------------------
   --  Sobel edge
   ---------------------------------------------------------------------

   function Column_Only
     (Image  : Ks_Image_8_Grey;
      Column : Natural;
      Value  : Grey_8) return Boolean;
   --  Every pixel of Column is Value and every other pixel is 0.

   function Column_Only
     (Image  : Ks_Image_8_Grey;
      Column : Natural;
      Value  : Grey_8) return Boolean is
   begin
      for Y in 0 .. Image.Height - 1 loop
         for X in 0 .. Image.Width - 1 loop
            if Image.Get_Pixel (X, Y) /= (if X = Column then Value else 0)
            then
               return False;
            end if;
         end loop;
      end loop;
      return True;
   end Column_Only;

   procedure Test_Sobel_Edge is
      Tool : IE.Ks_Sobel_Edge_Tool;
      type Mode_List is array (Positive range <>) of K.Int32;
   begin
      Section ("Sobel: a vertical step edge");
      --  50 left of column 32, 150 from it on: the Sobel magnitude is the
      --  step, 100, in columns 31 and 32, and 0 elsewhere.
      Tool.Input_Image := Step_Image (64, 48, 50, 150, 32);
      Check (Tool.Run_Params = KE.Ks_Sobel_Edge'(others => <>)
             and then Tool.Run_Params.Magnitude_Scale = 1.0
             and then Tool.Run_Params.Post_Process_Mode = IE.None
             and then Tool.Run_Params.Peak_Detect_Threshold = 20
             and then Tool.Run_Params.Hysteresis_Threshold_Low = 10
             and then Tool.Run_Params.Hysteresis_Threshold_High = 20
             and then Tool.Run_Params.Hysteresis_Survivor_Pel_Value = 255
             and then Tool.Run_Params.Hysteresis_Non_Survivor_Pel_Value = 0
             and then Tool.Run_Params.Region_Mode
                        = IE.Pixel_Aligned_Bounding_Box,
             "VisionPro's defaults");
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result,
             "Accept_Result (" & Tool.Run_Status.Message & ")");
      declare
         M : constant Ks_Image_8_Grey := Tool.Result.Edge_Magnitude_Image;
         A : constant Ks_Image_8_Grey := Tool.Result.Edge_Angle_Image;
         F : constant Ks_Image_8_Grey := Tool.Result.Final_Magnitude_Image;
         Good : Boolean := True;
      begin
         for Y in 0 .. 47 loop
            for X in 0 .. 63 loop
               Good := Good
                 and then M.Get_Pixel (X, Y)
                            = (if X in 31 .. 32 then 100 else 0)
                 and then A.Get_Pixel (X, Y) = 0;
            end loop;
         end loop;
         Check (Good, "magnitude 100 on both sides of the step, angle 0 "
                      & "(towards +x)");
         Check (F.To_Matrix = M.To_Matrix,
                "None: the final image is the magnitude image");
      end;

      Section ("Sobel: directions");
      Tool.Input_Image := Step_Image (64, 48, 150, 50, 32);
      Tool.Run;
      Check (Tool.Result.Edge_Angle_Image.Get_Pixel (31, 10) = 128
             and then Tool.Result.Edge_Magnitude_Image.Get_Pixel (31, 10)
                        = 100,
             "a step down to the right points along -x (128)");
      declare
         Image : Ks_Image_8_Grey := Create (64, 48, 50);
      begin
         for Y in 24 .. 47 loop
            for X in 0 .. 63 loop
               Image.Set_Pixel (X, Y, 150);
            end loop;
         end loop;
         Tool.Input_Image := Image;
         Tool.Run;
         Check (Tool.Result.Edge_Angle_Image.Get_Pixel (10, 23) = 64
                and then Tool.Result.Edge_Angle_Image.Get_Pixel (10, 24) = 64
                and then Tool.Result.Edge_Magnitude_Image.Get_Pixel (10, 24)
                           = 100,
                "brighter below: +y (64)");
         for Y in 0 .. 47 loop
            for X in 0 .. 63 loop
               Image.Set_Pixel (X, Y, (if X + Y > 63 then 200 else 40));
            end loop;
         end loop;
         Tool.Run;
         Check (Tool.Result.Edge_Angle_Image.Get_Pixel (32, 32) = 32
                and then Tool.Result.Edge_Angle_Image.Get_Pixel (20, 43) = 32,
                "brighter to the lower right: 45 degrees (32)");
      end;

      Section ("Sobel: a ramp and the magnitude scale");
      --  Slope 4 grey levels per pixel: the magnitude (grey level
      --  difference across two pixels) is 8.
      Tool.Input_Image := AMV_Test_Images.Horizontal_Ramp (64, 8, 0.0, 252.0);
      Tool.Run;
      Check (Tool.Result.Edge_Magnitude_Image.Get_Pixel (30, 3) = 8,
             "a ramp of slope 4 gives magnitude 8");
      Tool.Input_Image := Step_Image (64, 48, 50, 150, 32);
      Tool.Run_Params.Magnitude_Scale := 0.5;
      Tool.Run;
      Check (Tool.Result.Edge_Magnitude_Image.Get_Pixel (32, 5) = 50,
             "MagnitudeScale 0.5 halves the magnitude");
      Tool.Run_Params.Magnitude_Scale := 3.0;
      Tool.Run;
      Check (Tool.Result.Edge_Magnitude_Image.Get_Pixel (32, 5) = 255,
             "magnitudes above 255 are clamped");
      declare
         Image : Ks_Image_8_Grey := Create (8, 8, 0);
      begin
         --  The steepest corner of an 8-bit image around (4, 4): the
         --  magnitude is Sqrt (255**2 + 127.5**2), about 285.1, which
         --  MagnitudeScale 0.89 brings just below 256.
         Image.Set_Pixel (5, 3, 255);
         Image.Set_Pixel (5, 4, 255);
         Image.Set_Pixel (4, 5, 255);
         Image.Set_Pixel (5, 5, 255);
         Tool.Input_Image := Image;
         Tool.Run_Params.Magnitude_Scale := 0.89;
         Tool.Run;
         Check (Tool.Result.Edge_Magnitude_Image.Get_Pixel (4, 4) = 254,
                "MagnitudeScale 0.89: the steepest corner gives 254");
         Tool.Run_Params.Magnitude_Scale := 1.0;
         Tool.Run;
         Check (Tool.Result.Edge_Magnitude_Image.Get_Pixel (4, 4) = 255,
                "MagnitudeScale 1: the steepest corner is clamped to 255");
      end;
      Tool.Run_Params := (others => <>);

      Section ("Sobel: peak detection");
      Tool.Input_Image := Step_Image (64, 48, 50, 150, 32);
      Tool.Run_Params.Post_Process_Mode := IE.Peak_Detect;
      Tool.Run;
      Check (Column_Only (Tool.Result.Final_Magnitude_Image, 32, 100),
             "one column survives, with its magnitude");
      Tool.Run_Params.Peak_Detect_Threshold := 101;
      Tool.Run;
      Check (Column_Only (Tool.Result.Final_Magnitude_Image, 32, 0),
             "a threshold above the magnitude removes the edge");

      Section ("Sobel: hysteresis thresholding");
      declare
         Image : Ks_Image_8_Grey := Create (64, 48, 100);
      begin
         --  A vertical edge, strong (50) above row 24 and weak (15) below,
         --  and a separate weak block edge (15) on the left.
         for Y in 0 .. 47 loop
            for X in 32 .. 63 loop
               Image.Set_Pixel (X, Y, (if Y < 24 then 150 else 115));
            end loop;
         end loop;
         for Y in 30 .. 47 loop
            for X in 5 .. 20 loop
               Image.Set_Pixel (X, Y, 115);
            end loop;
         end loop;
         Tool.Input_Image := Image;
      end;
      Tool.Run_Params := (others => <>);
      Tool.Run_Params.Post_Process_Mode := IE.Hysteresis_Threshold;
      IE.Set_Hysteresis_Thresholds (Tool.Run_Params, 10, 40);
      Tool.Run;
      declare
         F : constant Ks_Image_8_Grey := Tool.Result.Final_Magnitude_Image;
      begin
         Check (Tool.Run_Status.Result = Accept_Result
                and then F.Get_Pixel (32, 5) = 255
                and then F.Get_Pixel (32, 40) = 255
                and then F.Get_Pixel (31, 45) = 255,
                "the strong edge and the weak edge connected to it survive");
         Check (F.Get_Pixel (5, 40) = 0 and then F.Get_Pixel (20, 40) = 0
                and then F.Get_Pixel (12, 30) = 0
                and then F.Get_Pixel (50, 10) = 0,
                "a weak edge on its own and flat pixels do not");
         Check ((for all Y in 0 .. 47
                 => (for all X in 0 .. 63
                     => F.Get_Pixel (X, Y) in 0 | 255)),
                "every pixel is a survivor or a non-survivor");
      end;
      Tool.Run_Params.Hysteresis_Survivor_Pel_Value := 7;
      Tool.Run_Params.Hysteresis_Non_Survivor_Pel_Value := 7;
      Tool.Run;
      Check ((for all Y in 0 .. 47
              => (for all X in 0 .. 63
                  => Tool.Result.Final_Magnitude_Image.Get_Pixel (X, Y) = 7)),
             "equal survivor and non-survivor values");
      Tool.Run_Params.Hysteresis_Non_Survivor_Pel_Value := 1;
      IE.Set_Hysteresis_Thresholds (Tool.Run_Params, 10, 60);
      Tool.Run;
      Check (Tool.Result.Final_Magnitude_Image.Get_Pixel (32, 5) = 1,
             "no seed above the high threshold: nothing survives");

      Section ("Sobel: Region_Mode Pixel_Aligned_Bounding_Box");
      declare
         Image : Ks_Image_8_Grey := Step_Image (64, 48, 50, 150, 32);
         Plain : IE.Ks_Sobel_Edge_Tool;

         function Same (A, B : Ks_Image_8_Grey) return Boolean is
           (A.Width = B.Width and then A.Height = B.Height
            and then A.To_Matrix = B.To_Matrix);
      begin
         Add_Fixture (Image);
         Tool.Input_Image := Image;
         Tool.Run_Params := (others => <>);
         Tool.Run_Params.Post_Process_Mode := IE.Peak_Detect;
         Plain.Run_Params := Tool.Run_Params;
         for Shape in 1 .. 2 loop
            if Shape = 1 then
               Tool.Region := Rectangle (20.0, 0.0, 30.0, 10.0, "#");
            else
               declare
                  C : Ks_Circle;
               begin
                  C.Set_Center_Radius (32.0, 20.0, 9.0);
                  C.Set_Selected_Space_Name ("#");
                  Tool.Region := RH.To_Holder (C);
               end;
            end if;
            declare
               R : constant AMV.Regions.Pixel_Region :=
                 AMV.Regions.Rasterize (Image, Tool.Region);
               P  : constant Grey_8_Matrix := Image.To_Matrix;
               W  : constant Natural := R.Width;
               H  : constant Natural := R.Height;
               X0 : constant Natural := R.X_Min;
               Y0 : constant Natural := R.Y_Min;
               B  : Grey_8_Matrix (0 .. H - 1, 0 .. W - 1);
               MX, MY, OX, OY : Real;
            begin
               for Y in B'Range (1) loop
                  for X in B'Range (2) loop
                     B (Y, X) := P (Y0 + Y, X0 + X);
                  end loop;
               end loop;
               Tool.Run;
               Plain.Input_Image := From_Matrix (B);
               Plain.Run;
               Check (Tool.Run_Status.Result = Accept_Result
                      and then Plain.Run_Status.Result = Accept_Result
                      and then R.Width < 64 and then R.Height < 48,
                      "region" & Shape'Image & " ("
                      & Tool.Run_Status.Message & ")");
               Check (Same (Tool.Result.Edge_Magnitude_Image,
                            Plain.Result.Edge_Magnitude_Image)
                      and then Same (Tool.Result.Edge_Angle_Image,
                                     Plain.Result.Edge_Angle_Image)
                      and then Same (Tool.Result.Final_Magnitude_Image,
                                     Plain.Result.Final_Magnitude_Image),
                      "the three images of the region's box, as of an"
                      & " image of its own (region" & Shape'Image & ")");
               --  A root point on input pixel (X_Min + 3, Y_Min + 2) lies
               --  on output pixel (3, 2).
               Image.Pixel_From_Root_Transform.Invert.Map_Point
                 (Real (R.X_Min + 3), Real (R.Y_Min + 2), MX, MY);
               Tool.Result.Final_Magnitude_Image.Pixel_From_Root_Transform
                 .Map_Point (MX, MY, OX, OY);
               Check (abs (OX - 3.0) < 1.0E-9 and then abs (OY - 2.0) < 1.0E-9
                      and then Tool.Result.Edge_Angle_Image
                                 .Selected_Space_Name = "@\Fixture",
                      "the images keep the meaning of root coordinates"
                      & " and the selected space (region" & Shape'Image
                      & ")");
               if Shape = 2 then
                  Check (not R.Contains (31, Y0) and then X0 < 31
                         and then Tool.Result.Edge_Magnitude_Image
                                    .Get_Pixel (31 - X0, 0) = 100,
                         "every pixel of the box is processed, also"
                         & " outside the circle");
               end if;
            end;
         end loop;
         Tool.Region := Rectangle (200.0, 0.0, 30.0, 10.0, "#");
         Tool.Run;
         Check (Tool.Run_Status.Result = Error
                and then Tool.Run_Status.Exception_Name
                           = "AMV.KS_BAD_PARAMETER_EXCEPTION"
                and then Tool.Run_Status.Message
                           = "Region covers no pixel of InputImage"
                and then not Tool.Result.Edge_Magnitude_Image.Allocated,
                "a region outside the image (" & Tool.Run_Status.Message
                & ")");
         for Mode of Mode_List'(0, 3, K.Int32'Last) loop
            Tool.Region := RH.Empty_Holder;
            Tool.Run_Params.Region_Mode := Mode;
            Tool.Run;
            Check (Tool.Run_Status.Result = Error
                   and then Tool.Run_Status.Message
                              = "RunParams.RegionMode must be"
                                & " PixelAlignedBoundingBox (1) or"
                                & " AffineTransform (2)",
                   "Region_Mode" & Mode'Image & " ("
                   & Tool.Run_Status.Message & ")");
         end loop;
         Tool.Run_Params.Region_Mode := IE.Pixel_Aligned_Bounding_Box;
      end;

      Section ("Sobel: Region_Mode Affine_Transform");
      declare
         Image  : constant Ks_Image_8_Grey :=
           Step_Image (64, 48, 50, 150, 32);
         Affine : AMV.Image_Processing.Affine_Transform
                    .Ks_Affine_Transform_Tool;
         Plain  : IE.Ks_Sobel_Edge_Tool;
         R      : Ks_Rectangle_Affine;
         MX, MY, AX, AY, OX, OY : Real;
      begin
         Tool.Input_Image := Image;
         Tool.Run_Params := (others => <>);
         Tool.Run_Params.Region_Mode := IE.Affine_Transform;
         R.Set_Center_Lengths_Rotation_Skew
           (32.0, 20.0, 24.0, 16.0, 0.4, 0.0);
         Tool.Region := RH.To_Holder (R);
         Tool.Run;
         Affine.Input_Image := Image;
         Affine.Region := R;
         Affine.Run;
         Plain.Input_Image := Affine.Output_Image;
         Plain.Run;
         Check (Tool.Run_Status.Result = Accept_Result
                and then Tool.Result.Edge_Magnitude_Image.To_Matrix
                           = Plain.Result.Edge_Magnitude_Image.To_Matrix
                and then Tool.Result.Edge_Angle_Image.To_Matrix
                           = Plain.Result.Edge_Angle_Image.To_Matrix,
                "the affine rectangle resampled as the affine transform"
                & " tool does, then processed ("
                & Tool.Run_Status.Message & ")");
         Affine.Output_Image.Pixel_From_Root_Transform.Invert.Map_Point
           (4.0, 3.0, MX, MY);
         Affine.Output_Image.Pixel_From_Root_Transform.Map_Point
           (MX, MY, AX, AY);
         Tool.Result.Edge_Magnitude_Image.Pixel_From_Root_Transform
           .Map_Point (MX, MY, OX, OY);
         Check (abs (OX - AX) < 1.0E-9 and then abs (OY - AY) < 1.0E-9,
                "the images keep the resampled rectangle's root"
                & " coordinates");
         Tool.Region := Rectangle (20.0, 0.0, 30.0, 10.0);
         Tool.Run;
         Check (Tool.Run_Status.Result = Error
                and then Tool.Run_Status.Message
                           = "Region must be an affine rectangle for"
                             & " RegionMode AffineTransform",
                "a rectangle with Affine_Transform ("
                & Tool.Run_Status.Message & ")");
         Tool.Region := RH.Empty_Holder;
         Tool.Run;
         Plain.Input_Image := Image;
         Plain.Run;
         Check (Tool.Run_Status.Result = Accept_Result
                and then Tool.Result.Final_Magnitude_Image.To_Matrix
                           = Plain.Result.Final_Magnitude_Image.To_Matrix,
                "no region: the whole image");
         Tool.Run_Params := (others => <>);
      end;

      Section ("Sobel: parameter validation and unallocated image");
      declare
         procedure Expect_Bad (Params : IE.Ks_Sobel_Edge; Message : String)
         is
         begin
            Tool.Run_Params := Params;
            Tool.Run;
            Check (Tool.Run_Status.Result = Error
                   and then Tool.Run_Status.Exception_Name = Bad_Name
                   and then Tool.Run_Status.Message = Message
                   and then not Tool.Result.Edge_Magnitude_Image.Allocated,
                   "rejected: " & Message & " (got "
                   & Tool.Run_Status.Message & ")");
         end Expect_Bad;
         Default : constant IE.Ks_Sobel_Edge := (others => <>);
         P       : IE.Ks_Sobel_Edge;
      begin
         P := Default;
         P.Magnitude_Scale := -0.1;
         Expect_Bad (P, "RunParams.MagnitudeScale must be in 0 .. 50");
         P.Magnitude_Scale := 50.5;
         Expect_Bad (P, "RunParams.MagnitudeScale must be in 0 .. 50");
         P := Default;
         P.Post_Process_Mode := 3;
         Expect_Bad (P, "RunParams.PostProcessMode must be None (0), "
                        & "PeakDetect (1) or HysteresisThreshold (2)");
         P := Default;
         P.Peak_Detect_Threshold := 256;
         Expect_Bad (P, "RunParams.PeakDetectThreshold must be in 0 .. 255");
         P := Default;
         IE.Set_Hysteresis_Thresholds (P, 30, 20);
         Expect_Bad (P, "RunParams.HysteresisThresholdHigh must be >= "
                        & "HysteresisThresholdLow");
         P := Default;
         P.Hysteresis_Survivor_Pel_Value := -1;
         Expect_Bad (P,
                     "RunParams.HysteresisSurvivorPelValue must be in 0 .. 255");
      end;
      declare
         Unallocated : Ks_Image_8_Grey;
      begin
         Tool.Run_Params := (others => <>);
         Tool.Input_Image := Unallocated;
         Tool.Run;
         Check (Tool.Run_Status.Result = Error
                and then Tool.Run_Status.Exception_Name = No_Pixels_Name,
                "an unallocated input: Error");
      end;
   end Test_Sobel_Edge;

   ---------------------------------------------------------------------
   --  Sharpness
   ---------------------------------------------------------------------

   procedure Test_Sharpness is
      Tool  : SH.Ks_Image_Sharpness_Tool;
      Sharp : Real;
   begin
      Section ("Sharpness: gradient energy");
      Check (Tool.Run_Params.Mode = SH.Gradient_Energy
             and then Tool.Run_Params.Abs_Diff_Distance_X = 1
             and then Tool.Run_Params.Abs_Diff_Distance_Y = 1
             and then Tool.Run_Params.Gradient_Energy_Low_Pass_Smoothing = 0
             and then Tool.Run_Params.Band_Pass_Max_Frequency = 0.45
             and then Tool.Run_Params.Band_Pass_Min_Frequency = 0.25,
             "the defaults");
      --  A step of 100: Dx = 50 in two of 64 columns, so the mean of
      --  Dx**2 is 2 * 2500 / 64.
      Tool.Input_Image := Step_Image (64, 48, 50, 150, 32);
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result,
             "Accept_Result (" & Tool.Run_Status.Message & ")");
      Check_Near (Tool.Score, 2.0 * 2500.0 / 64.0, 1.0E-9,
                  "a step: the mean squared gradient");
      Sharp := Tool.Score;
      Tool.Input_Image := Ramp_Edge (64, 48, 50.0, 150.0, 27.0, 10.0);
      Tool.Run;
      Check (Tool.Score < Sharp / 3.0 and then Tool.Score > 0.0,
             "a blurred edge scores lower than a sharp one:"
             & Real'Image (Tool.Score) & " <" & Real'Image (Sharp));
      Tool.Input_Image := AMV_Test_Images.Horizontal_Ramp (64, 8, 0.0, 252.0);
      Tool.Region := Rectangle (2.0, 1.0, 58.0, 5.0);
      Tool.Run;
      Check_Near (Tool.Score, 16.0, 1.0E-9,
                  "a ramp of slope 4: 16 inside the image");
      Tool.Region := RH.Empty_Holder;
      Tool.Input_Image := Step_Image (64, 48, 50, 150, 32);
      Tool.Run_Params.Gradient_Energy_Low_Pass_Smoothing := 2;
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Score < Sharp and then Tool.Score > 0.0,
             "smoothing lowers the score");
      Tool.Run_Params := (others => <>);

      Section ("Sharpness: absolute differences");
      Tool.Run_Params.Mode := SH.Abs_Diff;
      Tool.Run_Params.Abs_Diff_Distance_Y := 0;
      Tool.Input_Image := AMV_Test_Images.Horizontal_Ramp (64, 8, 0.0, 252.0);
      Tool.Run;
      Check_Near (Tool.Score, 4.0, 1.0E-12,
                  "a ramp of slope 4: differences of 4 along x");
      Tool.Run_Params.Abs_Diff_Distance_X := 0;
      Tool.Run_Params.Abs_Diff_Distance_Y := 1;
      Tool.Run;
      Check_Near (Tool.Score, 0.0, 0.0, "no difference along y");
      declare
         Board   : Ks_Image_8_Grey := Create (64, 64);
         Blurred : Ks_Image_8_Grey;
         Score   : Real;
      begin
         for Y in 0 .. 63 loop
            for X in 0 .. 63 loop
               Board.Set_Pixel
                 (X, Y, (if (X / 4 + Y / 4) mod 2 = 0 then 30 else 220));
            end loop;
         end loop;
         Blurred := AMV.Image_Math.To_Grey_8
           (AMV.Image_Math.Gaussian_Smooth
              (AMV.Image_Math.From_Grey_8 (Board), 1.5));
         Tool.Run_Params.Abs_Diff_Distance_X := 1;
         Tool.Input_Image := Board;
         Tool.Run;
         Score := Tool.Score;
         Tool.Input_Image := Blurred;
         Tool.Run;
         Check (Tool.Score < Score,
                "a blurred checkerboard scores lower:" & Real'Image (Score)
                & " >" & Real'Image (Tool.Score));
      end;

      Section ("Sharpness: validation, empty region, unallocated image");
      declare
         procedure Expect_Bad
           (Params  : SH.Ks_Image_Sharpness;
            Message : String) is
         begin
            Tool.Run_Params := Params;
            Tool.Run;
            Check (Tool.Run_Status.Result = Error
                   and then Tool.Run_Status.Exception_Name = Bad_Name
                   and then Tool.Run_Status.Message = Message
                   and then Tool.Score = 0.0,
                   "rejected: " & Message & " (got "
                   & Tool.Run_Status.Message & ")");
         end Expect_Bad;
         Default : constant SH.Ks_Image_Sharpness := (others => <>);
         P       : SH.Ks_Image_Sharpness;
      begin
         Tool.Input_Image := Step_Image (64, 48, 50, 150, 32);
         P := Default;
         P.Mode := 3;
         Expect_Bad (P, "RunParams.Mode must be AutoCorrelation (1), AbsDiff "
                        & "(2), BandPass (4) or GradientEnergy (8)");
         P.Mode := SH.Band_Pass;
         Expect_Bad (P, "RunParams.Mode: BandPass is not implemented");
         P.Mode := SH.Auto_Correlation;
         Expect_Bad (P, "RunParams.Mode: AutoCorrelation is not implemented");
         P := Default;
         P.Gradient_Energy_Low_Pass_Smoothing := 101;
         Expect_Bad (P, "RunParams.GradientEnergyLowPassSmoothing must be "
                        & "in 0 .. 100");
         P := Default;
         P.Band_Pass_Min_Frequency := 0.46;
         Expect_Bad (P, "RunParams.BandPassMinFrequency must not exceed "
                        & "BandPassMaxFrequency");
         P := Default;
         P.Abs_Diff_Distance_X := -1;
         Expect_Bad (P, "RunParams.AbsDiffDistanceX must be >= 0");
         P := Default;
         P.Mode := SH.Abs_Diff;
         P.Abs_Diff_Distance_X := 64;
         Expect_Bad (P, "RunParams.AbsDiffDistanceX must be less than the "
                        & "width of InputImage");
         P.Mode := SH.Gradient_Energy;
         Tool.Run_Params := P;
         Tool.Run;
         Check (Tool.Run_Status.Result = Accept_Result,
                "GradientEnergy ignores the distances");
      end;
      Tool.Run_Params := (others => <>);
      Tool.Region := Circle (-100.0, -100.0, 5.0);
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result and then Tool.Score = 0.0,
             "an empty region scores 0");
      Tool.Region := RH.Empty_Holder;
      declare
         Unallocated : Ks_Image_8_Grey;
      begin
         Tool.Input_Image := Unallocated;
         Tool.Run;
         Check (Tool.Run_Status.Result = Error
                and then Tool.Run_Status.Exception_Name = No_Pixels_Name
                and then Tool.Score = 0.0,
                "an unallocated input: Error, Score 0");
      end;
   end Test_Sharpness;

   ---------------------------------------------------------------------
   --  Kernels
   ---------------------------------------------------------------------

   procedure Test_Kernels is
      Image   : KI.Ks_Image_8_Grey;
      Region  : KR.Ks_Pixel_Region;
      Result  : KH.Ks_Histogram_Result;
      Output  : KI.Ks_Image_8_Grey;
      M, A, F : KI.Ks_Image_8_Grey;
      Score   : Long_Float;
      Status  : K.Ks_Status;
      NaN     : constant Real := Zero / Zero;
   begin
      Section ("Kernels: null handles");
      KH.Execute (null, null, KH.Auto_Params, Result, Status);
      Check (Status.Failure = K.Failure_Image_No_Pixels
             and then Message_Of (Status) = "InputImage has no pixels"
             and then Result = null,
             "histogram: a null image has no pixels");
      KI.Create (10, 8, 42, Image, Status);
      KH.Execute (Image, null, KH.Auto_Params, Result, Status);
      declare
         S : KH.Ks_Histogram_Statistics;
      begin
         KH.Get_Statistics (Result, S, Status);
         Check (K.Succeeded (Status) and then S.Num_Samples = 0
                and then S.Num_Bins = 256 and then S.Mean = 0.0,
                "histogram: a null region has no samples");
      end;
      KH.Destroy (Result, Status);
      KR.Whole_Image (10, 8, Region, Status);
      KH.Execute (Image, Region, (KH.Bin_Mode_Uniform, 4), Result, Status);
      declare
         S     : KH.Ks_Histogram_Statistics;
         Count : K.Int32;
         Level : K.Int32;
      begin
         KH.Get_Statistics (Result, S, Status);
         Check (K.Succeeded (Status) and then S.Num_Samples = 80
                and then S.Minimum = 42 and then S.Maximum = 42
                and then S.Mean = 42.0 and then S.Variance = 0.0
                and then S.Num_Bins = 4,
                "histogram: a flat image");
         KH.Get_Bin (Result, 0, Count, Status);
         Check (K.Succeeded (Status) and then Count = 80,
                "histogram: 42 falls into the first of 4 bins");
         KH.Get_Bin (Result, 4, Count, Status);
         Check (Status.Failure = K.Failure_Index_Out_Of_Range
                and then Message_Of (Status)
                           = "GetHistogram: index 4 is outside 0 .. 3"
                and then Count = 0,
                "histogram: a bin index beyond the bins");
         KH.Get_Bin (Result, -1, Count, Status);
         Check (Status.Failure = K.Failure_Index_Out_Of_Range,
                "histogram: a negative bin index");
         KH.Inverse_Cumulative_Grey_Level (Result, -1, Level, Status);
         Check (Status.Failure = K.Failure_Bad_Parameter
                and then Message_Of (Status)
                           = "GetInverseCumulativeGreyLevel: percent must be "
                             & "in 0 .. 100",
                "histogram: percent -1");
      end;
      KH.Destroy (Result, Status);
      KH.Destroy (Result, Status);
      Check (K.Succeeded (Status) and then Result = null,
             "histogram: destroying null does nothing");
      declare
         S     : KH.Ks_Histogram_Statistics;
         Count : K.Int32;
      begin
         KH.Get_Statistics (null, S, Status);
         Check (Status.Failure = K.Failure_Other
                and then Message_Of (Status)
                           = "Result: the histogram tool has no result",
                "histogram: the accessors of a null result");
         KH.Get_Bin (null, 0, Count, Status);
         Check (Status.Failure = K.Failure_Other, "histogram: bin of null");
      end;
      KH.Execute (Image, Region, (5, 10), Result, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter and then Result = null,
             "histogram: a bad bin mode code");

      KP.Execute (null, Region, (Map => KP.Identity_Map), Output, Status);
      Check (Status.Failure = K.Failure_Image_No_Pixels and then Output = null,
             "pixel map: a null image");
      KP.Execute (Image, null, (Map => [others => 9]), Output, Status);
      declare
         V  : KI.Grey_8;
         St : K.Ks_Status;
      begin
         KI.Get_Pixel (Output, 3, 3, V, St);
         Check (K.Succeeded (Status) and then V = 42,
                "pixel map: a null region copies the image");
      end;
      KI.Destroy (Output, Status);

      KE.Execute (null, Region, (others => <>), M, A, F, Status);
      Check (Status.Failure = K.Failure_Image_No_Pixels
             and then M = null and then A = null and then F = null,
             "Sobel: a null image");
      KE.Execute (Image, Region, (Magnitude_Scale => NaN, others => <>),
                  M, A, F, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then Message_Of (Status)
                        = "RunParams.MagnitudeScale must be in 0 .. 50"
             and then M = null,
             "Sobel: a NaN magnitude scale");
      KE.Execute (Image, null, (others => <>), M, A, F, Status);
      Check (K.Succeeded (Status) and then M /= null and then A /= null
             and then F /= null,
             "Sobel: a null region gives three images");
      KI.Destroy (M, Status);
      KI.Destroy (A, Status);
      KI.Destroy (F, Status);

      KS.Execute (null, Region, (others => <>), Score, Status);
      Check (Status.Failure = K.Failure_Image_No_Pixels and then Score = 0.0,
             "sharpness: a null image");
      KS.Execute (Image, Region,
                  (Auto_Correlation_Noise_Level => NaN, others => <>),
                  Score, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then Message_Of (Status)
                        = "RunParams.AutoCorrelationNoiseLevel must be in "
                          & "0 .. 255",
             "sharpness: a NaN noise level");
      KS.Execute (Image, Region,
                  (Band_Pass_Max_Frequency => NaN, others => <>),
                  Score, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter,
             "sharpness: a NaN frequency");
      KS.Execute (Image, null, (others => <>), Score, Status);
      Check (K.Succeeded (Status) and then Score = 0.0,
             "sharpness: a null region scores 0");

      Section ("Kernels: run parameter defaults");
      declare
         H  : KH.Ks_Histogram := (0, 0);
         P  : KP.Ks_IP_One_Image_Pixel_Map := (Map => [others => 1]);
         E  : KE.Ks_Sobel_Edge := (Magnitude_Scale => 9.0, others => 0);
         S  : KS.Ks_Image_Sharpness := (Mode => 0, others => <>);
      begin
         KH.Run_Params_Default (H);
         KP.Run_Params_Default (P);
         KE.Run_Params_Default (E);
         KS.Run_Params_Default (S);
         Check (H = KH.Auto_Params and then P.Map = KP.Identity_Map
                and then E = KE.Ks_Sobel_Edge'(others => <>)
                and then S = KS.Ks_Image_Sharpness'(others => <>),
                "the default procedures give the record defaults");
         Check (KH.Ks_Histogram'Size = 64
                and then KH.Ks_Histogram_Statistics'Size = 48 * 8
                and then KP.Ks_IP_One_Image_Pixel_Map'Size = 256 * 8
                and then KE.Ks_Sobel_Edge'Size = 40 * 8
                and then KS.Ks_Image_Sharpness'Size = 40 * 8,
                "the C layouts");
      end;
      KR.Destroy (Region, Status);
      KI.Destroy (Image, Status);
   end Test_Kernels;

   ---------------------------------------------------------------------
   --  Timing
   ---------------------------------------------------------------------

   procedure Test_Timing is
      Image   : constant Ks_Image_8_Grey := Random_Image (640, 480, 5);
      Region  : constant RH.Holder := Circle (320.0, 240.0, 200.0);
      Hist    : IH.Ks_Histogram_Tool;
      Map     : IP.Ks_Pixel_Map_Tool;
      Sobel   : IE.Ks_Sobel_Edge_Tool;
      Sharp   : SH.Ks_Image_Sharpness_Tool;

      procedure Report (Name : String; Tool : Ks_Tool'Class) is
      begin
         Ada.Text_IO.Put_Line
           ("  640 x 480 " & Name & ":"
            & Integer'Image (Integer (Tool.Run_Status.Processing_Time))
            & " ms");
         Check (Tool.Run_Status.Result = Accept_Result
                and then Tool.Run_Status.Processing_Time < 1000.0,
                Name & " runs on 640 x 480 in well under a second");
      end Report;
   begin
      Section ("Timing (640 x 480, whole image and a circle)");
      Hist.Input_Image := Image;
      Hist.Run;
      Report ("histogram", Hist);
      Hist.Region := Region;
      Hist.Run;
      Report ("histogram in a circle", Hist);
      Map.Input_Image := Image;
      Map.Run;
      Report ("pixel map", Map);
      Sobel.Input_Image := Image;
      Sobel.Run;
      Report ("Sobel edge", Sobel);
      Sobel.Run_Params.Post_Process_Mode := IE.Peak_Detect;
      Sobel.Run;
      Report ("Sobel edge, peak detection", Sobel);
      Sobel.Run_Params.Post_Process_Mode := IE.Hysteresis_Threshold;
      Sobel.Run;
      Report ("Sobel edge, hysteresis", Sobel);
      Sharp.Input_Image := Image;
      Sharp.Run;
      Report ("sharpness (gradient energy)", Sharp);
      Sharp.Run_Params.Gradient_Energy_Low_Pass_Smoothing := 2;
      Sharp.Run;
      Report ("sharpness (gradient energy, sigma 2)", Sharp);
      Sharp.Run_Params.Mode := SH.Abs_Diff;
      Sharp.Run;
      Report ("sharpness (absolute differences)", Sharp);
   end Test_Timing;

   procedure Run_All is
   begin
      Test_Histogram;
      Test_Pixel_Map;
      Test_Sobel_Edge;
      Test_Sharpness;
      Test_Kernels;
      Test_Timing;
   exception
      when E : others =>
         Fail ("unexpected exception "
               & Ada.Exceptions.Exception_Information (E));
   end Run_All;

   procedure Main is new AMV_Test_Support.Standalone (Run_All);

begin
   Main;
end Test_Image_Processing_Filters;
