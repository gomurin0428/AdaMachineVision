--  Tests for AMV.Caliper (CogCaliperTool) and its kernel
--  AMV.Kernels.Caliper.
--
--  The scenes are drawn with AMV_Test_Images: half-planes give straight
--  edges at known positions, rectangles give bars of known width. Edges
--  are turned by generic angles (not ratios of small integers), for which
--  the renderer places an edge within about 0.002 pixel (see
--  AMV_Test_Images), so the 0.05 pixel tolerance measures the caliper.

pragma Validity_Checks ("F");
--  The kernel tests build NaNs on purpose.

with Ada.Calendar;
with Ada.Numerics.Long_Elementary_Functions;
with Ada.Text_IO;

with AMV;                    use AMV;
with AMV.Caliper;            use AMV.Caliper;
with AMV.Coordinate_Spaces;  use AMV.Coordinate_Spaces;
with AMV.Images;             use AMV.Images;
with AMV.Kernels;
with AMV.Kernels.Caliper;
with AMV.Kernels.Images;
with AMV.Kernels.Shapes;
with AMV.Kernels.Transforms;
with AMV.Tools;              use AMV.Tools;
with AMV.Transforms;         use AMV.Transforms;
with AMV_Test_Images;
with AMV_Test_Support;       use AMV_Test_Support;

procedure Test_Caliper is

   package EF renames Ada.Numerics.Long_Elementary_Functions;
   package K renames AMV.Kernels;
   package KC renames AMV.Kernels.Caliper;
   package KI renames AMV.Kernels.Images;
   package KS renames AMV.Kernels.Shapes;
   package KT renames AMV.Kernels.Transforms;
   package TI renames AMV_Test_Images;

   use type K.Int32;
   use type KC.Ks_Caliper_Results;
   use type KC.Ks_Caliper_Run_Params;
   use type KC.Ks_Caliper_Edge;
   use type KC.Ks_Caliper_Scorer;

   Pi : constant := Ada.Numerics.Pi;

   Zero : constant Real := Real'Value ("0.0");

   W : constant := 200;
   H : constant := 200;
   CX : constant := 100.0;
   CY : constant := 100.0;
   --  The default scene and the centre of the default region.

   function Status_Is
     (Tool      : Ks_Caliper_Tool;
      Exception_Name_Part : String;
      Message   : String) return Boolean
   is (Tool.Run_Status.Result = Error
       and then AMV.Tools.Exception_Name (Tool.Run_Status)
                  = "AMV." & Exception_Name_Part
       and then AMV.Tools.Message (Tool.Run_Status) = Message);

   procedure Report (Tool : Ks_Caliper_Tool; Description : String);
   --  Prints the run status when it is not Accept_Result.

   procedure Report (Tool : Ks_Caliper_Tool; Description : String) is
   begin
      if Tool.Run_Status.Result /= Accept_Result then
         Ada.Text_IO.Put_Line
           ("  " & Description & ": " & Tool.Run_Status.Result'Image & " "
            & Exception_Name (Tool.Run_Status) & " "
            & Message (Tool.Run_Status));
      end if;
   end Report;

   procedure Draw_Step
     (Image       : in out Ks_Image_8_Grey;
      Theta       : Real;
      Offset      : Real;
      Rising      : Boolean;
      Value       : Grey_8;
      Center_X    : Real := CX;
      Center_Y    : Real := CY);
   --  Fills the side of the line perpendicular to direction Theta through
   --  Center + Offset (cos Theta, sin Theta) that lies after it along
   --  Theta (Rising) or before it, with Value.

   procedure Draw_Step
     (Image       : in out Ks_Image_8_Grey;
      Theta       : Real;
      Offset      : Real;
      Rising      : Boolean;
      Value       : Grey_8;
      Center_X    : Real := CX;
      Center_Y    : Real := CY)
   is
      --  Draw_Half_Plane fills the left normal of its line: for the line
      --  direction Theta - Pi/2 that is +(cos Theta, sin Theta).
      Line : constant Real := (if Rising then Theta - Pi / 2.0
                               else Theta + Pi / 2.0);
   begin
      TI.Draw_Half_Plane
        (Image,
         Center_X + Offset * EF.Cos (Theta),
         Center_Y + Offset * EF.Sin (Theta),
         Line, Value);
   end Draw_Step;

   procedure Set_Region
     (Tool   : in out Ks_Caliper_Tool;
      Theta  : Real;
      Search : Real := 60.0;
      Across : Real := 20.0) is
   begin
      Tool.Region.Set_Center_Lengths_Rotation_Skew
        (CX, CY, Search, Across, Theta, 0.0);
   end Set_Region;

   ---------------------------------------------------------------------

   procedure Test_Defaults is
      P    : constant Ks_Caliper := (others => <>);
      Tool : Ks_Caliper_Tool;
      KP   : KC.Ks_Caliper_Run_Params;
      S    : K.Ks_Status;
   begin
      Section ("Caliper: defaults");
      Check (Edge_Mode (P.Edge_Mode) = Single_Edge, "EdgeMode SingleEdge");
      Check (Polarity (P.Edge_0_Polarity) = Dont_Care
             and then Polarity (P.Edge_1_Polarity) = Dont_Care,
             "polarities DontCare");
      Check (P.Edge_0_Position = 0.0 and then P.Edge_1_Position = 10.0,
             "Edge0Position 0, Edge1Position 10");
      Check (P.Contrast_Threshold = 5.0, "ContrastThreshold 5");
      Check (P.Filter_Half_Size_In_Pixels = 2, "FilterHalfSizeInPixels 2");
      Check (P.Max_Results = 1, "MaxResults 1");
      Check (Sampling_Mode (P.Sampling_Mode) = Bilinear_Interpolation,
             "SamplingMode BilinearInterpolation");
      Check (Count (P.Single_Edge_Scorers) = 1
             and then Kind (P.Single_Edge_Scorers.Items (0)) = Contrast
             and then Enabled (P.Single_Edge_Scorers.Items (0)),
             "SingleEdgeScorers: one enabled contrast scorer");
      Check (Count (P.Two_Edge_Scorers) = 1
             and then Kind (P.Two_Edge_Scorers.Items (0)) = Size_Diff_Norm
             and then Enabled (P.Two_Edge_Scorers.Items (0)),
             "TwoEdgeScorers: one enabled SizeDiffNorm scorer");
      KC.Run_Params_Default (KP, S);
      Check (S.Failure = K.Failure_None and then KP = P,
             "ks_caliper_run_params_default gives the record defaults");
      Check (Tool.Results.Count = 0, "no results before a run");
      Check (Tool.Results.Get_Projection_Values'Length = 0,
             "no profile before a run");
      Check (Code (Pair) = 2 and then Code (Light_To_Dark) = 2
             and then Code (Bilinear_Accurate) = 4
             and then Code (Straddle) = 8,
             "codes are VisionPro's values");
   end Test_Defaults;

   procedure Test_Failures is
      Tool : Ks_Caliper_Tool;
   begin
      Section ("Caliper: failures");
      Tool.Run;
      Check (Status_Is (Tool, "KS_IMAGE_NO_PIXELS_EXCEPTION",
                        "InputImage has no pixels"),
             "unallocated image");

      Tool.Input_Image := TI.Blank (W, H, 40);
      Draw_Step (Tool.Input_Image, 0.3, 2.0, True, 200);
      Set_Region (Tool, 0.3);
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Count = 1, "a valid run");

      Tool.Run_Params.Contrast_Threshold := -1.0;
      Tool.Run;
      Check (Status_Is (Tool, "KS_BAD_PARAMETER_EXCEPTION",
                        "RunParams.ContrastThreshold must be >= 0"),
             "negative ContrastThreshold");
      Check (Tool.Results.Count = 0, "a failed run clears the results");
      Tool.Run_Params.Contrast_Threshold := 5.0;

      Tool.Run_Params.Filter_Half_Size_In_Pixels := 0;
      Tool.Run;
      Check (Status_Is (Tool, "KS_BAD_PARAMETER_EXCEPTION",
                        "RunParams.FilterHalfSizeInPixels must be in"
                        & " 1 .. 1000"),
             "FilterHalfSizeInPixels 0");
      Tool.Run_Params.Filter_Half_Size_In_Pixels := 2;

      Tool.Run_Params.Max_Results := 0;
      Tool.Run;
      Check (Status_Is (Tool, "KS_BAD_PARAMETER_EXCEPTION",
                        "RunParams.MaxResults must be in 1 .. 1000"),
             "MaxResults 0");
      Tool.Run_Params.Max_Results := 1;

      Tool.Run_Params.Edge_Mode := 7;
      Tool.Run;
      Check (Status_Is (Tool, "KS_BAD_PARAMETER_EXCEPTION",
                        "RunParams.EdgeMode must be SingleEdge (1) or"
                        & " Pair (2)"),
             "unknown EdgeMode code");
      Tool.Run_Params.Edge_Mode := Code (Single_Edge);

      Tool.Run_Params.Edge_0_Polarity := 0;
      Tool.Run;
      Check (Tool.Run_Status.Result = Error, "unknown polarity code");
      Tool.Run_Params.Edge_0_Polarity := Code (Dont_Care);

      Tool.Run_Params.Sampling_Mode := 3;
      Tool.Run;
      Check (Tool.Run_Status.Result = Error, "unknown sampling mode code");
      Tool.Run_Params.Sampling_Mode := Code (Bilinear_Accurate);
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Count = 1, "BilinearAccurate runs");

      Tool.Region.Set_Side_X_Length (0.0);
      Tool.Run;
      Check (Status_Is (Tool, "KS_BAD_PARAMETER_EXCEPTION",
                        "Region.SideXLength must be > 0"),
             "side X of length 0");
      Set_Region (Tool, 0.3, 60.0, 0.0);
      Tool.Run;
      Check (Status_Is (Tool, "KS_BAD_PARAMETER_EXCEPTION",
                        "Region.SideYLength must be > 0"),
             "side Y of length 0");
      Set_Region (Tool, 0.3, 40_000.0, 10.0);
      Tool.Run;
      Check (Status_Is (Tool, "KS_BAD_PARAMETER_EXCEPTION",
                        "Region: side X is longer than 32768 pixels"),
             "side X too long");
      Set_Region (Tool, 0.3, 20_000.0, 1_000.0);
      Tool.Run;
      Check (Status_Is (Tool, "KS_BAD_PARAMETER_EXCEPTION",
                        "Region covers more than 16777216 samples"),
             "too many samples");
      Set_Region (Tool, 0.3);

      --  Scorers in the wrong list, or needing an expected width.
      Tool.Run_Params.Single_Edge_Scorers.Items (0) := New_Scorer (Straddle);
      Tool.Run;
      Check (Status_Is (Tool, "KS_BAD_PARAMETER_EXCEPTION",
                        "RunParams.SingleEdgeScorers(0).Kind measures pairs:"
                        & " it does not belong to SingleEdgeScorers"),
             "a pair scorer among the single edge scorers");
      Tool.Run_Params.Single_Edge_Scorers := KC.Default_Single_Edge_Scorers;
      Tool.Run_Params.Edge_Mode := Code (Pair);
      Tool.Run_Params.Edge_1_Position := -3.0;
      Tool.Run;
      Check (Status_Is (Tool, "KS_BAD_PARAMETER_EXCEPTION",
                        "RunParams.Edge1Position must be greater than"
                        & " Edge0Position for the size scorers"),
             "a size scorer without a positive expected width");
      Tool.Run_Params := (others => <>);
      Tool.Run_Params.Two_Edge_Scorers.Items (0).Y1 := 1.5;
      Tool.Run;
      Check (Status_Is (Tool, "KS_BAD_PARAMETER_EXCEPTION",
                        "RunParams.TwoEdgeScorers(0).Y1 must be within"
                        & " [0, 1]"),
             "a scorer parameter out of range is checked even when unused");
      Tool.Run_Params := (others => <>);
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result, "back to a valid run");
   end Test_Failures;

   procedure Test_Single_Edges is
      Thetas  : constant array (1 .. 5) of Real := [0.3, 1.1, 2.0, -0.7, 2.9];
      Offsets : constant array (1 .. 3) of Real := [-10.37, 3.2, 12.61];
      Worst   : Real := 0.0;
      Worst_N : Real := 0.0;
   begin
      Section ("Caliper: single edges at known positions");
      for Theta of Thetas loop
         for Offset of Offsets loop
            for Rising in Boolean loop
               for Noisy in Boolean loop
                  declare
                     Tool : Ks_Caliper_Tool;
                     R    : Ks_Caliper_Result;
                     Err  : Real;
                  begin
                     Tool.Input_Image := TI.Blank (W, H, 40);
                     Draw_Step (Tool.Input_Image, Theta, Offset, Rising, 200);
                     if Noisy then
                        TI.Add_Noise (Tool.Input_Image, 12.0, 7);
                     end if;
                     Set_Region (Tool, Theta);
                     Tool.Run;
                     Report (Tool, "single edge");
                     Check (Tool.Run_Status.Result = Accept_Result
                            and then Tool.Results.Count = 1,
                            "one edge found");
                     if Tool.Results.Count = 1 then
                        R := Tool.Results.Item (0);
                        Err := abs (R.Position - Offset);
                        if Noisy then
                           Worst_N := Real'Max (Worst_N, Err);
                        else
                           Worst := Real'Max (Worst, Err);
                        end if;
                        Check (Err < (if Noisy then 0.2 else 0.05),
                               "edge position" & Theta'Image & Offset'Image
                               & Rising'Image & Noisy'Image
                               & " error" & Err'Image);
                        Check_Near (R.Position_X,
                                    CX + R.Position * EF.Cos (Theta), 1.0E-9,
                                    "PositionX on the centre line");
                        Check_Near (R.Position_Y,
                                    CY + R.Position * EF.Sin (Theta), 1.0E-9,
                                    "PositionY on the centre line");
                        Check ((R.Edge_0.Contrast > 0.0) = Rising,
                               "the sign of the contrast is the polarity");
                        Check (abs R.Edge_0.Contrast > 100.0
                               and then abs R.Edge_0.Contrast < 180.0,
                               "contrast between 100 and 180 (a step of"
                               & " 160 seen by the filter)");
                        Check (R.Edge_1 = R.Edge_0 and then R.Width = 0.0,
                               "a single edge result: Edge1 = Edge0,"
                               & " Width 0");
                        Check_Near (R.Score, abs R.Edge_0.Contrast / 255.0,
                                    1.0E-12, "default score contrast / 255");
                     end if;
                  end;
               end loop;
            end loop;
         end loop;
      end loop;
      Ada.Text_IO.Put_Line
        ("  worst position error:" & Worst'Image & " px without noise,"
         & Worst_N'Image & " px with noise");
   end Test_Single_Edges;

   procedure Test_Polarity_And_Threshold is
      Theta : constant Real := 0.83;
      Tool  : Ks_Caliper_Tool;
   begin
      Section ("Caliper: polarity and contrast threshold");
      --  A bright band from -9.3 to +7.6 along the search direction.
      Tool.Input_Image := TI.Blank (W, H, 50);
      Draw_Step (Tool.Input_Image, Theta, -9.3, True, 210);
      Draw_Step (Tool.Input_Image, Theta, 7.6, True, 50);
      Set_Region (Tool, Theta);

      Tool.Run_Params.Edge_0_Polarity := Code (Dark_To_Light);
      Tool.Run;
      Check (Tool.Results.Count = 1
             and then abs (Tool.Results.Item (0).Position + 9.3) < 0.05,
             "DarkToLight finds the rising edge");
      Tool.Run_Params.Edge_0_Polarity := Code (Light_To_Dark);
      Tool.Run;
      Check (Tool.Results.Count = 1
             and then abs (Tool.Results.Item (0).Position - 7.6) < 0.05,
             "LightToDark finds the falling edge");
      Tool.Run_Params.Edge_0_Polarity := Code (Dont_Care);
      Tool.Run_Params.Max_Results := 5;
      Tool.Run;
      Check (Tool.Results.Count = 2, "DontCare finds both edges");

      --  A weak edge (contrast 20).
      Tool.Input_Image := TI.Blank (W, H, 100);
      Draw_Step (Tool.Input_Image, Theta, 1.7, True, 120);
      Tool.Run_Params.Contrast_Threshold := 30.0;
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Count = 0,
             "an edge below ContrastThreshold is not found (Accept, 0)");
      Tool.Run_Params.Contrast_Threshold := 10.0;
      Tool.Run;
      Check (Tool.Results.Count = 1
             and then abs (Tool.Results.Item (0).Position - 1.7) < 0.05,
             "an edge above ContrastThreshold is found");
   end Test_Polarity_And_Threshold;

   procedure Test_Pairs is
      Thetas : constant array (1 .. 3) of Real := [0.41, 1.93, -2.6];
      Widths : constant array (1 .. 3) of Real := [5.3, 9.17, 14.4];
      Worst  : Real := 0.0;
   begin
      Section ("Caliper: pairs on bars");
      for Theta of Thetas loop
         for Width of Widths loop
            declare
               Tool   : Ks_Caliper_Tool;
               Offset : constant Real := 2.37;
               R      : Ks_Caliper_Result;
            begin
               Tool.Input_Image := TI.Blank (W, H, 30);
               TI.Draw_Rectangle
                 (Tool.Input_Image,
                  CX + Offset * EF.Cos (Theta), CY + Offset * EF.Sin (Theta),
                  Width, 300.0, Theta, 220);
               Set_Region (Tool, Theta);
               Tool.Run_Params.Edge_Mode := Code (Pair);
               Tool.Run_Params.Edge_0_Polarity := Code (Dark_To_Light);
               Tool.Run_Params.Edge_1_Polarity := Code (Light_To_Dark);
               Tool.Run_Params.Edge_0_Position := 0.0;
               Tool.Run_Params.Edge_1_Position := Width;
               Tool.Run;
               Report (Tool, "pair");
               Check (Tool.Results.Count = 1, "one pair");
               if Tool.Results.Count = 1 then
                  R := Tool.Results.Item (0);
                  Worst := Real'Max (Worst, abs (R.Width - Width));
                  Check (abs (R.Width - Width) < 0.1,
                         "pair width" & Width'Image & " got" & R.Width'Image);
                  Check (abs (R.Position - Offset) < 0.05,
                         "pair centre" & R.Position'Image);
                  Check_Near (R.Position,
                              (R.Edge_0.Position + R.Edge_1.Position) / 2.0,
                              1.0E-9, "the pair's position is the mean");
                  Check (R.Edge_0.Contrast > 0.0
                         and then R.Edge_1.Contrast < 0.0,
                         "edge 0 rises, edge 1 falls");
                  Check (R.Score > 0.95, "SizeDiffNorm score near 1");
               end if;
            end;
         end loop;
      end loop;
      Ada.Text_IO.Put_Line ("  worst pair width error:" & Worst'Image);

      --  The size scorer picks the bar of the expected width.
      declare
         Tool  : Ks_Caliper_Tool;
         Theta : constant Real := 0.62;
      begin
         Tool.Input_Image := TI.Blank (W, H, 30);
         TI.Draw_Rectangle
           (Tool.Input_Image, CX - 15.0 * EF.Cos (Theta),
            CY - 15.0 * EF.Sin (Theta), 4.0, 300.0, Theta, 220);
         TI.Draw_Rectangle
           (Tool.Input_Image, CX + 10.0 * EF.Cos (Theta),
            CY + 10.0 * EF.Sin (Theta), 11.0, 300.0, Theta, 220);
         Set_Region (Tool, Theta);
         Tool.Run_Params.Edge_Mode := Code (Pair);
         Tool.Run_Params.Edge_0_Polarity := Code (Dark_To_Light);
         Tool.Run_Params.Edge_1_Polarity := Code (Light_To_Dark);
         Tool.Run_Params.Edge_1_Position := 11.0;
         Tool.Run_Params.Max_Results := 3;
         Tool.Run;
         Check (Tool.Results.Count = 3, "three pairs (4, 11 and across)");
         Check (abs (Tool.Results.Item (0).Width - 11.0) < 0.1
                and then abs (Tool.Results.Item (0).Position - 10.0) < 0.05,
                "the 11 pixel bar is the best pair");
         Tool.Run_Params.Edge_1_Position := 4.0;
         Tool.Run;
         Check (abs (Tool.Results.Item (0).Width - 4.0) < 0.1
                and then abs (Tool.Results.Item (0).Position + 15.0) < 0.05,
                "with Edge1Position 4 the 4 pixel bar is the best");
      end;
   end Test_Pairs;

   procedure Test_Max_Results is
      Theta : constant Real := -1.23;
      Tool  : Ks_Caliper_Tool;
   begin
      Section ("Caliper: MaxResults and ordering");
      --  Rising steps of 40, 100 and 70 grey levels.
      Tool.Input_Image := TI.Blank (W, H, 20);
      Draw_Step (Tool.Input_Image, Theta, -18.0, True, 60);
      Draw_Step (Tool.Input_Image, Theta, 0.4, True, 160);
      Draw_Step (Tool.Input_Image, Theta, 15.0, True, 230);
      Set_Region (Tool, Theta);
      Tool.Run_Params.Max_Results := 10;
      Tool.Run;
      Check (Tool.Results.Count = 3, "three edges");
      if Tool.Results.Count = 3 then
         Check (Tool.Results.Item (0).Score >= Tool.Results.Item (1).Score
                and then Tool.Results.Item (1).Score
                           >= Tool.Results.Item (2).Score,
                "sorted by score");
         Check (abs (Tool.Results.Item (0).Position - 0.4) < 0.05
                and then abs (Tool.Results.Item (1).Position - 15.0) < 0.05
                and then abs (Tool.Results.Item (2).Position + 18.0) < 0.05,
                "strongest first: 100, 70, 40");
      end if;
      Tool.Run_Params.Max_Results := 2;
      Tool.Run;
      Check (Tool.Results.Count = 2
             and then abs (Tool.Results.Item (1).Position - 15.0) < 0.05,
             "MaxResults 2 keeps the two best");
      declare
         Raised : Boolean := False;
         R      : Ks_Caliper_Result;
      begin
         begin
            R := Tool.Results.Item (2);
            Check (R.Score < 0.0, "not reached");
         exception
            when Constraint_Error =>
               Raised := True;
         end;
         Check (Raised, "Item beyond Count raises Constraint_Error");
      end;
   end Test_Max_Results;

   procedure Test_Position_Scorer is
      Theta : constant Real := 2.37;
      Tool  : Ks_Caliper_Tool;
      S     : Ks_Caliper_Scorer := New_Scorer (Position);
      X0, X1, XC, Y0, Y1 : Real;
   begin
      Section ("Caliper: the position scorer");
      Tool.Input_Image := TI.Blank (W, H, 50);
      Draw_Step (Tool.Input_Image, Theta, -10.0, True, 210);
      Draw_Step (Tool.Input_Image, Theta, 8.0, True, 50);
      Set_Region (Tool, Theta);

      Set_XY_Parameters (S, 20.0, 20.0, 8.0, 0.0, 1.0);
      Get_XY_Parameters (S, X0, X1, XC, Y0, Y1);
      Check (X0 = 20.0 and then X1 = 20.0 and then XC = 8.0
             and then Y0 = 0.0 and then Y1 = 1.0, "Get_XY_Parameters");
      Add (Tool.Run_Params.Single_Edge_Scorers, S);
      Check (Count (Tool.Run_Params.Single_Edge_Scorers) = 2, "Add");
      Tool.Run;
      Check (Tool.Results.Count = 1
             and then abs (Tool.Results.Item (0).Position - 8.0) < 0.05,
             "XC = 8 picks the edge at +8");
      if Tool.Results.Count = 1 then
         Check_Near (Tool.Results.Item (0).Score,
                     abs Tool.Results.Item (0).Edge_0.Contrast / 255.0
                     * (1.0 - abs (Tool.Results.Item (0).Position - 8.0)
                                / 20.0),
                     1.0E-9, "the score is the product of both scorers");
      end if;
      Set_XY_Parameters (Tool.Run_Params.Single_Edge_Scorers.Items (1),
                         20.0, 20.0, -10.0, 0.0, 1.0);
      Tool.Run;
      Check (Tool.Results.Count = 1
             and then abs (Tool.Results.Item (0).Position + 10.0) < 0.05,
             "XC = -10 picks the edge at -10");
      Set_Enabled (Tool.Run_Params.Single_Edge_Scorers.Items (1), False);
      Tool.Run_Params.Single_Edge_Scorers.Items (0).Enabled := 0;
      Tool.Run_Params.Max_Results := 2;
      Tool.Run;
      Check (Tool.Results.Count = 2
             and then Tool.Results.Item (0).Score = 1.0
             and then Tool.Results.Item (1).Score = 1.0,
             "no enabled scorer: every score is 1");
      Remove_At (Tool.Run_Params.Single_Edge_Scorers, 0);
      Check (Count (Tool.Run_Params.Single_Edge_Scorers) = 1
             and then Kind (Tool.Run_Params.Single_Edge_Scorers.Items (0))
                        = Position,
             "Remove_At");
      Clear (Tool.Run_Params.Single_Edge_Scorers);
      Check (Count (Tool.Run_Params.Single_Edge_Scorers) = 0, "Clear");
      declare
         Raised : Boolean := False;
      begin
         begin
            Set_XY_Parameters (S, -1.0, 1.0, 0.0, 0.0, 1.0);
         exception
            when Ks_Bad_Parameter_Exception =>
               Raised := True;
         end;
         Check (Raised and then S.X0 = 20.0,
                "a negative X0 is rejected and the scorer kept");
      end;

      --  Normalised position: XC = 0.3 of the half length (30 px) = +9.
      Tool.Run_Params := (others => <>);
      S := New_Scorer (Position_Norm);
      Set_XY_Parameters (S, 0.2, 0.2, 0.3, 0.0, 1.0);
      Add (Tool.Run_Params.Single_Edge_Scorers, S);
      Tool.Run;
      Check (Tool.Results.Count = 1
             and then abs (Tool.Results.Item (0).Position - 8.0) < 0.05,
             "PositionNorm near +0.3 picks the edge at +8");
      S := New_Scorer (Position_Neg);
      Set_XY_Parameters (S, 20.0, 20.0, -8.0, 0.0, 1.0);
      Tool.Run_Params.Single_Edge_Scorers.Items (1) := S;
      Tool.Run;
      Check (Tool.Results.Count = 1
             and then abs (Tool.Results.Item (0).Position - 8.0) < 0.05,
             "PositionNeg at -8 picks the edge at +8");
   end Test_Position_Scorer;

   procedure Test_Fixture is
      Alpha  : constant Real := 0.4;
      Scale  : constant Real := 2.0;
      Fix    : constant Ks_Transform_2D_Linear :=
        Create (Scale * EF.Cos (Alpha), -Scale * EF.Sin (Alpha),
                Scale * EF.Sin (Alpha), Scale * EF.Cos (Alpha), 30.0, 20.0);
      --  Fixture (u, v) to root (= pixel) coordinates: 2 pixels per unit.
      Tree   : Ks_Coordinate_Space_Tree;
      Tool   : Ks_Caliper_Tool;
      Phi    : constant Real := 0.7;
      U0     : constant Real := 30.0;
      V0     : constant Real := 25.0;
      Off    : constant Real := 4.3;
      --  The region in the fixture: centre (U0, V0), rotation Phi; the
      --  edge Off fixture units along it.
      PX, PY : Real;
      R      : Ks_Caliper_Result;
   begin
      Section ("Caliper: fixture space");
      Tool.Input_Image := TI.Blank (W, H, 40);
      Tree.Add_Space ("@", "Fixture", Fix);
      Tool.Input_Image.Set_Coordinate_Space_Tree (Tree);
      Tool.Input_Image.Set_Selected_Space_Name ("@\Fixture");
      Fix.Map_Point (U0, V0, PX, PY);
      Draw_Step (Tool.Input_Image, Phi + Alpha, Off * Scale, True, 200,
                 PX, PY);
      Tool.Region.Set_Center_Lengths_Rotation_Skew
        (U0, V0, 30.0, 10.0, Phi, 0.0);
      Tool.Run;
      Report (Tool, "fixture");
      Check (Tool.Results.Count = 1, "the edge is found in the fixture");
      if Tool.Results.Count = 1 then
         R := Tool.Results.Item (0);
         Check (abs (R.Position - Off) < 0.03,
                "Position in fixture units" & R.Position'Image);
         Check (abs (R.Position_X - (U0 + Off * EF.Cos (Phi))) < 0.03
                and then abs (R.Position_Y - (V0 + Off * EF.Sin (Phi)))
                           < 0.03,
                "PositionX/Y in the fixture");
         Check (Tool.Results.Get_Projection_Values'Length = 60,
                "60 samples: 30 units of 2 pixels");
      end if;

      --  The same region given in pixel space.
      Tool.Region.Set_Selected_Space_Name ("#");
      Tool.Region.Set_Center_Lengths_Rotation_Skew
        (PX, PY, 60.0, 20.0, Phi + Alpha, 0.0);
      Tool.Run;
      Check (Tool.Results.Count = 1
             and then abs (Tool.Results.Item (0).Position - Off) < 0.03,
             "a region in pixel space, results in the fixture");
   end Test_Fixture;

   procedure Test_Profiles is
      Theta : constant Real := 0.3;
      Tool  : Ks_Caliper_Tool;
   begin
      Section ("Caliper: profiles");
      Tool.Input_Image := TI.Blank (W, H, 40);
      Draw_Step (Tool.Input_Image, Theta, 0.0, True, 200);
      Set_Region (Tool, Theta);
      Tool.Run;
      declare
         P : constant Real_Array := Tool.Results.Get_Projection_Values;
         F : constant Real_Array := Tool.Results.Get_Filtered_Values;
         Shared : constant Ks_Caliper_Results := Tool.Results;
      begin
         Check (P'First = 0 and then P'Length = 60 and then F'Length = 60,
                "60 samples along 60 pixels");
         Check (abs (P (0) - 40.0) < 0.5 and then abs (P (59) - 200.0) < 0.5,
                "the profile runs from 40 to 200");
         Check (F (59) = 0.0 and then F (29) > 130.0
                and then F (29) >= F (28) and then F (29) >= F (30),
                "the filter peaks at the centre boundary; the last is 0");
         Tool.Run_Params.Contrast_Threshold := 300.0;
         Tool.Run;
         Check (Tool.Results.Count = 0 and then Shared.Count = 1,
                "copies of the results keep the earlier run");
      end;
   end Test_Profiles;

   procedure Test_Timing is
      Tool  : Ks_Caliper_Tool;
      Start : Ada.Calendar.Time;
      Total : Duration;
      Runs  : constant := 20;
   begin
      Section ("Caliper: timing");
      Tool.Input_Image := TI.Blank (640, 480, 40);
      Draw_Step (Tool.Input_Image, 0.2, 0.0, True, 200, 320.0, 240.0);
      Tool.Region.Set_Center_Lengths_Rotation_Skew
        (320.0, 240.0, 400.0, 100.0, 0.2, 0.0);
      Start := Ada.Calendar.Clock;
      for I in 1 .. Runs loop
         Tool.Run;
      end loop;
      Total := Ada.Calendar."-" (Ada.Calendar.Clock, Start);
      Check (Tool.Results.Count = 1, "the edge is found");
      Ada.Text_IO.Put_Line
        ("  a 400 x 100 pixel caliper on a 640 x 480 image:"
         & Duration'Image (Total / Runs * 1000.0) & " ms per run");
   end Test_Timing;

   procedure Test_Kernel is
      Image   : KI.Ks_Image_8_Grey;
      Region  : KS.Ks_Rectangle_Affine :=
        (Center_X => 50.0, Center_Y => 50.0, Side_X_Length => 40.0,
         Side_Y_Length => 10.0, Rotation => 0.0, Skew => 0.0);
      Id      : constant KT.Ks_Transform_2D_Linear := (others => <>);
      Params  : KC.Ks_Caliper_Run_Params;
      Results : KC.Ks_Caliper_Results;
      Copy    : KC.Ks_Caliper_Results;
      Status  : K.Ks_Status;
      Count   : K.Int32;
      Item    : KC.Ks_Caliper_Result;
      Value   : Real;
      NaN     : constant Real := Zero / Zero;
      Scorer  : KC.Ks_Caliper_Scorer;
      Other   : KC.Ks_Caliper_Scorer;
      List    : KC.Ks_Caliper_Scorers;

      function Message return String is
        (String (Status.Message) (1 .. Natural (Status.Length)));
   begin
      Section ("Caliper: kernel");
      KC.Execute (null, Region, Id, Id, Params, Results, Status);
      Check (Status.Failure = K.Failure_Image_No_Pixels and then Results = null
             and then Message = "InputImage has no pixels",
             "null image");
      KI.Create (100, 100, 40, Image, Status);
      for Y in 0 .. 99 loop
         for X in 52 .. 99 loop
            KI.Set_Pixel (Image, K.Int32 (X), K.Int32 (Y), 200, Status);
         end loop;
      end loop;
      KC.Execute (Image, Region, Id, Id, Params, Results, Status);
      Check (Status.Failure = K.Failure_None and then Results /= null,
             "a run on an axis-aligned step");
      KC.Results_Count (Results, Count, Status);
      Check (Count = 1, "one edge");
      KC.Results_Item (Results, 0, Item, Status);
      Check (abs (Item.Position - 1.5) < 1.0E-9,
             "the step between pixels 51 and 52 is at 51.5"
             & Item.Position'Image);
      KC.Results_Item (Results, 1, Item, Status);
      Check (Status.Failure = K.Failure_Index_Out_Of_Range,
             "Item beyond Count");
      KC.Results_Projection_Value (Results, 40, Value, Status);
      Check (Status.Failure = K.Failure_Index_Out_Of_Range,
             "profile index beyond the profile");
      KC.Results_Filtered_Value (Results, 21, Value, Status);
      Check (Status.Failure = K.Failure_None and then Value = 120.0,
             "filter value at the step");
      KC.Results_Duplicate (Results, Copy, Status);
      KC.Results_Count (Copy, Count, Status);
      Check (Copy /= null and then Count = 1, "duplicate");
      KC.Results_Destroy (Copy);
      KC.Results_Destroy (Results);
      Check (Results = null, "destroy");
      KC.Results_Count (null, Count, Status);
      Check (Status.Failure = K.Failure_None and then Count = 0,
             "null results have no items");
      KC.Results_Item (null, 0, Item, Status);
      Check (Status.Failure = K.Failure_Index_Out_Of_Range,
             "Item of null results");
      KC.Results_Duplicate (null, Copy, Status);
      Check (Status.Failure = K.Failure_None and then Copy = null,
             "duplicate of null");

      --  Non-finite and out-of-bound arguments.
      Params.Contrast_Threshold := NaN;
      KC.Execute (Image, Region, Id, Id, Params, Results, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter and then Results = null
             and then Message = "RunParams.ContrastThreshold must be >= 0",
             "NaN ContrastThreshold");
      Params := (others => <>);
      Params.Edge_1_Position := 1.0 / Zero;
      KC.Execute (Image, Region, Id, Id, Params, Results, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then Message = "RunParams.Edge1Position must be finite and"
                                & " within +/-1.0E150",
             "infinite Edge1Position");
      Params := (others => <>);
      Region.Rotation := NaN;
      KC.Execute (Image, Region, Id, Id, Params, Results, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter and then Results = null,
             "NaN region rotation");
      Region.Rotation := 0.0;
      KC.Execute (Image, Region, (A => NaN, others => <>), Id, Params,
                  Results, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then Message = "Pixel_From_Region must be finite and within"
                                & " +/-1.0E150",
             "NaN transform");
      KC.Execute (Image, Region, Id,
                  (A => 1.0E150, D => 1.0E150, others => <>), Params,
                  Results, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then Message = "Region: the search length exceeds 2.0E150"
                                & " in the selected space",
             "a selected space too large");
      KC.Execute (Image, Region, (A => 0.0, others => <>), Id, Params,
                  Results, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then Message = "Region: side X maps to a point in pixel"
                                & " space",
             "a singular transform");
      Region.Center_X := 1.0E149;
      KC.Execute (Image, Region, Id, Id, Params, Results, Status);
      KC.Results_Count (Results, Count, Status);
      Check (Results /= null and then Count = 0,
             "a region far outside the image finds nothing");
      KC.Results_Destroy (Results);

      --  Scorers.
      KC.Scorer_Default (9, Scorer, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter, "unknown scorer kind");
      KC.Scorer_Default (KC.Scorer_Straddle, Scorer, Status);
      Check (Status.Failure = K.Failure_None
             and then Scorer.Kind = KC.Scorer_Straddle,
             "straddle scorer");
      KC.Scorer_Set_XY_Parameters (Scorer, 1.0, 1.0, NaN, 0.0, 1.0, Other,
                                   Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then Other = Scorer, "NaN xc is rejected");
      for I in 1 .. 8 loop
         KC.Scorers_Add (List, Scorer, Status);
      end loop;
      Check (List.Count = 8, "eight scorers");
      KC.Scorers_Add (List, Scorer, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter and then List.Count = 8,
             "a full list");
      KC.Scorers_Remove_At (List, 8, Status);
      Check (Status.Failure = K.Failure_Index_Out_Of_Range,
             "RemoveAt beyond Count");
      List.Count := -1;
      KC.Scorers_Add (List, Scorer, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter,
             "a list with a bad Count");
      KI.Destroy (Image, Status);
   end Test_Kernel;

   procedure Run_All is
   begin
      Test_Defaults;
      Test_Failures;
      Test_Single_Edges;
      Test_Polarity_And_Threshold;
      Test_Pairs;
      Test_Max_Results;
      Test_Position_Scorer;
      Test_Fixture;
      Test_Profiles;
      Test_Kernel;
      Test_Timing;
   end Run_All;

   procedure Main is new AMV_Test_Support.Standalone (Run_All);
begin
   Main;
end Test_Caliper;
