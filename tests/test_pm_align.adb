--  Tests for AMV.PM_Align (CogPMAlignTool) and its kernel
--  AMV.Kernels.PM_Align.
--
--  The pattern is an asymmetric shape drawn with AMV_Test_Images: an L
--  (a polygon) with a dark round hole in its long arm and a separate disc
--  beside its short arm. Scenes are the same shape drawn at a known pose
--  (translation, rotation about the shape's reference point, scale), so
--  every result can be checked against the pose that drew it. The shape's
--  reference point is the pattern origin of the default training, so the
--  expected pose is exactly the drawing pose. Edges turned by generic
--  angles are placed by the renderer within about 0.002 pixel; axis-
--  aligned ones at multiples of 1/8 pixel exactly (see AMV_Test_Images),
--  so the 0.1 pixel and 0.1 degree tolerances measure the tool.

pragma Validity_Checks ("F");
--  The kernel tests build NaNs on purpose.

with Ada.Calendar;
with Ada.Numerics.Long_Elementary_Functions;
with Ada.Streams.Storage.Unbounded;
with Ada.Text_IO;
with Interfaces;

with AMV;                    use AMV;
with AMV.Coordinate_Spaces;  use AMV.Coordinate_Spaces;
with AMV.Images;             use AMV.Images;
with AMV.Images.Kernel_Images;
with AMV.Kernels;
with AMV.Kernels.Images;
with AMV.Kernels.PM_Align;
with AMV.Kernels.Regions;
with AMV.Kernels.Transforms;
with AMV.PM_Align;           use AMV.PM_Align;
with AMV.Regions;
with AMV.Regions.Kernel_Regions;
with AMV.Shapes;             use AMV.Shapes;
with AMV.Shapes.Region_Holders;
with AMV.Tools;              use AMV.Tools;
with AMV.Transforms;         use AMV.Transforms;
with AMV_Test_Images;
with AMV_Test_Support;       use AMV_Test_Support;

procedure Test_PM_Align is

   package EF renames Ada.Numerics.Long_Elementary_Functions;
   package K renames AMV.Kernels;
   package KI renames AMV.Kernels.Images;
   package KP renames AMV.Kernels.PM_Align;
   package KR renames AMV.Kernels.Regions;
   package KT renames AMV.Kernels.Transforms;
   package TI renames AMV_Test_Images;

   use type K.Int32;
   use type Interfaces.Unsigned_8;
   use type KP.Ks_PM_Align_Pattern;
   use type KP.Ks_PM_Align_Results;
   use type KP.Ks_PM_Align_Feature_Array;
   use type KP.Ks_PM_Align_Result;
   use type KP.Ks_PM_Align_Train_Params;
   use type KP.Ks_PM_Align_Pattern_Data;

   Pi  : constant := Ada.Numerics.Pi;
   Deg : constant := Pi / 180.0;

   Zero : constant Real := Real'Value ("0.0");

   Unallocated : Ks_Image_8_Grey;

   Background : constant Grey_8 := 40;
   Foreground : constant Grey_8 := 200;

   ---------------------------------------------------------------------
   --  The shape
   ---------------------------------------------------------------------

   type Point is record
      X, Y : Real;
   end record;

   type Point_List is array (Positive range <>) of Point;

   L_Shape : constant Point_List :=
     [(-40.0, -30.0), (38.0, -30.0), (38.0, -9.0), (-12.0, -9.0),
      (-12.0, 34.0), (-40.0, 34.0)];
   --  The L, around its reference point (0, 0).

   Hole_X : constant := -26.0;
   Hole_Y : constant := 16.0;
   Hole_R : constant := 6.5;
   Disc_X : constant := 18.0;
   Disc_Y : constant := 18.0;
   Disc_R : constant := 9.0;

   procedure Map
     (P            : Point;
      CX, CY, A, S : Real;
      X, Y         : out Real);
   --  The point P of the shape drawn at (CX, CY), turned by A, scaled by
   --  S.

   procedure Map
     (P            : Point;
      CX, CY, A, S : Real;
      X, Y         : out Real)
   is
      C : constant Real := EF.Cos (A);
      N : constant Real := EF.Sin (A);
   begin
      X := CX + S * (C * P.X - N * P.Y);
      Y := CY + S * (N * P.X + C * P.Y);
   end Map;

   procedure Draw_Shape
     (Image      : in out Ks_Image_8_Grey;
      CX, CY     : Real;
      Angle      : Real := 0.0;
      Scale      : Real := 1.0;
      Value      : Grey_8 := Foreground;
      Hole_Value : Grey_8 := Background);
   --  Draws the shape with its reference point at (CX, CY), turned by
   --  Angle and scaled by Scale.

   procedure Draw_Shape
     (Image      : in out Ks_Image_8_Grey;
      CX, CY     : Real;
      Angle      : Real := 0.0;
      Scale      : Real := 1.0;
      Value      : Grey_8 := Foreground;
      Hole_Value : Grey_8 := Background)
   is
      V    : TI.Vertex_List (1 .. 2 * L_Shape'Length);
      X, Y : Real;
   begin
      for I in L_Shape'Range loop
         Map (L_Shape (I), CX, CY, Angle, Scale, X, Y);
         V (2 * I - 1) := X;
         V (2 * I) := Y;
      end loop;
      TI.Draw_Polygon (Image, V, Value);
      Map ((Hole_X, Hole_Y), CX, CY, Angle, Scale, X, Y);
      TI.Draw_Circle (Image, X, Y, Scale * Hole_R, Hole_Value);
      Map ((Disc_X, Disc_Y), CX, CY, Angle, Scale, X, Y);
      TI.Draw_Circle (Image, X, Y, Scale * Disc_R, Value);
   end Draw_Shape;

   Train_CX : constant := 100.0;
   Train_CY : constant := 100.0;

   function Train_Image
     (Value      : Grey_8 := Foreground;
      Base       : Grey_8 := Background) return Ks_Image_8_Grey;
   --  The shape drawn at (100, 100) in a 200 x 200 image.

   function Train_Image
     (Value      : Grey_8 := Foreground;
      Base       : Grey_8 := Background) return Ks_Image_8_Grey is
   begin
      return Image : Ks_Image_8_Grey := TI.Blank (200, 200, Base) do
         Draw_Shape (Image, Train_CX, Train_CY, Value => Value,
                     Hole_Value => Base);
      end return;
   end Train_Image;

   function Train_Region return AMV.Shapes.Region_Holders.Holder;
   --  A 110 x 96 rectangle around the shape in the train image.

   function Train_Region return AMV.Shapes.Region_Holders.Holder is
      Region : Ks_Rectangle;
   begin
      Region.Set_Center_Width_Height (Train_CX, Train_CY + 2.0, 110.0, 96.0);
      return AMV.Shapes.Region_Holders.To_Holder (Region);
   end Train_Region;

   function Trained_Pattern
     (Algorithm : Ks_PM_Align_Train_Algorithm_Constants :=
        Pat_Max_And_Pat_Quick;
      Ignore    : Boolean := False) return Ks_PM_Align_Pattern;
   --  A pattern trained on Train_Image within Train_Region, with the
   --  origin at the shape's reference point.

   function Trained_Pattern
     (Algorithm : Ks_PM_Align_Train_Algorithm_Constants :=
        Pat_Max_And_Pat_Quick;
      Ignore    : Boolean := False) return Ks_PM_Align_Pattern is
   begin
      return Pattern : Ks_PM_Align_Pattern do
         Pattern.Set_Train_Image (Train_Image);
         Pattern.Set_Train_Region (Train_Region);
         Pattern.Set_Origin (Create_Rigid (0.0, Train_CX, Train_CY));
         Pattern.Set_Train_Algorithm (Algorithm);
         Pattern.Set_Ignore_Polarity (Ignore);
         Pattern.Train;
      end return;
   end Trained_Pattern;

   Shared_Pattern : constant Ks_PM_Align_Pattern := Trained_Pattern;

   procedure Report (Tool : Ks_PM_Align_Tool; Description : String);

   procedure Report (Tool : Ks_PM_Align_Tool; Description : String) is
   begin
      if Tool.Run_Status.Result /= Accept_Result then
         Ada.Text_IO.Put_Line
           ("  " & Description & ": " & Tool.Run_Status.Result'Image & " "
            & Exception_Name (Tool.Run_Status) & " "
            & Message (Tool.Run_Status));
      end if;
   end Report;

   function Status_Is
     (Tool                : Ks_PM_Align_Tool;
      Exception_Name_Part : String;
      Message             : String) return Boolean
   is (Tool.Run_Status.Result = Error
       and then AMV.Tools.Exception_Name (Tool.Run_Status)
                  = "AMV." & Exception_Name_Part
       and then AMV.Tools.Message (Tool.Run_Status) = Message);

   function Angle_Error (A, B : Real) return Real is
     (abs (EF.Arctan (EF.Sin (A - B), EF.Cos (A - B))));
   --  The absolute difference of two angles modulo 2 Pi.

   function Scene return Ks_Image_8_Grey is (TI.Blank (640, 480, Background));

   procedure Set_Full_Circle (Tool : in out Ks_PM_Align_Tool) is
   begin
      Tool.Run_Params.Zone_Angle.Configuration := Code (Low_High);
      Tool.Run_Params.Zone_Angle.Low := -Pi;
      Tool.Run_Params.Zone_Angle.High := Pi;
   end Set_Full_Circle;

   procedure Check_Pose
     (Description            : String;
      R                      : Ks_PM_Align_Result;
      CX, CY, Angle, Scale   : Real;
      Position_Tolerance     : Real := 0.1;
      Angle_Tolerance        : Real := 0.1 * Deg);
   --  R is the pose that drew the shape at (CX, CY, Angle, Scale).

   procedure Check_Pose
     (Description            : String;
      R                      : Ks_PM_Align_Result;
      CX, CY, Angle, Scale   : Real;
      Position_Tolerance     : Real := 0.1;
      Angle_Tolerance        : Real := 0.1 * Deg) is
   begin
      Check_Near (R.Translation_X, CX, Position_Tolerance,
                  Description & ": x");
      Check_Near (R.Translation_Y, CY, Position_Tolerance,
                  Description & ": y");
      Check (Angle_Error (R.Rotation, Angle) <= Angle_Tolerance,
             Description & ": angle");
      Check_Near (R.Scaling, Scale, 0.005 * Scale, Description & ": scale");
   end Check_Pose;

   ---------------------------------------------------------------------

   procedure Test_Defaults is
      P : constant Ks_PM_Align_Run_Params := (others => <>);
      T : Ks_PM_Align_Tool;
   begin
      Section ("PMAlign: defaults");
      Check (P.Accept_Threshold = 0.5 and then P.Approximate_Number_To_Find = 1
             and then Run_Algorithm (P.Run_Algorithm) = Pat_Max
             and then P.Score_Using_Clutter = 1
             and then P.Contrast_Threshold = 10.0
             and then P.Outside_Region_Threshold = 0.1
             and then P.Timeout_Enabled = 0,
             "AcceptThreshold 0.5, one result, PatMax, clutter scoring");
      Check (Zone (P.Zone_Angle.Configuration) = Nominal
             and then P.Zone_Angle.Nominal = 0.0
             and then Zone (P.Zone_Scale.Configuration) = Nominal
             and then P.Zone_Scale.Nominal = 1.0
             and then P.Zone_Scale.Low = 0.9 and then P.Zone_Scale.High = 1.1,
             "nominal zones");
      Check (not T.Pattern.Trained and then T.Results.Count = 0,
             "untrained pattern, no results");
      Check (T.Pattern.Train_Algorithm = Pat_Max
             and then T.Pattern.Grain_Limit_Auto_Select
             and then T.Pattern.Grain_Limit_Coarse = 8.0
             and then T.Pattern.Grain_Limit_Fine = 1.0
             and then not T.Pattern.Ignore_Polarity,
             "pattern defaults");
      Check (Identity (T.Pattern.Origin, 0.0), "Origin: the identity");
      Check (Shared_Pattern.Trained, "the shape trains");
      Check (Code (Ks_PM_Align_Run_Algorithm_Constants'(Best_Trained)) = 2
             and then Code (Ks_PM_Align_Train_Algorithm_Constants'
                              (Pat_Max_And_Pat_Quick)) = 2
             and then Code (Low_High) = 1,
             "VisionPro's enumeration values");
   end Test_Defaults;

   procedure Test_Features is
      Fine   : constant Ks_PM_Align_Feature_Array :=
        Shared_Pattern.Get_Trained_Features;
      Coarse : constant Ks_PM_Align_Feature_Array :=
        Shared_Pattern.Get_Trained_Features (Fine => False);
      Unit_Normals : Boolean := True;
      On_Edges     : Boolean := True;
   begin
      Section ("PMAlign: trained features");
      Check (Fine'Length >= 200 and then Fine'Length <= KP.Max_Features,
             "finest level: a few hundred features");
      Check (Coarse'Length >= KP.Min_Features
             and then Coarse'Length < Fine'Length,
             "coarsest level: fewer features");
      for F of Fine loop
         if abs (EF.Sqrt (F.Normal_X**2 + F.Normal_Y**2) - 1.0) > 1.0E-9 then
            Unit_Normals := False;
         end if;
         --  Every feature lies on the L's outline, the hole or the disc:
         --  within the shape's bounding box, pattern coordinates.
         if F.X < -41.0 or else F.X > 39.0 or else F.Y < -31.0
           or else F.Y > 35.0
         then
            On_Edges := False;
         end if;
      end loop;
      Check (Unit_Normals, "unit normals");
      Check (On_Edges, "features on the shape");
   end Test_Features;

   procedure Locate
     (Description          : String;
      CX, CY, Angle, Scale : Real;
      Full_Circle          : Boolean;
      Pos_Tol, Angle_Tol   : Real;
      Algorithm            : Ks_PM_Align_Run_Algorithm_Constants := Pat_Max;
      Noise                : Real := 0.0);
   --  Draws the shape at the pose, searches it in a 640 x 480 scene and
   --  checks the pose of the one result.

   procedure Locate
     (Description          : String;
      CX, CY, Angle, Scale : Real;
      Full_Circle          : Boolean;
      Pos_Tol, Angle_Tol   : Real;
      Algorithm            : Ks_PM_Align_Run_Algorithm_Constants := Pat_Max;
      Noise                : Real := 0.0)
   is
      Tool  : Ks_PM_Align_Tool;
      Image : Ks_Image_8_Grey := Scene;
      Start : Ada.Calendar.Time;
      Took  : Duration;
   begin
      Draw_Shape (Image, CX, CY, Angle, Scale);
      if Noise > 0.0 then
         TI.Add_Noise (Image, Noise, 7);
      end if;
      Tool.Input_Image := Image;
      Tool.Pattern := Shared_Pattern;
      Tool.Run_Params.Run_Algorithm := Code (Algorithm);
      if Full_Circle then
         Set_Full_Circle (Tool);
      else
         Tool.Run_Params.Zone_Angle.Nominal := Angle;
      end if;
      if Scale /= 1.0 then
         Tool.Run_Params.Zone_Scale :=
           (Configuration => Code (Low_High), Low => 0.85, High => 1.2,
            Nominal => 1.0);
      end if;
      Start := Ada.Calendar.Clock;
      Tool.Run;
      Took := Ada.Calendar."-" (Ada.Calendar.Clock, Start);
      Report (Tool, Description);
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Count = 1, Description & ": one result");
      if Tool.Results.Count >= 1 then
         declare
            R : constant Ks_PM_Align_Result := Tool.Results.Item (0);
         begin
            Ada.Text_IO.Put_Line
              ("  " & Description & ":" & Duration'Image (Took * 1000.0)
               & " ms, score" & R.Score'Image & ", error x"
               & Real'Image (R.Translation_X - CX) & " y"
               & Real'Image (R.Translation_Y - CY) & " angle (deg)"
               & Real'Image (Angle_Error (R.Rotation, Angle) / Deg)
               & " scale" & Real'Image (R.Scaling - Scale));
            Check_Pose (Description, R, CX, CY, Angle, Scale, Pos_Tol,
                        Angle_Tol);
            Check (R.Score >= 0.8, Description & ": score >= 0.8");
            Check (R.ID = 0 and then R.Fine_Stage
                                       = (if Algorithm /= Pat_Quick then 1
                                          else 0),
                   Description & ": ID and FineStage");
         end;
      end if;
   end Locate;

   procedure Test_Locate is
   begin
      Section ("PMAlign: translation, rotation, scale");
      Locate ("nominal angle", 300.375, 220.875, 0.0, 1.0, False, 0.1,
              0.1 * Deg);
      Locate ("full circle, 1.234 rad", 300.37, 220.81, 1.234, 1.0, True,
              0.1, 0.1 * Deg);
      Locate ("full circle, 3.0 rad", 330.2, 250.7, 3.0, 1.0, True, 0.1,
              0.1 * Deg);
      Locate ("full circle, near +180 deg", 411.6, 180.2, Pi - 0.004, 1.0,
              True, 0.1, 0.1 * Deg);
      Locate ("full circle, near -180 deg", 211.9, 300.6, -Pi + 0.003, 1.0,
              True, 0.1, 0.1 * Deg);
      Locate ("full circle, -2.1 rad", 160.3, 120.4, -2.1, 1.0, True, 0.1,
              0.1 * Deg);
      Locate ("full circle, -0.7 rad", 500.1, 380.6, -0.7, 1.0, True, 0.1,
              0.1 * Deg);
      Locate ("scale 1.1, 0.5 rad", 320.3, 240.2, 0.5, 1.1, True, 0.1,
              0.1 * Deg);
      Locate ("scale 0.9, -1.3 rad", 280.6, 210.4, -1.3, 0.9, True, 0.1,
              0.1 * Deg);
      Locate ("PatQuick", 300.37, 220.81, 1.234, 1.0, True, 0.5, 1.0 * Deg,
              Pat_Quick);
      Locate ("BestTrained", 280.6, 210.4, 2.2, 1.0, True, 0.1, 0.1 * Deg,
              Best_Trained);
      Locate ("noise 20", 260.4, 250.3, 2.5, 1.0, True, 0.15, 0.15 * Deg,
              Pat_Max, 20.0);
   end Test_Locate;

   procedure Test_Several is
      Tool  : Ks_PM_Align_Tool;
      Image : Ks_Image_8_Grey := Scene;
      type Pose is record
         X, Y, A : Real;
      end record;
      Poses : constant array (1 .. 3) of Pose :=
        [(130.3, 120.7, 0.4), (430.6, 140.2, -2.0), (300.1, 360.8, 2.9)];
      Found : array (Poses'Range) of Boolean := [others => False];
   begin
      Section ("PMAlign: several instances");
      for P of Poses loop
         Draw_Shape (Image, P.X, P.Y, P.A);
      end loop;
      Tool.Input_Image := Image;
      Tool.Pattern := Shared_Pattern;
      Set_Full_Circle (Tool);
      Tool.Run_Params.Approximate_Number_To_Find := 5;
      Tool.Run;
      Report (Tool, "three instances");
      Check (Tool.Results.Count = 3, "three results");
      for I in 0 .. Tool.Results.Count - 1 loop
         declare
            R : constant Ks_PM_Align_Result := Tool.Results.Item (I);
         begin
            Check (R.ID = K.Int32 (I), "ID is the index");
            if I > 0 then
               Check (Tool.Results.Item (I - 1).Score >= R.Score,
                      "sorted by score");
            end if;
            for J in Poses'Range loop
               if abs (R.Translation_X - Poses (J).X) < 0.1
                 and then abs (R.Translation_Y - Poses (J).Y) < 0.1
                 and then Angle_Error (R.Rotation, Poses (J).A) < 0.1 * Deg
               then
                  Found (J) := True;
               end if;
            end loop;
         end;
      end loop;
      Check (Found = [Poses'Range => True], "every instance, accurately");

      Tool.Run_Params.Approximate_Number_To_Find := 2;
      Tool.Run;
      Check (Tool.Results.Count = 2, "ApproximateNumberToFind 2: the best"
             & " two");
   end Test_Several;

   procedure Test_Search_Mask is
      --  Three instances; the mask leaves the second one (at 430.6, 140.2)
      --  out of the search region.
      Tool  : Ks_PM_Align_Tool;
      Image : Ks_Image_8_Grey := Scene;
      Full  : Ks_Image_8_Grey := TI.Blank (640, 480, 255);
      Small : constant Ks_Image_8_Grey := TI.Blank (120, 120, 0);
      function Has (X, Y : Real) return Boolean is
        (for some I in 0 .. Tool.Results.Count - 1 =>
           abs (Tool.Results.Item (I).Translation_X - X) < 0.2
           and then abs (Tool.Results.Item (I).Translation_Y - Y) < 0.2);
   begin
      Section ("PMAlign: the search image mask");
      Draw_Shape (Image, 130.3, 120.7, 0.4);
      Draw_Shape (Image, 430.6, 140.2, -2.0);
      Draw_Shape (Image, 300.1, 360.8, 2.9);
      for Y in 80 .. 199 loop
         for X in 370 .. 489 loop
            Full.Set_Pixel (X, Y, 0);
         end loop;
      end loop;
      Tool.Input_Image := Image;
      Tool.Pattern := Shared_Pattern;
      Set_Full_Circle (Tool);
      Tool.Run_Params.Approximate_Number_To_Find := 5;
      Tool.Run;
      Check (Tool.Results.Count = 3, "no mask: three results");
      Tool.Search_Image_Mask := Full;
      Tool.Run;
      Report (Tool, "search mask");
      Check (Tool.Results.Count = 2
             and then Has (130.3, 120.7) and then Has (300.1, 360.8)
             and then not Has (430.6, 140.2),
             "a mask over the second instance: the other two");
      --  The same with a mask of the left-out square only, at offsets.
      Tool.Search_Image_Mask := Small;
      Tool.Search_Image_Mask_Offset_X := 370;
      Tool.Search_Image_Mask_Offset_Y := 80;
      Tool.Run;
      Check (Tool.Results.Count = 2 and then not Has (430.6, 140.2),
             "a 120 x 120 mask at (370, 80): the same");
      --  Moved away from every instance, it leaves out nothing found.
      Tool.Search_Image_Mask_Offset_X := 0;
      Tool.Search_Image_Mask_Offset_Y := 300;
      Tool.Run;
      Check (Tool.Results.Count = 3, "a mask over no instance: three");
   end Test_Search_Mask;

   procedure Test_XY_Overlap is
      --  Two instances 55 pixels apart: their footprints (78 x 64 pixels)
      --  share 23 / 78, about 0.29, of their area.
      Tool  : Ks_PM_Align_Tool;
      Image : Ks_Image_8_Grey := Scene;
   begin
      Section ("PMAlign: XYOverlap");
      Draw_Shape (Image, 200.3, 240.6, 0.0);
      Draw_Shape (Image, 255.3, 240.6, 0.0);
      Tool.Input_Image := Image;
      Tool.Pattern := Shared_Pattern;
      Tool.Run_Params.Approximate_Number_To_Find := 3;
      Check (Tool.Run_Params.XY_Overlap = 1.0, "the default is 1.0");
      Tool.Run;
      Report (Tool, "XYOverlap 1.0");
      Check (Tool.Results.Count = 2,
             "XYOverlap 1.0: both overlapping instances" & Tool.Results.Count'Image);
      Tool.Run_Params.XY_Overlap := 0.4;
      Tool.Run;
      Check (Tool.Results.Count = 2, "XYOverlap 0.4 (above 0.29): both");
      Tool.Run_Params.XY_Overlap := 0.2;
      Tool.Run;
      Check (Tool.Results.Count = 1,
             "XYOverlap 0.2 (below 0.29): the worse one is dropped");
      if Tool.Results.Count = 1 then
         Check (abs (Tool.Results.Item (0).Translation_Y - 240.6) < 0.2
                and then (abs (Tool.Results.Item (0).Translation_X - 200.3)
                            < 0.2
                          or else abs (Tool.Results.Item (0).Translation_X
                                       - 255.3) < 0.2),
                "the one kept is one of the two");
      end if;
      Tool.Run_Params.XY_Overlap := 1.5;
      Tool.Run;
      Check (Status_Is (Tool, "KS_BAD_PARAMETER_EXCEPTION",
                        "RunParams.XYOverlap must be in [0, 1]"),
             "XYOverlap 1.5: Ks_Bad_Parameter_Exception");
   end Test_XY_Overlap;

   procedure Test_Occlusion_And_Contrast is
   begin
      Section ("PMAlign: occlusion, contrast, polarity");
      declare
         Tool  : Ks_PM_Align_Tool;
         Image : Ks_Image_8_Grey := Scene;
      begin
         Draw_Shape (Image, 320.3, 240.6, 0.8);
         --  A background-coloured bar over part of the long arm.
         TI.Draw_Rectangle (Image, 320.3, 240.6, 120.0, 22.0, 2.0,
                            Background);
         Tool.Input_Image := Image;
         Tool.Pattern := Shared_Pattern;
         Set_Full_Circle (Tool);
         Tool.Run;
         Report (Tool, "occlusion");
         Check (Tool.Results.Count = 1, "occluded: found");
         if Tool.Results.Count = 1 then
            Check (Tool.Results.Item (0).Score < 0.95
                   and then Tool.Results.Item (0).Coverage < 0.95,
                   "occluded: the score and the coverage drop");
            Check_Pose ("occluded", Tool.Results.Item (0), 320.3, 240.6, 0.8,
                        1.0, 0.15, 0.15 * Deg);
         end if;
      end;
      declare
         Tool  : Ks_PM_Align_Tool;
         Image : Ks_Image_8_Grey := TI.Blank (640, 480, 90);
      begin
         Draw_Shape (Image, 250.2, 200.4, -1.1, Value => 135,
                     Hole_Value => 90);
         Tool.Input_Image := Image;
         Tool.Pattern := Shared_Pattern;
         Set_Full_Circle (Tool);
         Tool.Run;
         Report (Tool, "low contrast");
         Check (Tool.Results.Count = 1
                and then Tool.Results.Item (0).Score > 0.9,
                "low contrast (45 grey levels): found, high score");
         if Tool.Results.Count = 1 then
            Check_Pose ("low contrast", Tool.Results.Item (0), 250.2, 200.4,
                        -1.1, 1.0);
         end if;
      end;
      declare
         Tool  : Ks_PM_Align_Tool;
         Image : Ks_Image_8_Grey := TI.Blank (640, 480, Foreground);
      begin
         --  The shape dark on a bright ground: the opposite polarity.
         Draw_Shape (Image, 250.2, 200.4, 0.3, Value => Background,
                     Hole_Value => Foreground);
         Tool.Input_Image := Image;
         Tool.Pattern := Shared_Pattern;
         Set_Full_Circle (Tool);
         Tool.Run;
         Check (Tool.Run_Status.Result = Accept_Result
                and then Tool.Results.Count = 0,
                "inverted polarity: not found");
         Tool.Pattern := Trained_Pattern (Ignore => True);
         Tool.Run;
         Report (Tool, "ignore polarity");
         Check (Tool.Results.Count = 1, "IgnorePolarity: found");
         if Tool.Results.Count = 1 then
            Check_Pose ("ignore polarity", Tool.Results.Item (0), 250.2,
                        200.4, 0.3, 1.0);
         end if;
      end;
   end Test_Occlusion_And_Contrast;

   procedure Test_No_False_Positives is
      Tool  : Ks_PM_Align_Tool;
      Image : Ks_Image_8_Grey := Scene;
   begin
      Section ("PMAlign: no false positives");
      Tool.Input_Image := Image;
      Tool.Pattern := Shared_Pattern;
      Set_Full_Circle (Tool);
      Tool.Run_Params.Approximate_Number_To_Find := 10;
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Count = 0, "a blank image: no result");
      --  Unrelated shapes: discs, a rectangle, a triangle.
      TI.Draw_Circle (Image, 120.0, 110.0, 30.0, Foreground);
      TI.Draw_Circle (Image, 500.0, 380.0, 45.0, Foreground);
      TI.Draw_Rectangle (Image, 300.0, 240.0, 90.0, 60.0, 0.3, Foreground);
      TI.Draw_Polygon (Image, [420.0, 60.0, 560.0, 90.0, 470.0, 180.0],
                       Foreground);
      TI.Add_Noise (Image, 10.0, 3);
      Tool.Input_Image := Image;
      Tool.Run;
      Report (Tool, "unrelated");
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Count = 0, "unrelated shapes: no result");
   end Test_No_False_Positives;

   procedure Test_Origin is
      Image : Ks_Image_8_Grey := Scene;
      A     : constant Real := 0.9;
      Tool  : Ks_PM_Align_Tool;
   begin
      Section ("PMAlign: the origin convention");
      Draw_Shape (Image, 310.6, 230.3, A);
      Tool.Input_Image := Image;
      Set_Full_Circle (Tool);

      --  The default Origin: pattern coordinates are the train image's.
      Tool.Pattern.Set_Train_Image (Train_Image);
      Tool.Pattern.Set_Train_Region (Train_Region);
      Tool.Pattern.Train;
      Tool.Run;
      Report (Tool, "default origin");
      Check (Tool.Results.Count = 1, "default origin: found");
      if Tool.Results.Count = 1 then
         declare
            R    : constant Ks_PM_Align_Result := Tool.Results.Item (0);
            Pose : constant Ks_Transform_2D_Linear := Get_Pose (R);
            X, Y : Real;
         begin
            --  The train image's point (100, 100), the shape's reference
            --  point, maps to the drawing position.
            Pose.Map_Point (Train_CX, Train_CY, X, Y);
            Check (abs (X - 310.6) < 0.1 and then abs (Y - 230.3) < 0.1,
                   "default origin: the pose maps the train image's point"
                   & " to the instance's");
            Check (Angle_Error (R.Rotation, A) < 0.1 * Deg,
                   "default origin: the rotation");
            Map ((Disc_X, Disc_Y), 310.6, 230.3, A, 1.0, X, Y);
            declare
               PX, PY : Real;
            begin
               Pose.Map_Point (Train_CX + Disc_X, Train_CY + Disc_Y, PX, PY);
               Check (abs (PX - X) < 0.1 and then abs (PY - Y) < 0.1,
                      "default origin: the disc's centre");
            end;
         end;
      end if;

      --  A custom Origin: at the reference point, turned by 0.3.
      Tool.Pattern.Set_Origin (Create_Rigid (0.3, Train_CX, Train_CY));
      Check (not Tool.Pattern.Trained, "Set_Origin untrains");
      Tool.Pattern.Train;
      Tool.Run;
      Report (Tool, "custom origin");
      Check (Tool.Results.Count = 1, "custom origin: found");
      if Tool.Results.Count = 1 then
         Check_Pose ("custom origin", Tool.Results.Item (0), 310.6, 230.3,
                     A + 0.3, 1.0);
      end if;
   end Test_Origin;

   procedure Test_Failures is
      Tool    : Ks_PM_Align_Tool;
      Pattern : Ks_PM_Align_Pattern;

      procedure Train_Blank;
      procedure Train_Blank is
         P : Ks_PM_Align_Pattern;
      begin
         P.Set_Train_Image (TI.Blank (100, 100, 60));
         P.Train;
      end Train_Blank;
      procedure Check_Blank is new Check_Raises_Exactly
        (Train_Blank, Ks_Bad_Parameter_Exception'Identity);

      procedure Train_Unallocated;
      procedure Train_Unallocated is
         P : Ks_PM_Align_Pattern;
      begin
         P.Train;
      end Train_Unallocated;
      procedure Check_Unallocated is new Check_Raises_Exactly
        (Train_Unallocated, Ks_Image_No_Pixels_Exception'Identity);

      procedure Train_Singular;
      procedure Train_Singular is
         P : Ks_PM_Align_Pattern;
      begin
         P.Set_Train_Image (Train_Image);
         P.Set_Origin (Create (1.0, 2.0, 2.0, 4.0, 0.0, 0.0));
         P.Train;
      end Train_Singular;
      procedure Check_Singular is new Check_Raises_Exactly
        (Train_Singular, Ks_Transform_Singular_Exception'Identity);

      procedure Bad_Grain;
      procedure Bad_Grain is
         P : Ks_PM_Align_Pattern;
      begin
         P.Set_Grain_Limit_Fine (16.0);
      end Bad_Grain;
      procedure Check_Bad_Grain is new Check_Raises_Exactly
        (Bad_Grain, Ks_Bad_Parameter_Exception'Identity);

      procedure Bad_Algorithm;
      procedure Bad_Algorithm is
         P : Ks_PM_Align_Pattern;
      begin
         P.Set_Train_Algorithm (Pat_Flex);
      end Bad_Algorithm;
      procedure Check_Bad_Algorithm is new Check_Raises_Exactly
        (Bad_Algorithm, Ks_Bad_Parameter_Exception'Identity);
   begin
      Section ("PMAlign: failures");
      Tool.Input_Image := Scene;
      Tool.Run;
      Check (Status_Is (Tool, "KS_OPERATOR_NOT_TRAINED_EXCEPTION",
                        "Pattern is not trained"),
             "untrained: Error, Ks_Operator_Not_Trained_Exception");
      Check (Tool.Results.Count = 0, "untrained: no results");

      Tool.Pattern := Trained_Pattern (Algorithm => Pat_Max);
      Tool.Run_Params.Run_Algorithm :=
        Code (Ks_PM_Align_Run_Algorithm_Constants'(Pat_Quick));
      Tool.Run;
      Check (Status_Is (Tool, "KS_OPERATOR_NOT_TRAINED_EXCEPTION",
                        "Pattern is not trained for PatQuick"),
             "PatQuick with a PatMax pattern: not trained");
      Tool.Run_Params.Run_Algorithm :=
        Code (Ks_PM_Align_Run_Algorithm_Constants'(Best_Trained));
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result,
             "BestTrained with a PatMax pattern runs PatMax");

      Tool.Pattern := Shared_Pattern;
      Tool.Run_Params.Accept_Threshold := 1.5;
      Tool.Run;
      Check (Status_Is (Tool, "KS_BAD_PARAMETER_EXCEPTION",
                        "RunParams.AcceptThreshold must be in [0, 1]"),
             "AcceptThreshold 1.5: Error naming the property");
      Tool.Run_Params := (others => <>);
      Tool.Run_Params.Zone_Angle :=
        (Configuration => Code (Low_High), Low => 1.0, High => -1.0,
         Nominal => 0.0);
      Tool.Run;
      Check (Tool.Run_Status.Result = Error
             and then Exception_Name (Tool.Run_Status)
                        = "AMV.KS_BAD_PARAMETER_EXCEPTION",
             "ZoneAngle Low > High: Error");
      Tool.Run_Params := (others => <>);
      Tool.Run_Params.Run_Algorithm :=
        Code (Ks_PM_Align_Run_Algorithm_Constants'(Pat_Flex));
      Tool.Run;
      Check (Tool.Run_Status.Result = Error, "PatFlex: Error");
      Tool.Run_Params := (others => <>);
      Tool.Input_Image := Unallocated;
      Tool.Run;
      Check (Status_Is (Tool, "KS_IMAGE_NO_PIXELS_EXCEPTION",
                        "InputImage has no pixels"),
             "unallocated input: Error");
      Check (Tool.Results.Count = 0, "no results after a failed run");

      Check_Blank ("a blank train image: Ks_Bad_Parameter_Exception");
      Check_Unallocated
        ("an unallocated train image: Ks_Image_No_Pixels_Exception");
      Check_Singular
        ("a singular Origin: Ks_Transform_Singular_Exception");
      Check_Bad_Grain ("GrainLimitFine above GrainLimitCoarse");
      Check_Bad_Algorithm ("TrainAlgorithm PatFlex");

      Pattern := Shared_Pattern;
      Check (Pattern.Trained, "a copy is trained");
      Pattern.Set_Grain_Limit_Coarse (4.0);
      Check (not Pattern.Trained and then Shared_Pattern.Trained,
             "a setter untrains the copy only");
      Pattern.Set_Grain_Limit_Auto_Select (False);
      Pattern.Train;
      Check (Pattern.Trained, "explicit grain limits: trained");
      Pattern.Untrain;
      Check (not Pattern.Trained, "Untrain");
   end Test_Failures;

   procedure Test_Grain_Limits is
      Tool  : Ks_PM_Align_Tool;
      Image : Ks_Image_8_Grey := Scene;
   begin
      Section ("PMAlign: grain limits");
      Draw_Shape (Image, 290.4, 211.7, 0.6);
      Tool.Input_Image := Image;
      Set_Full_Circle (Tool);
      Tool.Pattern := Shared_Pattern;
      Tool.Pattern.Set_Grain_Limit_Auto_Select (False);
      Tool.Pattern.Set_Grain_Limit_Coarse (4.0);
      Tool.Pattern.Set_Grain_Limit_Fine (2.0);
      Tool.Pattern.Train;
      Check (Tool.Pattern.Get_Trained_Features'Length
               < Shared_Pattern.Get_Trained_Features'Length,
             "finest level 1: fewer features");
      Tool.Run;
      Report (Tool, "grain 2 .. 4");
      Check (Tool.Results.Count = 1, "levels 1 .. 2: found");
      if Tool.Results.Count = 1 then
         Check_Pose ("levels 1 .. 2", Tool.Results.Item (0), 290.4, 211.7,
                     0.6, 1.0, 0.2, 0.2 * Deg);
      end if;
      Tool.Pattern.Set_Grain_Limit_Fine (1.0);
      Tool.Pattern.Set_Grain_Limit_Coarse (1.0);
      Tool.Pattern.Train;
      --  A search at full resolution: kept small (region and zone).
      declare
         Region : Ks_Rectangle;
      begin
         Region.Set_Center_Width_Height (290.0, 212.0, 150.0, 150.0);
         Tool.Search_Region := AMV.Shapes.Region_Holders.To_Holder (Region);
      end;
      Tool.Run_Params.Zone_Angle :=
        (Configuration => Code (Low_High), Low => 0.5, High => 0.7,
         Nominal => 0.0);
      Tool.Run;
      Report (Tool, "grain 1");
      Check (Tool.Results.Count = 1, "level 0 alone, a narrow zone: found");
      if Tool.Results.Count = 1 then
         Check_Pose ("level 0 alone", Tool.Results.Item (0), 290.4, 211.7,
                     0.6, 1.0);
      end if;
   end Test_Grain_Limits;

   procedure Test_Region is
      Tool   : Ks_PM_Align_Tool;
      Image  : Ks_Image_8_Grey := Scene;
      Region : Ks_Rectangle;
   begin
      Section ("PMAlign: search region");
      Draw_Shape (Image, 150.4, 150.2, 0.2);
      Draw_Shape (Image, 450.7, 300.1, -0.6);
      Tool.Input_Image := Image;
      Tool.Pattern := Shared_Pattern;
      Set_Full_Circle (Tool);
      Tool.Run_Params.Approximate_Number_To_Find := 4;
      Tool.Run;
      Check (Tool.Results.Count = 2, "whole image: both");
      Region.Set_Center_Width_Height (450.0, 300.0, 160.0, 160.0);
      Tool.Search_Region := AMV.Shapes.Region_Holders.To_Holder (Region);
      Tool.Run;
      Report (Tool, "region");
      Check (Tool.Results.Count = 1, "region: one");
      if Tool.Results.Count = 1 then
         Check_Pose ("region", Tool.Results.Item (0), 450.7, 300.1, -0.6,
                     1.0);
      end if;
      --  A region that cuts the instance: too much of it outside.
      Region.Set_Center_Width_Height (450.0, 300.0, 70.0, 70.0);
      Tool.Search_Region := AMV.Shapes.Region_Holders.To_Holder (Region);
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Count = 0,
             "a region smaller than the instance: none");
      Tool.Run_Params.Outside_Region_Threshold := 1.0;
      Tool.Run_Params.Accept_Threshold := 0.3;
      Tool.Run;
      Check (Tool.Results.Count = 1
             and then Tool.Results.Item (0)
                        .Outside_Region_Feature_Proportion > 0.1,
             "OutsideRegionThreshold 1: found, the proportion reported");
   end Test_Region;

   procedure Test_Fixture is
      A     : constant Real := 1.3;
      Alpha : constant Real := -0.3;
      Fix   : constant Ks_Transform_2D_Linear :=
        Create_Rigid (Alpha, 60.0, 140.0);
      --  Fixture coordinates to pixel coordinates.
      Tree  : Ks_Coordinate_Space_Tree;
      Tool  : Ks_PM_Align_Tool;
      Image : Ks_Image_8_Grey := Scene;
      U, V  : Real;
   begin
      Section ("PMAlign: fixture space on the input");
      Draw_Shape (Image, 333.3, 222.2, A);
      Tree.Add_Space ("@", "Fixture", Fix);
      Image.Set_Coordinate_Space_Tree (Tree);
      Image.Set_Selected_Space_Name ("@\Fixture");
      Tool.Input_Image := Image;
      Tool.Pattern := Shared_Pattern;
      Set_Full_Circle (Tool);
      Tool.Run;
      Report (Tool, "fixture");
      Check (Tool.Results.Count = 1, "fixture: found");
      if Tool.Results.Count = 1 then
         Fix.Invert.Map_Point (333.3, 222.2, U, V);
         Check_Pose ("fixture", Tool.Results.Item (0), U, V, A - Alpha, 1.0);
      end if;

      --  A fixture of 2 pixels per unit: the same instance has scale 0.5.
      Tree.Add_Space ("@", "Fixture", Create_Similarity (2.0, Alpha, 60.0,
                                                          140.0));
      Image.Set_Coordinate_Space_Tree (Tree);
      Tool.Input_Image := Image;
      Tool.Run_Params.Zone_Scale.Nominal := 0.5;
      Tool.Run;
      Report (Tool, "scaled fixture");
      Check (Tool.Results.Count = 1, "scaled fixture: found");
      if Tool.Results.Count = 1 then
         Create_Similarity (2.0, Alpha, 60.0, 140.0).Invert.Map_Point
           (333.3, 222.2, U, V);
         Check_Pose ("scaled fixture", Tool.Results.Item (0), U, V,
                     A - Alpha, 0.5, 0.05);
      end if;
   end Test_Fixture;

   procedure Test_Train_Space is
      Image : Ks_Image_8_Grey := Train_Image;
      Tree  : Ks_Coordinate_Space_Tree;
      Scene_Image : Ks_Image_8_Grey := Scene;
      Tool  : Ks_PM_Align_Tool;
      Region : Ks_Rectangle;
   begin
      Section ("PMAlign: a train image in millimetres");
      --  The train image's selected space: millimetres, 2 pixels each.
      Tree.Add_Space ("@", "Mm", Create_Similarity (2.0, 0.0, 0.0, 0.0));
      Image.Set_Coordinate_Space_Tree (Tree);
      Image.Set_Selected_Space_Name ("@\Mm");
      Region.Set_Center_Width_Height (Train_CX / 2.0, Train_CY / 2.0 + 1.0,
                                      55.0, 48.0);
      Tool.Pattern.Set_Train_Image (Image);
      Tool.Pattern.Set_Train_Region
        (AMV.Shapes.Region_Holders.To_Holder (Region));
      Tool.Pattern.Set_Origin
        (Create_Rigid (0.0, Train_CX / 2.0, Train_CY / 2.0));
      Tool.Pattern.Train;
      Check (Tool.Pattern.Trained, "trained in millimetres");
      --  The features are in millimetres: the L spans 78 pixels, 39 mm.
      declare
         Low, High : Real := 0.0;
      begin
         for F of Tool.Pattern.Get_Trained_Features loop
            Low := Real'Min (Low, F.X);
            High := Real'Max (High, F.X);
         end loop;
         Check (High - Low > 37.0 and then High - Low < 41.0,
                "features in millimetres");
      end;
      --  A scene in pixels: the pose maps millimetres to pixels, scale 2.
      Draw_Shape (Scene_Image, 301.7, 244.1, -0.9);
      Tool.Input_Image := Scene_Image;
      Set_Full_Circle (Tool);
      Tool.Run_Params.Zone_Scale.Nominal := 2.0;
      Tool.Run;
      Report (Tool, "millimetres");
      Check (Tool.Results.Count = 1, "millimetres: found");
      if Tool.Results.Count = 1 then
         Check_Pose ("millimetres", Tool.Results.Item (0), 301.7, 244.1,
                     -0.9, 2.0);
      end if;
   end Test_Train_Space;

   procedure Test_Chain is
      A     : constant Real := -2.4;
      Image : Ks_Image_8_Grey := Scene;
      Tool  : Ks_PM_Align_Tool;
      Tree  : Ks_Coordinate_Space_Tree;
      X, Y  : Real;
      PX, PY : Real;
   begin
      Section ("PMAlign: pose -> fixture");
      Draw_Shape (Image, 287.9, 199.4, A);
      Tool.Input_Image := Image;
      Tool.Pattern := Shared_Pattern;
      Set_Full_Circle (Tool);
      Tool.Run;
      Check (Tool.Results.Count = 1, "found");
      if Tool.Results.Count = 1 then
         --  What a fixture tool does with the pose: a child space of the
         --  selected space, with the pose as its Parent_From_New.
         Tree := Image.Get_Coordinate_Space_Tree;
         Tree.Add_Space ("@", "Part", Get_Pose (Tool.Results.Item (0)));
         Image.Set_Coordinate_Space_Tree (Tree);
         --  The disc's centre, given in the part's (the pattern's)
         --  coordinates, lands on the drawn disc.
         Image.Get_Transform ("#", "@\Part").Map_Point (Disc_X, Disc_Y, PX,
                                                       PY);
         Map ((Disc_X, Disc_Y), 287.9, 199.4, A, 1.0, X, Y);
         Check (abs (PX - X) < 0.1 and then abs (PY - Y) < 0.1,
                "the disc's centre through the fixture");
         Image.Get_Transform ("#", "@\Part").Map_Point (L_Shape (2).X,
                                                       L_Shape (2).Y, PX, PY);
         Map (L_Shape (2), 287.9, 199.4, A, 1.0, X, Y);
         Check (abs (PX - X) < 0.1 and then abs (PY - Y) < 0.1,
                "a corner of the L through the fixture");
      end if;
   end Test_Chain;

   procedure Test_Self_Match
     (Description : String;
      Image       : Ks_Image_8_Grey;
      CX, CY      : Real);
   --  Trains a pattern on the whole of Image (origin at (CX, CY)) and finds
   --  it in Image itself: it must be found at (CX, CY) with a score close
   --  to 1, no edge of the pattern counting as clutter.

   procedure Test_Self_Match
     (Description : String;
      Image       : Ks_Image_8_Grey;
      CX, CY      : Real)
   is
      Tool : Ks_PM_Align_Tool;
   begin
      Tool.Pattern.Set_Train_Image (Image);
      Tool.Pattern.Set_Origin (Create_Rigid (0.0, CX, CY));
      Tool.Pattern.Train;
      Tool.Input_Image := Image;
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Count = 1,
             Description & ": found");
      if Tool.Results.Count = 1 then
         declare
            R : constant Ks_PM_Align_Result := Tool.Results.Item (0);
         begin
            Check_Near (R.Translation_X, CX, 0.1, Description & ": x");
            Check_Near (R.Translation_Y, CY, 0.1, Description & ": y");
            Check (R.Clutter <= 0.02,
                   Description & ": clutter <= 0.02 (clutter"
                   & Integer (R.Clutter * 1000.0)'Image & "e-3)");
            Check (R.Score >= 0.97,
                   Description & ": score >= 0.97 (score"
                   & Integer (R.Score * 1000.0)'Image & "e-3)");
         end;
      end if;
   end Test_Self_Match;

   procedure Draw_Texture
     (Image          : in out Ks_Image_8_Grey;
      X0, Y0, X1, Y1 : Natural;
      Seed           : Natural);
   --  Adds a coarse random texture to the pixels X0 .. X1, Y0 .. Y1: blocks
   --  of 3 x 3 pixels each moved by -70 or +70 grey levels (a linear
   --  congruential generator seeded by Seed), clamped to 0 .. 255.

   procedure Draw_Texture
     (Image          : in out Ks_Image_8_Grey;
      X0, Y0, X1, Y1 : Natural;
      Seed           : Natural)
   is
      State : Natural := Seed mod 2 ** 20;
   begin
      for BY in 0 .. (Y1 - Y0) / 3 loop
         for BX in 0 .. (X1 - X0) / 3 loop
            State := (State * 1103 + 12345) mod 2 ** 20;
            declare
               Delta_Grey : constant Integer :=
                 (if State / 2 ** 19 = 1 then 70 else -70);
            begin
               for Y in Y0 + 3 * BY .. Natural'Min (Y1, Y0 + 3 * BY + 2) loop
                  for X in X0 + 3 * BX .. Natural'Min (X1, X0 + 3 * BX + 2)
                  loop
                     Image.Set_Pixel
                       (X, Y,
                        Grey_8 (Integer'Max
                                  (0, Integer'Min
                                        (255, Integer (Image.Get_Pixel (X, Y))
                                              + Delta_Grey))));
                  end loop;
               end loop;
            end;
         end loop;
      end loop;
   end Draw_Texture;

   procedure Test_Automatic_Grain is
      --  A part whose surface carries a fine random texture that differs
      --  from part to part (as the wire mesh, the lettering and the grain
      --  of real parts do): trained on one part, searched on another. At
      --  the finest level most features are the texture's, which does not
      --  match; one level up they are the outline's.
      Train : Ks_Image_8_Grey := TI.Blank (400, 300, 60);
      Image : Ks_Image_8_Grey := TI.Blank (400, 300, 60);
      Tool  : Ks_PM_Align_Tool;
      DX    : constant Real := 17.3;
      DY    : constant Real := -9.6;
   begin
      Section ("PMAlign: automatic grain on a textured part");
      TI.Draw_Rectangle (Train, 200.0, 150.0, 220.0, 150.0, 0.0, 170);
      TI.Draw_Circle (Train, 140.0, 110.0, 25.0, 60);
      Draw_Texture (Train, 92, 77, 307, 222, 7);
      TI.Draw_Rectangle (Image, 200.0 + DX, 150.0 + DY, 220.0, 150.0, 0.0,
                         170);
      TI.Draw_Circle (Image, 140.0 + DX, 110.0 + DY, 25.0, 60);
      Draw_Texture (Image, 92 + 17, 77 - 10, 307 + 17, 222 - 10, 911);
      Tool.Pattern.Set_Train_Image (Train);
      Tool.Pattern.Set_Origin (Create_Rigid (0.0, 200.0, 150.0));
      Tool.Input_Image := Image;

      --  The finest grain forced: the texture's features do not match.
      Tool.Pattern.Set_Grain_Limit_Auto_Select (False);
      Tool.Pattern.Set_Grain_Limit_Fine (1.0);
      Tool.Pattern.Set_Grain_Limit_Coarse (16.0);
      Tool.Pattern.Train;
      Tool.Run;
      Report (Tool, "grain 1 .. 16");
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Count = 0,
             "grain limits 1 .. 16: the textured part is not found");

      --  The automatic grain: found, measured one level up or more.
      Tool.Pattern.Set_Grain_Limit_Auto_Select (True);
      Tool.Pattern.Train;
      Tool.Run;
      Report (Tool, "automatic grain");
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Count = 1,
             "automatic grain: the textured part is found");
      if Tool.Results.Count = 1 then
         Check_Pose ("automatic grain", Tool.Results.Item (0),
                     200.0 + DX, 150.0 + DY, 0.0, 1.0, 0.5, 0.2 * Deg);
      end if;
   end Test_Automatic_Grain;

   procedure Test_Train_Mask is
      --  A part with a label whose print differs from part to part (a
      --  coarse random texture): trained on one part, searched on another.
      --  The mask leaves the label out (0 in the label and 2 pixels around
      --  it, 255 elsewhere).
      DX : constant Real := 17.3;
      DY : constant Real := -9.6;

      function Part (X0, Y0 : Real; Seed : Natural) return Ks_Image_8_Grey;
      function Part (X0, Y0 : Real; Seed : Natural) return Ks_Image_8_Grey
      is
         XL : constant Natural := Natural (Real'Floor (X0)) + 30;
         YL : constant Natural := Natural (Real'Floor (Y0)) + 10;
      begin
         return Image : Ks_Image_8_Grey := TI.Blank (400, 300, 60) do
            TI.Draw_Rectangle (Image, X0, Y0, 220.0, 150.0, 0.0, 170);
            TI.Draw_Circle (Image, X0 - 60.0, Y0 - 40.0, 25.0, 60);
            if Seed > 0 then
               Draw_Texture (Image, XL, YL, XL + 60, YL + 40, Seed);
            end if;
         end return;
      end Part;

      Train : constant Ks_Image_8_Grey := Part (200.0, 150.0, 7);
      Full  : Ks_Image_8_Grey := TI.Blank (400, 300, 255);
      Small : Ks_Image_8_Grey := TI.Blank (80, 60, 255);
      Plain_Tool, Masked_Tool : Ks_PM_Align_Tool;
      Offset_Pattern : Ks_PM_Align_Pattern;
      Inside_Plain, Inside_Masked : Natural := 0;
      Textured, Blank_Label : Real := 0.0;
   begin
      Section ("PMAlign: the train image mask");
      for Y in 158 .. 202 loop
         for X in 228 .. 292 loop
            Full.Set_Pixel (X, Y, 0);
            Small.Set_Pixel (X - 220, Y - 150, 0);
         end loop;
      end loop;

      Plain_Tool.Pattern.Set_Train_Image (Train);
      Plain_Tool.Pattern.Set_Origin (Create_Rigid (0.0, 200.0, 150.0));
      Plain_Tool.Pattern.Train;
      Masked_Tool.Pattern := Plain_Tool.Pattern;
      Masked_Tool.Pattern.Set_Train_Image_Mask (Full);
      Check (not Masked_Tool.Pattern.Trained,
             "setting the mask untrains the pattern");
      Masked_Tool.Pattern.Train;

      --  The features: none in the label with the mask.
      for F of Plain_Tool.Pattern.Get_Trained_Features loop
         if F.X in 28.0 .. 92.0 and then F.Y in 8.0 .. 52.0 then
            Inside_Plain := Inside_Plain + 1;
         end if;
      end loop;
      for Fine in Boolean loop
         for F of Masked_Tool.Pattern.Get_Trained_Features (Fine) loop
            if F.X in 28.0 .. 92.0 and then F.Y in 8.0 .. 52.0 then
               Inside_Masked := Inside_Masked + 1;
            end if;
         end loop;
      end loop;
      Check (Inside_Plain > 20,
             "without the mask the label gives features:"
             & Inside_Plain'Image);
      Check (Inside_Masked = 0,
             "with the mask no feature lies in the label, at any level:"
             & Inside_Masked'Image);

      --  A smaller mask placed by the offsets gives the same model.
      Offset_Pattern := Plain_Tool.Pattern;
      Offset_Pattern.Set_Train_Image_Mask (Small);
      Offset_Pattern.Set_Train_Image_Mask_Offset_X (220);
      Offset_Pattern.Set_Train_Image_Mask_Offset_Y (150);
      Check (Offset_Pattern.Train_Image_Mask_Offset_X = 220
             and then Offset_Pattern.Train_Image_Mask_Offset_Y = 150
             and then Offset_Pattern.Train_Image_Mask.Width = 80,
             "the mask and its offsets");
      Offset_Pattern.Train;
      Check (Offset_Pattern.Get_Trained_Features
               = Masked_Tool.Pattern.Get_Trained_Features
             and then Offset_Pattern.Get_Trained_Features (False)
                        = Masked_Tool.Pattern.Get_Trained_Features (False),
             "a mask of the label's size at offsets (220, 150): the same"
             & " features");
      Offset_Pattern.Set_Train_Image_Mask_Offset_X (0);
      Check (not Offset_Pattern.Trained,
             "setting an offset untrains the pattern");

      --  Another part, its label printed differently.
      Plain_Tool.Input_Image := Part (200.0 + DX, 150.0 + DY, 911);
      Masked_Tool.Input_Image := Plain_Tool.Input_Image;
      Plain_Tool.Run;
      Masked_Tool.Run;
      Report (Plain_Tool, "no mask");
      Report (Masked_Tool, "mask");
      Check (Masked_Tool.Run_Status.Result = Accept_Result
             and then Masked_Tool.Results.Count = 1,
             "with the mask the other part is found");
      if Masked_Tool.Results.Count = 1 then
         Check_Pose ("with the mask", Masked_Tool.Results.Item (0),
                     200.0 + DX, 150.0 + DY, 0.0, 1.0, 0.2, 0.1 * Deg);
         Textured := Masked_Tool.Results.Item (0).Clutter;
         Ada.Text_IO.Put_Line
           ("  mask: score" & Masked_Tool.Results.Item (0).Score'Image
            & ", clutter" & Textured'Image);
         if Plain_Tool.Results.Count = 1 then
            Ada.Text_IO.Put_Line
              ("  no mask: score" & Plain_Tool.Results.Item (0).Score'Image
               & ", clutter" & Plain_Tool.Results.Item (0).Clutter'Image);
            Check (Masked_Tool.Results.Item (0).Score
                     > Plain_Tool.Results.Item (0).Score + 0.1,
                   "the mask raises the score");
         end if;
      end if;

      --  The label's print is not counted as clutter: the same part with a
      --  blank label gives about the same clutter.
      Masked_Tool.Input_Image := Part (200.0 + DX, 150.0 + DY, 0);
      Masked_Tool.Run;
      if Masked_Tool.Results.Count = 1 then
         Blank_Label := Masked_Tool.Results.Item (0).Clutter;
      end if;
      Check (Masked_Tool.Results.Count = 1
             and then abs (Textured - Blank_Label) < 0.02,
             "the clutter of a printed label (" & Textured'Image
             & ") and a blank one (" & Blank_Label'Image & ")");
   end Test_Train_Mask;

   procedure Test_Thinning is
      Board   : Ks_Image_8_Grey := TI.Blank (400, 300, 0);
      Striped : Ks_Image_8_Grey := TI.Blank (300, 200, 0);
   begin
      Section ("PMAlign: thinned and textured patterns");

      --  About 12000 edge pixels, more than Max_Features (2048): the
      --  features are thinned, and every edge must stay near one of them.
      TI.Checkerboard (Board, 7.3, 5.1, 20.0);
      Test_Self_Match ("checkerboard", Board, 200.0, 150.0);

      --  A strong outline with faint stripes inside, weaker than the
      --  train threshold (a fifth of the strongest edge) but above the run
      --  ContrastThreshold: they are not trained, so they must not count
      --  as clutter either.
      TI.Draw_Rectangle (Striped, 150.0, 100.0, 180.0, 120.0, 0.0, 255);
      for K in 0 .. 9 loop
         TI.Draw_Rectangle
           (Striped, 72.0 + 16.0 * Real (K), 100.0, 8.0, 110.0, 0.0, 215);
      end loop;
      Test_Self_Match ("faint stripes", Striped, 150.0, 100.0);
   end Test_Thinning;

   procedure Test_Stream is
      Buffer : aliased Ada.Streams.Storage.Unbounded.Stream_Type;
      Copy   : Ks_PM_Align_Pattern;
      Tool_A : Ks_PM_Align_Tool;
      Tool_B : Ks_PM_Align_Tool;
      Image  : Ks_Image_8_Grey := Scene;

      procedure Write_Prefix
        (Stream : not null access Ada.Streams.Root_Stream_Type'Class);
      --  The train image, region and origin of a pattern.

      procedure Write_Prefix
        (Stream : not null access Ada.Streams.Root_Stream_Type'Class) is
      begin
         Ks_Image_8_Grey'Write (Stream, Train_Image);
         AMV.Shapes.Region_Holders.Holder'Write (Stream, Train_Region);
         Ks_Transform_2D_Linear'Write (Stream, Identity);
      end Write_Prefix;

      Target : Ks_PM_Align_Pattern := Shared_Pattern;

      procedure Read_Bad_Code;
      procedure Read_Bad_Code is
         Bad : aliased Ada.Streams.Storage.Unbounded.Stream_Type;
      begin
         Write_Prefix (Bad'Access);
         Interfaces.Unsigned_32'Write (Bad'Access, 12345);
         Ks_PM_Align_Pattern'Read (Bad'Access, Target);
      end Read_Bad_Code;
      procedure Check_Bad_Code is new Check_Raises_Exactly
        (Read_Bad_Code, Ks_Image_File_Exception'Identity);

      procedure Write_Model_Start
        (Stream  : not null access Ada.Streams.Root_Stream_Type'Class;
         Count   : Interfaces.Unsigned_32;
         Spacing : Interfaces.Unsigned_32 := 1;
         Code    : Interfaces.Unsigned_32 := KP.Stream_Code);
      --  A trained model of one level (0) of that spacing, with Count
      --  features to follow.

      procedure Write_Model_Start
        (Stream  : not null access Ada.Streams.Root_Stream_Type'Class;
         Count   : Interfaces.Unsigned_32;
         Spacing : Interfaces.Unsigned_32 := 1;
         Code    : Interfaces.Unsigned_32 := KP.Stream_Code) is
      begin
         Write_Prefix (Stream);
         Interfaces.Unsigned_32'Write (Stream, Code);
         K.Int32'Write (Stream, 0);
         K.Int32'Write (Stream, 1);
         K.Int32'Write (Stream, 0);
         Real'Write (Stream, 8.0);
         Real'Write (Stream, 1.0);
         K.Int32'Write (Stream, 1);
         K.Int32'Write (Stream, 0);
         K.Int32'Write (Stream, 0);
         Interfaces.Unsigned_32'Write (Stream, Spacing);
         Interfaces.Unsigned_32'Write (Stream, Count);
      end Write_Model_Start;

      Bad_Spacing : Interfaces.Unsigned_32;

      procedure Read_Bad_Spacing;
      procedure Read_Bad_Spacing is
         Bad    : aliased Ada.Streams.Storage.Unbounded.Stream_Type;
         Target : Ks_PM_Align_Pattern;
      begin
         Write_Model_Start (Bad'Access, 10, Spacing => Bad_Spacing);
         Ks_PM_Align_Pattern'Read (Bad'Access, Target);
      end Read_Bad_Spacing;
      procedure Check_Bad_Spacing is new Check_Raises_Exactly
        (Read_Bad_Spacing, Ks_Image_File_Exception'Identity);

      procedure Read_Old_Format;
      procedure Read_Old_Format is
         Bad    : aliased Ada.Streams.Storage.Unbounded.Stream_Type;
         Target : Ks_PM_Align_Pattern;
      begin
         --  "KSPA": the format before the levels carried their spacing.
         Write_Model_Start (Bad'Access, 10, Code => 16#4B53_5041#);
         Ks_PM_Align_Pattern'Read (Bad'Access, Target);
      end Read_Old_Format;
      procedure Check_Old_Format is new Check_Raises_Exactly
        (Read_Old_Format, Ks_Image_File_Exception'Identity);

      procedure Read_NaN_Feature;
      procedure Read_NaN_Feature is
         Bad    : aliased Ada.Streams.Storage.Unbounded.Stream_Type;
         Target : Ks_PM_Align_Pattern;
      begin
         Write_Model_Start (Bad'Access, 10);
         Real'Write (Bad'Access, Zero / Zero);
         Real'Write (Bad'Access, 1.0);
         Real'Write (Bad'Access, 1.0);
         Real'Write (Bad'Access, 0.0);
         Ks_PM_Align_Pattern'Read (Bad'Access, Target);
      end Read_NaN_Feature;
      procedure Check_NaN_Feature is new Check_Raises_Exactly
        (Read_NaN_Feature, Ks_Image_File_Exception'Identity);

      procedure Write_Features
        (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
         Count  : Positive);
      --  Count valid features, on a line.

      procedure Write_Features
        (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
         Count  : Positive) is
      begin
         for I in 1 .. Count loop
            Real'Write (Stream, Real (I));
            Real'Write (Stream, 0.0);
            Real'Write (Stream, 0.0);
            Real'Write (Stream, 1.0);
         end loop;
      end Write_Features;

      Previous : Ks_PM_Align_Pattern;

      procedure Read_Previous_Format;
      procedure Read_Previous_Format is
         Old : aliased Ada.Streams.Storage.Unbounded.Stream_Type;
      begin
         --  "KSPB": the format before the train image mask.
         Write_Model_Start (Old'Access, 10);
         Write_Features (Old'Access, 10);
         Ks_PM_Align_Pattern'Read (Old'Access, Previous);
      end Read_Previous_Format;

      Bad_Ignored_Spacing : Interfaces.Unsigned_32;

      procedure Read_Bad_Ignored;
      procedure Read_Bad_Ignored is
         Bad    : aliased Ada.Streams.Storage.Unbounded.Stream_Type;
         Target : Ks_PM_Align_Pattern;
      begin
         Write_Model_Start (Bad'Access, 10, Code => KP.Stream_Code_Masked);
         Write_Features (Bad'Access, 10);
         Interfaces.Unsigned_32'Write (Bad'Access, Bad_Ignored_Spacing);
         Interfaces.Unsigned_32'Write (Bad'Access, 1);
         Real'Write (Bad'Access, Zero / Zero);
         Real'Write (Bad'Access, 0.0);
         Ks_PM_Align_Pattern'Read (Bad'Access, Target);
      end Read_Bad_Ignored;
      procedure Check_Bad_Ignored is new Check_Raises_Exactly
        (Read_Bad_Ignored, Ks_Image_File_Exception'Identity);

      procedure Read_Huge_Count;
      procedure Read_Huge_Count is
         Bad    : aliased Ada.Streams.Storage.Unbounded.Stream_Type;
         Target : Ks_PM_Align_Pattern;
      begin
         Write_Model_Start (Bad'Access, 1_000_000);
         Ks_PM_Align_Pattern'Read (Bad'Access, Target);
      end Read_Huge_Count;
      procedure Check_Huge_Count is new Check_Raises_Exactly
        (Read_Huge_Count, Ks_Image_File_Exception'Identity);
   begin
      Section ("PMAlign: streams");
      Ks_PM_Align_Pattern'Write (Buffer'Access, Shared_Pattern);
      Ks_PM_Align_Pattern'Read (Buffer'Access, Copy);
      Check (Copy.Trained, "the pattern read is trained");
      Check (Copy.Get_Trained_Features = Shared_Pattern.Get_Trained_Features
             and then Copy.Get_Trained_Features (False)
                        = Shared_Pattern.Get_Trained_Features (False),
             "the same features");
      Check (Copy.Train_Algorithm = Shared_Pattern.Train_Algorithm
             and then Copy.Grain_Limit_Coarse
                        = Shared_Pattern.Grain_Limit_Coarse,
             "the same train parameters");
      Draw_Shape (Image, 301.2, 233.9, -0.4);
      Tool_A.Input_Image := Image;
      Tool_A.Pattern := Shared_Pattern;
      Set_Full_Circle (Tool_A);
      Tool_B := Tool_A;
      Tool_B.Pattern := Copy;
      Tool_A.Run;
      Tool_B.Run;
      Check (Tool_A.Results.Count = 1 and then Tool_B.Results.Count = 1
             and then Tool_A.Results.Item (0) = Tool_B.Results.Item (0),
             "the pattern read finds the same result");
      Check_Bad_Code ("a wrong format code: Ks_Image_File_Exception");
      Check (Target.Trained
             and then Target.Get_Trained_Features
                        = Shared_Pattern.Get_Trained_Features,
             "a malformed stream leaves it as it was (trained)");
      Check_NaN_Feature ("a NaN feature: Ks_Image_File_Exception");
      Check_Huge_Count ("a huge feature count: Ks_Image_File_Exception");
      Bad_Spacing := 0;
      Check_Bad_Spacing ("a spacing of 0: Ks_Image_File_Exception");
      Bad_Spacing := 17;
      Check_Bad_Spacing ("a spacing of 17: Ks_Image_File_Exception");
      Check_Old_Format ("the format before spacing (KSPA):"
                        & " Ks_Image_File_Exception");
      Bad_Ignored_Spacing := 0;
      Check_Bad_Ignored ("an ignored point spacing of 0:"
                         & " Ks_Image_File_Exception");
      Bad_Ignored_Spacing := 1;
      Check_Bad_Ignored ("a NaN ignored point: Ks_Image_File_Exception");
      Read_Previous_Format;
      Check (Previous.Trained and then not Previous.Train_Image_Mask.Allocated
             and then Previous.Get_Trained_Features'Length = 10,
             "the format before the mask (KSPB) is read: trained, no mask");

      --  A pattern trained with a mask (over the disc, by a 40 x 40 mask
      --  at (100, 100)) keeps its mask, offsets and model.
      declare
         Masked_Buffer : aliased Ada.Streams.Storage.Unbounded.Stream_Type;
         Masked        : Ks_PM_Align_Pattern := Shared_Pattern;
         Masked_Copy   : Ks_PM_Align_Pattern;
         Mask          : Ks_Image_8_Grey := TI.Blank (40, 40, 255);
      begin
         for Y in 3 .. 33 loop
            for X in 3 .. 33 loop
               Mask.Set_Pixel (X, Y, 0);
            end loop;
         end loop;
         Masked.Set_Train_Image_Mask (Mask);
         Masked.Set_Train_Image_Mask_Offset_X (100);
         Masked.Set_Train_Image_Mask_Offset_Y (100);
         Masked.Train;
         Check (Masked.Get_Trained_Features'Length
                  < Shared_Pattern.Get_Trained_Features'Length,
                "the mask removes the disc's features");
         Ks_PM_Align_Pattern'Write (Masked_Buffer'Access, Masked);
         Ks_PM_Align_Pattern'Read (Masked_Buffer'Access, Masked_Copy);
         Check (Masked_Copy.Trained
                and then Masked_Copy.Get_Trained_Features
                           = Masked.Get_Trained_Features
                and then Masked_Copy.Train_Image_Mask.Width = 40
                and then Masked_Copy.Train_Image_Mask.Get_Pixel (10, 10) = 0
                and then Masked_Copy.Train_Image_Mask.Get_Pixel (1, 1) = 255
                and then Masked_Copy.Train_Image_Mask_Offset_X = 100
                and then Masked_Copy.Train_Image_Mask_Offset_Y = 100,
                "a masked pattern read back: its model, mask and offsets");
         Tool_A.Pattern := Masked;
         Tool_B.Pattern := Masked_Copy;
         Tool_A.Run;
         Tool_B.Run;
         Check (Tool_A.Results.Count = 1 and then Tool_B.Results.Count = 1
                and then Tool_A.Results.Item (0) = Tool_B.Results.Item (0),
                "the masked pattern read finds the same result (with the"
                & " same clutter)");
         Masked_Copy.Train;
         Check (Masked_Copy.Get_Trained_Features (False)
                  = Masked.Get_Trained_Features (False),
                "trained again from what was read: the same model");
      end;
   end Test_Stream;

   procedure Test_Kernel is
      Image   : constant Ks_Image_8_Grey := Train_Image;
      Handle  : constant access constant KI.Ks_Image_8_Grey_Data :=
        AMV.Images.Kernel_Images.Kernel_Handle (Image);
      Region  : constant AMV.Regions.Pixel_Region :=
        AMV.Regions.Rasterize (Image, Train_Region);
      Region_Handle : constant access constant KR.Ks_Pixel_Region_Data :=
        AMV.Regions.Kernel_Regions.Kernel_Handle (Region);
      Identity_T : constant KT.Ks_Transform_2D_Linear := (others => <>);
      Origin_T   : constant KT.Ks_Transform_2D_Linear :=
        (Translation_X => Train_CX, Translation_Y => Train_CY,
         others => <>);
      NaN        : constant Real := Zero / Zero;
      Pattern  : KP.Ks_PM_Align_Pattern;
      Copy     : KP.Ks_PM_Align_Pattern;
      Results  : KP.Ks_PM_Align_Results;
      Status   : K.Ks_Status;
      Flag     : K.Int32;
      Count    : K.Int32;
      Finest   : K.Int32;
      Coarsest : K.Int32;
      First    : K.Int32;
      Last     : K.Int32;
      Train    : KP.Ks_PM_Align_Train_Params;
      Params   : constant KP.Ks_PM_Align_Run_Params := (others => <>);
      Item     : KP.Ks_PM_Align_Result;
      Feature  : KP.Ks_PM_Align_Feature;
      Pose     : KT.Ks_Transform_2D_Linear;
      Spacing_Read : Interfaces.Unsigned_32;

      function Message_Is (Text : String) return Boolean is
        (Integer (Status.Length) = Text'Length
         and then String (Status.Message (1 .. Text'Length)) = Text);

      procedure Expect_Bad_Run
        (P           : KP.Ks_PM_Align_Run_Params;
         Description : String);

      procedure Expect_Bad_Run
        (P           : KP.Ks_PM_Align_Run_Params;
         Description : String) is
      begin
         KP.Execute (Handle, Region_Handle, Identity_T, Pattern, P, Results,
                     Status);
         Check (Status.Failure = K.Failure_Bad_Parameter
                and then Results = null, Description);
         KP.Check_Run_Params (P, Status);
         Check (Status.Failure = K.Failure_Bad_Parameter,
                Description & " (check_run_params)");
      end Expect_Bad_Run;
   begin
      Section ("PMAlign: kernel");
      --  A null pattern reads as an untrained one with the defaults.
      KP.Pattern_Trained (null, Flag, Status);
      Check (K.Succeeded (Status) and then Flag = 0, "trained (null) = 0");
      KP.Pattern_Get_Train_Params (null, Train, Status);
      Check (K.Succeeded (Status) and then Train = (others => <>),
             "train params (null) = defaults");
      KP.Pattern_Levels (null, Finest, Coarsest, Status);
      Check (Status.Failure = K.Failure_Operator_Not_Trained,
             "levels (null): not trained");
      KP.Pattern_Set_Train_Params (null, Train, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter,
             "set train params (null): bad parameter");
      KP.Pattern_Train (null, Handle, Region_Handle, Identity_T, Origin_T,
                        Status);
      Check (Status.Failure = K.Failure_Bad_Parameter,
             "train (null): bad parameter");
      KP.Pattern_Untrain (null, Status);
      Check (K.Succeeded (Status), "untrain (null)");
      KP.Pattern_Duplicate (null, Copy, Status);
      Check (K.Succeeded (Status) and then Copy = null,
             "duplicate (null) = null");
      KP.Execute (Handle, Region_Handle, Identity_T, null, Params, Results,
                  Status);
      Check (Status.Failure = K.Failure_Operator_Not_Trained
             and then Results = null
             and then Message_Is ("Pattern is not trained"),
             "execute (null pattern): not trained, no results");

      KP.Pattern_Create (Pattern, Status);
      Check (K.Succeeded (Status) and then Pattern /= null, "create");
      KP.Execute (Handle, Region_Handle, Identity_T, Pattern, Params,
                  Results, Status);
      Check (Status.Failure = K.Failure_Operator_Not_Trained
             and then Results = null, "execute (untrained): not trained");

      --  Training failures.
      KP.Pattern_Train (Pattern, null, Region_Handle, Identity_T, Origin_T,
                        Status);
      Check (Status.Failure = K.Failure_Image_No_Pixels,
             "train (null image): no pixels");
      KP.Pattern_Train (Pattern, Handle, null, Identity_T, Origin_T, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter,
             "train (null region): bad parameter");
      KP.Pattern_Train (Pattern, Handle, Region_Handle, Identity_T,
                        (Origin_T with delta A => NaN), Status);
      Check (Status.Failure = K.Failure_Bad_Parameter,
             "train (NaN origin): bad parameter");
      KP.Pattern_Train (Pattern, Handle, Region_Handle,
                        (Identity_T with delta D => 0.0), Origin_T, Status);
      Check (Status.Failure = K.Failure_Transform_Singular,
             "train (singular selected space): singular");
      KP.Pattern_Trained (Pattern, Flag, Status);
      Check (Flag = 0, "failed trains leave it untrained");

      KP.Pattern_Train (Pattern, Handle, Region_Handle, Identity_T, Origin_T,
                        Status);
      Check (K.Succeeded (Status), "train");
      KP.Pattern_Levels (Pattern, Finest, Coarsest, Status);
      Check (K.Succeeded (Status) and then Finest = 0 and then Coarsest >= 1,
             "levels");
      KP.Pattern_Feature_Count (Pattern, 7, Count, Status);
      Check (Status.Failure = K.Failure_Index_Out_Of_Range,
             "feature count (level 7): out of range");
      KP.Pattern_Feature_Count (Pattern, 5, Count, Status);
      Check (K.Succeeded (Status) and then Count = 0,
             "feature count (level 5, unused): 0");
      KP.Pattern_Feature_Count (Pattern, 0, Count, Status);
      Check (K.Succeeded (Status) and then Count >= 8, "feature count");
      KP.Pattern_Feature (Pattern, 0, Count, Feature, Status);
      Check (Status.Failure = K.Failure_Index_Out_Of_Range,
             "feature (Count): out of range");
      KP.Pattern_Feature (Pattern, 0, 0, Feature, Status);
      Check (K.Succeeded (Status), "feature (0)");
      KP.Level_Ignored (Pattern, 0, Spacing_Read, Flag, Status);
      Check (K.Succeeded (Status) and then Flag = 0,
             "no ignored points without a mask");

      --  Trained with a null mask: the same model; with a mask over the
      --  disc (pixels 105 .. 131): fewer features and ignored points.
      KP.Pattern_Create (Copy, Status);
      KP.Pattern_Train_Masked (Copy, Handle, Region_Handle, Identity_T,
                               Origin_T, null, 7, 9, Status);
      Check (K.Succeeded (Status) and then Copy.all = Pattern.all,
             "train_masked with a null mask: the same model");
      declare
         Mask : Ks_Image_8_Grey := TI.Blank (200, 200, 255);
         Masked_Count, Ignored : K.Int32;
         X, Y : Real;
      begin
         for Y in 105 .. 131 loop
            for X in 105 .. 131 loop
               Mask.Set_Pixel (X, Y, 0);
            end loop;
         end loop;
         KP.Pattern_Train_Masked
           (Copy, Handle, Region_Handle, Identity_T, Origin_T,
            AMV.Images.Kernel_Images.Kernel_Handle (Mask), 0, 0, Status);
         KP.Pattern_Feature_Count (Copy, 0, Masked_Count, Status);
         KP.Level_Ignored (Copy, 0, Spacing_Read, Ignored, Status);
         Check (K.Succeeded (Status) and then Masked_Count < Count
                and then Ignored > 0,
                "train_masked: fewer features," & Ignored'Image
                & " ignored points");
         KP.Pattern_Ignored_Point (Copy, 0, 0, X, Y, Status);
         Check (K.Succeeded (Status)
                and then X in 0.0 .. 40.0 and then Y in 0.0 .. 40.0,
                "the first ignored point lies in the masked part"
                & X'Image & Y'Image);
         KP.Pattern_Ignored_Point (Copy, 0, Ignored, X, Y, Status);
         Check (Status.Failure = K.Failure_Index_Out_Of_Range,
                "ignored point (count): out of range");
         --  The mask covers nothing at offsets beyond the image.
         KP.Pattern_Train_Masked
           (Copy, Handle, Region_Handle, Identity_T, Origin_T,
            AMV.Images.Kernel_Images.Kernel_Handle (Mask), 300, 0, Status);
         Check (K.Succeeded (Status) and then Copy.all = Pattern.all,
                "a mask beyond the image: the same model as none");
      end;
      KP.Pattern_Destroy (Copy);

      KP.Pattern_Duplicate (Pattern, Copy, Status);
      Check (K.Succeeded (Status) and then Copy /= null
             and then Copy.all = Pattern.all, "duplicate");
      KP.Pattern_Destroy (Copy);
      Check (Copy = null, "destroy");

      --  Train parameters.
      Train := (others => <>);
      KP.Pattern_Duplicate (Pattern, Copy, Status);
      KP.Pattern_Set_Train_Params
        (Copy, (Train with delta Grain_Limit_Fine => NaN), Status);
      Check (Status.Failure = K.Failure_Bad_Parameter,
             "GrainLimitFine NaN: bad parameter");
      KP.Pattern_Set_Train_Params
        (Copy, (Train with delta Grain_Limit_Coarse => 64.0), Status);
      Check (Status.Failure = K.Failure_Bad_Parameter,
             "GrainLimitCoarse 64: bad parameter");
      KP.Pattern_Set_Train_Params
        (Copy, (Train with delta Train_Algorithm => 4), Status);
      Check (Status.Failure = K.Failure_Bad_Parameter,
             "TrainAlgorithm 4: bad parameter");
      KP.Pattern_Trained (Copy, Flag, Status);
      Check (Flag = 1, "failed sets keep the model");
      KP.Pattern_Set_Train_Params
        (Copy, (Train with delta Ignore_Polarity => 1), Status);
      KP.Pattern_Trained (Copy, Flag, Status);
      Check (Flag = 0, "a set untrains");
      KP.Pattern_Destroy (Copy);

      --  Run parameters.
      Expect_Bad_Run ((Params with delta Accept_Threshold => NaN),
                      "AcceptThreshold NaN");
      KP.Execute (Handle, Region_Handle, Identity_T, Pattern,
                  (Params with delta Accept_Threshold => NaN), Results,
                  Status);
      Check (Message_Is ("RunParams.AcceptThreshold must be in [0, 1]"),
             "the message names the property");
      Expect_Bad_Run ((Params with delta Approximate_Number_To_Find => 0),
                      "ApproximateNumberToFind 0");
      Expect_Bad_Run ((Params with delta Approximate_Number_To_Find => 257),
                      "ApproximateNumberToFind 257");
      Expect_Bad_Run ((Params with delta Contrast_Threshold => 2000.0),
                      "ContrastThreshold 2000");
      Expect_Bad_Run ((Params with delta Timeout => NaN), "Timeout NaN");
      Expect_Bad_Run ((Params with delta Score_Using_Clutter => 2),
                      "ScoreUsingClutter 2");
      Expect_Bad_Run ((Params with delta Run_Algorithm => 3),
                      "RunAlgorithm PatFlex");
      Expect_Bad_Run ((Params with delta Outside_Region_Threshold => -0.1),
                      "OutsideRegionThreshold -0.1");
      Expect_Bad_Run
        ((Params with delta Zone_Angle =>
            (Configuration => 2, others => <>)),
         "ZoneAngle.Configuration 2");
      Expect_Bad_Run
        ((Params with delta Zone_Angle =>
            (Configuration => 0, Nominal => NaN, others => <>)),
         "ZoneAngle.Nominal NaN");
      Expect_Bad_Run
        ((Params with delta Zone_Angle =>
            (Configuration => 1, Low => -1.0E5, others => <>)),
         "ZoneAngle.Low -1.0E5");
      Expect_Bad_Run
        ((Params with delta Zone_Scale =>
            (Configuration => 1, Low => 0.05, others => <>)),
         "ZoneScale.Low 0.05");
      Expect_Bad_Run
        ((Params with delta Zone_Scale =>
            (Configuration => 0, Nominal => NaN, others => <>)),
         "ZoneScale.Nominal NaN");

      --  Inputs.
      KP.Execute (null, Region_Handle, Identity_T, Pattern, Params, Results,
                  Status);
      Check (Status.Failure = K.Failure_Image_No_Pixels
             and then Results = null, "execute (null image): no pixels");
      KP.Execute (Handle, Region_Handle, (Identity_T with delta B => NaN),
                  Pattern, Params, Results, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then Results = null, "execute (NaN transform)");
      KP.Execute (Handle, Region_Handle, (Identity_T with delta A => 0.0),
                  Pattern, Params, Results, Status);
      Check (Status.Failure = K.Failure_Transform_Singular
             and then Results = null, "execute (singular transform)");
      KP.Execute (Handle, null, Identity_T, Pattern, Params, Results, Status);
      KP.Results_Count (Results, Count, Status);
      Check (K.Succeeded (Status) and then Results /= null and then Count = 0,
             "execute (empty region): no results");
      KP.Results_Destroy (Results);

      --  The train image itself: one result, the identity pose.
      KP.Execute (Handle, Region_Handle, Identity_T, Pattern, Params,
                  Results, Status);
      KP.Results_Count (Results, Count, Status);
      Check (Count = 1, "the train image: one result");
      KP.Results_Item (Results, 0, Item, Status);
      Check (K.Succeeded (Status)
             and then abs (Item.Translation_X - Train_CX) < 0.02
             and then abs (Item.Translation_Y - Train_CY) < 0.02
             and then Item.Rotation = 0.0 and then Item.Scaling = 1.0
             and then Item.Score > 0.95,
             "the train image: the pose of the origin");
      KP.Results_Item (Results, 1, Item, Status);
      Check (Status.Failure = K.Failure_Index_Out_Of_Range,
             "item (1): out of range");
      KP.Results_Item (null, 0, Item, Status);
      Check (Status.Failure = K.Failure_Index_Out_Of_Range,
             "item (null): out of range");
      KP.Results_Count (null, Count, Status);
      Check (Count = 0, "count (null) = 0");
      KP.Results_Item (Results, 0, Item, Status);
      KP.Result_Get_Pose (Item, Pose, Status);
      Check (K.Succeeded (Status) and then Pose.A = Pose.D
             and then Pose.B = -Pose.C, "get pose: a similarity");
      KP.Result_Get_Pose ((Item with delta Scaling => NaN), Pose, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter,
             "get pose (NaN scaling): bad parameter");
      KP.Results_Destroy (Results);
      Check (Results = null, "results destroy");

      --  Stream helpers.
      KP.Check_Read_Code (1, Status);
      Check (Status.Failure = K.Failure_Image_File, "read code");
      KP.Check_Read_Count (3, Status);
      Check (Status.Failure = K.Failure_Image_File, "read count 3");
      KP.Check_Read_Count (5000, Status);
      Check (Status.Failure = K.Failure_Image_File, "read count 5000");
      KP.Pattern_Duplicate (Pattern, Copy, Status);
      KP.Read_Start (Copy, Train, 2, 0, 0, First, Last, Status);
      Check (Status.Failure = K.Failure_Image_File and then Last < First,
             "read start (trained 2)");
      KP.Read_Start (Copy, Train, 1, 2, 1, First, Last, Status);
      Check (Status.Failure = K.Failure_Image_File, "read start (2 .. 1)");
      KP.Read_Start (Copy, Train, 1, 0, 0, First, Last, Status);
      Check (K.Succeeded (Status) and then First = 0 and then Last = 0,
             "read start");
      KP.Read_Feature (Copy, 0, NaN, 0.0, 1.0, 0.0, Status);
      Check (Status.Failure = K.Failure_Image_File, "read feature (NaN)");
      KP.Read_Feature (Copy, 0, 0.0, 0.0, 2.0, 0.0, Status);
      Check (Status.Failure = K.Failure_Image_File,
             "read feature (normal 2)");
      KP.Read_Feature (Copy, 1, 0.0, 0.0, 1.0, 0.0, Status);
      Check (Status.Failure = K.Failure_Image_File,
             "read feature (level 1)");
      KP.Read_Feature (Copy, 0, 1.0, 2.0, 1.0, 0.0, Status);
      Check (K.Succeeded (Status), "read feature");
      KP.Read_Finish (Copy, 1, Status);
      Check (Status.Failure = K.Failure_Image_File,
             "read finish (one feature)");
      KP.Pattern_Destroy (Copy);
      KP.Pattern_Destroy (Pattern);
   end Test_Kernel;

   procedure Test_Timing is
      Image : Ks_Image_8_Grey := Scene;
      Tool  : Ks_PM_Align_Tool;
      Start : Ada.Calendar.Time;
      Full, Narrow, Scaled : Duration := Duration'Last;
   begin
      Section ("PMAlign: timing");
      Draw_Shape (Image, 333.3, 222.2, 2.0);
      TI.Add_Noise (Image, 5.0, 11);
      Tool.Input_Image := Image;
      Tool.Pattern := Shared_Pattern;
      --  The fastest of five runs of each, taken in turn, so that other
      --  work on the machine (the CI runner is shared) does not decide
      --  the comparison.
      for Round in 1 .. 5 loop
         Set_Full_Circle (Tool);
         Start := Ada.Calendar.Clock;
         Tool.Run;
         Full := Duration'Min
           (Full, Ada.Calendar."-" (Ada.Calendar.Clock, Start));
         Check (Tool.Results.Count = 1, "full circle: found");
         Tool.Run_Params.Zone_Angle :=
           (Configuration => Code (Low_High), Low => 1.9, High => 2.1,
            Nominal => 0.0);
         Start := Ada.Calendar.Clock;
         Tool.Run;
         Narrow := Duration'Min
           (Narrow, Ada.Calendar."-" (Ada.Calendar.Clock, Start));
         Check (Tool.Results.Count = 1, "narrow zone: found");
      end loop;
      Set_Full_Circle (Tool);
      Tool.Run_Params.Zone_Scale :=
        (Configuration => Code (Low_High), Low => 0.9, High => 1.1,
         Nominal => 1.0);
      Start := Ada.Calendar.Clock;
      Tool.Run;
      Scaled := Ada.Calendar."-" (Ada.Calendar.Clock, Start);
      Check (Tool.Results.Count = 1, "full circle and scale zone: found");
      Ada.Text_IO.Put_Line
        ("  640 x 480, full circle:" & Duration'Image (Full * 1000.0)
         & " ms; +/-0.1 rad:" & Duration'Image (Narrow * 1000.0)
         & " ms; full circle, scale 0.9 .. 1.1:"
         & Duration'Image (Scaled * 1000.0) & " ms");
      Check (Full < 5.0, "full circle within 5 s");
      Check (Narrow < Full, "a narrow zone is faster");
   end Test_Timing;

   procedure Run_All is
   begin
      Test_Defaults;
      Test_Features;
      Test_Locate;
      Test_Several;
      Test_XY_Overlap;
      Test_Search_Mask;
      Test_Occlusion_And_Contrast;
      Test_No_False_Positives;
      Test_Origin;
      Test_Failures;
      Test_Grain_Limits;
      Test_Region;
      Test_Fixture;
      Test_Train_Space;
      Test_Chain;
      Test_Thinning;
      Test_Automatic_Grain;
      Test_Train_Mask;
      Test_Stream;
      Test_Kernel;
      Test_Timing;
   end Run_All;

   procedure Main is new AMV_Test_Support.Standalone (Run_All);
begin
   Main;
end Test_PM_Align;
