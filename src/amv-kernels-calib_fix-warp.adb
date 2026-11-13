pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Numerics.Long_Elementary_Functions;

with AMV.Kernels.Image_Sampling;
with AMV.Kernels.Numerics;

package body AMV.Kernels.Calib_Fix.Warp with SPARK_Mode is

   package EF renames Ada.Numerics.Long_Elementary_Functions;
   package N renames AMV.Kernels.Numerics;
   package SM renames AMV.Kernels.Image_Sampling;

   procedure Bad (Status : out Ks_Status; Message : String)
   with
     Pre  => Message'Length <= 160,
     Post => Valid (Status) and then Status.Failure = Failure_Bad_Parameter;

   procedure Bad (Status : out Ks_Status; Message : String) is
   begin
      Set_Failure (Status, Failure_Bad_Parameter, Message);
   end Bad;

   ---------------------------------------------------------------------
   --  The model record
   ---------------------------------------------------------------------

   function Params_Of (Model : Ks_Radial_Warp_Model) return R.Params is
     (H11 => Model.H11, H12 => Model.H12, H13 => Model.H13,
      H21 => Model.H21, H22 => Model.H22, H23 => Model.H23,
      H31 => Model.H31, H32 => Model.H32,
      K1 => Model.K1, K2 => Model.K2,
      Rho_Max => Model.Valid_Radius_Squared);

   J_Limit : constant := 1088.0;
   --  An entry of the ideal point's derivative at the plate's centre:
   --  Max_Homography_Entry + Max_Ideal * Max_Perspective_Entry.

   Jn_Limit : constant := 2.0 ** 25;
   --  An entry of the observed point's derivative there: two products of
   --  at most 10240 * 1088.

   Min_Det : constant := 2.0 ** (-30);
   --  The smallest magnitude of the determinant of that derivative (in
   --  normalised units) that the warp accepts.

   Min_Scale : constant := 2.0 ** (-10);
   --  The smallest S * Sqrt (|det|) (output pixels per grid half extent)
   --  that the warp accepts.

   procedure Centre_Derivative
     (P        : R.Params;
      E        : R.Evaluation;
      J11, J12 : out Long_Float;
      J21, J22 : out Long_Float)
   with
     Post => abs J11 <= Jn_Limit and then abs J12 <= Jn_Limit
             and then abs J21 <= Jn_Limit and then abs J22 <= Jn_Limit;
   --  The derivative of the normalised observed point by the normalised
   --  plate point at the plate's centre g = 0, where w = 1: M D, with D
   --  the derivative of the ideal point, (H1j - A H3j, H2j - B H3j), and
   --  M = F I + 2 G h h**T the derivative of the radial map (E is the
   --  model at g = 0).

   procedure Centre_Derivative
     (P        : R.Params;
      E        : R.Evaluation;
      J11, J12 : out Long_Float;
      J21, J22 : out Long_Float)
   is
      D11 : constant Long_Float :=
        P.H11 - N.Mul_Within (E.A, P.H31, Max_Ideal, Max_Perspective_Entry);
      D12 : constant Long_Float :=
        P.H12 - N.Mul_Within (E.A, P.H32, Max_Ideal, Max_Perspective_Entry);
      D21 : constant Long_Float :=
        P.H21 - N.Mul_Within (E.B, P.H31, Max_Ideal, Max_Perspective_Entry);
      D22 : constant Long_Float :=
        P.H22 - N.Mul_Within (E.B, P.H32, Max_Ideal, Max_Perspective_Entry);
      A2  : constant Long_Float := N.Square_Within (E.A, Max_Ideal);
      B2  : constant Long_Float := N.Square_Within (E.B, Max_Ideal);
      AB  : constant Long_Float :=
        N.Mul_Within (E.A, E.B, Max_Ideal, Max_Ideal);
      M11 : constant Long_Float :=
        E.F + 2.0 * N.Mul_Within (E.G, A2, R.G_Limit, 16.0);
      M12 : constant Long_Float :=
        2.0 * N.Mul_Within (E.G, AB, R.G_Limit, 16.0);
      M22 : constant Long_Float :=
        E.F + 2.0 * N.Mul_Within (E.G, B2, R.G_Limit, 16.0);
   begin
      J11 := N.Mul_Within (M11, D11, 10240.0, J_Limit)
             + N.Mul_Within (M12, D21, 8192.0, J_Limit);
      J12 := N.Mul_Within (M11, D12, 10240.0, J_Limit)
             + N.Mul_Within (M12, D22, 8192.0, J_Limit);
      J21 := N.Mul_Within (M12, D11, 8192.0, J_Limit)
             + N.Mul_Within (M22, D21, 10240.0, J_Limit);
      J22 := N.Mul_Within (M12, D12, 8192.0, J_Limit)
             + N.Mul_Within (M22, D22, 10240.0, J_Limit);
   end Centre_Derivative;

   procedure Grid_Map
     (F             : R.Frame;
      E             : R.Evaluation;
      J11, J21      : Long_Float;
      Det           : Long_Float;
      Tile_X        : Long_Float;
      Tile_Y        : Long_Float;
      Map           : out KT.Ks_Transform_2D_Linear;
      Status        : out Ks_Status)
   with
     Pre  => abs J11 <= Jn_Limit and then abs J21 <= Jn_Limit
             and then abs Det <= 2.0 ** 52
             and then Valid_Tile (Tile_X) and then Valid_Tile (Tile_Y),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then abs Map.A <= Max_Warp_Entry
                            and then abs Map.B <= Max_Warp_Entry
                            and then abs Map.C <= Max_Warp_Entry
                            and then abs Map.D <= Max_Warp_Entry
                            and then abs Map.Translation_X
                                       <= Max_Warp_Translation
                            and then abs Map.Translation_Y
                                       <= Max_Warp_Translation);
   --  The map from output pixels u to normalised plate points:
   --  L (u - u0), with u0 the pixel where the plate's centre is seen (E
   --  the model there) and L = k diag (Sqrt (Rt), Sigma / Sqrt (Rt))
   --  R (-Theta), k = 1 / (S Sqrt (|Det|)), Rt = Tile_Y / Tile_X, Theta
   --  the direction of the plate's first axis (J11, J21) and Sigma the
   --  sign of Det (see the parent's spec).

   procedure Grid_Map
     (F             : R.Frame;
      E             : R.Evaluation;
      J11, J21      : Long_Float;
      Det           : Long_Float;
      Tile_X        : Long_Float;
      Tile_Y        : Long_Float;
      Map           : out KT.Ks_Transform_2D_Linear;
      Status        : out Ks_Status)
   is
      Ratio, Root_Ratio, Inverse_Root : Long_Float;
      Root, Scale, Kappa              : Long_Float;
      Fits                            : Boolean;
      Theta, Cos_T, Sin_T             : Long_Float;
      KX, KY                          : Long_Float;
      L11, L12, L21, L22              : Long_Float;
      U0X, U0Y                        : Long_Float;
   begin
      Map := (others => <>);
      if not (abs Det >= Min_Det) then
         Bad (Status, "Calibrate: the fitted model is degenerate at the "
                      & "plate's centre (PerspectiveAndRadialWarp)");
         return;
      elsif J11 = 0.0 and then J21 = 0.0 then
         Bad (Status, "Calibrate: the fitted model is degenerate at the "
                      & "plate's centre (PerspectiveAndRadialWarp)");
         return;
      elsif not (Tile_Y <= Max_Tile_Aspect * Tile_X
                 and then Tile_X <= Max_Tile_Aspect * Tile_Y)
      then
         Bad (Status, "PhysicalTileSizeX and PhysicalTileSizeY must be "
                      & "within a factor of 1024 of each other "
                      & "(PerspectiveAndRadialWarp)");
         return;
      end if;

      --  Rt and its root, within 1024 and 32 of 1.
      N.Ratio_Within (Tile_Y, Tile_X, Max_Tile_Aspect, Ratio, Fits);
      Root_Ratio := EF.Sqrt (Ratio);
      if not Fits
        or else not (Root_Ratio >= 2.0 ** (-6) and then Root_Ratio <= 64.0)
      then
         Bad (Status, "PhysicalTileSizeX and PhysicalTileSizeY must be "
                      & "within a factor of 1024 of each other "
                      & "(PerspectiveAndRadialWarp)");
         return;
      end if;
      N.Ratio_Within (1.0, Root_Ratio, 64.0, Inverse_Root, Fits);
      if not Fits then
         Bad (Status, "PhysicalTileSizeX and PhysicalTileSizeY must be "
                      & "within a factor of 1024 of each other "
                      & "(PerspectiveAndRadialWarp)");
         return;
      end if;

      --  k = 1 / (S Sqrt (|Det|)), at most 1 / Min_Scale.
      Root := N.Clamp (EF.Sqrt (abs Det), 2.0 ** 26);
      Scale := N.Mul_Within (F.S, Root, Max_Model_Coordinate, 2.0 ** 26);
      if not (Scale >= Min_Scale) then
         Bad (Status, "Calibrate: the plate is too small in the image "
                      & "(PerspectiveAndRadialWarp)");
         return;
      end if;
      N.Ratio_Within (1.0, Scale, 1.0 / Min_Scale, Kappa, Fits);
      if not Fits then
         Bad (Status, "Calibrate: the plate is too small in the image "
                      & "(PerspectiveAndRadialWarp)");
         return;
      end if;
      KX := N.Mul_Within (Kappa, Root_Ratio, 1.0 / Min_Scale, 64.0);
      KY := N.Mul_Within (Kappa, Inverse_Root, 1.0 / Min_Scale, 64.0);
      if Det < 0.0 then
         KY := -KY;
      end if;

      Theta := N.Direction (J21, J11);
      Cos_T := EF.Cos (Theta);
      Sin_T := EF.Sin (Theta);
      L11 := N.Times_Unit (KX, Cos_T);
      L12 := N.Times_Unit (KX, Sin_T);
      L21 := -N.Times_Unit (KY, Sin_T);
      L22 := N.Times_Unit (KY, Cos_T);

      --  u0: where the plate's centre is seen, in pixels.
      U0X := F.CX + N.Mul_Within (F.S, E.MX, Max_Model_Coordinate,
                                  R.M_Limit);
      U0Y := F.CY + N.Mul_Within (F.S, E.MY, Max_Model_Coordinate,
                                  R.M_Limit);
      Map :=
        (A             => L11,
         B             => L12,
         C             => L21,
         D             => L22,
         Translation_X =>
           -(N.Mul_Within (L11, U0X, Max_Warp_Entry, 2.0 ** 38)
             + N.Mul_Within (L12, U0Y, Max_Warp_Entry, 2.0 ** 38)),
         Translation_Y =>
           -(N.Mul_Within (L21, U0X, Max_Warp_Entry, 2.0 ** 38)
             + N.Mul_Within (L22, U0Y, Max_Warp_Entry, 2.0 ** 38)));
      Set_Success (Status);
   end Grid_Map;

   procedure Build_Model
     (P             : R.Params;
      F             : R.Frame;
      RMS           : Long_Float;
      Iterations    : Natural;
      Width, Height : Int32;
      Tile_X        : Long_Float;
      Tile_Y        : Long_Float;
      Model         : out Ks_Radial_Warp_Model;
      Status        : out Ks_Status)
   is
      E                  : R.Evaluation;
      OK                 : Boolean;
      J11, J12, J21, J22 : Long_Float;
      Det                : Long_Float;
      Map                : KT.Ks_Transform_2D_Linear;
      Calibrated_From_Grid   : KT.Ks_Transform_2D_Linear;
      Calibrated_From_Output : KT.Ks_Transform_2D_Linear;
      Output_From_Calibrated : KT.Ks_Transform_2D_Linear;
   begin
      Model := (others => <>);
      R.Evaluate (P, 0.0, 0.0, Min_Denominator, E, OK);
      if not OK then
         Bad (Status, "Calibrate: the plate's centre has no image under the "
                      & "fitted model (PerspectiveAndRadialWarp)");
         return;
      end if;
      Centre_Derivative (P, E, J11, J12, J21, J22);
      Det := N.Mul_Within (J11, J22, Jn_Limit, Jn_Limit)
             - N.Mul_Within (J12, J21, Jn_Limit, Jn_Limit);
      Grid_Map (F, E, J11, J21, Det, Tile_X, Tile_Y, Map, Status);
      if not Succeeded (Status) then
         return;
      end if;

      --  The calibrated point of a normalised plate point g:
      --  ((GX + SG g_x) Tile_X, (GY + SG g_y) Tile_Y). Its entries may
      --  exceed Max_Value (a plate of raw calibrated points near the bound
      --  with tiles of 1, a large tile with a grid of up to Max_Grid_Index
      --  stay within it): Compose rejects such a transform.
      Calibrated_From_Grid :=
        (A             => N.Mul_Within (Tile_X, F.SG, Max_Tile_Size,
                                        Max_Value),
         B             => 0.0,
         C             => 0.0,
         D             => N.Mul_Within (Tile_Y, F.SG, Max_Tile_Size,
                                        Max_Value),
         Translation_X => N.Mul_Within (Tile_X, F.GX, Max_Tile_Size,
                                        Max_Value),
         Translation_Y => N.Mul_Within (Tile_Y, F.GY, Max_Tile_Size,
                                        Max_Value));
      KT.Compose (Calibrated_From_Grid, Map, Calibrated_From_Output, Status);
      if Succeeded (Status) then
         KT.Invert (Calibrated_From_Output, Output_From_Calibrated, Status);
      end if;
      if not Succeeded (Status) then
         Bad (Status, "Calibrate: the transform from calibrated to output "
                      & "pixels exceeds 1.0E150 (PerspectiveAndRadialWarp)");
         return;
      end if;

      Model :=
        (H11 => P.H11, H12 => P.H12, H13 => P.H13,
         H21 => P.H21, H22 => P.H22, H23 => P.H23,
         H31 => P.H31, H32 => P.H32,
         K1 => P.K1, K2 => P.K2,
         Center_X => F.CX, Center_Y => F.CY,
         Normalizer => F.S,
         Grid_Center_X => F.GX, Grid_Center_Y => F.GY,
         Grid_Scale => F.SG,
         Valid_Radius_Squared => P.Rho_Max,
         RMS_Error => RMS,
         Output_Pixel_From_Calibrated => Output_From_Calibrated,
         Grid_From_Output => Map,
         Image_Width => Width,
         Image_Height => Height,
         Iterations => Int32 (Iterations));
      Set_Success (Status);
   end Build_Model;

   ---------------------------------------------------------------------
   --  The map and the resampling
   ---------------------------------------------------------------------

   procedure Input_From_Output
     (Model  : Ks_Radial_Warp_Model;
      X, Y   : Long_Float;
      PX, PY : out Long_Float;
      Inside : out Boolean)
   is
      T  : constant KT.Ks_Transform_2D_Linear := Model.Grid_From_Output;
      GU : constant Long_Float :=
        N.Mul_Within (T.A, X, Max_Warp_Entry, Max_Output_Coordinate)
        + N.Mul_Within (T.B, Y, Max_Warp_Entry, Max_Output_Coordinate)
        + T.Translation_X;
      GV : constant Long_Float :=
        N.Mul_Within (T.C, X, Max_Warp_Entry, Max_Output_Coordinate)
        + N.Mul_Within (T.D, Y, Max_Warp_Entry, Max_Output_Coordinate)
        + T.Translation_Y;
      E  : R.Evaluation;
   begin
      PX := 0.0;
      PY := 0.0;
      R.Evaluate (Params_Of (Model), GU, GV, 0.0, E, Inside);
      if Inside then
         PX := Model.Center_X
           + N.Mul_Within (Model.Normalizer, E.MX, Max_Model_Coordinate,
                           R.M_Limit);
         PY := Model.Center_Y
           + N.Mul_Within (Model.Normalizer, E.MY, Max_Model_Coordinate,
                           R.M_Limit);
      end if;
   end Input_From_Output;

   --  The inverse map in three steps, each with its own bounds.

   subtype Distance is Long_Float range 0.0 .. 4.0;
   --  A normalised distance of an ideal point (the valid radius is at most
   --  Sqrt (Max_Radius_Squared) = 4).

   subtype Coefficient is Long_Float
     range -Max_Radial_Coefficient .. Max_Radial_Coefficient;

   function Radial (K1, K2 : Coefficient; R : Distance) return Long_Float is
     (R * (1.0 + K1 * (R * R) + K2 * ((R * R) * (R * R))));
   --  The observed distance of an ideal point at distance R (within
   --  4 * (1 + 4 * 16 + 4 * 256)).

   function Ideal_Distance
     (K1, K2 : Coefficient;
      R_Max  : Distance;
      S      : Long_Float) return Distance
   with Post => Ideal_Distance'Result <= R_Max;
   --  The R in [0, R_Max] with Radial (R) = S, by Bisection_Steps
   --  halvings (the radial map rises on [0, R_Max]).

   function Ideal_Distance
     (K1, K2 : Coefficient;
      R_Max  : Distance;
      S      : Long_Float) return Distance
   is
      Lo  : Distance := 0.0;
      Hi  : Distance := R_Max;
      Mid : Distance;
   begin
      for Step in 1 .. Bisection_Steps loop
         pragma Loop_Invariant (Lo <= Hi and then Hi <= R_Max);
         Mid := Long_Float'Min (Hi, Long_Float'Max (Lo, (Lo + Hi) / 2.0));
         if Radial (K1, K2, Mid) < S then
            Lo := Mid;
         else
            Hi := Mid;
         end if;
      end loop;
      --  After 64 halvings Hi - Lo is at most 4 / 2**64.
      return Hi;
   end Ideal_Distance;

   subtype Ideal_Component is Long_Float range -4.0 .. 4.0;

   procedure Along
     (MX, MY : Long_Float;
      S      : Long_Float;
      R      : Distance;
      A, B   : out Ideal_Component)
   with Pre => S >= 0.0 and then abs MX <= S and then abs MY <= S;
   --  The point at distance R from the centre in the direction of
   --  (MX, MY), whose length is S (the centre for S = 0).

   procedure Along
     (MX, MY : Long_Float;
      S      : Long_Float;
      R      : Distance;
      A, B   : out Ideal_Component) is
   begin
      if S > 0.0 then
         A := N.Times_Unit (R, N.Unit_Ratio (MX, S));
         B := N.Times_Unit (R, N.Unit_Ratio (MY, S));
      else
         A := 0.0;
         B := 0.0;
      end if;
   end Along;

   subtype H_Entry is Long_Float
     range -Max_Homography_Entry .. Max_Homography_Entry;
   subtype P_Entry is Long_Float
     range -Max_Perspective_Entry .. Max_Perspective_Entry;
   subtype Grid_Coordinate is Long_Float range -2.0 ** 62 .. 2.0 ** 62;

   procedure Solve_Grid
     (H11, H12, H13, H21, H22, H23 : H_Entry;
      H31, H32                     : P_Entry;
      A, B                         : Ideal_Component;
      GX, GY                       : out Grid_Coordinate;
      Found                        : out Boolean);
   --  The grid point g with w (a, b) = N (g): (H11 - a H31) g_x + (H12 -
   --  a H32) g_y = a - H13 and the same with b, H21, H22, H23, by Cramer's
   --  rule. Found is False (and g = 0) when the determinant is below
   --  1.0E-12 in magnitude or a coordinate beyond 2**62.

   procedure Solve_Grid
     (H11, H12, H13, H21, H22, H23 : H_Entry;
      H31, H32                     : P_Entry;
      A, B                         : Ideal_Component;
      GX, GY                       : out Grid_Coordinate;
      Found                        : out Boolean)
   is
      subtype Entry_Value is Long_Float range -1100.0 .. 1100.0;
      --  Within 1024 + 4 * 16 (the matrix) or 1024 + 4 (the right side).
      subtype Product_Value is Long_Float range -2.5E6 .. 2.5E6;
      M11 : constant Entry_Value := H11 - A * H31;
      M12 : constant Entry_Value := H12 - A * H32;
      M21 : constant Entry_Value := H21 - B * H31;
      M22 : constant Entry_Value := H22 - B * H32;
      B1  : constant Entry_Value := A - H13;
      B2  : constant Entry_Value := B - H23;
      D   : constant Product_Value := M11 * M22 - M12 * M21;
      NX  : constant Product_Value := B1 * M22 - M12 * B2;
      NY  : constant Product_Value := M11 * B2 - B1 * M21;
      AD  : constant Long_Float range 1.0E-12 .. 2.5E6 :=
        Long_Float'Max (1.0E-12, Long_Float'Min (abs D, 2.5E6));
      QX, QY       : Long_Float;
      Fit_X, Fit_Y : Boolean;
   begin
      GX := 0.0;
      GY := 0.0;
      Found := False;
      if abs D < 1.0E-12 then
         return;
      end if;
      N.Ratio_Within (abs NX, AD, 2.0 ** 62, QX, Fit_X);
      N.Ratio_Within (abs NY, AD, 2.0 ** 62, QY, Fit_Y);
      if Fit_X and then Fit_Y then
         GX := (if (NX < 0.0) /= (D < 0.0) then -QX else QX);
         GY := (if (NY < 0.0) /= (D < 0.0) then -QY else QY);
         Found := True;
      end if;
   end Solve_Grid;

   procedure Output_From_Input
     (Model  : Ks_Radial_Warp_Model;
      X, Y   : Long_Float;
      UX, UY : out Long_Float;
      Inside : out Boolean)
   is
      --  The normalised observed point m (within (2**32 + 2**24) / 0.5).
      M_Bound : constant := 2.0 ** 34;
      MX : constant Long_Float :=
        N.Clamp ((X - Model.Center_X) / Model.Normalizer, M_Bound);
      MY : constant Long_Float :=
        N.Clamp ((Y - Model.Center_Y) / Model.Normalizer, M_Bound);
      S  : constant Long_Float := N.Hypot (MX, MY);
      R_Max : constant Distance :=
        Long_Float'Min
          (4.0, Long_Float'Max (0.0, EF.Sqrt (Model.Valid_Radius_Squared)));
      K1    : constant Coefficient := Model.K1;
      K2    : constant Coefficient := Model.K2;
      H11   : constant H_Entry := Model.H11;
      H12   : constant H_Entry := Model.H12;
      H13   : constant H_Entry := Model.H13;
      H21   : constant H_Entry := Model.H21;
      H22   : constant H_Entry := Model.H22;
      H23   : constant H_Entry := Model.H23;
      H31   : constant P_Entry := Model.H31;
      H32   : constant P_Entry := Model.H32;
      A, B   : Ideal_Component;
      GX, GY : Grid_Coordinate;
      Found  : Boolean;
      Back   : KT.Ks_Transform_2D_Linear;
      St     : Ks_Status;
   begin
      UX := 0.0;
      UY := 0.0;
      Inside := False;
      if S > Radial (K1, K2, R_Max) then
         return;
      end if;
      --  The ideal point along m: h = m * R / S (0 at the centre).
      declare
         CX : constant Long_Float := N.Clamp (MX, S);
         CY : constant Long_Float := N.Clamp (MY, S);
         R  : constant Distance := Ideal_Distance (K1, K2, R_Max, S);
      begin
         Along (CX, CY, S, R, A, B);
      end;
      Solve_Grid (H11, H12, H13, H21, H22, H23, H31, H32, A, B, GX, GY,
                  Found);
      if not Found or else 1.0 + H31 * GX + H32 * GY < Min_Denominator then
         return;
      end if;
      KT.Invert (Model.Grid_From_Output, Back, St);
      if not Succeeded (St) then
         return;
      end if;
      declare
         OX, OY : Long_Float;
      begin
         KT.Map_Point (Back, GX, GY, OX, OY, St);
         if Succeeded (St)
           and then abs OX <= Max_Output_Coordinate
           and then abs OY <= Max_Output_Coordinate
         then
            UX := OX;
            UY := OY;
            Inside := True;
         end if;
      end;
   end Output_From_Input;

   procedure Resample
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Model  : Ks_Radial_Warp_Model;
      Fill   : KI.Grey_8;
      Output : KI.Ks_Image_8_Grey)
   is
      Width  : constant Int32 := Output.Width with Ghost;
      Height : constant Int32 := Output.Height with Ghost;
      PX, PY : Long_Float;
      Inside : Boolean;
   begin
      for Y in Output.Pixels'Range (1) loop
         for X in Output.Pixels'Range (2) loop
            Input_From_Output
              (Model, Long_Float (X), Long_Float (Y), PX, PY, Inside);
            Output.Pixels (Y, X) :=
              (if Inside then SM.Bilinear_Sample (Image, PX, PY, Fill)
               else Fill);
            pragma Loop_Invariant
              (KI.Valid_Image (Output)
               and then Output.Width = Width
               and then Output.Height = Height);
         end loop;
         pragma Loop_Invariant
           (KI.Valid_Image (Output)
            and then Output.Width = Width
            and then Output.Height = Height);
      end loop;
   end Resample;

end AMV.Kernels.Calib_Fix.Warp;
