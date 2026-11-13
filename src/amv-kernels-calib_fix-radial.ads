--  The fit of the perspective and radial distortion model of
--  AMV.Kernels.Calib_Fix (ComputationMode PerspectiveAndRadialWarp). The
--  model and its sources are described in the parent's spec; this package
--  works in its normalised coordinates:
--
--  * a plate point (X, Y) (an Observation's: a corner's grid indices, an
--    N-point calibration's raw calibrated point) becomes
--    g = ((X - GX) / SG, (Y - GY) / SG), with (GX, GY) the centre of the
--    plate points' bounding box and SG the larger of its half extents, so
--    g lies in [-1, 1]**2;
--  * a pixel position p becomes (p - C) / S, with C the image centre
--    ((Width - 1) / 2, (Height - 1) / 2) and S half the image diagonal,
--    so every pixel of the image lies in [-1, 1]**2 (Hartley's
--    normalisation, adapted to fixed scales).
--
--  The model maps g to the ideal point h = (N_x / w, N_y / w) with
--  N_x = H11 g_x + H12 g_y + H13, N_y = H21 g_x + H22 g_y + H23 and
--  w = 1 + H31 g_x + H32 g_y (a homography with H33 = 1, which is
--  possible since the centre g = 0 of the board is seen at a finite
--  point), and h to the observed point m = h (1 + K1 rho + K2 rho**2),
--  rho = |h|**2.
--
--  For grid indices (integers within Max_Grid_Index) the normalisation is
--  exact, and the fit computes what it computed when it took the corners
--  themselves (bit for bit).
--
--  The fit: points whose normalised plate points or pixel positions lie
--  on one line (the determinant of their scatter matrix at most
--  Collinear_Tolerance times its squared trace, as for the DOF fits) are
--  rejected; then the direct linear transform (DLT) for the homography (the
--  linear least squares solution of w m = N for the eight entries, from
--  the 8 x 8 normal equations), then at most Max_Iterations damped
--  Gauss-Newton (Levenberg-Marquardt) iterations on the ten parameters,
--  minimising the sum of the squared distances between the observed and
--  the modelled points. A step is accepted when every parameter stays
--  within its bound, every point stays valid (below) and the sum
--  decreases; otherwise the damping grows by 8 (up to Max_Damping_Tries
--  times per iteration). The iteration stops early when an accepted step
--  changes no parameter by more than Step_Tolerance or the sum by less
--  than a relative 2**(-45).
--
--  A point is valid under a model when w >= Min_Denominator, both
--  components of h lie within Max_Ideal, and rho is at most the model's
--  valid radius (the largest rho up to which the radial map is monotonic,
--  Valid_Radius).

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

private package AMV.Kernels.Calib_Fix.Radial
  with SPARK_Mode, Preelaborate
is

   subtype H_Value is
     Long_Float range -Max_Homography_Entry .. Max_Homography_Entry;
   subtype P_Value is
     Long_Float range -Max_Perspective_Entry .. Max_Perspective_Entry;
   subtype K_Value is
     Long_Float range -Max_Radial_Coefficient .. Max_Radial_Coefficient;
   subtype Rho_Value is Long_Float range 0.0 .. Max_Radius_Squared;
   subtype Ideal_Value is Long_Float range -Max_Ideal .. Max_Ideal;
   subtype Unit_Value is Long_Float range -1.0 .. 1.0;

   type Params is record
      H11, H12, H13, H21, H22, H23 : H_Value := 0.0;
      H31, H32                     : P_Value := 0.0;
      K1, K2                       : K_Value := 0.0;
      Rho_Max                      : Rho_Value := 0.0;
   end record;
   --  The ten parameters of the model and the valid radius (squared) of
   --  K1 and K2.

   type Frame is record
      CX, CY : Long_Float range 0.0 .. Max_Model_Coordinate := 0.0;
      S      : Long_Float range 0.5 .. Max_Model_Coordinate := 1.0;
      GX, GY : Long_Float range -Max_Value .. Max_Value := 0.0;
      SG     : Long_Float range Min_Plate_Scale .. Max_Value := 1.0;
   end record;
   --  The normalisation: the image centre (CX, CY) and half the diagonal
   --  S in pixels, the plate's centre (GX, GY) and half extent SG in plate
   --  units.

   ---------------------------------------------------------------------
   --  The observed points
   ---------------------------------------------------------------------

   Max_Pixel : constant := 2.0 ** 31;
   subtype Pixel_Value is Long_Float range -Max_Pixel .. Max_Pixel;

   type Observation is record
      Pixel_X, Pixel_Y : Pixel_Value := 0.0;
      Plate_X, Plate_Y : Coordinate := 0.0;
   end record;
   --  A point the fit takes: its position in the pixel space of the
   --  calibration image and its plate point (plate units): a corner of a
   --  checkerboard with its grid indices, or a pair of an N-point
   --  calibration (its uncalibrated point mapped to pixel space, its raw
   --  calibrated point).

   type Observation_Array is array (Natural range <>) of Observation;

   type Observation_Array_Access is access Observation_Array;

   Min_Stretch : constant := 0.05;
   --  The radial map r -> r (1 + K1 r**2 + K2 r**4) counts as monotonic
   --  while its derivative 1 + 3 K1 rho + 5 K2 rho**2 is at least this.

   Radius_Steps : constant := 4096;
   --  Valid_Radius tests rho = j * Max_Radius_Squared / Radius_Steps.

   function Valid_Radius (K1, K2 : K_Value) return Rho_Value;
   --  The largest rho = j * Max_Radius_Squared / Radius_Steps (j in
   --  0 .. Radius_Steps) such that the derivative of the radial map is at
   --  least Min_Stretch at every tested rho up to it.

   ---------------------------------------------------------------------
   --  One point of the model
   ---------------------------------------------------------------------

   Grid_Limit : constant := 2.0 ** 62;
   subtype Grid_Value is Long_Float range -Grid_Limit .. Grid_Limit;

   F_Limit : constant := 2048.0;
   --  1 + K1 rho + K2 rho**2 is within 1 + 4 * 16 + 4 * 256 = 1089.
   G_Limit : constant := 256.0;
   --  K1 + 2 K2 rho is within 4 + 2 * 4 * 16 = 132.
   M_Limit : constant := 8192.0;
   --  F_Limit * Max_Ideal.

   type Evaluation is record
      A, B : Ideal_Value := 0.0;
      W    : Long_Float range 0.0 .. 2.0 ** 70 := 1.0;
      Rho  : Rho_Value := 0.0;
      Rho2 : Long_Float range 0.0 .. 256.0 := 0.0;
      F    : Long_Float range -F_Limit .. F_Limit := 1.0;
      G    : Long_Float range -G_Limit .. G_Limit := 0.0;
      MX   : Long_Float range -M_Limit .. M_Limit := 0.0;
      MY   : Long_Float range -M_Limit .. M_Limit := 0.0;
   end record;
   --  The model at one grid point: the ideal point (A, B) and its
   --  denominator W, Rho = A**2 + B**2 and Rho2 = Rho**2, the radial
   --  factor F = 1 + K1 Rho + K2 Rho2, G = K1 + 2 K2 Rho (half the
   --  derivative of F by Rho) and the observed point (MX, MY) = F (A, B),
   --  all normalised.

   procedure Evaluate
     (P     : Params;
      U, V  : Grid_Value;
      Min_W : Long_Float;
      E     : out Evaluation;
      OK    : out Boolean)
   with
     Pre  => Min_W >= 0.0 and then Min_W <= 1.0,
     Post => (if OK then E.W > 0.0 and then E.W >= Min_W
                         and then E.Rho <= P.Rho_Max);
   --  The model at the normalised grid point (U, V). OK is False (and E
   --  its default) when W is not positive or below Min_W, when a
   --  component of the ideal point exceeds Max_Ideal, or when Rho exceeds
   --  P.Rho_Max.

   ---------------------------------------------------------------------
   --  The fit
   ---------------------------------------------------------------------

   Max_Iterations    : constant := Max_Fit_Iterations;
   Max_Damping_Tries : constant := 12;
   Step_Tolerance    : constant := 2.0 ** (-40);

   procedure Fit
     (Points        : Observation_Array;
      Count         : Natural;
      Width, Height : Int32;
      P             : out Params;
      F             : out Frame;
      RMS           : out Long_Float;
      Iterations    : out Natural;
      Status        : out Ks_Status)
   with
     Pre  => Points'First = 0
             and then Count in Min_Warp_Points .. Max_Warp_Points
             and then Count - 1 <= Points'Last
             and then Width in 1 .. Max_Model_Side
             and then Height in 1 .. Max_Model_Side,
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then RMS >= 0.0 and then RMS <= Max_RMS
             and then Iterations <= Max_Iterations
             and then F.CX = Long_Float (Width - 1) * 0.5
             and then F.CY = Long_Float (Height - 1) * 0.5;
   --  Fits the model to Points (0 .. Count - 1) (pixel positions in an
   --  image of Width x Height pixels, plate points) as described above:
   --  P is the fitted model (with Rho_Max = Valid_Radius (K1, K2)), F the
   --  normalisation, RMS the root mean square distance in pixels between
   --  the points and the model, Iterations the number of accepted
   --  steps. Bad_Parameter when the plate points span less than
   --  2 Min_Plate_Scale, when a pixel position lies beyond the
   --  normalisation (more than half the diagonal from the image centre
   --  along an axis), when the plate points or the pixel positions lie on
   --  one line, when the points do not determine a homography (a singular
   --  system), when the homography leaves the bounds of the parameters or
   --  makes a point invalid; Out_Of_Memory.

   function Normaliser (Width, Height : Int32) return Long_Float
   with
     Pre  => Width in 1 .. Max_Model_Side
             and then Height in 1 .. Max_Model_Side,
     Post => Normaliser'Result >= 0.5
             and then Normaliser'Result <= Max_Model_Coordinate
             and then Normaliser'Result >= Long_Float (Width - 1) * 0.5
             and then Normaliser'Result >= Long_Float (Height - 1) * 0.5;
   --  Half the diagonal of a Width x Height image, Hypot (Width, Height)
   --  / 2 (the bounds stated are limits that never act).

end AMV.Kernels.Calib_Fix.Radial;
