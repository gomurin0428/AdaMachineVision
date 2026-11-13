--  Tests for AMV.Geometry: distances, projections, intersections and the
--  least squares line and circle fits (plain and robust).
--
--  Noisy fits use deterministic pseudo-noise that is made orthogonal to
--  the fit's gradient conditions (for a line: to 1 and to the position
--  along the line; for a circle: to 1, cos and sin of the point angle).
--  The generating line or circle is then exactly the least squares
--  solution, so noisy fits can be checked with tight tolerances too.

with Ada.Exceptions;
with Ada.Numerics.Generic_Elementary_Functions;
with Ada.Text_IO;
with Interfaces;

with AMV;
with AMV.Geometry;
with AMV.Misc;
with AMV_Test_Support;

procedure Test_Geometry is

   use AMV;
   use AMV.Geometry;
   use AMV_Test_Support;

   package Math is new Ada.Numerics.Generic_Elementary_Functions (Real);
   use Math;

   Pi : constant := AMV.Misc.Pi;

   type Real_List is array (Positive range <>) of Real;
   type Count_List is array (Positive range <>) of Positive;

   ---------------------------------------------------------------------
   --  Helpers
   ---------------------------------------------------------------------

   Seed : Interfaces.Unsigned_64 := 16#2545_F491_4F6C_DD1D#;

   function Uniform return Real;
   --  Deterministic pseudo-random value in [-1, 1) (64-bit LCG).

   function Uniform return Real is
      use type Interfaces.Unsigned_64;
   begin
      Seed := Seed * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
      return Real (Interfaces.Shift_Right (Seed, 11)) / 2.0 ** 52 - 1.0;
   end Uniform;

   generic
      with procedure Action;
   procedure Expect_Bad_Parameter (Description : String);
   --  Passes only when Action raises Ks_Bad_Parameter_Exception.

   procedure Expect_Bad_Parameter (Description : String) is
      procedure Filtered;
      procedure Filtered is
      begin
         Action;
      exception
         when AMV.Ks_Bad_Parameter_Exception =>
            raise;
         when E : others =>
            --  Swallowed, so Check_Raises reports the failure.
            Ada.Text_IO.Put_Line
              ("  " & Description & ": wrong exception "
               & Ada.Exceptions.Exception_Name (E) & ": "
               & Ada.Exceptions.Exception_Message (E));
      end Filtered;
      procedure Run_Check is new Check_Raises (Filtered);
   begin
      Run_Check (Description);
   end Expect_Bad_Parameter;

   procedure Check_Point
     (Got, Expected : Point_2D; Tolerance : Real; Description : String);

   procedure Check_Point
     (Got, Expected : Point_2D; Tolerance : Real; Description : String) is
   begin
      Check_Near (Got.X, Expected.X, Tolerance, Description & " X");
      Check_Near (Got.Y, Expected.Y, Tolerance, Description & " Y");
   end Check_Point;

   procedure Check_In_Line_Range (Rotation : Real; Description : String);
   --  Line rotations must lie in (-Pi/2, Pi/2].

   procedure Check_In_Line_Range (Rotation : Real; Description : String) is
   begin
      Check (Rotation > -Pi / 2.0 and then Rotation <= Pi / 2.0,
             Description & ": rotation in (-Pi/2, Pi/2] (got"
             & Real'Image (Rotation) & ")");
   end Check_In_Line_Range;

   procedure Check_Axis_Near
     (Got, Expected, Tolerance : Real; Description : String);
   --  Compares undirected line orientations (modulo Pi).

   procedure Check_Axis_Near
     (Got, Expected, Tolerance : Real; Description : String) is
   begin
      Check_Near (AMV.Misc.Norm_Angle_Pi (Got - Expected), 0.0, Tolerance,
                  Description & " (orientation mod Pi)");
   end Check_Axis_Near;

   procedure Make_Line_Points
     (X0, Y0, Rotation, Spacing, Noise : Real;
      Points       : out Point_Array;
      Expected_RMS : out Real);
   --  Points spaced evenly along the line through (X0, Y0) with the given
   --  direction, centred on (X0, Y0), displaced across the line by noise
   --  of amplitude Noise that has zero mean and no correlation with the
   --  position along the line. Expected_RMS is the RMS of that noise.

   procedure Make_Line_Points
     (X0, Y0, Rotation, Spacing, Noise : Real;
      Points       : out Point_Array;
      Expected_RMS : out Real)
   is
      N      : constant Natural := Points'Length;
      C      : constant Real := Cos (Rotation);
      S      : constant Real := Sin (Rotation);
      T      : array (Points'Range) of Real;
      E      : array (Points'Range) of Real;
      Mean   : Real := 0.0;
      Stt    : Real := 0.0;
      Ste    : Real := 0.0;
      Sum_Sq : Real := 0.0;
   begin
      for I in Points'Range loop
         T (I) := (Real (I - Points'First) - Real (N - 1) / 2.0) * Spacing;
         E (I) := Noise * Uniform;
         Mean := Mean + E (I);
      end loop;
      Mean := Mean / Real (N);
      for I in Points'Range loop
         E (I) := E (I) - Mean;
         Stt := Stt + T (I) * T (I);
         Ste := Ste + T (I) * E (I);
      end loop;
      for I in Points'Range loop
         E (I) := E (I) - (Ste / Stt) * T (I);
         Sum_Sq := Sum_Sq + E (I) * E (I);
         Points (I) := (X => X0 + T (I) * C - E (I) * S,
                        Y => Y0 + T (I) * S + E (I) * C);
      end loop;
      Expected_RMS := Sqrt (Sum_Sq / Real (N));
   end Make_Line_Points;

   procedure Make_Circle_Points
     (CX, CY, Radius, Start, Extent, Noise : Real;
      Points       : out Point_Array;
      Expected_RMS : out Real);
   --  Points at angles Start + Extent * k / (N - 1) on the circle, moved
   --  radially by noise of amplitude Noise that is orthogonal to 1, cos
   --  and sin of the angle. Pass Extent = 2 Pi (N - 1) / N for evenly
   --  spaced points around the full circle.

   procedure Make_Circle_Points
     (CX, CY, Radius, Start, Extent, Noise : Real;
      Points       : out Point_Array;
      Expected_RMS : out Real)
   is
      subtype Index is Natural range Points'Range;
      type Vector is array (Index) of Real;
      N      : constant Natural := Points'Length;
      Angle  : Vector;
      Basis  : array (1 .. 3) of Vector;
      E      : Vector;
      Dot    : Real;
      Norm   : Real;
      Sum_Sq : Real := 0.0;
   begin
      for I in Index loop
         Angle (I) := Start + Extent * Real (I - Points'First)
                                     / Real (N - 1);
         Basis (1) (I) := 1.0;
         Basis (2) (I) := Cos (Angle (I));
         Basis (3) (I) := Sin (Angle (I));
         E (I) := Noise * Uniform;
      end loop;

      --  Modified Gram-Schmidt with a second pass for accuracy.
      for J in 1 .. 3 loop
         for Pass in 1 .. 2 loop
            for K in 1 .. J - 1 loop
               Dot := 0.0;
               for I in Index loop
                  Dot := Dot + Basis (J) (I) * Basis (K) (I);
               end loop;
               for I in Index loop
                  Basis (J) (I) := Basis (J) (I) - Dot * Basis (K) (I);
               end loop;
            end loop;
            Norm := 0.0;
            for I in Index loop
               Norm := Norm + Basis (J) (I) ** 2;
            end loop;
            Norm := Sqrt (Norm);
            for I in Index loop
               Basis (J) (I) := Basis (J) (I) / Norm;
            end loop;
         end loop;
      end loop;

      for Pass in 1 .. 2 loop
         for J in 1 .. 3 loop
            Dot := 0.0;
            for I in Index loop
               Dot := Dot + E (I) * Basis (J) (I);
            end loop;
            for I in Index loop
               E (I) := E (I) - Dot * Basis (J) (I);
            end loop;
         end loop;
      end loop;

      for I in Index loop
         Sum_Sq := Sum_Sq + E (I) ** 2;
         Points (I) := (X => CX + (Radius + E (I)) * Cos (Angle (I)),
                        Y => CY + (Radius + E (I)) * Sin (Angle (I)));
      end loop;
      Expected_RMS := Sqrt (Sum_Sq / Real (N));
   end Make_Circle_Points;

   ---------------------------------------------------------------------
   --  Distances, projection, angles
   ---------------------------------------------------------------------

   procedure Test_Distances is
      L0 : constant Line_2D := (X => 1.0, Y => 2.0, Rotation => 0.0);
      L1 : constant Line_2D := (X => 1.0, Y => 2.0, Rotation => Pi / 2.0);
      L2 : constant Line_2D := (X => 0.0, Y => 0.0, Rotation => Pi / 4.0);
      L3 : constant Line_2D := (X => 0.0, Y => 0.0, Rotation => Pi);
      L4 : constant Line_2D := (X => 10.0, Y => 0.0, Rotation => 0.0);
      C  : constant Circle_2D :=
        (Center_X => 1.0, Center_Y => 1.0, Radius => 2.0);
      R2 : constant Real := Sqrt (2.0);
   begin
      Section ("distances and projection");
      Check_Near (Distance (Point_2D'(0.0, 0.0), Point_2D'(3.0, 4.0)), 5.0,
                  1.0E-15, "point distance 3-4-5");
      Check_Near (Distance (Point_2D'(2.0, 2.0), Point_2D'(2.0, 2.0)), 0.0,
                  0.0, "point distance to itself");

      --  Rotation 0: the left normal (0, 1) points down in a y-down image.
      Check_Near (Signed_Distance ((5.0, 7.0), L0), 5.0, 1.0E-15,
                  "below a rightward line is positive");
      Check_Near (Signed_Distance ((5.0, -1.0), L0), -3.0, 1.0E-15,
                  "above a rightward line is negative");
      Check_Near (Distance ((5.0, -1.0), L0), 3.0, 1.0E-15,
                  "unsigned distance");
      --  Rotation Pi/2: direction (0, 1), left normal (-1, 0).
      Check_Near (Signed_Distance ((-2.0, 10.0), L1), 3.0, 1.0E-14,
                  "left of a downward line is positive");
      Check_Near (Signed_Distance ((4.0, 0.0), L1), -3.0, 1.0E-14,
                  "right of a downward line is negative");
      --  Reversing the direction flips the sign.
      Check_Near (Signed_Distance ((0.0, 5.0), L3), -5.0, 1.0E-14,
                  "reversed line flips the sign");
      Check_Near (Signed_Distance ((3.0, 2.0), L0), 0.0, 0.0,
                  "point on the line");

      Check_Near (Signed_Distance ((0.0, R2), L2), 1.0, 1.0E-15,
                  "diagonal line signed distance");
      Check_Near (Position_Along ((0.0, R2), L2), 1.0, 1.0E-15,
                  "diagonal line position along");
      Check_Point (Project ((0.0, R2), L2), (R2 / 2.0, R2 / 2.0), 1.0E-15,
                   "diagonal projection");

      Check_Near (Position_Along ((4.0, 3.0), L4), -6.0, 1.0E-15,
                  "position behind the anchor is negative");
      Check_Point (Project ((4.0, 3.0), L4), (4.0, 0.0), 1.0E-15,
                   "projection onto a horizontal line");
      Check_Point (Project ((-7.0, 3.5), L1), (1.0, 3.5), 1.0E-14,
                   "projection onto a vertical line");
      Check_Point (Project ((6.0, 2.0), L0), (6.0, 2.0), 1.0E-15,
                   "a point on the line projects to itself");
      Check_Near (Position_Along ((1.0, -3.0), L1), -5.0, 1.0E-14,
                  "position along a vertical line");

      Check_Near (Distance ((1.0, 1.0), C), 2.0, 0.0,
                  "circle distance from the centre is the radius");
      Check_Near (Distance ((4.0, 5.0), C), 3.0, 1.0E-15,
                  "circle distance from outside");
      Check_Near (Distance ((1.0, 2.0), C), 1.0, 1.0E-15,
                  "circle distance from inside");
      Check_Near (Distance ((1.0, 3.0), C), 0.0, 1.0E-15,
                  "circle distance of a point on it");

      --  Lengths neither underflow nor overflow in between (before the
      --  fix 3-4-5 at 1E-170 gave 0 and at 1E160 Constraint_Error). Since
      --  the kernel, coordinates are bounded by 1.0E150, so the large scale
      --  is 1E140; 1E160 is rejected.
      for S of Real_List'[1.0E-170, 1.0E-300, 1.0E140] loop
         Check_Near (Distance (Point_2D'(3.0 * S, 4.0 * S), Point_2D'(0.0, 0.0))
                     / S, 5.0, 1.0E-15,
                     "point distance 3-4-5 scaled by" & Real'Image (S));
         Check_Near (Distance (Point_2D'(4.0 * S, 5.0 * S),
                               Circle_2D'(S, S, 2.0 * S)) / S,
                     3.0, 1.0E-15,
                     "circle distance scaled by" & Real'Image (S));
      end loop;
      declare
         procedure Beyond_Bound is
            D : constant Real :=
              Distance (Point_2D'(3.0E160, 4.0E160), Point_2D'(0.0, 0.0));
         begin
            Check (D = D, "unreachable");
         end Beyond_Bound;
         procedure Result_Beyond_Bound is
            D : constant Real :=
              Distance (Point_2D'(-1.0E150, -1.0E150),
                        Point_2D'(1.0E150, 1.0E150));
         begin
            Check (D = D, "unreachable");
         end Result_Beyond_Bound;
         procedure Run_1 is new Expect_Bad_Parameter (Beyond_Bound);
         procedure Run_2 is new Expect_Bad_Parameter (Result_Beyond_Bound);
      begin
         Run_1 ("a coordinate beyond 1.0E150 is rejected");
         Run_2 ("a distance beyond 1.0E150 is rejected");
      end;

      Section ("Angle_Between");
      Check_Near (Angle_Between ((0.0, 0.0, 0.5), (0.0, 0.0, 1.2)), 0.7,
                  1.0E-15, "simple difference");
      Check_Near (Angle_Between ((0.0, 0.0, 3.0), (0.0, 0.0, -3.0)),
                  2.0 * Pi - 6.0, 1.0E-14, "wraps past -Pi");
      Check_Near (Angle_Between ((0.0, 0.0, -3.0), (0.0, 0.0, 3.0)),
                  6.0 - 2.0 * Pi, 1.0E-14, "wraps past Pi");
      Check_Near (Angle_Between ((0.0, 0.0, 0.0), (0.0, 0.0, Pi)), Pi,
                  1.0E-15, "half turn gives +Pi");
      Check_Near (Angle_Between ((0.0, 0.0, 0.0), (0.0, 0.0, -Pi)), Pi,
                  1.0E-15, "minus half turn also gives +Pi");
      Check_Near (Angle_Between ((5.0, 5.0, 1.0), (-2.0, 3.0, 1.0)), 0.0,
                  0.0, "parallel lines");
   end Test_Distances;

   ---------------------------------------------------------------------
   --  Intersections
   ---------------------------------------------------------------------

   procedure Test_Line_Line is
      P        : Point_2D;
      Parallel : Boolean;
      A        : constant Line_2D := (X => 0.0, Y => 0.0, Rotation => 0.3);
   begin
      Section ("line-line intersection");
      Intersect ((0.0, 0.0, 0.0), (3.0, -4.0, Pi / 2.0), P, Parallel);
      Check (not Parallel, "perpendicular lines intersect");
      Check_Point (P, (3.0, 0.0), 1.0E-14, "perpendicular intersection");

      Intersect ((1.0, 1.0, Pi / 4.0), (0.0, 4.0, -Pi / 4.0), P, Parallel);
      Check (not Parallel, "diagonals intersect");
      Check_Point (P, (2.0, 2.0), 1.0E-14, "diagonal intersection");
      Intersect ((0.0, 4.0, -Pi / 4.0), (1.0, 1.0, Pi / 4.0), P, Parallel);
      Check_Point (P, (2.0, 2.0), 1.0E-14, "argument order irrelevant");

      Intersect ((-5.0, 7.0, 2.0), (10.0, -3.0, 2.0 - 1.1), P, Parallel);
      Check (not Parallel, "general lines intersect");
      Check_Near (Distance (P, Line_2D'(-5.0, 7.0, 2.0)), 0.0, 1.0E-12,
                  "general intersection lies on line 1");
      Check_Near (Distance (P, Line_2D'(10.0, -3.0, 0.9)), 0.0, 1.0E-12,
                  "general intersection lies on line 2");

      Intersect (A, (5.0, 1.0, 0.3), P, Parallel);
      Check (Parallel, "parallel lines");
      Check_Point (P, (0.0, 0.0), 0.0, "parallel lines give (0, 0)");
      Intersect (A, (5.0, 1.0, 0.3 + Pi), P, Parallel);
      Check (Parallel, "anti-parallel lines are parallel");
      Intersect (A, A, P, Parallel);
      Check (Parallel, "coincident lines are parallel");
      Intersect (A, (5.0, 1.0, 0.3 - 2.0 * Pi), P, Parallel);
      Check (Parallel, "rotations a full turn apart are parallel");
      Intersect ((0.0, 0.0, 0.0), (0.0, 1.0, 1.0E-13), P, Parallel);
      Check (Parallel, "within the 1E-12 tolerance counts as parallel");

      Intersect ((0.0, 0.0, 0.0), (0.0, 1.0, 1.0E-9), P, Parallel);
      Check (not Parallel, "1E-9 apart is not parallel");
      Check_Near (P.Y, 0.0, 1.0E-9, "nearly parallel intersection Y");
      Check_Near (P.X / (-1.0 / Tan (1.0E-9)), 1.0, 1.0E-6,
                  "nearly parallel intersection X (relative)");
   end Test_Line_Line;

   procedure Test_Line_Circle is
      P1, P2 : Point_2D;
      Count  : Natural;
      C      : constant Circle_2D := (0.0, 0.0, 5.0);

      procedure Negative_Radius is
      begin
         Intersect (Line_2D'(0.0, 0.0, 0.0), Circle_2D'(0.0, 0.0, -1.0),
                    P1, P2, Count);
         Fail ("negative radius accepted, count" & Count'Image);
      end Negative_Radius;
      procedure Expect_Negative is new Expect_Bad_Parameter
        (Negative_Radius);
   begin
      Section ("line-circle intersection");
      Intersect (Line_2D'(-10.0, 3.0, 0.0), C, P1, P2, Count);
      Check (Count = 2, "secant: two points");
      Check_Point (P1, (-4.0, 3.0), 1.0E-14, "secant first point");
      Check_Point (P2, (4.0, 3.0), 1.0E-14, "secant second point");

      Intersect (Line_2D'(10.0, 3.0, Pi), C, P1, P2, Count);
      Check (Count = 2, "reversed secant: two points");
      Check_Point (P1, (4.0, 3.0), 1.0E-14,
                   "reversed direction: first point along the line");
      Check_Point (P2, (-4.0, 3.0), 1.0E-14, "reversed second point");

      Intersect (Line_2D'(0.0, 0.0, Pi / 2.0), C, P1, P2, Count);
      Check (Count = 2, "line through the centre");
      Check_Point (P1, (0.0, -5.0), 1.0E-14, "through centre first point");
      Check_Point (P2, (0.0, 5.0), 1.0E-14, "through centre second point");

      Intersect (Line_2D'(2.0, -3.0, Pi / 4.0), (2.0, -3.0, Sqrt (2.0)),
                 P1, P2, Count);
      Check (Count = 2, "oblique line through the centre");
      Check_Point (P1, (1.0, -4.0), 1.0E-14, "oblique first point");
      Check_Point (P2, (3.0, -2.0), 1.0E-14, "oblique second point");

      Intersect (Line_2D'(-3.0, 5.0, 0.0), C, P1, P2, Count);
      Check (Count = 1, "tangent line: one point");
      Check_Point (P1, (0.0, 5.0), 1.0E-14, "tangent point");
      Check_Point (P2, P1, 0.0, "tangent: both points equal");

      Intersect (Line_2D'(-3.0, 5.0 + 1.0E-12, 0.0), C, P1, P2, Count);
      Check (Count = 1, "tangent within tolerance");
      Intersect (Line_2D'(-3.0, 5.0 - 1.0E-12, 0.0), C, P1, P2, Count);
      Check (Count = 1, "tangent within tolerance from inside");

      Intersect (Line_2D'(-3.0, 5.0 + 1.0E-6, 0.0), C, P1, P2, Count);
      Check (Count = 0, "just outside the tolerance misses");
      Check_Point (P1, (0.0, 0.0), 0.0, "miss: first point (0, 0)");
      Check_Point (P2, (0.0, 0.0), 0.0, "miss: second point (0, 0)");
      Intersect (Line_2D'(-3.0, 5.0 - 1.0E-6, 0.0), C, P1, P2, Count);
      Check (Count = 2, "just inside the tolerance gives two points");
      Check (P1.X < P2.X, "close points keep their order");

      Intersect (Line_2D'(0.0, -7.0, 0.2), C, P1, P2, Count);
      Check (Count = 0, "far line misses");

      Intersect (Line_2D'(1.0, 1.0, 0.7), (1.0, 1.0, 0.0), P1, P2, Count);
      Check (Count = 1, "zero radius on the line: one point");
      Check_Point (P1, (1.0, 1.0), 1.0E-15, "zero radius point");
      Intersect (Line_2D'(1.0, 2.0, 0.0), (1.0, 1.0, 0.0), P1, P2, Count);
      Check (Count = 0, "zero radius off the line: none");

      Expect_Negative ("negative radius raises Ks_Bad_Parameter_Exception");
   end Test_Line_Circle;

   procedure Test_Circle_Circle is
      P1, P2 : Point_2D;
      Count  : Natural;

      procedure Negative_Radius is
      begin
         Intersect (Circle_2D'(0.0, 0.0, 1.0), Circle_2D'(1.0, 0.0, -1.0),
                    P1, P2, Count);
         Fail ("negative radius accepted, count" & Count'Image);
      end Negative_Radius;
      procedure Expect_Negative is new Expect_Bad_Parameter
        (Negative_Radius);
   begin
      Section ("circle-circle intersection");
      Intersect (Circle_2D'(0.0, 0.0, 5.0), (8.0, 0.0, 5.0), P1, P2, Count);
      Check (Count = 2, "two points");
      Check_Point (P1, (4.0, 3.0), 1.0E-14,
                   "first point on the positive side of centre line");
      Check_Point (P2, (4.0, -3.0), 1.0E-14, "second point");
      Check (Signed_Distance (P1, Line_2D'(0.0, 0.0, 0.0)) > 0.0,
             "first point has positive signed distance");

      Intersect (Circle_2D'(8.0, 0.0, 5.0), (0.0, 0.0, 5.0), P1, P2, Count);
      Check (Count = 2, "swapped: two points");
      Check_Point (P1, (4.0, -3.0), 1.0E-14, "swapping swaps the points");
      Check_Point (P2, (4.0, 3.0), 1.0E-14, "swapped second point");

      --  Circles through (3, 4) and (5, 0) with different radii.
      Intersect (Circle_2D'(0.0, 0.0, 5.0), (6.0, 3.0, Sqrt (10.0)),
                 P1, P2, Count);
      Check (Count = 2, "general: two points");
      Check_Point (P1, (3.0, 4.0), 1.0E-13, "general first point");
      Check_Point (P2, (5.0, 0.0), 1.0E-13, "general second point");

      Intersect (Circle_2D'(0.0, 0.0, 3.0), (5.0, 0.0, 2.0), P1, P2, Count);
      Check (Count = 1, "external tangency");
      Check_Point (P1, (3.0, 0.0), 1.0E-14, "external tangent point");
      Check_Point (P2, P1, 0.0, "tangent: both points equal");
      Intersect (Circle_2D'(0.0, 0.0, 3.0), (5.0 + 1.0E-12, 0.0, 2.0),
                 P1, P2, Count);
      Check (Count = 1, "external tangency within tolerance");

      Intersect (Circle_2D'(0.0, 0.0, 5.0), (2.0, 0.0, 3.0), P1, P2, Count);
      Check (Count = 1, "internal tangency");
      Check_Point (P1, (5.0, 0.0), 1.0E-14, "internal tangent point");
      Intersect (Circle_2D'(2.0, 0.0, 3.0), (0.0, 0.0, 5.0), P1, P2, Count);
      Check (Count = 1, "internal tangency, small circle first");
      Check_Point (P1, (5.0, 0.0), 1.0E-14,
                   "internal tangent point, small circle first");

      Intersect (Circle_2D'(0.0, 0.0, 5.0), (3.0, 4.0, 0.0), P1, P2, Count);
      Check (Count = 1, "zero radius circle on the other circle");
      Check_Point (P1, (3.0, 4.0), 1.0E-14, "zero radius contact point");

      Intersect (Circle_2D'(0.0, 0.0, 1.0), (5.0, 0.0, 1.0), P1, P2, Count);
      Check (Count = 0, "separate circles");
      Check_Point (P1, (0.0, 0.0), 0.0, "none: first point (0, 0)");
      Check_Point (P2, (0.0, 0.0), 0.0, "none: second point (0, 0)");
      Intersect (Circle_2D'(0.0, 0.0, 5.0), (1.0, 0.0, 1.0), P1, P2, Count);
      Check (Count = 0, "one circle inside the other");
      Intersect (Circle_2D'(2.0, 3.0, 4.0), (2.0, 3.0, 4.0), P1, P2, Count);
      Check (Count = 0, "coincident circles");
      Intersect (Circle_2D'(2.0, 3.0, 4.0), (2.0, 3.0, 1.0), P1, P2, Count);
      Check (Count = 0, "concentric circles");

      Expect_Negative ("negative radius raises Ks_Bad_Parameter_Exception");
   end Test_Circle_Circle;

   ---------------------------------------------------------------------
   --  Line fitting
   ---------------------------------------------------------------------

   procedure Expect_Line_Failure (Points : Point_Array; Description : String);

   procedure Expect_Line_Failure (Points : Point_Array; Description : String)
   is
      procedure Action;
      procedure Action is
         Line : Line_2D;
         RMS  : Real;
      begin
         Fit_Line (Points, Line, RMS);
         Fail (Description & ": returned rotation"
               & Real'Image (Line.Rotation) & ", RMS" & Real'Image (RMS));
      end Action;
      procedure Run is new Expect_Bad_Parameter (Action);
   begin
      Run (Description);
   end Expect_Line_Failure;

   procedure Expect_Robust_Line_Failure
     (Points                : Point_Array;
      Num_To_Ignore         : Natural;
      Used_First, Used_Last : Integer;
      Description           : String);

   procedure Expect_Robust_Line_Failure
     (Points                : Point_Array;
      Num_To_Ignore         : Natural;
      Used_First, Used_Last : Integer;
      Description           : String)
   is
      procedure Action;
      procedure Action is
         Line : Line_2D;
         RMS  : Real;
         Used : Boolean_Array (Used_First .. Used_Last);
      begin
         Fit_Line (Points, Num_To_Ignore, Line, RMS, Used);
         Fail (Description & ": returned rotation"
               & Real'Image (Line.Rotation) & ", RMS" & Real'Image (RMS));
      end Action;
      procedure Run is new Expect_Bad_Parameter (Action);
   begin
      Run (Description);
   end Expect_Robust_Line_Failure;

   function RMS_About (Points : Point_Array; Line : Line_2D) return Real;
   --  RMS perpendicular distance of Points from Line, computed directly.

   function RMS_About (Points : Point_Array; Line : Line_2D) return Real is
      Sum : Real := 0.0;
   begin
      for P of Points loop
         Sum := Sum + Signed_Distance (P, Line) ** 2;
      end loop;
      return Sqrt (Sum / Real (Points'Length));
   end RMS_About;

   function Count_Used (Used : Boolean_Array) return Natural;

   function Count_Used (Used : Boolean_Array) return Natural is
      Count : Natural := 0;
   begin
      for U of Used loop
         if U then
            Count := Count + 1;
         end if;
      end loop;
      return Count;
   end Count_Used;

   procedure Test_Isotropic_Scatter is
      Line : Line_2D;
      RMS  : Real;

      procedure Polygon
        (Count : Positive; CX, CY, Radius, Phase : Real; Expected_RMS : Real)
      is
         Points : Point_Array (1 .. Count);
      begin
         for I in Points'Range loop
            Points (I) :=
              (X => CX + Radius * Cos (Phase + 2.0 * Pi * Real (I) / Real (Count)),
               Y => CY + Radius * Sin (Phase + 2.0 * Pi * Real (I) / Real (Count)));
         end loop;
         Fit_Line (Points, Line, RMS);
         Check (Line.Rotation = 0.0,
                "regular" & Count'Image & "-gon of radius" & Real'Image (Radius)
                & " at (" & Real'Image (CX) & "," & Real'Image (CY)
                & "): rotation 0 (got" & Real'Image (Line.Rotation) & ")");
         Check_Near (RMS, Expected_RMS, 1.0E-12,
                     "regular" & Count'Image & "-gon RMS");
      end Polygon;

      Third : constant Real := 1.0 / 3.0;
      Two_Thirds : constant Real := 2.0 / 3.0;
   begin
      Section ("Fit_Line isotropic scatter");
      --  Every direction fits these equally well; before the fix rounding
      --  noise in the moments chose the rotation (for example 0.49 for the
      --  triangle and 0.23 for the hexagon).
      for Count of Count_List'[3, 6, 8] loop
         Polygon (Count, 0.0, 0.0, 10.0, 0.3, 10.0 / Sqrt (2.0));
         Polygon (Count, 250.0, 250.0, 10.0, 0.3, 10.0 / Sqrt (2.0));
      end loop;
      --  A small scatter far from the origin: rounding of the coordinates
      --  makes the stored hexagon anisotropic at about 1E-13 relative.
      Polygon (6, 1000.0, -1000.0, 1.0, 0.3, 1.0 / Sqrt (2.0));

      --  Exactly isotropic as stored, yet the computed moments differ in
      --  the last bits (before: -0.23, Pi/2, or 0 depending on the order).
      Fit_Line ([(Third, Third), (Two_Thirds, Third), (Third, Two_Thirds),
                 (Two_Thirds, Two_Thirds)], Line, RMS);
      Check (Line.Rotation = 0.0, "square {1/3, 2/3}: rotation 0");
      Fit_Line ([(Third, Third), (Two_Thirds, Two_Thirds),
                 (Two_Thirds, Third), (Third, Two_Thirds)], Line, RMS);
      Check (Line.Rotation = 0.0,
             "square {1/3, 2/3}, other order: rotation 0");
      Fit_Line ([(Two_Thirds, Two_Thirds), (Third, Two_Thirds),
                 (Two_Thirds, Third), (Third, Third)], Line, RMS);
      Check (Line.Rotation = 0.0,
             "square {1/3, 2/3}, third order: rotation 0");
      Fit_Line ([(1.1, 2.2), (-1.1, 2.2), (1.1, -2.2), (-1.1, -2.2),
                 (2.2, 1.1), (-2.2, 1.1), (2.2, -1.1), (-2.2, -1.1)],
                Line, RMS);
      Check (Line.Rotation = 0.0,
             "8 points (+-1.1, +-2.2), (+-2.2, +-1.1): rotation 0 (was Pi/2)");
      Fit_Line ([(0.1, 0.3), (-0.3, 0.1), (-0.1, -0.3), (0.3, -0.1)],
                Line, RMS);
      Check (Line.Rotation = 0.0,
             "orbit of (0.1, 0.3) under quarter turns: rotation 0");

      --  The tolerance does not hide a real elongation: an ellipse whose
      --  axes differ by 1 part in 1E9, turned by 0.4.
      declare
         Points : Point_Array (0 .. 19);
         Major  : constant Real := 10.0 * (1.0 + 1.0E-9);
      begin
         for I in Points'Range loop
            declare
               T : constant Real := 2.0 * Pi * Real (I) / 20.0;
               U : constant Real := Major * Cos (T);
               V : constant Real := 10.0 * Sin (T);
            begin
               Points (I) := (X => U * Cos (0.4) - V * Sin (0.4),
                              Y => U * Sin (0.4) + V * Cos (0.4));
            end;
         end loop;
         Fit_Line (Points, Line, RMS);
         Check_Near (Line.Rotation, 0.4, 1.0E-6,
                     "ellipse elongated by 1E-9 keeps its direction");
      end;
   end Test_Isotropic_Scatter;

   procedure Test_Fit_Line_Exact is
      Line : Line_2D;
      RMS  : Real;
   begin
      Section ("Fit_Line exact data");
      declare
         Points : Point_Array (0 .. 9);
      begin
         for I in Points'Range loop
            Points (I) := (X => Real (I), Y => 2.5);
         end loop;
         Fit_Line (Points, Line, RMS);
         Check_Near (Line.Rotation, 0.0, 1.0E-15, "horizontal rotation");
         Check_Point ((Line.X, Line.Y), (4.5, 2.5), 1.0E-14,
                      "horizontal line passes through the centroid");
         Check_Near (RMS, 0.0, 1.0E-15, "horizontal RMS");

         for I in Points'Range loop
            Points (I) := (X => 5.0, Y => Real (I));
         end loop;
         Fit_Line (Points, Line, RMS);
         Check_Near (Line.Rotation, Pi / 2.0, 1.0E-15,
                     "vertical rotation is +Pi/2");
         Check_In_Line_Range (Line.Rotation, "vertical");
         Check_Point ((Line.X, Line.Y), (5.0, 4.5), 1.0E-14,
                      "vertical centroid");
         Check_Near (RMS, 0.0, 1.0E-15, "vertical RMS");

         for I in Points'Range loop
            Points (I) := (X => 5.0, Y => Real (9 - I));
         end loop;
         Fit_Line (Points, Line, RMS);
         Check_Near (Line.Rotation, Pi / 2.0, 1.0E-15,
                     "vertical, points in reverse order");
      end;

      --  Rotation normalisation: every direction maps into (-Pi/2, Pi/2].
      declare
         Rotations : constant array (Positive range <>) of Real :=
           [-1.4, -0.3, 0.0, 1.0E-3, 0.7, Pi / 2.0 - 0.01, Pi / 2.0 + 0.01,
            2.5, -2.5, Pi, -Pi, -Pi / 2.0 + 0.001, 3.0 * Pi / 2.0 - 0.2,
            7.0];
         Points    : Point_Array (0 .. 14);
         Expected  : Real;
         Truth_RMS : Real;
      begin
         for R of Rotations loop
            Make_Line_Points (120.25, -37.5, R, 1.5, 0.0, Points, Truth_RMS);
            Fit_Line (Points, Line, RMS);
            Expected := AMV.Misc.Norm_Angle_Pi (R);
            Check_Near (Line.Rotation, Expected, 1.0E-12,
                        "normalised rotation for" & Real'Image (R));
            Check_In_Line_Range (Line.Rotation,
                                 "rotation" & Real'Image (R));
            Check_Point ((Line.X, Line.Y), (120.25, -37.5), 1.0E-11,
                         "centroid for" & Real'Image (R));
            Check_Near (RMS, 0.0, 1.0E-12, "exact RMS for" & Real'Image (R));
         end loop;
      end;

      declare
         Two     : constant Point_Array := [(1.0, 1.0), (4.0, 5.0)];
         Two_Rev : constant Point_Array := [(4.0, 5.0), (1.0, 1.0)];
         Up      : constant Point_Array := [(0.0, 5.0), (0.0, 0.0)];
         Square  : constant Point_Array :=
           [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0)];
      begin
         Fit_Line (Two, Line, RMS);
         Check_Near (Line.Rotation, Arctan (4.0, 3.0), 1.0E-15,
                     "two points: rotation");
         Check_Point ((Line.X, Line.Y), (2.5, 3.0), 1.0E-15,
                      "two points: midpoint");
         Check_Near (RMS, 0.0, 1.0E-15, "two points: RMS");
         Fit_Line (Two_Rev, Line, RMS);
         Check_Near (Line.Rotation, Arctan (4.0, 3.0), 1.0E-15,
                     "two points reversed: same (undirected) rotation");
         Fit_Line (Up, Line, RMS);
         Check_Near (Line.Rotation, Pi / 2.0, 1.0E-15,
                     "two points one above the other: +Pi/2");

         Fit_Line (Square, Line, RMS);
         Check_Near (Line.Rotation, 0.0, 0.0,
                     "isotropic scatter gives rotation 0");
         Check_Point ((Line.X, Line.Y), (0.5, 0.5), 1.0E-15,
                      "isotropic centroid");
         Check_Near (RMS, 0.5, 1.0E-15, "isotropic RMS");
      end;

      declare
         Points    : Point_Array (5 .. 14);
         Truth_RMS : Real;
      begin
         Make_Line_Points (-3.0, 8.0, 0.4, 2.0, 0.0, Points, Truth_RMS);
         Fit_Line (Points, Line, RMS);
         Check_Near (Line.Rotation, 0.4, 1.0E-13,
                     "array not starting at 0: rotation");
         Check_Point ((Line.X, Line.Y), (-3.0, 8.0), 1.0E-13,
                      "array not starting at 0: centroid");
      end;

      declare
         Points : Point_Array (0 .. 20);
      begin
         for I in Points'Range loop
            Points (I) := (X => 1.0E6 + Real (I), Y => 2.0E6 + 0.5 * Real (I));
         end loop;
         Fit_Line (Points, Line, RMS);
         Check_Near (Line.Rotation, Arctan (0.5), 1.0E-12,
                     "large coordinates: rotation");
         Check_Point ((Line.X, Line.Y), (1.0E6 + 10.0, 2.0E6 + 5.0), 1.0E-9,
                      "large coordinates: centroid");
         Check_Near (RMS, 0.0, 1.0E-9, "large coordinates: RMS");
      end;
   end Test_Fit_Line_Exact;

   procedure Test_Fit_Line_Noisy is
      Rotations : constant array (Positive range <>) of Real :=
        [0.4, Pi / 2.0, Pi / 2.0 - 1.0E-3, -Pi / 2.0 + 1.0E-3, -1.2, 0.0];
      Points    : Point_Array (0 .. 40);
      Line      : Line_2D;
      RMS       : Real;
      Truth_RMS : Real;
   begin
      Section ("Fit_Line noisy data");
      for R of Rotations loop
         Make_Line_Points (50.0, 60.0, R, 0.75, 0.08, Points, Truth_RMS);
         Fit_Line (Points, Line, RMS);
         Check_Axis_Near (Line.Rotation, R, 1.0E-12,
                          "noisy rotation for" & Real'Image (R));
         Check_In_Line_Range (Line.Rotation,
                              "noisy rotation" & Real'Image (R));
         Check_Point ((Line.X, Line.Y), (50.0, 60.0), 1.0E-11,
                      "noisy centroid for" & Real'Image (R));
         Check (Truth_RMS > 0.02, "the noise is not negligible");
         Check_Near (RMS, Truth_RMS, 1.0E-13,
                     "noisy RMS for" & Real'Image (R));
         Check_Near (RMS, RMS_About (Points, Line), 1.0E-13,
                     "RMS_Error matches the perpendicular distances");

         --  The fit is a minimum: turning or shifting the line hurts.
         Check (RMS_About (Points, (Line.X, Line.Y, Line.Rotation + 1.0E-3))
                > RMS
                and then
                RMS_About (Points, (Line.X, Line.Y, Line.Rotation - 1.0E-3))
                > RMS,
                "turning the fitted line increases the RMS");
         Check (RMS_About (Points,
                           (Line.X - 1.0E-3 * Sin (Line.Rotation),
                            Line.Y + 1.0E-3 * Cos (Line.Rotation),
                            Line.Rotation)) > RMS,
                "shifting the fitted line increases the RMS");
      end loop;
   end Test_Fit_Line_Noisy;

   procedure Test_Fit_Line_Errors is
      Line : Line_2D;
      RMS  : Real;
      Empty : constant Point_Array (1 .. 0) := [others => (0.0, 0.0)];
   begin
      Section ("Fit_Line degenerate input");
      Expect_Line_Failure (Empty, "no points");
      Expect_Line_Failure ([0 => (1.0, 2.0)], "one point");
      Expect_Line_Failure ([(1.0, 2.0), (1.0, 2.0)], "two equal points");
      Expect_Line_Failure ([(0.1, 0.3), (0.1, 0.3), (0.1, 0.3), (0.1, 0.3),
                            (0.1, 0.3)], "five equal points");
      Expect_Line_Failure ([(1000.0, 1000.0), (1000.0 + 1.0E-10, 1000.0)],
                           "points equal to 1E-13 relative");
      Fit_Line ([(1000.0, 1000.0), (1000.0 + 1.0E-6, 1000.0)], Line, RMS);
      Check_Near (Line.Rotation, 0.0, 1.0E-9,
                  "points 1E-6 apart at 1000 are still distinct");
   end Test_Fit_Line_Errors;

   procedure Test_Fit_Line_Robust is
      Outlier_Index  : constant array (1 .. 3) of Natural := [2, 9, 17];
      Outlier_T      : constant array (1 .. 3) of Real := [-5.0, 1.0, 6.0];
      Outlier_Offset : constant array (1 .. 3) of Real := [6.0, -9.0, 12.0];
      Rot            : constant Real := 0.3;

      procedure Build
        (Noise     : Real;
         First     : Natural;
         All_Pts   : out Point_Array;
         Is_Inlier : out Boolean_Array;
         Truth_RMS : out Real);
      --  20 inliers on the line through (10, 20) with rotation Rot (with
      --  orthogonalised noise), and 3 outliers at the indices above
      --  (relative to First).

      procedure Build
        (Noise     : Real;
         First     : Natural;
         All_Pts   : out Point_Array;
         Is_Inlier : out Boolean_Array;
         Truth_RMS : out Real)
      is
         Inliers : Point_Array (0 .. 19);
         Next    : Natural := 0;
      begin
         Make_Line_Points (10.0, 20.0, Rot, 1.0, Noise, Inliers, Truth_RMS);
         Is_Inlier := [others => True];
         for K in Outlier_Index'Range loop
            Is_Inlier (First + Outlier_Index (K)) := False;
         end loop;
         for I in All_Pts'Range loop
            if Is_Inlier (I) then
               All_Pts (I) := Inliers (Next);
               Next := Next + 1;
            end if;
         end loop;
         for K in Outlier_Index'Range loop
            All_Pts (First + Outlier_Index (K)) :=
              (X => 10.0 + Outlier_T (K) * Cos (Rot)
                    - Outlier_Offset (K) * Sin (Rot),
               Y => 20.0 + Outlier_T (K) * Sin (Rot)
                    + Outlier_Offset (K) * Cos (Rot));
         end loop;
      end Build;

      Line, Plain : Line_2D;
      RMS, Plain_RMS, Truth_RMS : Real;
   begin
      Section ("Fit_Line robust");
      declare
         Pts       : Point_Array (0 .. 22);
         Is_Inlier : Boolean_Array (0 .. 22);
         Used      : Boolean_Array (0 .. 22);
      begin
         for Noise of Real_List'[0.0, 0.05] loop
            Build (Noise, 0, Pts, Is_Inlier, Truth_RMS);
            Fit_Line (Pts, 3, Line, RMS, Used);
            Check (Used = Is_Inlier,
                   "exactly the outliers are unused, noise"
                   & Real'Image (Noise));
            Check_Near (Line.Rotation, Rot, 1.0E-12,
                        "robust rotation, noise" & Real'Image (Noise));
            Check_Point ((Line.X, Line.Y), (10.0, 20.0), 1.0E-11,
                         "robust centroid, noise" & Real'Image (Noise));
            Check_Near (RMS, Truth_RMS, 1.0E-12,
                        "robust RMS over the inliers, noise"
                        & Real'Image (Noise));
         end loop;

         --  With the outliers included the plain fit is visibly wrong.
         Fit_Line (Pts, Plain, Plain_RMS);
         Check (Plain_RMS > 1.0, "plain fit is spoiled by the outliers");

         Fit_Line (Pts, 0, Line, RMS, Used);
         Check (Count_Used (Used) = Used'Length,
                "Num_To_Ignore = 0 uses every point");
         Check (Line = Plain and then RMS = Plain_RMS,
                "Num_To_Ignore = 0 equals the plain fit");

         Fit_Line (Pts, 1, Line, RMS, Used);
         Check (Count_Used (Used) = 22, "Num_To_Ignore = 1 drops one point");
         Check ((for some K in Outlier_Index'Range =>
                   not Used (Outlier_Index (K))),
                "the dropped point is an outlier");

         Fit_Line (Pts, 21, Line, RMS, Used);
         Check (Count_Used (Used) = 2, "N - 2 ignored leaves two points");
         Check_Near (RMS, 0.0, 1.0E-12, "two remaining points fit exactly");

         Expect_Robust_Line_Failure (Pts, 22, 0, 22,
                                     "ignoring N - 1 points");
         Expect_Robust_Line_Failure (Pts, 1, 1, 23,
                                     "Used shifted by one index");
         Expect_Robust_Line_Failure (Pts, 1, 0, 21, "Used too short");
         Expect_Robust_Line_Failure (Pts, 0, 0, 23, "Used too long");
      end;

      declare
         Pts       : Point_Array (100 .. 122);
         Is_Inlier : Boolean_Array (100 .. 122);
         Used      : Boolean_Array (100 .. 122);
      begin
         Build (0.02, 100, Pts, Is_Inlier, Truth_RMS);
         Fit_Line (Pts, 3, Line, RMS, Used);
         Check (Used = Is_Inlier, "index range 100 .. 122: outliers found");
         Check_Near (Line.Rotation, Rot, 1.0E-12,
                     "index range 100 .. 122: rotation");
         Check_Near (RMS, Truth_RMS, 1.0E-12,
                     "index range 100 .. 122: RMS");
      end;

      declare
         Square : constant Point_Array :=
           [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0)];
         Used   : Boolean_Array (Square'Range);
      begin
         Fit_Line (Square, 1, Line, RMS, Used);
         Check (Used = [False, True, True, True],
                "equal residuals: the lowest index is dropped");
      end;

      --  One outlier whose offset across the line exceeds the spread of
      --  the good points along it: it pulls the fit of all points so far
      --  round that good points get the largest residuals. Before the fix
      --  the robust fit dropped good points (8, then 7, then 6) and kept
      --  the outlier, with rotation 0.89.
      declare
         Pts  : Point_Array (0 .. 9);
         Used : Boolean_Array (0 .. 9);
      begin
         for I in 0 .. 8 loop
            Pts (I) := (X => Real (I), Y => 0.0);
         end loop;
         Pts (9) := (X => 9.0, Y => 10.0);
         Fit_Line (Pts, 1, Line, RMS, Used);
         Check (Used = [0 .. 8 => True, 9 => False],
                "end outlier 10 off a line of 9 points is dropped");
         Check_Near (Line.Rotation, 0.0, 1.0E-15, "end outlier: rotation");
         Check_Near (RMS, 0.0, 1.0E-15, "end outlier: RMS");
         for Ignore in 2 .. 3 loop
            Fit_Line (Pts, Ignore, Line, RMS, Used);
            Check (not Used (9) and then Count_Used (Used) = 10 - Ignore,
                   "end outlier dropped with Num_To_Ignore" & Ignore'Image);
            Check_Near (Line.Rotation, 0.0, 1.0E-15,
                        "end outlier, Num_To_Ignore" & Ignore'Image
                        & ": rotation");
         end loop;

         --  The same in the middle, 30 off (before: index 0 dropped,
         --  rotation -1.53).
         Pts (9) := (X => 9.0, Y => 0.0);
         Pts (4) := (X => 4.0, Y => 30.0);
         Fit_Line (Pts, 1, Line, RMS, Used);
         Check (Used = [0 .. 3 => True, 4 => False, 5 .. 9 => True],
                "middle outlier 30 off is dropped");
         Check_Near (Line.Rotation, 0.0, 1.0E-15, "middle outlier: rotation");
      end;

      --  A far leverage point (before: kept for Num_To_Ignore 1 to 3,
      --  rotation 0.79).
      declare
         Pts  : Point_Array (0 .. 10);
         Used : Boolean_Array (0 .. 10);
      begin
         for I in 0 .. 9 loop
            Pts (I) := (X => Real (I), Y => 0.0);
         end loop;
         Pts (10) := (X => 1000.0, Y => 1000.0);
         for Ignore in 1 .. 3 loop
            Fit_Line (Pts, Ignore, Line, RMS, Used);
            Check (not Used (10) and then Count_Used (Used) = 11 - Ignore,
                   "far point (1000, 1000) dropped with Num_To_Ignore"
                   & Ignore'Image);
            Check_Near (Line.Rotation, 0.0, 1.0E-15,
                        "far point, Num_To_Ignore" & Ignore'Image
                        & ": rotation");
            Check_Near (RMS, 0.0, 1.0E-12,
                        "far point, Num_To_Ignore" & Ignore'Image & ": RMS");
         end loop;
      end;

      --  Removing the odd point out would leave four coinciding points, so
      --  a point of the cluster goes instead (before: the odd point went
      --  and the final fit raised "the points coincide").
      declare
         Pts  : constant Point_Array :=
           [(5.0, 5.0), (0.0, 0.0), (0.0, 0.0), (0.0, 0.0), (0.0, 0.0)];
         Used : Boolean_Array (Pts'Range);
      begin
         Fit_Line (Pts, 1, Line, RMS, Used);
         Check (Used = [True, False, True, True, True],
                "a removal that leaves coinciding points is not chosen");
         Check_Near (Line.Rotation, Pi / 4.0, 1.0E-15,
                     "cluster and odd point: rotation");
      end;

      --  Exactly symmetric points: every removal is equally good, and the
      --  lowest index goes.
      declare
         Pts  : constant Point_Array :=
           [(1.1, 2.2), (-1.1, 2.2), (1.1, -2.2), (-1.1, -2.2),
            (2.2, 1.1), (-2.2, 1.1), (2.2, -1.1), (-2.2, -1.1)];
         Used : Boolean_Array (Pts'Range);
      begin
         Fit_Line (Pts, 1, Line, RMS, Used);
         Check (Used = [False, True, True, True, True, True, True, True],
                "symmetric 8 points: the lowest index is dropped");
      end;

      Expect_Robust_Line_Failure ([0 => (1.0, 1.0)], 0, 0, 0,
                                  "robust fit of one point");
      Expect_Robust_Line_Failure ([(1.0, 1.0), (1.0, 1.0), (1.0, 1.0)], 0,
                                  0, 2, "robust fit of equal points");
   end Test_Fit_Line_Robust;

   ---------------------------------------------------------------------
   --  Circle fitting
   ---------------------------------------------------------------------

   procedure Expect_Circle_Failure
     (Points : Point_Array; Description : String);

   procedure Expect_Circle_Failure (Points : Point_Array; Description : String)
   is
      procedure Action;
      procedure Action is
         Circle : Circle_2D;
         RMS    : Real;
      begin
         Fit_Circle (Points, Circle, RMS);
         Fail (Description & ": returned radius"
               & Real'Image (Circle.Radius) & ", RMS" & Real'Image (RMS));
      end Action;
      procedure Run is new Expect_Bad_Parameter (Action);
   begin
      Run (Description);
   end Expect_Circle_Failure;

   procedure Expect_Robust_Circle_Failure
     (Points                : Point_Array;
      Num_To_Ignore         : Natural;
      Used_First, Used_Last : Integer;
      Description           : String);

   procedure Expect_Robust_Circle_Failure
     (Points                : Point_Array;
      Num_To_Ignore         : Natural;
      Used_First, Used_Last : Integer;
      Description           : String)
   is
      procedure Action;
      procedure Action is
         Circle : Circle_2D;
         RMS    : Real;
         Used   : Boolean_Array (Used_First .. Used_Last);
      begin
         Fit_Circle (Points, Num_To_Ignore, Circle, RMS, Used);
         Fail (Description & ": returned radius"
               & Real'Image (Circle.Radius) & ", RMS" & Real'Image (RMS));
      end Action;
      procedure Run is new Expect_Bad_Parameter (Action);
   begin
      Run (Description);
   end Expect_Robust_Circle_Failure;

   function Radial_RMS (Points : Point_Array; Circle : Circle_2D) return Real;
   --  RMS of |P - centre| - radius, computed directly.

   function Radial_RMS (Points : Point_Array; Circle : Circle_2D) return Real
   is
      Sum : Real := 0.0;
   begin
      for P of Points loop
         Sum := Sum + Distance (P, Circle) ** 2;
      end loop;
      return Sqrt (Sum / Real (Points'Length));
   end Radial_RMS;

   procedure Check_Circle
     (Got, Expected : Circle_2D; Tolerance : Real; Description : String);

   procedure Check_Circle
     (Got, Expected : Circle_2D; Tolerance : Real; Description : String) is
   begin
      Check_Near (Got.Center_X, Expected.Center_X, Tolerance,
                  Description & " centre X");
      Check_Near (Got.Center_Y, Expected.Center_Y, Tolerance,
                  Description & " centre Y");
      Check_Near (Got.Radius, Expected.Radius, Tolerance,
                  Description & " radius");
   end Check_Circle;

   procedure Test_Fit_Circle_Exact is
      Circle    : Circle_2D;
      RMS       : Real;
      Truth_RMS : Real;
   begin
      Section ("Fit_Circle exact data");
      declare
         Points : Point_Array (0 .. 11);
      begin
         Make_Circle_Points (120.5, -40.25, 33.0, 0.1, 2.0 * Pi * 11.0 / 12.0,
                             0.0, Points, Truth_RMS);
         Fit_Circle (Points, Circle, RMS);
         Check_Circle (Circle, (120.5, -40.25, 33.0), 1.0E-11,
                       "full circle");
         Check_Near (RMS, 0.0, 1.0E-11, "full circle RMS");
      end;

      Fit_Circle ([(0.0, 0.0), (4.0, 0.0), (0.0, 3.0)], Circle, RMS);
      Check_Circle (Circle, (2.0, 1.5, 2.5), 1.0E-13,
                    "three points: circumcircle");
      Check_Near (RMS, 0.0, 1.0E-13, "three points RMS");

      declare
         Points : Point_Array (0 .. 24);
         Degrees : constant Real_List :=
           [180.0, 90.0, 30.0, 10.0, 3.0, 1.0, 0.5];
      begin
         for Extent of Degrees loop
            Make_Circle_Points (300.0, 200.0, 100.0, 0.7,
                                AMV.Misc.Deg_To_Rad (Extent), 0.0,
                                Points, Truth_RMS);
            Fit_Circle (Points, Circle, RMS);
            Check_Circle (Circle, (300.0, 200.0, 100.0), 1.0E-8,
                          "exact arc of" & Real'Image (Extent) & " deg");
            Check_Near (RMS, 0.0, 1.0E-10,
                        "exact arc RMS," & Real'Image (Extent) & " deg");
         end loop;
      end;

      declare
         Points : Point_Array (7 .. 26);
      begin
         Make_Circle_Points (1000.0, 1000.0, 0.5, -2.0, 2.0 * Pi * 19.0 / 20.0,
                             0.0, Points, Truth_RMS);
         Fit_Circle (Points, Circle, RMS);
         Check_Circle (Circle, (1000.0, 1000.0, 0.5), 1.0E-11,
                       "small circle far from the origin, index from 7");
      end;
   end Test_Fit_Circle_Exact;

   procedure Test_Fit_Circle_Noisy is
      Circle    : Circle_2D;
      RMS       : Real;
      Truth_RMS : Real;

      procedure Try
        (N                         : Positive;
         CX, CY, R, Start, Extent : Real;
         Noise                     : Real;
         Description               : String);

      procedure Try
        (N                         : Positive;
         CX, CY, R, Start, Extent : Real;
         Noise                     : Real;
         Description               : String)
      is
         Points : Point_Array (0 .. N - 1);
      begin
         Make_Circle_Points (CX, CY, R, Start, Extent, Noise, Points,
                             Truth_RMS);
         Fit_Circle (Points, Circle, RMS);
         Check_Circle (Circle, (CX, CY, R), 1.0E-8, Description);
         Check (Truth_RMS > Noise / 10.0, Description & ": real noise");
         Check_Near (RMS, Truth_RMS, 1.0E-10, Description & " RMS");
         Check_Near (RMS, Radial_RMS (Points, Circle), 1.0E-12,
                     Description & ": RMS_Error matches the residuals");
      end Try;
   begin
      Section ("Fit_Circle noisy data");
      Try (60, 10.0, -20.0, 40.0, 0.0, 2.0 * Pi * 59.0 / 60.0, 0.1,
           "noisy full circle");
      Try (40, -5.0, 7.0, 25.0, 1.0, Pi, 0.05, "noisy semicircle");
      Try (30, 200.0, 150.0, 80.0, -0.4, AMV.Misc.Deg_To_Rad (30.0), 0.02,
           "noisy 30 deg arc");
      Try (30, 200.0, 150.0, 80.0, 2.9, AMV.Misc.Deg_To_Rad (15.0), 0.005,
           "noisy 15 deg arc");
      Try (8, 0.0, 0.0, 10.0, 0.0, 2.0 * Pi * 7.0 / 8.0, 0.5,
           "few points, large noise");
   end Test_Fit_Circle_Noisy;

   procedure Test_Fit_Circle_Errors is
      Empty     : constant Point_Array (1 .. 0) := [others => (0.0, 0.0)];
      Collinear : Point_Array (0 .. 9);
   begin
      Section ("Fit_Circle degenerate input");
      Expect_Circle_Failure (Empty, "no points");
      Expect_Circle_Failure ([0 => (1.0, 1.0)], "one point");
      Expect_Circle_Failure ([(1.0, 1.0), (2.0, 5.0)], "two points");
      Expect_Circle_Failure ([(0.0, 0.0), (1.0, 1.0), (2.0, 2.0)],
                             "three collinear points");
      for I in Collinear'Range loop
         Collinear (I) := (X => 0.1 * Real (I), Y => 0.3 * Real (I) + 2.0);
      end loop;
      Expect_Circle_Failure (Collinear, "ten collinear points (rounded)");
      for I in Collinear'Range loop
         Collinear (I) := (X => -4.0, Y => Real (I) * 1.5);
      end loop;
      Expect_Circle_Failure (Collinear, "vertical collinear points");
      Expect_Circle_Failure ([(3.0, 4.0), (3.0, 4.0), (3.0, 4.0),
                              (3.0, 4.0)], "equal points");
      Expect_Circle_Failure ([(0.0, 0.0), (0.0, 0.0), (1.0, 0.0)],
                             "a repeated point makes three collinear");

      --  Scatter across the line of about 1E-9 of the scatter along it is
      --  below what a circle fit can resolve.
      for I in Collinear'Range loop
         Collinear (I) := (X => Real (I), Y => 3.0 + 1.0E-9 * Uniform);
      end loop;
      Expect_Circle_Failure (Collinear, "collinear up to 1E-9 noise");

      --  Symmetric about both axes: the centroid is a saddle point of the
      --  cost (zero gradient), and the cost keeps falling as the centre
      --  moves out along the y axis, so the best "circle" is the line y = 0.
      Expect_Circle_Failure ([(-1.0, 0.0), (0.0, 0.01), (1.0, 0.0),
                              (0.0, -0.01)],
                             "saddle with the best circle at infinity");
   end Test_Fit_Circle_Errors;

   function Best_RMS (Points : Point_Array; CX, CY : Real) return Real;
   --  RMS radial residual for the centre (CX, CY) with the optimal radius
   --  (the mean distance).

   function Best_RMS (Points : Point_Array; CX, CY : Real) return Real is
      Mean : Real := 0.0;
   begin
      for P of Points loop
         Mean := Mean + Distance (P, Point_2D'(CX, CY));
      end loop;
      Mean := Mean / Real (Points'Length);
      return Radial_RMS (Points, (CX, CY, Mean));
   end Best_RMS;

   procedure Test_Fit_Circle_Stationary is
      --  Four points on a circle of radius 10 plus one at its centre. The
      --  centre itself has zero gradient (by symmetry, with the distance to
      --  the middle point at a kink) but is no minimum.
      Points : constant Point_Array :=
        [(10.0, 0.0), (0.0, 10.0), (-10.0, 0.0), (0.0, -10.0), (0.0, 0.0)];
      Circle : Circle_2D;
      RMS    : Real;
      H      : constant Real := 1.0E-4;
   begin
      Section ("Fit_Circle stationary points");
      Fit_Circle (Points, Circle, RMS);
      Check (RMS < 4.0 - 0.1,
             "moves off the symmetric stationary point (RMS 4)");
      Check_Near (RMS, Radial_RMS (Points, Circle), 1.0E-12,
                  "RMS_Error matches the residuals");
      Check_Near (Best_RMS (Points, Circle.Center_X, Circle.Center_Y), RMS,
                  1.0E-12, "the radius is the mean distance");
      Check (Best_RMS (Points, Circle.Center_X + H, Circle.Center_Y) >= RMS
             and then
             Best_RMS (Points, Circle.Center_X - H, Circle.Center_Y) >= RMS
             and then
             Best_RMS (Points, Circle.Center_X, Circle.Center_Y + H) >= RMS
             and then
             Best_RMS (Points, Circle.Center_X, Circle.Center_Y - H) >= RMS,
             "the result is a local minimum");
   end Test_Fit_Circle_Stationary;

   procedure Test_Fit_Circle_Robust is
      Outlier_Index  : constant array (1 .. 3) of Natural := [4, 13, 27];
      Outlier_Angle  : constant array (1 .. 3) of Real := [0.3, 2.0, 4.0];
      Outlier_Offset : constant array (1 .. 3) of Real := [6.0, -9.0, 15.0];
      Truth          : constant Circle_2D := (5.0, 5.0, 50.0);

      procedure Build
        (Noise     : Real;
         All_Pts   : out Point_Array;
         Is_Inlier : out Boolean_Array;
         Truth_RMS : out Real);
      --  30 inliers around Truth (orthogonalised noise) and 3 outliers.

      procedure Build
        (Noise     : Real;
         All_Pts   : out Point_Array;
         Is_Inlier : out Boolean_Array;
         Truth_RMS : out Real)
      is
         Inliers : Point_Array (0 .. 29);
         Next    : Natural := 0;
      begin
         Make_Circle_Points (Truth.Center_X, Truth.Center_Y, Truth.Radius,
                             0.0, 2.0 * Pi * 29.0 / 30.0, Noise, Inliers,
                             Truth_RMS);
         Is_Inlier := [others => True];
         for K in Outlier_Index'Range loop
            Is_Inlier (All_Pts'First + Outlier_Index (K)) := False;
         end loop;
         for I in All_Pts'Range loop
            if Is_Inlier (I) then
               All_Pts (I) := Inliers (Next);
               Next := Next + 1;
            end if;
         end loop;
         for K in Outlier_Index'Range loop
            All_Pts (All_Pts'First + Outlier_Index (K)) :=
              (X => Truth.Center_X
                    + (Truth.Radius + Outlier_Offset (K))
                      * Cos (Outlier_Angle (K)),
               Y => Truth.Center_Y
                    + (Truth.Radius + Outlier_Offset (K))
                      * Sin (Outlier_Angle (K)));
         end loop;
      end Build;

      Pts                        : Point_Array (0 .. 32);
      Is_Inlier, Used            : Boolean_Array (0 .. 32);
      Circle, Plain              : Circle_2D;
      RMS, Plain_RMS, Truth_RMS  : Real;
   begin
      Section ("Fit_Circle robust");
      for Noise of Real_List'[0.0, 0.03] loop
         Build (Noise, Pts, Is_Inlier, Truth_RMS);
         Fit_Circle (Pts, 3, Circle, RMS, Used);
         Check (Used = Is_Inlier,
                "exactly the outliers are unused, noise"
                & Real'Image (Noise));
         Check_Circle (Circle, Truth, 1.0E-9,
                       "robust circle, noise" & Real'Image (Noise));
         Check_Near (RMS, Truth_RMS, 1.0E-10,
                     "robust RMS over the inliers, noise"
                     & Real'Image (Noise));
      end loop;

      Fit_Circle (Pts, Plain, Plain_RMS);
      Check (Plain_RMS > 1.0, "plain fit is spoiled by the outliers");
      Fit_Circle (Pts, 0, Circle, RMS, Used);
      Check (Count_Used (Used) = Used'Length,
             "Num_To_Ignore = 0 uses every point");
      Check (Circle = Plain and then RMS = Plain_RMS,
             "Num_To_Ignore = 0 equals the plain fit");

      Fit_Circle (Pts, 30, Circle, RMS, Used);
      Check (Count_Used (Used) = 3, "N - 3 ignored leaves three points");
      Check_Near (RMS, 0.0, 1.0E-9, "three remaining points fit exactly");

      Expect_Robust_Circle_Failure (Pts, 31, 0, 32, "ignoring N - 2 points");
      Expect_Robust_Circle_Failure (Pts, 1, 1, 33,
                                    "Used shifted by one index");
      Expect_Robust_Circle_Failure (Pts, 1, 0, 31, "Used too short");
      Expect_Robust_Circle_Failure ([(0.0, 0.0), (1.0, 0.0)], 0, 0, 1,
                                    "robust fit of two points");
      Expect_Robust_Circle_Failure
        ([(0.0, 0.0), (1.0, 1.0), (2.0, 2.0), (3.0, 3.0)], 1, 0, 3,
         "robust fit of collinear points");

      --  A short arc plus one far point: the circle through all of them is
      --  dominated by the far point (centre near (-486, -124), radius 511),
      --  so before the fix good points of the arc were dropped instead.
      declare
         Arc      : Point_Array (0 .. 12);
         Arc_Used : Boolean_Array (0 .. 12);
         Angle    : Real;
      begin
         for I in 0 .. 11 loop
            Angle := AMV.Misc.Deg_To_Rad (33.0 * Real (I) / 11.0);
            Arc (I) := (X => 10.0 * Cos (Angle), Y => 10.0 * Sin (Angle));
         end loop;
         Arc (12) := (X => -200.0, Y => 300.0);
         Fit_Circle (Arc, 1, Circle, RMS, Arc_Used);
         Check (Arc_Used = [0 .. 11 => True, 12 => False],
                "33 deg arc plus a far point: the far point is dropped");
         Check_Circle (Circle, (0.0, 0.0, 10.0), 1.0E-9,
                       "33 deg arc plus a far point");
         Fit_Circle (Arc, 2, Circle, RMS, Arc_Used);
         Check (not Arc_Used (12) and then Count_Used (Arc_Used) = 11,
                "33 deg arc plus a far point, Num_To_Ignore 2");
         Check_Circle (Circle, (0.0, 0.0, 10.0), 1.0E-9,
                       "33 deg arc plus a far point, Num_To_Ignore 2");
      end;

      --  On a quarter circle the end points set the curvature: moving the
      --  last one out by just 1 (of radius 100) made the old method drop
      --  its neighbour.
      declare
         Quarter      : Point_Array (0 .. 7);
         Quarter_Used : Boolean_Array (0 .. 7);
         Angle        : Real;
      begin
         for I in Quarter'Range loop
            Angle := AMV.Misc.Deg_To_Rad (90.0 * Real (I) / 7.0);
            Quarter (I) := (X => (if I = 7 then 101.0 else 100.0) * Cos (Angle),
                            Y => (if I = 7 then 101.0 else 100.0) * Sin (Angle));
         end loop;
         Fit_Circle (Quarter, 1, Circle, RMS, Quarter_Used);
         Check (Quarter_Used = [0 .. 6 => True, 7 => False],
                "quarter circle, end point 1 out: that point is dropped");
         Check_Circle (Circle, (0.0, 0.0, 100.0), 1.0E-9,
                       "quarter circle with one end point 1 out");
      end;
   end Test_Fit_Circle_Robust;

   procedure Test_Fit_Circle_Large_Residuals is
      --  Short noisy arcs, where the residuals are large compared with the
      --  curvature. Gauss-Newton alone then converges linearly at a rate
      --  near 1 and stopped on the iteration cap far from the least squares
      --  circle; the Newton steps reach it.
      H : constant Real := 1.0E-4;

      procedure Check_Minimum
        (Points    : Point_Array;
         Expected  : Circle_2D;
         Tolerance : Real;
         Description : String)
      is
         Circle : Circle_2D;
         RMS    : Real;
      begin
         Fit_Circle (Points, Circle, RMS);
         Check_Circle (Circle, Expected, Tolerance, Description);
         Check_Near (RMS, Radial_RMS (Points, Circle), 1.0E-12,
                     Description & ": RMS_Error matches the residuals");
         Check (Best_RMS (Points, Circle.Center_X + H, Circle.Center_Y) >= RMS
                and then
                Best_RMS (Points, Circle.Center_X - H, Circle.Center_Y) >= RMS
                and then
                Best_RMS (Points, Circle.Center_X, Circle.Center_Y + H) >= RMS
                and then
                Best_RMS (Points, Circle.Center_X, Circle.Center_Y - H) >= RMS,
                Description & ": the result is a local minimum");
      end Check_Minimum;
   begin
      Section ("Fit_Circle large residuals");
      --  Before: centre (68.99, 27.90), radius 38.10, 1.99 from the
      --  minimum, after 100 iterations with steps still 7.7E-2.
      Check_Minimum
        ([(29.3419309329947424, 18.8352073981810300),
          (32.9905025431765893, 23.4313191669243288),
          (33.3703654750840499, 9.84787800169671179),
          (38.1203181692699360, 8.65560863765617761),
          (34.3553470541040369, 9.71960957424601091),
          (37.3204301203910092, 9.82322171823273038),
          (33.7149842191451015, 11.3130226981626265),
          (37.8273787868285325, 6.32485175203809291),
          (35.4764325266279030, 1.92662820184290107),
          (40.2006610899366876, 6.34004073555790004),
          (38.7038461809266607, 10.4461270924232004)],
         (70.8442933887, 28.6208067904, 40.0500184291), 1.0E-8,
         "11 points, noise 5% of the radius");
      --  Before: centre (11.30, -18.27), radius 23.24, RMS 7.37.
      Check_Minimum
        ([(-4.68776956915941767E+00, -3.45529746975853911E+01),
          (2.66134004767590220E+01, -3.48445895703542092E+01),
          (4.58805865004793887E+01, -2.56157616061336313E+01),
          (1.78404479344748594E+01, -3.42275520267027460E+01),
          (1.27169481291758100E+01, -4.58154153057674165E+01),
          (-1.43684873535443280E+01, -2.45016043023402474E+01),
          (2.19254266661545145E+01, -1.93212226463114334E+01),
          (3.82462539923582483E+01, -2.80484811576896149E+01),
          (-1.50526747547383266E+00, -2.47171973115541235E+01),
          (1.67198311659098238E+01, -3.48836468765996912E+01),
          (-7.26617884150632776E+00, -4.49518859320905833E+01)],
         (10.62934, 8.43806, 44.61813), 1.0E-4,
         "90 deg arc, noise 20% of the radius");
   end Test_Fit_Circle_Large_Residuals;

   procedure Test_Fit_Scale is
      --  The fits scale the offsets from the centroid by a power of two
      --  before forming moments, so scaled input gives scaled results.
      --  Before the fix the tiny cases raised "the points coincide" or
      --  "collinear" and the huge ones Constraint_Error.
      Line   : Line_2D;
      Circle : Circle_2D;
      RMS    : Real;
   begin
      Section ("Fit_Line and Fit_Circle at extreme scales");
      --  Since the kernel, coordinates are bounded by 1.0E150, so the large
      --  scales are 1E80 and 1E140 (1E160 and 1E300 before).
      for S of Real_List'[1.0E-170, 1.0E-110, 1.0E-300, 1.0E80, 1.0E140]
      loop
         Fit_Line ([(0.0, 0.0), (S, 0.5 * S), (2.0 * S, S)], Line, RMS);
         Check_Near (Line.Rotation, Arctan (0.5), 1.0E-15,
                     "line scaled by" & Real'Image (S) & ": rotation");
         Check_Point ((Line.X / S, Line.Y / S), (1.0, 0.5), 1.0E-15,
                      "line scaled by" & Real'Image (S) & ": centroid");
         Check_Near (RMS / S, 0.0, 1.0E-15,
                     "line scaled by" & Real'Image (S) & ": RMS");

         Fit_Circle ([(0.0, 0.0), (4.0 * S, 0.0), (0.0, 3.0 * S)],
                     Circle, RMS);
         Check_Circle ((Circle.Center_X / S, Circle.Center_Y / S,
                        Circle.Radius / S),
                       (2.0, 1.5, 2.5), 1.0E-13,
                       "circumcircle scaled by" & Real'Image (S));
         Check_Near (RMS / S, 0.0, 1.0E-13,
                     "circumcircle scaled by" & Real'Image (S) & ": RMS");

         --  Robust fits compare their candidates in scaled units too.
         declare
            Pts  : Point_Array (0 .. 9);
            Used : Boolean_Array (0 .. 9);
         begin
            for I in 0 .. 8 loop
               Pts (I) := (X => Real (I) * S, Y => 0.0);
            end loop;
            Pts (9) := (X => 9.0 * S, Y => 10.0 * S);
            Fit_Line (Pts, 1, Line, RMS, Used);
            Check (Used = [0 .. 8 => True, 9 => False],
                   "robust line scaled by" & Real'Image (S));
            for I in 0 .. 8 loop
               Pts (I) := (X => S * 10.0 * Cos (0.3 * Real (I)),
                           Y => S * 10.0 * Sin (0.3 * Real (I)));
            end loop;
            Pts (9) := (X => -200.0 * S, Y => 300.0 * S);
            Fit_Circle (Pts, 1, Circle, RMS, Used);
            Check (Used = [0 .. 8 => True, 9 => False],
                   "robust circle scaled by" & Real'Image (S));
            Check_Near (Circle.Radius / S, 10.0, 1.0E-12,
                        "robust circle scaled by" & Real'Image (S)
                        & ": radius");
         end;
      end loop;

      --  A spread far below the coordinates still counts as coinciding.
      Expect_Line_Failure ([(1.0E140, 1.0E140), (1.0E140, 1.0E140 * (1.0 + 1.0E-15))],
                           "points equal to 1E-15 relative at 1E140");
      Expect_Line_Failure ([(1.0E160, 1.0E160), (0.0, 0.0)],
                           "coordinates beyond 1.0E150");
      Expect_Line_Failure ([(1.0E-300, 1.0E-300),
                            (1.0E-300 * (1.0 + 1.0E-15), 1.0E-300)],
                           "points equal to 1E-15 relative at 1E-300");
   end Test_Fit_Scale;

   procedure Run_All is
   begin
      Test_Distances;
      Test_Line_Line;
      Test_Line_Circle;
      Test_Circle_Circle;
      Test_Fit_Line_Exact;
      Test_Isotropic_Scatter;
      Test_Fit_Line_Noisy;
      Test_Fit_Line_Errors;
      Test_Fit_Line_Robust;
      Test_Fit_Circle_Exact;
      Test_Fit_Circle_Noisy;
      Test_Fit_Circle_Errors;
      Test_Fit_Circle_Stationary;
      Test_Fit_Circle_Large_Residuals;
      Test_Fit_Circle_Robust;
      Test_Fit_Scale;
      Ada.Text_IO.Put_Line ("Test_Geometry done");
   end Run_All;

   procedure Main is new AMV_Test_Support.Standalone (Run_All);

begin
   Main;
end Test_Geometry;
