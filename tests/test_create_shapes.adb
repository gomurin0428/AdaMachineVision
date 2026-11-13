--  Tests for AMV.Dimensioning.Create_Shapes (the CogCreate*Tool classes of
--  Cognex.VisionPro.Dimensioning) and its kernel AMV.Kernels.Create_Shapes.
--
--  The expected shapes are worked out by hand in the comments. A fixture
--  space (a rotation by 0.5 and a translation by (100, 50)) shows that the
--  inputs are mapped into the image's selected space and the created shape
--  is expressed there; the created shapes are then measured again by the
--  tools of AMV.Dimensioning.

pragma Validity_Checks ("F");

with Ada.Calendar;
with Ada.Characters.Handling;
with Ada.Exceptions;
with Ada.Numerics.Long_Elementary_Functions;
with Ada.Text_IO;

with AMV;                          use AMV;
with AMV.Coordinate_Spaces;        use AMV.Coordinate_Spaces;
with AMV.Dimensioning;             use AMV.Dimensioning;
with AMV.Dimensioning.Create_Shapes;      use AMV.Dimensioning.Create_Shapes;
with AMV.Kernels;
with AMV.Kernels.Create_Shapes;
with AMV.Kernels.Shapes;
with AMV.Kernels.Transforms;
with AMV.Shapes;                   use AMV.Shapes;
with AMV.Tools;                    use AMV.Tools;
with AMV.Transforms;               use AMV.Transforms;
with AMV_Test_Support;             use AMV_Test_Support;

procedure Test_Create_Shapes is

   package EF renames Ada.Numerics.Long_Elementary_Functions;
   package K renames AMV.Kernels;
   package KC renames AMV.Kernels.Create_Shapes;
   package KS renames AMV.Kernels.Shapes;
   package KT renames AMV.Kernels.Transforms;

   use type K.Int32;
   use type KS.Ks_Circle;
   use type KS.Ks_Ellipse;
   use type KS.Ks_Line;
   use type KS.Ks_Line_Segment;

   Pi : constant := Ada.Numerics.Pi;

   Zero : constant Real := Real'Value ("0.0");
   NaN  : constant Real := Zero / Zero;
   Inf  : constant Real := 1.0 / Zero;

   Id : constant KT.Ks_Transform_2D_Linear := (others => <>);

   ---------------------------------------------------------------------
   --  Helpers
   ---------------------------------------------------------------------

   function New_Line (X, Y, Rotation : Real) return Ks_Line is
   begin
      return L : Ks_Line do
         L.Set_XY_Rotation (X, Y, Rotation);
      end return;
   end New_Line;

   function New_Segment (X0, Y0, X1, Y1 : Real) return Ks_Line_Segment is
   begin
      return S : Ks_Line_Segment do
         S.Set_Start_End (X0, Y0, X1, Y1);
      end return;
   end New_Segment;

   function New_Circle (CX, CY, R : Real) return Ks_Circle is
   begin
      return C : Ks_Circle do
         C.Set_Center_Radius (CX, CY, R);
      end return;
   end New_Circle;

   function New_Ellipse (CX, CY, RX, RY, Rotation : Real) return Ks_Ellipse
   is
   begin
      return E : Ks_Ellipse do
         E.Set_Center_XY_Radius_XY_Rotation (CX, CY, RX, RY, Rotation);
      end return;
   end New_Ellipse;

   function Accepted (Tool : Ks_Tool'Class) return Boolean is
     (Tool.Run_Status.Result = Accept_Result);

   function Failed_With
     (Tool    : Ks_Tool'Class;
      Name    : String;
      Message : String := "") return Boolean
   is (Tool.Run_Status.Result = Error
       and then Exception_Name (Tool.Run_Status)
                  = "AMV." & Ada.Characters.Handling.To_Upper (Name)
       and then (Message = "" or else AMV.Tools.Message (Tool.Run_Status)
                                        = Message));

   function Message_Of (Status : K.Ks_Status) return String is
     (String (Status.Message (1 .. Integer (Status.Length))));
   --  The message of a kernel status.

   procedure Report (Tool : Ks_Tool'Class; Description : String);

   procedure Report (Tool : Ks_Tool'Class; Description : String) is
   begin
      if Tool.Run_Status.Result /= Accept_Result then
         Ada.Text_IO.Put_Line
           ("  " & Description & ": " & Tool.Run_Status.Result'Image & " "
            & Exception_Name (Tool.Run_Status) & " "
            & AMV.Tools.Message (Tool.Run_Status));
      end if;
   end Report;

   procedure Check_Line
     (Line        : Ks_Line;
      X, Y, R     : Real;
      Tolerance   : Real;
      Description : String);

   procedure Check_Line
     (Line        : Ks_Line;
      X, Y, R     : Real;
      Tolerance   : Real;
      Description : String) is
   begin
      Check_Near (Line.X, X, Tolerance, Description & ": X");
      Check_Near (Line.Y, Y, Tolerance, Description & ": Y");
      Check_Near (Line.Rotation, R, Tolerance, Description & ": Rotation");
   end Check_Line;

   procedure Check_Segment
     (Segment        : Ks_Line_Segment;
      X0, Y0, X1, Y1 : Real;
      Tolerance      : Real;
      Description    : String);

   procedure Check_Segment
     (Segment        : Ks_Line_Segment;
      X0, Y0, X1, Y1 : Real;
      Tolerance      : Real;
      Description    : String) is
   begin
      Check_Near (Segment.Start_X, X0, Tolerance, Description & ": StartX");
      Check_Near (Segment.Start_Y, Y0, Tolerance, Description & ": StartY");
      Check_Near (Segment.End_X, X1, Tolerance, Description & ": EndX");
      Check_Near (Segment.End_Y, Y1, Tolerance, Description & ": EndY");
   end Check_Segment;

   ---------------------------------------------------------------------
   --  Every tool on hand-computed cases (one space)
   ---------------------------------------------------------------------

   procedure Test_Tools is
      CC : Ks_Create_Circle_Tool;
      CE : Ks_Create_Ellipse_Tool;
      CL : Ks_Create_Line_Tool;
      CS : Ks_Create_Segment_Tool;
      BP : Ks_Create_Line_Bisect_Points_Tool;
      LP : Ks_Create_Line_Parallel_Tool;
      PL : Ks_Create_Line_Perpendicular_Tool;
      AS : Ks_Create_Segment_Avg_Segs_Tool;
      C  : Ks_Circle;
      E  : Ks_Ellipse;
      L  : Ks_Line;
      S  : Ks_Line_Segment;
   begin
      Section ("Create shapes: every tool");
      C := CC.Get_Output_Circle;
      Check (C.Center_X = 0.0 and then C.Radius = 50.0
             and then C.Selected_Space_Name = ".",
             "before a run: the default circle");

      CC.Input_Circle := New_Circle (10.0, 20.0, 5.0);
      CC.Run;
      Report (CC, "CreateCircle");
      C := CC.Get_Output_Circle;
      Check (Accepted (CC) and then C.Center_X = 10.0
             and then C.Center_Y = 20.0 and then C.Radius = 5.0,
             "CreateCircle: the circle itself");
      Check (C.Selected_Space_Name = "@",
             "CreateCircle: in the image's selected space, ""@""");
      CC.Input_Circle := New_Circle (1.0, 2.0, 0.0);
      CC.Run;
      Check (Accepted (CC) and then CC.Get_Output_Circle.Radius = 0.0,
             "CreateCircle: a radius of 0 is a valid circle");

      CE.Ellipse := New_Ellipse (10.0, 20.0, 8.0, 4.0, 0.3);
      CE.Run;
      Report (CE, "CreateEllipse");
      E := CE.Get_Output_Ellipse;
      Check (Accepted (CE), "CreateEllipse runs");
      Check_Near (E.Center_X, 10.0, 1.0E-12, "CreateEllipse: centre X");
      Check_Near (E.Center_Y, 20.0, 1.0E-12, "CreateEllipse: centre Y");
      Check_Near (E.Radius_X, 8.0, 1.0E-12, "CreateEllipse: RadiusX");
      Check_Near (E.Radius_Y, 4.0, 1.0E-12, "CreateEllipse: RadiusY");
      Check_Near (E.Rotation, 0.3, 1.0E-12, "CreateEllipse: rotation");

      CL.Line := New_Line (1.0, 2.0, 0.3);
      CL.Run;
      Report (CL, "CreateLine");
      Check (Accepted (CL), "CreateLine runs");
      Check_Line (CL.Get_Output_Line, 1.0, 2.0, 0.3, 1.0E-15, "CreateLine");
      --  A rotation outside (-Pi, Pi] comes back reduced: 7 - 2 Pi.
      CL.Line := New_Line (1.0, 2.0, 7.0);
      CL.Run;
      Check_Line (CL.Get_Output_Line, 1.0, 2.0, 7.0 - 2.0 * Pi, 1.0E-14,
                  "CreateLine, rotation 7");

      CS.Segment := New_Segment (1.0, 2.0, 5.0, 7.0);
      CS.Run;
      Report (CS, "CreateSegment");
      S := CS.Get_Output_Segment;
      Check (Accepted (CS) and then S.Start_X = 1.0 and then S.Start_Y = 2.0
             and then S.End_X = 5.0 and then S.End_Y = 7.0,
             "CreateSegment: the segment itself");

      --  The bisector of (0, 0) and (4, 2): through (2, 1), direction
      --  atan2 (2, 4) + Pi/2.
      BP.End_X := 4.0;
      BP.End_Y := 2.0;
      BP.Run;
      Report (BP, "CreateLineBisectPoints");
      Check (Accepted (BP), "CreateLineBisectPoints runs");
      Check_Line (BP.Get_Output_Line, 2.0, 1.0,
                  EF.Arctan (2.0, 4.0) + Pi / 2.0, 1.0E-15, "bisector");
      --  (3, 5) to (-1, 5): direction Pi, plus Pi/2 is 3 Pi/2, reduced to
      --  -Pi/2; the midpoint is (1, 5).
      BP.Start_X := 3.0;
      BP.Start_Y := 5.0;
      BP.End_X := -1.0;
      BP.End_Y := 5.0;
      BP.Run;
      Check_Line (BP.Get_Output_Line, 1.0, 5.0, -Pi / 2.0, 1.0E-15,
                  "bisector of a leftward pair");
      --  Going down (y decreasing): direction -Pi/2, bisector rotation 0.
      BP.End_X := 3.0;
      BP.End_Y := -5.0;
      BP.Run;
      Check_Line (BP.Get_Output_Line, 3.0, 0.0, 0.0, 1.0E-15,
                  "bisector of a downward pair");

      --  Parallel to the line of rotation 0.25 through (5, 7).
      LP.Line := New_Line (-3.0, 1.0, 0.25);
      LP.X := 5.0;
      LP.Y := 7.0;
      LP.Run;
      Report (LP, "CreateLineParallel");
      Check (Accepted (LP), "CreateLineParallel runs");
      Check_Line (LP.Get_Output_Line, 5.0, 7.0, 0.25, 1.0E-15, "parallel");
      LP.Line := New_Line (-3.0, 1.0, -Pi);
      LP.Run;
      Check_Line (LP.Get_Output_Line, 5.0, 7.0, Pi, 1.0E-15,
                  "parallel to a line of rotation -Pi: Pi");

      PL.Line := New_Line (-3.0, 1.0, 0.25);
      PL.X := 5.0;
      PL.Y := 7.0;
      PL.Run;
      Report (PL, "CreateLinePerpendicular");
      Check (Accepted (PL), "CreateLinePerpendicular runs");
      Check_Line (PL.Get_Output_Line, 5.0, 7.0, 0.25 + Pi / 2.0, 1.0E-15,
                  "perpendicular");
      --  2 + Pi/2 > Pi: 2 + Pi/2 - 2 Pi.
      PL.Line := New_Line (-3.0, 1.0, 2.0);
      PL.Run;
      Check_Line (PL.Get_Output_Line, 5.0, 7.0, 2.0 - 1.5 * Pi, 1.0E-14,
                  "perpendicular, rotation 2");
      --  Pi/2 + Pi/2 = Pi stays Pi.
      PL.Line := New_Line (-3.0, 1.0, Pi / 2.0);
      PL.Run;
      Check_Line (PL.Get_Output_Line, 5.0, 7.0, Pi, 1.0E-15,
                  "perpendicular to a vertical line: Pi");

      --  The centre line of two parallel edges, 4 apart.
      AS.Segment_A := New_Segment (0.0, 0.0, 10.0, 0.0);
      AS.Segment_B := New_Segment (2.0, 4.0, 12.0, 4.0);
      AS.Run;
      Report (AS, "CreateSegmentAvgSegs");
      Check (Accepted (AS), "CreateSegmentAvgSegs runs");
      Check_Segment (AS.Get_Output_Segment, 1.0, 2.0, 11.0, 2.0, 0.0,
                     "the average");
      --  Opposite directions are not turned round: the starts (0, 0) and
      --  (12, 4) average to (6, 2), the ends (10, 0) and (2, 4) to (6, 2).
      AS.Segment_B := New_Segment (12.0, 4.0, 2.0, 4.0);
      AS.Run;
      Check (Accepted (AS), "opposite directions: accepted");
      Check_Segment (AS.Get_Output_Segment, 6.0, 2.0, 6.0, 2.0, 0.0,
                     "opposite directions: a segment of no length");
      L := PL.Get_Output_Line;
      Check (L.Selected_Space_Name = "@", "outputs are in ""@""");
   end Test_Tools;

   ---------------------------------------------------------------------
   --  Degenerate inputs and failures
   ---------------------------------------------------------------------

   procedure Test_Failures is
      Tree : Ks_Coordinate_Space_Tree;
      CC   : Ks_Create_Circle_Tool;
      CE   : Ks_Create_Ellipse_Tool;
      CL   : Ks_Create_Line_Tool;
      CS   : Ks_Create_Segment_Tool;
      BP   : Ks_Create_Line_Bisect_Points_Tool;
      LP   : Ks_Create_Line_Parallel_Tool;
      PL   : Ks_Create_Line_Perpendicular_Tool;
      AS   : Ks_Create_Segment_Avg_Segs_Tool;
      L    : Ks_Line;
   begin
      Section ("Create shapes: degenerate inputs and failures");
      BP.Start_X := 3.0;
      BP.Start_Y := 4.0;
      BP.End_X := 3.0;
      BP.End_Y := 4.0;
      BP.Run;
      Check (Failed_With (BP, "Ks_Bad_Parameter_Exception",
                          "StartX, StartY and EndX, EndY are the same point"
                          & " (the bisector needs a direction)"),
             "bisector of one point: Bad_Parameter");
      L := BP.Get_Output_Line;
      Check (L.X = 0.0 and then L.Y = 0.0 and then L.Rotation = 0.0
             and then L.Selected_Space_Name = ".",
             "after a failed run: the default line");
      BP.End_X := NaN;
      BP.Run;
      Check (Failed_With (BP, "Ks_Bad_Parameter_Exception",
                          "EndX must be finite and within +/-1.0E150"),
             "a NaN EndX");
      BP.End_X := 3.0;
      BP.Start_Y := 2.0E150;
      BP.Run;
      Check (Failed_With (BP, "Ks_Bad_Parameter_Exception",
                          "StartY must be finite and within +/-1.0E150"),
             "StartY beyond the bound");

      --  A successful run, then a failed one: the output is reset.
      LP.Line := New_Line (0.0, 0.0, 0.5);
      LP.X := 1.0;
      LP.Y := 1.0;
      LP.Run;
      Check (Accepted (LP), "parallel runs");
      LP.X := Inf;
      LP.Run;
      Check (Failed_With (LP, "Ks_Bad_Parameter_Exception",
                          "X must be finite and within +/-1.0E150")
             and then LP.Get_Output_Line.Rotation = 0.0,
             "an infinite X; the output is reset");
      --  (AMV.Shapes rejects a NaN in a shape already; the kernel tests
      --  below pass one directly.)
      PL.Line := New_Line (0.0, 0.0, 0.5);
      PL.Y := -Inf;
      PL.Run;
      Check (Failed_With (PL, "Ks_Bad_Parameter_Exception",
                          "Y must be finite and within +/-1.0E150"),
             "perpendicular: an infinite Y");

      CE.Ellipse := New_Ellipse (0.0, 0.0, 5.0, 0.0, 0.0);
      CE.Run;
      Check (Failed_With (CE, "Ks_Bad_Parameter_Exception",
                          "Ellipse.RadiusX and Ellipse.RadiusY must be > 0"),
             "an ellipse with a radius of 0");
      Check (CE.Get_Output_Ellipse.Radius_X = 50.0,
             "the default ellipse after the failure");

      AS.Segment_B := New_Segment (0.0, 0.0, 1.0E150, 0.0);
      AS.Segment_B.Set_Selected_Space_Name ("@\Nowhere");
      AS.Run;
      Check (Failed_With (AS, "Ks_Image_Bad_Selected_Space_Name_Exception"),
             "SegmentB in an unknown space");

      --  A stretched space (x scaled by 2): circles cannot be mapped,
      --  ellipses can.
      Tree.Add_Space
        ("@", "Stretch",
         AMV.Transforms.Create (2.0, 0.0, 0.0, 1.0, 0.0, 0.0));
      CC.Input_Image.Set_Coordinate_Space_Tree (Tree);
      CC.Input_Circle := New_Circle (0.0, 0.0, 5.0);
      CC.Input_Circle.Set_Selected_Space_Name ("@\Stretch");
      CC.Run;
      Check (Failed_With
               (CC, "Ks_Bad_Parameter_Exception",
                "InputCircle: its transform to the selected space is not a"
                & " similarity (the circle would become an ellipse)"),
             "a circle in a stretched space");
      CE.Input_Image.Set_Coordinate_Space_Tree (Tree);
      CE.Ellipse := New_Ellipse (1.0, 2.0, 5.0, 3.0, 0.0);
      CE.Ellipse.Set_Selected_Space_Name ("@\Stretch");
      CE.Run;
      Check (Accepted (CE), "an ellipse in a stretched space");
      Check_Near (CE.Get_Output_Ellipse.Center_X, 2.0, 1.0E-12,
                  "stretched ellipse: centre X doubled");
      Check_Near (CE.Get_Output_Ellipse.Radius_X, 10.0, 1.0E-12,
                  "stretched ellipse: RadiusX doubled");
      Check_Near (CE.Get_Output_Ellipse.Radius_Y, 3.0, 1.0E-12,
                  "stretched ellipse: RadiusY kept");
      CS.Input_Image.Set_Coordinate_Space_Tree (Tree);
      CS.Segment := New_Segment (1.0, 1.0, 2.0, 3.0);
      CS.Segment.Set_Selected_Space_Name ("@\Stretch");
      CS.Run;
      Check_Segment (CS.Get_Output_Segment, 2.0, 1.0, 4.0, 3.0, 0.0,
                     "a stretched segment");
      CL.Input_Image.Set_Coordinate_Space_Tree (Tree);
      CL.Line := New_Line (1.0, 1.0, Pi / 4.0);
      CL.Line.Set_Selected_Space_Name ("@\Stretch");
      CL.Run;
      --  The direction (1, 1) becomes (2, 1).
      Check_Line (CL.Get_Output_Line, 2.0, 1.0, EF.Arctan (1.0, 2.0),
                  1.0E-15, "a stretched line");
   end Test_Failures;

   ---------------------------------------------------------------------
   --  A fixture space
   ---------------------------------------------------------------------

   procedure Test_Spaces is
      Fix  : constant Ks_Transform_2D_Linear :=
        Create_Rigid (0.5, 100.0, 50.0);
      Tree : Ks_Coordinate_Space_Tree;
      CC   : Ks_Create_Circle_Tool;
      CE   : Ks_Create_Ellipse_Tool;
      CL   : Ks_Create_Line_Tool;
      CS   : Ks_Create_Segment_Tool;
      BP   : Ks_Create_Line_Bisect_Points_Tool;
      LP   : Ks_Create_Line_Parallel_Tool;
      PL   : Ks_Create_Line_Perpendicular_Tool;
      AS   : Ks_Create_Segment_Avg_Segs_Tool;
      X0, Y0, X1, Y1 : Real;
      E    : Ks_Ellipse;
      S    : Ks_Line_Segment;
   begin
      Section ("Create shapes: a fixture space");
      Tree.Add_Space ("@", "Fixture", Fix);

      --  The image selects the fixture; the inputs are given in the root
      --  space "@" as the fixture's shapes mapped by Fix. Every created
      --  shape comes back in fixture coordinates, in "@\Fixture".
      LP.Input_Image.Set_Coordinate_Space_Tree (Tree);
      LP.Input_Image.Set_Selected_Space_Name ("@\Fixture");
      Fix.Map_Point (10.0, 0.0, X0, Y0);
      LP.Line := New_Line (X0, Y0, 0.2 + 0.5);
      LP.Line.Set_Selected_Space_Name ("@");
      LP.X := 5.0;
      LP.Y := 3.0;
      LP.Run;
      Report (LP, "parallel in a fixture");
      Check_Line (LP.Get_Output_Line, 5.0, 3.0, 0.2, 1.0E-12,
                  "parallel in fixture coordinates");
      Check (LP.Get_Output_Line.Selected_Space_Name = "@\Fixture",
             "parallel: in ""@\Fixture""");

      PL.Input_Image := LP.Input_Image;
      PL.Line := LP.Line;
      PL.X := 5.0;
      PL.Y := 3.0;
      PL.Run;
      Check_Line (PL.Get_Output_Line, 5.0, 3.0, 0.2 + Pi / 2.0, 1.0E-12,
                  "perpendicular in fixture coordinates");
      Check (PL.Get_Output_Line.Selected_Space_Name = "@\Fixture",
             "perpendicular: in ""@\Fixture""");

      CC.Input_Image := LP.Input_Image;
      Fix.Map_Point (10.0, 20.0, X0, Y0);
      CC.Input_Circle := New_Circle (X0, Y0, 7.0);
      CC.Input_Circle.Set_Selected_Space_Name ("@");
      CC.Run;
      Check_Near (CC.Get_Output_Circle.Center_X, 10.0, 1.0E-12,
                  "circle: centre X in the fixture");
      Check_Near (CC.Get_Output_Circle.Center_Y, 20.0, 1.0E-12,
                  "circle: centre Y in the fixture");
      Check_Near (CC.Get_Output_Circle.Radius, 7.0, 1.0E-12,
                  "circle: radius kept");
      Check (CC.Get_Output_Circle.Selected_Space_Name = "@\Fixture",
             "circle: in ""@\Fixture""");

      CE.Input_Image := LP.Input_Image;
      CE.Ellipse := New_Ellipse (X0, Y0, 8.0, 4.0, 0.3 + 0.5);
      CE.Ellipse.Set_Selected_Space_Name ("@");
      CE.Run;
      E := CE.Get_Output_Ellipse;
      Check (Accepted (CE) and then E.Selected_Space_Name = "@\Fixture",
             "ellipse in the fixture");
      Check_Near (E.Center_X, 10.0, 1.0E-12, "ellipse: centre X");
      Check_Near (E.Center_Y, 20.0, 1.0E-12, "ellipse: centre Y");
      Check_Near (E.Radius_X, 8.0, 1.0E-12, "ellipse: RadiusX");
      Check_Near (E.Radius_Y, 4.0, 1.0E-12, "ellipse: RadiusY");
      Check_Near (E.Rotation, 0.3, 1.0E-12, "ellipse: rotation");

      CS.Input_Image := LP.Input_Image;
      Fix.Map_Point (1.0, 2.0, X0, Y0);
      Fix.Map_Point (5.0, 7.0, X1, Y1);
      CS.Segment := New_Segment (X0, Y0, X1, Y1);
      CS.Segment.Set_Selected_Space_Name ("@");
      CS.Run;
      Check_Segment (CS.Get_Output_Segment, 1.0, 2.0, 5.0, 7.0, 1.0E-12,
                     "segment in the fixture");

      --  One segment in the root, one in the fixture itself (".").
      AS.Input_Image := LP.Input_Image;
      Fix.Map_Point (0.0, 0.0, X0, Y0);
      Fix.Map_Point (10.0, 0.0, X1, Y1);
      AS.Segment_A := New_Segment (X0, Y0, X1, Y1);
      AS.Segment_A.Set_Selected_Space_Name ("@");
      AS.Segment_B := New_Segment (0.0, 4.0, 10.0, 4.0);
      AS.Run;
      S := AS.Get_Output_Segment;
      Check_Segment (S, 0.0, 2.0, 10.0, 2.0, 1.0E-12,
                     "average of a root and a fixture segment");
      Check (S.Selected_Space_Name = "@\Fixture", "average: in the fixture");

      --  Plain coordinates are taken in the selected space.
      BP.Input_Image := LP.Input_Image;
      BP.End_X := 2.0;
      BP.Run;
      Check_Line (BP.Get_Output_Line, 1.0, 0.0, Pi / 2.0, 1.0E-15,
                  "bisector in the fixture");
      Check (BP.Get_Output_Line.Selected_Space_Name = "@\Fixture",
             "bisector: in ""@\Fixture""");

      --  The other way round: the image selects the root, the line is in
      --  the fixture; the created line is Fix applied to it, in "@".
      CL.Input_Image.Set_Coordinate_Space_Tree (Tree);
      CL.Line := New_Line (10.0, 0.0, 0.2);
      CL.Line.Set_Selected_Space_Name ("@\Fixture");
      CL.Run;
      Fix.Map_Point (10.0, 0.0, X0, Y0);
      Check_Line (CL.Get_Output_Line, X0, Y0, 0.7, 1.0E-12,
                  "a fixture line in the root");
      Check (CL.Get_Output_Line.Selected_Space_Name = "@",
             "in ""@""");
   end Test_Spaces;

   ---------------------------------------------------------------------
   --  Created shapes measured again
   ---------------------------------------------------------------------

   procedure Test_Measure_Created is
      Fix  : constant Ks_Transform_2D_Linear :=
        Create_Rigid (-1.1, -40.0, 75.0);
      Tree : Ks_Coordinate_Space_Tree;
      PL   : Ks_Create_Line_Perpendicular_Tool;
      LP   : Ks_Create_Line_Parallel_Tool;
      BP   : Ks_Create_Line_Bisect_Points_Tool;
      AS   : Ks_Create_Segment_Avg_Segs_Tool;
      CC   : Ks_Create_Circle_Tool;
      AL   : Ks_Angle_Line_Line_Tool;
      IL   : Ks_Intersect_Line_Line_Tool;
      DL   : Ks_Distance_Point_Line_Tool;
      DS   : Ks_Distance_Segment_Segment_Tool;
      DC   : Ks_Distance_Point_Circle_Tool;
      D0   : Real;
   begin
      Section ("Create shapes: created shapes measured again");
      Tree.Add_Space ("@", "Fixture", Fix);
      PL.Input_Image.Set_Coordinate_Space_Tree (Tree);
      PL.Input_Image.Set_Selected_Space_Name ("@\Fixture");

      --  A perpendicular (created in the fixture) to a line given in the
      --  root: the angle between them, measured in the fixture, is Pi/2.
      PL.Line := New_Line (30.0, -20.0, 2.5);
      PL.Line.Set_Selected_Space_Name ("@");
      PL.X := 12.0;
      PL.Y := -7.0;
      PL.Run;
      Check (Accepted (PL), "the perpendicular");
      AL.Input_Image := PL.Input_Image;
      AL.Line_A := PL.Line;
      AL.Line_B := PL.Get_Output_Line;
      AL.Run;
      Report (AL, "AngleLineLine");
      Check_Near (AL.Angle, Pi / 2.0, 1.0E-12,
                  "AngleLineLine (line, perpendicular) = Pi/2");
      --  It crosses the line at the foot of (12, -7).
      IL.Input_Image := PL.Input_Image;
      IL.Line_A := PL.Line;
      IL.Line_B := PL.Get_Output_Line;
      IL.Run;
      DL.Input_Image := PL.Input_Image;
      DL.Line := PL.Line;
      DL.X := 12.0;
      DL.Y := -7.0;
      DL.Run;
      Check (Accepted (IL) and then IL.Num_Points = 1,
             "the perpendicular crosses the line");
      Check_Near (IL.X, DL.Line_X, 1.0E-9, "at the foot (X)");
      Check_Near (IL.Y, DL.Line_Y, 1.0E-9, "at the foot (Y)");

      --  A parallel: AngleLineLine 0, no crossing, and every point of the
      --  original line at the same distance from it.
      LP.Input_Image := PL.Input_Image;
      LP.Line := PL.Line;
      LP.X := 12.0;
      LP.Y := -7.0;
      LP.Run;
      AL.Line_B := LP.Get_Output_Line;
      AL.Run;
      Check_Near (AL.Angle, 0.0, 1.0E-12, "AngleLineLine (line, parallel)");
      IL.Line_B := LP.Get_Output_Line;
      IL.Run;
      Check (Accepted (IL) and then IL.Num_Points = 0,
             "the parallel does not cross the line");
      DL.Line := LP.Get_Output_Line;
      DL.Input_Image := PL.Input_Image;
      DL.X := 30.0;
      DL.Y := -20.0;
      DL.Line.Set_Selected_Space_Name ("@\Fixture");
      DL.Run;
      D0 := DL.Distance;
      Check (D0 > 1.0, "the parallel is apart from the line");

      --  The bisector: both points at the same distance from it, the
      --  midpoint on it.
      BP.Input_Image := PL.Input_Image;
      BP.Start_X := 3.0;
      BP.Start_Y := 9.0;
      BP.End_X := -5.0;
      BP.End_Y := 1.0;
      BP.Run;
      DL.Input_Image := PL.Input_Image;
      DL.Line := BP.Get_Output_Line;
      DL.X := 3.0;
      DL.Y := 9.0;
      DL.Run;
      D0 := DL.Distance;
      DL.X := -5.0;
      DL.Y := 1.0;
      DL.Run;
      Check_Near (DL.Distance, D0, 1.0E-12,
                  "both points equally far from the bisector");
      Check_Near (D0, EF.Sqrt (32.0), 1.0E-12,
                  "half the distance between them");
      DL.X := -1.0;
      DL.Y := 5.0;
      DL.Run;
      Check_Near (DL.Distance, 0.0, 1.0E-12, "the midpoint on the bisector");

      --  The average of two parallel segments 6 apart lies 3 from each.
      AS.Input_Image := PL.Input_Image;
      AS.Segment_A := New_Segment (0.0, 0.0, 20.0, 0.0);
      AS.Segment_B := New_Segment (0.0, 6.0, 20.0, 6.0);
      AS.Run;
      DS.Input_Image := PL.Input_Image;
      DS.Segment_A := AS.Segment_A;
      DS.Segment_B := AS.Get_Output_Segment;
      DS.Run;
      Check_Near (DS.Distance, 3.0, 1.0E-12, "average to A: 3");
      DS.Segment_A := AS.Segment_B;
      DS.Run;
      Check_Near (DS.Distance, 3.0, 1.0E-12, "average to B: 3");

      --  A circle created in the fixture from one in the root.
      CC.Input_Image := PL.Input_Image;
      CC.Input_Circle := New_Circle (10.0, 10.0, 4.0);
      CC.Input_Circle.Set_Selected_Space_Name ("@");
      CC.Run;
      DC.Input_Image := PL.Input_Image;
      DC.Input_Circle := CC.Get_Output_Circle;
      DC.X := CC.Get_Output_Circle.Center_X + 10.0;
      DC.Y := CC.Get_Output_Circle.Center_Y;
      DC.Run;
      Check_Near (DC.Distance, 6.0, 1.0E-12,
                  "a point 10 from the created circle's centre: 6");
   end Test_Measure_Created;

   ---------------------------------------------------------------------
   --  The kernel directly
   ---------------------------------------------------------------------

   procedure Test_Kernel is
      Status : K.Ks_Status;
      C      : KS.Ks_Circle;
      E      : KS.Ks_Ellipse;
      L      : KS.Ks_Line;
      S      : KS.Ks_Line_Segment;
      Line   : constant KS.Ks_Line := (X => 1.0, Y => 2.0, Rotation => 0.5);
      Seg    : constant KS.Ks_Line_Segment := (0.0, 0.0, 10.0, 0.0);
      Zero_T : constant KT.Ks_Transform_2D_Linear :=
        (A => 0.0, B => 0.0, C => 0.0, D => 0.0, others => <>);
      Flat_T : constant KT.Ks_Transform_2D_Linear :=
        (A => 1.0, B => 0.0, C => 0.0, D => 0.0, others => <>);
      Double : constant KT.Ks_Transform_2D_Linear :=
        (A => 2.0, D => 2.0, others => <>);
      Max    : constant := 1.0E150;
   begin
      Section ("Create shapes: kernel");
      KC.Create_Line (Line, Id, L, Status);
      Check (Status.Failure = K.Failure_None and then L.X = 1.0
             and then L.Y = 2.0, "ks_create_line_execute");
      KC.Create_Line ((Line with delta Rotation => NaN), Id, L, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then L = (others => <>), "a NaN rotation, default line");
      KC.Create_Line (Line, (Id with delta B => Inf), L, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter,
             "an infinite transform");
      KC.Create_Line (Line, Zero_T, L, Status);
      Check (Status.Failure = K.Failure_Transform_Singular
             and then L = (others => <>), "a singular transform of a line");
      KC.Create_Line_Perpendicular (0.0, 0.0, Line, Zero_T, L, Status);
      Check (Status.Failure = K.Failure_Transform_Singular,
             "perpendicular: a singular transform");
      KC.Create_Line_Parallel (0.0, 0.0, (Line with delta X => 2.0E150),
                               Id, L, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter,
             "parallel: a line beyond the bound");
      KC.Create_Line_Parallel (Max, -Max, Line, Id, L, Status);
      Check (Status.Failure = K.Failure_None and then L.X = Max
             and then L.Y = -Max, "parallel: a point at the bound");
      KC.Create_Line_Perpendicular (0.0, 0.0, (Line with delta Rotation => Pi),
                                    Id, L, Status);
      Check (Status.Failure = K.Failure_None, "perpendicular to Pi runs");
      Check_Near (L.Rotation, -Pi / 2.0, 1.0E-15,
                  "perpendicular to Pi: -Pi/2");
      --  A line mapped far beyond the bound.
      KC.Create_Line ((Line with delta X => Max),
                      (A => 2.0, D => 2.0, others => <>), L, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then K.Succeeded (Status) = False,
             "a line mapped beyond the bound");

      --  Bisector at the bounds: the corners (-Max, -Max) and (Max, Max).
      KC.Create_Line_Bisect_Points (-Max, -Max, Max, Max, L, Status);
      Check (Status.Failure = K.Failure_None and then L.X = 0.0
             and then L.Y = 0.0, "bisector of opposite corners");
      Check_Near (L.Rotation, 3.0 * Pi / 4.0, 1.0E-15,
                  "bisector of opposite corners: 3 Pi/4");
      KC.Create_Line_Bisect_Points (Max, Max, Max, Max, L, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then L = (others => <>), "bisector of one point");
      KC.Create_Line_Bisect_Points (0.0, 0.0, 1.0E-300, 0.0, L, Status);
      Check (Status.Failure = K.Failure_None and then L.Rotation = Pi / 2.0,
             "bisector of very close points");
      KC.Create_Line_Bisect_Points (0.0, -Inf, 1.0, 0.0, L, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter,
             "bisector: an infinite StartY");

      --  Segments.
      KC.Create_Segment (Seg, Zero_T, S, Status);
      Check (Status.Failure = K.Failure_None and then S.Start_X = 0.0
             and then S.End_X = 0.0,
             "a segment under a singular transform: a point");
      KC.Create_Segment ((Seg with delta End_Y => NaN), Id, S, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then S = (others => <>), "a NaN segment, default result");
      KC.Create_Segment_Avg_Segs
        ((Max, Max, -Max, -Max), (Max, Max, -Max, -Max), Id, Id, S, Status);
      Check (Status.Failure = K.Failure_None and then S.Start_X = Max
             and then S.End_Y = -Max, "average at the bounds");
      KC.Create_Segment_Avg_Segs
        ((Max, Max, -Max, -Max), (-Max, -Max, Max, Max), Id, Id, S, Status);
      Check (Status.Failure = K.Failure_None and then S.Start_X = 0.0
             and then S.End_X = 0.0, "average of opposite segments: (0, 0)");
      KC.Create_Segment_Avg_Segs (Seg, Seg, Id, (Id with delta A => NaN), S,
                                  Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then Message_Of (Status)
                        = "the transform of SegmentB must be finite and"
                          & " within +/-1.0E150",
             "a NaN transform of SegmentB");
      KC.Create_Segment_Avg_Segs (Seg, Seg, Double, Id, S, Status);
      Check (Status.Failure = K.Failure_None and then S.End_X = 15.0,
             "SegmentA doubled");

      --  Circles.
      KC.Create_Circle ((0.0, 0.0, 6.0E149), Double, C, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then C = (others => <>),
             "a circle whose radius would exceed 1.0E150");
      KC.Create_Circle ((0.0, 0.0, 5.0E149), Double, C, Status);
      Check (Status.Failure = K.Failure_None and then C.Radius = Max,
             "a circle whose radius reaches 1.0E150");
      KC.Create_Circle ((0.0, 0.0, -1.0), Id, C, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter,
             "a negative radius");
      KC.Create_Circle ((0.0, 0.0, 1.0), Zero_T, C, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter,
             "a circle under a singular transform");

      --  Ellipses.
      KC.Create_Ellipse ((0.0, 0.0, 5.0, 3.0, 0.0), Flat_T, E, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then Message_Of (Status)
                        = "Ellipse: a radius becomes 0 in the selected space",
             "an ellipse flattened to a segment");
      KC.Create_Ellipse ((0.0, 0.0, 5.0, 3.0, 1.0E151), Id, E, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter,
             "an ellipse rotation beyond the bound");
      KC.Create_Ellipse ((0.0, 0.0, 6.0E149, 3.0, 0.0), Double, E, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then E = (others => <>),
             "an ellipse radius beyond 1.0E150 once mapped");
      KC.Create_Ellipse ((0.0, 0.0, 5.0, 3.0, 9.0), Id, E, Status);
      Check (Status.Failure = K.Failure_None
             and then E.Rotation > -Pi and then E.Rotation <= Pi,
             "an ellipse rotation brought into (-Pi, Pi]");
   end Test_Kernel;

   procedure Test_Timing is
      PL    : Ks_Create_Line_Perpendicular_Tool;
      AS    : Ks_Create_Segment_Avg_Segs_Tool;
      Fix   : constant Ks_Transform_2D_Linear :=
        Create_Rigid (0.5, 100.0, 50.0);
      Tree  : Ks_Coordinate_Space_Tree;
      Start : Ada.Calendar.Time;
      Runs  : constant := 10_000;
      Status : K.Ks_Status;
      L     : KS.Ks_Line;
   begin
      Section ("Create shapes: timing");
      Tree.Add_Space ("@", "Fixture", Fix);
      PL.Input_Image.Set_Coordinate_Space_Tree (Tree);
      PL.Input_Image.Set_Selected_Space_Name ("@\Fixture");
      PL.Line := New_Line (30.0, -20.0, 2.5);
      PL.Line.Set_Selected_Space_Name ("@");
      Start := Ada.Calendar.Clock;
      for I in 1 .. Runs loop
         PL.Run;
      end loop;
      Ada.Text_IO.Put_Line
        ("  perpendicular with a fixture (Ada API):"
         & Duration'Image (Ada.Calendar."-" (Ada.Calendar.Clock, Start)
                           * (1_000_000 / Runs)) & " us per run");
      Check (Accepted (PL), "the timed runs succeed");
      AS.Segment_A := New_Segment (0.0, 0.0, 20.0, 0.0);
      Start := Ada.Calendar.Clock;
      for I in 1 .. Runs loop
         AS.Run;
      end loop;
      Ada.Text_IO.Put_Line
        ("  average of segments (Ada API):"
         & Duration'Image (Ada.Calendar."-" (Ada.Calendar.Clock, Start)
                           * (1_000_000 / Runs)) & " us per run");
      Start := Ada.Calendar.Clock;
      for I in 1 .. Runs loop
         KC.Create_Line_Perpendicular
           (Real (I), 0.0, (1.0, 2.0, 0.5), Id, L, Status);
      end loop;
      Ada.Text_IO.Put_Line
        ("  ks_create_line_perpendicular_execute:"
         & Duration'Image (Ada.Calendar."-" (Ada.Calendar.Clock, Start)
                           * (1_000_000 / Runs)) & " us per call");
      Check (Status.Failure = K.Failure_None, "the timed calls succeed");
   end Test_Timing;

   procedure Run_All is
   begin
      Test_Tools;
      Test_Failures;
      Test_Spaces;
      Test_Measure_Created;
      Test_Kernel;
      Test_Timing;
   exception
      when E : others =>
         Fail ("unexpected exception "
               & Ada.Exceptions.Exception_Information (E));
   end Run_All;

   procedure Main is new AMV_Test_Support.Standalone (Run_All);
begin
   Main;
end Test_Create_Shapes;
