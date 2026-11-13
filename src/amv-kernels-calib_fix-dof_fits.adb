pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Numerics;

package body AMV.Kernels.Calib_Fix.DOF_Fits with SPARK_Mode is

   pragma Unevaluated_Use_Of_Old (Allow);

   package N renames AMV.Kernels.Numerics;

   use type KT.Ks_Transform_2D_Linear;

   --  Scaled points. Each group is centred on its centroid and divided by
   --  its largest centred coordinate (its spread), so every scaled
   --  coordinate lies in [-1, 1] and every sum of products of them over
   --  at most Max_Pairs pairs lies within Max_Pairs (Sum_Limit leaves a
   --  factor of two).

   Sum_Limit : constant := 2.0 ** 20;

   subtype Sum_Value is Long_Float range -Sum_Limit .. Sum_Limit;
   subtype Square_Sum is Long_Float range 0.0 .. Sum_Limit;
   subtype Unit_Value is Long_Float range -1.0 .. 1.0;
   subtype Spread is Long_Float range 0.0 .. 2.0 * Max_Value;

   type Frame is record
      CA_X, CA_Y, CB_X, CB_Y : Coordinate := 0.0;
      SA, SB                 : Spread := 0.0;
   end record;
   --  The centroids of the A and B points and their spreads (0 when the
   --  points of the group coincide).

   type Sums is record
      Hxx, Hxy, Hyx, Hyy : Sum_Value := 0.0;
      Qxx, Qyy           : Square_Sum := 0.0;
      Qxy                : Sum_Value := 0.0;
   end record;
   --  With p the scaled A points and q the scaled B points: H_jk is the
   --  sum of p_j q_k (Hxy = sum of p_x q_y), Q_kl the sum of q_k q_l.

   type Component is (Ax, Ay, Bx, By);

   function Value (P : Ks_Point_Pair; C : Component) return Coordinate is
     (case C is
        when Ax => P.A_X,
        when Ay => P.A_Y,
        when Bx => P.B_X,
        when By => P.B_Y);

   ---------------------------------------------------------------------
   --  Failures
   ---------------------------------------------------------------------

   procedure Fail (Status : out Ks_Status; Message : String)
   with
     Pre  => Message'Length <= 120,
     Post => Valid (Status) and then Status.Failure = Failure_Bad_Parameter;

   procedure Fail (Status : out Ks_Status; Message : String) is
   begin
      Set_Failure (Status, Failure_Bad_Parameter, Message);
   end Fail;

   procedure Coincident (Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure = Failure_Bad_Parameter;

   procedure Coincident (Status : out Ks_Status) is
   begin
      Fail (Status, "N-point fit: the raw points (group B) all coincide");
   end Coincident;

   procedure Collinear (Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure = Failure_Bad_Parameter;

   procedure Collinear (Status : out Ks_Status) is
   begin
      Fail (Status, "N-point fit: the raw points (group B) lie on one line");
   end Collinear;

   procedure Singular (Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure = Failure_Bad_Parameter;

   procedure Singular (Status : out Ks_Status) is
   begin
      Fail (Status, "N-point fit: the points do not determine an "
                    & "invertible transform");
   end Singular;

   procedure Beyond (Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure = Failure_Bad_Parameter;

   procedure Beyond (Status : out Ks_Status) is
   begin
      Fail (Status, "N-point fit: the fitted transform exceeds the bound "
                    & "of the transforms (1.0E150)");
   end Beyond;

   ---------------------------------------------------------------------
   --  Arithmetic
   ---------------------------------------------------------------------

   function Ratio (X, Y, Limit : Long_Float) return Long_Float
   with
     Pre  => abs X <= N.Mul_Limit and then Y > 0.0
             and then Y <= N.Mul_Limit
             and then Limit >= 1.0 and then Limit <= N.Mul_Limit,
     Post => abs Ratio'Result <= Limit;
   --  X / Y, saturated at +/-Limit (the callers' quotients never reach
   --  it; see docs/PROOF.md).

   function Ratio (X, Y, Limit : Long_Float) return Long_Float is
      R    : Long_Float;
      Fits : Boolean;
   begin
      N.Ratio_Within (abs X, Y, Limit, R, Fits);
      if not Fits then
         R := Limit;
      end if;
      return (if X < 0.0 then -R else R);
   end Ratio;

   function Add (S : Sum_Value; T : Unit_Value) return Sum_Value is
     (N.Clamp (S + T, Sum_Limit));
   --  S + T (the clamp never acts: a sum has at most Max_Pairs terms).

   function Add_Square (S : Square_Sum; T : Long_Float) return Square_Sum is
     (Long_Float'Min (S + T, Sum_Limit))
   with Pre => T >= 0.0 and then T <= 1.0;

   function Scaled (X, Centre : Coordinate; S : Spread) return Unit_Value is
     (if S = 0.0 then 0.0
      elsif X - Centre >= S then 1.0
      elsif X - Centre <= -S then -1.0
      else N.Unit_Ratio (X - Centre, S));
   --  (X - Centre) / S, 0 for a group without spread.

   ---------------------------------------------------------------------
   --  Centroids, spreads and sums
   ---------------------------------------------------------------------

   function Mean
     (Pairs : Pair_Array;
      Count : Positive;
      C     : Component) return Coordinate
   with Pre => Pairs'First = 0 and then Count <= Max_Pairs
               and then Count - 1 <= Pairs'Last;
   --  The mean of the coordinate C of the pairs.

   function Mean
     (Pairs : Pair_Array;
      Count : Positive;
      C     : Component) return Coordinate
   is
      Sum_Bound : constant := 2.0 ** 520;
      --  At most Max_Pairs terms of at most 1.0E150 (about 5.3E155).
      Sum       : Long_Float range -Sum_Bound .. Sum_Bound := 0.0;
   begin
      for I in 0 .. Count - 1 loop
         Sum := N.Clamp (Sum + Value (Pairs (I), C), Sum_Bound);
      end loop;
      return N.Clamp (Sum / Long_Float (Count), Max_Value);
   end Mean;

   function Spread_Of
     (Pairs  : Pair_Array;
      Count  : Positive;
      C      : Component;
      Centre : Coordinate) return Spread
   with Pre => Pairs'First = 0 and then Count <= Max_Pairs
               and then Count - 1 <= Pairs'Last;
   --  The largest magnitude of the coordinate C minus Centre.

   function Spread_Of
     (Pairs  : Pair_Array;
      Count  : Positive;
      C      : Component;
      Centre : Coordinate) return Spread
   is
      S : Spread := 0.0;
   begin
      for I in 0 .. Count - 1 loop
         S := Long_Float'Max (S, abs (Value (Pairs (I), C) - Centre));
      end loop;
      return S;
   end Spread_Of;

   function Frame_Of (Pairs : Pair_Array; Count : Positive) return Frame
   with Pre => Pairs'First = 0 and then Count <= Max_Pairs
               and then Count - 1 <= Pairs'Last;

   function Frame_Of (Pairs : Pair_Array; Count : Positive) return Frame is
      F : Frame;
   begin
      F.CA_X := Mean (Pairs, Count, Ax);
      F.CA_Y := Mean (Pairs, Count, Ay);
      F.CB_X := Mean (Pairs, Count, Bx);
      F.CB_Y := Mean (Pairs, Count, By);
      F.SA := Long_Float'Max (Spread_Of (Pairs, Count, Ax, F.CA_X),
                              Spread_Of (Pairs, Count, Ay, F.CA_Y));
      F.SB := Long_Float'Max (Spread_Of (Pairs, Count, Bx, F.CB_X),
                              Spread_Of (Pairs, Count, By, F.CB_Y));
      return F;
   end Frame_Of;

   function Sums_Of
     (Pairs : Pair_Array;
      Count : Positive;
      F     : Frame) return Sums
   with Pre => Pairs'First = 0 and then Count <= Max_Pairs
               and then Count - 1 <= Pairs'Last;

   function Sums_Of
     (Pairs : Pair_Array;
      Count : Positive;
      F     : Frame) return Sums
   is
      S : Sums;
   begin
      for I in 0 .. Count - 1 loop
         declare
            Px : constant Unit_Value := Scaled (Pairs (I).A_X, F.CA_X, F.SA);
            Py : constant Unit_Value := Scaled (Pairs (I).A_Y, F.CA_Y, F.SA);
            Qx : constant Unit_Value := Scaled (Pairs (I).B_X, F.CB_X, F.SB);
            Qy : constant Unit_Value := Scaled (Pairs (I).B_Y, F.CB_Y, F.SB);
         begin
            S.Hxx := Add (S.Hxx, N.Times_Unit (Px, Qx));
            S.Hxy := Add (S.Hxy, N.Times_Unit (Px, Qy));
            S.Hyx := Add (S.Hyx, N.Times_Unit (Py, Qx));
            S.Hyy := Add (S.Hyy, N.Times_Unit (Py, Qy));
            S.Qxx := Add_Square (S.Qxx, N.Square_Within (Qx, 1.0));
            S.Qyy := Add_Square (S.Qyy, N.Square_Within (Qy, 1.0));
            S.Qxy := Add (S.Qxy, N.Times_Unit (Qx, Qy));
         end;
      end loop;
      return S;
   end Sums_Of;

   ---------------------------------------------------------------------
   --  The translation and the result
   ---------------------------------------------------------------------

   procedure Shift
     (A, B, C, D : Coordinate;
      F          : Frame;
      Tx, Ty     : out Long_Float;
      Fits       : out Boolean)
   with Post => (if Fits then Tx in Coordinate and then Ty in Coordinate
                 else Tx = 0.0 and then Ty = 0.0);
   --  The translation that maps the B centroid onto the A centroid under
   --  the matrix [A B; C D]; Fits is False when it exceeds Max_Value.

   procedure Shift
     (A, B, C, D : Coordinate;
      F          : Frame;
      Tx, Ty     : out Long_Float;
      Fits       : out Boolean)
   is
      X : constant Long_Float :=
        F.CA_X - (N.Mul (A, F.CB_X) + N.Mul (B, F.CB_Y));
      Y : constant Long_Float :=
        F.CA_Y - (N.Mul (C, F.CB_X) + N.Mul (D, F.CB_Y));
   begin
      Fits := X in Coordinate and then Y in Coordinate;
      Tx := (if Fits then X else 0.0);
      Ty := (if Fits then Y else 0.0);
   end Shift;

   function Distance
     (P : Ks_Point_Pair;
      T : KT.Ks_Transform_2D_Linear) return Long_Float
   with
     Pre  => KT.Bounded (T),
     Post => Distance'Result >= 0.0 and then Distance'Result <= Max_RMS;
   --  |T (B) - A|, limited to Max_RMS (the residual components are first
   --  limited to Max_RMS too).

   function Distance
     (P : Ks_Point_Pair;
      T : KT.Ks_Transform_2D_Linear) return Long_Float
   is
      Dx : constant Long_Float :=
        N.Clamp ((N.Mul (T.A, P.B_X) + N.Mul (T.B, P.B_Y))
                 + (T.Translation_X - P.A_X), Max_RMS);
      Dy : constant Long_Float :=
        N.Clamp ((N.Mul (T.C, P.B_X) + N.Mul (T.D, P.B_Y))
                 + (T.Translation_Y - P.A_Y), Max_RMS);
   begin
      return N.Clamp (N.Hypot (Dx, Dy), Max_RMS);
   end Distance;

   function RMS
     (Pairs : Pair_Array;
      Count : Natural;
      T     : KT.Ks_Transform_2D_Linear) return Long_Float
   with
     Pre  => Pairs'First = 0 and then Count <= Max_Pairs
             and then Count - 1 <= Pairs'Last
             and then KT.Bounded (T),
     Post => RMS'Result >= 0.0 and then RMS'Result <= Max_RMS;
   --  The root mean square of the distances (0 without pairs).

   function RMS
     (Pairs : Pair_Array;
      Count : Natural;
      T     : KT.Ks_Transform_2D_Linear) return Long_Float
   is
      Sum_Bound : constant := 2.0 ** 1022;
      --  At most Max_Pairs squares of at most Max_RMS**2 (about 8.4E306).
      Sum       : Long_Float range 0.0 .. Sum_Bound := 0.0;
   begin
      if Count = 0 then
         return 0.0;
      end if;
      for I in 0 .. Count - 1 loop
         Sum := Long_Float'Min
           (Sum + N.Square_Within (Distance (Pairs (I), T), Max_RMS),
            Sum_Bound);
      end loop;
      return N.Clamp (EF.Sqrt (Sum / Long_Float (Count)), Max_RMS);
   end RMS;

   procedure Finish
     (Pairs     : Pair_Array;
      Count     : Natural;
      T         : KT.Ks_Transform_2D_Linear;
      Scaling_X : Long_Float;
      Scaling_Y : Long_Float;
      Rotation  : Long_Float;
      Skew      : Long_Float;
      Result    : out Ks_N_Point_To_N_Point_Fit;
      Status    : out Ks_Status)
   with
     Pre  => Pairs'First = 0 and then Count <= Max_Pairs
             and then Count - 1 <= Pairs'Last
             and then KT.Bounded (T)
             and then Scaling_X >= -KT.Max_Scaling
             and then Scaling_X <= KT.Max_Scaling
             and then Scaling_Y >= -KT.Max_Scaling
             and then Scaling_Y <= KT.Max_Scaling
             and then Rotation > -Pi and then Rotation <= Pi
             and then Skew > -Pi and then Skew <= Pi,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Valid_Fit (Result)
                            and then Result.Transform = T
                            and then Result.Scaling_X = Scaling_X
                            and then Result.Scaling_Y = Scaling_Y
                            and then Result.Rotation = Rotation
                            and then Result.Skew = Skew
                       else Result = Identity_Fit);
   --  The fit with transform T and the given parameters, once T is shown
   --  to be invertible (Bad_Parameter otherwise), with its RMS error.

   procedure Finish
     (Pairs     : Pair_Array;
      Count     : Natural;
      T         : KT.Ks_Transform_2D_Linear;
      Scaling_X : Long_Float;
      Scaling_Y : Long_Float;
      Rotation  : Long_Float;
      Skew      : Long_Float;
      Result    : out Ks_N_Point_To_N_Point_Fit;
      Status    : out Ks_Status)
   is
      Inverse : KT.Ks_Transform_2D_Linear;
   begin
      Result := Identity_Fit;
      if Det_Of (T) = 0.0 then
         Singular (Status);
         return;
      end if;
      KT.Invert (T, Inverse, Status);
      if not Succeeded (Status) or else not KT.Bounded (Inverse) then
         Singular (Status);
         return;
      end if;
      Result :=
        (Transform => T,
         RMS_Error => RMS (Pairs, Count, T),
         Scaling_X => Scaling_X,
         Scaling_Y => Scaling_Y,
         Rotation  => Rotation,
         Skew      => Skew);
      Set_Success (Status);
   end Finish;

   ---------------------------------------------------------------------
   --  The fits per DOF
   ---------------------------------------------------------------------

   procedure Fit_Translation
     (Pairs  : Pair_Array;
      Count  : Positive;
      DOF    : DOF_Code;
      Result : out Ks_N_Point_To_N_Point_Fit;
      Status : out Ks_Status)
   with
     Pre  => Pairs'First = 0 and then Count <= Max_Pairs
             and then Count - 1 <= Pairs'Last
             and then DOF in DOF_Translation_X .. DOF_Translation,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status) then Gold_Fit (Result, DOF)
                       else Result = Identity_Fit);

   procedure Fit_Translation
     (Pairs  : Pair_Array;
      Count  : Positive;
      DOF    : DOF_Code;
      Result : out Ks_N_Point_To_N_Point_Fit;
      Status : out Ks_Status)
   is
      Dx : constant Long_Float :=
        (if DOF = DOF_Translation_Y then 0.0
         else Mean (Pairs, Count, Ax) - Mean (Pairs, Count, Bx));
      Dy : constant Long_Float :=
        (if DOF = DOF_Translation_X then 0.0
         else Mean (Pairs, Count, Ay) - Mean (Pairs, Count, By));
      T  : KT.Ks_Transform_2D_Linear;
   begin
      Result := Identity_Fit;
      if Dx not in Coordinate or else Dy not in Coordinate then
         Beyond (Status);
         return;
      end if;
      T.Translation_X := Dx;
      T.Translation_Y := Dy;
      Finish (Pairs, Count, T, 1.0, 1.0, 0.0, 0.0, Result, Status);
   end Fit_Translation;

   procedure Fit_Rigid
     (Pairs  : Pair_Array;
      Count  : Positive;
      F      : Frame;
      S      : Sums;
      Result : out Ks_N_Point_To_N_Point_Fit;
      Status : out Ks_Status)
   with
     Pre  => Pairs'First = 0 and then Count <= Max_Pairs
             and then Count - 1 <= Pairs'Last,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Gold_Fit (Result, DOF_Rotation_And_Translation)
                       else Result = Identity_Fit);
   --  The rotation that best turns the scaled B points onto the scaled A
   --  points: the direction of (sum of p . q, sum of q x p).

   procedure Fit_Rigid
     (Pairs  : Pair_Array;
      Count  : Positive;
      F      : Frame;
      S      : Sums;
      Result : out Ks_N_Point_To_N_Point_Fit;
      Status : out Ks_Status)
   is
      Dot   : constant Long_Float := S.Hxx + S.Hyy;
      Cross : constant Long_Float := S.Hyx - S.Hxy;
      Theta : constant Long_Float :=
        (if Dot = 0.0 and then Cross = 0.0 then 0.0
         else N.Direction (Cross, Dot));
      Cos_T : constant Long_Float := EF.Cos (Theta);
      Sin_T : constant Long_Float := EF.Sin (Theta);
      T     : KT.Ks_Transform_2D_Linear :=
        (A => Cos_T, B => -Sin_T, C => Sin_T, D => Cos_T,
         Translation_X => 0.0, Translation_Y => 0.0);
      Fits  : Boolean;
   begin
      Result := Identity_Fit;
      Shift (T.A, T.B, T.C, T.D, F, T.Translation_X, T.Translation_Y, Fits);
      if not Fits then
         Beyond (Status);
         return;
      end if;
      Finish (Pairs, Count, T, 1.0, 1.0, Theta, 0.0, Result, Status);
   end Fit_Rigid;

   procedure Fit_Similarity
     (Pairs  : Pair_Array;
      Count  : Positive;
      F      : Frame;
      S      : Sums;
      Result : out Ks_N_Point_To_N_Point_Fit;
      Status : out Ks_Status)
   with
     Pre  => Pairs'First = 0 and then Count <= Max_Pairs
             and then Count - 1 <= Pairs'Last
             and then F.SB > 0.0,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Gold_Fit
                              (Result, DOF_Scaling_Rotation_And_Translation)
                       else Result = Identity_Fit);
   --  The matrix [a -b; b a] with (a, b) = (dot, cross) / (sum of |q|**2),
   --  scaled back by SA / SB.

   procedure Fit_Similarity
     (Pairs  : Pair_Array;
      Count  : Positive;
      F      : Frame;
      S      : Sums;
      Result : out Ks_N_Point_To_N_Point_Fit;
      Status : out Ks_Status)
   is
      Alpha_Limit : constant := 2.0 ** 23;
      K_Limit     : constant := 2.0 ** 480;
      Q           : constant Long_Float := S.Qxx + S.Qyy;
      K           : Long_Float;
      K_Fits      : Boolean;
      Alpha, Beta : Long_Float;
      A_Val       : Long_Float;
      C_Val       : Long_Float;
      Scale       : Long_Float;
      T           : KT.Ks_Transform_2D_Linear;
      Fits        : Boolean;
   begin
      Result := Identity_Fit;
      --  The B point with the largest centred coordinate has a scaled
      --  coordinate of magnitude 1, so Q >= 1 when SB > 0.
      if Q < 0.5 then
         Coincident (Status);
         return;
      end if;
      N.Ratio_Within (F.SA, F.SB, K_Limit, K, K_Fits);
      if not K_Fits then
         Beyond (Status);
         return;
      end if;
      Alpha := Ratio (S.Hxx + S.Hyy, Q, Alpha_Limit);
      Beta := Ratio (S.Hyx - S.Hxy, Q, Alpha_Limit);
      A_Val := N.Mul_Within (Alpha, K, Alpha_Limit, K_Limit);
      C_Val := N.Mul_Within (Beta, K, Alpha_Limit, K_Limit);
      if A_Val not in Coordinate or else C_Val not in Coordinate then
         Beyond (Status);
         return;
      end if;
      Scale := N.Hypot (A_Val, C_Val);
      if Scale <= 0.0 then
         Singular (Status);
         return;
      end if;
      T := (A => A_Val, B => -C_Val, C => C_Val, D => A_Val,
            Translation_X => 0.0, Translation_Y => 0.0);
      Shift (T.A, T.B, T.C, T.D, F, T.Translation_X, T.Translation_Y, Fits);
      if not Fits then
         Beyond (Status);
         return;
      end if;
      Finish (Pairs, Count, T, Scale, Scale, N.Direction (C_Val, A_Val), 0.0,
              Result, Status);
   end Fit_Similarity;

   Min_Det_Q : constant := 2.0E-11;
   Min_Q     : constant := 1.0E-11;

   function Scatter_Det (S : Sums) return Long_Float is
     (N.Mul_Within (S.Qxx, S.Qyy, Sum_Limit, Sum_Limit)
      - N.Mul_Within (S.Qxy, S.Qxy, Sum_Limit, Sum_Limit))
   with Post => abs Scatter_Det'Result <= 2.0 ** 41;
   --  The determinant of the scatter of the scaled B points.

   procedure Check_Spread
     (S      : Sums;
      Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Scatter_Det (S) >= Min_Det_Q
                            and then S.Qxx >= Min_Q
                            and then S.Qyy >= Min_Q);
   --  Bad_Parameter when the scaled B points lie on one line: the
   --  determinant of their scatter is below Collinear_Tolerance times its
   --  squared trace. Then the trace is at least 1/2 (as in
   --  Fit_Similarity), the determinant at least 2.5E-11 and either
   --  diagonal entry at least the determinant over the other, 5.0E-11; the
   --  bounds Min_Det_Q and Min_Q below these are guards that never act.

   procedure Check_Spread
     (S      : Sums;
      Status : out Ks_Status)
   is
      Trace : constant Long_Float := S.Qxx + S.Qyy;
      Det_Q : constant Long_Float := Scatter_Det (S);
   begin
      if Trace < 0.5 then
         Coincident (Status);
         return;
      end if;
      if Det_Q < Collinear_Tolerance
                 * N.Square_Within (Trace, 2.0 * Sum_Limit)
        or else Det_Q < Min_Det_Q
        or else S.Qxx < Min_Q or else S.Qyy < Min_Q
      then
         Collinear (Status);
         return;
      end if;
      Set_Success (Status);
   end Check_Spread;

   Scale_Limit : constant := 2.0 ** 60;

   procedure Aspect_Scalings
     (S          : Sums;
      Theta      : Long_Float;
      Sx_N, Sy_N : out Long_Float)
   with
     Pre  => S.Qxx >= Min_Q and then S.Qyy >= Min_Q,
     Post => abs Sx_N <= Scale_Limit and then abs Sy_N <= Scale_Limit;
   --  The best scalings of the scaled points along the axes of B for the
   --  rotation Theta: (sum of q_x (R^T p)_x) / Qxx and
   --  (sum of q_y (R^T p)_y) / Qyy (at most 2**21 / Min_Q, below 2**58).

   procedure Aspect_Scalings
     (S          : Sums;
      Theta      : Long_Float;
      Sx_N, Sy_N : out Long_Float)
   is
      Cos_T : constant Long_Float := EF.Cos (Theta);
      Sin_T : constant Long_Float := EF.Sin (Theta);
   begin
      Sx_N := Ratio (N.Times_Unit (S.Hxx, Cos_T) + N.Times_Unit (S.Hyx, Sin_T),
                     S.Qxx, Scale_Limit);
      Sy_N := Ratio (N.Times_Unit (S.Hyy, Cos_T) - N.Times_Unit (S.Hxy, Sin_T),
                     S.Qyy, Scale_Limit);
   end Aspect_Scalings;

   Quadratic_Limit : constant := 2.0 ** 80;

   function Aspect_Angle (S : Sums) return Long_Float
   with
     Pre  => S.Qxx >= Min_Q and then S.Qyy >= Min_Q,
     Post => Aspect_Angle'Result > -Pi / 2.0
             and then Aspect_Angle'Result <= Pi / 2.0;
   --  The angle that maximises f (Theta) = (h1 . v)**2 / Qxx +
   --  (h2 . v)**2 / Qyy over v = (cos Theta, sin Theta), with h1 = (Hxx,
   --  Hyx) and h2 = (Hyy, -Hxy): the principal axis of the 2 x 2 matrix of
   --  that quadratic form (0 when the form is isotropic). The terms are at
   --  most 2**40 / Min_Q, below 2**77.

   function Aspect_Angle (S : Sums) return Long_Float is
      function Term (X, Y, Q : Long_Float) return Long_Float is
        (Ratio (N.Mul_Within (X, Y, Sum_Limit, Sum_Limit), Q,
                Quadratic_Limit))
      with Pre  => abs X <= Sum_Limit and then abs Y <= Sum_Limit
                   and then Q >= Min_Q and then Q <= Sum_Limit,
           Post => abs Term'Result <= Quadratic_Limit;
      K11 : constant Long_Float :=
        Term (S.Hxx, S.Hxx, S.Qxx) + Term (S.Hyy, S.Hyy, S.Qyy);
      K22 : constant Long_Float :=
        Term (S.Hyx, S.Hyx, S.Qxx) + Term (S.Hxy, S.Hxy, S.Qyy);
      K12 : constant Long_Float :=
        Term (S.Hxx, S.Hyx, S.Qxx) - Term (S.Hyy, S.Hxy, S.Qyy);
      Y   : constant Long_Float := 2.0 * K12;
      X   : constant Long_Float := K11 - K22;
   begin
      if X = 0.0 and then Y = 0.0 then
         return 0.0;
      end if;
      return 0.5 * N.Direction (Y, X);
   end Aspect_Angle;

   procedure Aspect_Result
     (Pairs  : Pair_Array;
      Count  : Positive;
      F      : Frame;
      Sx, Sy : Long_Float;
      Theta  : Long_Float;
      Result : out Ks_N_Point_To_N_Point_Fit;
      Status : out Ks_Status)
   with
     Pre  => Pairs'First = 0 and then Count <= Max_Pairs
             and then Count - 1 <= Pairs'Last
             and then Sx > 0.0 and then Sx <= Max_Value
             and then Sy >= -Max_Value and then Sy <= Max_Value
             and then Theta > -Pi and then Theta <= Pi,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Gold_Fit
                              (Result,
                               DOF_Scaling_Aspect_Rotation_And_Translation)
                       else Result = Identity_Fit);
   --  The fit with the columns Sx (cos Theta, sin Theta) and
   --  Sy (-sin Theta, cos Theta).

   procedure Aspect_Result
     (Pairs  : Pair_Array;
      Count  : Positive;
      F      : Frame;
      Sx, Sy : Long_Float;
      Theta  : Long_Float;
      Result : out Ks_N_Point_To_N_Point_Fit;
      Status : out Ks_Status)
   is
      Cos_T : constant Long_Float := EF.Cos (Theta);
      Sin_T : constant Long_Float := EF.Sin (Theta);
      T     : KT.Ks_Transform_2D_Linear :=
        (A             => Sx * Cos_T,
         B             => -(Sy * Sin_T),
         C             => Sx * Sin_T,
         D             => Sy * Cos_T,
         Translation_X => 0.0,
         Translation_Y => 0.0);
      Fits  : Boolean;
   begin
      Result := Identity_Fit;
      --  A guard: each entry is a product of a value within the bound
      --  and a cosine or a sine.
      if not KT.Bounded (T) then
         Beyond (Status);
         return;
      end if;
      Shift (T.A, T.B, T.C, T.D, F, T.Translation_X, T.Translation_Y, Fits);
      if not Fits then
         Beyond (Status);
         return;
      end if;
      pragma Assert
        (T.A = Sx * EF.Cos (Theta) and then T.C = Sx * EF.Sin (Theta)
         and then T.B = -(Sy * EF.Sin (Theta))
         and then T.D = Sy * EF.Cos (Theta));
      Finish (Pairs, Count, T, Sx, Sy, Theta, 0.0, Result, Status);
   end Aspect_Result;

   procedure Fit_Aspect
     (Pairs  : Pair_Array;
      Count  : Positive;
      F      : Frame;
      S      : Sums;
      Result : out Ks_N_Point_To_N_Point_Fit;
      Status : out Ks_Status)
   with
     Pre  => Pairs'First = 0 and then Count <= Max_Pairs
             and then Count - 1 <= Pairs'Last
             and then F.SB > 0.0,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Gold_Fit
                              (Result,
                               DOF_Scaling_Aspect_Rotation_And_Translation)
                       else Result = Identity_Fit);

   procedure Fit_Aspect
     (Pairs  : Pair_Array;
      Count  : Positive;
      F      : Frame;
      S      : Sums;
      Result : out Ks_N_Point_To_N_Point_Fit;
      Status : out Ks_Status)
   is
      K_Limit    : constant := 2.0 ** 440;
      Theta      : Long_Float;
      Sx_N, Sy_N : Long_Float;
      K          : Long_Float;
      K_Fits     : Boolean;
      Sx, Sy     : Long_Float;
   begin
      Result := Identity_Fit;
      Check_Spread (S, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Theta := Aspect_Angle (S);
      Aspect_Scalings (S, Theta, Sx_N, Sy_N);
      if Sx_N < 0.0 then
         --  Half a turn more makes Sx positive (and flips Sy).
         Theta := N.Reduce_Two_Pi (Theta + Pi);
         Aspect_Scalings (S, Theta, Sx_N, Sy_N);
      end if;
      if Sx_N <= 0.0
        or else abs Sy_N < Singular_Tolerance * Sx_N
        or else Sx_N < Singular_Tolerance * abs Sy_N
      then
         Singular (Status);
         return;
      end if;
      N.Ratio_Within (F.SA, F.SB, K_Limit, K, K_Fits);
      if not K_Fits then
         Beyond (Status);
         return;
      end if;
      Sx := N.Mul_Within (Sx_N, K, Scale_Limit, K_Limit);
      Sy := N.Mul_Within (Sy_N, K, Scale_Limit, K_Limit);
      if Sx not in Coordinate or else Sy not in Coordinate or else Sx <= 0.0
      then
         Beyond (Status);
         return;
      end if;
      Aspect_Result (Pairs, Count, F, Sx, Sy, Theta, Result, Status);
   end Fit_Aspect;

   procedure Fit_Affine
     (Pairs  : Pair_Array;
      Count  : Positive;
      F      : Frame;
      S      : Sums;
      Result : out Ks_N_Point_To_N_Point_Fit;
      Status : out Ks_Status)
   with
     Pre  => Pairs'First = 0 and then Count <= Max_Pairs
             and then Count - 1 <= Pairs'Last
             and then F.SB > 0.0,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Gold_Fit
                              (Result,
                               DOF_Scaling_Aspect_Rotation_Skew_And_Translation)
                       else Result = Identity_Fit);
   --  M = H Q^-1 on the scaled points (the normal equations), scaled back
   --  by SA / SB. The entries of M are at most 2**41 / Min_Det_Q, below
   --  2**77.

   procedure Fit_Affine
     (Pairs  : Pair_Array;
      Count  : Positive;
      F      : Frame;
      S      : Sums;
      Result : out Ks_N_Point_To_N_Point_Fit;
      Status : out Ks_Status)
   is
      K_Limit : constant := 2.0 ** 420;
      M_Limit : constant := Quadratic_Limit;

      function Product (X, Y : Long_Float) return Long_Float is
        (N.Mul_Within (X, Y, Sum_Limit, Sum_Limit))
      with Pre  => abs X <= Sum_Limit and then abs Y <= Sum_Limit,
           Post => abs Product'Result <= 2.0 ** 40;

      M11, M12, M21, M22 : Long_Float;
      Largest            : Long_Float;
      Det_M              : Long_Float;
      K                  : Long_Float;
      K_Fits             : Boolean;
      T                  : KT.Ks_Transform_2D_Linear;
      Fits               : Boolean;
      Parts              : KT.Ks_Decomposition;
   begin
      Result := Identity_Fit;
      Check_Spread (S, Status);
      if not Succeeded (Status) then
         return;
      end if;
      declare
         Det_Q : constant Long_Float := Scatter_Det (S);
      begin
         M11 := Ratio (Product (S.Hxx, S.Qyy) - Product (S.Hxy, S.Qxy), Det_Q,
                       M_Limit);
         M12 := Ratio (Product (S.Hxy, S.Qxx) - Product (S.Hxx, S.Qxy), Det_Q,
                       M_Limit);
         M21 := Ratio (Product (S.Hyx, S.Qyy) - Product (S.Hyy, S.Qxy), Det_Q,
                       M_Limit);
         M22 := Ratio (Product (S.Hyy, S.Qxx) - Product (S.Hyx, S.Qxy), Det_Q,
                       M_Limit);
      end;
      Largest := Long_Float'Max (Long_Float'Max (abs M11, abs M12),
                                 Long_Float'Max (abs M21, abs M22));
      Det_M := N.Mul_Within (M11, M22, M_Limit, M_Limit)
               - N.Mul_Within (M12, M21, M_Limit, M_Limit);
      if Largest = 0.0
        or else abs Det_M
                  < Singular_Tolerance * N.Square_Within (Largest, M_Limit)
      then
         Singular (Status);
         return;
      end if;
      N.Ratio_Within (F.SA, F.SB, K_Limit, K, K_Fits);
      if not K_Fits then
         Beyond (Status);
         return;
      end if;
      T := (A             => N.Mul_Within (M11, K, M_Limit, K_Limit),
            B             => N.Mul_Within (M12, K, M_Limit, K_Limit),
            C             => N.Mul_Within (M21, K, M_Limit, K_Limit),
            D             => N.Mul_Within (M22, K, M_Limit, K_Limit),
            Translation_X => 0.0,
            Translation_Y => 0.0);
      if not KT.Bounded (T) then
         Beyond (Status);
         return;
      end if;
      Shift (T.A, T.B, T.C, T.D, F, T.Translation_X, T.Translation_Y, Fits);
      if not Fits then
         Beyond (Status);
         return;
      end if;
      KT.Decompose (T, Parts, Status);
      if not Succeeded (Status) then
         Singular (Status);
         return;
      end if;
      Finish (Pairs, Count, T, Parts.Scaling_X, Parts.Scaling_Y,
              Parts.Rotation_X, Parts.Skew, Result, Status);
   end Fit_Affine;

   ---------------------------------------------------------------------
   --  Fit
   ---------------------------------------------------------------------

   procedure Fit
     (Pairs  : Pair_Array;
      Count  : Natural;
      DOF    : DOF_Code;
      Result : out Ks_N_Point_To_N_Point_Fit;
      Status : out Ks_Status)
   is
   begin
      Result := Identity_Fit;
      if DOF = DOF_None then
         Finish (Pairs, Count, KT.Ks_Transform_2D_Linear'(others => <>),
                 1.0, 1.0, 0.0, 0.0, Result, Status);
         return;
      elsif DOF in DOF_Translation_X .. DOF_Translation then
         Fit_Translation (Pairs, Count, DOF, Result, Status);
         return;
      end if;
      declare
         F : constant Frame := Frame_Of (Pairs, Count);
      begin
         if F.SB = 0.0 then
            Coincident (Status);
            return;
         end if;
         declare
            S : constant Sums := Sums_Of (Pairs, Count, F);
         begin
            case DOF is
               when DOF_Rotation_And_Translation =>
                  Fit_Rigid (Pairs, Count, F, S, Result, Status);
               when DOF_Scaling_Rotation_And_Translation =>
                  Fit_Similarity (Pairs, Count, F, S, Result, Status);
               when DOF_Scaling_Aspect_Rotation_And_Translation =>
                  Fit_Aspect (Pairs, Count, F, S, Result, Status);
               when others =>
                  Fit_Affine (Pairs, Count, F, S, Result, Status);
            end case;
         end;
      end;
   end Fit;

end AMV.Kernels.Calib_Fix.DOF_Fits;
