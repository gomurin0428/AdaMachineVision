--  Tests for AMV.Caliper.Find_Line (CogFindLineTool) and its kernel
--  AMV.Kernels.Find_Line.
--
--  The scenes are half-planes (AMV_Test_Images.Draw_Half_Plane) turned by
--  generic angles, so that their edges are placed within about 0.002
--  pixel, with discs as occluders and rectangles for partial edges.

pragma Validity_Checks ("F");

with Ada.Calendar;
with Ada.Numerics.Long_Elementary_Functions;
with Ada.Text_IO;

with AMV;                    use AMV;
with AMV.Caliper;            use AMV.Caliper;
with AMV.Caliper.Find_Line;  use AMV.Caliper.Find_Line;
with AMV.Coordinate_Spaces;  use AMV.Coordinate_Spaces;
with AMV.Images;             use AMV.Images;
with AMV.Kernels;
with AMV.Kernels.Caliper;
with AMV.Kernels.Find_Line;
with AMV.Kernels.Shapes;
with AMV.Misc;
with AMV.Shapes;             use AMV.Shapes;
with AMV.Tools;              use AMV.Tools;
with AMV.Transforms;         use AMV.Transforms;
with AMV_Test_Images;
with AMV_Test_Support;       use AMV_Test_Support;

procedure Test_Find_Line is

   package EF renames Ada.Numerics.Long_Elementary_Functions;
   package K renames AMV.Kernels;
   package KC renames AMV.Kernels.Caliper;
   package KF renames AMV.Kernels.Find_Line;
   package KS renames AMV.Kernels.Shapes;
   package TI renames AMV_Test_Images;

   use type K.Int32;
   use type KC.Ks_Caliper_Results;
   use type KF.Ks_Find_Line_Results;

   Pi : constant := Ada.Numerics.Pi;

   Zero : constant Real := Real'Value ("0.0");

   function Status_Is
     (Tool                : Ks_Find_Line_Tool;
      Exception_Name_Part : String;
      Message             : String) return Boolean
   is (Tool.Run_Status.Result = Error
       and then AMV.Tools.Exception_Name (Tool.Run_Status)
                  = "AMV." & Exception_Name_Part
       and then AMV.Tools.Message (Tool.Run_Status) = Message);

   procedure Report (Tool : Ks_Find_Line_Tool; Description : String);

   procedure Report (Tool : Ks_Find_Line_Tool; Description : String) is
   begin
      if Tool.Run_Status.Result /= Accept_Result then
         Ada.Text_IO.Put_Line
           ("  " & Description & ": " & Tool.Run_Status.Result'Image & " "
            & Exception_Name (Tool.Run_Status) & " "
            & Message (Tool.Run_Status));
      end if;
   end Report;

   function Distance_To
     (Line : Ks_Line; X, Y : Real) return Real
   is (abs ((X - Line.X) * EF.Sin (Line.Rotation)
            - (Y - Line.Y) * EF.Cos (Line.Rotation)));
   --  The distance of (X, Y) from Line.

   procedure Set_Segment
     (Tool         : in out Ks_Find_Line_Tool;
      X, Y, Beta   : Real;
      Half         : Real := 80.0) is
   begin
      Tool.Run_Params.Expected_Line_Segment.Set_Start_End
        (X - Half * EF.Cos (Beta), Y - Half * EF.Sin (Beta),
         X + Half * EF.Cos (Beta), Y + Half * EF.Sin (Beta));
   end Set_Segment;

   ---------------------------------------------------------------------

   procedure Test_Defaults is
      P    : constant Ks_Find_Line := (others => <>);
      Tool : Ks_Find_Line_Tool;
   begin
      Section ("Find line: defaults");
      Check (P.Num_Calipers = 6 and then P.Num_To_Ignore = 0
             and then not P.Decrement_Num_To_Ignore,
             "6 calipers, NumToIgnore 0");
      Check (P.Caliper_Search_Length = 30.0
             and then P.Caliper_Projection_Length = 10.0,
             "search length 30, projection length 10");
      Check (abs (P.Caliper_Search_Direction - Pi / 2.0) < 1.0E-15,
             "search direction Pi / 2");
      Check (P.Expected_Line_Segment.Start_X = 0.0
             and then P.Expected_Line_Segment.End_X = 100.0,
             "the default segment");
      Check (Tool.Results.Count = 0 and then Tool.Results.RMS_Error = 0.0
             and then Tool.Results.Num_Points_Found = 0,
             "no results before a run");
   end Test_Defaults;

   procedure Test_Rotated_Edges is
      Betas : constant array (1 .. 4) of Real := [0.23, 1.37, -0.81, 2.66];
      Worst_D, Worst_A : Real := 0.0;
   begin
      Section ("Find line: rotated half-planes");
      for Beta of Betas loop
         for Noisy in Boolean loop
            declare
               Tool : Ks_Find_Line_Tool;
               X0   : constant Real := 150.0;
               Y0   : constant Real := 140.0;
               L    : Ks_Line;
               S    : Ks_Line_Segment;
               D, A : Real;
            begin
               Tool.Input_Image := TI.Blank (300, 300, 40);
               TI.Draw_Half_Plane (Tool.Input_Image, X0, Y0, Beta, 200);
               if Noisy then
                  TI.Add_Noise (Tool.Input_Image, 10.0, 3);
               end if;
               --  The expected segment: 4 pixels off and 0.03 rad turned.
               Set_Segment
                 (Tool, X0 - 4.0 * EF.Sin (Beta), Y0 + 4.0 * EF.Cos (Beta),
                  Beta + 0.03);
               Tool.Run;
               Report (Tool, "rotated edge");
               Check (Tool.Run_Status.Result = Accept_Result
                      and then Tool.Results.Count = 6
                      and then Tool.Results.Num_Points_Found = 6
                      and then Tool.Results.Num_Points_Used = 6,
                      "six points found and used");
               if Tool.Run_Status.Result = Accept_Result then
                  L := Tool.Results.Get_Line;
                  D := Distance_To (L, X0, Y0);
                  A := abs AMV.Misc.Norm_Angle (L.Rotation - Beta);
                  Worst_D := Real'Max (Worst_D, D);
                  Worst_A := Real'Max (Worst_A, A);
                  Check (D < (if Noisy then 0.1 else 0.02),
                         "the line passes through the edge" & D'Image);
                  Check (A < (if Noisy then 2.0E-3 else 2.0E-4),
                         "the line has the edge's direction" & A'Image);
                  Check (Tool.Results.RMS_Error
                           < (if Noisy then 0.2 else 0.02),
                         "small RMS error");
                  S := Tool.Results.Get_Line_Segment;
                  Check (Distance_To (L, S.Start_X, S.Start_Y) < 1.0E-9
                         and then Distance_To (L, S.End_X, S.End_Y) < 1.0E-9,
                         "the segment lies on the line");
                  Check (abs (S.Length - 160.0) < 1.0,
                         "the segment spans the first to the last point"
                         & S.Length'Image);
                  Check (abs AMV.Misc.Norm_Angle (S.Rotation - Beta) < 0.01,
                         "the segment runs like the expected one");
                  for I in 0 .. 5 loop
                     declare
                        R : constant Ks_Find_Line_Result :=
                          Tool.Results.Item (I);
                     begin
                        Check (R.Found and then R.Used
                               and then abs R.Distance_To_Line
                                          - Distance_To (L, R.X, R.Y)
                                        < 1.0E-9
                               and then R.Caliper_Results.Count = 1
                               and then R.Caliper_Results.Item (0).Position_X
                                          = R.X,
                               "item" & I'Image);
                     end;
                  end loop;
               end if;
            end;
         end loop;
      end loop;
      Ada.Text_IO.Put_Line
        ("  worst line offset" & Worst_D'Image & " px, angle"
         & Worst_A'Image & " rad");
   end Test_Rotated_Edges;

   procedure Test_Outlier is
      Beta : constant Real := 0.41;
      X0   : constant Real := 150.0;
      Y0   : constant Real := 150.0;
      Tool : Ks_Find_Line_Tool;
      Box  : Ks_Rectangle_Affine;
      L    : Ks_Line;
   begin
      Section ("Find line: an occluded caliper and NumToIgnore");
      Tool.Input_Image := TI.Blank (300, 300, 40);
      TI.Draw_Half_Plane (Tool.Input_Image, X0, Y0, Beta, 200);
      Set_Segment (Tool, X0, Y0, Beta);
      Tool.Run_Params.Caliper_Run_Params.Edge_0_Polarity :=
        Code (Dark_To_Light);
      --  A bright disc over the edge at caliper 2, centred 2 pixels on
      --  the dark side: that caliper finds the disc's border instead.
      Box := Get_Caliper_Region (Tool.Run_Params, 2);
      TI.Draw_Circle
        (Tool.Input_Image, Box.Center_X + 2.0 * EF.Sin (Beta),
         Box.Center_Y - 2.0 * EF.Cos (Beta), 10.0, 200);
      Tool.Run;
      Check (Tool.Results.Num_Points_Used = 6, "all six points used");
      Check (abs Tool.Results.Item (2).Distance_To_Line > 3.0,
             "the occluded caliper is an outlier");
      Check (Tool.Results.RMS_Error > 1.0, "the outlier spoils the fit");

      Tool.Run_Params.Num_To_Ignore := 1;
      Tool.Run;
      Report (Tool, "outlier");
      Check (Tool.Results.Num_Points_Found = 6
             and then Tool.Results.Num_Points_Used = 5,
             "NumToIgnore 1: five points used");
      Check (not Tool.Results.Item (2).Used
             and then Tool.Results.Item (2).Found,
             "the outlier is found but not used");
      L := Tool.Results.Get_Line;
      Check (Distance_To (L, X0, Y0) < 0.02
             and then abs AMV.Misc.Norm_Angle (L.Rotation - Beta) < 2.0E-4,
             "the line is the edge again");
      Check (Tool.Results.RMS_Error < 0.02, "small RMS error again");
      Check (Tool.Results.Item (2).Distance_To_Line > 10.0,
             "the outlier's distance from the line");
   end Test_Outlier;

   procedure Test_Partial is
      Beta : constant Real := -0.57;
      X0   : constant Real := 150.0;
      Y0   : constant Real := 150.0;
      Tool : Ks_Find_Line_Tool;
   begin
      Section ("Find line: a partial edge, NumToIgnore and its decrement");
      --  A bright rectangle whose lower side is the edge for t in
      --  [-95, -5] along the segment: calipers 0, 1, 2 see it.
      Tool.Input_Image := TI.Blank (300, 300, 40);
      TI.Draw_Rectangle
        (Tool.Input_Image,
         X0 - 50.0 * EF.Cos (Beta) - 30.0 * EF.Sin (Beta),
         Y0 - 50.0 * EF.Sin (Beta) + 30.0 * EF.Cos (Beta),
         90.0, 60.0, Beta, 200);
      Set_Segment (Tool, X0, Y0, Beta);
      Tool.Run;
      Report (Tool, "partial");
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Num_Points_Found = 3
             and then Tool.Results.Num_Points_Used = 3,
             "three of six calipers find the edge");
      Check (Tool.Results.Item (0).Found and then Tool.Results.Item (2).Found
             and then not Tool.Results.Item (3).Found
             and then not Tool.Results.Item (5).Used
             and then Tool.Results.Item (5).X = 0.0
             and then Tool.Results.Item (5).Caliper_Results.Count = 0,
             "the first three found, the last three not");

      Tool.Run_Params.Num_To_Ignore := 2;
      Tool.Run;
      Check (Status_Is (Tool, "KS_EXCEPTION",
                        "FindLine: fewer than 2 points remain to fit"
                        & " (NumPointsFound = 3, NumToIgnore = 2)"),
             "NumToIgnore 2 leaves one point: Error");
      Check (Tool.Results.Count = 0, "and no results");
      Tool.Run_Params.Decrement_Num_To_Ignore := True;
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Num_Points_Used = 2,
             "DecrementNumToIgnore: one point ignored, two used");
   end Test_Partial;

   procedure Test_Failures is
      Tool : Ks_Find_Line_Tool;
   begin
      Section ("Find line: failures");
      Tool.Run;
      Check (Status_Is (Tool, "KS_IMAGE_NO_PIXELS_EXCEPTION",
                        "InputImage has no pixels"),
             "unallocated image");
      Tool.Input_Image := TI.Blank (100, 100, 40);
      Tool.Run;
      Check (Status_Is (Tool, "KS_EXCEPTION",
                        "FindLine: fewer than 2 points remain to fit"
                        & " (NumPointsFound = 0, NumToIgnore = 0)"),
             "a blank image: no points");
      Tool.Run_Params.Num_Calipers := 1;
      Tool.Run;
      Check (Status_Is (Tool, "KS_BAD_PARAMETER_EXCEPTION",
                        "RunParams.NumCalipers must be in 2 .. 1000"),
             "one caliper");
      Tool.Run_Params.Num_Calipers := 4;
      Tool.Run_Params.Num_To_Ignore := 3;
      Tool.Run;
      Check (Status_Is (Tool, "KS_BAD_PARAMETER_EXCEPTION",
                        "RunParams.NumToIgnore must be in 0 .."
                        & " NumCalipers - 2"),
             "NumToIgnore too large");
      Tool.Run_Params.Num_To_Ignore := 0;
      Tool.Run_Params.Expected_Line_Segment.Set_Start_End
        (5.0, 5.0, 5.0, 5.0);
      Tool.Run;
      Check (Status_Is (Tool, "KS_BAD_PARAMETER_EXCEPTION",
                        "RunParams.ExpectedLineSegment must have a length"
                        & " > 0"),
             "a segment of length 0");
      Tool.Run_Params.Expected_Line_Segment.Set_Start_End
        (5.0, 5.0, 95.0, 5.0);
      Tool.Run_Params.Caliper_Search_Length := 0.0;
      Tool.Run;
      Check (Status_Is (Tool, "KS_BAD_PARAMETER_EXCEPTION",
                        "RunParams.CaliperSearchLength must be > 0 and"
                        & " <= 4.0E150"),
             "a search length of 0");
      Tool.Run_Params.Caliper_Search_Length := 30.0;
      Tool.Run_Params.Caliper_Run_Params.Contrast_Threshold := -2.0;
      Tool.Run;
      Check (Status_Is (Tool, "KS_BAD_PARAMETER_EXCEPTION",
                        "RunParams.CaliperRunParams.ContrastThreshold must"
                        & " be >= 0"),
             "bad caliper parameters are named as such");
      Tool.Run_Params.Caliper_Run_Params.Contrast_Threshold := 5.0;
      declare
         Raised : Boolean := False;
         Box    : Ks_Rectangle_Affine;
      begin
         begin
            Box := Get_Caliper_Region (Tool.Run_Params, 4);
            Check (Box.Center_X < 0.0, "not reached");
         exception
            when Constraint_Error =>
               Raised := True;
         end;
         Check (Raised, "Get_Caliper_Region beyond NumCalipers");
      end;
   end Test_Failures;

   procedure Test_Regions is
      P   : Ks_Find_Line;
      Box : Ks_Rectangle_Affine;
   begin
      Section ("Find line: caliper regions");
      P.Expected_Line_Segment.Set_Start_End (10.0, 20.0, 110.0, 20.0);
      P.Expected_Line_Segment.Set_Selected_Space_Name ("#");
      P.Num_Calipers := 5;
      for I in 0 .. 4 loop
         Box := Get_Caliper_Region (P, I);
         Check (abs (Box.Center_X - (10.0 + 25.0 * Real (I))) < 1.0E-12
                and then Box.Center_Y = 20.0
                and then Box.Side_X_Length = 30.0
                and then Box.Side_Y_Length = 10.0
                and then abs (Box.Rotation - Pi / 2.0) < 1.0E-15
                and then Box.Skew = 0.0
                and then Box.Selected_Space_Name = "#",
                "caliper" & I'Image & " evenly spaced, across the segment");
      end loop;
   end Test_Regions;

   procedure Test_Fixture is
      Alpha : constant Real := -0.3;
      Scale : constant Real := 1.5;
      Fix   : constant Ks_Transform_2D_Linear :=
        Create (Scale * EF.Cos (Alpha), -Scale * EF.Sin (Alpha),
                Scale * EF.Sin (Alpha), Scale * EF.Cos (Alpha), 60.0, 140.0);
      --  Fixture (u, v) to pixel coordinates, 1.5 pixels per unit.
      Tree  : Ks_Coordinate_Space_Tree;
      Tool  : Ks_Find_Line_Tool;
      Beta  : constant Real := 0.35;
      --  The edge in the fixture: through (60, 10), direction Beta.
      PX, PY : Real;
      L      : Ks_Line;
   begin
      Section ("Find line: fixture space");
      Tool.Input_Image := TI.Blank (300, 300, 40);
      Tree.Add_Space ("@", "Fixture", Fix);
      Tool.Input_Image.Set_Coordinate_Space_Tree (Tree);
      Tool.Input_Image.Set_Selected_Space_Name ("@\Fixture");
      Fix.Map_Point (60.0, 10.0, PX, PY);
      TI.Draw_Half_Plane (Tool.Input_Image, PX, PY, Beta + Alpha, 200);
      Set_Segment (Tool, 60.0, 10.0, Beta, 40.0);
      Tool.Run_Params.Caliper_Search_Length := 20.0;
      Tool.Run;
      Report (Tool, "fixture");
      Check (Tool.Results.Num_Points_Used = 6, "six points");
      L := Tool.Results.Get_Line;
      Check (Distance_To (L, 60.0, 10.0) < 0.02
             and then abs AMV.Misc.Norm_Angle (L.Rotation - Beta) < 3.0E-4,
             "the line in fixture coordinates");
      Check (abs (Tool.Results.Get_Line_Segment.Length - 80.0) < 0.5,
             "the segment length in fixture units");
   end Test_Fixture;

   procedure Test_Kernel is
      Params  : KF.Ks_Find_Line_Run_Params;
      Results : KF.Ks_Find_Line_Results;
      Status  : K.Ks_Status;
      Count   : K.Int32;
      Item    : KF.Ks_Find_Line_Result;
      Line    : KS.Ks_Line;
      Segment : KS.Ks_Line_Segment;
      Region  : KS.Ks_Rectangle_Affine;
      RMS     : Real;
      NF, NU  : K.Int32;
      Copy    : KC.Ks_Caliper_Results;
      Id      : constant AMV.Kernels.Shapes.KT.Ks_Transform_2D_Linear :=
        (others => <>);
   begin
      Section ("Find line: kernel");
      KF.Run_Params_Default (Params, Status);
      Check (Status.Failure = K.Failure_None and then Params.Num_Calipers = 6,
             "ks_find_line_run_params_default");
      KF.Execute (null, Params, Id, Id, Results, Status);
      Check (Status.Failure = K.Failure_Image_No_Pixels
             and then Results = null, "null image");
      KF.Results_Count (null, Count, Status);
      Check (Status.Failure = K.Failure_None and then Count = 0,
             "null results: count 0");
      KF.Results_Item (null, 0, Item, Status);
      Check (Status.Failure = K.Failure_Index_Out_Of_Range,
             "null results: no item");
      KF.Results_Line (null, Line, Segment, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter,
             "null results: no line");
      KF.Results_Fit (null, RMS, NF, NU, Status);
      Check (Status.Failure = K.Failure_None and then NF = 0 and then NU = 0,
             "null results: no points");
      KF.Results_Caliper_Results (null, 0, Copy, Status);
      Check (Status.Failure = K.Failure_Index_Out_Of_Range
             and then Copy = null, "null results: no caliper results");
      KF.Caliper_Region (Params, 6, Region, Status);
      Check (Status.Failure = K.Failure_Index_Out_Of_Range,
             "caliper region beyond NumCalipers");
      Params.Caliper_Search_Direction := Zero / Zero;
      KF.Caliper_Region (Params, 0, Region, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter,
             "a NaN search direction");
      KF.Results_Destroy (Results);
      Check (Results = null, "destroy null");
   end Test_Kernel;

   procedure Test_Timing is
      Tool  : Ks_Find_Line_Tool;
      Start : Ada.Calendar.Time;
      Total : Duration;
      Runs  : constant := 10;
   begin
      Section ("Find line: timing");
      Tool.Input_Image := TI.Blank (640, 480, 40);
      TI.Draw_Half_Plane (Tool.Input_Image, 320.0, 240.0, 0.2, 200);
      Set_Segment (Tool, 320.0, 240.0, 0.2, 250.0);
      Tool.Run_Params.Num_Calipers := 20;
      Tool.Run_Params.Caliper_Search_Length := 60.0;
      Tool.Run_Params.Caliper_Projection_Length := 20.0;
      Start := Ada.Calendar.Clock;
      for I in 1 .. Runs loop
         Tool.Run;
      end loop;
      Total := Ada.Calendar."-" (Ada.Calendar.Clock, Start);
      Check (Tool.Results.Num_Points_Used = 20, "twenty points");
      Ada.Text_IO.Put_Line
        ("  find line with 20 calipers of 60 x 20 pixels on 640 x 480:"
         & Duration'Image (Total / Runs * 1000.0) & " ms per run");
   end Test_Timing;

   procedure Run_All is
   begin
      Test_Defaults;
      Test_Rotated_Edges;
      Test_Outlier;
      Test_Partial;
      Test_Failures;
      Test_Regions;
      Test_Fixture;
      Test_Kernel;
      Test_Timing;
   end Run_All;

   procedure Main is new AMV_Test_Support.Standalone (Run_All);
begin
   Main;
end Test_Find_Line;
