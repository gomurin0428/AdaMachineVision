--  Several objects of one kind in an image: PMAlign finds the four tea
--  lights of a photograph, and Find Circle, placed by each result's pose,
--  measures the rim of each light's cup.
--
--     candle_rims [image]
--
--  It reads photographs of four tea lights on a tray (VisA, category
--  candle; see README.md here for where the images come from):
--  visa_candle_0000.bmp, on whose top left light the pattern is trained
--  and the rim was taught, and visa_candle_<image>.bmp (0450 unless an
--  image is named), in which it looks for the lights. It prints what it
--  measures and writes pictures into the current directory:
--
--     candle_rims_1_train.bmp     the taught light: the train region, the
--                                 trained features and the taught rim
--     candle_rims_2_found.bmp     the other image: the four lights PMAlign
--                                 found, each with its score
--     candle_rims_3_measured.bmp  the same image: the four rims
--     candle_rims_4_rim.bmp       a part of one rim, enlarged: the calipers
--                                 of Find Circle, their edge points and
--                                 the circle
--
--  The settings are those of the real-image tests (tests/real_images),
--  which chose them on other images than the ones they are judged on.

with Ada.Command_Line;
with Ada.Exceptions;
with Ada.Numerics.Generic_Elementary_Functions;
with Ada.Text_IO;

with AMV;
with AMV.Caliper;
with AMV.Caliper.Find_Circle;
with AMV.Images;
with AMV.PM_Align;
with AMV.Shapes;
with AMV.Shapes.Region_Holders;
with AMV.Tools;
with AMV.Transforms;

with Example_Draw;
with Example_Support;

procedure Candle_Rims is

   use Ada.Text_IO;
   use AMV;
   use AMV.PM_Align;
   use type AMV.Tools.Ks_Tool_Result_Constants;

   package EF is new Ada.Numerics.Generic_Elementary_Functions (Real);
   package Draw renames Example_Draw;

   Pi : constant := Ada.Numerics.Pi;

   function Image (Value : Real; Aft : Natural := 1) return String
     renames Example_Support.Image;

   function Number (Value : Natural) return String is
     (Value'Image (2 .. Value'Image'Last));

   --  What was taught on image 0000: the rim of the top left light's cup
   --  (centre and radius, in the pixels of visa_candle_0000.bmp). The
   --  pattern is that light and 15 pixels around it.
   Taught_X : constant := 338.631;
   Taught_Y : constant := 279.243;
   Taught_R : constant := 207.979;
   Half     : constant := Taught_R + 15.0;

   Name : constant String :=
     (if Ada.Command_Line.Argument_Count >= 1
      then Ada.Command_Line.Argument (1) else "0450");

   Finder : Ks_PM_Align_Tool;

   procedure Draw_Pattern
     (Onto : in out Draw.Picture;
      Pose : AMV.Transforms.Ks_Transform_2D_Linear);
   --  The train region and the trained features where Pose puts them.

   procedure Draw_Pattern
     (Onto : in out Draw.Picture;
      Pose : AMV.Transforms.Ks_Transform_2D_Linear)
   is
      type Corner_List is array (0 .. 3, 1 .. 2) of Real;
      Corners : constant Corner_List :=
        [[Taught_X - Half, Taught_Y - Half],
         [Taught_X + Half, Taught_Y - Half],
         [Taught_X + Half, Taught_Y + Half],
         [Taught_X - Half, Taught_Y + Half]];
      X, Y    : array (0 .. 3) of Real;
      PX, PY  : Real;
   begin
      for F of Finder.Pattern.Get_Trained_Features loop
         Pose.Map_Point (F.X, F.Y, PX, PY);
         Draw.Dot (Onto, PX, PY, Draw.Yellow, Size => 1.0);
      end loop;
      for K in 0 .. 3 loop
         Pose.Map_Point (Corners (K, 1), Corners (K, 2), X (K), Y (K));
      end loop;
      for K in 0 .. 3 loop
         Draw.Line
           (Onto, X (K), Y (K), X ((K + 1) mod 4), Y ((K + 1) mod 4),
            Draw.Cyan, Width => 2.0);
      end loop;
   end Draw_Pattern;

   procedure Find_Rim
     (Lights       : AMV.Images.Ks_Image_8_Grey;
      Start_X      : Real;
      Start_Y      : Real;
      Found        : out Boolean;
      Rim          : out AMV.Shapes.Ks_Circle;
      Used         : out Natural;
      RMS          : out Real;
      Picture_Name : String := "");
   --  The rim whose centre the pose puts at (Start_X, Start_Y). Two runs,
   --  the second from the first circle. With a Picture_Name, writes the
   --  enlarged picture of the second run.

   procedure Find_Rim
     (Lights       : AMV.Images.Ks_Image_8_Grey;
      Start_X      : Real;
      Start_Y      : Real;
      Found        : out Boolean;
      Rim          : out AMV.Shapes.Ks_Circle;
      Used         : out Natural;
      RMS          : out Real;
      Picture_Name : String := "")
   is
      use AMV.Caliper;
      use AMV.Caliper.Find_Circle;
      X : Real := Start_X;
      Y : Real := Start_Y;
      R : Real := Taught_R;
   begin
      Found := False;
      Used := 0;
      RMS := 0.0;
      for Pass in 1 .. 2 loop
         declare
            Tool : Ks_Find_Circle_Tool;
         begin
            Tool.Input_Image := Lights;
            --  64 calipers around the expected circle, each 16 pixels
            --  long across it and 6 wide, looking outwards for the step
            --  from the light rim to the dark tray. Every point found
            --  takes part in the fit: the rims are not perfectly round,
            --  and leaving the farthest points out pulls the circle to
            --  one side.
            Tool.Run_Params.Expected_Circular_Arc
              .Set_Center_Radius_Angle_Start_Angle_Span
                (X, Y, R, 0.0, 2.0 * Pi);
            Tool.Run_Params.Num_Calipers := 64;
            Tool.Run_Params.Caliper_Search_Length := 16.0;
            Tool.Run_Params.Caliper_Projection_Length := 6.0;
            Tool.Run_Params.Caliper_Search_Direction := Outward;
            Tool.Run_Params.Num_To_Ignore := 0;
            Tool.Run_Params.Caliper_Run_Params.Edge_0_Polarity :=
              Code (Light_To_Dark);
            Tool.Run_Params.Caliper_Run_Params.Contrast_Threshold := 20.0;
            Tool.Run_Params.Caliper_Run_Params.Filter_Half_Size_In_Pixels :=
              1;
            Tool.Run;
            Found := Tool.Run_Status.Result = AMV.Tools.Accept_Result;
            exit when not Found;
            Rim := Tool.Results.Get_Circle;
            Used := Tool.Results.Num_Points_Used;
            RMS := Tool.Results.RMS_Error;

            if Pass = 2 and then Picture_Name /= "" then
               declare
                  --  The part of the rim towards the top right.
                  Angle : constant Real := -Pi / 4.0;
                  Zoom  : Draw.Picture :=
                    Draw.Create
                      (Lights,
                       Integer (Rim.Center_X + Rim.Radius * EF.Cos (Angle))
                       - 45,
                       Integer (Rim.Center_Y + Rim.Radius * EF.Sin (Angle))
                       - 45,
                       90, 90, Scale => 6.0);
               begin
                  for K in 0 .. Tool.Results.Count - 1 loop
                     Draw.Outline
                       (Zoom, Get_Caliper_Region (Tool.Run_Params, K),
                        Draw.Cyan, Width => 1.0);
                  end loop;
                  Draw.Outline (Zoom, Rim, Draw.Green, Width => 2.5);
                  for K in 0 .. Tool.Results.Count - 1 loop
                     if Tool.Results.Item (K).Found then
                        Draw.Dot
                          (Zoom, Tool.Results.Item (K).X,
                           Tool.Results.Item (K).Y,
                           (if Tool.Results.Item (K).Used then Draw.Green
                            else Draw.Red),
                           Size => 4.0);
                     end if;
                  end loop;
                  Draw.Caption (Zoom, 0, "FIND CIRCLE ON A RIM (A PART)");
                  Draw.Caption
                    (Zoom, 1, "CALIPERS (" & Number (Tool.Results.Count)
                     & " AROUND THE RIM)", Draw.Cyan);
                  Draw.Caption (Zoom, 2, "EDGE POINTS, CIRCLE", Draw.Green);
                  Draw.Write (Zoom, Picture_Name);
               end;
            end if;

            X := Rim.Center_X;
            Y := Rim.Center_Y;
            R := Rim.Radius;
         end;
      end loop;
   end Find_Rim;

begin
   --  Train on the top left light of image 0000.
   declare
      Taught : constant AMV.Images.Ks_Image_8_Grey :=
        Example_Support.Real_Image ("visa_candle_0000.bmp");
      Region   : AMV.Shapes.Ks_Rectangle;
      Identity : AMV.Transforms.Ks_Transform_2D_Linear;
      Shown    : Draw.Picture := Draw.Create (Taught, Scale => 0.5);
   begin
      Region.Set_XY_Width_Height
        (Taught_X - Half, Taught_Y - Half, 2.0 * Half, 2.0 * Half);
      Finder.Pattern.Set_Train_Image (Taught);
      Finder.Pattern.Set_Train_Region
        (AMV.Shapes.Region_Holders.To_Holder (Region));
      --  The pattern's origin stays the identity, so that a result's pose
      --  maps the pixels of image 0000 to the pixels of the image
      --  searched.
      Finder.Pattern.Train;
      Put_Line
        ("trained on the top left light of image 0000:"
         & Natural'Image (Finder.Pattern.Get_Trained_Features'Length)
         & " fine features");

      Draw_Pattern (Shown, Identity);
      Draw.Circle
        (Shown, Taught_X, Taught_Y, Taught_R, Draw.Green, Width => 2.5);
      Draw.Cross (Shown, Taught_X, Taught_Y, Draw.Green, Size => 12.0);
      Draw.Caption (Shown, 0, "TAUGHT ON IMAGE 0000");
      Draw.Caption (Shown, 1, "TRAIN REGION", Draw.Cyan);
      Draw.Caption (Shown, 2, "TRAINED FEATURES", Draw.Yellow);
      Draw.Caption (Shown, 3, "RIM", Draw.Green);
      Draw.Write (Shown, "candle_rims_1_train.bmp");
   end;

   --  Four lights, at any angle, 5 % of scale either way. The other
   --  lights score well below the trained one (their wicks point in other
   --  directions and their shadows fall elsewhere), hence the low accept
   --  threshold.
   Finder.Run_Params.Approximate_Number_To_Find := 4;
   Finder.Run_Params.Zone_Angle.Configuration := Code (Low_High);
   Finder.Run_Params.Zone_Angle.Low := -Pi;
   Finder.Run_Params.Zone_Angle.High := Pi;
   Finder.Run_Params.Zone_Scale.Configuration := Code (Low_High);
   Finder.Run_Params.Zone_Scale.Low := 0.95;
   Finder.Run_Params.Zone_Scale.High := 1.05;
   Finder.Run_Params.Accept_Threshold := 0.3;

   declare
      Lights   : constant AMV.Images.Ks_Image_8_Grey :=
        Example_Support.Real_Image ("visa_candle_" & Name & ".bmp");
      Found    : Draw.Picture := Draw.Create (Lights, Scale => 0.5);
      Measured : Draw.Picture := Draw.Create (Lights, Scale => 0.5);
      Rims     : Natural := 0;
   begin
      Finder.Input_Image := Lights;
      Finder.Run;
      if Finder.Run_Status.Result /= AMV.Tools.Accept_Result then
         Put_Line ("image " & Name & ": PMAlign found no light");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;
      Put_Line
        ("image " & Name & ": PMAlign found"
         & Natural'Image (Finder.Results.Count) & " lights");

      for N in 0 .. Finder.Results.Count - 1 loop
         declare
            Match   : constant Ks_PM_Align_Result := Finder.Results.Item (N);
            Pose    : constant AMV.Transforms.Ks_Transform_2D_Linear :=
              Get_Pose (Match);
            Light   : constant String := Number (N + 1);
            Start_X : Real;
            Start_Y : Real;
            Ok      : Boolean;
            Rim     : AMV.Shapes.Ks_Circle;
            Used    : Natural;
            RMS     : Real;
         begin
            Pose.Map_Point (Taught_X, Taught_Y, Start_X, Start_Y);
            Draw_Pattern (Found, Pose);
            Draw.Text
              (Found, Start_X, Start_Y,
               Light & ": SCORE " & Image (Match.Score, 2), Draw.Yellow,
               DX => -78, DY => -9);

            Find_Rim
              (Lights, Start_X, Start_Y, Ok, Rim, Used, RMS,
               (if N = 0 then "candle_rims_4_rim.bmp" else ""));
            if Ok then
               Rims := Rims + 1;
               Put_Line
                 ("  light " & Light & ": score " & Image (Match.Score, 2)
                  & ", turned by " & Image (Match.Rotation * 180.0 / Pi)
                  & " degrees; rim centre (" & Image (Rim.Center_X, 2)
                  & ", " & Image (Rim.Center_Y, 2) & "), radius "
                  & Image (Rim.Radius, 2) & " (" & Number (Used)
                  & " points, rms " & Image (RMS, 2) & ")");
               Draw.Outline (Measured, Rim, Draw.Green, Width => 2.5);
               Draw.Cross
                 (Measured, Rim.Center_X, Rim.Center_Y, Draw.Green,
                  Size => 14.0);
               Draw.Text
                 (Measured, Rim.Center_X, Rim.Center_Y,
                  Light & ": RADIUS " & Image (Rim.Radius), Draw.Green,
                  DX => -90, DY => 14);
            else
               Put_Line
                 ("  light " & Light & ": score " & Image (Match.Score, 2)
                  & "; rim not found");
            end if;
         end;
      end loop;

      Draw.Caption
        (Found, 0, "PMALIGN:" & Natural'Image (Finder.Results.Count)
         & " LIGHTS IN IMAGE " & Name);
      Draw.Caption (Found, 1, "PATTERN, WHERE FOUND", Draw.Cyan);
      Draw.Caption (Found, 2, "ITS FEATURES", Draw.Yellow);
      Draw.Write (Found, "candle_rims_2_found.bmp");

      Draw.Caption
        (Measured, 0, "FIND CIRCLE:" & Rims'Image & " RIMS IN IMAGE "
         & Name);
      Draw.Write (Measured, "candle_rims_3_measured.bmp");
      Put_Line ("wrote candle_rims_1_train.bmp to candle_rims_4_rim.bmp");
   end;
exception
   when E : Example_Support.Missing_Image =>
      Put_Line (Ada.Exceptions.Exception_Message (E));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Candle_Rims;
