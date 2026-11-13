--  Tests for the image processing geometry tools: the affine transform,
--  copy region, two-image (add, subtract, min/max), image convert and
--  polar unwrap tools (AMV.Image_Processing.Affine_Transform,
--  Copy_Region, IP_Two_Image, Image_Convert, Polar_Unwrap) through Run,
--  and their kernels called directly for what the Ada API cannot reach:
--  null handles, bad codes, non-finite values and limits.
--
--  Results are checked against direct computations: exact crops and
--  rotations by quarter turns, brute-force formulas on random images,
--  centroids of drawn blobs measured in the selected space of input and
--  output, rows of unwrapped rings, and round trips of the point mappings.
--  The timings of 640 x 480 runs are printed.

pragma Validity_Checks ("F");
--  The kernel tests build a NaN on purpose.

with Ada.Numerics;
with Ada.Numerics.Long_Elementary_Functions;
with Ada.Text_IO;
with Interfaces;

with AMV;                    use AMV;
with AMV.Image_Processing.Affine_Transform;
with AMV.Image_Processing.Copy_Region;
with AMV.Image_Processing.Image_Convert;
with AMV.Image_Processing.IP_Two_Image;
with AMV.Image_Processing.Polar_Unwrap;
with AMV.Images;             use AMV.Images;
with AMV.Images.Image_Holders;
with AMV.Kernels;
with AMV.Kernels.Affine_Transform;
with AMV.Kernels.Copy_Region;
with AMV.Kernels.Image_Convert;
with AMV.Kernels.Images;
with AMV.Kernels.IP_Two_Image;
with AMV.Kernels.Polar_Unwrap;
with AMV.Kernels.Regions;
with AMV.Kernels.Shapes;
with AMV.Kernels.Transforms;
with AMV.Regions;
with AMV.Shapes;             use AMV.Shapes;
with AMV.Shapes.Region_Holders;
with AMV.Tools;              use AMV.Tools;
with AMV.Transforms;
with AMV_Test_Images;
with AMV_Test_Support;       use AMV_Test_Support;

procedure Test_IP_Geometry is

   package EF renames Ada.Numerics.Long_Elementary_Functions;
   package RH renames AMV.Shapes.Region_Holders;
   package IHo renames AMV.Images.Image_Holders;
   package AF renames AMV.Image_Processing.Affine_Transform;
   package CR renames AMV.Image_Processing.Copy_Region;
   package TI renames AMV.Image_Processing.IP_Two_Image;
   package IC renames AMV.Image_Processing.Image_Convert;
   package PU renames AMV.Image_Processing.Polar_Unwrap;
   package K renames AMV.Kernels;
   package KA renames AMV.Kernels.Affine_Transform;
   package KC renames AMV.Kernels.Copy_Region;
   package K2 renames AMV.Kernels.IP_Two_Image;
   package KV renames AMV.Kernels.Image_Convert;
   package KP renames AMV.Kernels.Polar_Unwrap;
   package KI renames AMV.Kernels.Images;
   package KR renames AMV.Kernels.Regions;
   package KS renames AMV.Kernels.Shapes;
   package KT renames AMV.Kernels.Transforms;

   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_32;
   use type K.Int32;
   use type KI.Ks_Image_8_Grey;
   use type KA.Ks_Affine_Transform;
   use type KC.Ks_Copy_Region;
   use type KV.Ks_Image_Convert_Run_Params;
   use type KP.Ks_Polar_Unwrap;

   Pi : constant := Ada.Numerics.Pi;

   Zero : constant Real := Real'Value ("0.0");
   --  Read at run time, so that Zero / Zero is not folded.

   No_Pixels_Name : constant String := "AMV.KS_IMAGE_NO_PIXELS_EXCEPTION";
   Bad_Name       : constant String := "AMV.KS_BAD_PARAMETER_EXCEPTION";
   Space_Name     : constant String :=
     "AMV.KS_IMAGE_BAD_SELECTED_SPACE_NAME_EXCEPTION";

   Unallocated : Ks_Image_8_Grey;
   No_Colour   : Ks_Image_24_Planar_Color;
   --  Images without pixels (the default).

   function Message_Of (Status : K.Ks_Status) return String is
     (String (Status.Message (1 .. Natural (Status.Length))));

   ---------------------------------------------------------------------
   --  Helpers
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

   procedure Add_Fixture (Image : in out Ks_Image'Class);
   --  Adds the space "@\Fixture" (rotated by 0.3 rad and translated) and
   --  selects it.

   procedure Add_Fixture (Image : in out Ks_Image'Class) is
   begin
      Image.Coordinate_Space_Tree.Add_Space
        ("@", "Fixture", AMV.Transforms.Create_Rigid (0.3, 12.0, 7.0));
      Image.Set_Selected_Space_Name ("@\Fixture");
   end Add_Fixture;

   procedure Map
     (Transform : AMV.Transforms.Ks_Transform_2D_Linear;
      X, Y      : Real;
      MX, MY    : out Real) renames AMV.Transforms.Map_Point;

   procedure Centroid
     (Image      : Ks_Image_8_Grey;
      Background : Real;
      CX, CY     : out Real);
   --  The centroid of the pixels weighted by their value above Background.

   procedure Centroid
     (Image      : Ks_Image_8_Grey;
      Background : Real;
      CX, CY     : out Real)
   is
      Sum, SX, SY : Real := 0.0;
   begin
      for Y in 0 .. Image.Height - 1 loop
         for X in 0 .. Image.Width - 1 loop
            declare
               W : constant Real :=
                 Real'Max (Real (Image.Get_Pixel (X, Y)) - Background, 0.0);
            begin
               Sum := Sum + W;
               SX := SX + W * Real (X);
               SY := SY + W * Real (Y);
            end;
         end loop;
      end loop;
      CX := SX / Sum;
      CY := SY / Sum;
   end Centroid;

   procedure Check_Accept (Tool : Ks_Tool'Class; What : String);

   procedure Check_Accept (Tool : Ks_Tool'Class; What : String) is
   begin
      Check (Tool.Run_Status.Result = Accept_Result,
             What & ": Accept_Result (" & Tool.Run_Status.Message & ")");
   end Check_Accept;

   procedure Check_Error
     (Tool    : Ks_Tool'Class;
      Name    : String;
      Message : String;
      What    : String);
   --  The run failed with the exception Name and the message Message
   --  (any message when Message is empty).

   procedure Check_Error
     (Tool    : Ks_Tool'Class;
      Name    : String;
      Message : String;
      What    : String) is
   begin
      Check (Tool.Run_Status.Result = Error
             and then Tool.Run_Status.Exception_Name = Name
             and then (Message = ""
                       or else Tool.Run_Status.Message = Message),
             What & " (" & Tool.Run_Status.Exception_Name & ": "
             & Tool.Run_Status.Message & ")");
   end Check_Error;

   function Same_Transform
     (A, B      : AMV.Transforms.Ks_Transform_2D_Linear;
      Tolerance : Real := 1.0E-9) return Boolean;

   function Same_Transform
     (A, B      : AMV.Transforms.Ks_Transform_2D_Linear;
      Tolerance : Real := 1.0E-9) return Boolean
   is
      A1, B1, C1, D1, X1, Y1 : Real;
      A2, B2, C2, D2, X2, Y2 : Real;
   begin
      A.Get_Matrix_Elements_Translation (A1, B1, C1, D1, X1, Y1);
      B.Get_Matrix_Elements_Translation (A2, B2, C2, D2, X2, Y2);
      return abs (A1 - A2) <= Tolerance and then abs (B1 - B2) <= Tolerance
        and then abs (C1 - C2) <= Tolerance and then abs (D1 - D2) <= Tolerance
        and then abs (X1 - X2) <= Tolerance
        and then abs (Y1 - Y2) <= Tolerance;
   end Same_Transform;

   function Rectangle_Affine
     (CX, CY, SX, SY, Rotation, Skew : Real;
      Space                          : String := ".")
      return Ks_Rectangle_Affine;

   function Rectangle_Affine
     (CX, CY, SX, SY, Rotation, Skew : Real;
      Space                          : String := ".")
      return Ks_Rectangle_Affine
   is
      R : Ks_Rectangle_Affine;
   begin
      R.Set_Center_Lengths_Rotation_Skew (CX, CY, SX, SY, Rotation, Skew);
      R.Set_Selected_Space_Name (Space);
      return R;
   end Rectangle_Affine;

   function Section
     (CX, CY, Radius, Start, Span, Scale : Real;
      Space                              : String := ".")
      return Ks_Circular_Annulus_Section;

   function Section
     (CX, CY, Radius, Start, Span, Scale : Real;
      Space                              : String := ".")
      return Ks_Circular_Annulus_Section
   is
      S : Ks_Circular_Annulus_Section;
   begin
      S.Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
        (CX, CY, Radius, Start, Span, Scale);
      S.Set_Selected_Space_Name (Space);
      return S;
   end Section;

   ---------------------------------------------------------------------
   --  Affine transform
   ---------------------------------------------------------------------

   procedure Test_Affine_Exact is
      Image : constant Ks_Image_8_Grey := Random_Image (40, 30, 11);
      Tool  : AF.Ks_Affine_Transform_Tool;
      Same  : Boolean;
   begin
      AMV_Test_Support.Section ("Affine transform: exact crops and turns");
      Check (Tool.Run_Params = (others => <>)
             and then Tool.Run_Params.Scaling_X = 1.0
             and then Tool.Run_Params.Sampling_Mode = AF.Bilinear_Accurate
             and then Tool.Run_Params.Clip_Mode = AF.Zeroes
             and then Tool.Run_Params.Clip_Fill_Value = 0,
             "the defaults are VisionPro's");
      Tool.Input_Image := Image;
      --  Corner origin at (4.5, 5.5): output pixel (I, J) samples the
      --  centre of input pixel (5 + I, 6 + J).
      Tool.Region := Rectangle_Affine (14.5, 11.5, 20.0, 12.0, 0.0, 0.0);
      for Mode in 1 .. 2 loop
         Tool.Run_Params.Sampling_Mode :=
           (if Mode = 1 then AF.Nearest_Neighbor else AF.Bilinear_Accurate);
         Tool.Run;
         Check_Accept (Tool, "axis-aligned crop");
         Check (Tool.Output_Image.Width = 20
                and then Tool.Output_Image.Height = 12,
                "the output size is the side lengths in pixels");
         Same := True;
         for J in 0 .. 11 loop
            for I in 0 .. 19 loop
               Same := Same
                 and then Tool.Output_Image.Get_Pixel (I, J)
                            = Image.Get_Pixel (5 + I, 6 + J);
            end loop;
         end loop;
         Check (Same, "an axis-aligned region gives the exact crop"
                & (if Mode = 1 then " (nearest)" else " (bilinear)"));
      end loop;
      Check (Same_Transform
               (Tool.Output_Image.Get_Transform ("#", "@"),
                AMV.Transforms.Create (1.0, 0.0, 0.0, 1.0, -5.0, -6.0)),
             "the output's pixel space is shifted by the crop's corner");
      Check (not Tool.Output_Image_Mask.Allocated,
             "no mask unless asked for");

      --  Scalings: 2 along x (each input column twice) and 1/3 along y
      --  (every third row, at the centres of rows 7, 10, 13, 16).
      Tool.Run_Params.Sampling_Mode := AF.Nearest_Neighbor;
      Tool.Run_Params.Scaling_X := 2.0;
      Tool.Run_Params.Scaling_Y := 1.0 / 3.0;
      Tool.Run;
      Check_Accept (Tool, "scaled crop");
      Check (Tool.Output_Image.Width = 40
             and then Tool.Output_Image.Height = 4,
             "the output size follows the scalings (40 x 4)");
      Same := Tool.Output_Image.Width = 40;
      if Same then
         for J in 0 .. 3 loop
            for I in 0 .. 39 loop
               Same := Same
                 and then Tool.Output_Image.Get_Pixel (I, J)
                            = Image.Get_Pixel (5 + I / 2, 7 + 3 * J);
            end loop;
         end loop;
      end if;
      Check (Same, "nearest-neighbour scaling repeats and skips pixels");

      --  A quarter turn: side X runs down the image, side Y to the left.
      --  Corner origin (24.5, 10.5): output (I, J) samples (24 - J, 11 + I).
      Tool.Run_Params := (others => <>);
      Tool.Region :=
        Rectangle_Affine (20.5, 15.5, 10.0, 8.0, Pi / 2.0, 0.0);
      for Mode in 1 .. 2 loop
         Tool.Run_Params.Sampling_Mode :=
           (if Mode = 1 then AF.Nearest_Neighbor
            else AF.Bilinear_Interpolation);
         Tool.Run;
         Check_Accept (Tool, "quarter turn");
         Same := Tool.Output_Image.Width = 10
           and then Tool.Output_Image.Height = 8;
         if Same then
            for J in 0 .. 7 loop
               for I in 0 .. 9 loop
                  Same := Same
                    and then Tool.Output_Image.Get_Pixel (I, J)
                               = Image.Get_Pixel (24 - J, 11 + I);
               end loop;
            end loop;
         end if;
         Check (Same, "a region turned by Pi / 2 gives the turned crop"
                & (if Mode = 1 then " (nearest)" else " (bilinear)"));
      end loop;
   end Test_Affine_Exact;

   procedure Test_Affine_Measurement is
      Image : Ks_Image_8_Grey := AMV_Test_Images.Blank (200, 160, 20);
      Tool  : AF.Ks_Affine_Transform_Tool;
      IX, IY, OX, OY, SX, SY, TX, TY : Real;
   begin
      AMV_Test_Support.Section
        ("Affine transform: a measurement in the selected space");
      AMV_Test_Images.Draw_Circle (Image, 101.3, 78.6, 9.0, 220);
      Image.Set_Pixel_From_Root_Transform
        (AMV.Transforms.Create_Similarity (1.25, 0.1, -3.0, 4.0));
      Add_Fixture (Image);
      Centroid (Image, 20.0, IX, IY);
      Map (Image.Get_Transform (".", "#"), IX, IY, SX, SY);
      Tool.Input_Image := Image;

      --  Rotated, skewed and scaled regions, in pixel space and in the
      --  selected space.
      for Case_Number in 1 .. 3 loop
         case Case_Number is
            when 1 =>
               Tool.Region :=
                 Rectangle_Affine (100.0, 80.0, 50.0, 40.0, 0.4, 0.0, "#");
            when 2 =>
               Tool.Region :=
                 Rectangle_Affine (99.0, 81.0, 50.0, 44.0, -0.7, 0.25, "#");
               Tool.Run_Params.Scaling_X := 1.3;
               Tool.Run_Params.Scaling_Y := 0.8;
            when 3 =>
               --  The region of case 2 expressed in the fixture space.
               Tool.Region :=
                 Ks_Rectangle_Affine
                   (Rectangle_Affine
                      (99.0, 81.0, 50.0, 44.0, -0.7, 0.25, "#").Map
                      (Image.Get_Transform (".", "#")));
               Tool.Region.Set_Selected_Space_Name (".");
         end case;
         Tool.Run;
         Check_Accept (Tool, "drawn disc" & Integer'Image (Case_Number));
         if Tool.Output_Image.Allocated then
            Centroid (Tool.Output_Image, 20.0, OX, OY);
            Map (Tool.Output_Image.Get_Transform (".", "#"), OX, OY, TX, TY);
            Ada.Text_IO.Put_Line
              ("  affine case" & Integer'Image (Case_Number)
               & ": centre moved by" & Real'Image (EF.Sqrt
                 ((TX - SX) ** 2 + (TY - SY) ** 2)) & " in ""."""
               & " (output" & Integer'Image (Tool.Output_Image.Width)
               & " x" & Integer'Image (Tool.Output_Image.Height) & ")");
            Check_Near (TX, SX, 0.05,
                        "case" & Integer'Image (Case_Number)
                        & ": the disc's centre X in ""."" agrees");
            Check_Near (TY, SY, 0.05,
                        "case" & Integer'Image (Case_Number)
                        & ": the disc's centre Y in ""."" agrees");
            Check (Tool.Output_Image.Selected_Space_Name = "@\Fixture",
                   "the output keeps the selected space");
         end if;
      end loop;
      Check (Tool.Output_Image.Width = 65
             and then Tool.Output_Image.Height = 35,
             "the output size is round (scaling * side in pixels)"
             & Integer'Image (Tool.Output_Image.Width) & " x"
             & Integer'Image (Tool.Output_Image.Height));
   end Test_Affine_Measurement;

   procedure Test_Affine_Clipping is
      Image : constant Ks_Image_8_Grey := Random_Image (40, 30, 3);
      Tool  : AF.Ks_Affine_Transform_Tool;
      Good  : Boolean;
      Count : Natural;
   begin
      AMV_Test_Support.Section ("Affine transform: clipping and the mask");
      Tool.Input_Image := Image;
      --  Corner origin (-4.5, -4.5): output (I, J) samples (I - 4, J - 4),
      --  outside the image for I or J below 4.
      Tool.Region := Rectangle_Affine (5.5, 5.5, 20.0, 20.0, 0.0, 0.0);
      Tool.Run_Params.Sampling_Mode := AF.Nearest_Neighbor;
      Tool.Create_Output_Image_Mask := True;
      for Mode in 1 .. 2 loop
         Tool.Run_Params.Clip_Mode := (if Mode = 1 then AF.Zeroes else AF.Fill);
         Tool.Run_Params.Clip_Fill_Value := 77;
         Tool.Run;
         Check_Accept (Tool, "a region partly outside the image");
         Good := Tool.Output_Image.Width = 20
           and then Tool.Output_Image_Mask.Width = 20
           and then Tool.Output_Image_Mask.Height = 20;
         Count := 0;
         if Good then
            for J in 0 .. 19 loop
               for I in 0 .. 19 loop
                  if I < 4 or else J < 4 then
                     Good := Good
                       and then Tool.Output_Image.Get_Pixel (I, J)
                                  = (if Mode = 1 then 0 else 77)
                       and then Tool.Output_Image_Mask.Get_Pixel (I, J) = 0;
                  else
                     Good := Good
                       and then Tool.Output_Image.Get_Pixel (I, J)
                                  = Image.Get_Pixel (I - 4, J - 4)
                       and then Tool.Output_Image_Mask.Get_Pixel (I, J)
                                  = 255;
                     Count := Count + 1;
                  end if;
               end loop;
            end loop;
         end if;
         Check (Good and then Count = 256,
                (if Mode = 1 then "Zeroes" else "Fill")
                & ": clipped pixels get the fill value, the mask is 0 there");
      end loop;
      Check (Same_Transform (Tool.Output_Image_Mask.Get_Transform ("#", "@"),
                             Tool.Output_Image.Get_Transform ("#", "@")),
             "the mask has the output's coordinate spaces");
      Tool.Run_Params.Clip_Mode := AF.Error;
      Tool.Run;
      Check_Error (Tool, Bad_Name,
                   "Region lies partly outside InputImage "
                   & "(RunParams.ClipMode is Error)",
                   "ClipMode Error fails on a clipped region");
      Check (not Tool.Output_Image.Allocated
             and then not Tool.Output_Image_Mask.Allocated,
             "a failed run leaves no output");
      Tool.Region := Rectangle_Affine (20.0, 15.0, 30.0, 20.0, 0.2, 0.0);
      Tool.Run;
      Check_Accept (Tool, "ClipMode Error accepts a region inside the image");
   end Test_Affine_Clipping;

   procedure Test_Affine_Errors is
      Tool : AF.Ks_Affine_Transform_Tool;
   begin
      AMV_Test_Support.Section ("Affine transform: errors");
      Tool.Run;
      Check_Error (Tool, No_Pixels_Name, "InputImage has no pixels",
                   "an unallocated input");
      Tool.Input_Image := Random_Image (30, 20, 5);
      Tool.Region := Rectangle_Affine (10.0, 10.0, 8.0, 8.0, 0.0, 0.0,
                                       "@\Nowhere");
      Tool.Run;
      Check_Error (Tool, Space_Name, "", "a region in an unknown space");
      Tool.Region := Rectangle_Affine (10.0, 10.0, 8.0, 8.0, 0.0, 0.0);
      Tool.Run_Params.Scaling_X := 0.0;
      Tool.Run;
      Check_Error (Tool, Bad_Name,
                   "RunParams.ScalingX must be in 0.001 .. 1000",
                   "ScalingX 0");
      Tool.Run_Params := (others => <>);
      Tool.Run_Params.Scaling_Y := 1001.0;
      Tool.Run;
      Check_Error (Tool, Bad_Name,
                   "RunParams.ScalingY must be in 0.001 .. 1000",
                   "ScalingY above 1000");
      Tool.Run_Params := (others => <>);
      Tool.Run_Params.Sampling_Mode := AF.High_Precision;
      Tool.Run;
      Check_Error (Tool, Bad_Name,
                   "RunParams.SamplingMode HighPrecision is not implemented",
                   "HighPrecision is not implemented");
      Tool.Run_Params := (others => <>);
      Tool.Run_Params.Clip_Fill_Value := 256;
      Tool.Run;
      Check_Error (Tool, Bad_Name,
                   "RunParams.ClipFillValue must be in 0 .. 255",
                   "ClipFillValue 256");
      Tool.Run_Params := (others => <>);
      Tool.Run_Params.Clip_Mode := 3;
      Tool.Run;
      Check_Error (Tool, Bad_Name, "", "ClipMode 3");
      Tool.Run_Params := (others => <>);
      Tool.Region := Rectangle_Affine (10.0, 10.0, 0.4, 8.0, 0.0, 0.0);
      Tool.Run;
      Check_Error (Tool, Bad_Name,
                   "the output image would be less than 1 pixel wide "
                   & "(RunParams.ScalingX times Region.SideXLength in "
                   & "pixels)",
                   "an output below 1 pixel");
      Tool.Region := Rectangle_Affine (10.0, 10.0, 8.0, 40_000.0, 0.0, 0.0);
      Tool.Run;
      Check_Error (Tool, Bad_Name,
                   "the output image would be more than 32767 pixels high "
                   & "(RunParams.ScalingY times Region.SideYLength in "
                   & "pixels)",
                   "an output above 32767 pixels");
      Check (not Tool.Output_Image.Allocated,
             "Reset_Results leaves no output after a failed run");
   end Test_Affine_Errors;

   ---------------------------------------------------------------------
   --  Copy region
   ---------------------------------------------------------------------

   procedure Test_Copy_Region is
      Image : Ks_Image_8_Grey := Random_Image (40, 30, 7);
      Tool  : CR.Ks_Copy_Region_Tool;
      Good  : Boolean;
      R     : Ks_Rectangle;
      C     : Ks_Circle;
   begin
      AMV_Test_Support.Section ("Copy region");
      Check (Tool.Run_Params = (others => <>)
             and then Tool.Run_Params.Fill_Bounding_Box = 1
             and then Tool.Run_Params.Fill_Bounding_Box_Value = 0
             and then Tool.Run_Params.Fill_Region = 0
             and then Tool.Run_Params.Fill_Region_Value = 255
             and then Tool.Run_Params.Region_Mode
                        = CR.Pixel_Aligned_Bounding_Box_Adjust_Mask,
             "the defaults are VisionPro's");
      Image.Set_Pixel_From_Root_Transform
        (AMV.Transforms.Create_Similarity (2.0, 0.3, 3.0, -1.0));
      Tool.Input_Image := Image;

      --  The whole image.
      Tool.Run;
      Check_Accept (Tool, "the whole image");
      Good := Tool.Output_Image.Width = 40 and then Tool.Output_Image.Height = 30;
      if Good then
         Good := Tool.Output_Image.To_Matrix = Image.To_Matrix;
      end if;
      Check (Good, "an empty Region copies the whole image");
      Check (Same_Transform (Tool.Output_Image.Pixel_From_Root_Transform,
                             Image.Pixel_From_Root_Transform),
             "the whole image keeps the pixel-from-root transform");

      --  A rectangle: pixel centres 5 .. 14 by 4 .. 10.
      R.Set_XY_Width_Height (4.6, 3.2, 10.0, 7.0);
      R.Set_Selected_Space_Name ("#");
      Tool.Region := RH.To_Holder (R);
      Tool.Run;
      Check_Accept (Tool, "a rectangle");
      Good := Tool.Output_Image.Width = 10 and then Tool.Output_Image.Height = 7;
      if Good then
         for J in 0 .. 6 loop
            for I in 0 .. 9 loop
               Good := Good
                 and then Tool.Output_Image.Get_Pixel (I, J)
                            = Image.Get_Pixel (5 + I, 4 + J);
            end loop;
         end loop;
      end if;
      Check (Good, "a rectangle gives the exact crop");
      declare
         X0, Y0, X1, Y1 : Real;
      begin
         --  A root point lies 5 and 4 pixels further left and up in the
         --  output.
         Map (Image.Get_Transform ("#", "@"), 3.7, -2.9, X0, Y0);
         Map (Tool.Output_Image.Get_Transform ("#", "@"), 3.7, -2.9, X1, Y1);
         Check_Near (X1, X0 - 5.0, 1.0E-9, "crop coordinates: X");
         Check_Near (Y1, Y0 - 4.0, 1.0E-9, "crop coordinates: Y");
      end;

      --  A circle with the fills.
      C.Set_Center_Radius (20.0, 15.0, 6.3);
      C.Set_Selected_Space_Name ("#");
      Tool.Region := RH.To_Holder (C);
      declare
         Pixels : constant AMV.Regions.Pixel_Region :=
           AMV.Regions.Rasterize (Image, C);
         X0     : constant Natural := AMV.Regions.X_Min (Pixels);
         Y0     : constant Natural := AMV.Regions.Y_Min (Pixels);
         W      : constant Natural := AMV.Regions.Width (Pixels);
         H      : constant Natural := AMV.Regions.Height (Pixels);
         Inside : Natural := 0;
         Holes  : Natural := 0;
      begin
         for Case_Number in 1 .. 4 loop
            Tool.Run_Params := (others => <>);
            case Case_Number is
               when 1 => null;
               when 2 =>
                  CR.Set_Fill_Region (Tool.Run_Params, True);
                  Tool.Run_Params.Fill_Region_Value := 200;
                  Tool.Run_Params.Fill_Bounding_Box_Value := 9;
               when 3 =>
                  CR.Set_Fill_Bounding_Box (Tool.Run_Params, False);
               when 4 =>
                  Tool.Run_Params.Region_Mode := CR.Pixel_Aligned_Bounding_Box;
            end case;
            Tool.Run;
            Check_Accept (Tool, "a circle" & Integer'Image (Case_Number));
            Good := Tool.Output_Image.Width = W
              and then Tool.Output_Image.Height = H;
            Inside := 0;
            Holes := 0;
            if Good then
               for J in 0 .. H - 1 loop
                  for I in 0 .. W - 1 loop
                     declare
                        In_Region : constant Boolean :=
                          AMV.Regions.Contains (Pixels, X0 + I, Y0 + J);
                        Input     : constant Grey_8 :=
                          Image.Get_Pixel (X0 + I, Y0 + J);
                        Expected  : constant Grey_8 :=
                          (case Case_Number is
                              when 1 => (if In_Region then Input else 0),
                              when 2 => (if In_Region then 200 else 9),
                              when 3 | 4 => Input);
                     begin
                        Good := Good
                          and then Tool.Output_Image.Get_Pixel (I, J)
                                     = Expected;
                        if In_Region then
                           Inside := Inside + 1;
                        else
                           Holes := Holes + 1;
                        end if;
                     end;
                  end loop;
               end loop;
            end if;
            Check (Good and then Inside = AMV.Regions.Pixel_Count (Pixels)
                   and then Holes > 0,
                   "circle" & Integer'Image (Case_Number)
                   & ": region pixels copied (or filled), the others "
                   & "filled (or copied)");
         end loop;
      end;
   end Test_Copy_Region;

   procedure Test_Copy_Region_Spaces is
      Image : Ks_Image_8_Grey := AMV_Test_Images.Blank (80, 60, 0);
      Tool  : CR.Ks_Copy_Region_Tool;
      C     : Ks_Circle;
      IX, IY, OX, OY, SX, SY, TX, TY : Real;
   begin
      AMV_Test_Support.Section ("Copy region: the selected space");
      AMV_Test_Images.Draw_Circle (Image, 41.3, 27.8, 6.0, 180);
      Add_Fixture (Image);
      Centroid (Image, 0.0, IX, IY);
      Map (Image.Get_Transform (".", "#"), IX, IY, SX, SY);
      --  A circle around the disc, in the fixture space.
      Map (Image.Get_Transform (".", "#"), 41.0, 28.0, TX, TY);
      C.Set_Center_Radius (TX, TY, 10.3);
      Tool.Input_Image := Image;
      Tool.Region := RH.To_Holder (C);
      Tool.Run;
      Check_Accept (Tool, "a circle in the fixture space");
      Check (Tool.Output_Image.Width = 21 and then Tool.Output_Image.Height = 21,
             "the bounding box of the circle");
      Centroid (Tool.Output_Image, 0.0, OX, OY);
      Map (Tool.Output_Image.Get_Transform (".", "#"), OX, OY, TX, TY);
      Check_Near (TX, SX, 1.0E-9, "the disc's centre X in ""."" agrees");
      Check_Near (TY, SY, 1.0E-9, "the disc's centre Y in ""."" agrees");
      Check (Tool.Output_Image.Selected_Space_Name = "@\Fixture",
             "the output keeps the selected space");
   end Test_Copy_Region_Spaces;

   procedure Test_Copy_Region_Errors is
      Tool : CR.Ks_Copy_Region_Tool;
      C    : Ks_Circle;
   begin
      AMV_Test_Support.Section ("Copy region: errors");
      Tool.Run;
      Check_Error (Tool, No_Pixels_Name, "InputImage has no pixels",
                   "an unallocated input");
      Tool.Input_Image := Random_Image (20, 10, 1);
      C.Set_Center_Radius (-50.0, -50.0, 3.0);
      Tool.Region := RH.To_Holder (C);
      Tool.Run;
      Check_Error (Tool, Bad_Name, "Region covers no pixel of InputImage",
                   "a region outside the image");
      Tool.Region.Clear;
      Tool.Run_Params.Region_Mode := CR.Affine_Transform;
      Tool.Run;
      Check_Error (Tool, Bad_Name,
                   "RunParams.RegionMode AffineTransform is not implemented",
                   "RegionMode AffineTransform");
      Tool.Run_Params := (others => <>);
      Tool.Run_Params.Fill_Region_Value := 256;
      Tool.Run;
      Check_Error (Tool, Bad_Name,
                   "RunParams.FillRegionValue must be in 0 .. 255",
                   "FillRegionValue 256");
      Tool.Run_Params := (others => <>);
      Tool.Run_Params.Fill_Bounding_Box := 2;
      Tool.Run;
      Check_Error (Tool, Bad_Name, "RunParams.FillBoundingBox must be 0 or 1",
                   "FillBoundingBox 2");
      Check (not Tool.Output_Image.Allocated, "no output after a failed run");
   end Test_Copy_Region_Errors;

   ---------------------------------------------------------------------
   --  Two-image tools
   ---------------------------------------------------------------------

   procedure Test_Two_Image is
      A     : Ks_Image_8_Grey := Random_Image (23, 17, 21);
      B     : constant Ks_Image_8_Grey := Random_Image (23, 17, 22);
      Add   : TI.Ks_IP_Two_Image_Add_Tool;
      Sub   : TI.Ks_IP_Two_Image_Subtract_Tool;
      MM    : TI.Ks_IP_Two_Image_Min_Max_Tool;
      Good  : Boolean;

      function Add_Of (Mode : Integer; P, Q : Integer) return Integer is
        (case Mode is
            when 0 => Integer'Min (P + Q, 255),
            when 1 => (P + Q) mod 256,
            when others => (P + Q) / 2);

      function Sub_Of (Mode : Integer; P, Q : Integer) return Integer is
        (case Mode is
            when 0 => Integer'Max (P - Q, 0),
            when 1 => (P - Q) mod 256,
            when 2 => (P - Q + 256) / 2,
            when others => abs (P - Q));
   begin
      AMV_Test_Support.Section ("Two-image tools against brute force");
      Add_Fixture (A);
      Add.Input_Image_A := A;
      Add.Input_Image_B := B;
      Sub.Input_Image_A := A;
      Sub.Input_Image_B := B;
      MM.Input_Image_A := A;
      MM.Input_Image_B := B;
      Check (Add.Run_Params.Overflow_Mode = TI.Bounded
             and then Sub.Run_Params.Overflow_Mode = TI.Bounded
             and then MM.Run_Params.Operation = TI.Min,
             "the defaults are VisionPro's");
      for Mode in 0 .. 2 loop
         Add.Run_Params.Overflow_Mode := K.Int32 (Mode);
         Add.Run;
         Check_Accept (Add, "add");
         Good := Add.Output_Image.Width = 23 and then Add.Output_Image.Height = 17;
         if Good then
            for Y in 0 .. 16 loop
               for X in 0 .. 22 loop
                  Good := Good
                    and then Integer (Add.Output_Image.Get_Pixel (X, Y))
                               = Add_Of (Mode, Integer (A.Get_Pixel (X, Y)),
                                         Integer (B.Get_Pixel (X, Y)));
               end loop;
            end loop;
         end if;
         Check (Good, "add, overflow mode" & Integer'Image (Mode));
      end loop;
      Check (Add.Output_Image.Selected_Space_Name = "@\Fixture"
             and then Same_Transform
                        (Add.Output_Image.Get_Transform ("@\Fixture", "#"),
                         A.Get_Transform ("@\Fixture", "#")),
             "the output has InputImageA's coordinate spaces");
      for Mode in 0 .. 3 loop
         Sub.Run_Params.Overflow_Mode := K.Int32 (Mode);
         Sub.Run;
         Check_Accept (Sub, "subtract");
         Good := Sub.Output_Image.Width = 23;
         if Good then
            for Y in 0 .. 16 loop
               for X in 0 .. 22 loop
                  Good := Good
                    and then Integer (Sub.Output_Image.Get_Pixel (X, Y))
                               = Sub_Of (Mode, Integer (A.Get_Pixel (X, Y)),
                                         Integer (B.Get_Pixel (X, Y)));
               end loop;
            end loop;
         end if;
         Check (Good, "subtract, overflow mode" & Integer'Image (Mode));
      end loop;
      for Operation in 0 .. 1 loop
         MM.Run_Params.Operation := K.Int32 (Operation);
         MM.Run;
         Check_Accept (MM, "min/max");
         Good := MM.Output_Image.Width = 23;
         if Good then
            for Y in 0 .. 16 loop
               for X in 0 .. 22 loop
                  Good := Good
                    and then MM.Output_Image.Get_Pixel (X, Y)
                               = (if Operation = 0
                                  then Grey_8'Min (A.Get_Pixel (X, Y),
                                                   B.Get_Pixel (X, Y))
                                  else Grey_8'Max (A.Get_Pixel (X, Y),
                                                   B.Get_Pixel (X, Y)));
               end loop;
            end loop;
         end if;
         Check (Good, (if Operation = 0 then "Min" else "Max"));
      end loop;

      --  The same image twice.
      Add.Input_Image_B := A;
      Add.Run_Params.Overflow_Mode := TI.Shift;
      Add.Run;
      Check_Accept (Add, "the same image twice");
      Check (Add.Output_Image.To_Matrix = A.To_Matrix,
             "(A + A) / 2 = A");

      AMV_Test_Support.Section ("Two-image tools: errors");
      Add.Input_Image_B := Random_Image (22, 17, 3);
      Add.Run;
      Check_Error (Add, Bad_Name,
                   "InputImageB is 22 x 17 pixels but InputImageA is "
                   & "23 x 17",
                   "images of different sizes");
      Check (not Add.Output_Image.Allocated, "no output after a failed run");
      Sub.Input_Image_A := Unallocated;
      Sub.Run;
      Check_Error (Sub, No_Pixels_Name, "InputImageA has no pixels",
                   "an unallocated InputImageA");
      MM.Input_Image_B := Unallocated;
      MM.Run;
      Check_Error (MM, No_Pixels_Name, "InputImageB has no pixels",
                   "an unallocated InputImageB");
      Add.Input_Image_B := B;
      Add.Run_Params.Overflow_Mode := 3;
      Add.Run;
      Check_Error (Add, Bad_Name,
                   "RunParams.OverflowMode must be Bounded (0), Wrap (1) or "
                   & "Shift (2)",
                   "add: OverflowMode 3");
      MM.Input_Image_B := B;
      MM.Run_Params.Operation := 2;
      MM.Run;
      Check_Error (MM, Bad_Name, "RunParams.Operation must be Min (0) or "
                   & "Max (1)", "min/max: Operation 2");
   end Test_Two_Image;

   ---------------------------------------------------------------------
   --  Image convert
   ---------------------------------------------------------------------

   procedure Test_Image_Convert is
      Colour : Ks_Image_24_Planar_Color := Create (13, 11);
      State  : Interfaces.Unsigned_32 := 77;
      Tool   : IC.Ks_Image_Convert_Tool;
      Good   : Boolean;
      R, G, B : Grey_8;

      function Next return Grey_8 is
      begin
         State := State * 1_664_525 + 1_013_904_223;
         return Grey_8 (Interfaces.Shift_Right (State, 24));
      end Next;

      function Weighted (WR, WG, WB : Real; R, G, B : Grey_8) return Grey_8
      is
         V : constant Real := WR * Real (R) + WG * Real (G) + WB * Real (B);
      begin
         return (if V <= 0.0 then 0 elsif V >= 255.0 then 255
                 else Grey_8 (Integer (V)));
      end Weighted;
   begin
      AMV_Test_Support.Section ("Image convert");
      for Y in 0 .. 10 loop
         for X in 0 .. 12 loop
            declare
               PR : constant Grey_8 := Next;
               PG : constant Grey_8 := Next;
               PB : constant Grey_8 := Next;
            begin
               Colour.Set_Pixel (X, Y, PR, PG, PB);
            end;
         end loop;
      end loop;
      Colour.Set_Pixel (0, 0, 255, 0, 0);
      Colour.Set_Pixel (1, 0, 0, 255, 0);
      Colour.Set_Pixel (2, 0, 0, 0, 255);
      Colour.Set_Pixel (3, 0, 255, 255, 255);
      Add_Fixture (Colour);
      Check (Tool.Run_Params = (others => <>)
             and then Tool.Run_Params.Run_Mode = IC.Intensity
             and then Tool.Run_Params.Intensity_From_Weighted_RGB_Red_Weight
                        = 0.299,
             "the defaults");
      Tool.Input_Image := IHo.To_Holder (Colour);
      Tool.Run;
      Check_Accept (Tool, "colour intensity");
      Good := Tool.Output_Image.Width = 13 and then Tool.Output_Image.Height = 11;
      if Good then
         for Y in 0 .. 10 loop
            for X in 0 .. 12 loop
               Colour.Get_Pixel (X, Y, R, G, B);
               Good := Good
                 and then Integer (Tool.Output_Image.Get_Pixel (X, Y))
                            = (299 * Integer (R) + 587 * Integer (G)
                               + 114 * Integer (B) + 500) / 1000
                 and then abs (Real (Tool.Output_Image.Get_Pixel (X, Y))
                               - (0.299 * Real (R) + 0.587 * Real (G)
                                  + 0.114 * Real (B))) <= 0.5;
            end loop;
         end loop;
      end if;
      Check (Good, "intensity = round (0.299 R + 0.587 G + 0.114 B)");
      Check (Tool.Output_Image.Get_Pixel (0, 0) = 76
             and then Tool.Output_Image.Get_Pixel (1, 0) = 150
             and then Tool.Output_Image.Get_Pixel (2, 0) = 29
             and then Tool.Output_Image.Get_Pixel (3, 0) = 255,
             "pure red, green, blue and white");
      Check (Tool.Output_Image.Selected_Space_Name = "@\Fixture",
             "the output keeps the input's coordinate spaces");

      for Plane in 0 .. 2 loop
         Tool.Run_Params.Run_Mode := IC.Plane_0 + K.Int32 (Plane);
         Tool.Run;
         Check_Accept (Tool, "plane");
         Check (Tool.Output_Image.To_Matrix
                  = Colour.Get_Plane (Ks_Image_Plane_Constants'Val (Plane))
                      .To_Matrix,
                "Plane" & Integer'Image (Plane) & " is the plane");
      end loop;

      for Case_Number in 1 .. 2 loop
         Tool.Run_Params := (others => <>);
         Tool.Run_Params.Run_Mode := IC.Intensity_From_Weighted_RGB;
         if Case_Number = 2 then
            Tool.Run_Params.Intensity_From_Weighted_RGB_Red_Weight := -1.0;
            Tool.Run_Params.Intensity_From_Weighted_RGB_Green_Weight := 2.0;
            Tool.Run_Params.Intensity_From_Weighted_RGB_Blue_Weight := 0.5;
         end if;
         Tool.Run;
         Check_Accept (Tool, "weighted");
         Good := Tool.Output_Image.Width = 13;
         if Good then
            for Y in 0 .. 10 loop
               for X in 0 .. 12 loop
                  Colour.Get_Pixel (X, Y, R, G, B);
                  Good := Good
                    and then Tool.Output_Image.Get_Pixel (X, Y)
                               = Weighted
                                   (Tool.Run_Params
                                      .Intensity_From_Weighted_RGB_Red_Weight,
                                    Tool.Run_Params
                                      .Intensity_From_Weighted_RGB_Green_Weight,
                                    Tool.Run_Params
                                      .Intensity_From_Weighted_RGB_Blue_Weight,
                                    R, G, B);
               end loop;
            end loop;
         end if;
         Check (Good, "IntensityFromWeightedRGB, weights" &
                Integer'Image (Case_Number) & " (limited to 0 .. 255)");
      end loop;

      --  16-bit and 8-bit inputs.
      declare
         Deep : Ks_Image_16_Grey := Create (7, 5);
         Grey : constant Ks_Image_8_Grey := Random_Image (7, 5, 4);
      begin
         for Y in 0 .. 4 loop
            for X in 0 .. 6 loop
               Deep.Set_Pixel (X, Y, Grey_16 (X * 9000 + Y * 1234 + 7));
            end loop;
         end loop;
         Tool.Run_Params := (others => <>);
         Tool.Input_Image := IHo.To_Holder (Deep);
         Tool.Run;
         Check_Accept (Tool, "16-bit intensity");
         Good := Tool.Output_Image.Width = 7;
         if Good then
            for Y in 0 .. 4 loop
               for X in 0 .. 6 loop
                  Good := Good
                    and then Integer (Tool.Output_Image.Get_Pixel (X, Y))
                               = Integer (Deep.Get_Pixel (X, Y)) / 256;
               end loop;
            end loop;
         end if;
         Check (Good, "a 16-bit image gives its high byte");
         Tool.Input_Image := IHo.To_Holder (Grey);
         Tool.Run;
         Check_Accept (Tool, "8-bit intensity");
         Check (Tool.Output_Image.To_Matrix = Grey.To_Matrix
                and then not Tool.Output_Image.Shares_Pixels (Grey),
                "an 8-bit image is copied");
         Tool.Run_Params.Run_Mode := IC.Plane_0;
         Tool.Run;
         Check_Error (Tool, Bad_Name,
                      "RunParams.RunMode Plane0 needs a colour InputImage",
                      "Plane0 of a grey image");
      end;

      AMV_Test_Support.Section ("Image convert: errors");
      Tool.Run_Params := (others => <>);
      Tool.Input_Image.Clear;
      Tool.Run;
      Check_Error (Tool, No_Pixels_Name, "InputImage has no pixels",
                   "an empty holder");
      Tool.Input_Image :=
        IHo.To_Holder (No_Colour);
      Tool.Run;
      Check_Error (Tool, No_Pixels_Name, "InputImage has no pixels",
                   "an unallocated colour image");
      Tool.Input_Image := IHo.To_Holder (Colour);
      Tool.Run_Params.Run_Mode := IC.HSI;
      Tool.Run;
      Check_Error (Tool, Bad_Name, "RunParams.RunMode HSI is not implemented",
                   "HSI is not implemented");
      Tool.Run_Params.Run_Mode := 13;
      Tool.Run;
      Check_Error (Tool, Bad_Name,
                   "RunParams.RunMode must be a "
                   & "CogImageConvertRunModeConstants value (1 .. 12)",
                   "RunMode 13");
      Tool.Run_Params := (others => <>);
      Tool.Run_Params.Bayer_Type := 4;
      Tool.Run;
      Check_Error (Tool, Bad_Name, "RunParams.BayerType must be in 0 .. 3",
                   "BayerType 4");
      Check (not Tool.Output_Image.Allocated, "no output after a failed run");
   end Test_Image_Convert;

   ---------------------------------------------------------------------
   --  Polar unwrap
   ---------------------------------------------------------------------

   procedure Test_Polar_Rings is
      CX    : constant Real := 110.3;
      CY    : constant Real := 99.6;
      Image : Ks_Image_8_Grey := AMV_Test_Images.Blank (220, 200, 10);
      Tool  : PU.Ks_Polar_Unwrap_Tool;
      Worst : Real := 0.0;
      Mean  : Real := 0.0;
   begin
      AMV_Test_Support.Section ("Polar unwrap: concentric rings");
      Check (Tool.Run_Params = (others => <>)
             and then Tool.Run_Params.Scaling_X = 1.0
             and then Tool.Run_Params.Sampling_Mode
                        = PU.Bilinear_Interpolation,
             "the defaults are VisionPro's");
      AMV_Test_Images.Draw_Annulus (Image, CX, CY, 34.0, 36.0, 200);
      AMV_Test_Images.Draw_Annulus (Image, CX, CY, 44.0, 46.0, 200);
      Tool.Input_Image := Image;
      --  Radii 30 .. 54: row Y samples radius 30.5 + Y, so the rings at 35
      --  and 45 lie on rows 4.5 and 14.5.
      Tool.Region := Section (CX, CY, 30.0, 0.2, 2.0 * Pi, 1.8);
      Tool.Run;
      Check_Accept (Tool, "unwrapping two rings");
      Check (Tool.Output_Image.Width = 264
             and then Tool.Output_Image.Height = 24,
             "the size is the middle arc and the radial extent in pixels"
             & Integer'Image (Tool.Output_Image.Width) & " x"
             & Integer'Image (Tool.Output_Image.Height));
      if Tool.Output_Image.Height = 24 then
         for X in 0 .. Tool.Output_Image.Width - 1 loop
            for Ring in 0 .. 1 loop
               declare
                  Sum, SY : Real := 0.0;
               begin
                  for Y in Ring * 10 .. Ring * 10 + 9 loop
                     declare
                        W : constant Real :=
                          Real (Tool.Output_Image.Get_Pixel (X, Y)) - 10.0;
                     begin
                        Sum := Sum + W;
                        SY := SY + W * Real (Y);
                     end;
                  end loop;
                  Worst := Real'Max
                    (Worst, abs (SY / Sum - (4.5 + 10.0 * Real (Ring))));
                  Mean := Mean + (SY / Sum - (4.5 + 10.0 * Real (Ring)));
               end;
            end loop;
         end loop;
         Mean := Mean / Real (2 * Tool.Output_Image.Width);
         Ada.Text_IO.Put_Line
           ("  rings: largest row error" & Real'Image (Worst)
            & " px, mean" & Real'Image (Mean) & " px");
         --  A ring 2 pixels wide sampled once per pixel: the phase of the
         --  samples against the pixel grid moves each column's centroid by
         --  about a tenth of a pixel; the mean shows no bias.
         Check (Worst < 0.15, "every column has the rings at rows 4.5, 14.5");
         Check (abs Mean < 0.02, "the rows have no bias");
      end if;
      Check (Tool.Output_Image.Selected_Space_Name = "@"
             and then Tool.Output_Image.Get_Coordinate_Space_Tree.Space_Count
                        = 1
             and then Same_Transform
                        (Tool.Output_Image.Pixel_From_Root_Transform,
                         AMV.Transforms.Identity),
             "the output has a fresh coordinate space tree");
   end Test_Polar_Rings;

   procedure Test_Polar_Mapping is
      Image  : Ks_Image_8_Grey := Random_Image (220, 200, 9);
      Tool   : PU.Ks_Polar_Unwrap_Tool;
      Params : PU.Ks_Polar_Unwrap;
      Good   : Boolean;
      IX, IY, OX, OY, PX, PY : Real;
      Width, Height : Natural;
   begin
      AMV_Test_Support.Section ("Polar unwrap: point mappings");
      Tool.Input_Image := Image;
      for Case_Number in 1 .. 3 loop
         case Case_Number is
            when 1 =>
               Tool.Region := Section (100.0, 95.0, 40.0, 0.5, 1.5, 0.5);
            when 2 =>
               Tool.Region := Section (100.0, 95.0, 20.0, 1.0, -2.5, 3.0);
               Tool.Run_Params.Scaling_X := 0.7;
               Tool.Run_Params.Scaling_Y := 2.0;
            when 3 =>
               Add_Fixture (Image);
               Tool.Input_Image := Image;
               Map (Image.Get_Transform (".", "#"), 100.0, 95.0, PX, PY);
               Tool.Region := Section (PX, PY, 20.0, 1.0, -2.5, 3.0);
         end case;
         Tool.Run;
         Check_Accept (Tool, "mapping case" & Integer'Image (Case_Number));
         Width := Tool.Output_Image.Width;
         Height := Tool.Output_Image.Height;
         Good := Width > 0;
         for J in 0 .. 4 loop
            for I in 0 .. 4 loop
               exit when not Good;
               OX := Real (I) * Real (Width - 1) / 4.0;
               OY := Real (J) * Real (Height - 1) / 4.0;
               PU.Get_Input_Point_From_Output_Point
                 (Tool.Run_Params, Image, Tool.Region, OX, OY, IX, IY);
               --  Expected: the angle and radius of the output point.
               declare
                  R0     : constant Real := Tool.Region.Radius;
                  R1     : constant Real := R0 * Tool.Region.Radial_Scale;
                  Angle  : constant Real :=
                    Tool.Region.Angle_Start
                    + (OX + 0.5) / Real (Width) * Tool.Region.Angle_Span;
                  Radius : constant Real :=
                    R0 + (OY + 0.5) / Real (Height) * (R1 - R0);
                  EX     : constant Real :=
                    Tool.Region.Center_X + Radius * EF.Cos (Angle);
                  EY     : constant Real :=
                    Tool.Region.Center_Y + Radius * EF.Sin (Angle);
                  BX, BY : Real;
               begin
                  Good := Good and then abs (IX - EX) < 1.0E-9
                    and then abs (IY - EY) < 1.0E-9;
                  PU.Get_Output_Point_From_Input_Point
                    (Tool.Run_Params, Image, Tool.Region, IX, IY, BX, BY);
                  Good := Good and then abs (BX - OX) < 1.0E-8
                    and then abs (BY - OY) < 1.0E-8;
               end;
            end loop;
         end loop;
         Check (Good, "case" & Integer'Image (Case_Number)
                & ": output -> input -> output round trips");
      end loop;

      --  Nearest neighbour: every output pixel is the input pixel nearest
      --  to the point Get_Input_Point_From_Output_Point gives.
      Image := Random_Image (220, 200, 9);
      Tool.Input_Image := Image;
      Tool.Region := Section (100.0, 95.0, 30.0, 0.3, 4.0, 1.7);
      Tool.Run_Params := (others => <>);
      Tool.Run_Params.Sampling_Mode := PU.Nearest_Neighbor;
      Tool.Run;
      Check_Accept (Tool, "nearest neighbour");
      Good := Tool.Output_Image.Allocated;
      if Good then
         for J in 0 .. Tool.Output_Image.Height - 1 loop
            for I in 0 .. Tool.Output_Image.Width - 1 loop
               PU.Get_Input_Point_From_Output_Point
                 (Tool.Run_Params, Image, Tool.Region, Real (I), Real (J),
                  IX, IY);
               Good := Good
                 and then Tool.Output_Image.Get_Pixel (I, J)
                            = Image.Get_Pixel
                                (Natural (Real'Floor (IX + 0.5)),
                                 Natural (Real'Floor (IY + 0.5)));
            end loop;
         end loop;
      end if;
      Check (Good, "nearest-neighbour samples are input pixels");

      --  Several turns: the point of a revolution later lies half the
      --  width further right.
      Params := (others => <>);
      PU.Get_Input_Point_From_Output_Point
        (Params, Image, Section (100.0, 95.0, 30.0, 0.0, 4.0 * Pi, 1.5),
         10.0, 3.0, IX, IY);
      PU.Get_Output_Point_From_Input_Point
        (Params, Image, Section (100.0, 95.0, 30.0, 0.0, 4.0 * Pi, 1.5),
         IX, IY, OX, OY, Revolution => 1);
      PU.Get_Output_Point_From_Input_Point
        (Params, Image, Section (100.0, 95.0, 30.0, 0.0, 4.0 * Pi, 1.5),
         IX, IY, PX, PY);
      Check (abs (PX - 10.0) < 1.0E-8 and then abs (PY - 3.0) < 1.0E-8,
             "revolution 0 maps back");
      Check (abs (OX - PX - 0.5 * Real'Floor (4.0 * Pi * 37.5 + 0.5))
               < 1.0E-6,
             "revolution 1 lies half the width further");

      AMV_Test_Support.Section ("Polar unwrap: errors");
      declare
         procedure Centre is
         begin
            PU.Get_Output_Point_From_Input_Point
              (Params, Image, Section (100.0, 95.0, 30.0, 0.0, 1.0, 1.5),
               100.0, 95.0, OX, OY);
         end Centre;
         procedure Check_Centre is new Check_Raises_Exactly
           (Centre, Ks_Bad_Parameter_Exception'Identity);
         procedure Outside is
         begin
            PU.Get_Input_Point_From_Output_Point
              (Params, Image, Section (100.0, 95.0, 30.0, 0.0, 1.0, 1.5),
               -1.0, 0.0, IX, IY);
         end Outside;
         procedure Check_Outside is new Check_Raises_Exactly
           (Outside, Ks_Bad_Parameter_Exception'Identity);
      begin
         Check_Centre ("the centre has no output point");
         Check_Outside ("an output point outside the output image");
      end;
      Tool.Run_Params := (others => <>);
      Tool.Region := Section (100.0, 95.0, 120.0, 0.0, 1.0, 1.5);
      Tool.Run;
      Check_Error (Tool, Bad_Name, "Region lies partly outside InputImage",
                   "a section reaching outside the image");
      Check (not Tool.Output_Image.Allocated, "no output after a failed run");
      Tool.Region := Section (100.0, 95.0, 0.0, 0.0, 1.0, 1.5);
      Tool.Run;
      Check_Error (Tool, Bad_Name,
                   "Region.Radius must be > 0 and at most 4.0E150",
                   "Radius 0");
      Tool.Region := Section (100.0, 95.0, 30.0, 0.0, 1.0, 1.0);
      Tool.Run;
      Check_Error (Tool, Bad_Name,
                   "Region.RadialScale must be > 0, at most 1.0E150 and not 1",
                   "RadialScale 1");
      Tool.Region := Section (100.0, 95.0, 30.0, 0.0, 0.0, 1.5);
      Tool.Run;
      Check_Error (Tool, Bad_Name, "Region.AngleSpan must not be 0",
                   "AngleSpan 0");
      Tool.Region := Section (100.0, 95.0, 30.0, 0.0, 1.0, 1.5);
      Tool.Run_Params.Scaling_Y := 0.0;
      Tool.Run;
      Check_Error (Tool, Bad_Name,
                   "RunParams.ScalingY must be in 0.001 .. 1000",
                   "ScalingY 0");
      Tool.Run_Params := (others => <>);
      Tool.Run_Params.Sampling_Mode := 2;
      Tool.Run;
      Check_Error (Tool, Bad_Name, "", "SamplingMode 2");
      Tool.Run_Params := (others => <>);
      Tool.Input_Image := Unallocated;
      Tool.Run;
      Check_Error (Tool, No_Pixels_Name, "InputImage has no pixels",
                   "an unallocated input");
   end Test_Polar_Mapping;

   procedure Test_Polar_Spaces is
      Image : Ks_Image_8_Grey := AMV_Test_Images.Blank (220, 200, 10);
      One   : PU.Ks_Polar_Unwrap_Tool;
      Two   : PU.Ks_Polar_Unwrap_Tool;
      Worst : Integer := 0;
   begin
      AMV_Test_Support.Section ("Polar unwrap: the region's space");
      AMV_Test_Images.Draw_Circle (Image, 130.0, 90.0, 8.0, 200);
      AMV_Test_Images.Draw_Annulus (Image, 100.0, 95.0, 38.0, 41.0, 150);
      One.Input_Image := Image;
      One.Region := Section (100.0, 95.0, 25.0, 0.4, 3.0, 2.0, "#");
      One.Run;
      Check_Accept (One, "a section in pixel space");
      Add_Fixture (Image);
      Two.Input_Image := Image;
      Two.Region :=
        Ks_Circular_Annulus_Section
          (One.Region.Map (Image.Get_Transform (".", "#")));
      Two.Region.Set_Selected_Space_Name (".");
      Two.Run;
      Check_Accept (Two, "the same section in the fixture space");
      if One.Output_Image.Allocated and then Two.Output_Image.Allocated
        and then One.Output_Image.Width = Two.Output_Image.Width
        and then One.Output_Image.Height = Two.Output_Image.Height
      then
         for Y in 0 .. One.Output_Image.Height - 1 loop
            for X in 0 .. One.Output_Image.Width - 1 loop
               Worst := Integer'Max
                 (Worst, abs (Integer (One.Output_Image.Get_Pixel (X, Y))
                              - Integer (Two.Output_Image.Get_Pixel (X, Y))));
            end loop;
         end loop;
         Check (Worst <= 1, "both give the same image (within 1 grey level)");
      else
         Fail ("both give images of one size");
      end if;
   end Test_Polar_Spaces;

   ---------------------------------------------------------------------
   --  Kernels
   ---------------------------------------------------------------------

   procedure Test_Kernels is
      NaN      : constant Real := Zero / Zero;
      Image    : KI.Ks_Image_8_Grey;
      Region   : KR.Ks_Pixel_Region;
      Output   : KI.Ks_Image_8_Grey;
      Mask     : KI.Ks_Image_8_Grey;
      Root     : KT.Ks_Transform_2D_Linear;
      Identity : constant KT.Ks_Transform_2D_Linear := (others => <>);
      Rect     : constant KS.Ks_Rectangle_Affine :=
        (Center_X => 10.0, Center_Y => 8.0, Side_X_Length => 6.0,
         Side_Y_Length => 4.0, Rotation => 0.0, Skew => 0.0);
      Annulus  : constant KS.Ks_Circular_Annulus_Section :=
        (Center_X => 10.0, Center_Y => 8.0, Radius => 3.0,
         Angle_Start => 0.0, Angle_Span => 1.0, Radial_Scale => 2.0);
      X, Y     : Real;
      Status   : K.Ks_Status;
   begin
      AMV_Test_Support.Section ("Kernels: null handles, codes, NaN");
      KI.Create (20, 16, 50, Image, Status);

      --  Affine transform.
      KA.Execute (null, Rect, Identity, Identity, (others => <>), 0, Output,
                  Mask, Root, Status);
      Check (Status.Failure = K.Failure_Image_No_Pixels
             and then Message_Of (Status) = "InputImage has no pixels"
             and then Output = null and then Mask = null,
             "affine: a null image");
      KA.Execute (Image, Rect, Identity, Identity,
                  (Scaling_X => NaN, others => <>), 0, Output, Mask, Root,
                  Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then Message_Of (Status)
                        = "RunParams.ScalingX must be in 0.001 .. 1000"
             and then Output = null,
             "affine: a NaN scaling");
      KA.Execute (Image, (Rect with delta Center_X => NaN), Identity,
                  Identity, (others => <>), 0, Output, Mask, Root, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then Message_Of (Status)
                        = "Region.CenterX must be finite and within 1.0E150",
             "affine: a NaN region");
      KA.Execute (Image, Rect, (Identity with delta Translation_Y => NaN),
                  Identity, (others => <>), 0, Output, Mask, Root, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter,
             "affine: a NaN transform");
      KA.Execute (Image, Rect, Identity, Identity,
                  (Sampling_Mode => 0, others => <>), 0, Output, Mask, Root,
                  Status);
      Check (Status.Failure = K.Failure_Bad_Parameter,
             "affine: SamplingMode 0");
      KA.Execute (Image, Rect, Identity, Identity, (others => <>), 2, Output,
                  Mask, Root, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then Message_Of (Status)
                        = "CreateOutputImageMask must be 0 or 1",
             "affine: a mask flag of 2");
      KA.Execute (Image, Rect, Identity, Identity, (others => <>), 1, Output,
                  Mask, Root, Status);
      Check (K.Succeeded (Status) and then Output /= null and then Mask /= null,
             "affine: the kernel with a mask");
      KI.Destroy (Output, Status);
      KI.Destroy (Mask, Status);

      --  Copy region.
      KC.Execute (null, null, Identity, (others => <>), Output, Root, Status);
      Check (Status.Failure = K.Failure_Image_No_Pixels and then Output = null,
             "copy region: a null image");
      KC.Execute (Image, null, Identity, (others => <>), Output, Root,
                  Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then Message_Of (Status)
                        = "Region covers no pixel of InputImage",
             "copy region: the empty region");
      KR.Whole_Image (30, 16, Region, Status);
      KC.Execute (Image, Region, Identity, (others => <>), Output, Root,
                  Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then Message_Of (Status) = "Region does not lie in InputImage",
             "copy region: a region larger than the image");
      KR.Destroy (Region, Status);
      KR.Whole_Image (20, 16, Region, Status);
      KC.Execute (Image, Region, (Identity with delta A => NaN),
                  (others => <>), Output, Root, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter,
             "copy region: a NaN pixel-from-root transform");
      KC.Execute (Image, Region, Identity, (others => <>), Output, Root,
                  Status);
      Check (K.Succeeded (Status) and then Output /= null,
             "copy region: the whole image");
      KI.Destroy (Output, Status);
      KR.Destroy (Region, Status);

      --  Two images.
      K2.Add_Execute (null, Image, (others => <>), Output, Status);
      Check (Status.Failure = K.Failure_Image_No_Pixels
             and then Message_Of (Status) = "InputImageA has no pixels"
             and then Output = null,
             "two images: a null A");
      K2.Subtract_Execute (Image, null, (others => <>), Output, Status);
      Check (Status.Failure = K.Failure_Image_No_Pixels
             and then Message_Of (Status) = "InputImageB has no pixels",
             "two images: a null B");
      K2.Min_Max_Execute (Image, Image, (Operation => -1), Output, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter,
             "two images: Operation -1");

      --  Image convert.
      KV.Execute (null, null, null, null, null, (others => <>), Output,
                  Status);
      Check (Status.Failure = K.Failure_Image_No_Pixels
             and then Output = null,
             "convert: no image");
      KV.Execute (Image, null, Image, Image, Image, (others => <>), Output,
                  Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then Message_Of (Status)
                        = "InputImage must be one image: an 8-bit, a 16-bit "
                          & "or a colour image",
             "convert: two kinds of image");
      KV.Execute (null, null, Image, null, Image, (others => <>), Output,
                  Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then Message_Of (Status)
                        = "InputImage: Red, Green and Blue must be planes of "
                          & "the same size",
             "convert: a colour image without its green plane");
      KV.Execute (null, null, Image, Image, Image,
                  (Run_Mode => KV.Run_Mode_Intensity_From_Weighted_RGB,
                   Intensity_From_Weighted_RGB_Green_Weight => NaN,
                   others => <>),
                  Output, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then Message_Of (Status)
                        = "RunParams.IntensityFromWeightedRGBGreenWeight must "
                          & "be finite and within 1.0E150",
             "convert: a NaN weight");
      KV.Execute (null, null, Image, Image, Image,
                  (Run_Mode => KV.Run_Mode_Intensity_From_Weighted_RGB,
                   others => <>),
                  Output, Status);
      Check (K.Succeeded (Status) and then Output /= null,
             "convert: one image given as all three planes");
      KI.Destroy (Output, Status);

      --  Polar unwrap.
      KP.Execute (null, Annulus, Identity, (others => <>), Output, Status);
      Check (Status.Failure = K.Failure_Image_No_Pixels and then Output = null,
             "polar unwrap: a null image");
      KP.Execute (Image, (Annulus with delta Radius => NaN), Identity,
                  (others => <>), Output, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then Message_Of (Status)
                        = "Region.Radius must be > 0 and at most 4.0E150",
             "polar unwrap: a NaN radius");
      KP.Execute (Image, Annulus, Identity, (Scaling_X => 40_000.0,
                                             others => <>),
                  Output, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter,
             "polar unwrap: ScalingX 40000");
      KP.Execute (Image, (Annulus with delta Angle_Span => 1.0E150),
                  Identity, (others => <>), Output, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then Message_Of (Status)
                        = "the output image would be more than 32767 "
                          & "pixels wide (RunParams.ScalingX times the middle "
                          & "arc of Region in pixels)",
             "polar unwrap: a span of 1.0E150");
      KP.Get_Input_Point_From_Output_Point
        (Annulus, Identity, Identity, (others => <>), NaN, 0.0, X, Y,
         Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then X = 0.0 and then Y = 0.0,
             "polar unwrap: a NaN output point");
      KP.Get_Output_Point_From_Input_Point
        (Annulus, Identity, Identity, (others => <>), 1.0, NaN, 0, X, Y,
         Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then Message_Of (Status)
                        = "InputPointY must be finite and within 1.0E150",
             "polar unwrap: a NaN input point");
      KP.Get_Output_Point_From_Input_Point
        (Annulus, Identity, Identity, (others => <>), 13.0, 8.0,
         K.Int32'Last, X, Y, Status);
      Check (K.Succeeded (Status) and then X > 1.0E9,
             "polar unwrap: the largest revolution");
      KI.Destroy (Image, Status);
   end Test_Kernels;

   ---------------------------------------------------------------------
   --  Timing
   ---------------------------------------------------------------------

   procedure Test_Timing is
      Image  : constant Ks_Image_8_Grey := Random_Image (640, 480, 5);
      Other  : constant Ks_Image_8_Grey := Random_Image (640, 480, 6);
      Colour : constant Ks_Image_24_Planar_Color := Create (640, 480, 10, 20, 30);
      Affine : AF.Ks_Affine_Transform_Tool;
      Copy   : CR.Ks_Copy_Region_Tool;
      Add    : TI.Ks_IP_Two_Image_Add_Tool;
      Conv   : IC.Ks_Image_Convert_Tool;
      Polar  : PU.Ks_Polar_Unwrap_Tool;
      C      : Ks_Circle;

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
      AMV_Test_Support.Section ("Timing (640 x 480)");
      Affine.Input_Image := Image;
      Affine.Region := Rectangle_Affine (320.0, 240.0, 600.0, 440.0, 0.1, 0.0);
      Affine.Run;
      Report ("affine transform (bilinear, turned)", Affine);
      Affine.Run_Params.Sampling_Mode := AF.Nearest_Neighbor;
      Affine.Run;
      Report ("affine transform (nearest, turned)", Affine);
      Copy.Input_Image := Image;
      Copy.Run;
      Report ("copy region (whole image)", Copy);
      C.Set_Center_Radius (320.0, 240.0, 200.0);
      Copy.Region := RH.To_Holder (C);
      Copy.Run;
      Report ("copy region (circle)", Copy);
      Add.Input_Image_A := Image;
      Add.Input_Image_B := Other;
      Add.Run;
      Report ("two-image add", Add);
      Conv.Input_Image := IHo.To_Holder (Colour);
      Conv.Run;
      Report ("image convert (colour intensity)", Conv);
      Polar.Input_Image := Image;
      Polar.Region := Section (320.0, 240.0, 50.0, 0.0, 2.0 * Pi, 4.0);
      Polar.Run;
      Report ("polar unwrap (785 x 150)", Polar);
   end Test_Timing;

   procedure Run_All is
   begin
      Test_Affine_Exact;
      Test_Affine_Measurement;
      Test_Affine_Clipping;
      Test_Affine_Errors;
      Test_Copy_Region;
      Test_Copy_Region_Spaces;
      Test_Copy_Region_Errors;
      Test_Two_Image;
      Test_Image_Convert;
      Test_Polar_Rings;
      Test_Polar_Mapping;
      Test_Polar_Spaces;
      Test_Kernels;
      Test_Timing;
   end Run_All;

   procedure Main is new AMV_Test_Support.Standalone (Run_All);
begin
   Main;
end Test_IP_Geometry;
