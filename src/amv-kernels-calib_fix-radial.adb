pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Unchecked_Deallocation;

with AMV.Kernels.Calib_Fix.Solver;
with AMV.Kernels.Numerics;

package body AMV.Kernels.Calib_Fix.Radial with SPARK_Mode is

   package N renames AMV.Kernels.Numerics;
   package LS renames AMV.Kernels.Calib_Fix.Solver;

   ---------------------------------------------------------------------
   --  The normalised points
   ---------------------------------------------------------------------

   type Sample is record
      U, V : Unit_Value := 0.0;
      X, Y : Unit_Value := 0.0;
   end record;
   --  An observed point: its normalised plate point (U, V) and its
   --  normalised pixel position (X, Y).

   type Sample_Array is array (Natural range <>) of Sample;

   type Sample_Array_Access is access Sample_Array;

   procedure Free is new Ada.Unchecked_Deallocation
     (Sample_Array, Sample_Array_Access);

   procedure Allocate_Samples
     (Count   : Positive;
      Samples : out Sample_Array_Access)
   with
     Global => null,
     Pre    => Count <= Max_Warp_Points,
     Post   => (if Samples /= null
                then Samples'First = 0 and then Samples'Last = Count - 1);
   --  A new array of Count samples (the record's defaults), or null when
   --  the memory cannot be allocated. Trusted: the allocator raises
   --  Storage_Error, which SPARK cannot express.

   procedure Allocate_Samples
     (Count   : Positive;
      Samples : out Sample_Array_Access)
     with SPARK_Mode => Off
   is
   begin
      Samples := new Sample_Array (0 .. Count - 1);
   exception
      when Storage_Error =>
         Samples := null;
   end Allocate_Samples;

   procedure Bad (Status : out Ks_Status; Message : String)
   with
     Pre  => Message'Length <= 160,
     Post => Valid (Status) and then Status.Failure = Failure_Bad_Parameter;

   procedure Bad (Status : out Ks_Status; Message : String) is
   begin
      Set_Failure (Status, Failure_Bad_Parameter, Message);
   end Bad;

   ---------------------------------------------------------------------
   --  The valid radius
   ---------------------------------------------------------------------

   Radius_Step : constant := Max_Radius_Squared / Long_Float (Radius_Steps);

   function Stretch (K1, K2 : K_Value; Rho : Rho_Value) return Long_Float
   is
     (1.0
      + 3.0 * N.Mul_Within (K1, Rho, Max_Radial_Coefficient,
                            Max_Radius_Squared)
      + 5.0 * N.Mul_Within (K2, N.Square_Within (Rho, Max_Radius_Squared),
                            Max_Radial_Coefficient,
                            Max_Radius_Squared * Max_Radius_Squared));
   --  The derivative of r -> r (1 + K1 r**2 + K2 r**4) at r**2 = Rho.

   function Valid_Radius (K1, K2 : K_Value) return Rho_Value is
   begin
      for J in 1 .. Radius_Steps loop
         pragma Loop_Invariant (True);
         if not (Stretch (K1, K2, Long_Float (J) * Radius_Step)
                   >= Min_Stretch)
         then
            return Long_Float (J - 1) * Radius_Step;
         end if;
      end loop;
      return Max_Radius_Squared;
   end Valid_Radius;

   ---------------------------------------------------------------------
   --  One point of the model
   ---------------------------------------------------------------------

   procedure Evaluate
     (P     : Params;
      U, V  : Grid_Value;
      Min_W : Long_Float;
      E     : out Evaluation;
      OK    : out Boolean)
   is
      NX  : constant Long_Float :=
        N.Mul_Within (P.H11, U, Max_Homography_Entry, Grid_Limit)
        + N.Mul_Within (P.H12, V, Max_Homography_Entry, Grid_Limit)
        + P.H13;
      NY  : constant Long_Float :=
        N.Mul_Within (P.H21, U, Max_Homography_Entry, Grid_Limit)
        + N.Mul_Within (P.H22, V, Max_Homography_Entry, Grid_Limit)
        + P.H23;
      W   : constant Long_Float :=
        1.0
        + N.Mul_Within (P.H31, U, Max_Perspective_Entry, Grid_Limit)
        + N.Mul_Within (P.H32, V, Max_Perspective_Entry, Grid_Limit);
      A, B : Ideal_Value;
      Rho  : Long_Float;
   begin
      E := (others => <>);
      OK := False;
      if not (W > 0.0 and then W >= Min_W) then
         return;
      elsif not (abs NX <= Max_Ideal * W and then abs NY <= Max_Ideal * W)
      then
         return;
      end if;
      A := Max_Ideal * N.Unit_Ratio (NX, Max_Ideal * W);
      B := Max_Ideal * N.Unit_Ratio (NY, Max_Ideal * W);
      Rho := N.Square_Within (A, Max_Ideal) + N.Square_Within (B, Max_Ideal);
      if not (Rho <= P.Rho_Max) then
         return;
      end if;
      E.A := A;
      E.B := B;
      E.W := W;
      E.Rho := Rho;
      E.Rho2 := N.Square_Within (Rho, Max_Radius_Squared);
      E.F := 1.0
        + N.Mul_Within (P.K1, Rho, Max_Radial_Coefficient, Max_Radius_Squared)
        + N.Mul_Within (P.K2, E.Rho2, Max_Radial_Coefficient, 256.0);
      E.G := P.K1
        + 2.0 * N.Mul_Within (P.K2, Rho, Max_Radial_Coefficient,
                              Max_Radius_Squared);
      E.MX := N.Mul_Within (E.F, A, F_Limit, Max_Ideal);
      E.MY := N.Mul_Within (E.F, B, F_Limit, Max_Ideal);
      OK := True;
   end Evaluate;

   ---------------------------------------------------------------------
   --  Normalisation
   ---------------------------------------------------------------------

   function Normaliser (Width, Height : Int32) return Long_Float is
      Half_X : constant Long_Float := Long_Float (Width - 1) * 0.5;
      Half_Y : constant Long_Float := Long_Float (Height - 1) * 0.5;
      Half_D : constant Long_Float :=
        N.Hypot (Long_Float (Width), Long_Float (Height)) * 0.5;
   begin
      return Long_Float'Min
        (Max_Model_Coordinate,
         Long_Float'Max (Half_D,
                         Long_Float'Max (0.5,
                                         Long_Float'Max (Half_X, Half_Y))));
   end Normaliser;

   procedure Make_Frame
     (Points        : Observation_Array;
      Count         : Natural;
      Width, Height : Int32;
      F             : out Frame;
      Status        : out Ks_Status)
   with
     Pre  => Points'First = 0
             and then Count in Min_Warp_Points .. Max_Warp_Points
             and then Count - 1 <= Points'Last
             and then Width in 1 .. Max_Model_Side
             and then Height in 1 .. Max_Model_Side,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then F.CX = Long_Float (Width - 1) * 0.5
             and then F.CY = Long_Float (Height - 1) * 0.5;
   --  The normalisation of the points. Bad_Parameter when the plate
   --  points span less than 2 Min_Plate_Scale (every corner of a
   --  checkerboard with the same grid indices, which the detector never
   --  returns; equal raw calibrated points).

   procedure Make_Frame
     (Points        : Observation_Array;
      Count         : Natural;
      Width, Height : Int32;
      F             : out Frame;
      Status        : out Ks_Status)
   is
      Min_X, Max_X : Coordinate := Points (0).Plate_X;
      Min_Y, Max_Y : Coordinate := Points (0).Plate_Y;
      Span         : Long_Float range 0.0 .. 2.0 * Max_Value;
   begin
      F := (CX     => Long_Float (Width - 1) * 0.5,
            CY     => Long_Float (Height - 1) * 0.5,
            S      => Normaliser (Width, Height),
            others => <>);
      for K in 1 .. Count - 1 loop
         Min_X := Long_Float'Min (Min_X, Points (K).Plate_X);
         Max_X := Long_Float'Max (Max_X, Points (K).Plate_X);
         Min_Y := Long_Float'Min (Min_Y, Points (K).Plate_Y);
         Max_Y := Long_Float'Max (Max_Y, Points (K).Plate_Y);
         pragma Loop_Invariant (Min_X <= Max_X and then Min_Y <= Max_Y);
      end loop;
      Span := Long_Float'Max (Max_X - Min_X, Max_Y - Min_Y);
      if not (Span * 0.5 >= Min_Plate_Scale) then
         Bad (Status, "Calibrate: the points do not span the plate "
                      & "(PerspectiveAndRadialWarp)");
         return;
      end if;
      --  Exact for grid indices: their sums and differences are integers
      --  far below 2**53, and halving is exact.
      F.GX := (Min_X + Max_X) * 0.5;
      F.GY := (Min_Y + Max_Y) * 0.5;
      --  Span * 0.5 is in [Min_Plate_Scale, Max_Value]: the limits never
      --  act.
      F.SG := Long_Float'Min
        (Max_Value, Long_Float'Max (Min_Plate_Scale, Span * 0.5));
      Set_Success (Status);
   end Make_Frame;

   procedure Make_Samples
     (Points  : Observation_Array;
      Count   : Natural;
      F       : Frame;
      Samples : in out Sample_Array;
      Status  : out Ks_Status)
   with
     Pre  => Points'First = 0
             and then Count in Min_Warp_Points .. Max_Warp_Points
             and then Count - 1 <= Points'Last
             and then Samples'First = 0
             and then Samples'Last = Count - 1,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter;
   --  The normalised points. Bad_Parameter when a point lies outside
   --  the frame (a guard for the plate points, which lie in their
   --  bounding box; a corner lies in the image, and the parent checks
   --  that an N-point calibration's points do).

   procedure Make_Samples
     (Points  : Observation_Array;
      Count   : Natural;
      F       : Frame;
      Samples : in out Sample_Array;
      Status  : out Ks_Status)
   is
      DU, DV, DX, DY : Long_Float;
   begin
      for K in 0 .. Count - 1 loop
         DU := Points (K).Plate_X - F.GX;
         DV := Points (K).Plate_Y - F.GY;
         DX := Points (K).Pixel_X - F.CX;
         DY := Points (K).Pixel_Y - F.CY;
         if not (abs DU <= F.SG and then abs DV <= F.SG
                 and then abs DX <= F.S and then abs DY <= F.S)
         then
            Bad (Status, "Calibrate: a point lies outside the image "
                         & "(PerspectiveAndRadialWarp)");
            return;
         end if;
         Samples (K) := (U => N.Unit_Ratio (DU, F.SG),
                         V => N.Unit_Ratio (DV, F.SG),
                         X => N.Unit_Ratio (DX, F.S),
                         Y => N.Unit_Ratio (DY, F.S));
      end loop;
      Set_Success (Status);
   end Make_Samples;

   ---------------------------------------------------------------------
   --  Points on one line
   ---------------------------------------------------------------------

   Sum_Limit : constant := 2.0 ** 17;
   subtype Sum_Value is Long_Float range -Sum_Limit .. Sum_Limit;
   --  A sum of at most Max_Warp_Points values in [-1, 1].

   Moment_Limit : constant := 2.0 ** 19;
   subtype Moment_Value is Long_Float range -Moment_Limit .. Moment_Limit;
   --  A sum of at most Max_Warp_Points products of values in [-2, 2].

   function Mean (Sum : Sum_Value; Count : Positive) return Unit_Value
   with Pre => Count <= Max_Warp_Points;
   --  Sum / Count limited to [-1, 1] (Sum is a sum of Count values in
   --  [-1, 1]: the limit never acts).

   function Mean (Sum : Sum_Value; Count : Positive) return Unit_Value is
      Q    : Long_Float;
      Fits : Boolean;
   begin
      N.Ratio_Within (abs Sum, Long_Float (Count), 1.0, Q, Fits);
      return (if not Fits then 0.0 elsif Sum < 0.0 then -Q else Q);
   end Mean;

   function First_Of (S : Sample; Plate : Boolean) return Unit_Value is
     (if Plate then S.U else S.X);
   function Second_Of (S : Sample; Plate : Boolean) return Unit_Value is
     (if Plate then S.V else S.Y);
   --  The normalised plate point (Plate) or pixel position of a sample.

   function Flat
     (Samples : Sample_Array;
      Count   : Natural;
      Plate   : Boolean) return Boolean
   with Pre => Samples'First = 0
               and then Count in 1 .. Max_Warp_Points
               and then Count - 1 <= Samples'Last;
   --  The normalised plate points (Plate) or pixel positions of the
   --  samples lie on one line, or nearly so: the determinant of their
   --  scatter matrix about their centroid is at most Collinear_Tolerance
   --  times its squared trace (scale free, as for the DOF fits; True when
   --  they all coincide).

   function Flat
     (Samples : Sample_Array;
      Count   : Natural;
      Plate   : Boolean) return Boolean
   is
      Sum_A, Sum_B    : Sum_Value := 0.0;
      Mean_A, Mean_B  : Unit_Value;
      DA, DB          : Long_Float range -2.0 .. 2.0;
      SAA, SAB, SBB   : Moment_Value := 0.0;
      Det, Trace_Sq   : Long_Float;
   begin
      for K in 0 .. Count - 1 loop
         Sum_A := N.Clamp (Sum_A + First_Of (Samples (K), Plate), Sum_Limit);
         Sum_B := N.Clamp (Sum_B + Second_Of (Samples (K), Plate),
                           Sum_Limit);
      end loop;
      Mean_A := Mean (Sum_A, Count);
      Mean_B := Mean (Sum_B, Count);
      for K in 0 .. Count - 1 loop
         DA := First_Of (Samples (K), Plate) - Mean_A;
         DB := Second_Of (Samples (K), Plate) - Mean_B;
         SAA := N.Clamp (SAA + N.Square_Within (DA, 2.0), Moment_Limit);
         SAB := N.Clamp (SAB + N.Mul_Within (DA, DB, 2.0, 2.0),
                         Moment_Limit);
         SBB := N.Clamp (SBB + N.Square_Within (DB, 2.0), Moment_Limit);
      end loop;
      Det := N.Mul_Within (SAA, SBB, Moment_Limit, Moment_Limit)
             - N.Square_Within (SAB, Moment_Limit);
      Trace_Sq := N.Square_Within (SAA + SBB, 2.0 * Moment_Limit);
      return not (Det > Collinear_Tolerance * Trace_Sq);
   end Flat;

   ---------------------------------------------------------------------
   --  The homography (DLT)
   ---------------------------------------------------------------------

   DLT_Limit : constant := 2.0 ** 20;
   --  An entry of the DLT's normal equations is a sum of at most two
   --  products in [-1, 1] per point, at most 2**17 in all.

   type Unit_Row is array (LS.Order) of Unit_Value;

   procedure Add_Row
     (A     : in out LS.Matrix;
      B     : in out LS.Vector;
      R     : Unit_Row;
      Right : Unit_Value);
   --  Adds R**T R to A (1 .. 8, 1 .. 8) and R * Right to B (1 .. 8),
   --  each entry limited to DLT_Limit (the limit never acts).

   procedure Add_Row
     (A     : in out LS.Matrix;
      B     : in out LS.Vector;
      R     : Unit_Row;
      Right : Unit_Value) is
   begin
      for I in 1 .. 8 loop
         pragma Loop_Invariant (True);
         for J in 1 .. 8 loop
            pragma Loop_Invariant (True);
            A (I, J) := N.Clamp (A (I, J) + N.Times_Unit (R (I), R (J)),
                                 DLT_Limit);
         end loop;
         B (I) := N.Clamp (B (I) + N.Times_Unit (R (I), Right), DLT_Limit);
      end loop;
   end Add_Row;

   procedure Initial_Homography
     (Samples : Sample_Array;
      Count   : Natural;
      P       : out Params;
      Status  : out Ks_Status)
   with
     Pre  => Samples'First = 0 and then Count >= 1
             and then Count - 1 <= Samples'Last,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then P.K1 = 0.0 and then P.K2 = 0.0);
   --  The DLT: the homography with H33 = 1 that solves w m = N in the
   --  least squares sense, without distortion. Bad_Parameter for a
   --  singular system and a homography beyond the bounds.

   procedure Initial_Homography
     (Samples : Sample_Array;
      Count   : Natural;
      P       : out Params;
      Status  : out Ks_Status)
   is
      A     : LS.Matrix := [others => [others => 0.0]];
      B     : LS.Vector := [others => 0.0];
      H     : LS.Solution;
      Found : Boolean;
   begin
      P := (others => <>);
      for K in 0 .. Count - 1 loop
         declare
            S : constant Sample := Samples (K);
         begin
            Add_Row (A, B,
                     [S.U, S.V, 1.0, 0.0, 0.0, 0.0,
                      -N.Times_Unit (S.U, S.X), -N.Times_Unit (S.V, S.X),
                      0.0, 0.0],
                     S.X);
            Add_Row (A, B,
                     [0.0, 0.0, 0.0, S.U, S.V, 1.0,
                      -N.Times_Unit (S.U, S.Y), -N.Times_Unit (S.V, S.Y),
                      0.0, 0.0],
                     S.Y);
         end;
      end loop;
      LS.Solve (A, B, 8, H, Found);
      if not Found then
         Bad (Status, "Calibrate: the points do not determine a "
                      & "homography (PerspectiveAndRadialWarp)");
         return;
      end if;
      if not (abs H (1) <= Max_Homography_Entry
              and then abs H (2) <= Max_Homography_Entry
              and then abs H (3) <= Max_Homography_Entry
              and then abs H (4) <= Max_Homography_Entry
              and then abs H (5) <= Max_Homography_Entry
              and then abs H (6) <= Max_Homography_Entry
              and then abs H (7) <= Max_Perspective_Entry
              and then abs H (8) <= Max_Perspective_Entry)
      then
         Bad (Status, "Calibrate: the homography of the points exceeds "
                      & "its bounds (PerspectiveAndRadialWarp)");
         return;
      end if;
      P := (H11 => H (1), H12 => H (2), H13 => H (3),
            H21 => H (4), H22 => H (5), H23 => H (6),
            H31 => H (7), H32 => H (8),
            K1 => 0.0, K2 => 0.0,
            Rho_Max => Valid_Radius (0.0, 0.0));
      Set_Success (Status);
   end Initial_Homography;

   ---------------------------------------------------------------------
   --  The sum of squared distances
   ---------------------------------------------------------------------

   Residual_Limit : constant := 2.0 ** 14;
   --  A normalised point (within 1) minus a model point (within M_Limit).

   Cost_Limit : constant := 2.0 ** 62;
   subtype Cost_Value is Long_Float range 0.0 .. Cost_Limit;
   --  At most Max_Warp_Points terms of at most 2 * Residual_Limit**2 = 2**29:
   --  the limit never acts.

   procedure Cost_Of
     (Samples : Sample_Array;
      Count   : Natural;
      P       : Params;
      Cost    : out Cost_Value;
      OK      : out Boolean)
   with
     Pre => Samples'First = 0 and then Count - 1 <= Samples'Last;
   --  The sum of the squared distances between the points and the
   --  model. OK is False (and Cost 0) when a point is not valid.

   procedure Cost_Of
     (Samples : Sample_Array;
      Count   : Natural;
      P       : Params;
      Cost    : out Cost_Value;
      OK      : out Boolean)
   is
      E     : Evaluation;
      Valid : Boolean;
   begin
      Cost := 0.0;
      OK := False;
      for K in 0 .. Count - 1 loop
         Evaluate (P, Samples (K).U, Samples (K).V, Min_Denominator, E,
                   Valid);
         if not Valid then
            Cost := 0.0;
            return;
         end if;
         Cost := Long_Float'Min
           (Cost
            + N.Square_Within (Samples (K).X - E.MX, Residual_Limit)
            + N.Square_Within (Samples (K).Y - E.MY, Residual_Limit),
            Cost_Limit);
      end loop;
      OK := True;
   end Cost_Of;

   ---------------------------------------------------------------------
   --  The normal equations of a Gauss-Newton step
   ---------------------------------------------------------------------

   Jac_Limit : constant := 2.0 ** 21;
   subtype Jac_Value is Long_Float range -Jac_Limit .. Jac_Limit;
   type Jac_Row is array (LS.Order) of Jac_Value;

   Acc_Limit : constant := 2.0 ** 62;
   --  A sum of at most Max_Warp_Points terms of at most 2 * Jac_Limit**2 =
   --  2**43 (the Jacobian) or 2 * Jac_Limit * Residual_Limit = 2**36
   --  (the gradient): the limit never acts.

   subtype Acc_Value is Long_Float range -Acc_Limit .. Acc_Limit;
   type Acc_Matrix is array (LS.Order, LS.Order) of Acc_Value;
   type Acc_Vector is array (LS.Order) of Acc_Value;

   procedure Jacobian_Rows
     (U, V   : Unit_Value;
      E      : Evaluation;
      RX, RY : out Jac_Row)
   with Pre => E.W >= Min_Denominator;
   --  The derivatives of the model point (MX, MY) by the parameters
   --  (H11, H12, H13, H21, H22, H23, H31, H32, K1, K2) at the grid point
   --  (U, V). With the ideal point h = N / w and m = F h:
   --  dm = M dh with M = F I + 2 G h h**T, dh / dH1j = (g_j / w, 0),
   --  dh / dH2j = (0, g_j / w) (g_3 = 1) and dh / dH3j = -h g_j / w;
   --  dm / dK1 = Rho h and dm / dK2 = Rho2 h.

   procedure Jacobian_Rows
     (U, V   : Unit_Value;
      E      : Evaluation;
      RX, RY : out Jac_Row)
   is
      IW  : constant Long_Float :=
        16.0 * N.Unit_Ratio (Min_Denominator, E.W);
      A2  : constant Long_Float := N.Square_Within (E.A, Max_Ideal);
      B2  : constant Long_Float := N.Square_Within (E.B, Max_Ideal);
      AB  : constant Long_Float := N.Mul_Within (E.A, E.B, Max_Ideal,
                                                 Max_Ideal);
      M11 : constant Long_Float :=
        E.F + 2.0 * N.Mul_Within (E.G, A2, G_Limit, 16.0);
      M12 : constant Long_Float :=
        2.0 * N.Mul_Within (E.G, AB, G_Limit, 16.0);
      M22 : constant Long_Float :=
        E.F + 2.0 * N.Mul_Within (E.G, B2, G_Limit, 16.0);
      Q11 : constant Long_Float := N.Mul_Within (M11, IW, 10240.0, 16.0);
      Q12 : constant Long_Float := N.Mul_Within (M12, IW, 8192.0, 16.0);
      Q22 : constant Long_Float := N.Mul_Within (M22, IW, 10240.0, 16.0);
      DX  : constant Long_Float :=
        N.Mul_Within (Q11, E.A, 163840.0, Max_Ideal)
        + N.Mul_Within (Q12, E.B, 131072.0, Max_Ideal);
      DY  : constant Long_Float :=
        N.Mul_Within (Q12, E.A, 131072.0, Max_Ideal)
        + N.Mul_Within (Q22, E.B, 163840.0, Max_Ideal);
   begin
      RX := [N.Times_Unit (Q11, U), N.Times_Unit (Q11, V), Q11,
             N.Times_Unit (Q12, U), N.Times_Unit (Q12, V), Q12,
             -N.Times_Unit (DX, U), -N.Times_Unit (DX, V),
             N.Mul_Within (E.Rho, E.A, Max_Radius_Squared, Max_Ideal),
             N.Mul_Within (E.Rho2, E.A, 256.0, Max_Ideal)];
      RY := [N.Times_Unit (Q12, U), N.Times_Unit (Q12, V), Q12,
             N.Times_Unit (Q22, U), N.Times_Unit (Q22, V), Q22,
             -N.Times_Unit (DY, U), -N.Times_Unit (DY, V),
             N.Mul_Within (E.Rho, E.B, Max_Radius_Squared, Max_Ideal),
             N.Mul_Within (E.Rho2, E.B, 256.0, Max_Ideal)];
   end Jacobian_Rows;

   procedure Add_Point
     (S      : in out Acc_Matrix;
      G      : in out Acc_Vector;
      RX, RY : Jac_Row;
      EX, EY : Long_Float)
   with Pre => abs EX <= Residual_Limit and then abs EY <= Residual_Limit;
   --  Adds the point's terms to the upper triangle of S = J**T J and to
   --  G = J**T e (each entry limited to Acc_Limit, which never acts).

   procedure Add_Point
     (S      : in out Acc_Matrix;
      G      : in out Acc_Vector;
      RX, RY : Jac_Row;
      EX, EY : Long_Float) is
   begin
      for I in LS.Order loop
         pragma Loop_Invariant (True);
         for J in I .. LS.Max_Order loop
            pragma Loop_Invariant (True);
            S (I, J) := N.Clamp
              (S (I, J)
               + N.Mul_Within (RX (I), RX (J), Jac_Limit, Jac_Limit)
               + N.Mul_Within (RY (I), RY (J), Jac_Limit, Jac_Limit),
               Acc_Limit);
         end loop;
         G (I) := N.Clamp
           (G (I)
            + N.Mul_Within (RX (I), EX, Jac_Limit, Residual_Limit)
            + N.Mul_Within (RY (I), EY, Jac_Limit, Residual_Limit),
            Acc_Limit);
      end loop;
   end Add_Point;

   procedure Normal_Equations
     (Samples : Sample_Array;
      Count   : Natural;
      P       : Params;
      S       : out Acc_Matrix;
      G       : out Acc_Vector;
      OK      : out Boolean)
   with Pre => Samples'First = 0 and then Count - 1 <= Samples'Last;
   --  S = J**T J and G = J**T e for the model P (e the points minus the
   --  model). OK is False when a point is not valid.

   procedure Normal_Equations
     (Samples : Sample_Array;
      Count   : Natural;
      P       : Params;
      S       : out Acc_Matrix;
      G       : out Acc_Vector;
      OK      : out Boolean)
   is
      E      : Evaluation;
      RX, RY : Jac_Row;
      Valid  : Boolean;
   begin
      S := [others => [others => 0.0]];
      G := [others => 0.0];
      OK := False;
      for K in 0 .. Count - 1 loop
         Evaluate (P, Samples (K).U, Samples (K).V, Min_Denominator, E,
                   Valid);
         if not Valid then
            return;
         end if;
         Jacobian_Rows (Samples (K).U, Samples (K).V, E, RX, RY);
         Add_Point (S, G, RX, RY, Samples (K).X - E.MX,
                     Samples (K).Y - E.MY);
      end loop;
      --  The lower triangle mirrors the upper one.
      for I in 2 .. LS.Max_Order loop
         pragma Loop_Invariant (True);
         for J in 1 .. I - 1 loop
            pragma Loop_Invariant (True);
            S (I, J) := S (J, I);
         end loop;
      end loop;
      OK := True;
   end Normal_Equations;

   ---------------------------------------------------------------------
   --  Levenberg-Marquardt
   ---------------------------------------------------------------------

   Min_Lambda     : constant := 2.0 ** (-40);
   Max_Lambda     : constant := 2.0 ** 30;
   Initial_Lambda : constant := 2.0 ** (-10);
   Tiny_Diagonal  : constant := 2.0 ** (-60);

   subtype Lambda_Value is Long_Float range Min_Lambda .. Max_Lambda;

   procedure Damped
     (S      : Acc_Matrix;
      G      : Acc_Vector;
      Lambda : Lambda_Value;
      D      : out LS.Matrix;
      B      : out LS.Vector);
   --  D is S with every diagonal entry S (I, I) raised by Lambda times
   --  Max (S (I, I), Tiny_Diagonal) (Marquardt's scaling); B is G.

   procedure Damped
     (S      : Acc_Matrix;
      G      : Acc_Vector;
      Lambda : Lambda_Value;
      D      : out LS.Matrix;
      B      : out LS.Vector) is
   begin
      D := [for I in LS.Order =>
              [for J in LS.Order =>
                 (if I = J
                  then S (I, I)
                       + N.Mul_Within
                           (Lambda, Long_Float'Max (S (I, I), Tiny_Diagonal),
                            Max_Lambda, Acc_Limit)
                  else S (I, J))]];
      B := [for I in LS.Order => G (I)];
   end Damped;

   subtype Param_Value is
     Long_Float range -Max_Homography_Entry .. Max_Homography_Entry;
   type Param_Vector is array (LS.Order) of Param_Value;

   function To_Vector (P : Params) return Param_Vector is
     ([P.H11, P.H12, P.H13, P.H21, P.H22, P.H23, P.H31, P.H32, P.K1, P.K2]);

   type Sum_Vector is array (LS.Order) of Long_Float;

   procedure Step
     (P      : Params;
      Change : LS.Solution;
      Q      : out Params;
      OK     : out Boolean;
      Small  : out Boolean);
   --  Q = P + Change when every parameter stays within its bound (OK);
   --  Small tells whether no parameter changes by more than
   --  Step_Tolerance.

   procedure Step
     (P      : Params;
      Change : LS.Solution;
      Q      : out Params;
      OK     : out Boolean;
      Small  : out Boolean)
   is
      Base : constant Param_Vector := To_Vector (P);
      V    : constant Sum_Vector :=
        [for I in LS.Order => Base (I) + Change (I)];
   begin
      Q := P;
      OK := False;
      Small := (for all I in LS.Order => abs Change (I) <= Step_Tolerance);
      if not (abs V (1) <= Max_Homography_Entry
              and then abs V (2) <= Max_Homography_Entry
              and then abs V (3) <= Max_Homography_Entry
              and then abs V (4) <= Max_Homography_Entry
              and then abs V (5) <= Max_Homography_Entry
              and then abs V (6) <= Max_Homography_Entry
              and then abs V (7) <= Max_Perspective_Entry
              and then abs V (8) <= Max_Perspective_Entry
              and then abs V (9) <= Max_Radial_Coefficient
              and then abs V (10) <= Max_Radial_Coefficient)
      then
         return;
      end if;
      Q := (H11 => V (1), H12 => V (2), H13 => V (3),
            H21 => V (4), H22 => V (5), H23 => V (6),
            H31 => V (7), H32 => V (8),
            K1 => V (9), K2 => V (10),
            Rho_Max => Valid_Radius (V (9), V (10)));
      OK := True;
   end Step;

   procedure Refine
     (Samples    : Sample_Array;
      Count      : Natural;
      P          : in out Params;
      Cost       : in out Cost_Value;
      Iterations : out Natural)
   with
     Pre  => Samples'First = 0 and then Count - 1 <= Samples'Last,
     Post => Iterations <= Max_Iterations;
   --  The Levenberg-Marquardt iterations from P, whose cost is Cost (see
   --  the spec). P and Cost are those of the last accepted step.

   procedure Refine
     (Samples    : Sample_Array;
      Count      : Natural;
      P          : in out Params;
      Cost       : in out Cost_Value;
      Iterations : out Natural)
   is
      Lambda   : Lambda_Value := Initial_Lambda;
      S        : Acc_Matrix;
      G        : Acc_Vector;
      D        : LS.Matrix;
      B        : LS.Vector;
      Change   : LS.Solution;
      Q        : Params;
      New_Cost : Cost_Value;
      Found    : Boolean;
      OK       : Boolean;
      Small    : Boolean := False;
      Accepted : Boolean;
   begin
      Iterations := 0;
      for Iteration in 1 .. Max_Iterations loop
         pragma Loop_Invariant (Iterations < Iteration);
         Normal_Equations (Samples, Count, P, S, G, OK);
         exit when not OK;
         Accepted := False;
         for Try in 1 .. Max_Damping_Tries loop
            pragma Loop_Invariant (True);
            Damped (S, G, Lambda, D, B);
            LS.Solve (D, B, LS.Max_Order, Change, Found);
            if Found then
               Step (P, Change, Q, OK, Small);
               if OK then
                  Cost_Of (Samples, Count, Q, New_Cost, OK);
                  if OK and then New_Cost < Cost then
                     Small := Small
                       or else Cost - New_Cost <= Cost * 2.0 ** (-45);
                     P := Q;
                     Cost := New_Cost;
                     Lambda := Long_Float'Max (Lambda / 8.0, Min_Lambda);
                     Accepted := True;
                     exit;
                  end if;
               end if;
            end if;
            exit when Lambda >= Max_Lambda;
            Lambda := Long_Float'Min (Lambda * 8.0, Max_Lambda);
         end loop;
         exit when not Accepted;
         Iterations := Iterations + 1;
         exit when Small;
      end loop;
   end Refine;

   ---------------------------------------------------------------------
   --  Fit
   ---------------------------------------------------------------------

   procedure Fit
     (Points        : Observation_Array;
      Count         : Natural;
      Width, Height : Int32;
      P             : out Params;
      F             : out Frame;
      RMS           : out Long_Float;
      Iterations    : out Natural;
      Status        : out Ks_Status)
   is
      Samples : Sample_Array_Access;
      Cost    : Cost_Value;
      OK      : Boolean;
      Mean    : Long_Float;
      Fits    : Boolean;
      Root    : Long_Float;
   begin
      P := (others => <>);
      RMS := 0.0;
      Iterations := 0;
      Make_Frame (Points, Count, Width, Height, F, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Allocate_Samples (Count, Samples);
      if Samples = null then
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "Calibrate: not enough memory");
         return;
      end if;
      Make_Samples (Points, Count, F, Samples.all, Status);
      if Succeeded (Status)
        and then (Flat (Samples.all, Count, True)
                  or else Flat (Samples.all, Count, False))
      then
         Bad (Status, "Calibrate: the points lie on one line "
                      & "(PerspectiveAndRadialWarp)");
      end if;
      if Succeeded (Status) then
         Initial_Homography (Samples.all, Count, P, Status);
      end if;
      if not Succeeded (Status) then
         Free (Samples);
         return;
      end if;
      Cost_Of (Samples.all, Count, P, Cost, OK);
      if not OK then
         Free (Samples);
         Bad (Status, "Calibrate: the homography of the points sees a "
                      & "point too far off (PerspectiveAndRadialWarp)");
         return;
      end if;
      Refine (Samples.all, Count, P, Cost, Iterations);
      Free (Samples);

      --  The RMS distance in pixels: S times the root of the mean.
      N.Ratio_Within (Cost, Long_Float (Count), Cost_Limit, Mean, Fits);
      --  The mean is at most Cost: Fits always holds.
      Root := (if Fits then N.Clamp (EF.Sqrt (Mean), 2.0 ** 31)
               else 2.0 ** 31);
      RMS := Long_Float'Max
        (0.0, N.Mul_Within (F.S, Root, Max_Model_Coordinate, 2.0 ** 31));
      Set_Success (Status);
   end Fit;

end AMV.Kernels.Calib_Fix.Radial;
