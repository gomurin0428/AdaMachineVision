--  Tests for AMV.Dimensioning (the measuring tools of
--  Cognex.VisionPro.Dimensioning), AMV.Dimensioning.Fitting (CogFitLine,
--  CogFitCircle, CogFitEllipse and their tools) and their kernels
--  AMV.Kernels.Dimensioning and AMV.Kernels.Dimensioning.Fitting.
--
--  The expected values are worked out by hand in the comments; the
--  ellipse distances are compared with a dense sampling of the ellipse,
--  and the fits with the shapes the points were drawn from.

pragma Validity_Checks ("F");

with Ada.Calendar;
with Ada.Characters.Handling;
with Ada.Exceptions;
with Ada.Numerics.Long_Elementary_Functions;
with Ada.Streams.Storage.Unbounded;
with Ada.Text_IO;

with AMV;                          use AMV;
with AMV.Coordinate_Spaces;        use AMV.Coordinate_Spaces;
with AMV.Dimensioning;             use AMV.Dimensioning;
with AMV.Dimensioning.Fitting;     use AMV.Dimensioning.Fitting;
with AMV.Kernels;
with AMV.Kernels.Dimensioning;
with AMV.Kernels.Dimensioning.Fitting;
with AMV.Kernels.Shapes;
with AMV.Kernels.Transforms;
with AMV.Shapes;                   use AMV.Shapes;
with AMV.Tools;                    use AMV.Tools;
with AMV.Transforms;               use AMV.Transforms;
with AMV_Test_Support;             use AMV_Test_Support;

procedure Test_Dimensioning is

   package EF renames Ada.Numerics.Long_Elementary_Functions;
   package K renames AMV.Kernels;
   package KD renames AMV.Kernels.Dimensioning;
   package KF renames AMV.Kernels.Dimensioning.Fitting;
   package KS renames AMV.Kernels.Shapes;
   package KT renames AMV.Kernels.Transforms;

   use type K.Int32;
   use type KS.Ks_Polygon;
   use type KF.Ks_Fit_Result;
   use type KD.Ks_Distance_Point_Line_Result;

   Pi : constant := Ada.Numerics.Pi;

   Zero : constant Real := Real'Value ("0.0");
   NaN  : constant Real := Zero / Zero;

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

   --  A deterministic noise source (a linear congruential generator).
   Seed : Long_Long_Integer := 12345;

   function Noise (Amplitude : Real) return Real is
   begin
      Seed := (Seed * 1103515245 + 12345) mod 2**31;
      return Amplitude * (2.0 * Real (Seed) / 2.0**31 - 1.0);
   end Noise;
   --  A value in [-Amplitude, Amplitude].

   procedure Noisy_Point (X, Y, Amplitude : Real; Nx, Ny : out Real) is
   begin
      Nx := X + Noise (Amplitude);
      Ny := Y + Noise (Amplitude);
   end Noisy_Point;
   --  (X, Y) with noise, drawn for X first. The language leaves the order
   --  of two calls of Noise in one parameter list to the compiler, and it
   --  differs between targets: the data of the tests would differ with it.

   procedure Ellipse_Point
     (CX, CY, RX, RY, Rotation, T : Real;
      X, Y                        : out Real) is
      U : constant Real := RX * EF.Cos (T);
      V : constant Real := RY * EF.Sin (T);
   begin
      X := CX + U * EF.Cos (Rotation) - V * EF.Sin (Rotation);
      Y := CY + U * EF.Sin (Rotation) + V * EF.Cos (Rotation);
   end Ellipse_Point;

   function Brute_Distance
     (PX, PY, CX, CY, RX, RY, Rotation : Real) return Real
   is
      Steps : constant := 200_000;
      Best  : Real := Real'Last;
      X, Y  : Real;
   begin
      for I in 0 .. Steps - 1 loop
         Ellipse_Point (CX, CY, RX, RY, Rotation,
                        2.0 * Pi * Real (I) / Real (Steps), X, Y);
         Best := Real'Min (Best, EF.Sqrt ((X - PX)**2 + (Y - PY)**2));
      end loop;
      return Best;
   end Brute_Distance;
   --  The distance from (PX, PY) to the ellipse by dense sampling (to
   --  about 1.0E-7 for the sizes used here).

   function Ellipse_Value
     (PX, PY, CX, CY, RX, RY, Rotation : Real) return Real
   is
      DX : constant Real := PX - CX;
      DY : constant Real := PY - CY;
      U  : constant Real := DX * EF.Cos (Rotation) + DY * EF.Sin (Rotation);
      V  : constant Real := DY * EF.Cos (Rotation) - DX * EF.Sin (Rotation);
   begin
      return (U / RX)**2 + (V / RY)**2;
   end Ellipse_Value;
   --  1 on the ellipse, below 1 inside.

   ---------------------------------------------------------------------
   --  Points and angles
   ---------------------------------------------------------------------

   procedure Test_Points_And_Angles is
      PP : Ks_Distance_Point_Point_Tool;
      AP : Ks_Angle_Point_Point_Tool;
      AL : Ks_Angle_Line_Line_Tool;
   begin
      Section ("Dimensioning: points and angles");
      Check (PP.Distance = 0.0 and then PP.Angle = 0.0,
             "no values before a run");
      PP.Start_X := 1.0;
      PP.Start_Y := 2.0;
      PP.End_X := 4.0;
      PP.End_Y := 6.0;
      PP.Run;
      Check (Accepted (PP), "DistancePointPoint runs");
      Check_Near (PP.Distance, 5.0, 1.0E-12, "3-4-5 distance");
      Check_Near (PP.Angle, EF.Arctan (4.0, 3.0), 1.0E-15, "its angle");
      PP.End_X := 1.0;
      PP.End_Y := 2.0;
      PP.Run;
      Check (Accepted (PP) and then PP.Distance = 0.0
             and then PP.Angle = 0.0, "coincident points: 0 and angle 0");
      PP.End_X := -5.0;
      PP.Run;
      Check_Near (PP.Angle, Pi, 0.0, "the negative x axis gives +Pi");

      AP.Start_X := 1.0;
      AP.Start_Y := 1.0;
      AP.End_X := 0.0;
      AP.End_Y := 2.0;
      AP.Run;
      Check (Accepted (AP), "AnglePointPoint runs");
      Check_Near (AP.Angle, 3.0 * Pi / 4.0, 1.0E-15, "angle 3 Pi / 4");
      AP.End_Y := 0.0;
      AP.Run;
      Check_Near (AP.Angle, -3.0 * Pi / 4.0, 1.0E-15, "angle -3 Pi / 4");

      AL.Line_A := New_Line (0.0, 0.0, 0.3);
      AL.Line_B := New_Line (5.0, 1.0, -2.9);
      AL.Run;
      Check (Accepted (AL), "AngleLineLine runs");
      --  -2.9 - 0.3 = -3.2, reduced: -3.2 + 2 Pi.
      Check_Near (AL.Angle, -3.2 + 2.0 * Pi, 1.0E-14, "B - A reduced");
      AL.Line_B := New_Line (5.0, 1.0, 0.3 + 7.0 * Pi);
      AL.Run;
      Check_Near (abs AL.Angle, Pi, 1.0E-9, "anti-parallel lines: Pi");
      PP.Start_X := NaN;
      PP.Run;
      Check (Failed_With (PP, "Ks_Bad_Parameter_Exception",
                          "StartX must be finite and within +/-1.0E150"),
             "a NaN start point is rejected");
      Check (PP.Distance = 0.0 and then PP.Angle = 0.0,
             "no values after a failed run");
      PP.Start_X := 2.0E150;
      PP.Run;
      Check (Failed_With (PP, "Ks_Bad_Parameter_Exception"),
             "a start point beyond 1.0E150 is rejected");
   end Test_Points_And_Angles;

   ---------------------------------------------------------------------
   --  Distances
   ---------------------------------------------------------------------

   procedure Test_Point_Distances is
      PL : Ks_Distance_Point_Line_Tool;
      PS : Ks_Distance_Point_Segment_Tool;
      PC : Ks_Distance_Point_Circle_Tool;
   begin
      Section ("Dimensioning: point to line, segment, circle");
      PL.X := 5.0;
      PL.Y := 3.0;
      PL.Run;
      Check (Accepted (PL), "DistancePointLine runs");
      Check_Near (PL.Distance, 3.0, 0.0, "distance to the x axis");
      Check (PL.Line_X = 5.0 and then PL.Line_Y = 0.0, "the foot (5, 0)");
      --  The line through (1, 1) at Pi / 4 and the point (0, 2): offset
      --  (2 - 1) cos - (0 - 1) sin = Sqrt (2); the foot is (1, 1).
      PL.Line := New_Line (1.0, 1.0, Pi / 4.0);
      PL.X := 0.0;
      PL.Y := 2.0;
      PL.Run;
      Check_Near (PL.Distance, EF.Sqrt (2.0), 1.0E-15, "rotated line");
      Check_Near (PL.Line_X, 1.0, 1.0E-15, "its foot X");
      Check_Near (PL.Line_Y, 1.0, 1.0E-15, "its foot Y");

      PS.Segment := New_Segment (0.0, 0.0, 10.0, 0.0);
      PS.X := 5.0;
      PS.Y := 3.0;
      PS.Run;
      Check (Accepted (PS) and then PS.Distance = 3.0
             and then PS.Segment_X = 5.0 and then PS.Segment_Y = 0.0,
             "point over the segment: the foot");
      PS.X := -4.0;
      PS.Run;
      Check (PS.Distance = 5.0 and then PS.Segment_X = 0.0
             and then PS.Segment_Y = 0.0, "before the start: the start");
      PS.X := 13.0;
      PS.Y := 4.0;
      PS.Run;
      Check (PS.Distance = 5.0 and then PS.Segment_X = 10.0,
             "beyond the end: the end");
      PS.Segment := New_Segment (2.0, 2.0, 2.0, 2.0);
      PS.Run;
      Check (Accepted (PS) and then PS.Segment_X = 2.0
             and then PS.Segment_Y = 2.0,
             "a segment of no length is its point");
      Check_Near (PS.Distance, EF.Sqrt (11.0**2 + 2.0**2), 1.0E-12,
                  "and the distance to it");

      PC.Input_Circle := New_Circle (0.0, 0.0, 5.0);
      PC.X := 10.0;
      PC.Y := 0.0;
      PC.Run;
      Check (Accepted (PC) and then PC.Distance = 5.0
             and then PC.Circle_X = 5.0 and then PC.Circle_Y = 0.0,
             "outside: positive");
      PC.X := 3.0;
      PC.Run;
      Check (PC.Distance = -2.0 and then PC.Circle_X = 5.0,
             "inside: negative (VisionPro)");
      PC.X := 3.0;
      PC.Y := 4.0;
      PC.Run;
      Check (PC.Distance = 0.0 and then PC.Circle_X = 3.0
             and then PC.Circle_Y = 4.0, "on the circle: 0 and the point");
      PC.X := 0.0;
      PC.Y := 0.0;
      PC.Run;
      Check (PC.Distance = 5.0 and then PC.Circle_X = 5.0
             and then PC.Circle_Y = 0.0,
             "at the centre: +Radius and the point at angle 0 (VisionPro)");
   end Test_Point_Distances;

   procedure Test_Ellipse_Distances is
      PE    : Ks_Distance_Point_Ellipse_Tool;
      Worst : Real := 0.0;
      PX, PY, Expected : Real;
      Inside : Boolean;
      Signs_OK : Boolean := True;
      On_OK    : Boolean := True;
   begin
      Section ("Dimensioning: point to ellipse");
      PE.Ellipse := New_Ellipse (0.0, 0.0, 5.0, 3.0, 0.0);
      PE.X := 10.0;
      PE.Y := 0.0;
      PE.Run;
      Check (Accepted (PE), "DistancePointEllipse runs");
      Check_Near (PE.Distance, 5.0, 1.0E-12, "on the major axis");
      Check_Near (PE.Ellipse_X, 5.0, 1.0E-12, "nearest (5, 0)");
      PE.X := 0.0;
      PE.Y := 7.0;
      PE.Run;
      Check_Near (PE.Distance, 4.0, 1.0E-12, "on the minor axis");
      Check_Near (PE.Ellipse_Y, 3.0, 1.0E-12, "nearest (0, 3)");
      PE.X := 0.0;
      PE.Y := 0.0;
      PE.Run;
      Check_Near (PE.Distance, -3.0, 1.0E-12,
                  "the centre: minus the minor radius");
      --  Inside on the major axis: the nearest point is off the axis at
      --  X = 25 / 16 (E0**2 Y0 / (E0**2 - E1**2) for Y0 = 1).
      PE.X := 1.0;
      PE.Run;
      Check_Near (PE.Ellipse_X, 25.0 / 16.0, 1.0E-12,
                  "inside on the axis: off-axis nearest point");
      Check_Near (PE.Distance,
                  -EF.Sqrt ((25.0 / 16.0 - 1.0)**2
                            + 9.0 * (1.0 - (25.0 / 16.0 / 5.0)**2)),
                  1.0E-12, "and its distance");
      PE.Ellipse := New_Ellipse (0.0, 0.0, 4.0, 4.0, 0.7);
      PE.X := 0.0;
      PE.Y := 0.0;
      PE.Run;
      Check (PE.Distance = 4.0,
             "the centre of a circular ellipse: +Radius (VisionPro)");

      --  Generic points against dense sampling.
      for Trial in 1 .. 40 loop
         declare
            CX  : constant Real := Noise (50.0);
            CY  : constant Real := Noise (50.0);
            RX  : constant Real := 2.0 + abs Noise (20.0);
            RY  : constant Real := 2.0 + abs Noise (20.0);
            Rot : constant Real := Noise (3.0);
         begin
            PE.Ellipse := New_Ellipse (CX, CY, RX, RY, Rot);
            PX := CX + Noise (40.0);
            PY := CY + Noise (40.0);
            PE.X := PX;
            PE.Y := PY;
            PE.Run;
            Expected := Brute_Distance (PX, PY, CX, CY, RX, RY, Rot);
            Inside := Ellipse_Value (PX, PY, CX, CY, RX, RY, Rot) < 1.0;
            Worst := Real'Max (Worst, abs (abs PE.Distance - Expected));
            if Inside /= (PE.Distance < 0.0) then
               Signs_OK := False;
            end if;
            if abs (Ellipse_Value (PE.Ellipse_X, PE.Ellipse_Y, CX, CY, RX,
                                   RY, Rot) - 1.0) > 1.0E-9
            then
               On_OK := False;
            end if;
         end;
      end loop;
      Check (Worst < 1.0E-6, "40 random cases match dense sampling");
      Check (Signs_OK, "negative exactly inside");
      Check (On_OK, "the nearest points lie on the ellipse");
      Ada.Text_IO.Put_Line
        ("  largest difference from sampling:" & Worst'Image);

      PE.Ellipse := New_Ellipse (0.0, 0.0, 0.0, 3.0, 0.0);
      PE.Run;
      Check (Failed_With (PE, "Ks_Bad_Parameter_Exception",
                          "Ellipse.RadiusX and Ellipse.RadiusY must be > 0"),
             "a radius of 0 is rejected");
   end Test_Ellipse_Distances;

   procedure Test_Two_Shape_Distances is
      SS : Ks_Distance_Segment_Segment_Tool;
      SL : Ks_Distance_Segment_Line_Tool;
      LC : Ks_Distance_Line_Circle_Tool;
      SC : Ks_Distance_Segment_Circle_Tool;
      CC : Ks_Distance_Circle_Circle_Tool;
      LE : Ks_Distance_Line_Ellipse_Tool;
      SE : Ks_Distance_Segment_Ellipse_Tool;
   begin
      Section ("Dimensioning: distances between shapes");
      --  Parallel segments 3 apart: the first nearest pair is B's start
      --  over A.
      SS.Segment_A := New_Segment (0.0, 0.0, 10.0, 0.0);
      SS.Segment_B := New_Segment (2.0, 3.0, 8.0, 3.0);
      SS.Run;
      Check (Accepted (SS) and then SS.Distance = 3.0
             and then SS.Segment_A_X = 2.0 and then SS.Segment_A_Y = 0.0
             and then SS.Segment_B_X = 2.0 and then SS.Segment_B_Y = 3.0,
             "parallel segments");
      SS.Segment_B := New_Segment (3.0, 1.0, 3.0, 5.0);
      SS.Segment_A := New_Segment (0.0, 0.0, 1.0, 0.0);
      SS.Run;
      Check_Near (SS.Distance, EF.Sqrt (5.0), 1.0E-15, "end to end");
      Check (SS.Segment_A_X = 1.0 and then SS.Segment_B_Y = 1.0,
             "the nearest end points");
      SS.Segment_A := New_Segment (0.0, 0.0, 2.0, 2.0);
      SS.Segment_B := New_Segment (0.0, 2.0, 2.0, 0.0);
      SS.Run;
      Check (SS.Distance = 0.0 and then SS.Segment_A_X = 0.0
             and then SS.Segment_B_X = 0.0, "crossing: 0 and (0, 0)");
      SS.Segment_A := New_Segment (0.0, 0.0, 1.0, 0.0);
      SS.Segment_B := New_Segment (3.0, 0.0, 5.0, 0.0);
      SS.Run;
      Check (SS.Distance = 2.0 and then SS.Segment_A_X = 1.0
             and then SS.Segment_B_X = 3.0, "collinear apart");

      SL.Segment := New_Segment (0.0, 2.0, 10.0, 5.0);
      SL.Run;
      Check (Accepted (SL) and then SL.Distance = 2.0
             and then SL.Segment_X = 0.0 and then SL.Segment_Y = 2.0
             and then SL.Line_X = 0.0 and then SL.Line_Y = 0.0,
             "segment above the x axis");
      SL.Segment := New_Segment (0.0, 3.0, 5.0, 3.0);
      SL.Run;
      Check (SL.Distance = 3.0 and then SL.Segment_X = 0.0
             and then SL.Line_X = 0.0, "parallel: the start point");
      SL.Segment := New_Segment (0.0, -1.0, 5.0, 3.0);
      SL.Run;
      Check (SL.Distance = 0.0 and then SL.Segment_Y = 0.0,
             "crossing: 0 and (0, 0)");

      LC.Input_Circle := New_Circle (5.0, 10.0, 3.0);
      LC.Run;
      Check (Accepted (LC) and then LC.Distance = 7.0
             and then LC.Line_X = 5.0 and then LC.Line_Y = 0.0
             and then LC.Circle_X = 5.0 and then LC.Circle_Y = 7.0,
             "line and circle apart");
      LC.Input_Circle := New_Circle (5.0, -10.0, 3.0);
      LC.Run;
      Check (LC.Distance = 7.0 and then LC.Circle_Y = -7.0,
             "below the line");
      LC.Input_Circle := New_Circle (5.0, 3.0, 3.0);
      LC.Run;
      Check (LC.Distance = 0.0 and then LC.Circle_X = 0.0,
             "tangent: 0 and (0, 0)");

      SC.Segment := New_Segment (-5.0, 10.0, 5.0, 10.0);
      SC.Input_Circle := New_Circle (0.0, 0.0, 3.0);
      SC.Run;
      Check (Accepted (SC) and then SC.Distance = 7.0
             and then SC.Segment_X = 0.0 and then SC.Segment_Y = 10.0
             and then SC.Circle_X = 0.0 and then SC.Circle_Y = 3.0,
             "segment outside the circle");
      SC.Segment := New_Segment (-1.0, 0.0, 2.0, 0.0);
      SC.Input_Circle := New_Circle (0.0, 0.0, 5.0);
      SC.Run;
      Check (SC.Distance = -3.0 and then SC.Segment_X = 2.0
             and then SC.Circle_X = 5.0,
             "inside: the farther end point, negative (VisionPro)");
      SC.Segment := New_Segment (0.0, 0.0, 10.0, 0.0);
      SC.Run;
      Check (SC.Distance = 0.0 and then SC.Segment_X = 0.0,
             "crossing: 0 and (0, 0)");

      CC.Circle_A := New_Circle (0.0, 0.0, 1.0);
      CC.Circle_B := New_Circle (10.0, 0.0, 2.0);
      CC.Run;
      Check (Accepted (CC) and then CC.Distance = 7.0
             and then CC.Circle_A_X = 1.0 and then CC.Circle_B_X = 8.0,
             "circles apart");
      CC.Circle_A := New_Circle (0.0, 0.0, 10.0);
      CC.Circle_B := New_Circle (2.0, 0.0, 3.0);
      CC.Run;
      Check (CC.Distance = -5.0 and then CC.Circle_A_X = 10.0
             and then CC.Circle_B_X = 5.0, "B inside A: negative");
      CC.Circle_A := New_Circle (2.0, 0.0, 3.0);
      CC.Circle_B := New_Circle (0.0, 0.0, 10.0);
      CC.Run;
      Check (CC.Distance = -5.0 and then CC.Circle_A_X = 5.0
             and then CC.Circle_B_X = 10.0, "A inside B: negative");
      CC.Circle_A := New_Circle (0.0, 0.0, 5.0);
      CC.Circle_B := New_Circle (0.0, 0.0, 2.0);
      CC.Run;
      Check (CC.Distance = -3.0 and then CC.Circle_A_X = 5.0
             and then CC.Circle_B_X = 2.0, "concentric");
      CC.Circle_B := New_Circle (0.0, 0.0, 5.0);
      CC.Run;
      Check (Accepted (CC) and then CC.Distance = 0.0
             and then CC.Circle_A_X = 0.0, "identical: 0");
      CC.Circle_B := New_Circle (6.0, 0.0, 5.0);
      CC.Run;
      Check (CC.Distance = 0.0, "crossing: 0");

      LE.Line := New_Line (0.0, 10.0, 0.0);
      LE.Ellipse := New_Ellipse (0.0, 0.0, 5.0, 3.0, 0.0);
      LE.Run;
      Check (Accepted (LE), "DistanceLineEllipse runs");
      Check_Near (LE.Distance, 7.0, 1.0E-12, "line above the ellipse");
      Check_Near (LE.Ellipse_Y, 3.0, 1.0E-12, "the top of the ellipse");
      Check_Near (LE.Line_Y, 10.0, 1.0E-12, "and its foot on the line");
      LE.Line := New_Line (20.0, 0.0, Pi / 2.0);
      LE.Run;
      Check_Near (LE.Distance, 15.0, 1.0E-12, "vertical line");
      Check_Near (LE.Ellipse_X, 5.0, 1.0E-12, "the right end");
      --  A slanted line: the gap is the line's distance from the centre
      --  minus the ellipse's extent across it, Sqrt (a**2 nx**2 + b**2
      --  ny**2).
      LE.Line := New_Line (0.0, 20.0, 0.4);
      LE.Ellipse := New_Ellipse (1.0, 2.0, 5.0, 3.0, 0.3);
      LE.Run;
      declare
         NX  : constant Real := -EF.Sin (0.4 - 0.3);
         NY  : constant Real := EF.Cos (0.4 - 0.3);
         Off : constant Real :=
           abs ((2.0 - 20.0) * EF.Cos (0.4) - (1.0 - 0.0) * EF.Sin (0.4));
      begin
         Check_Near (LE.Distance,
                     Off - EF.Sqrt (25.0 * NX**2 + 9.0 * NY**2), 1.0E-12,
                     "slanted line and rotated ellipse");
         Check_Near (Ellipse_Value (LE.Ellipse_X, LE.Ellipse_Y, 1.0, 2.0,
                                    5.0, 3.0, 0.3), 1.0, 1.0E-12,
                     "the ellipse point lies on it");
      end;
      LE.Line := New_Line (0.0, 2.0, 0.0);
      LE.Run;
      Check (LE.Distance = 0.0 and then LE.Line_X = 0.0,
             "crossing: 0 and (0, 0)");

      SE.Ellipse := New_Ellipse (0.0, 0.0, 5.0, 3.0, 0.0);
      SE.Segment := New_Segment (-2.0, 10.0, 2.0, 10.0);
      SE.Run;
      Check (Accepted (SE), "DistanceSegmentEllipse runs");
      Check_Near (SE.Distance, 7.0, 1.0E-12,
                  "segment passing over the top");
      Check_Near (SE.Segment_X, 0.0, 1.0E-12, "at its middle");
      SE.Segment := New_Segment (10.0, 0.0, 20.0, 0.0);
      SE.Run;
      Check_Near (SE.Distance, 5.0, 1.0E-12, "the nearer end point");
      Check (SE.Segment_X = 10.0, "the start point");
      SE.Segment := New_Segment (-1.0, 0.0, 1.0, 0.0);
      SE.Run;
      Check_Near (SE.Distance,
                  -EF.Sqrt ((25.0 / 16.0 - 1.0)**2
                            + 9.0 * (1.0 - (25.0 / 16.0 / 5.0)**2)),
                  1.0E-12, "inside: negative");
      Check (SE.Segment_X = -1.0, "the start point (both are as near)");
      SE.Segment := New_Segment (0.0, 0.0, 10.0, 0.0);
      SE.Run;
      Check (SE.Distance = 0.0 and then SE.Segment_X = 0.0,
             "crossing the boundary: 0");
   end Test_Two_Shape_Distances;

   ---------------------------------------------------------------------
   --  Intersections
   ---------------------------------------------------------------------

   procedure Test_Intersections is
      LL : Ks_Intersect_Line_Line_Tool;
      SL : Ks_Intersect_Segment_Line_Tool;
      SS : Ks_Intersect_Segment_Segment_Tool;
      LC : Ks_Intersect_Line_Circle_Tool;
      SC : Ks_Intersect_Segment_Circle_Tool;
      CC : Ks_Intersect_Circle_Circle_Tool;
      LE : Ks_Intersect_Line_Ellipse_Tool;
      SE : Ks_Intersect_Segment_Ellipse_Tool;
   begin
      Section ("Dimensioning: intersections");
      LL.Line_B := New_Line (2.0, 0.0, Pi / 2.0);
      LL.Run;
      Check (Accepted (LL) and then LL.Intersects
             and then LL.Num_Points = 1, "crossing lines: one point");
      Check_Near (LL.X, 2.0, 1.0E-15, "at X = 2");
      Check_Near (LL.Y, 0.0, 1.0E-15, "and Y = 0");
      Check_Near (LL.Angle, Pi / 2.0, 1.0E-15, "angle Pi / 2");
      LL.Line_B := New_Line (2.0, 5.0, Pi);
      LL.Run;
      Check (not LL.Intersects and then LL.Num_Points = 0
             and then LL.X = 0.0, "parallel lines: none");
      Check_Near (LL.Angle, Pi, 1.0E-15, "angle Pi");
      LL.Line_B := New_Line (-7.0, 0.0, 0.0);
      LL.Run;
      Check (LL.Intersects and then LL.Num_Points = -1
             and then LL.X = 0.0 and then LL.Y = 0.0,
             "coincident lines: -1, no point (VisionPro)");

      SL.Segment := New_Segment (3.0, -1.0, 3.0, 2.0);
      SL.Run;
      Check (Accepted (SL) and then SL.Num_Points = 1
             and then SL.X = 3.0 and then SL.Y = 0.0, "segment across");
      SL.Segment := New_Segment (3.0, 1.0, 3.0, 2.0);
      SL.Run;
      Check (not SL.Intersects and then SL.Num_Points = 0, "short of it");
      SL.Segment := New_Segment (3.0, 0.0, 3.0, 2.0);
      SL.Run;
      Check (SL.Num_Points = 1 and then SL.X = 3.0 and then SL.Y = 0.0,
             "touching at its start");
      SL.Segment := New_Segment (3.0, 0.0, 9.0, 0.0);
      SL.Run;
      Check (SL.Intersects and then SL.Num_Points = -1,
             "lying on the line: -1");

      SS.Segment_A := New_Segment (0.0, 0.0, 2.0, 2.0);
      SS.Segment_B := New_Segment (0.0, 2.0, 2.0, 0.0);
      SS.Run;
      Check (Accepted (SS) and then SS.Num_Points = 1
             and then SS.X = 1.0 and then SS.Y = 1.0, "crossing at (1, 1)");
      SS.Segment_A := New_Segment (0.0, 0.0, 1.0, 0.0);
      SS.Segment_B := New_Segment (1.0, 0.0, 1.0, 1.0);
      SS.Run;
      Check (SS.Num_Points = 1 and then SS.X = 1.0 and then SS.Y = 0.0,
             "touching at an end point");
      SS.Segment_B := New_Segment (0.0, 1.0, 1.0, 1.0);
      SS.Run;
      Check (not SS.Intersects and then SS.Num_Points = 0, "parallel");
      SS.Segment_B := New_Segment (0.5, 0.0, 3.0, 0.0);
      SS.Run;
      Check (SS.Intersects and then SS.Num_Points = -1,
             "collinear and overlapping: -1");
      SS.Segment_B := New_Segment (1.0, 0.0, 3.0, 0.0);
      SS.Run;
      Check (SS.Num_Points = 1 and then SS.X = 1.0,
             "collinear, sharing only an end point");
      SS.Segment_B := New_Segment (2.0, 0.0, 3.0, 0.0);
      SS.Run;
      Check (SS.Num_Points = 0, "collinear apart");

      LC.Input_Circle := New_Circle (0.0, 0.0, 5.0);
      LC.Run;
      Check (Accepted (LC) and then LC.Num_Points = 2
             and then LC.X0 = -5.0 and then LC.X1 = 5.0,
             "two points along the line");
      LC.Line := New_Line (0.0, 5.0, Pi);
      LC.Run;
      Check (LC.Num_Points = 1 and then abs LC.X0 < 1.0E-12
             and then LC.Y0 = 5.0 and then LC.X1 = 0.0 and then LC.Y1 = 0.0,
             "tangent: one point, the second (0, 0)");
      LC.Line := New_Line (0.0, 6.0, 0.0);
      LC.Run;
      Check (not LC.Intersects and then LC.Num_Points = 0, "missing");

      SC.Input_Circle := New_Circle (0.0, 0.0, 5.0);
      SC.Segment := New_Segment (10.0, 0.0, -10.0, 0.0);
      SC.Run;
      Check (Accepted (SC) and then SC.Num_Points = 2
             and then SC.X0 = 5.0 and then SC.X1 = -5.0,
             "two points from start to end");
      SC.Segment := New_Segment (0.0, 0.0, 10.0, 0.0);
      SC.Run;
      Check (SC.Num_Points = 1 and then SC.X0 = 5.0, "from inside out");
      SC.Segment := New_Segment (-3.0, 0.0, 3.0, 0.0);
      SC.Run;
      Check (SC.Num_Points = 0, "inside");
      SC.Segment := New_Segment (5.0, 0.0, 10.0, 0.0);
      SC.Run;
      Check (SC.Num_Points = 1 and then SC.X0 = 5.0 and then SC.Y0 = 0.0,
             "an end point on the circle");

      CC.Circle_A := New_Circle (0.0, 0.0, 5.0);
      CC.Circle_B := New_Circle (8.0, 0.0, 5.0);
      CC.Run;
      Check (Accepted (CC) and then CC.Num_Points = 2, "two points");
      Check_Near (CC.X0, 4.0, 1.0E-12, "X0 = 4");
      Check_Near (CC.Y0, 3.0, 1.0E-12, "the first on the left (+y)");
      Check_Near (CC.Y1, -3.0, 1.0E-12, "the second on the right");
      Check (CC.X2 = 0.0 and then CC.Y3 = 0.0, "X2 .. Y3 stay 0");
      CC.Circle_B := New_Circle (10.0, 0.0, 5.0);
      CC.Run;
      Check (CC.Num_Points = 1 and then CC.X1 = 0.0, "touching");
      Check_Near (CC.X0, 5.0, 1.0E-12, "at (5, 0)");
      CC.Circle_B := New_Circle (0.0, 0.0, 5.0);
      CC.Run;
      Check (CC.Intersects and then CC.Num_Points = -1 and then CC.X0 = 0.0,
             "identical: -1 (VisionPro)");
      CC.Circle_B := New_Circle (0.0, 0.0, 3.0);
      CC.Run;
      Check (not CC.Intersects and then CC.Num_Points = 0, "concentric");

      LE.Ellipse := New_Ellipse (0.0, 0.0, 5.0, 3.0, 0.0);
      LE.Run;
      Check (Accepted (LE) and then LE.Num_Points = 2, "two points");
      Check_Near (LE.X0, -5.0, 1.0E-12, "(-5, 0) first");
      Check_Near (LE.X1, 5.0, 1.0E-12, "then (5, 0)");
      LE.Line := New_Line (0.0, 3.0, 0.0);
      LE.Run;
      Check (LE.Num_Points = 1 and then LE.X1 = 0.0, "tangent");
      Check_Near (LE.Y0, 3.0, 1.0E-12, "at the top");
      LE.Ellipse := New_Ellipse (2.0, -1.0, 6.0, 2.0, Pi / 6.0);
      LE.Line := New_Line (0.0, 0.0, 1.1);
      LE.Run;
      Check (LE.Num_Points = 2, "rotated ellipse: two points");
      Check_Near (Ellipse_Value (LE.X0, LE.Y0, 2.0, -1.0, 6.0, 2.0,
                                 Pi / 6.0), 1.0, 1.0E-12,
                  "the first lies on the ellipse");
      Check_Near (Ellipse_Value (LE.X1, LE.Y1, 2.0, -1.0, 6.0, 2.0,
                                 Pi / 6.0), 1.0, 1.0E-12,
                  "the second too");
      Check_Near (LE.Y0 * EF.Cos (1.1) - LE.X0 * EF.Sin (1.1), 0.0, 1.0E-12,
                  "and on the line");
      Check (LE.X0 * EF.Cos (1.1) + LE.Y0 * EF.Sin (1.1)
             < LE.X1 * EF.Cos (1.1) + LE.Y1 * EF.Sin (1.1),
             "in the order of the line");

      SE.Ellipse := New_Ellipse (0.0, 0.0, 5.0, 3.0, 0.0);
      SE.Segment := New_Segment (0.0, 0.0, 0.0, 10.0);
      SE.Run;
      Check (Accepted (SE) and then SE.Num_Points = 1, "from inside out");
      Check_Near (SE.Y0, 3.0, 1.0E-12, "at the top");
      SE.Segment := New_Segment (0.0, 10.0, 0.0, -10.0);
      SE.Run;
      Check (SE.Num_Points = 2 and then SE.Y0 > 0.0 and then SE.Y1 < 0.0,
             "through: from start to end");
      SE.Segment := New_Segment (-1.0, 0.0, 1.0, 0.0);
      SE.Run;
      Check (SE.Num_Points = 0, "inside");
   end Test_Intersections;

   ---------------------------------------------------------------------
   --  Coordinate spaces and failures
   ---------------------------------------------------------------------

   procedure Test_Spaces is
      Fix  : constant Ks_Transform_2D_Linear :=
        Create_Rigid (0.5, 100.0, 50.0);
      Tree : Ks_Coordinate_Space_Tree;
      PL   : Ks_Distance_Point_Line_Tool;
      PC   : Ks_Distance_Point_Circle_Tool;
      PE   : Ks_Distance_Point_Ellipse_Tool;
      PX, PY, FX, FY : Real;
   begin
      Section ("Dimensioning: coordinate spaces");
      Tree.Add_Space ("@", "Fixture", Fix);
      Tree.Add_Space ("@", "Stretch", Create (2.0, 0.0, 0.0, 1.0, 0.0, 0.0));
      PL.Input_Image.Set_Coordinate_Space_Tree (Tree);
      --  The line through the fixture's (10, 0) along its x axis, the
      --  point at the fixture's (10, 5), given in the root space.
      PL.Line := New_Line (10.0, 0.0, 0.0);
      PL.Line.Set_Selected_Space_Name ("@\Fixture");
      Fix.Map_Point (10.0, 5.0, PX, PY);
      Fix.Map_Point (10.0, 0.0, FX, FY);
      PL.X := PX;
      PL.Y := PY;
      PL.Run;
      Check (Accepted (PL), "a line in a fixture space");
      Check_Near (PL.Distance, 5.0, 1.0E-12, "the distance in the root");
      Check_Near (PL.Line_X, FX, 1.0E-12, "the foot, mapped X");
      Check_Near (PL.Line_Y, FY, 1.0E-12, "the foot, mapped Y");
      --  The image's selected space is the fixture: the point in fixture
      --  coordinates, the line in "." (the fixture too).
      PL.Input_Image.Set_Selected_Space_Name ("@\Fixture");
      PL.Line.Set_Selected_Space_Name (".");
      PL.X := 10.0;
      PL.Y := 5.0;
      PL.Run;
      Check (Accepted (PL) and then PL.Distance = 5.0
             and then PL.Line_X = 10.0, "everything in the fixture");
      PL.Line.Set_Selected_Space_Name ("@\Nowhere");
      PL.Run;
      Check (Failed_With (PL, "Ks_Image_Bad_Selected_Space_Name_Exception"),
             "an unknown space name");

      PC.Input_Image.Set_Coordinate_Space_Tree (Tree);
      PC.Input_Circle := New_Circle (0.0, 0.0, 5.0);
      PC.Input_Circle.Set_Selected_Space_Name ("@\Stretch");
      PC.Run;
      Check (Failed_With (PC, "Ks_Bad_Parameter_Exception"),
             "a circle in a stretched space (not a similarity)");
      PE.Input_Image.Set_Coordinate_Space_Tree (Tree);
      PE.Ellipse := New_Ellipse (0.0, 0.0, 5.0, 3.0, 0.0);
      PE.Ellipse.Set_Selected_Space_Name ("@\Stretch");
      PE.X := 20.0;
      PE.Run;
      Check (Accepted (PE), "an ellipse in a stretched space");
      Check_Near (PE.Distance, 10.0, 1.0E-12,
                  "measured on the stretched ellipse (radius 10 along x)");
   end Test_Spaces;

   ---------------------------------------------------------------------
   --  Fits
   ---------------------------------------------------------------------

   procedure Test_Fit_Points is
      P  : Ks_Fit_Line;
      Q  : Ks_Fit_Line;
      X, Y : Real;

      procedure Bad_Index is
      begin
         P.Get_Point (7, X, Y);
      end Bad_Index;

      procedure Check_Bad_Index is new Check_Raises_Exactly
        (Bad_Index, Constraint_Error'Identity);

      procedure Bad_Value is
      begin
         P.Add_Point (NaN, 1.0);
      end Bad_Value;

      procedure Check_Bad_Value is new Check_Raises_Exactly
        (Bad_Value, Ks_Bad_Parameter_Exception'Identity);

   begin
      Section ("Fitting: the point list");
      Check (P.Num_Points = 0 and then P.Num_To_Ignore = 0, "defaults");
      P.Add_Point (1.0, 2.0);
      P.Add_Point (3.0, 4.0);
      P.Add_Point (5.0, 6.0);
      Check (P.Num_Points = 3 and then P.Get_X (1) = 3.0
             and then P.Get_Y (2) = 6.0, "AddPoint appends");
      P.Delete_Point (0);
      Check (P.Num_Points = 2 and then P.Get_X (0) = 3.0, "DeletePoint");
      P.Set_Point (1, 7.0, 8.0);
      P.Set_X (0, -1.0);
      P.Set_Y (0, -2.0);
      P.Get_Point (1, X, Y);
      Check (X = 7.0 and then Y = 8.0 and then P.Get_X (0) = -1.0
             and then P.Get_Y (0) = -2.0, "SetPoint, SetX, SetY");
      P.Set_Num_Points (4);
      Check (P.Num_Points = 4 and then P.Get_X (3) = 0.0
             and then P.Get_Y (3) = 0.0, "NumPoints grows with (0, 0)");
      Q := P;
      P.Set_Num_Points (1);
      Check (P.Num_Points = 1 and then Q.Num_Points = 4,
             "copies are independent");
      Check (Q /= P and then Q = Q, "equality compares the points");
      Check_Bad_Index ("an index beyond the points");
      Check_Bad_Value ("a NaN coordinate");
      declare
         S    : aliased Ada.Streams.Storage.Unbounded.Stream_Type;
         C, D : Ks_Fit_Circle;
      begin
         C.Add_Point (1.5, -2.5);
         C.Add_Point (3.0, 4.0);
         C.Set_Num_To_Ignore (1);
         C.Set_Radius_Constraint_Enabled (True);
         C.Set_Radius_Constraint (12.5);
         Ks_Fit_Circle'Write (S'Access, C);
         Ks_Fit_Circle'Read (S'Access, D);
         Check (D = C and then D.Num_Points = 2 and then D.Get_Y (0) = -2.5
                and then D.Num_To_Ignore = 1
                and then D.Radius_Constraint_Enabled
                and then D.Radius_Constraint = 12.5,
                "the run parameters through a stream");
      end;
   end Test_Fit_Points;

   procedure Test_Fit_Line is
      Tool : Ks_Fit_Line_Tool;
      L    : Ks_Line;
   begin
      Section ("Fitting: lines");
      for I in 0 .. 9 loop
         Tool.Run_Params.Add_Point (Real (I), 0.5 * Real (I) + 3.0);
      end loop;
      Tool.Run;
      Report (Tool, "line");
      Check (Accepted (Tool), "FitLineTool runs");
      L := Tool.Result.Get_Line;
      Check_Angle_Near (L.Rotation, EF.Arctan (0.5), 1.0E-12,
                        "the direction of y = x / 2 + 3");
      Check_Near (L.Y - 0.5 * L.X - 3.0, 0.0, 1.0E-12, "through the line");
      Check (Tool.Result.Num_Points = 10
             and then Tool.Result.Num_Points_Used = 10,
             "every point used");
      Check (Tool.Result.RMS_Error < 1.0E-12, "RMS error 0");
      --  An outlier.
      Tool.Run_Params.Add_Point (5.0, 40.0);
      Tool.Run_Params.Set_Num_To_Ignore (1);
      Tool.Run;
      Check (Accepted (Tool) and then not Tool.Result.Get_Used (10)
             and then Tool.Result.Get_Used (3), "the outlier is left out");
      Check (Tool.Result.Num_Points = 11
             and then Tool.Result.Num_Points_Used = 10,
             "NumPoints 11, 10 used");
      Check_Near (Tool.Result.Get_Distance (10),
                  (40.0 - 5.5) / EF.Sqrt (1.25), 1.0E-9,
                  "the outlier's distance to the line");
      Check (Tool.Result.RMS_Error < 1.0E-12, "RMS error of the used points");
      Check (Tool.Result.Get_X (10) = 5.0
             and then Tool.Result.Get_Y (10) = 40.0, "GetX and GetY");
      Tool.Run_Params.Set_Num_To_Ignore (10);
      Tool.Run;
      Check (Failed_With (Tool, "Ks_Bad_Parameter_Exception",
                          "FitLine: NumPoints - NumToIgnore must be at least"
                          & " 2 (NumPoints = 11, NumToIgnore = 10)"),
             "too few points left");
      Check (Tool.Result.Num_Points = 0, "no result after a failure");
      declare
         procedure No_Line is
            Unused : constant Ks_Line := Tool.Result.Get_Line;
         begin
            null;
         end No_Line;

         procedure Check_No_Line is new Check_Raises_Exactly
           (No_Line, Ks_Bad_Parameter_Exception'Identity);

         R : Ks_Fit_Line_Result;
      begin
         Check_No_Line ("GetLine without a result");
         Tool.Run_Params.Set_Num_To_Ignore (0);
         R := Execute (Tool.Run_Params, "@\Fixture");
         Check (R.Get_Line.Selected_Space_Name = "@\Fixture"
                and then R.Num_Points = 11,
                "Execute: the line in the space named");
      end;
   end Test_Fit_Line;

   procedure Test_Fit_Circle is
      Tool : Ks_Fit_Circle_Tool;
      C    : Ks_Circle;
      X, Y : Real;
   begin
      Section ("Fitting: circles");
      for I in 0 .. 11 loop
         X := 10.0 + 30.0 * EF.Cos (0.4 * Real (I));
         Y := 20.0 + 30.0 * EF.Sin (0.4 * Real (I));
         Tool.Run_Params.Add_Point (X, Y);
      end loop;
      Tool.Run;
      Report (Tool, "circle");
      C := Tool.Result.Get_Circle;
      Check_Near (C.Center_X, 10.0, 1.0E-9, "centre X");
      Check_Near (C.Center_Y, 20.0, 1.0E-9, "centre Y");
      Check_Near (C.Radius, 30.0, 1.0E-9, "radius");
      Tool.Run_Params.Add_Point (10.0, 20.0);
      Tool.Run_Params.Add_Point (200.0, 20.0);
      Tool.Run_Params.Set_Num_To_Ignore (2);
      Tool.Run;
      C := Tool.Result.Get_Circle;
      Check (Accepted (Tool) and then not Tool.Result.Get_Used (12)
             and then not Tool.Result.Get_Used (13), "two outliers left out");
      Check_Near (C.Radius, 30.0, 1.0E-9, "the radius without them");
      Check_Near (Tool.Result.Get_Distance (12), 30.0, 1.0E-9,
                  "the centre point is 30 from the circle");
      --  The radius constraint on a short arc with a wrong radius.
      Tool.Run_Params.Set_Num_To_Ignore (2);
      Tool.Run_Params.Set_Radius_Constraint_Enabled (True);
      Tool.Run_Params.Set_Radius_Constraint (30.0);
      Tool.Run;
      Report (Tool, "fixed radius");
      C := Tool.Result.Get_Circle;
      Check (Accepted (Tool) and then C.Radius = 30.0,
             "the radius is the constraint");
      Check_Near (C.Center_X, 10.0, 1.0E-6, "fixed radius: centre X");
      Check_Near (C.Center_Y, 20.0, 1.0E-6, "fixed radius: centre Y");
      Tool.Run_Params.Set_Radius_Constraint (-1.0);
      Tool.Run;
      Check (Failed_With (Tool, "Ks_Bad_Parameter_Exception",
                          "RunParams.RadiusConstraint must be > 0 and within"
                          & " 1.0E150"), "a negative radius constraint");
      declare
         Collinear : Ks_Fit_Circle_Tool;
      begin
         for I in 0 .. 5 loop
            Collinear.Run_Params.Add_Point (Real (I), 2.0 * Real (I));
         end loop;
         Collinear.Run;
         Check (Failed_With (Collinear, "Ks_Bad_Parameter_Exception"),
                "collinear points");
      end;
   end Test_Fit_Circle;

   procedure Test_Fit_Ellipse is
      CX  : constant Real := 40.0;
      CY  : constant Real := -20.0;
      RX  : constant Real := 30.0;
      RY  : constant Real := 12.0;
      Rot : constant Real := 0.6;
      Tool : Ks_Fit_Ellipse_Tool;
      E    : Ks_Ellipse;
      X, Y, Nx, Ny : Real;
   begin
      Section ("Fitting: ellipses");
      for I in 0 .. 39 loop
         Ellipse_Point (CX, CY, RX, RY, Rot, 2.0 * Pi * Real (I) / 40.0,
                        X, Y);
         Tool.Run_Params.Add_Point (X, Y);
      end loop;
      Tool.Run;
      Report (Tool, "exact ellipse");
      E := Tool.Result.Get_Ellipse;
      Check (Accepted (Tool), "FitEllipseTool runs");
      Check_Near (E.Center_X, CX, 1.0E-7, "exact points: centre X");
      Check_Near (E.Center_Y, CY, 1.0E-7, "centre Y");
      Check_Near (E.Radius_X, RX, 1.0E-7, "major radius");
      Check_Near (E.Radius_Y, RY, 1.0E-7, "minor radius");
      Check_Near (E.Rotation, Rot, 1.0E-9, "rotation of the major axis");
      Check (Tool.Result.RMS_Error < 1.0E-7, "RMS error about 0");

      --  Noisy samples of the same ellipse, all around.
      declare
         Noisy : Ks_Fit_Ellipse_Tool;
      begin
         for I in 0 .. 199 loop
            Ellipse_Point (CX, CY, RX, RY, Rot, 2.0 * Pi * Real (I) / 200.0,
                           X, Y);
            Noisy_Point (X, Y, 0.2, Nx, Ny);
            Noisy.Run_Params.Add_Point (Nx, Ny);
         end loop;
         Noisy.Run;
         E := Noisy.Result.Get_Ellipse;
         Check_Near (E.Center_X, CX, 0.05, "noisy: centre X");
         Check_Near (E.Center_Y, CY, 0.05, "noisy: centre Y");
         Check_Near (E.Radius_X, RX, 0.1, "noisy: major radius");
         Check_Near (E.Radius_Y, RY, 0.1, "noisy: minor radius");
         Check_Angle_Near (E.Rotation, Rot, 0.01, "noisy: rotation");
         Check (Noisy.Result.RMS_Error > 0.01
                and then Noisy.Result.RMS_Error < 0.2,
                "noisy: RMS error of the order of the noise");
         Ada.Text_IO.Put_Line
           ("  noisy fit: centre (" & E.Center_X'Image & ","
            & E.Center_Y'Image & "), radii" & E.Radius_X'Image & ","
            & E.Radius_Y'Image & ", rotation" & E.Rotation'Image
            & ", RMS" & Noisy.Result.RMS_Error'Image);
      end;

      --  Half of a rotated ellipse with noise.
      declare
         Half : Ks_Fit_Ellipse_Tool;
      begin
         for I in 0 .. 99 loop
            Ellipse_Point (CX, CY, RX, RY, -1.1, Pi * Real (I) / 99.0,
                           X, Y);
            Noisy_Point (X, Y, 0.05, Nx, Ny);
            Half.Run_Params.Add_Point (Nx, Ny);
         end loop;
         Half.Run;
         E := Half.Result.Get_Ellipse;
         Check (Accepted (Half), "half an ellipse");
         Check_Near (E.Radius_X, RX, 0.3, "half: major radius");
         Check_Near (E.Radius_Y, RY, 0.3, "half: minor radius");
         Check_Angle_Near (E.Rotation, -1.1, 0.02, "half: rotation");
      end;

      --  Outliers.
      Tool.Run_Params.Add_Point (CX, CY);
      Tool.Run_Params.Add_Point (CX + 200.0, CY - 50.0);
      Tool.Run_Params.Set_Num_To_Ignore (2);
      Tool.Run;
      Report (Tool, "outliers");
      E := Tool.Result.Get_Ellipse;
      Check (Accepted (Tool) and then not Tool.Result.Get_Used (40)
             and then not Tool.Result.Get_Used (41)
             and then Tool.Result.Num_Points_Used = 40,
             "both outliers left out");
      Check_Near (E.Radius_X, RX, 1.0E-7, "outliers: major radius");
      Check_Near (Tool.Result.Get_Distance (40), RY, 1.0E-6,
                  "the centre is the minor radius from the ellipse");

      --  The rotation constraint.
      Tool.Run_Params.Set_Num_To_Ignore (2);
      Tool.Run_Params.Set_Rotation_Constraint_Enabled (True);
      Tool.Run_Params.Set_Rotation_Constraint (Rot);
      Tool.Run;
      Report (Tool, "constrained");
      E := Tool.Result.Get_Ellipse;
      Check (Accepted (Tool) and then E.Rotation = Rot,
             "the rotation is the constraint");
      Check_Near (E.Radius_X, RX, 1.0E-7, "constrained: radius along it");
      Check_Near (E.Radius_Y, RY, 1.0E-7, "constrained: radius across");
      Tool.Run_Params.Set_Rotation_Constraint (Rot + Pi / 2.0);
      Tool.Run;
      E := Tool.Result.Get_Ellipse;
      Check_Near (E.Radius_X, RY, 1.0E-7,
                  "turned by Pi / 2: Radius_X is the minor radius");

      declare
         Few  : Ks_Fit_Ellipse_Tool;
         Line : Ks_Fit_Ellipse_Tool;
      begin
         for I in 0 .. 3 loop
            Ellipse_Point (CX, CY, RX, RY, Rot, Real (I), X, Y);
            Few.Run_Params.Add_Point (X, Y);
         end loop;
         Few.Run;
         Check (Failed_With (Few, "Ks_Bad_Parameter_Exception",
                             "FitEllipse: NumPoints - NumToIgnore must be at"
                             & " least 5 (NumPoints = 4, NumToIgnore = 0)"),
                "four points are too few");
         for I in 0 .. 7 loop
            Line.Run_Params.Add_Point (Real (I), 3.0 * Real (I) - 1.0);
         end loop;
         Line.Run;
         Check (Failed_With (Line, "Ks_Bad_Parameter_Exception",
                             "FitEllipse: the points are (nearly)"
                             & " collinear"), "collinear points");
      end;

      --  Large coordinates.
      declare
         Far : Ks_Fit_Ellipse_Tool;
      begin
         for I in 0 .. 29 loop
            Ellipse_Point (1.0E6, -3.0E6, 500.0, 200.0, 2.0,
                           2.0 * Pi * Real (I) / 30.0, X, Y);
            Far.Run_Params.Add_Point (X, Y);
         end loop;
         Far.Run;
         E := Far.Result.Get_Ellipse;
         Check_Near (E.Center_X, 1.0E6, 1.0E-5, "far away: centre");
         Check_Near (E.Radius_X, 500.0, 1.0E-5, "far away: radius");
         Check_Angle_Near (2.0 * E.Rotation, 2.0 * (2.0 - Pi), 1.0E-9,
                           "far away: rotation (mod Pi)");
      end;
   end Test_Fit_Ellipse;

   ---------------------------------------------------------------------
   --  The kernels directly
   ---------------------------------------------------------------------

   procedure Test_Kernel is
      Status : K.Ks_Status;
      R1     : KD.Ks_Distance_Point_Line_Result;
      R2     : KD.Ks_Intersect_Circle_Circle_Result;
      Angle  : Real;
      Line   : constant KS.Ks_Line := (X => 0.0, Y => 0.0, Rotation => 0.0);
      Circle : constant KS.Ks_Circle :=
        (Center_X => 0.0, Center_Y => 0.0, Radius => 5.0);
      Zero_T : constant KT.Ks_Transform_2D_Linear :=
        (A => 0.0, B => 0.0, C => 0.0, D => 0.0, others => <>);
      Points : KS.Ks_Polygon;
      Result : KF.Ks_Fit_Result;
      Count  : K.Int32;
      X, Y, D : Real;
      Used   : K.Int32;
      KL     : KS.Ks_Line;
      Params : KF.Ks_Fit_Line_Run_Params;
   begin
      Section ("Dimensioning: kernel");
      KD.Distance_Point_Line (NaN, 0.0, Line, Id, R1, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then R1 = (others => <>), "a NaN point, zero results");
      KD.Distance_Point_Line (1.0, 0.0, (Line with delta Rotation => NaN),
                              Id, R1, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter, "a NaN rotation");
      KD.Distance_Point_Line (1.0, 0.0, Line, (Id with delta A => NaN), R1,
                              Status);
      Check (Status.Failure = K.Failure_Bad_Parameter, "a NaN transform");
      KD.Distance_Point_Line (1.0, 0.0, Line, Zero_T, R1, Status);
      Check (Status.Failure = K.Failure_Transform_Singular,
             "a singular transform of a line");
      KD.Angle_Line_Line (Line, Line, Id, (Id with delta D => 1.0 / Zero),
                          Angle, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter and then Angle = 0.0,
             "an infinite transform");
      KD.Intersect_Circle_Circle (Circle, (Circle with delta Radius => -1.0),
                                  Id, Id, R2, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then R2.Num_Points = 0, "a negative radius");
      KD.Intersect_Circle_Circle
        (Circle, (Circle with delta Center_X => 1.0E150), Id, Id, R2,
         Status);
      Check (Status.Failure = K.Failure_None and then R2.Num_Points = 0,
             "circles at the bound");

      --  The point list and the results with null handles.
      KF.Points_Num_Points (null, Count, Status);
      Check (Status.Failure = K.Failure_None and then Count = 0,
             "null points: none");
      KF.Points_Get_Point (null, 0, X, Y, Status);
      Check (Status.Failure = K.Failure_Index_Out_Of_Range,
             "null points: no point 0");
      KF.Points_Set_Num_Points (Points, KF.Max_Points + 1, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter and then Points = null,
             "more than Max_Points");
      KF.Points_Set_Num_Points (Points, KF.Max_Points, Status);
      Check (Status.Failure = K.Failure_None, "exactly Max_Points");
      KF.Points_Add_Point (Points, 1.0, 1.0, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter,
             "no room beyond Max_Points");
      KF.Line_Execute (Points, Params, Result, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter and then Result = null,
             "Max_Points coinciding points");
      KF.Points_Destroy (Points);
      Check (Points = null, "destroy");
      KF.Points_Add_Point (Points, 1.0 / Zero, 1.0, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter and then Points = null,
             "an infinite coordinate");
      KF.Line_Execute (null, Params, Result, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter and then Result = null,
             "no points");
      Params.Num_To_Ignore := -1;
      KF.Points_Add_Point (Points, 1.0, 1.0, Status);
      KF.Points_Add_Point (Points, 2.0, 1.0, Status);
      KF.Line_Execute (Points, Params, Result, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter,
             "a negative NumToIgnore");
      Params.Num_To_Ignore := 0;
      KF.Line_Execute (Points, Params, Result, Status);
      Check (Status.Failure = K.Failure_None and then Result /= null,
             "two points");
      KF.Result_Get_XY_Used_Distance (Result, 1, X, Y, Used, D, Status);
      Check (Status.Failure = K.Failure_None and then X = 2.0
             and then Used = K.True_Value and then D < 1.0E-15,
             "GetXYUsedDistance");
      KF.Result_Get_XY_Used_Distance (Result, 2, X, Y, Used, D, Status);
      Check (Status.Failure = K.Failure_Index_Out_Of_Range,
             "an index beyond the points");
      KF.Result_Destroy (Result);
      KF.Points_Destroy (Points);
      KF.Result_Num_Points (null, Count, Status);
      Check (Status.Failure = K.Failure_None and then Count = 0,
             "null result: no points");
      KF.Result_Get_Line (null, KL, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter, "null result: no line");
   end Test_Kernel;

   procedure Test_Timing is
      Tool  : Ks_Fit_Ellipse_Tool;
      Fit_C : Ks_Fit_Circle_Tool;
      PE    : Ks_Distance_Point_Ellipse_Tool;
      Start : Ada.Calendar.Time;
      X, Y, Nx, Ny : Real;
   begin
      Section ("Dimensioning: timing");
      for I in 0 .. 999 loop
         Ellipse_Point (0.0, 0.0, 300.0, 100.0, 0.3,
                        2.0 * Pi * Real (I) / 1000.0, X, Y);
         Noisy_Point (X, Y, 0.5, Nx, Ny);
         Tool.Run_Params.Add_Point (Nx, Ny);
         if I mod 5 = 0 then
            Fit_C.Run_Params.Add_Point (X, Y);
         end if;
      end loop;
      Start := Ada.Calendar.Clock;
      Tool.Run;
      Ada.Text_IO.Put_Line
        ("  ellipse fit of 1000 points:"
         & Duration'Image (Ada.Calendar."-" (Ada.Calendar.Clock, Start)
                           * 1000.0) & " ms");
      Tool.Run_Params.Set_Num_To_Ignore (5);
      Start := Ada.Calendar.Clock;
      Tool.Run;
      Ada.Text_IO.Put_Line
        ("  ellipse fit of 1000 points, NumToIgnore 5:"
         & Duration'Image (Ada.Calendar."-" (Ada.Calendar.Clock, Start)
                           * 1000.0) & " ms");
      Check (Accepted (Tool), "the robust fit runs");
      Fit_C.Run_Params.Set_Num_To_Ignore (5);
      Start := Ada.Calendar.Clock;
      Fit_C.Run;
      Ada.Text_IO.Put_Line
        ("  circle fit of 200 points, NumToIgnore 5:"
         & Duration'Image (Ada.Calendar."-" (Ada.Calendar.Clock, Start)
                           * 1000.0) & " ms");
      PE.Ellipse := New_Ellipse (0.0, 0.0, 300.0, 100.0, 0.3);
      PE.X := 17.0;
      PE.Y := 400.0;
      Start := Ada.Calendar.Clock;
      for I in 1 .. 1000 loop
         PE.Run;
      end loop;
      Ada.Text_IO.Put_Line
        ("  point to ellipse:"
         & Duration'Image (Ada.Calendar."-" (Ada.Calendar.Clock, Start))
         & " ms per run");
   end Test_Timing;

   procedure Run_All is
   begin
      Test_Points_And_Angles;
      Test_Point_Distances;
      Test_Ellipse_Distances;
      Test_Two_Shape_Distances;
      Test_Intersections;
      Test_Spaces;
      Test_Fit_Points;
      Test_Fit_Line;
      Test_Fit_Circle;
      Test_Fit_Ellipse;
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
end Test_Dimensioning;
