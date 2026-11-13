--  Tests for AMV.Transforms (Ks_Transform_2D_Linear).

with Ada.Exceptions;
with Ada.Numerics.Long_Elementary_Functions;

with AMV;            use AMV;
with AMV.Misc;
with AMV.Transforms; use AMV.Transforms;
with AMV_Test_Support; use AMV_Test_Support;

procedure Test_Transforms is

   package EF renames Ada.Numerics.Long_Elementary_Functions;

   Pi   : constant := AMV.Misc.Pi;
   Tol  : constant := 1.0E-12;

   type Real_Array is array (Positive range <>) of Real;
   Sqrt_2 : constant Real := EF.Sqrt (2.0);
   Sqrt_3 : constant Real := EF.Sqrt (3.0);

   procedure Check_Matrix
     (T                        : Ks_Transform_2D_Linear;
      A, B, C, D, Tx, Ty       : Real;
      Tolerance                : Real;
      Description              : String)
   is
      GA, GB, GC, GD, GTx, GTy : Real;
   begin
      T.Get_Matrix_Elements_Translation (GA, GB, GC, GD, GTx, GTy);
      Check_Near (GA, A, Tolerance, Description & " A");
      Check_Near (GB, B, Tolerance, Description & " B");
      Check_Near (GC, C, Tolerance, Description & " C");
      Check_Near (GD, D, Tolerance, Description & " D");
      Check_Near (GTx, Tx, Tolerance, Description & " Tx");
      Check_Near (GTy, Ty, Tolerance, Description & " Ty");
   end Check_Matrix;

   procedure Check_Same_Matrix
     (Actual, Expected : Ks_Transform_2D_Linear;
      Tolerance        : Real;
      Description      : String)
   is
      A, B, C, D, Tx, Ty : Real;
   begin
      Expected.Get_Matrix_Elements_Translation (A, B, C, D, Tx, Ty);
      Check_Matrix (Actual, A, B, C, D, Tx, Ty, Tolerance, Description);
   end Check_Same_Matrix;

   procedure Check_Point
     (T           : Ks_Transform_2D_Linear;
      X, Y        : Real;
      EX, EY      : Real;
      Tolerance   : Real;
      Description : String)
   is
      MX, MY : Real;
   begin
      T.Map_Point (X, Y, MX, MY);
      Check_Near (MX, EX, Tolerance, Description & " x");
      Check_Near (MY, EY, Tolerance, Description & " y");
   end Check_Point;

   procedure Check_In_Angle_Range (Angle : Real; Description : String) is
   begin
      Check (Angle > -Pi and then Angle <= Pi,
             Description & " in (-Pi, Pi]:" & Real'Image (Angle));
   end Check_In_Angle_Range;

   function Is_Positive_Zero (X : Real) return Boolean is
     (X = 0.0 and then Real'Copy_Sign (1.0, X) = 1.0);

   procedure Fail_With (E : Ada.Exceptions.Exception_Occurrence;
                        Description : String);
   --  Records an unexpected exception as one failed check.

   procedure Fail_With (E : Ada.Exceptions.Exception_Occurrence;
                        Description : String) is
   begin
      Fail (Description & ": raised " & Ada.Exceptions.Exception_Name (E)
            & ": " & Ada.Exceptions.Exception_Message (E));
   end Fail_With;

   procedure Check_Relative
     (Actual, Expected : Real;
      Tolerance        : Real;
      Description      : String);
   --  abs (Actual - Expected) <= Tolerance * abs Expected (both zero when
   --  Expected is zero). Opposite signs fail before the difference is
   --  formed, so it cannot overflow.

   procedure Check_Relative
     (Actual, Expected : Real;
      Tolerance        : Real;
      Description      : String) is
   begin
      Check ((if Expected = 0.0 then Actual = 0.0
              else (Actual > 0.0) = (Expected > 0.0)
                   and then abs (Actual - Expected)
                              <= Tolerance * abs Expected),
             Description & ": got" & Real'Image (Actual) & ", expected"
             & Real'Image (Expected));
   end Check_Relative;

   procedure Check_Inverse
     (T                       : Ks_Transform_2D_Linear;
      A, B, C, D, Tx, Ty      : Real;
      Description             : String);
   --  T.Invert does not raise, matches the expected inverse entry by entry
   --  within a relative 1.0E-15, and composes with T to the identity
   --  (within 1.0E-12) in both orders when the translations are zero.

   procedure Check_Inverse
     (T                       : Ks_Transform_2D_Linear;
      A, B, C, D, Tx, Ty      : Real;
      Description             : String)
   is
      GA, GB, GC, GD, GTx, GTy : Real;
   begin
      declare
         Inverse : constant Ks_Transform_2D_Linear := T.Invert;
      begin
         Inverse.Get_Matrix_Elements_Translation (GA, GB, GC, GD, GTx, GTy);
         Check_Relative (GA, A, 1.0E-15, Description & " A");
         Check_Relative (GB, B, 1.0E-15, Description & " B");
         Check_Relative (GC, C, 1.0E-15, Description & " C");
         Check_Relative (GD, D, 1.0E-15, Description & " D");
         Check_Relative (GTx, Tx, 1.0E-15, Description & " Tx");
         Check_Relative (GTy, Ty, 1.0E-15, Description & " Ty");
         if Tx = 0.0 and then Ty = 0.0 and then T.Translation_X = 0.0
           and then T.Translation_Y = 0.0
         then
            Check (T.Compose (Inverse).Identity (1.0E-12),
                   Description & ": T * T^-1 = identity");
            Check (Inverse.Compose (T).Identity (1.0E-12),
                   Description & ": T^-1 * T = identity");
         end if;
      end;
   exception
      when E : others =>
         Fail_With (E, Description);
   end Check_Inverse;

   --------------------------------------------------------------------

   procedure Test_Defaults is
      Default : Ks_Transform_2D_Linear;
      S, Asp, R, K, Tx, Ty : Real;
   begin
      Section ("defaults");
      Check_Matrix (Default, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0,
                    "default object");
      Check_Matrix (Identity, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0,
                    "Identity");
      Check (Default.Identity, "default Identity");
      Check (Default.Identity (0.0), "default Identity, tol 0");
      Check (Default.Is_Similarity, "identity Is_Similarity");
      Check (Default.Is_Axis_Aligned, "identity Is_Axis_Aligned");
      Check (Default.Matrix_Determinant = 1.0, "identity determinant");
      Check (Default.Scaling = 1.0, "identity Scaling");
      Check (Default.Aspect = 1.0, "identity Aspect");
      Check (Default.Rotation = 0.0, "identity Rotation");
      Check (Default.Skew = 0.0, "identity Skew");
      Check (Default.Scaling_X = 1.0, "identity Scaling_X");
      Check (Default.Scaling_Y = 1.0, "identity Scaling_Y");
      Check (Default.Rotation_X = 0.0, "identity Rotation_X");
      Check (Default.Rotation_Y = 0.0, "identity Rotation_Y");
      Check (Default.Translation_X = 0.0, "identity Translation_X");
      Check (Default.Translation_Y = 0.0, "identity Translation_Y");
      Default.Get_Scaling_Aspect_Rotation_Skew_Translation
        (S, Asp, R, K, Tx, Ty);
      Check (S = 1.0 and then Asp = 1.0 and then R = 0.0 and then K = 0.0
             and then Tx = 0.0 and then Ty = 0.0,
             "identity composite getter");
      Check (Default.Invert.Identity (0.0), "identity inverse");
   end Test_Defaults;

   procedure Test_Constructors is
      T : Ks_Transform_2D_Linear;
   begin
      Section ("constructors and matrix form");
      T := Create (1.0, 2.0, 3.0, 4.0, 5.0, 6.0);
      Check_Matrix (T, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 0.0, "Create");
      Check (T.Translation_X = 5.0 and then T.Translation_Y = 6.0,
             "Create translation getters");
      Check (T.Matrix_Determinant = -2.0, "Create determinant");

      T.Set_Matrix_Elements_Translation (-1.5, 0.25, 7.0, 0.0, -8.0, 9.5);
      Check_Matrix (T, -1.5, 0.25, 7.0, 0.0, -8.0, 9.5, 0.0,
                    "Set_Matrix_Elements_Translation");

      --  30 degrees: (1, 0) goes to (cos, sin), (0, 1) to (-sin, cos).
      T := Create_Rigid (Pi / 6.0, 3.0, -4.0);
      Check_Matrix (T, Sqrt_3 / 2.0, -0.5, 0.5, Sqrt_3 / 2.0, 3.0, -4.0,
                    Tol, "Create_Rigid 30 deg");
      Check_Point (T, 1.0, 0.0, Sqrt_3 / 2.0 + 3.0, 0.5 - 4.0, Tol,
                   "rigid maps (1, 0)");
      Check_Point (T, 0.0, 2.0, -1.0 + 3.0, Sqrt_3 - 4.0, Tol,
                   "rigid maps (0, 2)");
      Check_Near (T.Rotation, Pi / 6.0, Tol, "rigid Rotation");
      Check_Near (T.Scaling, 1.0, Tol, "rigid Scaling");
      Check_Near (T.Aspect, 1.0, Tol, "rigid Aspect");
      Check_Near (T.Skew, 0.0, Tol, "rigid Skew");
      Check_Near (T.Matrix_Determinant, 1.0, Tol, "rigid determinant");

      --  A quarter turn takes the x axis to the y axis (y down image).
      T := Create_Rigid (Pi / 2.0, 0.0, 0.0);
      Check_Point (T, 1.0, 0.0, 0.0, 1.0, Tol, "quarter turn (1, 0)");
      Check_Point (T, 0.0, 1.0, -1.0, 0.0, Tol, "quarter turn (0, 1)");

      T := Create_Similarity (2.5, -Pi / 4.0, 1.0, 2.0);
      Check_Matrix (T, 2.5 * Sqrt_2 / 2.0, 2.5 * Sqrt_2 / 2.0,
                    -2.5 * Sqrt_2 / 2.0, 2.5 * Sqrt_2 / 2.0, 1.0, 2.0,
                    Tol, "Create_Similarity");
      Check (T.Is_Similarity (0.0), "Create_Similarity exact similarity");
      Check_Near (T.Scaling, 2.5, Tol, "similarity Scaling");
      Check_Near (T.Rotation, -Pi / 4.0, Tol, "similarity Rotation");
      Check_Near (T.Matrix_Determinant, 6.25, Tol, "similarity determinant");

      --  Pure anisotropic scaling.
      T := Create_Scaling_Aspect_Rotation_Skew_Translation
        (2.0, 1.5, 0.0, 0.0, -1.0, 4.0);
      Check_Matrix (T, 2.0, 0.0, 0.0, 3.0, -1.0, 4.0, Tol,
                    "scaling 2, aspect 1.5");
      Check_Near (T.Scaling_Y, 3.0, Tol, "aspect 1.5 Scaling_Y");

      --  Pure skew of 45 degrees: the y axis turns, the x axis stays.
      T := Create_Scaling_Aspect_Rotation_Skew_Translation
        (1.0, 1.0, 0.0, Pi / 4.0, 0.0, 0.0);
      Check_Matrix (T, 1.0, -Sqrt_2 / 2.0, 0.0, Sqrt_2 / 2.0, 0.0, 0.0,
                    Tol, "skew 45 deg");
      Check_Near (T.Skew, Pi / 4.0, Tol, "skew 45 deg Skew");
      Check_Near (T.Rotation, 0.0, Tol, "skew 45 deg Rotation");
      Check_Near (T.Rotation_Y, Pi / 4.0, Tol, "skew 45 deg Rotation_Y");
      Check_Near (T.Matrix_Determinant, Sqrt_2 / 2.0, Tol, "skew determinant");

      --  Everything at once.
      T := Create_Scaling_Aspect_Rotation_Skew_Translation
        (2.0, 0.5, 0.3, -0.2, 5.0, 6.0);
      Check_Matrix (T, 2.0 * EF.Cos (0.3), -EF.Sin (0.1),
                    2.0 * EF.Sin (0.3), EF.Cos (0.1), 5.0, 6.0, Tol,
                    "general SARST");
      Check_Near (T.Scaling_X, 2.0, Tol, "general Scaling_X");
      Check_Near (T.Scaling_Y, 1.0, Tol, "general Scaling_Y");
      Check_Near (T.Rotation_X, 0.3, Tol, "general Rotation_X");
      Check_Near (T.Rotation_Y, 0.1, Tol, "general Rotation_Y");
      Check_Near (T.Matrix_Determinant, 2.0 * EF.Cos (0.2), Tol,
                  "determinant = Sx Sy cos (skew)");
   end Test_Constructors;

   procedure Test_Setters is
      Base : constant Ks_Transform_2D_Linear :=
        Create_Scaling_Aspect_Rotation_Skew_Translation
          (2.0, 0.5, 0.3, -0.2, 5.0, 6.0);
      T : Ks_Transform_2D_Linear;

      procedure Check_Kept_Translation (Description : String) is
      begin
         Check (T.Translation_X = 5.0 and then T.Translation_Y = 6.0,
                Description & " keeps translation");
      end Check_Kept_Translation;
   begin
      Section ("individual setters");

      T := Base;
      T.Set_Translation_X (-7.5);
      Check (T.Translation_X = -7.5, "Set_Translation_X round trip");
      T.Set_Translation_Y (8.25);
      Check (T.Translation_Y = 8.25, "Set_Translation_Y round trip");
      declare
         A, B, C, D, Tx, Ty, A0, B0, C0, D0, Tx0, Ty0 : Real;
      begin
         T.Get_Matrix_Elements_Translation (A, B, C, D, Tx, Ty);
         Base.Get_Matrix_Elements_Translation (A0, B0, C0, D0, Tx0, Ty0);
         Check (A = A0 and then B = B0 and then C = C0 and then D = D0,
                "translation setters keep the linear part exactly");
         Check (Tx /= Tx0 and then Ty /= Ty0, "translation changed");
      end;

      --  Set_Rotation keeps skew, scaling and aspect.
      T := Base;
      T.Set_Rotation (1.1);
      Check_Near (T.Rotation, 1.1, Tol, "Set_Rotation round trip");
      Check_Near (T.Skew, -0.2, Tol, "Set_Rotation keeps Skew");
      Check_Near (T.Scaling, 2.0, Tol, "Set_Rotation keeps Scaling");
      Check_Near (T.Aspect, 0.5, Tol, "Set_Rotation keeps Aspect");
      Check_Near (T.Rotation_Y, 0.9, Tol, "Set_Rotation turns the y axis");
      Check_Kept_Translation ("Set_Rotation");

      T := Base;
      T.Set_Skew (0.7);
      Check_Near (T.Skew, 0.7, Tol, "Set_Skew round trip");
      Check_Near (T.Rotation, 0.3, Tol, "Set_Skew keeps Rotation");
      Check_Near (T.Scaling, 2.0, Tol, "Set_Skew keeps Scaling");
      Check_Near (T.Aspect, 0.5, Tol, "Set_Skew keeps Aspect");
      Check_Kept_Translation ("Set_Skew");

      T := Base;
      T.Set_Scaling (4.0);
      Check_Near (T.Scaling, 4.0, Tol, "Set_Scaling round trip");
      Check_Near (T.Aspect, 0.5, Tol, "Set_Scaling keeps Aspect");
      Check_Near (T.Scaling_Y, 2.0, Tol, "Set_Scaling scales y too");
      Check_Near (T.Rotation, 0.3, Tol, "Set_Scaling keeps Rotation");
      Check_Near (T.Skew, -0.2, Tol, "Set_Scaling keeps Skew");
      Check_Kept_Translation ("Set_Scaling");

      T := Base;
      T.Set_Aspect (3.0);
      Check_Near (T.Aspect, 3.0, Tol, "Set_Aspect round trip");
      Check_Near (T.Scaling, 2.0, Tol, "Set_Aspect keeps Scaling");
      Check_Near (T.Scaling_Y, 6.0, Tol, "Set_Aspect changes Scaling_Y");
      Check_Near (T.Rotation, 0.3, Tol, "Set_Aspect keeps Rotation");
      Check_Near (T.Skew, -0.2, Tol, "Set_Aspect keeps Skew");
      Check_Kept_Translation ("Set_Aspect");

      T := Base;
      T.Set_Scaling_X (5.0);
      Check_Near (T.Scaling_X, 5.0, Tol, "Set_Scaling_X round trip");
      Check_Near (T.Scaling_Y, 1.0, Tol, "Set_Scaling_X keeps Scaling_Y");
      Check_Near (T.Aspect, 0.2, Tol, "Set_Scaling_X changes Aspect");
      Check_Near (T.Rotation_X, 0.3, Tol, "Set_Scaling_X keeps Rotation_X");
      Check_Near (T.Rotation_Y, 0.1, Tol, "Set_Scaling_X keeps Rotation_Y");
      Check_Kept_Translation ("Set_Scaling_X");

      T := Base;
      T.Set_Scaling_Y (7.0);
      Check_Near (T.Scaling_Y, 7.0, Tol, "Set_Scaling_Y round trip");
      Check_Near (T.Scaling_X, 2.0, Tol, "Set_Scaling_Y keeps Scaling_X");
      Check_Near (T.Aspect, 3.5, Tol, "Set_Scaling_Y changes Aspect");
      Check_Near (T.Rotation_X, 0.3, Tol, "Set_Scaling_Y keeps Rotation_X");
      Check_Near (T.Rotation_Y, 0.1, Tol, "Set_Scaling_Y keeps Rotation_Y");
      Check_Kept_Translation ("Set_Scaling_Y");

      --  Set_Rotation_X keeps Rotation_Y, so the skew changes.
      T := Base;
      T.Set_Rotation_X (-1.0);
      Check_Near (T.Rotation_X, -1.0, Tol, "Set_Rotation_X round trip");
      Check_Near (T.Rotation_Y, 0.1, Tol, "Set_Rotation_X keeps Rotation_Y");
      Check_Near (T.Skew, 1.1, Tol, "Set_Rotation_X changes Skew");
      Check_Near (T.Scaling_X, 2.0, Tol, "Set_Rotation_X keeps Scaling_X");
      Check_Near (T.Scaling_Y, 1.0, Tol, "Set_Rotation_X keeps Scaling_Y");
      Check_Kept_Translation ("Set_Rotation_X");

      T := Base;
      T.Set_Rotation_Y (2.0);
      Check_Near (T.Rotation_Y, 2.0, Tol, "Set_Rotation_Y round trip");
      Check_Near (T.Rotation_X, 0.3, Tol, "Set_Rotation_Y keeps Rotation_X");
      Check_Near (T.Skew, 1.7, Tol, "Set_Rotation_Y changes Skew");
      Check_Near (T.Scaling_X, 2.0, Tol, "Set_Rotation_Y keeps Scaling_X");
      Check_Near (T.Scaling_Y, 1.0, Tol, "Set_Rotation_Y keeps Scaling_Y");
      Check_Kept_Translation ("Set_Rotation_Y");

      Section ("angle wrapping");
      T := Base;
      T.Set_Rotation (3.5);
      Check_Angle_Near (T.Rotation, 3.5, Tol, "Set_Rotation (3.5)");
      Check_Near (T.Rotation, 3.5 - 2.0 * Pi, Tol,
                  "Set_Rotation (3.5) reads back normalised");
      Check_Near (T.Skew, -0.2, Tol, "wrapped rotation keeps Skew");

      T.Set_Rotation (Pi);
      Check_Near (T.Rotation, Pi, Tol, "Set_Rotation (Pi)");
      Check_In_Angle_Range (T.Rotation, "rotation Pi");
      T.Set_Rotation (-Pi);
      Check_Angle_Near (T.Rotation, Pi, Tol, "Set_Rotation (-Pi)");
      Check_In_Angle_Range (T.Rotation, "rotation -Pi");
      T.Set_Rotation (-7.0);
      Check_Near (T.Rotation, -7.0 + 2.0 * Pi, Tol, "Set_Rotation (-7)");

      --  Rotation_Y wraps past Pi, the skew still reads 0.5.
      T := Base;
      T.Set_Rotation_X (3.0);
      T.Set_Skew (0.5);
      Check_Near (T.Skew, 0.5, Tol, "skew across the Pi seam");
      Check_Near (T.Rotation_Y, 3.5 - 2.0 * Pi, Tol,
                  "Rotation_Y across the Pi seam");
      T.Set_Skew (-3.0);
      Check_Near (T.Skew, -3.0, Tol, "large negative skew");
      T.Set_Skew (4.0);
      Check_Near (T.Skew, 4.0 - 2.0 * Pi, Tol, "skew 4 reads normalised");
      Check_In_Angle_Range (T.Skew, "skew 4");
   end Test_Setters;

   procedure Test_Composite is
      T : Ks_Transform_2D_Linear;
      S, Asp, R, K, Tx, Ty     : Real;
      SX, SY, RX, RY, Tx2, Ty2 : Real;
   begin
      Section ("composite setters and getters");
      T.Set_Scaling_Aspect_Rotation_Skew_Translation
        (1.75, 0.6, -2.0, 0.4, -3.0, 11.0);
      T.Get_Scaling_Aspect_Rotation_Skew_Translation (S, Asp, R, K, Tx, Ty);
      Check_Near (S, 1.75, Tol, "SARST Scaling");
      Check_Near (Asp, 0.6, Tol, "SARST Aspect");
      Check_Near (R, -2.0, Tol, "SARST Rotation");
      Check_Near (K, 0.4, Tol, "SARST Skew");
      Check (Tx = -3.0 and then Ty = 11.0, "SARST translation");
      Check (S = T.Scaling and then Asp = T.Aspect and then R = T.Rotation
             and then K = T.Skew,
             "SARST getter agrees with individual getters");
      Check_Same_Matrix
        (T, Create_Scaling_Aspect_Rotation_Skew_Translation
              (1.75, 0.6, -2.0, 0.4, -3.0, 11.0), 0.0,
         "SARST setter equals constructor");

      T.Get_Scalings_Rotations_Translation (SX, SY, RX, RY, Tx2, Ty2);
      Check_Near (SX, 1.75, Tol, "SRT Scaling_X of SARST");
      Check_Near (SY, 1.05, Tol, "SRT Scaling_Y of SARST");
      Check_Near (RX, -2.0, Tol, "SRT Rotation_X of SARST");
      Check_Near (RY, -1.6, Tol, "SRT Rotation_Y of SARST");
      Check (Tx2 = -3.0 and then Ty2 = 11.0, "SRT translation");

      T.Set_Scalings_Rotations_Translation (0.5, 4.0, 2.5, -2.9, 1.0, -2.0);
      T.Get_Scalings_Rotations_Translation (SX, SY, RX, RY, Tx2, Ty2);
      Check_Near (SX, 0.5, Tol, "SRT round trip Scaling_X");
      Check_Near (SY, 4.0, Tol, "SRT round trip Scaling_Y");
      Check_Near (RX, 2.5, Tol, "SRT round trip Rotation_X");
      Check_Near (RY, -2.9, Tol, "SRT round trip Rotation_Y");
      Check (Tx2 = 1.0 and then Ty2 = -2.0, "SRT round trip translation");
      Check (SX = T.Scaling_X and then SY = T.Scaling_Y
             and then RX = T.Rotation_X and then RY = T.Rotation_Y,
             "SRT getter agrees with individual getters");
      Check_Near (T.Aspect, 8.0, Tol, "SRT aspect");
      Check_Near (T.Skew, -2.9 - 2.5 + 2.0 * Pi, Tol, "SRT skew wraps");
      Check_Matrix (T, 0.5 * EF.Cos (2.5), 4.0 * EF.Sin (2.9),
                    0.5 * EF.Sin (2.5), 4.0 * EF.Cos (-2.9), 1.0, -2.0,
                    Tol, "SRT matrix");
   end Test_Composite;

   procedure Test_Reflections_And_Degenerate is
      T : Ks_Transform_2D_Linear;
      MX, MY : Real;
   begin
      Section ("reflections");
      --  Mirror y: the y axis image points along -y, skew is Pi.
      T := Create (1.0, 0.0, 0.0, -1.0, 0.0, 0.0);
      Check (T.Scaling_X = 1.0 and then T.Scaling_Y = 1.0,
             "mirror y scalings");
      Check (T.Rotation = 0.0, "mirror y rotation");
      Check (T.Skew = Pi, "mirror y skew is exactly +Pi");
      Check (T.Rotation_Y = Pi, "mirror y Rotation_Y is +Pi");
      Check (T.Matrix_Determinant = -1.0, "mirror y determinant");
      Check (not T.Is_Similarity, "mirror is no similarity");
      Check (T.Is_Axis_Aligned, "mirror is axis aligned");

      --  Mirror x: the x axis image points along -x.
      T := Create (-1.0, 0.0, 0.0, 1.0, 0.0, 0.0);
      Check (T.Rotation = Pi, "mirror x rotation is +Pi");
      Check (T.Skew = Pi, "mirror x skew is +Pi");
      Check (T.Aspect = 1.0, "mirror x aspect");

      --  A reflection about the line through the origin at angle 0.2.
      T := Create_Scaling_Aspect_Rotation_Skew_Translation
        (1.0, 1.0, 0.4, Pi, 0.0, 0.0);
      Check_Matrix (T, EF.Cos (0.4), EF.Sin (0.4), EF.Sin (0.4),
                    -EF.Cos (0.4), 0.0, 0.0, Tol, "reflection matrix");
      Check_Near (T.Matrix_Determinant, -1.0, Tol, "reflection determinant");
      Check_Point (T, EF.Cos (0.2), EF.Sin (0.2), EF.Cos (0.2),
                   EF.Sin (0.2), Tol, "point on the mirror line is fixed");
      Check_Point (T, -EF.Sin (0.2), EF.Cos (0.2), EF.Sin (0.2),
                   -EF.Cos (0.2), Tol, "normal of the mirror line flips");
      Check_Angle_Near (T.Skew, Pi, Tol, "reflection skew");
      Check_Near (T.Rotation, 0.4, Tol, "reflection rotation");
      Check_Same_Matrix (T.Compose (T), Identity, Tol,
                         "reflection is its own inverse");
      T.Set_Rotation (-1.0);
      Check_Angle_Near (T.Skew, Pi, Tol, "Set_Rotation keeps reflection");
      Check_Near (T.Matrix_Determinant, -1.0, Tol, "still a reflection");
      Check_Angle_Near (T.Map_Angle (0.0), -1.0, Tol,
                        "reflection maps angle 0 to its rotation");
      Check_Angle_Near (T.Map_Angle (-0.5), -0.5, Tol,
                        "the mirror line direction is fixed");
      Check_Angle_Near (T.Map_Angle (1.0), -2.0, Tol,
                        "reflection maps phi to -1 - phi");

      Section ("negative scaling inputs");
      T := Identity;
      T.Set_Scaling_X (-2.0);
      Check_Matrix (T, -2.0, 0.0, 0.0, 1.0, 0.0, 0.0, Tol,
                    "negative Scaling_X reverses x");
      Check_Near (T.Scaling_X, 2.0, Tol, "reads back magnitude");
      Check_Near (T.Rotation_X, Pi, Tol, "rotation turned by Pi");
      T := Create_Scaling_Aspect_Rotation_Skew_Translation
        (-1.0, 1.0, 0.0, 0.0, 0.0, 0.0);
      Check_Matrix (T, -1.0, 0.0, 0.0, -1.0, 0.0, 0.0, Tol,
                    "negative scaling is a half turn");
      Check_Angle_Near (T.Rotation, Pi, Tol, "half turn rotation");
      Check_Near (T.Skew, 0.0, Tol, "half turn skew");
      T := Identity;
      T.Set_Aspect (-1.0);
      Check_Matrix (T, 1.0, 0.0, 0.0, -1.0, 0.0, 0.0, Tol,
                    "negative aspect mirrors y");
      Check_Near (T.Aspect, 1.0, Tol, "negative aspect reads magnitude");
      Check_Angle_Near (T.Skew, Pi, Tol, "negative aspect gives skew Pi");

      Section ("zero scalings");
      T := Create (0.0, 0.0, 0.0, 2.0, 1.0, 1.0);
      Check (T.Scaling = 0.0, "zero x column Scaling");
      Check (T.Scaling_X = 0.0, "zero x column Scaling_X");
      Check (T.Rotation = 0.0, "zero x column Rotation is 0");
      Check (T.Rotation_X = 0.0, "zero x column Rotation_X is 0");
      Check (T.Aspect = 0.0, "Aspect with zero Scaling_X is 0, no raise");
      Check (T.Scaling_Y = 2.0, "zero x column Scaling_Y");
      Check (T.Rotation_Y = 0.0, "zero x column Rotation_Y");
      Check (T.Skew = 0.0, "zero x column Skew");
      declare
         Copy : Ks_Transform_2D_Linear := T;
      begin
         Copy.Set_Scaling (3.0);
         Check_Matrix (Copy, 3.0, 0.0, 0.0, 0.0, 1.0, 1.0, Tol,
                       "Set_Scaling with zero Scaling_X zeroes y");
         Copy := T;
         Copy.Set_Scaling_X (3.0);
         Check_Matrix (Copy, 3.0, 0.0, 0.0, 2.0, 1.0, 1.0, Tol,
                       "Set_Scaling_X from zero keeps Scaling_Y");
         Copy := T;
         Copy.Set_Aspect (5.0);
         Check_Matrix (Copy, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, Tol,
                       "Set_Aspect with zero Scaling_X");
         Copy := T;
         Copy.Set_Rotation (0.5);
         Check (Copy.Rotation = 0.0,
                "rotation of a zero column still reads 0");
         Check_Near (Copy.Rotation_Y, 0.5, Tol,
                     "Set_Rotation turns the remaining axis");
      end;

      --  The documented zero column cases: with Scaling_X = 0, both
      --  Set_Rotation and Set_Skew turn the y axis from a Rotation of 0.
      declare
         Copy : Ks_Transform_2D_Linear := T;
      begin
         Copy.Set_Rotation (0.5);
         Check (Copy.Rotation = 0.0, "zero x column: Rotation stays 0");
         Check_Near (Copy.Skew, 0.5, Tol,
                     "zero x column: Set_Rotation changes Skew");
         Copy.Set_Rotation (0.25);
         Check_Near (Copy.Rotation_Y, 0.75, Tol,
                     "zero x column: Set_Rotation adds to Rotation_Y");
         Copy := T;
         Copy.Set_Skew (0.7);
         Check_Near (Copy.Skew, 0.7, Tol,
                     "zero x column: Set_Skew reads back");
         Check (Copy.Rotation = 0.0,
                "zero x column: Set_Skew keeps Rotation 0");
         Check_Near (Copy.Scaling_Y, 2.0, Tol,
                     "zero x column: Set_Skew keeps Scaling_Y");
      end;
      --  With Scaling_Y = 0, Skew reads -Rotation; Set_Skew and
      --  Set_Rotation_Y have no effect.
      declare
         Copy : Ks_Transform_2D_Linear :=
           Create (1.0, 0.0, 0.0, 0.0, 0.0, 0.0);
      begin
         Copy.Set_Rotation (0.5);
         Check_Near (Copy.Rotation, 0.5, Tol,
                     "zero y column: Set_Rotation round trip");
         Check_Near (Copy.Skew, -0.5, Tol,
                     "zero y column: Set_Rotation makes Skew -0.5");
         Copy := Create (1.0, 0.0, 0.0, 0.0, 0.0, 0.0);
         Copy.Set_Skew (0.7);
         Check (Copy.Skew = 0.0, "zero y column: Set_Skew has no effect");
         Check_Matrix (Copy, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                       "zero y column: Set_Skew leaves the matrix");
         Copy.Set_Rotation_Y (1.0);
         Check_Matrix (Copy, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                       "zero y column: Set_Rotation_Y leaves the matrix");
      end;
      --  A setter that makes a scaling zero loses that axis's rotation.
      declare
         Base : constant Ks_Transform_2D_Linear :=
           Create_Scaling_Aspect_Rotation_Skew_Translation
             (1.0, 2.0, 0.3, 0.2, 0.0, 0.0);
         Copy : Ks_Transform_2D_Linear := Base;
      begin
         Copy.Set_Scaling_X (0.0);
         Check (Copy.Rotation = 0.0, "Set_Scaling_X (0) loses Rotation");
         Check_Near (Copy.Skew, 0.5, Tol,
                     "Set_Scaling_X (0): Skew reads Rotation_Y");
         Copy := Base;
         Copy.Set_Aspect (0.0);
         Check_Near (Copy.Skew, -0.3, Tol,
                     "Set_Aspect (0): Skew reads -Rotation");
         Copy := Base;
         Copy.Set_Scaling (0.0);
         Check (Copy.Rotation = 0.0 and then Copy.Skew = 0.0,
                "Set_Scaling (0) loses both rotations");
      end;
      --  A zero linear part: only the scaling setters change it.
      declare
         Copy : Ks_Transform_2D_Linear :=
           Create (0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
      begin
         Copy.Set_Rotation (1.0);
         Copy.Set_Skew (0.5);
         Copy.Set_Rotation_X (0.2);
         Copy.Set_Rotation_Y (0.3);
         Copy.Set_Aspect (2.0);
         Check_Matrix (Copy, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                       "zero matrix: angle and aspect setters do nothing");
         Copy.Set_Scaling_Y (2.0);
         Check_Matrix (Copy, 0.0, 0.0, 0.0, 2.0, 0.0, 0.0, 0.0,
                       "zero matrix: Set_Scaling_Y");
      end;

      T := Create (0.0, -3.0, 0.0, 0.0, 0.0, 0.0);
      Check (T.Scaling_X = 0.0 and then T.Rotation_X = 0.0,
             "zero x column reads rotation 0");
      Check_Near (T.Scaling_Y, 3.0, Tol, "y column length");
      Check_Near (T.Rotation_Y, Pi / 2.0, Tol, "y axis image along -x");

      T := Create (1.0, 0.0, 0.0, 0.0, 0.0, 0.0);
      Check (T.Scaling_Y = 0.0 and then T.Rotation_Y = 0.0,
             "zero y column rotation reads 0");
      Check (T.Aspect = 0.0, "zero y column aspect");
      Check (T.Skew = 0.0, "zero y column skew");

      T := Create (0.0, 0.0, 0.0, 0.0, 4.0, 5.0);
      Check (T.Scaling = 0.0 and then T.Aspect = 0.0
             and then T.Rotation = 0.0 and then T.Skew = 0.0,
             "zero matrix decomposes to zeros");
      T.Map_Point (100.0, -100.0, MX, MY);
      Check (MX = 4.0 and then MY = 5.0, "zero matrix maps to translation");

      Section ("extreme magnitudes");
      --  Entries up to 1.0E150 are accepted (scalings up to 2.0E150).
      T := Create (3.0E149, 0.0, 4.0E149, 1.0, 0.0, 0.0);
      Check_Near (T.Scaling_X / 5.0E149, 1.0, Tol, "huge Scaling_X");
      Check_Near (T.Rotation_X, EF.Arctan (4.0, 3.0), Tol, "huge rotation");
      T := Create (1.0E150, 0.0, 1.0E150, 1.0, 0.0, 0.0);
      Check_Near (T.Scaling_X / (Sqrt_2 * 1.0E150), 1.0, Tol,
                  "Scaling_X of entries at the bound exceeds 1.0E150");
      declare
         procedure Read_Scaling is
         begin
            if Create (3.0E200, 0.0, 4.0E200, 1.0, 0.0, 0.0).Scaling_X = 0.0
            then
               Fail ("impossible");
            end if;
         end Read_Scaling;
         procedure Check_Too_Big is new Check_Raises_Exactly
           (Read_Scaling, Ks_Bad_Parameter_Exception'Identity);
      begin
         Check_Too_Big ("entries above 1.0E150 are rejected");
      end;
      T := Create (3.0E-200, 0.0, 4.0E-200, 1.0, 0.0, 0.0);
      Check_Near (T.Scaling_X / 5.0E-200, 1.0, Tol, "tiny Scaling_X");
      Check_Near (T.Rotation_X, EF.Arctan (4.0, 3.0), Tol, "tiny rotation");
   end Test_Reflections_And_Degenerate;

   procedure Test_Mapping is
      T  : Ks_Transform_2D_Linear := Create (1.0, 2.0, 3.0, 4.0, 5.0, 6.0);
      MX, MY : Real;
   begin
      Section ("map point and vector");
      T.Map_Point (7.0, -8.0, MX, MY);
      Check (MX = -4.0 and then MY = -5.0, "Map_Point exact");
      T.Map_Vector (7.0, -8.0, MX, MY);
      Check (MX = -9.0 and then MY = -11.0, "Map_Vector ignores translation");
      T.Map_Point (0.0, 0.0, MX, MY);
      Check (MX = 5.0 and then MY = 6.0, "origin maps to the translation");

      Section ("map angle");
      T := Create_Rigid (0.5, 10.0, -3.0);
      Check_Near (T.Map_Angle (0.25), 0.75, Tol, "rotation adds");
      Check_Near (T.Map_Angle (3.0), 3.5 - 2.0 * Pi, Tol,
                  "mapped angle wraps to (-Pi, Pi]");
      Check_Near (Identity.Map_Angle (Pi), Pi, Tol, "Pi stays +Pi");
      Check_In_Angle_Range (Identity.Map_Angle (Pi), "identity Pi");
      Check_In_Angle_Range (Identity.Map_Angle (-Pi), "identity -Pi");
      Check_Near (Identity.Map_Angle (7.0), 7.0 - 2.0 * Pi, Tol,
                  "identity normalises");

      --  Anisotropic scaling diag (2, 1): tan (out) = tan (in) / 2.
      T := Create (2.0, 0.0, 0.0, 1.0, 0.0, 0.0);
      Check_Near (T.Map_Angle (Pi / 4.0), EF.Arctan (0.5), Tol,
                  "anisotropic 45 deg");
      Check_Near (T.Map_Angle (-3.0 * Pi / 4.0), EF.Arctan (0.5) - Pi, Tol,
                  "anisotropic -135 deg");
      Check_Near (T.Map_Angle (Pi / 2.0), Pi / 2.0, Tol,
                  "anisotropic keeps the axes");
      T := Create (1.0, 0.0, 0.0, 3.0, 0.0, 0.0);
      Check_Near (T.Map_Angle (Pi / 6.0),
                  EF.Arctan (3.0 * EF.Sin (Pi / 6.0), EF.Cos (Pi / 6.0)),
                  Tol, "anisotropic 30 deg");
      --  A mirror negates angles.
      T := Create (1.0, 0.0, 0.0, -1.0, 0.0, 0.0);
      Check_Near (T.Map_Angle (0.6), -0.6, Tol, "mirror negates");
      --  A skew of 45 degrees maps the y axis to angle Pi/2 + Pi/4.
      T := Create_Scaling_Aspect_Rotation_Skew_Translation
        (1.0, 1.0, 0.0, Pi / 4.0, 0.0, 0.0);
      Check_Near (T.Map_Angle (Pi / 2.0), 3.0 * Pi / 4.0, Tol,
                  "skewed y axis");
      Check_Near (T.Map_Angle (0.0), 0.0, Tol, "skew keeps the x axis");
      --  Scale does not matter.
      Check_Near (Create (1.0E-200, 0.0, 0.0, 1.0E-200, 0.0, 0.0).Map_Angle
                    (0.3), 0.3, Tol, "tiny scale map angle");
      Check_Near (Create (1.0E150, 0.0, 0.0, 1.0E150, 0.0, 0.0).Map_Angle
                    (0.3), 0.3, Tol, "huge scale map angle");
      --  A rank one matrix still maps directions off its null space.
      T := Create (1.0, 1.0, 1.0, 1.0, 0.0, 0.0);
      Check_Near (T.Map_Angle (0.0), Pi / 4.0, Tol, "rank one, angle 0");
      Check_Near (T.Map_Angle (Pi), -3.0 * Pi / 4.0, Tol,
                  "rank one, angle Pi");
   end Test_Mapping;

   procedure Test_Map_Angle_Singular is
      Singular : Ks_Transform_2D_Linear;
      Angle    : Real := 0.0;
      Result   : Real := 0.0;

      procedure Map is
      begin
         Result := Singular.Map_Angle (Angle);
      end Map;

      procedure Check_Map_Raises is new Check_Raises_Exactly
        (Map, Ks_Transform_Singular_Exception'Identity);
   begin
      Section ("map angle, singular");
      Singular := Create (0.0, 0.0, 0.0, 1.0, 0.0, 0.0);
      Angle := 0.0;
      Check_Map_Raises ("x axis onto zero column");
      Angle := Pi;
      Check_Map_Raises ("-x axis onto zero column");
      Angle := Pi / 2.0;
      Map;
      Check_Near (Result, Pi / 2.0, Tol, "y axis survives");

      Singular := Create (1.0, 0.0, 0.0, 0.0, 0.0, 0.0);
      Angle := Pi / 2.0;
      Check_Map_Raises ("rounded cos (Pi/2) counts as zero");
      Angle := 0.1;
      Map;
      Check_Near (Result, 0.0, Tol, "projection onto x");

      Singular := Create (1.0, 1.0, 1.0, 1.0, 0.0, 0.0);
      Angle := -Pi / 4.0;
      Check_Map_Raises ("null direction of a rank one matrix");
      Angle := 3.0 * Pi / 4.0;
      Check_Map_Raises ("opposite null direction");

      Singular := Create (0.0, 0.0, 0.0, 0.0, 1.0, 2.0);
      Angle := 1.0;
      Check_Map_Raises ("zero matrix");
   end Test_Map_Angle_Singular;

   procedure Test_Invert_And_Compose is
      General : constant Ks_Transform_2D_Linear :=
        Create_Scaling_Aspect_Rotation_Skew_Translation
          (2.0, 0.5, 0.3, -0.2, 5.0, 6.0);
      Inverse : Ks_Transform_2D_Linear;
      Victim  : Ks_Transform_2D_Linear;
      Sink    : Ks_Transform_2D_Linear;
      MX, MY, BX, BY : Real;

      procedure Do_Invert is
      begin
         Sink := Victim.Invert;
      end Do_Invert;

      procedure Check_Invert_Raises is new Check_Raises_Exactly
        (Do_Invert, Ks_Transform_Singular_Exception'Identity);

      procedure Do_Matrix_Determinant is
      begin
         if Victim.Matrix_Determinant = Real'Last then
            Fail ("impossible determinant");
         end if;
      end Do_Matrix_Determinant;

      procedure Check_Matrix_Determinant_Rejected is new Check_Raises_Exactly
        (Do_Matrix_Determinant, Ks_Bad_Parameter_Exception'Identity);

      function Tiny return Real is (1.0E-160);
      --  A function, so products with it are not static (a static
      --  subnormal value draws a warning).
   begin
      Section ("invert");
      Inverse := Create (2.0, 0.0, 0.0, 4.0, 6.0, 8.0).Invert;
      Check_Matrix (Inverse, 0.5, 0.0, 0.0, 0.25, -3.0, -2.0, 0.0,
                    "inverse of scaling plus translation");
      Inverse := Create_Rigid (0.7, 3.0, -1.0).Invert;
      Check_Same_Matrix
        (Inverse,
         Create_Rigid (-0.7, 0.0, 0.0).Compose
           (Create (1.0, 0.0, 0.0, 1.0, -3.0, 1.0)),
         Tol, "inverse of a rigid transform");
      Inverse := Create (1.0, 2.0, 3.0, 4.0, 5.0, 6.0).Invert;
      Check_Matrix (Inverse, -2.0, 1.0, 1.5, -0.5, 4.0, -4.5, Tol,
                    "inverse of a general matrix");

      Inverse := General.Invert;
      Check (General.Compose (Inverse).Identity (Tol),
             "T * T^-1 = identity");
      Check (Inverse.Compose (General).Identity (Tol),
             "T^-1 * T = identity");
      Check (Inverse.Invert.Compose (Inverse).Identity (Tol),
             "inverse of inverse");
      Check_Same_Matrix (Inverse.Invert, General, Tol,
                         "double inversion restores");
      General.Map_Point (-2.5, 7.0, MX, MY);
      Inverse.Map_Point (MX, MY, BX, BY);
      Check_Near (BX, -2.5, Tol, "point round trip x");
      Check_Near (BY, 7.0, Tol, "point round trip y");
      Check_Near
        (Inverse.Matrix_Determinant * General.Matrix_Determinant, 1.0, Tol,
         "det (T^-1) = 1 / det (T)");
      Inverse := Create_Similarity (2.0, 0.3, 1.0, -1.0).Invert;
      Check_Near (Inverse.Rotation, -0.3, Tol, "inverse similarity rotation");
      Check_Near (Inverse.Scaling, 0.5, Tol, "inverse similarity scaling");
      Check (Inverse.Is_Similarity, "inverse of a similarity");

      --  A reflection inverts to a reflection.
      Victim := Create (1.0, 0.0, 0.0, -1.0, 2.0, 3.0);
      Check_Matrix (Victim.Invert, 1.0, 0.0, 0.0, -1.0, -2.0, 3.0, 0.0,
                    "inverse of a mirror");

      Section ("invert, extreme scales");
      --  Entries up to 1.0E150 are accepted. A matrix whose inverse is
      --  within that bound has a determinant of at least about 2.5E-301,
      --  far from the subnormal range, so these invert with full
      --  precision however small, large or anisotropic the entries are.
      Check_Inverse (Create (1.0E150, 0.0, 0.0, 1.0E150, 0.0, 0.0),
                     1.0E-150, 0.0, 0.0, 1.0E-150, 0.0, 0.0,
                     "huge matrix (determinant 1.0E300)");
      Check_Inverse (Create (1.0E150, 0.0, 0.0, 1.0E150, 3.0E149, -2.0E149),
                     1.0E-150, 0.0, 0.0, 1.0E-150, -0.3, 0.2,
                     "huge matrix with translation");
      Check_Inverse (Create (1.0E-150, 0.0, 0.0, 1.0E-150, 0.0, 0.0),
                     1.0E150, 0.0, 0.0, 1.0E150, 0.0, 0.0,
                     "tiny matrix (determinant 1.0E-300), inverse at the "
                     & "bound");
      Check_Inverse (Create (1.2E-140, -1.6E-140, 1.6E-140, 1.2E-140,
                             0.0, 0.0),
                     3.0E139, 4.0E139, -4.0E139, 3.0E139, 0.0, 0.0,
                     "similarity of scale 2.0E-140, rotation atan (4/3)");
      declare
         Turn : constant Ks_Transform_2D_Linear :=
           Create_Similarity (2.0E-140, EF.Arctan (4.0, 3.0), 0.0, 0.0);
      begin
         Inverse := Turn.Invert;
         Check (Turn.Compose (Inverse).Identity (1.0E-12)
                and then Inverse.Compose (Turn).Identity (1.0E-12),
                "Create_Similarity (2.0E-140, atan (4/3)) inverts");
      exception
         when E : others =>
            Fail_With (E, "Create_Similarity (2.0E-140, atan (4/3))");
      end;
      Check_Inverse (Create (1.0E10, 0.0, 0.0, 1.0E-140, 0.0, 0.0),
                     1.0E-10, 0.0, 0.0, 1.0E140, 0.0, 0.0,
                     "anisotropic diag (1.0E10, 1.0E-140)");
      Check_Inverse (Create (1.0, 1.0E-140, 1.0, 2.0E-140, 0.0, 0.0),
                     2.0, -1.0, -1.0E140, 1.0E140, 0.0, 0.0,
                     "rows that differ only far below their largest entry");
      --  Dividing a matrix by a power of two multiplies its inverse by
      --  the same power, exactly.
      declare
         Scale : constant Real := 2.0 ** 400;
         Big   : constant Ks_Transform_2D_Linear :=
           Create (Scale, 2.0 * Scale, 3.0 * Scale, 4.0 * Scale, 0.0, 0.0);
         Small : constant Ks_Transform_2D_Linear :=
           Create (1.0 / Scale, 2.0 / Scale, 3.0 / Scale, 4.0 / Scale,
                   0.0, 0.0);
      begin
         Check_Matrix (Big.Invert, -2.0 / Scale, 1.0 / Scale, 1.5 / Scale,
                       -0.5 / Scale, 0.0, 0.0, 0.0,
                       "2**400 times a general matrix");
         Check_Matrix (Small.Invert, -2.0 * Scale, 1.0 * Scale, 1.5 * Scale,
                       -0.5 * Scale, 0.0, 0.0, 0.0,
                       "2**-400 times a general matrix");
      exception
         when E : others =>
            Fail_With (E, "general matrix scaled by 2**(+/-400)");
      end;

      Section ("invert, singular");
      Victim := Create (1.0, 2.0, 2.0, 4.0, 0.0, 0.0);
      Check_Invert_Raises ("rank one matrix");
      Victim := Create (0.0, 0.0, 0.0, 0.0, 1.0, 1.0);
      Check_Invert_Raises ("zero matrix");
      Victim := Create (1.0, 0.0, 0.0, 0.0, 0.0, 0.0);
      Check_Invert_Raises ("zero scaling in y");
      Victim := Create (1.0E-300, 1.0E-300, 1.0E-300, 1.0E-300, 0.0, 0.0);
      Check_Invert_Raises ("tiny rank one matrix");
      Victim := Create (1.0E149, 2.0E149, 2.0E149, 4.0E149, 0.0, 0.0);
      Check_Invert_Raises ("huge rank one matrix");
      --  Inverses beyond the bound of 1.0E150 are reported as singular.
      Victim := Create (1.0E-300, 0.0, 0.0, 1.0, 1.0E10, 0.0);
      Check_Invert_Raises ("inverse 1.0E300 exceeds the bound");
      Victim := Create (0.9E-150, 0.0, 0.0, 0.9E-150, 0.0, 0.0);
      Check_Invert_Raises ("inverse 1.1E150 just exceeds the bound");
      Victim := Create (1.0, 0.0, 0.0, 1.0E-160, 0.0, 0.0);
      Check_Invert_Raises ("anisotropic inverse 1.0E160 exceeds the bound");
      Victim := Create (1.0, 1.0E-300, 1.0, 2.0E-300, 0.0, 0.0);
      Check_Invert_Raises ("nearly parallel rows, inverse 1.0E300");
      Victim := Create (Tiny * Tiny, 0.0, 0.0, Tiny * Tiny, 0.0, 0.0);
      Check_Invert_Raises ("subnormal entries, determinant 0");
      Victim := Create (1.0E-75, 0.0, 0.0, 1.0E-75, 1.0E100, 0.0);
      Check_Invert_Raises ("inverse translation 1.0E175 exceeds the bound");
      Victim := Create (1.0E-150, 0.0, 0.0, 1.0E-150, 0.0, 0.0);
      Do_Invert;
      Check_Near (Sink.Scaling_X / 1.0E150, 1.0, Tol,
                  "inverse at the bound is accepted");
      --  Arguments beyond the bound are rejected before anything else.
      declare
         procedure Invert_Huge is
         begin
            Sink := Create (1.0E200, 0.0, 0.0, 1.0E200, 0.0, 0.0).Invert;
         end Invert_Huge;
         procedure Check_Huge is new Check_Raises_Exactly
           (Invert_Huge, Ks_Bad_Parameter_Exception'Identity);
      begin
         Check_Huge ("Invert of entries 1.0E200 is a bad parameter");
      end;

      Section ("determinant bounds");
      Check_Near
        (Create (1.0E150, 0.0, 0.0, 1.0E150, 0.0, 0.0).Matrix_Determinant
           / 1.0E300, 1.0, Tol,
         "Matrix_Determinant of diag (1.0E150) is 1.0E300");
      Victim := Create (1.0E200, 0.0, 0.0, 1.0E200, 0.0, 0.0);
      Check_Matrix_Determinant_Rejected
        ("Matrix_Determinant of diag (1.0E200) is a bad parameter");

      Section ("compose");
      declare
         Shift : constant Ks_Transform_2D_Linear :=
           Create (1.0, 0.0, 0.0, 1.0, 1.0, 0.0);
         Turn  : constant Ks_Transform_2D_Linear :=
           Create_Rigid (Pi / 2.0, 0.0, 0.0);
         Other : constant Ks_Transform_2D_Linear :=
           Create (-1.0, 0.5, 2.0, 3.0, -4.0, 0.25);
         Composed : Ks_Transform_2D_Linear;
         OX, OY, TX, TY : Real;
      begin
         Check_Point (Shift.Compose (Turn), 1.0, 0.0, 1.0, 1.0, Tol,
                      "shift after turn");
         Check_Point (Turn.Compose (Shift), 1.0, 0.0, 0.0, 2.0, Tol,
                      "turn after shift");
         Check_Same_Matrix (Shift * Turn, Shift.Compose (Turn), 0.0,
                            """*"" is Compose");

         Composed := General.Compose (Other);
         Other.Map_Point (1.5, -2.5, OX, OY);
         General.Map_Point (OX, OY, TX, TY);
         Check_Point (Composed, 1.5, -2.5, TX, TY, Tol,
                      "Compose applies Other first");
         Check_Near
           (Composed.Matrix_Determinant,
            General.Matrix_Determinant * Other.Matrix_Determinant, Tol,
            "det of a product");
         Check_Same_Matrix (General.Compose (Identity), General, 0.0,
                            "right identity");
         Check_Same_Matrix (Identity.Compose (General), General, 0.0,
                            "left identity");
         Check_Same_Matrix
           (Create_Rigid (0.4, 0.0, 0.0) * Create_Rigid (0.5, 0.0, 0.0),
            Create_Rigid (0.9, 0.0, 0.0), Tol, "rotations add");
         Check_Same_Matrix
           ((General * Other) * Turn, General * (Other * Turn), Tol,
            "associative");
      end;
   end Test_Invert_And_Compose;

   procedure Test_Predicates is
   begin
      Section ("tolerance predicates");
      Check (Create (1.0 + 1.0E-13, 0.0, 0.0, 1.0, 0.0, 0.0).Identity,
             "Identity within default tolerance");
      Check (not Create (1.0 + 1.0E-11, 0.0, 0.0, 1.0, 0.0, 0.0).Identity,
             "Identity outside default tolerance");
      Check (not Create (1.0, 0.0, 0.0, 1.0, 0.0, 1.0E-11).Identity,
             "Identity looks at the translation");
      Check (Create (1.0, 0.0, 1.0E-11, 1.0, 1.0E-11, 0.0).Identity
               (1.0E-10),
             "Identity with a custom tolerance");
      Check (not Create (1.0, 0.0, 0.0, 1.0, 0.0, 1.0E-11).Identity (0.0),
             "Identity with zero tolerance");

      Check (Create_Similarity (3.0, 0.7, 5.0, 6.0).Is_Similarity,
             "similarity");
      Check (Create_Rigid (-2.0, 1.0, 1.0).Is_Similarity, "rigid");
      Check (Create_Scaling_Aspect_Rotation_Skew_Translation
               (3.0, 1.0 + 1.0E-12, 0.7, 0.0, 0.0, 0.0).Is_Similarity,
             "aspect within tolerance");
      Check (not Create_Scaling_Aspect_Rotation_Skew_Translation
               (3.0, 1.001, 0.7, 0.0, 0.0, 0.0).Is_Similarity,
             "aspect outside tolerance");
      Check (Create_Scaling_Aspect_Rotation_Skew_Translation
               (3.0, 1.001, 0.7, 0.0, 0.0, 0.0).Is_Similarity (1.0E-2),
             "aspect within a custom tolerance");
      Check (not Create_Scaling_Aspect_Rotation_Skew_Translation
               (3.0, 1.0, 0.7, 1.0E-3, 0.0, 0.0).Is_Similarity,
             "skew is no similarity");
      Check (not Create (1.0, 0.0, 0.0, -1.0, 0.0, 0.0).Is_Similarity,
             "reflection is no similarity");
      Check (Create (-1.0, 0.0, 0.0, -1.0, 0.0, 0.0).Is_Similarity,
             "half turn is a similarity");
      Check (not Create (0.0, 0.0, 0.0, 0.0, 0.0, 0.0).Is_Similarity,
             "zero matrix is no similarity");
      Check (Create (1.0E6, 1.0E-4, -1.0E-4, 1.0E6 + 1.0E-4, 0.0, 0.0)
               .Is_Similarity,
             "similarity tolerance is relative (large)");
      Check (Create_Similarity (1.0E-12, 1.0, 0.0, 0.0).Is_Similarity,
             "similarity tolerance is relative (small)");
      Check (not Create (1.0E-12, 0.0, 0.0, 2.0E-12, 0.0, 0.0).Is_Similarity,
             "small anisotropic scaling is no similarity");

      Check (Create (2.0, 0.0, 0.0, -3.0, 1.0, 1.0).Is_Axis_Aligned,
             "axis aligned with mirror");
      Check (Create (2.0, 1.0E-10, 0.0, 3.0, 0.0, 0.0).Is_Axis_Aligned,
             "axis aligned within tolerance");
      Check (not Create (2.0, 1.0E-6, 0.0, 3.0, 0.0, 0.0).Is_Axis_Aligned,
             "B outside tolerance");
      Check (not Create (2.0, 0.0, -1.0E-6, 3.0, 0.0, 0.0).Is_Axis_Aligned,
             "C outside tolerance");
      Check (Create (1.0E6, 1.0E-4, 0.0, 1.0E6, 0.0, 0.0).Is_Axis_Aligned,
             "axis aligned tolerance is relative");
      Check (not Create (1.0E-6, 1.0E-12, 0.0, 1.0E-6, 0.0, 0.0)
               .Is_Axis_Aligned (1.0E-9),
             "relative tolerance on a small matrix");
      Check (Create_Rigid (Pi, 0.0, 0.0).Is_Axis_Aligned,
             "half turn is axis aligned");
      Check (not Create_Rigid (Pi / 2.0, 0.0, 0.0).Is_Axis_Aligned,
             "quarter turn is not axis aligned");
      Check (Create (0.0, 0.0, 0.0, 0.0, 0.0, 0.0).Is_Axis_Aligned,
             "zero matrix is axis aligned");
   end Test_Predicates;

   procedure Test_Matrix_Elements is
      T      : Ks_Transform_2D_Linear :=
        Create (2.0, 3.0, 5.0, 7.0, 11.0, 13.0);
      Before : Ks_Transform_2D_Linear;
      Row    : Integer := 0;
      Column : Integer := 0;
      Value  : Real := 0.0;

      procedure Get is
      begin
         if T.Get_Matrix_Element (Row, Column) = Real'Last then
            Fail ("impossible matrix element");
         end if;
      end Get;

      procedure Set is
      begin
         T.Set_Matrix_Element (Row, Column, Value);
      end Set;

      procedure Check_Get_Rejected is new Check_Raises_Exactly
        (Get, Ks_Bad_Parameter_Exception'Identity);
      procedure Check_Set_Rejected is new Check_Raises_Exactly
        (Set, Ks_Bad_Parameter_Exception'Identity);

      type Index_Pair is record
         Row, Column : Integer;
      end record;

      Bad_Indices : constant array (Positive range <>) of Index_Pair :=
        [(-1, 0), (2, 0), (0, -1), (0, 2), (1, 2), (Integer'First, 0),
         (0, Integer'Last), (Integer'Last, Integer'First)];
   begin
      Section ("matrix elements by index");
      Check (T.Get_Matrix_Element (0, 0) = 2.0, "element (0, 0) is A");
      Check (T.Get_Matrix_Element (0, 1) = 3.0, "element (0, 1) is B");
      Check (T.Get_Matrix_Element (1, 0) = 5.0, "element (1, 0) is C");
      Check (T.Get_Matrix_Element (1, 1) = 7.0, "element (1, 1) is D");
      Check (Identity.Get_Matrix_Element (1, 1) = 1.0
             and then Identity.Get_Matrix_Element (1, 0) = 0.0,
             "elements of the identity");

      T.Set_Matrix_Element (0, 0, -1.5);
      Check_Matrix (T, -1.5, 3.0, 5.0, 7.0, 11.0, 13.0, 0.0,
                    "Set_Matrix_Element (0, 0)");
      T.Set_Matrix_Element (0, 1, 0.25);
      T.Set_Matrix_Element (1, 0, -8.0);
      T.Set_Matrix_Element (1, 1, 1.0E150);
      Check_Matrix (T, -1.5, 0.25, -8.0, 1.0E150, 11.0, 13.0, 0.0,
                    "Set_Matrix_Element of every element");
      Check (T.Get_Matrix_Element (1, 1) = 1.0E150,
             "an element at the bound reads back");

      --  Indices outside 0 .. 1 raise Ks_Bad_Parameter_Exception and
      --  leave the transform alone.
      Before := T;
      for Pair of Bad_Indices loop
         Row := Pair.Row;
         Column := Pair.Column;
         Value := 4.0;
         Check_Get_Rejected
           ("Get_Matrix_Element (" & Pair.Row'Image & ","
            & Pair.Column'Image & ")");
         Check_Set_Rejected
           ("Set_Matrix_Element (" & Pair.Row'Image & ","
            & Pair.Column'Image & ")");
         Check_Same_Matrix (T, Before, 0.0,
                            "a rejected index changes nothing");
      end loop;
      begin
         Row := 2;
         Get;
         Fail ("Get_Matrix_Element (2, 0): no exception");
      exception
         when E : Ks_Bad_Parameter_Exception =>
            Check (Ada.Exceptions.Exception_Message (E)
                     = "Row must be 0 or 1",
                   "the message names Row");
      end;
      begin
         Row := 1;
         Column := 7;
         Set;
         Fail ("Set_Matrix_Element (1, 7): no exception");
      exception
         when E : Ks_Bad_Parameter_Exception =>
            Check (Ada.Exceptions.Exception_Message (E)
                     = "Column must be 0 or 1",
                   "the message names Column");
      end;

      --  Values beyond the bound are rejected, and so are transforms
      --  with an entry beyond it (stored by Create, checked on use).
      Row := 0;
      Column := 1;
      Value := 2.0E150;
      Check_Set_Rejected ("Set_Matrix_Element of a value beyond 1.0E150");
      Check_Same_Matrix (T, Before, 0.0, "a rejected value changes nothing");
      T := Create (1.0, 0.0, 0.0, 1.0, 1.0E200, 0.0);
      Value := 1.0;
      Check_Get_Rejected ("Get_Matrix_Element of an unbounded transform");
      Check_Set_Rejected ("Set_Matrix_Element of an unbounded transform");

      Section ("matrix elements and translation");
      declare
         A, B, C, D, Tx, Ty : Real;
      begin
         T.Set_Matrix_Elements_Translation (1.0, 2.0, 3.0, 4.0, 5.0, 6.0);
         T.Get_Matrix_Elements_Translation (A, B, C, D, Tx, Ty);
         Check (A = 1.0 and then B = 2.0 and then C = 3.0 and then D = 4.0
                and then Tx = 5.0 and then Ty = 6.0,
                "Get_Matrix_Elements_Translation after "
                & "Set_Matrix_Elements_Translation");
         Check (A = T.Get_Matrix_Element (0, 0)
                and then B = T.Get_Matrix_Element (0, 1)
                and then C = T.Get_Matrix_Element (1, 0)
                and then D = T.Get_Matrix_Element (1, 1),
                "elem00, elem01, elem10, elem11 are A, B, C, D");
         --  The setter stores without checking, like Create.
         T.Set_Matrix_Elements_Translation
           (1.0E200, 0.0, 0.0, 1.0, 0.0, 0.0);
         T.Get_Matrix_Elements_Translation (A, B, C, D, Tx, Ty);
         Check (A = 1.0E200, "an unbounded value is stored as given");
      end;
   end Test_Matrix_Elements;

   procedure Test_Area_And_Tests is
      T     : Ks_Transform_2D_Linear;
      Area  : Real := 0.0;
      Tol_V : Real := 0.0;

      procedure Map is
      begin
         if T.Map_Area (Area) = Real'Last then
            Fail ("impossible mapped area");
         end if;
      end Map;

      procedure Singular_Test is
      begin
         if T.Singular (Tol_V) and then Tol_V < 0.0 then
            Fail ("a negative tolerance accepted");
         end if;
      end Singular_Test;

      procedure Matrix_Identity_Test is
      begin
         if T.Matrix_Identity (Tol_V) and then Tol_V < 0.0 then
            Fail ("a negative tolerance accepted");
         end if;
      end Matrix_Identity_Test;

      procedure Check_Map_Rejected is new Check_Raises_Exactly
        (Map, Ks_Bad_Parameter_Exception'Identity);
      procedure Check_Singular_Rejected is new Check_Raises_Exactly
        (Singular_Test, Ks_Bad_Parameter_Exception'Identity);
      procedure Check_Matrix_Identity_Rejected is new Check_Raises_Exactly
        (Matrix_Identity_Test, Ks_Bad_Parameter_Exception'Identity);
   begin
      Section ("Map_Area");
      T := Create (2.0, 0.0, 0.0, 3.0, 50.0, -7.0);
      Check (T.Map_Area (1.5) = 9.0, "Map_Area of diag (2, 3)");
      Check (T.Map_Area (0.0) = 0.0, "Map_Area of a zero area");
      Check (T.Map_Area (-4.0) = -24.0, "a negative area keeps its sign");
      Check (Create (1.0, 0.0, 0.0, -1.0, 0.0, 0.0).Map_Area (5.0) = 5.0,
             "a mirror keeps areas (abs det)");
      Check_Near (Create_Rigid (0.7, 3.0, 4.0).Map_Area (12.5), 12.5, Tol,
                  "a rigid transform keeps areas");
      Check_Near (Create_Similarity (3.0, -1.2, 0.0, 0.0).Map_Area (2.0),
                  18.0, Tol, "a similarity scales areas by its square");
      Check_Near
        (Create_Scaling_Aspect_Rotation_Skew_Translation
           (2.0, 0.5, 0.3, -0.2, 5.0, 6.0).Map_Area (10.0),
         10.0 * abs Create_Scaling_Aspect_Rotation_Skew_Translation
                      (2.0, 0.5, 0.3, -0.2, 5.0, 6.0).Matrix_Determinant,
         Tol, "Map_Area = abs Matrix_Determinant * Area");
      --  A unit square maps to the parallelogram of the two columns.
      declare
         General : constant Ks_Transform_2D_Linear :=
           Create (1.0, 2.0, 3.0, -4.0, 0.0, 0.0);
      begin
         Check (General.Map_Area (1.0) = 10.0,
                "a unit square maps to |det| = 10");
      end;
      Check (Create (0.0, 0.0, 0.0, 0.0, 1.0, 1.0).Map_Area (7.0) = 0.0,
             "a zero matrix maps every area to 0");
      T := Create (1.0E150, 0.0, 0.0, 1.0E150, 0.0, 0.0);
      Check_Near (T.Map_Area (1.0E-150) / 1.0E150, 1.0, Tol,
                  "det 1.0E300 with area 1.0E-150 gives 1.0E150");
      Area := 1.0E-149;
      Check_Map_Rejected ("det 1.0E300 with area 1.0E-149 exceeds 1.0E150");
      Area := 2.0;
      Check_Map_Rejected ("det 1.0E300 with area 2 exceeds 1.0E150");
      T := Create (2.0, 0.0, 0.0, 3.0, 0.0, 0.0);
      Area := 1.0E151;
      Check_Map_Rejected ("an area beyond 1.0E150");
      T := Create (1.0E200, 0.0, 0.0, 1.0, 0.0, 0.0);
      Area := 1.0;
      Check_Map_Rejected ("a transform beyond the bound");

      Section ("Singular");
      Check (Create (1.0, 2.0, 2.0, 4.0, 3.0, 3.0).Singular (0.0),
             "a rank one matrix is singular with tolerance 0");
      Check (Create (0.0, 0.0, 0.0, 0.0, 0.0, 0.0).Singular (0.0),
             "the zero matrix is singular");
      Check (not Identity.Singular (0.0), "the identity is not singular");
      Check (not Identity.Singular (0.999), "det 1 > 0.999");
      Check (Identity.Singular (1.0), "det 1 <= 1 (absolute tolerance)");
      T := Create (1.0, 0.0, 0.0, 1.0E-10, 0.0, 0.0);
      Check (T.Singular (1.0E-9), "det 1.0E-10 within 1.0E-9");
      Check (not T.Singular (1.0E-11), "det 1.0E-10 outside 1.0E-11");
      Check (Create (-2.0, 0.0, 0.0, 3.0, 0.0, 0.0).Singular (6.0)
             and then not Create (-2.0, 0.0, 0.0, 3.0, 0.0, 0.0)
                            .Singular (5.9),
             "a negative determinant is compared by its magnitude");
      T := Create (1.0E-170, 0.0, 0.0, 1.0E-170, 0.0, 0.0);
      Check (T.Singular (0.0),
             "a determinant that underflows to 0 is singular");
      T := Identity;
      Tol_V := -1.0;
      Check_Singular_Rejected ("Singular with a negative tolerance");
      Tol_V := 2.0E150;
      Check_Singular_Rejected ("Singular with a tolerance beyond 1.0E150");

      Section ("Identity and Matrix_Identity");
      Check (Identity.Identity, "Identity (the constructor) is Identity");
      Check (Identity (Identity, 0.0) and then Identity.Identity (0.0),
             "both call forms of the test");
      T := Create (1.0, 0.0, 0.0, 1.0, 5.0, -3.0);
      Check (T.Matrix_Identity (0.0), "a translation is a matrix identity");
      Check (not T.Identity, "but not an identity");
      Check (T.Matrix_Identity, "Matrix_Identity with the default tolerance");
      T := Create (1.0 + 1.0E-13, -1.0E-13, 1.0E-13, 1.0 - 1.0E-13,
                   0.0, 0.0);
      Check (T.Matrix_Identity and then T.Identity,
             "within the default tolerance 1.0E-12");
      Check (not T.Matrix_Identity (1.0E-14),
             "outside a tolerance of 1.0E-14");
      for Index in 0 .. 3 loop
         T := Identity;
         T.Set_Matrix_Element (Index / 2, Index mod 2,
                               T.Get_Matrix_Element (Index / 2, Index mod 2)
                               + 1.0E-6);
         Check (not T.Matrix_Identity (1.0E-7)
                and then T.Matrix_Identity (1.0E-5),
                "Matrix_Identity tests element" & Index'Image);
      end loop;
      Check (not Create_Rigid (Pi, 0.0, 0.0).Matrix_Identity (1.0),
             "a half turn is not a matrix identity");
      T := Identity;
      Tol_V := -1.0E-12;
      Check_Matrix_Identity_Rejected
        ("Matrix_Identity with a negative tolerance");
   end Test_Area_And_Tests;

   procedure Test_Misc is
      use AMV.Misc;

      --  Arguments far outside one turn. The finite ones near 1.0E17 and
      --  above came back out of range before Norm_Angle used the exact
      --  remainder (1.0E18 gave 121.7, -1.42181491743915E+308 gave about
      --  -2.0E292).
      Huge : constant array (Positive range <>) of Real :=
        [1.2E17, -1.2E17, 1.0E18, -1.0E18, 1.13367536548173E+17,
         -1.15022736026086E+17, 7.70613947559197E+18,
         8.20570375382666E+307, -1.42181491743915E+308, 1.0E100,
         Real'First, Real'Last];

      Argument : Real := 0.0;

      procedure Rad_To_Deg_Of_Argument is
      begin
         if Rad_To_Deg (Argument) = 0.5 then
            Fail ("impossible Rad_To_Deg");
         end if;
      end Rad_To_Deg_Of_Argument;

      procedure Check_Rad_To_Deg_Too_Large is new Check_Raises_Exactly
        (Rad_To_Deg_Of_Argument, Ks_Bad_Parameter_Exception'Identity);

      procedure Check_Pi_Range (Angle : Real; Description : String) is
      begin
         Check (Angle > -Pi / 2.0 and then Angle <= Pi / 2.0,
                Description & " in (-Pi/2, Pi/2]:" & Real'Image (Angle));
      end Check_Pi_Range;

      X           : Real;
      Samples     : Natural := 0;
      Out_Of_Range, Out_Of_Range_Pi, Out_Of_Range_Diff : Natural := 0;
   begin
      Section ("misc: angle conversions");
      for K in -8 .. 8 loop
         Check (Deg_To_Rad (45.0 * Real (K)) = Real (K) * Pi / 4.0,
                "Deg_To_Rad of" & Integer'Image (45 * K) & " deg is exact");
         Check (Rad_To_Deg (Real (K) * Pi / 4.0) = 45.0 * Real (K),
                "Rad_To_Deg of" & Integer'Image (K) & " Pi/4 is exact");
      end loop;
      Check_Near (Deg_To_Rad (1.0), 0.017453292519943295, 1.0E-18,
                  "one degree");
      Check_Near (Rad_To_Deg (1.0), 57.29577951308232, 1.0E-13,
                  "one radian");
      --  The constant factor is applied in one product, so a result that
      --  fits is computed even when Degrees * Pi or Radians * 180 would
      --  not.
      begin
         Check_Relative (Deg_To_Rad (Real'Last), (Real'Last / 180.0) * Pi,
                         1.0E-15, "Deg_To_Rad (Real'Last)");
         Check_Relative (Deg_To_Rad (-Real'Last), -(Real'Last / 180.0) * Pi,
                         1.0E-15, "Deg_To_Rad (-Real'Last)");
      exception
         when E : others =>
            Fail_With (E, "Deg_To_Rad near Real'Last");
      end;
      begin
         Check_Relative (Rad_To_Deg (2.0E306), (2.0E306 / Pi) * 180.0,
                         1.0E-15, "Rad_To_Deg (2.0E306)");
         Check_Relative (Rad_To_Deg (-3.0E306), (-3.0E306 / Pi) * 180.0,
                         1.0E-15, "Rad_To_Deg (-3.0E306)");
      exception
         when E : others =>
            Fail_With (E, "Rad_To_Deg near Real'Last / 57.3");
      end;
      --  Arguments above 3.1E306 in magnitude are rejected (documented).
      Check_Relative (Rad_To_Deg (3.1E306), (3.1E306 / Pi) * 180.0,
                      1.0E-15, "Rad_To_Deg (3.1E306), the largest accepted");
      Argument := Real'Last;
      Check_Rad_To_Deg_Too_Large ("Rad_To_Deg (Real'Last) is rejected");
      Argument := -4.0E306;
      Check_Rad_To_Deg_Too_Large ("Rad_To_Deg (-4.0E306) is rejected");

      Section ("misc: Norm_Angle boundaries");
      Check (Norm_Angle (Pi) = Pi, "Norm_Angle (Pi) is exactly Pi");
      Check (Norm_Angle (-Pi) = Pi, "Norm_Angle (-Pi) is exactly +Pi");
      Check (Norm_Angle_Pi (Pi / 2.0) = Pi / 2.0,
             "Norm_Angle_Pi (Pi/2) is exactly Pi/2");
      Check (Norm_Angle_Pi (-Pi / 2.0) = Pi / 2.0,
             "Norm_Angle_Pi (-Pi/2) is exactly +Pi/2");
      --  3 Pi and -3 Pi round to Reals near, not at, odd multiples of the
      --  machine Pi, so only the side of the seam is predictable.
      Check_Angle_Near (Norm_Angle (3.0 * Pi), Pi, 1.0E-15,
                        "Norm_Angle (3 Pi)");
      Check_Angle_Near (Norm_Angle (-3.0 * Pi), Pi, 1.0E-15,
                        "Norm_Angle (-3 Pi)");
      Check (Norm_Angle_Pi (Pi) = 0.0, "Norm_Angle_Pi (Pi) is 0");
      Check (Is_Positive_Zero (Norm_Angle (2.0 * Pi)),
             "Norm_Angle (2 Pi) is +0.0");
      Check (Is_Positive_Zero (Norm_Angle (-2.0 * Pi)),
             "Norm_Angle (-2 Pi) is +0.0, not -0.0");
      Check (Is_Positive_Zero (Norm_Angle (-4.0 * Pi)),
             "Norm_Angle (-4 Pi) is +0.0");
      Check (Is_Positive_Zero (Norm_Angle_Pi (-Pi)),
             "Norm_Angle_Pi (-Pi) is +0.0, not -0.0");
      Check (Is_Positive_Zero (Norm_Angle_Pi (-4.0 * Pi)),
             "Norm_Angle_Pi (-4 Pi) is +0.0");
      for In_Range of Real_Array'[0.0, 1.0, -1.0, 3.0, -3.0, Pi, 2.5E-300,
                                  -Pi + 1.0E-15]
      loop
         Check (Norm_Angle (In_Range) = In_Range,
                "Norm_Angle keeps" & Real'Image (In_Range));
      end loop;
      for In_Range of Real_Array'[0.0, 1.0, -1.0, 1.5, Pi / 2.0] loop
         Check (Norm_Angle_Pi (In_Range) = In_Range,
                "Norm_Angle_Pi keeps" & Real'Image (In_Range));
      end loop;

      Section ("misc: Norm_Angle of moderate values");
      Check_Near (Norm_Angle (7.0), 7.0 - 2.0 * Pi, 1.0E-15, "7 rad");
      Check_Near (Norm_Angle (-7.0), -7.0 + 2.0 * Pi, 1.0E-15, "-7 rad");
      Check_Near (Norm_Angle (1000.0), 1000.0 - 318.0 * Pi, 1.0E-12,
                  "1000 rad");
      Check_Near (Norm_Angle (-1000.0), -1000.0 + 318.0 * Pi, 1.0E-12,
                  "-1000 rad");
      Check_Near (Norm_Angle_Pi (3.0), 3.0 - Pi, 1.0E-15, "Pi range, 3");
      Check_Near (Norm_Angle_Pi (-2.0), -2.0 + Pi, 1.0E-15, "Pi range, -2");
      Check_Near (Norm_Angle_Pi (100.0), 100.0 - 32.0 * Pi, 1.0E-13,
                  "Pi range, 100");
      Check_Near (Angle_Difference (0.1, 2.0 * Pi - 0.1), 0.2, 1.0E-15,
                  "Angle_Difference across the seam");

      Section ("misc: Norm_Angle range for huge arguments");
      for H of Huge loop
         Check_In_Angle_Range (Norm_Angle (H),
                               "Norm_Angle of" & Real'Image (H));
         Check_Pi_Range (Norm_Angle_Pi (H),
                         "Norm_Angle_Pi of" & Real'Image (H));
         Check_In_Angle_Range (Angle_Difference (H, 0.0),
                               "Angle_Difference of" & Real'Image (H));
      end loop;
      --  A geometric sweep over every binade up to Real'Last, both signs
      --  (one check per function, counting the violations).
      X := 1.0;
      while X < Real'Last / 1.01 loop
         X := X * 1.01;
         for Sign of Real_Array'[1.0, -1.0] loop
            Samples := Samples + 1;
            declare
               N  : constant Real := Norm_Angle (Sign * X);
               NP : constant Real := Norm_Angle_Pi (Sign * X);
               ND : constant Real := Angle_Difference (Sign * X, 0.5);
            begin
               if not (N > -Pi and then N <= Pi) then
                  Out_Of_Range := Out_Of_Range + 1;
               end if;
               if not (NP > -Pi / 2.0 and then NP <= Pi / 2.0) then
                  Out_Of_Range_Pi := Out_Of_Range_Pi + 1;
               end if;
               if not (ND > -Pi and then ND <= Pi) then
                  Out_Of_Range_Diff := Out_Of_Range_Diff + 1;
               end if;
            end;
         end loop;
      end loop;
      Check (Samples > 100_000, "sweep size" & Natural'Image (Samples));
      Check (Out_Of_Range = 0, "sweep: Norm_Angle out of range"
             & Natural'Image (Out_Of_Range) & " times");
      Check (Out_Of_Range_Pi = 0, "sweep: Norm_Angle_Pi out of range"
             & Natural'Image (Out_Of_Range_Pi) & " times");
      Check (Out_Of_Range_Diff = 0, "sweep: Angle_Difference out of range"
             & Natural'Image (Out_Of_Range_Diff) & " times");
   end Test_Misc;

   procedure Run_All is
   begin
      Test_Misc;
      Test_Defaults;
      Test_Constructors;
      Test_Setters;
      Test_Composite;
      Test_Reflections_And_Degenerate;
      Test_Mapping;
      Test_Map_Angle_Singular;
      Test_Invert_And_Compose;
      Test_Predicates;
      Test_Matrix_Elements;
      Test_Area_And_Tests;
   end Run_All;

   procedure Main is new AMV_Test_Support.Standalone (Run_All);
begin
   Main;
end Test_Transforms;
