--  Tests for AMV.Caliper.Find_Circle (CogFindCircleTool) and its kernel
--  AMV.Kernels.Find_Circle.
--
--  The scenes are anti-aliased discs and rings (AMV_Test_Images) of radius
--  30 or more, whose edges the renderer places within about 0.01 pixel.

pragma Validity_Checks ("F");

with Ada.Calendar;
with Ada.Numerics.Long_Elementary_Functions;
with Ada.Text_IO;

with AMV;                     use AMV;
with AMV.Caliper;             use AMV.Caliper;
with AMV.Caliper.Find_Circle; use AMV.Caliper.Find_Circle;
with AMV.Coordinate_Spaces;   use AMV.Coordinate_Spaces;
with AMV.Images;              use AMV.Images;
with AMV.Kernels;
with AMV.Kernels.Caliper;
with AMV.Kernels.Find_Circle;
with AMV.Kernels.Shapes;
with AMV.Misc;
with AMV.Shapes;              use AMV.Shapes;
with AMV.Tools;               use AMV.Tools;
with AMV.Transforms;          use AMV.Transforms;
with AMV_Test_Images;
with AMV_Test_Support;        use AMV_Test_Support;

procedure Test_Find_Circle is

   package EF renames Ada.Numerics.Long_Elementary_Functions;
   package K renames AMV.Kernels;
   package KC renames AMV.Kernels.Caliper;
   package KF renames AMV.Kernels.Find_Circle;
   package KS renames AMV.Kernels.Shapes;
   package TI renames AMV_Test_Images;

   use type K.Int32;
   use type KC.Ks_Caliper_Results;
   use type KF.Ks_Find_Circle_Results;

   Pi : constant := Ada.Numerics.Pi;

   CX : constant := 160.37;
   CY : constant := 120.81;
   R  : constant := 50.3;
   --  The default disc.

   function Status_Is
     (Tool                : Ks_Find_Circle_Tool;
      Exception_Name_Part : String;
      Message             : String) return Boolean
   is (Tool.Run_Status.Result = Error
       and then AMV.Tools.Exception_Name (Tool.Run_Status)
                  = "AMV." & Exception_Name_Part
       and then AMV.Tools.Message (Tool.Run_Status) = Message);

   procedure Report (Tool : Ks_Find_Circle_Tool; Description : String);

   procedure Report (Tool : Ks_Find_Circle_Tool; Description : String) is
   begin
      if Tool.Run_Status.Result /= Accept_Result then
         Ada.Text_IO.Put_Line
           ("  " & Description & ": " & Tool.Run_Status.Result'Image & " "
            & Exception_Name (Tool.Run_Status) & " "
            & Message (Tool.Run_Status));
      end if;
   end Report;

   function Disc (Noise : Real := 0.0) return Ks_Image_8_Grey is
   begin
      return Image : Ks_Image_8_Grey := TI.Blank (320, 240, 40) do
         TI.Draw_Circle (Image, CX, CY, R, 200);
         if Noise > 0.0 then
            TI.Add_Noise (Image, Noise, 5);
         end if;
      end return;
   end Disc;

   procedure Set_Arc
     (Tool        : in out Ks_Find_Circle_Tool;
      X, Y, Rad   : Real;
      Start, Span : Real) is
   begin
      Tool.Run_Params.Expected_Circular_Arc
        .Set_Center_Radius_Angle_Start_Angle_Span (X, Y, Rad, Start, Span);
   end Set_Arc;

   procedure Check_Circle
     (Tool        : Ks_Find_Circle_Tool;
      X, Y, Rad   : Real;
      Tolerance   : Real;
      Description : String)
   is
      C : Ks_Circle;
   begin
      Report (Tool, Description);
      if Tool.Run_Status.Result /= Accept_Result then
         Fail (Description & ": the run failed");
         return;
      end if;
      C := Tool.Results.Get_Circle;
      Check (abs (C.Center_X - X) < Tolerance
             and then abs (C.Center_Y - Y) < Tolerance
             and then abs (C.Radius - Rad) < Tolerance,
             Description & ": centre (" & C.Center_X'Image & ","
             & C.Center_Y'Image & "), radius" & C.Radius'Image);
   end Check_Circle;

   ---------------------------------------------------------------------

   procedure Test_Defaults is
      P : constant Ks_Find_Circle := (others => <>);
   begin
      Section ("Find circle: defaults");
      Check (P.Num_Calipers = 6 and then P.Num_To_Ignore = 0
             and then P.Caliper_Search_Direction = Inward
             and then not P.Radius_Constraint_Enabled
             and then P.Radius_Constraint = 100.0
             and then P.Caliper_Search_Length = 30.0
             and then P.Caliper_Projection_Length = 10.0,
             "the defaults of CogFindCircle");
      Check (P.Expected_Circular_Arc.Radius = 50.0
             and then abs (P.Expected_Circular_Arc.Angle_Span - Pi) < 1.0E-15,
             "the default arc");
   end Test_Defaults;

   procedure Test_Full_Circles is
   begin
      Section ("Find circle: full circles, inward and outward");
      for Direction in Ks_Find_Circle_Search_Direction_Constants loop
         for Noisy in Boolean loop
            declare
               Tool : Ks_Find_Circle_Tool;
            begin
               Tool.Input_Image := Disc (if Noisy then 10.0 else 0.0);
               Set_Arc (Tool, CX + 2.0, CY - 3.0, 48.0, 0.0, 2.0 * Pi);
               Tool.Run_Params.Num_Calipers := 12;
               Tool.Run_Params.Caliper_Search_Direction := Direction;
               Tool.Run;
               Check_Circle (Tool, CX, CY, R,
                             (if Noisy then 0.15 else 0.03),
                             "a disc" & Direction'Image & Noisy'Image);
               Check (Tool.Results.Num_Points_Found = 12
                      and then Tool.Results.Num_Points_Used = 12,
                      "twelve points");
               Check (Tool.Results.RMS_Error < (if Noisy then 0.3 else 0.03),
                      "small RMS error" & Tool.Results.RMS_Error'Image);
               if Tool.Results.Count = 12 then
                  declare
                     Item : constant Ks_Find_Circle_Result :=
                       Tool.Results.Item (3);
                  begin
                     Check (Item.Found and then Item.Used
                            and then Item.Distance_To_Circle
                                       < (if Noisy then 0.5 else 0.05)
                            and then Item.Caliper_Results.Count = 1
                            and then (Item.Caliper_Results.Item (0)
                                        .Edge_0.Contrast > 0.0)
                                     = (Direction = Inward),
                            "an item with its caliper results");
                  end;
               end if;
            end;
         end loop;
      end loop;
   end Test_Full_Circles;

   procedure Test_Annulus is
      Tool : Ks_Find_Circle_Tool;
   begin
      Section ("Find circle: the two edges of a ring");
      Tool.Input_Image := TI.Blank (320, 240, 30);
      TI.Draw_Annulus (Tool.Input_Image, CX, CY, 32.4, 61.7, 210);
      Tool.Run_Params.Num_Calipers := 10;
      Tool.Run_Params.Caliper_Search_Length := 20.0;
      Set_Arc (Tool, CX, CY, 33.0, 0.4, 2.0 * Pi);
      Tool.Run;
      Check_Circle (Tool, CX, CY, 32.4, 0.03,
                    "the inner edge, inward");
      Tool.Run_Params.Caliper_Search_Direction := Outward;
      Tool.Run;
      Check_Circle (Tool, CX, CY, 32.4, 0.03,
                    "the inner edge, outward");
      Set_Arc (Tool, CX, CY, 60.0, 0.4, -2.0 * Pi);
      Tool.Run;
      Check_Circle (Tool, CX, CY, 61.7, 0.03,
                    "the outer edge, clockwise arc");
      Tool.Run_Params.Caliper_Projection_Length := 3.0;
      Tool.Run;
      Check_Circle (Tool, CX, CY, 61.7, 0.03,
                    "a shorter projection");
   end Test_Annulus;

   procedure Test_Curvature is
      type Case_Type is record
         Radius, Projection : Real;
      end record;
      --  L**2 / (8 R), the largest bend across a caliper, up to about
      --  1.6 pixels, within the default FilterHalfSizeInPixels (2).
      Cases : constant array (1 .. 7) of Case_Type :=
        [(12.3, 5.0), (12.3, 8.0), (30.7, 10.0), (30.7, 20.0),
         (100.6, 20.0), (100.6, 35.0), (200.2, 40.0)];
      Worst : Real := 0.0;
   begin
      Section ("Find circle: the curvature correction");
      for C of Cases loop
         declare
            Size : constant Positive := Positive (2.0 * C.Radius + 80.0);
            Mid  : constant Real := Real (Size) / 2.0 + 0.37;
            Tool : Ks_Find_Circle_Tool;
            Got  : Ks_Circle;
         begin
            Tool.Input_Image := TI.Blank (Size, Size, 40);
            TI.Draw_Circle (Tool.Input_Image, Mid, Mid - 0.21, C.Radius, 200);
            Set_Arc (Tool, Mid + 1.0, Mid - 1.0, C.Radius - 1.0, 0.1,
                     2.0 * Pi);
            Tool.Run_Params.Num_Calipers := 24;
            Tool.Run_Params.Caliper_Search_Length := 16.0;
            Tool.Run_Params.Caliper_Projection_Length := C.Projection;
            Tool.Run;
            Report (Tool, "curvature");
            if Tool.Run_Status.Result = Accept_Result then
               Got := Tool.Results.Get_Circle;
               Worst := Real'Max (Worst, abs (Got.Radius - C.Radius));
               Check (abs (Got.Radius - C.Radius) < 0.02
                      and then abs (Got.Center_X - Mid) < 0.02
                      and then abs (Got.Center_Y - (Mid - 0.21)) < 0.02,
                      "R" & C.Radius'Image & ", L" & C.Projection'Image
                      & ": radius" & Got.Radius'Image
                      & " (uncorrected"
                      & Real'Image (C.Radius
                                    - C.Projection**2 / (24.0 * C.Radius))
                      & ")");
               --  Each point is its caliper's edge moved out by the
               --  correction, and lies on the circle. The kernel takes the
               --  first fit's radius, smaller by about the correction, so
               --  the distance exceeds the one computed from the final
               --  radius by a relative Sag / R (under 2 percent here).
               declare
                  Item : constant Ks_Find_Circle_Result :=
                    Tool.Results.Item (5);
                  Edge : constant Ks_Caliper_Result :=
                    Item.Caliper_Results.Item (0);
                  Sag  : constant Real :=
                    C.Projection**2 / (24.0 * Got.Radius);
               begin
                  Check (abs (EF.Sqrt ((Item.X - Edge.Position_X)**2
                                       + (Item.Y - Edge.Position_Y)**2)
                              - Sag) < 0.03 * Sag
                         and then EF.Sqrt ((Item.X - Got.Center_X)**2
                                           + (Item.Y - Got.Center_Y)**2)
                                  > EF.Sqrt
                                      ((Edge.Position_X - Got.Center_X)**2
                                       + (Edge.Position_Y - Got.Center_Y)**2)
                         and then Item.Distance_To_Circle < 0.05,
                         "the point moved out by" & Sag'Image);
               end;
            else
               Fail ("curvature: the run failed");
            end if;
         end;
      end loop;
      Ada.Text_IO.Put_Line ("  largest radius error:" & Worst'Image);

      --  A short arc with the true radius as the constraint: the corrected
      --  points put the centre where it is.
      declare
         Tool : Ks_Find_Circle_Tool;
         Got  : Ks_Circle;
      begin
         Tool.Input_Image := TI.Blank (320, 240, 40);
         TI.Draw_Circle (Tool.Input_Image, CX, CY, 30.7, 200);
         Set_Arc (Tool, CX - 1.0, CY + 1.0, 30.7, 0.2, 0.9);
         Tool.Run_Params.Caliper_Projection_Length := 20.0;
         Tool.Run_Params.Radius_Constraint_Enabled := True;
         Tool.Run_Params.Radius_Constraint := 30.7;
         Tool.Run;
         Report (Tool, "constrained arc");
         Got := Tool.Results.Get_Circle;
         Check (Tool.Run_Status.Result = Accept_Result
                and then abs (Got.Center_X - CX) < 0.05
                and then abs (Got.Center_Y - CY) < 0.05,
                "a 0.9 rad arc of radius 30.7, L 20, the radius constrained:"
                & " centre (" & Got.Center_X'Image & ","
                & Got.Center_Y'Image & ")");
      end;
   end Test_Curvature;

   procedure Test_Partial_Arcs is
      Tool : Ks_Find_Circle_Tool;
      A    : Ks_Circular_Arc;
   begin
      Section ("Find circle: partial arcs");
      Tool.Input_Image := Disc;
      Set_Arc (Tool, CX - 1.0, CY + 2.0, R, 0.3, 1.2);
      Tool.Run;
      Check_Circle (Tool, CX, CY, R, 0.06, "an arc of 1.2 rad");
      A := Tool.Results.Get_Circular_Arc;
      Check (abs AMV.Misc.Norm_Angle (A.Angle_Start - 0.3) < 0.05
             and then abs (A.Angle_Span - 1.2) < 0.05,
             "the arc through the points:" & A.Angle_Start'Image
             & A.Angle_Span'Image);
      Set_Arc (Tool, CX - 1.0, CY + 2.0, R, 2.5, -0.9);
      Tool.Run;
      Check_Circle (Tool, CX, CY, R, 0.1,
                    "a clockwise arc of 0.9 rad");
      A := Tool.Results.Get_Circular_Arc;
      Check (abs AMV.Misc.Norm_Angle (A.Angle_Start - 2.5) < 0.05
             and then abs (A.Angle_Span + 0.9) < 0.05,
             "a clockwise arc through the points");
   end Test_Partial_Arcs;

   procedure Test_Radius_Constraint is
      Tool : Ks_Find_Circle_Tool;
      C    : Ks_Circle;
   begin
      Section ("Find circle: the radius constraint");
      Tool.Input_Image := Disc (6.0);
      Set_Arc (Tool, CX - 2.0, CY + 1.0, R, -0.4, 0.8);
      Tool.Run_Params.Radius_Constraint_Enabled := True;
      Tool.Run_Params.Radius_Constraint := R;
      Tool.Run;
      Check_Circle (Tool, CX, CY, R, 0.15,
                    "a short noisy arc with the true radius");
      C := Tool.Results.Get_Circle;
      Check (C.Radius = R, "the radius is the constraint");
      Tool.Run_Params.Radius_Constraint := 45.0;
      Tool.Run;
      C := Tool.Results.Get_Circle;
      Check (Tool.Run_Status.Result = Accept_Result and then C.Radius = 45.0
             and then abs (C.Center_X - (CX + 5.3)) < 0.5,
             "a smaller radius moves the centre towards the arc"
             & C.Center_X'Image);
      --  Three calipers, one ignored: two points suffice.
      Tool.Run_Params.Radius_Constraint := R;
      Tool.Run_Params.Num_Calipers := 3;
      Tool.Run_Params.Num_To_Ignore := 1;
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Num_Points_Used = 2,
             "two points with the radius constraint");
      Tool.Run_Params.Radius_Constraint_Enabled := False;
      Tool.Run;
      Check (Status_Is (Tool, "KS_BAD_PARAMETER_EXCEPTION",
                        "RunParams.NumToIgnore must be in 0 .. NumCalipers"
                        & " - 3"),
             "without it three points are needed");
   end Test_Radius_Constraint;

   procedure Test_Outlier is
      Tool : Ks_Find_Circle_Tool;
      Box  : Ks_Rectangle_Affine;
   begin
      Section ("Find circle: an occluded caliper and NumToIgnore");
      Tool.Input_Image := Disc;
      Set_Arc (Tool, CX, CY, R, 0.1, 2.0 * Pi);
      Tool.Run_Params.Num_Calipers := 10;
      Box := Get_Caliper_Region (Tool.Run_Params, 4);
      TI.Draw_Circle (Tool.Input_Image, Box.Center_X, Box.Center_Y, 9.0, 40);
      Tool.Run;
      Check (Tool.Results.Num_Points_Used = 10
             and then Tool.Results.Item (4).Distance_To_Circle > 3.0,
             "the occluded caliper is an outlier");
      Tool.Run_Params.Num_To_Ignore := 1;
      Tool.Run;
      Check_Circle (Tool, CX, CY, R, 0.03, "NumToIgnore 1");
      Check (not Tool.Results.Item (4).Used
             and then Tool.Results.Num_Points_Used = 9,
             "the outlier is not used");
      Tool.Run_Params.Radius_Constraint_Enabled := True;
      Tool.Run_Params.Radius_Constraint := R;
      Tool.Run;
      Check_Circle (Tool, CX, CY, R, 0.03,
                    "NumToIgnore 1 with the radius constraint");
      Check (not Tool.Results.Item (4).Used, "the outlier is not used");
   end Test_Outlier;

   procedure Test_Regions is
      P   : Ks_Find_Circle;
      Box : Ks_Rectangle_Affine;
   begin
      Section ("Find circle: caliper regions");
      P.Expected_Circular_Arc.Set_Center_Radius_Angle_Start_Angle_Span
        (10.0, 20.0, 40.0, 0.0, 2.0 * Pi);
      P.Num_Calipers := 4;
      for I in 0 .. 3 loop
         Box := Get_Caliper_Region (P, I);
         declare
            Theta : constant Real := Real (I) * Pi / 2.0;
         begin
            Check (abs (Box.Center_X - (10.0 + 40.0 * EF.Cos (Theta)))
                     < 1.0E-12
                   and then abs (Box.Center_Y - (20.0 + 40.0 * EF.Sin (Theta)))
                              < 1.0E-12
                   and then abs AMV.Misc.Norm_Angle
                                  (Box.Rotation - (Theta + Pi)) < 1.0E-12
                   and then Box.Side_X_Length = 30.0,
                   "full circle: caliper" & I'Image
                   & " a quarter turn apart, searching inward");
         end;
      end loop;
      P.Expected_Circular_Arc.Set_Angle_Span (1.0);
      P.Caliper_Search_Direction := Outward;
      Box := Get_Caliper_Region (P, 3);
      Check (abs (Box.Rotation - 1.0) < 1.0E-12,
             "partial arc: the last caliper at the end, outward");
   end Test_Regions;

   procedure Test_Fixture is
      Alpha : constant Real := 0.6;
      Scale : constant Real := 0.8;
      Fix   : constant Ks_Transform_2D_Linear :=
        Create (Scale * EF.Cos (Alpha), -Scale * EF.Sin (Alpha),
                Scale * EF.Sin (Alpha), Scale * EF.Cos (Alpha), 100.0, 30.0);
      Tree  : Ks_Coordinate_Space_Tree;
      Tool  : Ks_Find_Circle_Tool;
      U0    : constant Real := 70.0;
      V0    : constant Real := 60.0;
      Rad   : constant Real := 55.0;
      --  The circle in the fixture: 0.8 pixels per unit.
      PX, PY : Real;
   begin
      Section ("Find circle: fixture space");
      Tool.Input_Image := TI.Blank (320, 240, 40);
      Fix.Map_Point (U0, V0, PX, PY);
      TI.Draw_Circle (Tool.Input_Image, PX, PY, Rad * Scale, 200);
      Tree.Add_Space ("@", "Fixture", Fix);
      Tool.Input_Image.Set_Coordinate_Space_Tree (Tree);
      Tool.Input_Image.Set_Selected_Space_Name ("@\Fixture");
      Set_Arc (Tool, U0 + 2.0, V0, Rad, 0.0, 2.0 * Pi);
      Tool.Run_Params.Num_Calipers := 12;
      Tool.Run;
      Check_Circle (Tool, U0, V0, Rad, 0.05,
                    "a circle in the fixture");
   end Test_Fixture;

   procedure Test_Failures is
      Tool : Ks_Find_Circle_Tool;
   begin
      Section ("Find circle: failures");
      Tool.Run;
      Check (Status_Is (Tool, "KS_IMAGE_NO_PIXELS_EXCEPTION",
                        "InputImage has no pixels"),
             "unallocated image");
      Tool.Input_Image := TI.Blank (100, 100, 40);
      Tool.Run;
      Check (Status_Is (Tool, "KS_EXCEPTION",
                        "FindCircle: fewer than 3 points remain to fit"
                        & " (NumPointsFound = 0, NumToIgnore = 0)"),
             "a blank image");
      Tool.Run_Params.Num_Calipers := 2;
      Tool.Run;
      Check (Status_Is (Tool, "KS_BAD_PARAMETER_EXCEPTION",
                        "RunParams.NumCalipers must be in 3 .. 1000"),
             "two calipers");
      Tool.Run_Params.Num_Calipers := 6;
      Tool.Run_Params.Expected_Circular_Arc.Set_Radius (0.0);
      Tool.Run;
      Check (Status_Is (Tool, "KS_BAD_PARAMETER_EXCEPTION",
                        "RunParams.ExpectedCircularArc.Radius must be > 0"),
             "an arc of radius 0");
      Tool.Run_Params.Expected_Circular_Arc.Set_Radius (40.0);
      Tool.Run_Params.Radius_Constraint_Enabled := True;
      Tool.Run_Params.Radius_Constraint := -1.0;
      Tool.Run;
      Check (Status_Is (Tool, "KS_BAD_PARAMETER_EXCEPTION",
                        "RunParams.RadiusConstraint must be > 0 and"
                        & " <= 1.0E150"),
             "a negative radius constraint");
      Tool.Run_Params.Radius_Constraint := 40.0;
      Tool.Run_Params.Caliper_Run_Params.Max_Results := 0;
      Tool.Run;
      Check (Status_Is (Tool, "KS_BAD_PARAMETER_EXCEPTION",
                        "RunParams.CaliperRunParams.MaxResults must be in"
                        & " 1 .. 1000"),
             "bad caliper parameters");
      Tool.Run_Params.Caliper_Run_Params.Max_Results := 1;
      Tool.Run_Params.Expected_Circular_Arc
        .Set_Center_Radius_Angle_Start_Angle_Span
          (9.0E149, 0.0, 4.0E149, 0.0, Pi);
      Tool.Run;
      Check (Status_Is (Tool, "KS_BAD_PARAMETER_EXCEPTION",
                        "RunParams.ExpectedCircularArc: caliper 0 would lie"
                        & " beyond +/-1.0E150"),
             "a caliper beyond the bound");
   end Test_Failures;

   procedure Test_Kernel is
      Params  : KF.Ks_Find_Circle_Run_Params;
      Results : KF.Ks_Find_Circle_Results;
      Status  : K.Ks_Status;
      Count   : K.Int32;
      Item    : KF.Ks_Find_Circle_Result;
      Circle  : KS.Ks_Circle;
      Arc     : KS.Ks_Circular_Arc;
      RMS     : Real;
      NF, NU  : K.Int32;
      Copy    : KC.Ks_Caliper_Results;
      Id      : constant KS.KT.Ks_Transform_2D_Linear := (others => <>);
   begin
      Section ("Find circle: kernel");
      KF.Run_Params_Default (Params, Status);
      Check (Status.Failure = K.Failure_None and then Params.Num_Calipers = 6
             and then Params.Caliper_Search_Direction
                        = KF.Search_Direction_Inward,
             "ks_find_circle_run_params_default");
      KF.Execute (null, Params, Id, Id, Results, Status);
      Check (Status.Failure = K.Failure_Image_No_Pixels
             and then Results = null, "null image");
      KF.Results_Count (null, Count, Status);
      Check (Status.Failure = K.Failure_None and then Count = 0,
             "null results: count 0");
      KF.Results_Item (null, 0, Item, Status);
      Check (Status.Failure = K.Failure_Index_Out_Of_Range,
             "null results: no item");
      KF.Results_Circle (null, Circle, Arc, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter,
             "null results: no circle");
      KF.Results_Fit (null, RMS, NF, NU, Status);
      Check (Status.Failure = K.Failure_None and then NF = 0,
             "null results: no points");
      KF.Results_Caliper_Results (null, 0, Copy, Status);
      Check (Status.Failure = K.Failure_Index_Out_Of_Range
             and then Copy = null, "null results: no caliper results");
      Params.Caliper_Search_Direction := 2;
      KF.Execute (null, Params, Id, Id, Results, Status);
      Check (Status.Failure = K.Failure_Image_No_Pixels,
             "the image is checked first");
      KF.Results_Destroy (Results);
      Check (Results = null, "destroy null");
   end Test_Kernel;

   procedure Test_Timing is
      Tool  : Ks_Find_Circle_Tool;
      Start : Ada.Calendar.Time;
      Total : Duration;
      Runs  : constant := 10;
   begin
      Section ("Find circle: timing");
      Tool.Input_Image := TI.Blank (640, 480, 40);
      TI.Draw_Circle (Tool.Input_Image, 320.0, 240.0, 150.0, 200);
      Set_Arc (Tool, 322.0, 238.0, 148.0, 0.0, 2.0 * Pi);
      Tool.Run_Params.Num_Calipers := 16;
      Tool.Run_Params.Caliper_Search_Length := 40.0;
      Tool.Run_Params.Caliper_Projection_Length := 15.0;
      Tool.Run_Params.Num_To_Ignore := 2;
      Start := Ada.Calendar.Clock;
      for I in 1 .. Runs loop
         Tool.Run;
      end loop;
      Total := Ada.Calendar."-" (Ada.Calendar.Clock, Start);
      Check (Tool.Results.Num_Points_Used = 14, "fourteen points used");
      Ada.Text_IO.Put_Line
        ("  find circle with 16 calipers of 40 x 15 pixels on 640 x 480,"
         & " NumToIgnore 2:" & Duration'Image (Total / Runs * 1000.0)
         & " ms per run");
      Tool.Run_Params.Radius_Constraint_Enabled := True;
      Tool.Run_Params.Radius_Constraint := 150.0;
      Start := Ada.Calendar.Clock;
      for I in 1 .. Runs loop
         Tool.Run;
      end loop;
      Total := Ada.Calendar."-" (Ada.Calendar.Clock, Start);
      Check (Tool.Results.Num_Points_Used = 14, "fourteen points used");
      Ada.Text_IO.Put_Line
        ("  the same with the radius constraint:"
         & Duration'Image (Total / Runs * 1000.0) & " ms per run");
   end Test_Timing;

   procedure Run_All is
   begin
      Test_Defaults;
      Test_Full_Circles;
      Test_Annulus;
      Test_Partial_Arcs;
      Test_Curvature;
      Test_Radius_Constraint;
      Test_Outlier;
      Test_Regions;
      Test_Fixture;
      Test_Failures;
      Test_Kernel;
      Test_Timing;
   end Run_All;

   procedure Main is new AMV_Test_Support.Standalone (Run_All);
begin
   Main;
end Test_Find_Circle;
