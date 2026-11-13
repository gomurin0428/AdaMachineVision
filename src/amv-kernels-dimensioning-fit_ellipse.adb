pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Numerics.Long_Elementary_Functions;

with AMV.Kernels.Numerics;

package body AMV.Kernels.Dimensioning.Fit_Ellipse with SPARK_Mode is

   package N renames AMV.Kernels.Numerics;
   package EF renames Ada.Numerics.Long_Elementary_Functions;

   subtype Coordinate is Long_Float range -Max_Value .. Max_Value;
   subtype Unit is Long_Float range -1.0 .. 1.0;
   subtype Scale_Value is Long_Float range 0.0 .. 4.0 * Max_Value;

   --  Bounds of the intermediate quantities. Each one follows from the
   --  ones before it: an entry of inv (S3) is formed only below
   --  Inverse_Limit, an entry of T is a sum of three products of such an
   --  entry with a moment (at most 1), an entry of M a moment plus three
   --  products of a moment with an entry of T, an entry of M - Lambda C1
   --  at most M_Limit + 2 M_Limit (Lambda lies in [0, M_Limit]), and so
   --  on. They hold whatever the points; for well spread points every
   --  quantity is of the order of 1.

   Inverse_Limit     : constant := 2.0 ** 90;
   T_Limit           : constant := 2.0 ** 92;
   M_Limit           : constant := 2.0 ** 94;
   N_Limit           : constant := 2.0 ** 96;
   Cross_Limit       : constant := 2.0 ** 193;
   Coefficient_Limit : constant := 2.0 ** 94;
   Constant_Limit    : constant := 2.0 ** 126;
   Centre_Limit      : constant := 2.0 ** 30;
   Square_Limit      : constant := 2.0 ** 60;
   Sum_Limit         : constant := 2.0 ** 21;
   Coordinate_Sum    : constant := 2.0 ** 521;

   subtype Inverse_Value is Long_Float range -Inverse_Limit .. Inverse_Limit;
   subtype T_Value is Long_Float range -T_Limit .. T_Limit;
   subtype M_Value is Long_Float range -M_Limit .. M_Limit;
   subtype N_Value is Long_Float range -N_Limit .. N_Limit;
   subtype Cross_Value is Long_Float range -Cross_Limit .. Cross_Limit;
   subtype Coefficient_Value is
     Long_Float range -Coefficient_Limit .. Coefficient_Limit;
   subtype Centre_Value is Long_Float range -Centre_Limit .. Centre_Limit;
   subtype Radius_Value is Long_Float range 0.0 .. Centre_Limit;
   subtype Sum_Value is Long_Float range -Sum_Limit .. Sum_Limit;

   Collinear_Tolerance : constant := 1.0E-14;
   Bisection_Tolerance : constant := 2.0 ** (-60);
   Max_Bisection_Steps : constant := 200;

   type Reason is
     (Fitted, Too_Few, Coincident, Collinear, No_Ellipse, Too_Large,
      Out_Of_Bound);
   --  The outcome of one fit.

   function Read (X : Long_Float) return Coordinate is
     (N.Clamp (X, Max_Value));
   --  A coordinate of a point, limited to the bound (the points come from
   --  a polygon handle, whose vertices lie within it, so this never acts).

   ---------------------------------------------------------------------
   --  Frame: the centroid, the rotation and the scale
   ---------------------------------------------------------------------

   type Frame is record
      CX, CY : Coordinate := 0.0;
      Cos_R  : Unit := 1.0;
      Sin_R  : Unit := 0.0;
      Scale  : Scale_Value := 0.0;
      Count  : Natural := 0;
   end record;
   --  The centroid of the points in use, the cosine and sine of the
   --  rotation (1 and 0 without a constraint), the largest offset of a
   --  point from the centroid in the turned frame, and the number of
   --  points in use.

   procedure Offset_Of
     (Q    : KG.Ks_Point_2D;
      F    : Frame;
      U, V : out Long_Float)
   with Post => abs U <= 4.0 * Max_Value and then abs V <= 4.0 * Max_Value;
   --  Q - centroid, turned by minus the rotation.

   procedure Offset_Of
     (Q    : KG.Ks_Point_2D;
      F    : Frame;
      U, V : out Long_Float)
   is
      DX : constant Long_Float := Read (Q.X) - F.CX;
      DY : constant Long_Float := Read (Q.Y) - F.CY;
   begin
      U := N.Times_Unit (DX, F.Cos_R) + N.Times_Unit (DY, F.Sin_R);
      V := N.Times_Unit (DY, F.Cos_R) - N.Times_Unit (DX, F.Sin_R);
   end Offset_Of;

   procedure Make_Frame
     (Points       : KG.Point_Array;
      Active       : KG.Flag_Array;
      Cos_R, Sin_R : Unit;
      F            : out Frame)
   with
     Pre  => Points'First = 0 and then Points'Last < Max_Points
             and then Active'First = 0 and then Active'Last = Points'Last,
     Post => F.Count <= Max_Points;

   procedure Make_Frame
     (Points       : KG.Point_Array;
      Active       : KG.Flag_Array;
      Cos_R, Sin_R : Unit;
      F            : out Frame)
   is
      SX, SY : Long_Float := 0.0;
      U, V   : Long_Float;
   begin
      F := (CX => 0.0, CY => 0.0, Cos_R => Cos_R, Sin_R => Sin_R,
            Scale => 0.0, Count => 0);
      for I in Points'Range loop
         pragma Loop_Invariant
           (F.Count <= I and then abs SX <= Coordinate_Sum
            and then abs SY <= Coordinate_Sum
            and then F.Cos_R = Cos_R and then F.Sin_R = Sin_R);
         if Active (I) then
            --  At most 2**20 coordinates within 1.0E150: the limit never
            --  acts.
            SX := N.Clamp (SX + Read (Points (I).X), Coordinate_Sum);
            SY := N.Clamp (SY + Read (Points (I).Y), Coordinate_Sum);
            F.Count := F.Count + 1;
         end if;
      end loop;
      if F.Count = 0 then
         return;
      end if;
      F.CX := N.Clamp (SX / Long_Float (F.Count), Max_Value);
      F.CY := N.Clamp (SY / Long_Float (F.Count), Max_Value);
      for I in Points'Range loop
         pragma Loop_Invariant (F.Count <= Max_Points);
         if Active (I) then
            Offset_Of (Points (I), F, U, V);
            F.Scale := Long_Float'Max (F.Scale,
                                       Long_Float'Max (abs U, abs V));
         end if;
      end loop;
   end Make_Frame;

   ---------------------------------------------------------------------
   --  Moments
   ---------------------------------------------------------------------

   type Sum_Record is record
      S10, S01, S20, S11, S02, S30, S21, S12, S03 : Sum_Value := 0.0;
      S40, S31, S22, S13, S04                     : Sum_Value := 0.0;
   end record;

   type Moments is record
      M10, M01, M20, M11, M02, M30, M21, M12, M03 : Unit := 0.0;
      M40, M31, M22, M13, M04                     : Unit := 0.0;
   end record;
   --  The means of u**i v**j over the points in use, with (u, v) their
   --  offsets in the frame divided by the scale.

   procedure Add (S : in out Sum_Value; T : Unit) with Inline;
   --  S + T. A sum has at most 2**20 terms of at most 1, so its limit
   --  never acts.

   procedure Add (S : in out Sum_Value; T : Unit) is
   begin
      S := N.Clamp (S + T, Sum_Limit);
   end Add;

   function Mean (S : Sum_Value; Count : Positive) return Unit is
     (N.Clamp (S / Long_Float (Count), 1.0));
   --  S / Count, at most 1 in magnitude since every term is.

   procedure Normalized
     (Q      : KG.Ks_Point_2D;
      F      : Frame;
      UN, VN : out Unit)
   with Pre => F.Scale > 0.0;
   --  The offset of Q in the frame divided by the scale.

   procedure Normalized
     (Q      : KG.Ks_Point_2D;
      F      : Frame;
      UN, VN : out Unit)
   is
      U, V : Long_Float;
   begin
      Offset_Of (Q, F, U, V);
      UN := N.Unit_Ratio (N.Clamp (U, F.Scale), F.Scale);
      VN := N.Unit_Ratio (N.Clamp (V, F.Scale), F.Scale);
   end Normalized;

   procedure Compute_Moments
     (Points : KG.Point_Array;
      Active : KG.Flag_Array;
      F      : Frame;
      M      : out Moments)
   with
     Pre => Points'First = 0 and then Points'Last < Max_Points
            and then Active'First = 0 and then Active'Last = Points'Last
            and then F.Count >= 1 and then F.Scale > 0.0;

   procedure Compute_Moments
     (Points : KG.Point_Array;
      Active : KG.Flag_Array;
      F      : Frame;
      M      : out Moments)
   is
      S      : Sum_Record;
      UN, VN : Unit;
      U2, V2 : Unit;
      U3, V3 : Unit;
   begin
      for I in Points'Range loop
         if Active (I) then
            Normalized (Points (I), F, UN, VN);
            U2 := N.Square_Within (UN, 1.0);
            V2 := N.Square_Within (VN, 1.0);
            U3 := N.Times_Unit (U2, UN);
            V3 := N.Times_Unit (V2, VN);
            Add (S.S10, UN);
            Add (S.S01, VN);
            Add (S.S20, U2);
            Add (S.S11, N.Times_Unit (UN, VN));
            Add (S.S02, V2);
            Add (S.S30, U3);
            Add (S.S21, N.Times_Unit (U2, VN));
            Add (S.S12, N.Times_Unit (V2, UN));
            Add (S.S03, V3);
            Add (S.S40, N.Times_Unit (U2, U2));
            Add (S.S31, N.Times_Unit (U3, VN));
            Add (S.S22, N.Times_Unit (U2, V2));
            Add (S.S13, N.Times_Unit (V3, UN));
            Add (S.S04, N.Times_Unit (V2, V2));
         end if;
      end loop;
      M := (M10 => Mean (S.S10, F.Count), M01 => Mean (S.S01, F.Count),
            M20 => Mean (S.S20, F.Count), M11 => Mean (S.S11, F.Count),
            M02 => Mean (S.S02, F.Count), M30 => Mean (S.S30, F.Count),
            M21 => Mean (S.S21, F.Count), M12 => Mean (S.S12, F.Count),
            M03 => Mean (S.S03, F.Count), M40 => Mean (S.S40, F.Count),
            M31 => Mean (S.S31, F.Count), M22 => Mean (S.S22, F.Count),
            M13 => Mean (S.S13, F.Count), M04 => Mean (S.S04, F.Count));
   end Compute_Moments;

   ---------------------------------------------------------------------
   --  The reduced problem
   ---------------------------------------------------------------------

   procedure Signed_Quotient
     (X, Y   : Long_Float;
      Limit  : Long_Float;
      R      : out Long_Float;
      Fits   : out Boolean)
   with Pre  => abs X <= N.Mul_Limit and then Y > 0.0
                and then Y <= N.Mul_Limit
                and then Limit >= 1.0 and then Limit <= N.Mul_Limit,
        Post => abs R <= Limit;
   --  R := X / Y when that is at most Limit in magnitude (Fits True);
   --  otherwise Fits False and R := 0.

   procedure Signed_Quotient
     (X, Y   : Long_Float;
      Limit  : Long_Float;
      R      : out Long_Float;
      Fits   : out Boolean) is
   begin
      N.Ratio_Within (abs X, Y, Limit, R, Fits);
      if X < 0.0 then
         R := -R;
      end if;
   end Signed_Quotient;

   type Inverse_Matrix is array (1 .. 3, 1 .. 3) of Inverse_Value;
   type T_Matrix is array (1 .. 3, 1 .. 3) of T_Value;
   type M_Matrix is array (1 .. 3, 1 .. 3) of M_Value;
   type N_Matrix is array (1 .. 3, 1 .. 3) of N_Value;
   type Vector is array (1 .. 3) of Cross_Value;

   procedure Invert_Scatter
     (M   : Moments;
      Inv : out Inverse_Matrix;
      Why : out Reason)
   with Global => null, Post => True;
   --  inv (S3) for S3 = [M20 M11 M10; M11 M02 M01; M10 M01 1], from its
   --  cofactors; Collinear when its determinant is at most
   --  Collinear_Tolerance times the square of the trace of its upper 2 x 2
   --  block, or an entry of the inverse would exceed Inverse_Limit.

   procedure Invert_Scatter
     (M   : Moments;
      Inv : out Inverse_Matrix;
      Why : out Reason)
   is
      A   : constant Unit := M.M20;
      B   : constant Unit := M.M11;
      C   : constant Unit := M.M10;
      D   : constant Unit := M.M02;
      E   : constant Unit := M.M01;
      C11 : constant Long_Float := D - N.Times_Unit (E, E);
      C12 : constant Long_Float := N.Times_Unit (E, C) - B;
      C13 : constant Long_Float := N.Times_Unit (B, E) - N.Times_Unit (D, C);
      C22 : constant Long_Float := A - N.Times_Unit (C, C);
      C23 : constant Long_Float := N.Times_Unit (B, C) - N.Times_Unit (A, E);
      C33 : constant Long_Float := N.Times_Unit (A, D) - N.Times_Unit (B, B);
      Det : constant Long_Float :=
        N.Times_Unit (C11, A) + N.Times_Unit (C12, B)
        + N.Times_Unit (C13, C);
      Trace : constant Long_Float := Long_Float'Max (0.0, A + D);
      R11, R12, R13, R22, R23, R33 : Long_Float;
      F11, F12, F13, F22, F23, F33 : Boolean;
   begin
      Inv := [others => [others => 0.0]];
      if Det <= Collinear_Tolerance * N.Square_Within (Trace, 2.0) then
         Why := Collinear;
         return;
      end if;
      Signed_Quotient (C11, Det, Inverse_Limit, R11, F11);
      Signed_Quotient (C12, Det, Inverse_Limit, R12, F12);
      Signed_Quotient (C13, Det, Inverse_Limit, R13, F13);
      Signed_Quotient (C22, Det, Inverse_Limit, R22, F22);
      Signed_Quotient (C23, Det, Inverse_Limit, R23, F23);
      Signed_Quotient (C33, Det, Inverse_Limit, R33, F33);
      if not (F11 and then F12 and then F13 and then F22 and then F23
              and then F33)
      then
         Why := Collinear;
         return;
      end if;
      Inv := [[R11, R12, R13], [R12, R22, R23], [R13, R23, R33]];
      Why := Fitted;
   end Invert_Scatter;

   function T_Entry
     (I1, I2, I3 : Inverse_Value;
      S1, S2, S3 : Unit) return T_Value
   is
     (-(N.Mul_Within (I1, S1, Inverse_Limit, 1.0)
        + N.Mul_Within (I2, S2, Inverse_Limit, 1.0)
        + N.Mul_Within (I3, S3, Inverse_Limit, 1.0)));
   --  -(I1 S1 + I2 S2 + I3 S3): an entry of T = -inv (S3) S2'.

   function M_Entry
     (S0         : Unit;
      A1, A2, A3 : Unit;
      T1, T2, T3 : T_Value) return M_Value
   is
     (S0 + N.Mul_Within (A1, T1, 1.0, T_Limit)
      + N.Mul_Within (A2, T2, 1.0, T_Limit)
      + N.Mul_Within (A3, T3, 1.0, T_Limit));
   --  S0 + A1 T1 + A2 T2 + A3 T3: an entry of M = S1 + S2 T.

   function Coefficient
     (T1, T2, T3 : T_Value;
      A, B, C    : Unit) return Coefficient_Value
   is
     (N.Mul_Within (T1, A, T_Limit, 1.0) + N.Mul_Within (T2, B, T_Limit, 1.0)
      + N.Mul_Within (T3, C, T_Limit, 1.0));
   --  One of the coefficients (D, E, F) = T (A, B, C).

   function Average (X, Y : M_Value) return M_Value is (X / 2.0 + Y / 2.0);

   procedure Reduce
     (M   : Moments;
      Inv : Inverse_Matrix;
      T   : out T_Matrix;
      Red : out M_Matrix)
   with Global => null, Post => True;
   --  T = -inv (S3) S2' and the reduced scatter M = S1 + S2 T (made
   --  symmetric, as it is mathematically), for the rows (u**2, uv, v**2)
   --  of S1 and S2 and the columns (u, v, 1) of S2.

   procedure Reduce
     (M   : Moments;
      Inv : Inverse_Matrix;
      T   : out T_Matrix;
      Red : out M_Matrix)
   is
      S2 : constant array (1 .. 3, 1 .. 3) of Unit :=
        [[M.M30, M.M21, M.M20],
         [M.M21, M.M12, M.M11],
         [M.M12, M.M03, M.M02]];
      S1 : constant array (1 .. 3, 1 .. 3) of Unit :=
        [[M.M40, M.M31, M.M22],
         [M.M31, M.M22, M.M13],
         [M.M22, M.M13, M.M04]];
   begin
      T := [for K in 1 .. 3 =>
              [for J in 1 .. 3 =>
                 T_Entry (Inv (K, 1), Inv (K, 2), Inv (K, 3),
                          S2 (J, 1), S2 (J, 2), S2 (J, 3))]];
      Red := [for I in 1 .. 3 =>
                [for J in 1 .. 3 =>
                   M_Entry (S1 (I, J), S2 (I, 1), S2 (I, 2), S2 (I, 3),
                            T (1, J), T (2, J), T (3, J))]];
      Red (1, 2) := Average (Red (1, 2), Red (2, 1));
      Red (2, 1) := Red (1, 2);
      Red (1, 3) := Average (Red (1, 3), Red (3, 1));
      Red (3, 1) := Red (1, 3);
      Red (2, 3) := Average (Red (2, 3), Red (3, 2));
      Red (3, 2) := Red (2, 3);
   end Reduce;

   function Shifted (Red : M_Matrix; Lambda : Long_Float) return N_Matrix
   with Pre => Lambda >= 0.0 and then Lambda <= M_Limit;
   --  M - Lambda C1 (C1 has 2 at (1, 3) and (3, 1) and -1 at (2, 2)).

   function Shifted (Red : M_Matrix; Lambda : Long_Float) return N_Matrix
   is
     ([[Red (1, 1), Red (1, 2), Red (1, 3) - 2.0 * Lambda],
       [Red (2, 1), Red (2, 2) + Lambda, Red (2, 3)],
       [Red (3, 1) - 2.0 * Lambda, Red (3, 2), Red (3, 3)]]);

   function Product (X, Y : N_Value) return Long_Float is
     (N.Mul_Within (X, Y, N_Limit, N_Limit))
   with Post => abs Product'Result <= N_Limit * N_Limit;

   function Minor (A, B, C, D : N_Value) return Cross_Value is
     (Product (A, D) - Product (B, C));
   --  A D - B C.

   function Determinant (Mat : N_Matrix) return Long_Float is
     (N.Mul_Within (Mat (1, 1),
                    Minor (Mat (2, 2), Mat (2, 3), Mat (3, 2), Mat (3, 3)),
                    N_Limit, Cross_Limit)
      - N.Mul_Within (Mat (1, 2),
                      Minor (Mat (2, 1), Mat (2, 3), Mat (3, 1), Mat (3, 3)),
                      N_Limit, Cross_Limit)
      + N.Mul_Within (Mat (1, 3),
                      Minor (Mat (2, 1), Mat (2, 2), Mat (3, 1), Mat (3, 2)),
                      N_Limit, Cross_Limit));

   function Cross (Mat : N_Matrix; R1, R2 : Integer) return Vector
   with Pre => R1 in 1 .. 3 and then R2 in 1 .. 3;
   --  The cross product of rows R1 and R2.

   function Cross (Mat : N_Matrix; R1, R2 : Integer) return Vector is
     ([Minor (Mat (R1, 2), Mat (R1, 3), Mat (R2, 2), Mat (R2, 3)),
       Minor (Mat (R1, 3), Mat (R1, 1), Mat (R2, 3), Mat (R2, 1)),
       Minor (Mat (R1, 1), Mat (R1, 2), Mat (R2, 1), Mat (R2, 2))]);

   function Max_Abs (V : Vector) return Long_Float is
     (Long_Float'Max (abs V (1), Long_Float'Max (abs V (2), abs V (3))))
   with Post => Max_Abs'Result >= 0.0
                and then Max_Abs'Result <= Cross_Limit;

   procedure Eigenvector
     (Red     : M_Matrix;
      A, B, C : out Unit;
      Found   : out Boolean)
   with Global => null, Post => True;
   --  The eigenvector of M a = Lambda C1 a for the positive eigenvalue,
   --  scaled so that its largest component is 1 in magnitude.

   procedure Eigenvector
     (Red     : M_Matrix;
      A, B, C : out Unit;
      Found   : out Boolean)
   is
      Lo     : Long_Float := 0.0;
      Hi     : Long_Float;
      Mid    : Long_Float;
      Width  : Long_Float;
      Mat    : N_Matrix;
      V, W   : Vector;
      Big    : Long_Float;
   begin
      A := 0.0;
      B := 0.0;
      C := 0.0;
      --  The Rayleigh quotient of (1, 0, 1), whose constraint value is 4,
      --  bounds the eigenvalue from above.
      Hi := Long_Float'Max
        (0.0, Red (1, 1) / 4.0 + Red (1, 3) / 2.0 + Red (3, 3) / 4.0);
      Width := Bisection_Tolerance * Hi;
      for Step in 1 .. Max_Bisection_Steps loop
         pragma Loop_Invariant
           (Lo >= 0.0 and then Lo <= Hi and then Hi <= M_Limit);
         exit when Hi - Lo <= Width;
         Mid := Lo + (Hi - Lo) / 2.0;
         exit when Mid <= Lo or else Mid >= Hi;
         if Determinant (Shifted (Red, Mid)) > 0.0 then
            Lo := Mid;
         else
            Hi := Mid;
         end if;
      end loop;
      Mat := Shifted (Red, Hi);
      V := Cross (Mat, 1, 2);
      W := Cross (Mat, 1, 3);
      if Max_Abs (W) > Max_Abs (V) then
         V := W;
      end if;
      W := Cross (Mat, 2, 3);
      if Max_Abs (W) > Max_Abs (V) then
         V := W;
      end if;
      Big := Max_Abs (V);
      Found := Big > 0.0;
      if Found then
         A := N.Unit_Ratio (N.Clamp (V (1), Big), Big);
         B := N.Unit_Ratio (N.Clamp (V (2), Big), Big);
         C := N.Unit_Ratio (N.Clamp (V (3), Big), Big);
      end if;
   end Eigenvector;

   ---------------------------------------------------------------------
   --  From the conic to the ellipse (in the scaled frame)
   ---------------------------------------------------------------------

   type Scaled_Ellipse is record
      X0, Y0       : Centre_Value := 0.0;
      R_U, R_V     : Radius_Value := 0.0;
      Angle        : Long_Float := 0.0;
   end record;
   --  The centre, the radii along the axes and the angle of the first
   --  axis (Radius_X lies along it) in the scaled frame.

   procedure Centre
     (A, B, C : Unit;
      D, E    : Coefficient_Value;
      Disc    : Long_Float;
      X0, Y0  : out Centre_Value;
      Fits    : out Boolean)
   with Pre => Disc > 0.0 and then Disc <= 5.0;
   --  The centre of the conic A u**2 + B uv + C v**2 + D u + E v + F,
   --  ((B E - 2 C D) / Disc, (B D - 2 A E) / Disc) with Disc = 4AC -
   --  B**2; Fits is False when it lies beyond Centre_Limit.

   procedure Centre
     (A, B, C : Unit;
      D, E    : Coefficient_Value;
      Disc    : Long_Float;
      X0, Y0  : out Centre_Value;
      Fits    : out Boolean)
   is
      Num_X : constant Long_Float :=
        N.Mul_Within (B, E, 1.0, Coefficient_Limit)
        - 2.0 * N.Mul_Within (C, D, 1.0, Coefficient_Limit);
      Num_Y : constant Long_Float :=
        N.Mul_Within (B, D, 1.0, Coefficient_Limit)
        - 2.0 * N.Mul_Within (A, E, 1.0, Coefficient_Limit);
      Fits_Y : Boolean;
   begin
      Signed_Quotient (Num_X, Disc, Centre_Limit, X0, Fits);
      Signed_Quotient (Num_Y, Disc, Centre_Limit, Y0, Fits_Y);
      Fits := Fits and then Fits_Y;
   end Centre;

   function Constant_At
     (F      : Coefficient_Value;
      D, E   : Coefficient_Value;
      X0, Y0 : Centre_Value) return Long_Float
   is
     (F + N.Mul_Within (D, X0, Coefficient_Limit, Centre_Limit) / 2.0
        + N.Mul_Within (E, Y0, Coefficient_Limit, Centre_Limit) / 2.0)
   with Post => abs Constant_At'Result <= Constant_Limit;
   --  The value of the conic at its centre, F + (D X0 + E Y0) / 2.

   procedure Radius_Of
     (Minus_F0, Lambda : Long_Float;
      R                : out Radius_Value;
      Fits             : out Boolean)
   with Pre => Minus_F0 > 0.0 and then Minus_F0 <= Constant_Limit
               and then Lambda > 0.0 and then Lambda <= 3.0;
   --  Sqrt (Minus_F0 / Lambda), the radius along an axis whose eigenvalue
   --  is Lambda; Fits is False beyond Centre_Limit (the limit on the
   --  square root states the bound, which its contract does not give).

   procedure Radius_Of
     (Minus_F0, Lambda : Long_Float;
      R                : out Radius_Value;
      Fits             : out Boolean)
   is
      Square : Long_Float;
   begin
      N.Ratio_Within (Minus_F0, Lambda, Square_Limit, Square, Fits);
      R := Long_Float'Min (EF.Sqrt (Square), Centre_Limit);
   end Radius_Of;

   procedure Free_Conic
     (A, B, C : Unit;
      D, E, F : Coefficient_Value;
      Result  : out Scaled_Ellipse;
      Why     : out Reason)
   with Global => null, Post => True;
   --  The ellipse of the conic (any orientation): the major axis first.

   procedure Free_Conic
     (A, B, C : Unit;
      D, E, F : Coefficient_Value;
      Result  : out Scaled_Ellipse;
      Why     : out Reason)
   is
      Disc     : constant Long_Float :=
        4.0 * N.Times_Unit (A, C) - N.Square_Within (B, 1.0);
      X0, Y0   : Centre_Value;
      F0       : Long_Float;
      Half_Sum : constant Long_Float := A / 2.0 + C / 2.0;
      Radius   : Long_Float;
      L1, L2   : Long_Float;
      R1, R2   : Radius_Value;
      Fits     : Boolean;
      Fits_2   : Boolean;
      Axis     : Long_Float;
   begin
      Result := (others => <>);
      if Disc <= 0.0 or else Half_Sum <= 0.0 then
         Why := No_Ellipse;
         return;
      end if;
      Centre (A, B, C, D, E, Disc, X0, Y0, Fits);
      if not Fits then
         Why := Too_Large;
         return;
      end if;
      F0 := Constant_At (F, D, E, X0, Y0);
      if F0 >= 0.0 then
         Why := No_Ellipse;
         return;
      end if;
      --  The eigenvalues of [A B/2; B/2 C]: L1 = mean + radius (the
      --  larger, along the minor axis) and L2 = det / L1.
      Radius := N.Hypot (A / 2.0 - C / 2.0, B / 2.0);
      L1 := Half_Sum + Radius;
      N.Ratio_Within (Disc / 4.0, L1, 4.0, L2, Fits);
      if not Fits or else L2 <= 0.0 or else L1 > 3.0 then
         Why := No_Ellipse;
         return;
      end if;
      Radius_Of (-F0, L1, R1, Fits);
      Radius_Of (-F0, Long_Float'Min (L2, 3.0), R2, Fits_2);
      if not (Fits and then Fits_2) or else R1 = 0.0 or else R2 = 0.0 then
         Why := Too_Large;
         return;
      end if;
      --  The axis of L1 has the angle atan2 (B, A - C) / 2; the major axis
      --  is perpendicular to it.
      if A - C = 0.0 and then B = 0.0 then
         Axis := 0.0;
      else
         Axis := N.Direction (B, A - C) / 2.0;
      end if;
      Result := (X0    => X0,
                 Y0    => Y0,
                 R_U   => R2,
                 R_V   => R1,
                 Angle => N.Reduce_Pi (Axis + N.Half_Pi));
      Why := Fitted;
   end Free_Conic;

   procedure Axis_Conic
     (A, C    : Unit;
      D, E, F : Coefficient_Value;
      Result  : out Scaled_Ellipse;
      Why     : out Reason)
   with Global => null, Post => True;
   --  The ellipse of the conic A u**2 + C v**2 + D u + E v + F (axes along
   --  the frame): Radius_X along u.

   procedure Axis_Conic
     (A, C    : Unit;
      D, E, F : Coefficient_Value;
      Result  : out Scaled_Ellipse;
      Why     : out Reason)
   is
      X0, Y0 : Centre_Value;
      F0     : Long_Float;
      R1, R2 : Radius_Value;
      Fits   : Boolean;
      Fits_2 : Boolean;
   begin
      Result := (others => <>);
      if A <= 0.0 or else C <= 0.0 or else N.Times_Unit (A, C) <= 0.0 then
         Why := No_Ellipse;
         return;
      end if;
      Centre (A, 0.0, C, D, E, 4.0 * N.Times_Unit (A, C), X0, Y0, Fits);
      if not Fits then
         Why := Too_Large;
         return;
      end if;
      F0 := Constant_At (F, D, E, X0, Y0);
      if F0 >= 0.0 then
         Why := No_Ellipse;
         return;
      end if;
      Radius_Of (-F0, A, R1, Fits);
      Radius_Of (-F0, C, R2, Fits_2);
      if not (Fits and then Fits_2) or else R1 = 0.0 or else R2 = 0.0 then
         Why := Too_Large;
         return;
      end if;
      Result := (X0 => X0, Y0 => Y0, R_U => R1, R_V => R2, Angle => 0.0);
      Why := Fitted;
   end Axis_Conic;

   ---------------------------------------------------------------------
   --  One fit
   ---------------------------------------------------------------------

   type Conic is record
      A, B, C : Unit := 0.0;
      D, E, F : Coefficient_Value := 0.0;
   end record;

   procedure Solve_Free
     (M     : Moments;
      Inv   : Inverse_Matrix;
      Q     : out Conic;
      Found : out Boolean)
   with Global => null, Post => True;
   --  The conic of the unconstrained fit, with A + C > 0.

   procedure Solve_Free
     (M     : Moments;
      Inv   : Inverse_Matrix;
      Q     : out Conic;
      Found : out Boolean)
   is
      T       : T_Matrix;
      Red     : M_Matrix;
      A, B, C : Unit;
   begin
      Q := (others => <>);
      Reduce (M, Inv, T, Red);
      Eigenvector (Red, A, B, C, Found);
      if not Found then
         return;
      end if;
      if A + C < 0.0 then
         A := -A;
         B := -B;
         C := -C;
      end if;
      Q := (A => A, B => B, C => C,
            D => Coefficient (T (1, 1), T (1, 2), T (1, 3), A, B, C),
            E => Coefficient (T (2, 1), T (2, 2), T (2, 3), A, B, C),
            F => Coefficient (T (3, 1), T (3, 2), T (3, 3), A, B, C));
   end Solve_Free;

   procedure Solve_Axis
     (M     : Moments;
      Inv   : Inverse_Matrix;
      Q     : out Conic;
      Found : out Boolean)
   with Global => null, Post => True;
   --  The conic of the fit with the axes along the frame (B = 0): the
   --  2 x 2 reduced problem for the rows (u**2, v**2), whose solution of
   --  4AC = 1 is (A, C) proportional to (Sqrt (m22), Sqrt (m11)).

   procedure Solve_Axis
     (M     : Moments;
      Inv   : Inverse_Matrix;
      Q     : out Conic;
      Found : out Boolean)
   is
      S2 : constant array (1 .. 2, 1 .. 3) of Unit :=
        [[M.M30, M.M21, M.M20],
         [M.M12, M.M03, M.M02]];
      T  : T_Matrix := [others => [others => 0.0]];
      M11, M22 : M_Value;
      A, C     : Long_Float;
      Big      : Long_Float;
   begin
      Q := (others => <>);
      for K in 1 .. 3 loop
         for J in 1 .. 2 loop
            T (K, J) := T_Entry (Inv (K, 1), Inv (K, 2), Inv (K, 3),
                                 S2 (J, 1), S2 (J, 2), S2 (J, 3));
         end loop;
      end loop;
      M11 := M_Entry (M.M40, S2 (1, 1), S2 (1, 2), S2 (1, 3),
                      T (1, 1), T (2, 1), T (3, 1));
      M22 := M_Entry (M.M04, S2 (2, 1), S2 (2, 2), S2 (2, 3),
                      T (1, 2), T (2, 2), T (3, 2));
      --  Both are at most M_Limit = 2**94, so the roots at most 2**47.
      A := Long_Float'Min (EF.Sqrt (Long_Float'Max (0.0, M22)), 2.0 ** 47);
      C := Long_Float'Min (EF.Sqrt (Long_Float'Max (0.0, M11)), 2.0 ** 47);
      Big := Long_Float'Max (A, C);
      Found := Big > 0.0;
      if not Found then
         return;
      end if;
      A := N.Unit_Ratio (A, Big);
      C := N.Unit_Ratio (C, Big);
      Q := (A => A, B => 0.0, C => C,
            D => Coefficient (T (1, 1), T (1, 2), 0.0, A, C, 0.0),
            E => Coefficient (T (2, 1), T (2, 2), 0.0, A, C, 0.0),
            F => Coefficient (T (3, 1), T (3, 2), 0.0, A, C, 0.0));
   end Solve_Axis;

   function Radial_Distance
     (Q : KG.Ks_Point_2D;
      E : Ellipse_Value;
      C : Unit;
      S : Unit) return Long_Float
   with
     Pre  => Valid_Value (E),
     Post => Radial_Distance'Result >= 0.0
             and then Radial_Distance'Result <= Max_Length;
   --  The distance from Q to the ellipse (C and S the cosine and sine of
   --  its rotation) measured along the ray from the centre through Q:
   --  |rho - r| with rho the distance of Q from the centre and r the
   --  ellipse's radius in that direction (rho / s, s the "ellipse norm"
   --  Sqrt ((u / Radius_X)**2 + (v / Radius_Y)**2) of Q's offset (u, v) in
   --  the ellipse's frame). It is 0 exactly on the ellipse, close to the
   --  distance to the nearest point near it, and finite at the centre
   --  (the radius in some direction), which makes it a robust measure for
   --  choosing the points to leave out; the distances the results report
   --  are the exact ones. Computed on the offset and the radii divided by
   --  the largest of them.

   function Radial_Distance
     (Q : KG.Ks_Point_2D;
      E : Ellipse_Value;
      C : Unit;
      S : Unit) return Long_Float
   is
      DX     : constant Long_Float := Read (Q.X) - E.Center_X;
      DY     : constant Long_Float := Read (Q.Y) - E.Center_Y;
      U      : constant Long_Float :=
        N.Times_Unit (DX, C) + N.Times_Unit (DY, S);
      V      : constant Long_Float :=
        N.Times_Unit (DY, C) - N.Times_Unit (DX, S);
      Scale  : constant Long_Float :=
        Long_Float'Max (Long_Float'Max (E.Radius_X, E.Radius_Y),
                        Long_Float'Max (abs U, abs V));
      UN     : constant Unit := N.Unit_Ratio (N.Clamp (U, Scale), Scale);
      VN     : constant Unit := N.Unit_Ratio (N.Clamp (V, Scale), Scale);
      AN     : constant Long_Float :=
        Long_Float'Max (0.0, N.Unit_Ratio (E.Radius_X, Scale));
      BN     : constant Long_Float :=
        Long_Float'Max (0.0, N.Unit_Ratio (E.Radius_Y, Scale));
      Rho    : constant Long_Float := N.Hypot (UN, VN);
      Q0, Q1 : Long_Float;
      Norm   : Long_Float;
      R      : Long_Float;
      Fits_0 : Boolean;
      Fits_1 : Boolean;
      DN     : Long_Float;
   begin
      if AN = 0.0 or else BN = 0.0 then
         --  The ellipse is too thin for the scale: the distance from the
         --  centre.
         DN := Rho;
      else
         N.Ratio_Within (abs UN, AN, 2.0 ** 40, Q0, Fits_0);
         N.Ratio_Within (abs VN, BN, 2.0 ** 40, Q1, Fits_1);
         if not (Fits_0 and then Fits_1) then
            --  Far outside: the radius is negligible.
            DN := Rho;
         else
            Norm := N.Hypot (Q0, Q1);
            if Norm = 0.0 then
               DN := Long_Float'Min (AN, BN);
            else
               N.Ratio_Within (Rho, Norm, 2.0, R, Fits_0);
               if not Fits_0 then
                  R := 2.0;
               end if;
               DN := abs (Rho - R);
            end if;
         end if;
      end if;
      --  The distance is at most about 3.9E150 (see World_Length of
      --  AMV.Kernels.Dimensioning.Ellipses); the limit never acts.
      return Long_Float'Min
        (N.Mul (Scale, Long_Float'Min (DN, 4.0)), Max_Length);
   end Radial_Distance;

   function Radial_Cost
     (Points : KG.Point_Array;
      Active : KG.Flag_Array;
      E      : Ellipse_Value) return Long_Float
   with
     Pre  => Points'First = 0 and then Points'Last < Max_Points
             and then Active'First = 0 and then Active'Last = Points'Last
             and then Valid_Value (E),
     Post => Radial_Cost'Result >= 0.0
             and then Radial_Cost'Result <= Max_Length;
   --  The root mean square radial distance (see Radial_Distance) of the
   --  points in use: how well the ellipse fits, comparable between fits of
   --  different points.

   function Radial_Cost
     (Points : KG.Point_Array;
      Active : KG.Flag_Array;
      E      : Ellipse_Value) return Long_Float
   is
      Sum_Limit : constant := 2.0 ** 1021;
      --  At least Max_Points squares of distances of at most 4.0E150.
      C         : constant Unit := EF.Cos (E.Rotation);
      S         : constant Unit := EF.Sin (E.Rotation);
      Sum       : Long_Float := 0.0;
      Count     : Natural := 0;
   begin
      for I in Points'Range loop
         pragma Loop_Invariant
           (Sum >= 0.0 and then Sum <= Sum_Limit and then Count <= I);
         if Active (I) then
            --  The limit never acts (at most 2**20 terms of at most
            --  1.6E301).
            Sum := Long_Float'Min
              (Sum + N.Square_Within
                       (Radial_Distance (Points (I), E, C, S), Max_Length),
               Sum_Limit);
            Count := Count + 1;
         end if;
      end loop;
      if Count = 0 then
         return 0.0;
      end if;
      --  The root mean square is at most the largest distance; the limit
      --  states it (Sqrt has no upper bound in its contract).
      return Long_Float'Min (EF.Sqrt (Sum / Long_Float (Count)), Max_Length);
   end Radial_Cost;

   procedure To_World
     (F           : Frame;
      S           : Scaled_Ellipse;
      Constrained : Boolean;
      Rotation    : Long_Float;
      Result      : out Ellipse_Value;
      Why         : out Reason)
   with
     Pre  => Bounded (Rotation),
     Post => (if Why = Fitted
              then Valid_Value (Result)
                   and then (if Constrained then Result.Rotation = Rotation));
   --  The ellipse back in the space of the points: the centre turned by
   --  the rotation, scaled and moved by the centroid, the radii scaled.

   procedure To_World
     (F           : Frame;
      S           : Scaled_Ellipse;
      Constrained : Boolean;
      Rotation    : Long_Float;
      Result      : out Ellipse_Value;
      Why         : out Reason)
   is
      WX : constant Long_Float :=
        N.Times_Unit (S.X0, F.Cos_R) - N.Times_Unit (S.Y0, F.Sin_R);
      WY : constant Long_Float :=
        N.Times_Unit (S.X0, F.Sin_R) + N.Times_Unit (S.Y0, F.Cos_R);
      CX : constant Long_Float :=
        F.CX + N.Mul_Within (F.Scale, WX, 4.0 * Max_Value, 2.0 ** 31);
      CY : constant Long_Float :=
        F.CY + N.Mul_Within (F.Scale, WY, 4.0 * Max_Value, 2.0 ** 31);
      RX : constant Long_Float :=
        N.Mul_Within (F.Scale, S.R_U, 4.0 * Max_Value, Centre_Limit);
      RY : constant Long_Float :=
        N.Mul_Within (F.Scale, S.R_V, 4.0 * Max_Value, Centre_Limit);
      Angle : constant Long_Float :=
        (if Constrained then Rotation
         elsif S.Angle >= -Max_Value and then S.Angle <= Max_Value
         then S.Angle else 0.0);
   begin
      Result := (others => <>);
      if Bounded (CX) and then Bounded (CY)
        and then RX > 0.0 and then RX <= Max_Value
        and then RY > 0.0 and then RY <= Max_Value
      then
         Result := (Center_X => CX, Center_Y => CY,
                    Radius_X => RX, Radius_Y => RY,
                    Rotation => Angle);
         Why := Fitted;
      else
         Why := Out_Of_Bound;
      end if;
   end To_World;

   procedure Fit_Active
     (Points       : KG.Point_Array;
      Active       : KG.Flag_Array;
      Constrained  : Boolean;
      Rotation     : Long_Float;
      Cos_R, Sin_R : Unit;
      Result       : out Ellipse_Value;
      Cost         : out Long_Float;
      Why          : out Reason)
   with
     Pre  => Points'First = 0 and then Points'Last < Max_Points
             and then Active'First = 0 and then Active'Last = Points'Last
             and then Bounded (Rotation),
     Post => Cost >= 0.0
             and then (if Why = Fitted
                       then Valid_Value (Result)
                            and then (if Constrained
                                      then Result.Rotation = Rotation));
   --  The fit of the points whose Active flag is set, and its cost.

   procedure Fit_Active
     (Points       : KG.Point_Array;
      Active       : KG.Flag_Array;
      Constrained  : Boolean;
      Rotation     : Long_Float;
      Cos_R, Sin_R : Unit;
      Result       : out Ellipse_Value;
      Cost         : out Long_Float;
      Why          : out Reason)
   is
      F      : Frame;
      M      : Moments;
      Inv    : Inverse_Matrix;
      Q      : Conic;
      Found  : Boolean;
      Scaled : Scaled_Ellipse;
   begin
      Result := (others => <>);
      Cost := 0.0;
      Make_Frame (Points, Active, Cos_R, Sin_R, F);
      if F.Count < (if Constrained then 4 else 5) then
         Why := Too_Few;
         return;
      elsif F.Scale = 0.0 then
         Why := Coincident;
         return;
      end if;
      Compute_Moments (Points, Active, F, M);
      Invert_Scatter (M, Inv, Why);
      if Why /= Fitted then
         return;
      end if;
      if Constrained then
         Solve_Axis (M, Inv, Q, Found);
      else
         Solve_Free (M, Inv, Q, Found);
      end if;
      if not Found then
         Why := No_Ellipse;
         return;
      end if;
      if Constrained then
         Axis_Conic (Q.A, Q.C, Q.D, Q.E, Q.F, Scaled, Why);
      else
         Free_Conic (Q.A, Q.B, Q.C, Q.D, Q.E, Q.F, Scaled, Why);
      end if;
      if Why /= Fitted then
         return;
      end if;
      To_World (F, Scaled, Constrained, Rotation, Result, Why);
      if Why = Fitted then
         Cost := Radial_Cost (Points, Active, Result);
      end if;
   end Fit_Active;

   ---------------------------------------------------------------------
   --  The entry
   ---------------------------------------------------------------------

   procedure Fail (Why : Reason; Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure = Failure_Bad_Parameter;

   procedure Fail (Why : Reason; Status : out Ks_Status) is
   begin
      case Why is
         when Too_Few =>
            Set_Failure (Status, Failure_Bad_Parameter,
                         "FitEllipse: too few points in use (at least 5,"
                         & " or 4 with RotationConstraintEnabled)");
         when Coincident =>
            Set_Failure (Status, Failure_Bad_Parameter,
                         "FitEllipse: the points coincide");
         when Collinear =>
            Set_Failure (Status, Failure_Bad_Parameter,
                         "FitEllipse: the points are (nearly) collinear");
         when No_Ellipse | Fitted =>
            Set_Failure (Status, Failure_Bad_Parameter,
                         "FitEllipse: no ellipse fits the points");
         when Too_Large =>
            Set_Failure (Status, Failure_Bad_Parameter,
                         "FitEllipse: the fitted ellipse would be too large"
                         & " for the extent of the points");
         when Out_Of_Bound =>
            Set_Failure (Status, Failure_Bad_Parameter,
                         "FitEllipse: the fitted ellipse would exceed"
                         & " +/-1.0E150");
      end case;
   end Fail;

   procedure Fit
     (Points        : KG.Point_Array;
      Num_To_Ignore : Natural;
      Constrained   : Boolean;
      Rotation      : Long_Float;
      Result        : out Ellipse_Value;
      Used          : out KG.Flag_Array;
      Status        : out Ks_Status)
   is
      Cos_R      : constant Unit :=
        (if Constrained then EF.Cos (Rotation) else 1.0);
      Sin_R      : constant Unit :=
        (if Constrained then EF.Sin (Rotation) else 0.0);
      Trial      : Ellipse_Value;
      Trial_Cost : Long_Float;
      Why        : Reason;
      Best       : Integer;
      Best_Value : Ellipse_Value;
      Best_Cost  : Long_Float;
      Unused_Cost : Long_Float;
   begin
      Result := (others => <>);
      Used := [others => True];
      for Step in 1 .. Num_To_Ignore loop
         Best := -1;
         Best_Cost := 0.0;
         Best_Value := (others => <>);
         for J in Points'Range loop
            pragma Loop_Invariant
              (Best in -1 .. J - 1 and then Best_Cost >= 0.0
               and then (if Best >= 0
                         then Valid_Value (Best_Value)
                              and then (if Constrained
                                        then Best_Value.Rotation
                                               = Rotation)));
            if Used (J) then
               Used (J) := False;
               Fit_Active (Points, Used, Constrained, Rotation, Cos_R, Sin_R,
                           Trial, Trial_Cost, Why);
               Used (J) := True;
               if Why = Fitted
                 and then (Best = -1 or else Trial_Cost < Best_Cost)
               then
                  Best := J;
                  Best_Cost := Trial_Cost;
                  Best_Value := Trial;
               end if;
            end if;
         end loop;
         if Best = -1 then
            Used := [others => False];
            Result := (others => <>);
            Set_Failure (Status, Failure_Bad_Parameter,
                         "FitEllipse: no ellipse fits the points left after"
                         & " leaving out NumToIgnore of them");
            return;
         end if;
         Used (Best) := False;
         Result := Best_Value;
      end loop;
      if Num_To_Ignore = 0 then
         Fit_Active (Points, Used, Constrained, Rotation, Cos_R, Sin_R,
                     Result, Unused_Cost, Why);
         if Why /= Fitted then
            Used := [others => False];
            Result := (others => <>);
            Fail (Why, Status);
            return;
         end if;
      end if;
      pragma Assert (Valid_Value (Result));
      Set_Success (Status);
   end Fit;

end AMV.Kernels.Dimensioning.Fit_Ellipse;
