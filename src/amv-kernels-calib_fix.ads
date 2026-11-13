--  Kernel of AMV.Calib_Fix: the fixture tools and the calibrations of
--  Cognex.VisionPro.CalibFix (CogNPointToNPoint, CogFixtureTool with its
--  run parameters CogFixture, CogFixtureNPointToNPointTool with
--  CogFixtureNPointToNPoint, CogCalibNPointToNPoint and its tool,
--  CogCalibCheckerboard and its tool). The C API is declared in
--  include/amv_calib_fix.h.
--
--  Point pairs. A list of point pairs (C: ks_point_pairs *, an owned
--  handle; null is the empty list) holds up to Max_Pairs pairs (A, B): A
--  is the point in group A (unfixtured, uncalibrated: the space the image
--  measures in), B the same point in group B (raw fixtured, raw
--  calibrated: the space being defined). Every coordinate must be finite
--  and within Max_Value (1.0E150).
--
--  The fits. ks_n_point_to_n_point_compute (CogNPointToNPoint.
--  ComputeGroupAFromGroupBTransform) finds the transform T that maps
--  group B onto group A with the least sum of squared distances
--  |T (B) - A|**2, restricted to the degrees of freedom of the DOF code
--  (CogNPointToNPointDOFConstants, VisionPro's values):
--
--  * None (0): the identity;
--  * TranslationX (1), TranslationY (2), Translation (3): a shift along x,
--    along y, or both (the mean difference A - B);
--  * RotationAndTranslation (4): a rotation and a shift (the closed form
--    of the 2-D Procrustes problem: the angle of the summed dot and cross
--    products of the centred points);
--  * ScalingRotationAndTranslation (5): a similarity (Umeyama's closed
--    form in 2-D: the matrix [a -b; b a] with a and b the dot and cross
--    sums over the spread of the B points);
--  * ScalingAspectRotationAndTranslation (6): a rotation of independent
--    scalings along the two axes of B, R (Theta) * diag (Sx, Sy). For a
--    given angle the best scalings are linear in the data, and the best
--    angle maximises a quadratic form in (cos Theta, sin Theta), whose
--    principal axis has a closed form (half the direction of its doubled
--    off-diagonal term and the difference of its diagonal); Sx >= 0 is
--    kept by turning the angle half a turn when needed, so Sy is negative
--    exactly when the fit mirrors;
--  * ScalingAspectRotationSkewAndTranslation (7): the general affine
--    transform (linear least squares, the normal equations of the centred
--    points solved in closed form).
--
--  The points are centred on their centroids and each group is divided by
--  its largest centred coordinate before the sums are formed, so every
--  sum is bounded and the fits are independent of the units. At least
--  Min_Points (DOF) pairs are needed (0, 1, 1, 1, 2, 2, 3, 3); fewer give
--  Bad_Parameter before anything is fitted (Gold). Degenerate data give
--  Bad_Parameter too: B points that all coincide for the DOFs with a
--  rotation, B points on one line (Collinear_Tolerance) for the DOFs with
--  an aspect, a fitted matrix that is singular or close to it
--  (Singular_Tolerance), and a fitted transform beyond the bounds of
--  AMV.Kernels.Transforms or not invertible within them. The result
--  (Ks_N_Point_To_N_Point_Fit) holds the transform, the RMS of the
--  distances |T (B) - A| (in group A units; a distance beyond Max_RMS
--  counts as Max_RMS) and the fit's parameters (scalings, rotation,
--  skew).
--
--  Proved (Gold, Valid_Fit and Has_DOF_Structure): the transform is
--  within the bounds of AMV.Kernels.Transforms and its determinant, as
--  Det_Of evaluates it, is not zero (it is also invertible within the
--  bounds: ks_transform_2d_linear_invert succeeded on it); it has exactly
--  the structure of its DOF: the unit matrix for None and the
--  translations (with the other translation 0, both for None), a matrix
--  of Cos and Sin of the fitted rotation for RotationAndTranslation (unit
--  scale), A = D and B = -C for ScalingRotationAndTranslation (equal
--  scales, no skew), the columns Sx (Cos R, Sin R) and Sy (-Sin R, Cos R)
--  for ScalingAspectRotationAndTranslation (no skew); and RMSError is in
--  [0, Max_RMS]. The optimality of the fits is tested, not proved.
--
--  Fixtures and calibrated spaces. ks_fixture_execute,
--  ks_fixture_n_point_to_n_point_execute and ks_calibration_tool_execute
--  take the coordinate space state of the input image (its tree, its
--  selected space name as stored and its pixel-from-root transform, as the
--  ks_image_* functions do) and add the new space (fixtured or calibrated)
--  to the tree through ks_coordinate_space_tree_add_space, as a child of
--  the input's selected space, with Parent_From_New = the transform from
--  the new space into that space (UnfixturedFromFixtured,
--  UncalibratedFromCalibrated), stored exactly as given. An existing space
--  of that name has its transform replaced (Compatibility, the default) or
--  makes the run fail with Bad_Parameter (Enhanced: VisionPro accepts a
--  space added by the same fixture tool before; AMV does not record which
--  tool added a space). Then, with SpaceToOutput 0 (FixturedSpace,
--  CalibratedSpace) the new space becomes the selected space, with 1
--  (UnfixturedSpace, UncalibratedSpace) the selection stays as it reads.
--  The output image shares the input's pixels; the Ada API copies the
--  tree and the selection back into it.
--
--  The rule for pixel space. When the input's selected space is "#",
--  which is not a space of the tree, the new space is added under the
--  root "@" with Parent_From_New = Get_Transform ("@", "#") composed with
--  the given transform (new -> pixel -> root), so that the new space
--  means the same as it would under "#". Every tool of this kernel uses
--  this rule. With SpaceToOutput 1 the selection stays "#".
--
--  Calibrations. A calibration (C: ks_calibration *, an owned handle; AMV
--  name, one type for both kinds) is a trained object: a Kind
--  (Kind_N_Point_To_N_Point: CogCalibNPointToNPoint, or Kind_Checkerboard:
--  CogCalibCheckerboard), its inputs (the point pairs of an N-point
--  calibration, uncalibrated and raw calibrated; the physical tile sizes
--  of a checkerboard calibration, whose image the caller passes to
--  calibrate, as for an N-point calibration in PerspectiveAndRadialWarp
--  mode) and DOFsToCompute, and its computed state: Calibrated, the
--  pairs a checkerboard calibration found (with the corners' pixel
--  positions and grid indices), the computed transform
--  (UncalibratedFromRawCalibrated, which maps raw calibrated coordinates
--  to the uncalibrated space) and its RMS error. Changing an input
--  uncalibrates. The tools fail with Operator_Not_Trained for a
--  calibration that is not calibrated. A calibration also holds its
--  origin adjustment, which defines the calibrated space from the raw
--  calibrated space (below).
--
--  The origin adjustment (C: ks_calibration_adjustment; CalibratedOriginX,
--  CalibratedOriginY, CalibratedOriginSpace, CalibratedXAxisRotation,
--  CalibratedXAxisRotationSpace and SwapCalibratedHandedness of both
--  kinds; AMV's own design). Let F be the computed fit, uncalibrated from
--  raw calibrated, and Lin (F) its linear part. The calibrated space is
--  the raw calibrated space moved rigidly: raw calibrated from calibrated
--  is R = Translate (O) * Rotate (Phi) * M, where M is the mirror
--  diag (1, -1) when SwapCalibratedHandedness is set (the calibrated y
--  axis is turned the other way) and the identity otherwise, and
--
--  * O, the calibrated origin in raw calibrated coordinates, is
--    (CalibratedOriginX, CalibratedOriginY) when CalibratedOriginSpace is
--    RawCalibrated (Adjustment_Space_Raw_Calibrated, 0), and
--    F**(-1) (CalibratedOriginX, CalibratedOriginY) when it is
--    Uncalibrated (Adjustment_Space_Uncalibrated, 1): the given point of
--    the uncalibrated space (a pixel, say) becomes the calibrated origin;
--  * Phi, the direction of the calibrated x axis in raw calibrated
--    space, is CalibratedXAxisRotation (radians) when
--    CalibratedXAxisRotationSpace is RawCalibrated, and the direction of
--    Lin (F)**(-1) (cos CalibratedXAxisRotation, sin CalibratedXAxis-
--    Rotation) when it is Uncalibrated: the calibrated x axis is then seen
--    in the uncalibrated space along the angle CalibratedXAxisRotation,
--    whatever the aspect and skew of F (the y axis is perpendicular to it
--    in calibrated units, not necessarily in uncalibrated ones).
--
--  UncalibratedFromCalibrated is F * R (ks_calibration_computed_
--  uncalibrated_from_calibrated_transform), UncalibratedFromRawCalibrated
--  stays F (ks_calibration_computed_fit). R is rigid, so calibrated units
--  are raw calibrated units. The defaults are AMV's (VisionPro's are not
--  used): RawCalibrated, 0, 0, RawCalibrated, 0, not swapped; they give
--  R = identity and exactly F, the calibrated space of a calibration
--  without adjustment. The adjustment is not an input of the fit: setting
--  it keeps a calibration calibrated (and its raw calibrated points raw),
--  and F * R is formed from the adjustment as it is whenever it is needed
--  (that function and the tools, which add the calibrated space with
--  F * R). Setting it checks every value (Bad_Parameter): the space codes
--  0 or 1, the swap flag False_Value or True_Value, the origin finite and
--  within Max_Value, the rotation finite; the rotation is stored reduced
--  to (-Pi, Pi]. Forming F * R gives Bad_Parameter when F**(-1), the
--  mapped origin or F * R leaves the bounds of AMV.Kernels.Transforms or
--  F * R is not invertible within them, or when the direction of the
--  uncalibrated rotation cannot be mapped. In PerspectiveAndRadialWarp
--  mode F is the linear transform of the warped output (see below), and
--  the adjustment in raw calibrated space applies to it as above; the
--  Uncalibrated spaces are not supported there (the map from the input's
--  pixels to calibrated coordinates is not linear, so a point or an angle
--  of the uncalibrated space has no fixed counterpart in it): forming F * R
--  then gives Bad_Parameter.
--
--  The checkerboard detector (AMV.Kernels.Calib_Fix.Checkerboard) finds
--  the X-corners of a checkerboard in an 8-bit image, organises them in a
--  grid and fits the transform from the grid (raw calibrated coordinates
--  I * PhysicalTileSizeX, J * PhysicalTileSizeY) to the corners' positions
--  in the calibration image's selected space. In the computation mode
--  Linear (CogCalibFixComputationModeConstants, the default) it models the
--  image of the plate as a linear transform of the plate: no lens
--  distortion and no perspective. See that package for the method and its
--  limits.
--
--  The nonlinear mode PerspectiveAndRadialWarp (calibrations of both
--  kinds; the other nonlinear members of the enumeration give
--  Bad_Parameter). Our own design, after the public literature: Zhang, "A
--  flexible new technique for camera calibration" (IEEE PAMI, 2000) for
--  the plate-to-image homography and its refinement by Levenberg-
--  Marquardt; Brown, "Decentering distortion of lenses" (1966) and
--  Conrady (1919) for the radial polynomial; Hartley, "In defense of the
--  eight-point algorithm" (IEEE PAMI, 1997) for the normalisation.
--
--  * The plate. The model maps plate points, in plate units, to pixels of
--    the calibration image. A checkerboard's plate points are its
--    corners' grid indices (I, J), whose raw calibrated points are
--    (I * PhysicalTileSizeX, J * PhysicalTileSizeY), and their pixels the
--    corners' positions. An N-point calibration's plate points are its
--    raw calibrated points B (plate units are raw calibrated units, as
--    with tiles of size 1), and their pixels its uncalibrated points A,
--    which are given in the calibration image's selected space, mapped to
--    its pixel space by the inverse of Selected_From_Pixel. Everything
--    below holds for both kinds in the same way.
--  * The model. A plate point q (calibrated units) is seen at the ideal
--    pixel h = H (q), H a homography (perspective), and then at the
--    observed pixel p = c + (h - c) (1 + K1 r**2 + K2 r**4),
--    r = |h - c| / s, with c the centre of the calibration image
--    ((Width - 1) / 2, (Height - 1) / 2), the distortion centre, and s
--    half its diagonal, a fixed normaliser that makes K1 and K2
--    dimensionless (r = 1 at the image's corners). The centre is fixed:
--    from one view of a plane it can hardly be told apart from the
--    translation and the perspective of H. The model works in the
--    calibration image's pixel space; the images it is used on must have
--    that size.
--  * The estimate (AMV.Kernels.Calib_Fix.Radial), in normalised
--    coordinates (plate points and pixels scaled into [-1, 1]): the
--    direct linear transform for H from the points (K1 = K2 = 0), then
--    at most Max_Fit_Iterations damped Gauss-Newton (Levenberg-
--    Marquardt) iterations on all ten parameters (eight of H, K1, K2)
--    that minimise the sum of the squared distances in pixels between
--    the observed points and the model, stopping early when a step is
--    tiny. The RMS of those distances (pixels) is the calibration's
--    ComputedRMSError. Degenerate points (on one line, say) give
--    Bad_Parameter, never a calibration.
--  * N-point calibrations (AMV's rules; VisionPro does not publish its
--    own). Calibrate needs the calibration image in this mode, as the
--    checkerboard does: its size fixes the distortion centre and the
--    normaliser, its selected space is the space of the uncalibrated
--    points (Image_No_Pixels for null: "CalibrationImage has no pixels";
--    the linear mode still ignores the image). At least Min_Warp_Points
--    (8) and at most Max_Warp_Points pairs (Bad_Parameter before anything
--    is fitted; Gold): five pairs determine the ten parameters exactly
--    and leave nothing to check them; eight give sixteen equations, six
--    more than the parameters, so that the RMS error measures the fit
--    and a wrong pair shows in it. Every uncalibrated point, mapped to
--    pixel space, must lie on the image (in [-0.5, Width - 0.5] x
--    [-0.5, Height - 0.5]; Bad_Parameter otherwise: a point measured in
--    the image lies on it, so one that does not is in another space or
--    of another image). Raw calibrated points that span less than
--    2 Min_Plate_Scale (all equal, say), points on one line and points
--    whose fitted model is degenerate give Bad_Parameter, never a
--    calibration. DOFsToCompute is not used (Fit_DOF), as for the
--    checkerboard.
--  * The warp (AMV.Kernels.Calib_Fix.Warp). The tool's output image has
--    the input's size; its pixel u shows the plate point q = A (u), A a
--    similarity chosen so that the plate is seen without distortion and
--    without perspective: the plate's centre (the centre of the bounding
--    box of the plate points: the corners' grid, or the raw calibrated
--    points) stays where the input shows it, the plate's first axis keeps
--    its direction there, and an area of the plate covers as many output
--    pixels as it covers input pixels there (the determinant of the
--    observed map at the centre); a mirrored plate stays mirrored. The
--    output pixel u takes the bilinear sample of the input at
--    p = D (H (A (u))), or the unfilled value where that point lies
--    outside the input, behind the camera or beyond the model's valid
--    radius (beyond the first radius where the radial map stops being
--    monotonic, Radial.Valid_Radius). The output's calibrated space is
--    linear: output pixels from calibrated coordinates is Inverse (A),
--    and the calibration's UncalibratedFromRawCalibrated transform F is
--    Selected_From_Pixel (of the calibration image) composed with it, so
--    that the tool adds the calibrated space (F * R, R from an adjustment
--    in raw calibrated space) to the output exactly as in the linear mode
--    (and the coordinate space trees stay linear). The other spaces of
--    the input's tree are kept as they are (they now refer to the
--    corrected pixels). The N-point tool warps as the checkerboard tool
--    does (ks_calibration_n_point_tool_execute), its unfilled pixels 0
--    (VisionPro's N-point run parameters have no UnfilledPelValue).
--  * The model record (Ks_Radial_Warp_Model) holds the normalised
--    parameters and the normalisation, so that a C caller can evaluate
--    the model: with g = ((X - Grid_Center_X) / Grid_Scale,
--    (Y - Grid_Center_Y) / Grid_Scale) for the plate point (X, Y) (the
--    grid indices (I, J) of a corner, an N-point calibration's raw
--    calibrated point), N_x = H11 g_x + H12 g_y + H13,
--    N_y = H21 g_x + H22 g_y + H23, w = 1 + H31 g_x + H32 g_y and
--    h = (N_x / w, N_y / w), rho = |h|**2, the pixel is
--    (Center_X, Center_Y) + Normalizer (1 + K1 rho + K2 rho**2) h. The
--    output pixel u shows the normalised plate point
--    g = Grid_From_Output (u).
--
--  Proved (docs/PROOF.md): absence of run-time errors for any argument,
--  NaN and infinities included, and any handle that is null or came from
--  this kernel (an inconsistent one is rejected with Bad_Parameter); no
--  memory leaks; the point pair entry points change exactly what they
--  document; Gold: the minimum point count of each DOF is checked before
--  fitting; every fit (Valid_Fit, Has_DOF_Structure, above), also the one
--  a calibration stores; the corners a checkerboard calibration keeps
--  number at least Min_Corners and at most Max_Corners and lie inside the
--  calibration image; a nonlinear model (Valid_Model): every parameter
--  finite and within its bound, the RMS error in [0, Max_RMS], the
--  transforms within the bounds of AMV.Kernels.Transforms, and a
--  calibration in PerspectiveAndRadialWarp mode has at least
--  Min_Warp_Points points and a model of its calibration image's size
--  (of the image passed to Calibrate); the warped output image has the
--  input's size and is sampled only inside the input; the origin
--  adjustment a calibration stores is always valid (Valid_Adjustment),
--  setting it keeps the calibrated state and the fit,
--  the transform of the calibrated space is within the bounds with a
--  non-zero determinant, it is exactly F for the default adjustment
--  (which never fails), and a calibration in PerspectiveAndRadialWarp
--  mode only has one with an adjustment in raw calibrated space. Not
--  proved (tested): the optimality and the accuracy of the nonlinear fit,
--  and the geometry of F * R (the origin and the axis where they are
--  asked to be). Trusted parts (SPARK_Mode Off bodies, listed in
--  docs/PROOF.md): the allocation helpers, which turn a failed allocation
--  into Out_Of_Memory.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Numerics;
with Ada.Numerics.Long_Elementary_Functions;

with AMV.Kernels.Coordinate_Spaces;
with AMV.Kernels.Images;
with AMV.Kernels.Transforms;

package AMV.Kernels.Calib_Fix with SPARK_Mode, Preelaborate is

   pragma Unevaluated_Use_Of_Old (Allow);
   --  Postconditions compare counts with their values on entry through
   --  the total function Count_Of.

   package KC renames AMV.Kernels.Coordinate_Spaces;
   package KI renames AMV.Kernels.Images;
   package KT renames AMV.Kernels.Transforms;
   package EF renames Ada.Numerics.Long_Elementary_Functions;

   use type KI.Ks_Image_8_Grey;

   Pi : constant := Ada.Numerics.Pi;

   ---------------------------------------------------------------------
   --  Bounds and limits
   ---------------------------------------------------------------------

   Max_Value : constant := KT.Max_Value;
   --  Every coordinate taken or returned lies within +/-1.0E150 (C:
   --  KS_CALIB_FIX_MAX_VALUE), the bound of AMV.Kernels.Transforms, so
   --  that it is a valid argument again.

   subtype Coordinate is Long_Float range -Max_Value .. Max_Value;

   Max_Pairs : constant := 2**19;
   --  Point pairs in a list (C: KS_CALIB_FIX_MAX_PAIRS). The sums of the
   --  fits stay below 2**20 with it.

   Max_RMS : constant := 4.0E150;
   --  The largest RMS error reported (C: KS_CALIB_FIX_MAX_RMS).

   Max_Tile_Size : constant := 1.0E140;
   --  The largest physical tile size (C: KS_CALIB_FIX_MAX_TILE_SIZE), so
   --  that a raw calibrated coordinate (a grid index of at most
   --  Max_Grid_Index times a tile size) stays within Max_Value.

   Max_Corners : constant := 65_536;
   --  The most corners a checkerboard calibration keeps (C:
   --  KS_CALIB_FIX_MAX_CORNERS).

   Min_Corners : constant := 9;
   --  The fewest corners a checkerboard calibration needs (C:
   --  KS_CALIB_FIX_MIN_CORNERS); VisionPro asks for nine too.

   Max_Grid_Index : constant := 65_536;
   --  Grid indices of corners lie in -Max_Grid_Index .. Max_Grid_Index.

   Collinear_Tolerance : constant := 1.0E-10;
   --  The B points of the fits with an aspect are taken as collinear when
   --  the determinant of their scatter matrix is below this fraction of
   --  its squared trace (scale free).

   Singular_Tolerance : constant := 1.0E-12;
   --  A fitted linear part is taken as singular when the magnitude of its
   --  determinant is below this fraction of the square of its largest
   --  entry (computed on the scaled points, so scale free).

   --  The bounds of the nonlinear model (PerspectiveAndRadialWarp), in
   --  its normalised coordinates (see above; C: KS_CALIB_FIX_MAX_*). A
   --  fit that would leave them is not accepted; they hold every lens and
   --  view the detector can see a board through (a board seen at 75
   --  degrees has w within [0.4, 1.6]; a real lens K1 and K2 within 1).

   Max_Homography_Entry : constant := 1024.0;
   --  H11, H12, H13, H21, H22, H23.

   Max_Perspective_Entry : constant := 16.0;
   --  H31, H32.

   Max_Radial_Coefficient : constant := 4.0;
   --  K1, K2.

   Max_Ideal : constant := 4.0;
   --  Each component of a corner's normalised ideal point (h - c) / s.

   Min_Denominator : constant := 0.0625;
   --  The smallest w at a corner (the board's centre has w = 1).

   Max_Radius_Squared : constant := 16.0;
   --  The largest valid radius (squared) of the radial map, r = 4: four
   --  times the image's half diagonal.

   Max_Fit_Iterations : constant := 50;
   --  Levenberg-Marquardt iterations.

   Max_Model_Side : constant := 2**24;
   --  The largest side of a calibration image (the detector's limit).

   Max_Model_Coordinate : constant := 2.0 ** 24;
   --  A bound of the image centre and of the normaliser (pixels).

   Max_Warp_Entry : constant := 2.0 ** 16;
   Max_Warp_Translation : constant := 2.0 ** 56;
   --  Bounds of the map from output pixels to normalised grid points.

   Max_Output_Coordinate : constant := 2.0 ** 32;
   --  The largest output pixel coordinate the map takes.

   Max_Tile_Aspect : constant := 1024.0;
   --  The tile sizes of a calibration in PerspectiveAndRadialWarp mode
   --  must be within this factor of each other (the warp keeps squares
   --  of the plate square).

   Min_Warp_Points : constant := 8;
   --  The fewest point pairs of an N-point calibration in
   --  PerspectiveAndRadialWarp mode (C: KS_CALIB_FIX_MIN_WARP_POINTS; see
   --  above). A checkerboard has at least Min_Corners corners.

   Max_Warp_Points : constant := Max_Corners;
   --  The most points the nonlinear fit takes (C:
   --  KS_CALIB_FIX_MAX_WARP_POINTS): a checkerboard's corners, an N-point
   --  calibration's pairs (the sums of the fit stay bounded with it).

   Min_Plate_Scale : constant := 1.0E-150;
   --  The smallest half extent of the plate points (plate units) that the
   --  nonlinear fit takes (C: KS_CALIB_FIX_MIN_PLATE_SCALE), the
   --  reciprocal of Max_Value: raw calibrated points of an N-point
   --  calibration that span less give Bad_Parameter.

   ---------------------------------------------------------------------
   --  Codes
   ---------------------------------------------------------------------

   DOF_None                                         : constant Int32 := 0;
   DOF_Translation_X                                : constant Int32 := 1;
   DOF_Translation_Y                                : constant Int32 := 2;
   DOF_Translation                                  : constant Int32 := 3;
   DOF_Rotation_And_Translation                     : constant Int32 := 4;
   DOF_Scaling_Rotation_And_Translation             : constant Int32 := 5;
   DOF_Scaling_Aspect_Rotation_And_Translation      : constant Int32 := 6;
   DOF_Scaling_Aspect_Rotation_Skew_And_Translation : constant Int32 := 7;
   --  CogNPointToNPointDOFConstants and CogCalibCheckerboardDOFConstants
   --  (C: KS_DOF_*), VisionPro's values.

   subtype DOF_Code is Int32 range DOF_None
     .. DOF_Scaling_Aspect_Rotation_Skew_And_Translation;

   function Min_Points (DOF : DOF_Code) return Natural is
     (case DOF is
        when DOF_None                                  => 0,
        when DOF_Translation_X .. DOF_Translation      => 1,
        when DOF_Rotation_And_Translation
           | DOF_Scaling_Rotation_And_Translation       => 2,
        when others                                    => 3);
   --  The fewest point pairs the fit of each DOF needs.

   Group_A : constant Int32 := 0;
   Group_B : constant Int32 := 1;
   --  Which point of a pair (C: KS_POINT_GROUP_A, KS_POINT_GROUP_B): A is
   --  the unfixtured or uncalibrated point, B the raw fixtured or raw
   --  calibrated one.

   Space_To_Output_New : constant Int32 := 0;
   Space_To_Output_Old : constant Int32 := 1;
   --  SpaceToOutput (C: KS_SPACE_TO_OUTPUT_*): CogFixtureSpaceToOutput-
   --  Constants FixturedSpace / UnfixturedSpace and CogCalibSpaceToOutput-
   --  Constants CalibratedSpace / UncalibratedSpace, VisionPro's values.

   Duplicate_Compatibility : constant Int32 := 1;
   Duplicate_Enhanced      : constant Int32 := 2;
   --  CogFixturedSpaceNameDuplicateHandlingConstants (C:
   --  KS_FIXTURED_SPACE_NAME_DUPLICATE_*), VisionPro's values.

   Kind_N_Point_To_N_Point : constant Int32 := 0;
   Kind_Checkerboard       : constant Int32 := 1;
   --  The kind of a calibration (C: KS_CALIBRATION_*).

   subtype Kind_Code is Int32
     range Kind_N_Point_To_N_Point .. Kind_Checkerboard;

   Mode_Linear                       : constant Int32 := 1;
   Mode_Perspective_And_Radial_Warp  : constant Int32 := 2;
   Mode_Linescan_Warp                : constant Int32 := 3;
   Mode_Linescan_2D_Warp             : constant Int32 := 4;
   Mode_Sine_Tan_Law_Projection_Warp : constant Int32 := 5;
   Mode_Three_Param_Radial_Warp      : constant Int32 := 6;
   Mode_No_Distortion_Warp           : constant Int32 := 7;
   --  CogCalibFixComputationModeConstants (C: KS_COMPUTATION_MODE_*),
   --  VisionPro's values. AMV implements Linear and
   --  PerspectiveAndRadialWarp (for both kinds of calibration).

   subtype Implemented_Mode is Int32
     range Mode_Linear .. Mode_Perspective_And_Radial_Warp;

   Adjustment_Space_Raw_Calibrated : constant Int32 := 0;
   Adjustment_Space_Uncalibrated   : constant Int32 := 1;
   --  CogCalibNPointAdjustmentSpaceConstants and
   --  CogCalibCheckerboardAdjustmentSpaceConstants (C:
   --  KS_ADJUSTMENT_SPACE_*), VisionPro's values: the space the origin and
   --  the x axis rotation of the origin adjustment are given in.

   subtype Adjustment_Space_Code is Int32
     range Adjustment_Space_Raw_Calibrated .. Adjustment_Space_Uncalibrated;

   function Fit_DOF (Mode, DOF : Int32) return Int32 is
     (if Mode = Mode_Perspective_And_Radial_Warp
      then DOF_Scaling_Aspect_Rotation_Skew_And_Translation else DOF);
   --  The DOF whose structure a calibration's stored fit has: its own DOF
   --  in the linear mode; none in particular (a general affine transform)
   --  in PerspectiveAndRadialWarp, whose transform is the output's (the
   --  DOFsToCompute of a calibration in that mode is not used).

   ---------------------------------------------------------------------
   --  The result of a fit
   ---------------------------------------------------------------------

   type Ks_N_Point_To_N_Point_Fit is record
      Transform : KT.Ks_Transform_2D_Linear;
      RMS_Error : Long_Float := 0.0;
      Scaling_X : Long_Float := 1.0;
      Scaling_Y : Long_Float := 1.0;
      Rotation  : Long_Float := 0.0;
      Skew      : Long_Float := 0.0;
   end record
     with Convention => C;
   --  C: ks_n_point_to_n_point_fit. Transform maps group B to group A
   --  (GroupAFromGroupB, UnfixturedFromFixtured, UncalibratedFrom-
   --  Calibrated). The parameters are those of the DOF: 1, 1, 0, 0 without
   --  a rotation; 1, 1, the angle, 0 for RotationAndTranslation; the
   --  scaling twice, the angle and 0 for ScalingRotationAndTranslation;
   --  Sx, Sy, the angle and 0 for ScalingAspectRotationAndTranslation; the
   --  decomposition of ks_transform_2d_linear_decompose (Scaling_X,
   --  Scaling_Y, Rotation_X, Skew) for the affine fit. The default is the
   --  identity.

   function Det_Of (T : KT.Ks_Transform_2D_Linear) return Long_Float is
     (T.A * T.D - T.B * T.C)
   with Pre => KT.Bounded (T);
   --  The determinant of the matrix, evaluated as written (no overflow for
   --  a bounded transform).

   function Valid_Fit (F : Ks_N_Point_To_N_Point_Fit) return Boolean is
     (KT.Bounded (F.Transform)
      and then Det_Of (F.Transform) /= 0.0
      and then F.RMS_Error >= 0.0 and then F.RMS_Error <= Max_RMS
      and then F.Scaling_X >= -KT.Max_Scaling
      and then F.Scaling_X <= KT.Max_Scaling
      and then F.Scaling_Y >= -KT.Max_Scaling
      and then F.Scaling_Y <= KT.Max_Scaling
      and then F.Rotation > -Pi and then F.Rotation <= Pi
      and then F.Skew > -Pi and then F.Skew <= Pi);
   --  A fit within its bounds, with a non-singular matrix (False for NaN
   --  at run time).

   function Is_Unit_Matrix (T : KT.Ks_Transform_2D_Linear) return Boolean is
     (T.A = 1.0 and then T.B = 0.0 and then T.C = 0.0 and then T.D = 1.0);

   function Unit_Parameters (F : Ks_N_Point_To_N_Point_Fit) return Boolean is
     (F.Scaling_X = 1.0 and then F.Scaling_Y = 1.0 and then F.Skew = 0.0);

   function Has_DOF_Structure
     (F   : Ks_N_Point_To_N_Point_Fit;
      DOF : Int32) return Boolean
   is
     (case DOF is
        when DOF_None =>
          Is_Unit_Matrix (F.Transform)
          and then F.Transform.Translation_X = 0.0
          and then F.Transform.Translation_Y = 0.0
          and then Unit_Parameters (F) and then F.Rotation = 0.0,
        when DOF_Translation_X =>
          Is_Unit_Matrix (F.Transform)
          and then F.Transform.Translation_Y = 0.0
          and then Unit_Parameters (F) and then F.Rotation = 0.0,
        when DOF_Translation_Y =>
          Is_Unit_Matrix (F.Transform)
          and then F.Transform.Translation_X = 0.0
          and then Unit_Parameters (F) and then F.Rotation = 0.0,
        when DOF_Translation =>
          Is_Unit_Matrix (F.Transform)
          and then Unit_Parameters (F) and then F.Rotation = 0.0,
        when DOF_Rotation_And_Translation =>
          F.Transform.A = EF.Cos (F.Rotation)
          and then F.Transform.C = EF.Sin (F.Rotation)
          and then F.Transform.B = -F.Transform.C
          and then F.Transform.D = F.Transform.A
          and then Unit_Parameters (F),
        when DOF_Scaling_Rotation_And_Translation =>
          F.Transform.A = F.Transform.D
          and then F.Transform.B = -F.Transform.C
          and then F.Scaling_X > 0.0
          and then F.Scaling_Y = F.Scaling_X
          and then F.Skew = 0.0,
        when DOF_Scaling_Aspect_Rotation_And_Translation =>
          F.Transform.A = F.Scaling_X * EF.Cos (F.Rotation)
          and then F.Transform.C = F.Scaling_X * EF.Sin (F.Rotation)
          and then F.Transform.B = -(F.Scaling_Y * EF.Sin (F.Rotation))
          and then F.Transform.D = F.Scaling_Y * EF.Cos (F.Rotation)
          and then F.Scaling_X > 0.0
          and then F.Skew = 0.0,
        when others => True)
   with Pre => Valid_Fit (F);
   --  The fit has exactly the structure of DOF (see above): no rotation
   --  and unit scale without a rotation DOF, a pure rotation for
   --  RotationAndTranslation, equal scales and no skew for
   --  ScalingRotationAndTranslation, orthogonal columns (no skew) for
   --  ScalingAspectRotationAndTranslation. Executable: the kernel checks it
   --  on a stored fit and on one read from a stream.

   function Gold_Fit (F : Ks_N_Point_To_N_Point_Fit; DOF : Int32)
      return Boolean
   is (Valid_Fit (F) and then Has_DOF_Structure (F, DOF));

   ---------------------------------------------------------------------
   --  Point pairs (C: ks_point_pairs)
   ---------------------------------------------------------------------

   type Ks_Point_Pair is record
      A_X : Coordinate := 0.0;
      A_Y : Coordinate := 0.0;
      B_X : Coordinate := 0.0;
      B_Y : Coordinate := 0.0;
   end record;
   --  One pair (not seen by C, which passes the coordinates).

   type Pair_Array is array (Natural range <>) of Ks_Point_Pair;

   type Pair_Array_Access is access Pair_Array;

   type Ks_Point_Pairs_Data is limited record
      Count : Natural := 0;
      Pairs : Pair_Array_Access;
   end record;
   --  What a handle designates (opaque for C): Count pairs in
   --  Pairs (0 .. Count - 1); the array may be longer (room to add) and is
   --  null when there is no room. Valid_Pairs states the invariant.

   type Ks_Point_Pairs is access Ks_Point_Pairs_Data
     with Convention => C;
   --  C: ks_point_pairs *.

   function Valid_Pairs
     (Pairs : access constant Ks_Point_Pairs_Data) return Boolean
   is (Pairs /= null
       and then Pairs.Count <= Max_Pairs
       and then (if Pairs.Pairs = null then Pairs.Count = 0
                 else Pairs.Pairs'First = 0
                      and then Pairs.Pairs'Last < Max_Pairs
                      and then Pairs.Count <= Pairs.Pairs'Last + 1));
   --  A handle with its pairs in place.

   function Count_Of
     (Pairs : access constant Ks_Point_Pairs_Data) return Natural
   is (if Valid_Pairs (Pairs) then Pairs.Count else 0);
   --  The number of pairs (0 for null or an inconsistent handle).

   procedure Pairs_Num_Points
     (Pairs  : access constant Ks_Point_Pairs_Data;
      Count  : out Int32;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_point_pairs_num_points",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Count in 0 .. Max_Pairs
             and then (if Succeeded (Status)
                       then Count = Int32 (Count_Of (Pairs)));
   --  NumPoints (0 for null).

   procedure Pairs_Add_Point_Pair
     (Pairs              : in out Ks_Point_Pairs;
      A_X, A_Y, B_X, B_Y : Long_Float;
      Status             : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_point_pairs_add_point_pair",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Valid_Pairs (Pairs)
                            and then Pairs.Count = Count_Of (Pairs)'Old + 1
                            and then Pairs.Pairs (Pairs.Count - 1)
                                       = (A_X, A_Y, B_X, B_Y)
                       else Count_Of (Pairs) = Count_Of (Pairs)'Old);
   --  AddPointPair: appends the pair. Creates the handle when Pairs is
   --  null. Bad_Parameter for a coordinate that is not finite or not
   --  within Max_Value and when the list holds Max_Pairs pairs already.

   procedure Pairs_Delete_Point_Pair
     (Pairs  : Ks_Point_Pairs;
      Index  : Int32;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_point_pairs_delete_point_pair",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then (if Succeeded (Status)
                       then Valid_Pairs (Pairs)
                            and then Count_Of (Pairs)
                                       = Count_Of (Pairs)'Old - 1
                       else Count_Of (Pairs) = Count_Of (Pairs)'Old);
   --  DeletePointPair: removes pair Index (0-based); the later pairs move
   --  down by one. Index_Out_Of_Range unless Index is in
   --  0 .. NumPoints - 1.

   procedure Pairs_Get_Point
     (Pairs  : access constant Ks_Point_Pairs_Data;
      Index  : Int32;
      Group  : Int32;
      X, Y   : out Long_Float;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_point_pairs_get_point",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then (if Succeeded (Status)
                       then Valid_Pairs (Pairs)
                            and then Index in 0 .. Int32 (Pairs.Count) - 1
                            and then X
                                       = (if Group = Group_A
                                          then Pairs.Pairs (Natural (Index)).A_X
                                          else Pairs.Pairs (Natural (Index)).B_X)
                            and then Y
                                       = (if Group = Group_A
                                          then Pairs.Pairs (Natural (Index)).A_Y
                                          else Pairs.Pairs (Natural (Index)).B_Y)
                       else X = 0.0 and then Y = 0.0);
   --  The point of Group (Group_A or Group_B, Bad_Parameter otherwise) of
   --  pair Index: GetGroupAPoint, GetUnfixturedPoint, GetUncalibrated-
   --  Point (A) and GetGroupBPoint, GetRawFixturedPoint, GetRawCalibrated-
   --  Point (B).

   procedure Pairs_Set_Point
     (Pairs  : Ks_Point_Pairs;
      Index  : Int32;
      Group  : Int32;
      X, Y   : Long_Float;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_point_pairs_set_point",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then Count_Of (Pairs) = Count_Of (Pairs)'Old
             and then (if Succeeded (Status)
                       then Valid_Pairs (Pairs)
                            and then Index in 0 .. Int32 (Pairs.Count) - 1
                            and then (if Group = Group_A
                                      then Pairs.Pairs (Natural (Index)).A_X = X
                                           and then Pairs.Pairs
                                                      (Natural (Index)).A_Y = Y
                                      else Pairs.Pairs (Natural (Index)).B_X = X
                                           and then Pairs.Pairs
                                                      (Natural (Index)).B_Y
                                                      = Y));
   --  Changes the point of Group of pair Index (SetGroupAPoint,
   --  SetUnfixturedPoint, ...). A failed call changes nothing.

   procedure Pairs_Clear
     (Pairs  : Ks_Point_Pairs;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_point_pairs_clear",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status) then Count_Of (Pairs) = 0);
   --  Removes every pair (AMV name).

   procedure Pairs_Duplicate
     (Pairs  : access constant Ks_Point_Pairs_Data;
      Copy   : out Ks_Point_Pairs;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_point_pairs_duplicate",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status) and then Pairs /= null
                       then Valid_Pairs (Copy)
                            and then Copy.Count = Count_Of (Pairs)
                       else Copy = null);
   --  A new list with the same pairs (null for null).

   procedure Pairs_Destroy (Pairs : in out Ks_Point_Pairs)
   with
     Export, Convention => C,
     External_Name => "ks_point_pairs_destroy",
     Post => Pairs = null;
   --  Frees the list (nothing for null).

   ---------------------------------------------------------------------
   --  The fit (CogNPointToNPoint)
   ---------------------------------------------------------------------

   procedure N_Point_To_N_Point_Compute
     (Pairs           : access constant Ks_Point_Pairs_Data;
      DOFs_To_Compute : Int32;
      Fit             : out Ks_N_Point_To_N_Point_Fit;
      Status          : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_n_point_to_n_point_compute",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if DOFs_To_Compute in DOF_Code
                         and then Count_Of (Pairs)
                                    < Min_Points (DOFs_To_Compute)
                       then Status.Failure = Failure_Bad_Parameter)
             and then (if Succeeded (Status)
                       then DOFs_To_Compute in DOF_Code
                            and then Count_Of (Pairs)
                                       >= Min_Points (DOFs_To_Compute)
                            and then Gold_Fit (Fit, DOFs_To_Compute));
   --  ComputeGroupAFromGroupBTransform: the fit of the pairs (see above).
   --  Bad_Parameter for an unknown DOF code ("DOFsToCompute must be a
   --  CogNPointToNPointDOFConstants value"), an inconsistent handle, too
   --  few pairs and degenerate data. Fit is the identity when the call
   --  fails.

   ---------------------------------------------------------------------
   --  The fixture tool (CogFixtureTool, run parameters CogFixture)
   ---------------------------------------------------------------------

   Default_Fixture_Name : constant KC.Ks_Space_Name :=
     (Length => 7,
      Text   => ['F', 'i', 'x', 't', 'u', 'r', 'e', others => ASCII.NUL]);
   --  "Fixture" (AMV's default; VisionPro does not document one).

   type Ks_Fixture_Run_Params is record
      Unfixtured_From_Fixtured_Transform     : KT.Ks_Transform_2D_Linear;
      Fixtured_Space_Name                    : KC.Ks_Space_Name :=
        Default_Fixture_Name;
      Space_To_Output                        : Int32 := Space_To_Output_New;
      Fixtured_Space_Name_Duplicate_Handling : Int32 :=
        Duplicate_Compatibility;
   end record
     with Convention => C;
   --  CogFixture (C: ks_fixture_run_params): the transform from the
   --  fixtured space into the input's selected space (identity), the
   --  name of the fixtured space (a valid space name component), and the
   --  codes above.

   procedure Fixture_Run_Params_Default
     (Params : out Ks_Fixture_Run_Params;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_fixture_run_params_default",
     Post => Valid (Status) and then Succeeded (Status);
   --  The defaults above. Never fails.

   procedure Fixture_Execute
     (Input_Image     : access constant KI.Ks_Image_8_Grey_Data;
      Params          : Ks_Fixture_Run_Params;
      Tree            : in out KC.Ks_Coordinate_Space_Tree;
      Selected        : in out KC.Ks_Space_Name;
      Pixel_From_Root : KT.Ks_Transform_2D_Linear;
      Status          : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_fixture_execute",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter
                         | Failure_Image_Bad_Selected_Space_Name
                         | Failure_Transform_Singular | Failure_Other
             and then (if Succeeded (Status)
                       then KC.Valid_Tree (Tree) and then KC.Fits (Selected));
   --  CogFixture.Execute on the coordinate space state of the input image
   --  (Tree, Selected, Pixel_From_Root): adds the fixtured space as
   --  described above and updates the selection. Failures:
   --  Image_No_Pixels for a null Input_Image ("InputImage has no pixels");
   --  Bad_Parameter for codes out of range, a name that is not a valid
   --  component ("RunParams.FixturedSpaceName ..."), a transform that is
   --  not finite or not within the bound, an invalid tree, a full tree or
   --  a name that is too long, and an existing space with Enhanced;
   --  Transform_Singular for a transform that is not invertible within the
   --  bound; Image_Bad_Selected_Space_Name, Bad_Parameter or
   --  Transform_Singular from the pixel space rule. Failure_Other never
   --  happens (a guard). Tree and Selected are unchanged when the call
   --  fails before the space is added.

   ---------------------------------------------------------------------
   --  The N-point fixture tool (CogFixtureNPointToNPointTool, run
   --  parameters CogFixtureNPointToNPoint)
   ---------------------------------------------------------------------

   Default_N_Point_Fixture_Name : constant KC.Ks_Space_Name :=
     (Length => 15,
      Text   => ['N', '-', 'P', 'o', 'i', 'n', 't', ' ', 'F', 'i', 'x', 't',
                 'u', 'r', 'e', others => ASCII.NUL]);
   --  "N-Point Fixture", VisionPro's default.

   type Ks_Fixture_N_Point_To_N_Point_Run_Params is record
      DOFs_To_Compute                        : Int32 :=
        DOF_Rotation_And_Translation;
      Fixtured_Space_Name                    : KC.Ks_Space_Name :=
        Default_N_Point_Fixture_Name;
      Space_To_Output                        : Int32 := Space_To_Output_New;
      Fixtured_Space_Name_Duplicate_Handling : Int32 :=
        Duplicate_Compatibility;
   end record
     with Convention => C;
   --  CogFixtureNPointToNPoint without its point pairs (C:
   --  ks_fixture_n_point_to_n_point_run_params), with VisionPro's
   --  defaults.

   procedure Fixture_N_Point_To_N_Point_Run_Params_Default
     (Params : out Ks_Fixture_N_Point_To_N_Point_Run_Params;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_fixture_n_point_to_n_point_run_params_default",
     Post => Valid (Status) and then Succeeded (Status);

   procedure Fixture_N_Point_To_N_Point_Execute
     (Input_Image     : access constant KI.Ks_Image_8_Grey_Data;
      Pairs           : access constant Ks_Point_Pairs_Data;
      Params          : Ks_Fixture_N_Point_To_N_Point_Run_Params;
      Tree            : in out KC.Ks_Coordinate_Space_Tree;
      Selected        : in out KC.Ks_Space_Name;
      Pixel_From_Root : KT.Ks_Transform_2D_Linear;
      Fit             : out Ks_N_Point_To_N_Point_Fit;
      Status          : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_fixture_n_point_to_n_point_execute",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter
                         | Failure_Image_Bad_Selected_Space_Name
                         | Failure_Transform_Singular | Failure_Other
             and then (if Params.DOFs_To_Compute in DOF_Code
                         and then Input_Image /= null
                         and then Count_Of (Pairs)
                                    < Min_Points (Params.DOFs_To_Compute)
                       then Status.Failure = Failure_Bad_Parameter)
             and then (if Succeeded (Status)
                       then Params.DOFs_To_Compute in DOF_Code
                            and then Count_Of (Pairs)
                                       >= Min_Points (Params.DOFs_To_Compute)
                            and then Gold_Fit (Fit, Params.DOFs_To_Compute)
                            and then KC.Valid_Tree (Tree)
                            and then KC.Fits (Selected));
   --  CogFixtureNPointToNPoint.Execute: fits UnfixturedFromFixtured (group
   --  A from group B) as ks_n_point_to_n_point_compute does and adds the
   --  fixtured space with it as ks_fixture_execute does. Fit
   --  (CogFixtureNPointToNPointResult: GetUnfixturedFromFixturedTransform,
   --  RMSError) is the identity when the call fails.

   ---------------------------------------------------------------------
   --  Calibrations (C: ks_calibration; CogCalibNPointToNPoint and
   --  CogCalibCheckerboard)
   ---------------------------------------------------------------------

   ---------------------------------------------------------------------
   --  The nonlinear model (PerspectiveAndRadialWarp)
   ---------------------------------------------------------------------

   type Ks_Radial_Warp_Model is record
      H11                          : Long_Float := 1.0;
      H12                          : Long_Float := 0.0;
      H13                          : Long_Float := 0.0;
      H21                          : Long_Float := 0.0;
      H22                          : Long_Float := 1.0;
      H23                          : Long_Float := 0.0;
      H31                          : Long_Float := 0.0;
      H32                          : Long_Float := 0.0;
      K1                           : Long_Float := 0.0;
      K2                           : Long_Float := 0.0;
      Center_X                     : Long_Float := 0.0;
      Center_Y                     : Long_Float := 0.0;
      Normalizer                   : Long_Float := 1.0;
      Grid_Center_X                : Long_Float := 0.0;
      Grid_Center_Y                : Long_Float := 0.0;
      Grid_Scale                   : Long_Float := 1.0;
      Valid_Radius_Squared         : Long_Float := 0.0;
      RMS_Error                    : Long_Float := 0.0;
      Output_Pixel_From_Calibrated : KT.Ks_Transform_2D_Linear;
      Grid_From_Output             : KT.Ks_Transform_2D_Linear;
      Image_Width                  : Int32 := 0;
      Image_Height                 : Int32 := 0;
      Iterations                   : Int32 := 0;
   end record
     with Convention => C;
   --  (AMV name) C: ks_radial_warp_model. The fitted model of a
   --  calibration in PerspectiveAndRadialWarp mode, in the normalised
   --  coordinates described above: the homography from normalised plate
   --  points to normalised ideal points (H11 .. H32, H33 = 1), the radial
   --  coefficients K1 and K2, the distortion centre (Center_X, Center_Y)
   --  and the normaliser (pixels), the plate's normalisation
   --  (Grid_Center_X, Grid_Center_Y, Grid_Scale, in plate units: grid
   --  steps for a checkerboard, raw calibrated units for an N-point
   --  calibration), the valid radius (rho, normalised, squared) of the
   --  radial map, the RMS distance (pixels) between the observed points
   --  and the model, the warp: Output_Pixel_From_Calibrated (the inverse
   --  of A, a similarity of the calibrated coordinates) and
   --  Grid_From_Output (output pixels to normalised plate points), the
   --  size of the calibration image (the size of the images the model
   --  applies to) and the number of accepted Levenberg-Marquardt steps.

   function Valid_Model (M : Ks_Radial_Warp_Model) return Boolean is
     (abs M.H11 <= Max_Homography_Entry
      and then abs M.H12 <= Max_Homography_Entry
      and then abs M.H13 <= Max_Homography_Entry
      and then abs M.H21 <= Max_Homography_Entry
      and then abs M.H22 <= Max_Homography_Entry
      and then abs M.H23 <= Max_Homography_Entry
      and then abs M.H31 <= Max_Perspective_Entry
      and then abs M.H32 <= Max_Perspective_Entry
      and then abs M.K1 <= Max_Radial_Coefficient
      and then abs M.K2 <= Max_Radial_Coefficient
      and then M.Center_X >= 0.0 and then M.Center_X <= Max_Model_Coordinate
      and then M.Center_Y >= 0.0 and then M.Center_Y <= Max_Model_Coordinate
      and then M.Normalizer >= 0.5
      and then M.Normalizer <= Max_Model_Coordinate
      and then abs M.Grid_Center_X <= Max_Value
      and then abs M.Grid_Center_Y <= Max_Value
      and then M.Grid_Scale >= Min_Plate_Scale
      and then M.Grid_Scale <= Max_Value
      and then M.Valid_Radius_Squared >= 0.0
      and then M.Valid_Radius_Squared <= Max_Radius_Squared
      and then M.RMS_Error >= 0.0 and then M.RMS_Error <= Max_RMS
      and then KT.Bounded (M.Output_Pixel_From_Calibrated)
      and then abs M.Grid_From_Output.A <= Max_Warp_Entry
      and then abs M.Grid_From_Output.B <= Max_Warp_Entry
      and then abs M.Grid_From_Output.C <= Max_Warp_Entry
      and then abs M.Grid_From_Output.D <= Max_Warp_Entry
      and then abs M.Grid_From_Output.Translation_X <= Max_Warp_Translation
      and then abs M.Grid_From_Output.Translation_Y <= Max_Warp_Translation
      and then M.Image_Width in 1 .. Max_Model_Side
      and then M.Image_Height in 1 .. Max_Model_Side
      and then M.Iterations in 0 .. Max_Fit_Iterations);
   --  Gold: every value finite and within its documented bound (False for
   --  NaN at run time). Every model the kernel stores or returns has it.
   --  The plate's normalisation is bounded as the plate points are
   --  (within Max_Value, a half extent of at least Min_Plate_Scale): a
   --  checkerboard's lies within Max_Grid_Index (grid steps, a half
   --  extent of at least 0.5).

   Max_Image_Side : constant := 2**31 - 1;

   subtype Pixel_Position is Long_Float range 0.0 .. 2.0**31;
   subtype Grid_Index is Int32 range -Max_Grid_Index .. Max_Grid_Index;

   type Ks_Corner is record
      Pixel_X : Pixel_Position := 0.0;
      Pixel_Y : Pixel_Position := 0.0;
      Grid_I  : Grid_Index := 0;
      Grid_J  : Grid_Index := 0;
   end record;
   --  A corner a checkerboard calibration found: its position in pixel
   --  space and its grid indices (not seen by C).

   type Corner_Array is array (Natural range <>) of Ks_Corner;

   type Corner_Array_Access is access Corner_Array;

   type Ks_Calibration_Adjustment is record
      Calibrated_Origin_X              : Long_Float := 0.0;
      Calibrated_Origin_Y              : Long_Float := 0.0;
      Calibrated_X_Axis_Rotation       : Long_Float := 0.0;
      Calibrated_Origin_Space          : Int32 :=
        Adjustment_Space_Raw_Calibrated;
      Calibrated_X_Axis_Rotation_Space : Int32 :=
        Adjustment_Space_Raw_Calibrated;
      Swap_Calibrated_Handedness       : Int32 := False_Value;
   end record
     with Convention => C;
   --  (AMV name for the group of properties) C: ks_calibration_adjustment.
   --  The origin adjustment of a calibration (see above): CalibratedOriginX
   --  and CalibratedOriginY (in the space of CalibratedOriginSpace),
   --  CalibratedXAxisRotation (radians, in the space of
   --  CalibratedXAxisRotationSpace), the two space codes and
   --  SwapCalibratedHandedness (False_Value or True_Value). The defaults
   --  (AMV's) leave the raw calibrated space as it is.

   Default_Adjustment : constant Ks_Calibration_Adjustment := (others => <>);

   function Valid_Adjustment (A : Ks_Calibration_Adjustment) return Boolean
   is (A.Calibrated_Origin_X >= -Max_Value
       and then A.Calibrated_Origin_X <= Max_Value
       and then A.Calibrated_Origin_Y >= -Max_Value
       and then A.Calibrated_Origin_Y <= Max_Value
       and then A.Calibrated_X_Axis_Rotation > -Pi
       and then A.Calibrated_X_Axis_Rotation <= Pi
       and then A.Calibrated_Origin_Space in Adjustment_Space_Code
       and then A.Calibrated_X_Axis_Rotation_Space in Adjustment_Space_Code
       and then A.Swap_Calibrated_Handedness in False_Value | True_Value);
   --  An adjustment as a calibration stores it: the origin finite and
   --  within Max_Value, the rotation in (-Pi, Pi], the codes in range
   --  (False for NaN at run time).

   function Is_Identity_Adjustment (A : Ks_Calibration_Adjustment)
      return Boolean
   is (A.Calibrated_Origin_Space = Adjustment_Space_Raw_Calibrated
       and then A.Calibrated_Origin_X = 0.0
       and then A.Calibrated_Origin_Y = 0.0
       and then A.Calibrated_X_Axis_Rotation_Space
                  = Adjustment_Space_Raw_Calibrated
       and then A.Calibrated_X_Axis_Rotation = 0.0
       and then A.Swap_Calibrated_Handedness = False_Value);
   --  The adjustment leaves the raw calibrated space as it is (R is the
   --  identity): the defaults (a zero of either sign).

   function In_Raw_Calibrated_Space (A : Ks_Calibration_Adjustment)
      return Boolean
   is (A.Calibrated_Origin_Space = Adjustment_Space_Raw_Calibrated
       and then A.Calibrated_X_Axis_Rotation_Space
                  = Adjustment_Space_Raw_Calibrated);
   --  Both the origin and the rotation are given in raw calibrated space
   --  (what PerspectiveAndRadialWarp mode supports).

   type Ks_Calibration_Data is limited record
      Kind         : Int32 := Kind_N_Point_To_N_Point;
      DOF          : Int32 := DOF_Scaling_Aspect_Rotation_Skew_And_Translation;
      Tile_X       : Long_Float := 1.0;
      Tile_Y       : Long_Float := 1.0;
      Pairs        : Ks_Point_Pairs;
      Corners      : Corner_Array_Access;
      Image_Width  : Int32 := 0;
      Image_Height : Int32 := 0;
      Calibrated   : Int32 := False_Value;
      Fit          : Ks_N_Point_To_N_Point_Fit;
      Mode         : Int32 := Mode_Linear;
      Model        : Ks_Radial_Warp_Model;
      Adjustment   : Ks_Calibration_Adjustment;
   end record;
   --  What a calibration handle designates (opaque for C). Pairs holds the
   --  uncalibrated (A) and raw calibrated (B) points: the user's for an
   --  N-point calibration, the corners found for a checkerboard
   --  calibration, whose Corners (0 .. Count - 1) hold the corners'
   --  pixel positions and grid indices in the same order, and whose
   --  Image_Width and Image_Height are the size of the image they were
   --  found in (for an N-point calibration calibrated in
   --  PerspectiveAndRadialWarp mode, the size of its calibration image;
   --  0 otherwise). Tile_X and Tile_Y are the physical tile sizes (a
   --  checkerboard's input; 1.0 for an N-point calibration). Mode is the
   --  computation mode; Model the nonlinear model of a calibration
   --  calibrated in PerspectiveAndRadialWarp mode (the default record
   --  otherwise), whose Fit is then the output's UncalibratedFromRaw-
   --  Calibrated transform with the model's RMS error (pixels).
   --  Adjustment is the origin adjustment (not an input of the fit).

   type Ks_Calibration is access Ks_Calibration_Data
     with Convention => C;
   --  C: ks_calibration *.

   function Valid_Tile (Size : Long_Float) return Boolean is
     (Size > 0.0 and then Size <= Max_Tile_Size);

   function Valid_Calibration
     (Calibration : access constant Ks_Calibration_Data) return Boolean
   is (Calibration /= null
       and then Calibration.Kind in Kind_Code
       and then Calibration.DOF in DOF_Code
       and then Calibration.Calibrated in False_Value | True_Value
       and then Valid_Tile (Calibration.Tile_X)
       and then Valid_Tile (Calibration.Tile_Y)
       and then (Calibration.Pairs = null
                 or else Valid_Pairs (Calibration.Pairs))
       and then Calibration.Image_Width >= 0
       and then Calibration.Image_Height >= 0
       and then (if Calibration.Kind = Kind_N_Point_To_N_Point
                 then Calibration.Corners = null
                 elsif Calibration.Corners = null
                 then Count_Of (Calibration.Pairs) = 0
                 else Calibration.Corners'First = 0
                      and then Calibration.Corners'Last < Max_Corners
                      and then Count_Of (Calibration.Pairs)
                                 <= Calibration.Corners'Last + 1)
       and then Calibration.Mode in Implemented_Mode
       and then Valid_Adjustment (Calibration.Adjustment)
       and then (if Calibration.Calibrated = True_Value
                 then Count_Of (Calibration.Pairs)
                        >= Min_Points (Calibration.DOF)
                      and then Gold_Fit
                                 (Calibration.Fit,
                                  Fit_DOF (Calibration.Mode,
                                           Calibration.DOF))
                      and then
                        (if Calibration.Mode
                              = Mode_Perspective_And_Radial_Warp
                         then Valid_Model (Calibration.Model)
                              and then Count_Of (Calibration.Pairs)
                                         >= Min_Warp_Points
                              and then Calibration.Model.Image_Width
                                         = Calibration.Image_Width
                              and then Calibration.Model.Image_Height
                                         = Calibration.Image_Height)));
   --  The invariant of a calibration handle, checked by every entry point
   --  (Bad_Parameter otherwise): codes and tile sizes in range, consistent
   --  arrays, a valid origin adjustment, and a calibrated handle has enough
   --  points and a fit of its DOF's structure (in the linear mode), and in
   --  PerspectiveAndRadialWarp mode at least Min_Warp_Points points and a
   --  valid model of its calibration image (the corners' image of a
   --  checkerboard, the image an N-point calibration was calibrated with,
   --  whose size Image_Width and Image_Height record).

   function Is_Calibrated
     (Calibration : access constant Ks_Calibration_Data) return Boolean
   is (Valid_Calibration (Calibration)
       and then Calibration.Calibrated = True_Value);
   --  A consistent handle that is calibrated (False for null).

   function Fit_Of
     (Calibration : access constant Ks_Calibration_Data)
      return Ks_N_Point_To_N_Point_Fit
   is (if Valid_Calibration (Calibration) then Calibration.Fit
       else (others => <>));
   --  The stored fit (the identity for null or an inconsistent handle).

   function Adjustment_Of
     (Calibration : access constant Ks_Calibration_Data)
      return Ks_Calibration_Adjustment
   is (if Valid_Calibration (Calibration) then Calibration.Adjustment
       else Default_Adjustment);
   --  The stored origin adjustment (the defaults for null or an
   --  inconsistent handle).

   function Corners_Inside
     (Calibration : access constant Ks_Calibration_Data) return Boolean
   is (Valid_Calibration (Calibration)
       and then Calibration.Kind = Kind_Checkerboard
       and then Calibration.Corners /= null
       and then Count_Of (Calibration.Pairs) in Min_Corners .. Max_Corners
       and then (for all K in 0 .. Count_Of (Calibration.Pairs) - 1
                 => Calibration.Corners (K).Pixel_X
                      <= Long_Float (Calibration.Image_Width - 1)
                    and then Calibration.Corners (K).Pixel_Y
                               <= Long_Float (Calibration.Image_Height - 1)))
   with Ghost;
   --  The corners of a checkerboard calibration: between Min_Corners and
   --  Max_Corners of them, each inside the image they were found in
   --  (positions in [0, Width - 1] x [0, Height - 1]).

   function Count_Of
     (Calibration : access constant Ks_Calibration_Data) return Natural
   is (if Valid_Calibration (Calibration)
       then Count_Of (Calibration.Pairs) else 0);
   --  The number of point pairs (0 for null).

   procedure Calibration_Create
     (Kind        : Int32;
      Calibration : out Ks_Calibration;
      Status      : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_calibration_create",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Valid_Calibration (Calibration)
                            and then Calibration.Kind = Kind
                            and then Calibration.Calibrated = False_Value
                            and then Count_Of (Calibration) = 0
                            and then Calibration.Adjustment
                                       = Default_Adjustment
                       else Calibration = null);
   --  A new calibration of Kind with VisionPro's defaults: no points,
   --  DOFsToCompute ScalingAspectRotationSkewAndTranslation (for both
   --  kinds), PhysicalTileSizeX and Y 1.0, not calibrated; and AMV's
   --  default origin adjustment.

   procedure Calibration_Destroy (Calibration : in out Ks_Calibration)
   with
     Export, Convention => C,
     External_Name => "ks_calibration_destroy",
     Post => Calibration = null;
   --  Frees the calibration (nothing for null).

   procedure Calibration_Duplicate
     (Calibration : access constant Ks_Calibration_Data;
      Copy        : out Ks_Calibration;
      Status      : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_calibration_duplicate",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status) and then Calibration /= null
                       then Valid_Calibration (Calibration)
                            and then Valid_Calibration (Copy)
                            and then Copy.Kind = Calibration.Kind
                            and then Copy.Calibrated = Calibration.Calibrated
                            and then Count_Of (Copy)
                                       = Count_Of (Calibration)
                            and then Copy.Adjustment
                                       = Calibration.Adjustment
                       else Copy = null);
   --  A copy of everything, the computed state included (null for null).

   procedure Calibration_Kind
     (Calibration : access constant Ks_Calibration_Data;
      Kind        : out Int32;
      Status      : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_calibration_kind",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status) then Kind in Kind_Code);
   --  The kind (Bad_Parameter for null).

   procedure Calibration_Num_Points
     (Calibration : access constant Ks_Calibration_Data;
      Count       : out Int32;
      Status      : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_calibration_num_points",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Count in 0 .. Max_Pairs
             and then (if Succeeded (Status)
                       then Count = Int32 (Count_Of (Calibration)));
   --  NumPoints: the point pairs of an N-point calibration, the corners a
   --  checkerboard calibration found (0 before it is calibrated).

   procedure Calibration_Get_Point
     (Calibration : access constant Ks_Calibration_Data;
      Index       : Int32;
      Group       : Int32;
      X, Y        : out Long_Float;
      Status      : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_calibration_get_point",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then (if Succeeded (Status)
                       then X in Coordinate and then Y in Coordinate
                       else X = 0.0 and then Y = 0.0);
   --  GetUncalibratedPoint (Group_A) and GetRawCalibratedPoint (Group_B)
   --  of pair Index.

   procedure Calibration_Add_Point_Pair
     (Calibration                      : Ks_Calibration;
      Uncalibrated_X, Uncalibrated_Y   : Long_Float;
      Raw_Calibrated_X, Raw_Calibrated_Y : Long_Float;
      Status                           : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_calibration_add_point_pair",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Valid_Calibration (Calibration)
                            and then Calibration.Calibrated = False_Value
                            and then Count_Of (Calibration)
                                       = Count_Of (Calibration)'Old + 1);
   --  AddPointPair of an N-point calibration (Bad_Parameter for null and
   --  for a checkerboard calibration); uncalibrates.

   procedure Calibration_Delete_Point_Pair
     (Calibration : Ks_Calibration;
      Index       : Int32;
      Status      : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_calibration_delete_point_pair",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then (if Succeeded (Status)
                       then Valid_Calibration (Calibration)
                            and then Calibration.Calibrated = False_Value
                            and then Count_Of (Calibration)
                                       = Count_Of (Calibration)'Old - 1);
   --  DeletePointPair of an N-point calibration; uncalibrates.

   procedure Calibration_Set_Point
     (Calibration : Ks_Calibration;
      Index       : Int32;
      Group       : Int32;
      X, Y        : Long_Float;
      Status      : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_calibration_set_point",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then (if Succeeded (Status)
                       then Valid_Calibration (Calibration)
                            and then Calibration.Calibrated = False_Value);
   --  SetUncalibratedPoint (Group_A) and SetRawCalibratedPoint (Group_B)
   --  of an N-point calibration; uncalibrates.

   procedure Calibration_DOFs_To_Compute
     (Calibration : access constant Ks_Calibration_Data;
      DOF         : out Int32;
      Status      : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_calibration_dofs_to_compute",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status) then DOF in DOF_Code);

   procedure Calibration_Set_DOFs_To_Compute
     (Calibration : Ks_Calibration;
      DOF         : Int32;
      Status      : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_calibration_set_dofs_to_compute",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Valid_Calibration (Calibration)
                            and then Calibration.DOF = DOF
                            and then Calibration.Calibrated = False_Value);
   --  DOFsToCompute (a DOF code); setting it uncalibrates.

   procedure Calibration_Physical_Tile_Size
     (Calibration          : access constant Ks_Calibration_Data;
      Tile_Size_X, Tile_Size_Y : out Long_Float;
      Status               : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_calibration_physical_tile_size",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Valid_Tile (Tile_Size_X)
                            and then Valid_Tile (Tile_Size_Y));
   --  PhysicalTileSizeX and PhysicalTileSizeY (1.0 for an N-point
   --  calibration).

   procedure Calibration_Set_Physical_Tile_Size
     (Calibration          : Ks_Calibration;
      Tile_Size_X, Tile_Size_Y : Long_Float;
      Status               : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_calibration_set_physical_tile_size",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Valid_Calibration (Calibration)
                            and then Calibration.Tile_X = Tile_Size_X
                            and then Calibration.Tile_Y = Tile_Size_Y
                            and then Calibration.Calibrated = False_Value);
   --  Sets both physical tile sizes of a checkerboard calibration (each in
   --  (0, Max_Tile_Size]: "PhysicalTileSizeX must be > 0 and at most
   --  1.0E140"); uncalibrates.

   procedure Calibration_Calibrate
     (Calibration         : Ks_Calibration;
      Calibration_Image   : access constant KI.Ks_Image_8_Grey_Data;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Status              : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_calibration_calibrate",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Valid_Calibration (Calibration)
                            and then Calibration.Calibrated = True_Value
                            and then Count_Of (Calibration)
                                       >= Min_Points (Calibration.DOF)
                            and then Gold_Fit
                                       (Calibration.Fit,
                                        Fit_DOF (Calibration.Mode,
                                                 Calibration.DOF))
                            and then (if Calibration.Kind = Kind_Checkerboard
                                      then Corners_Inside (Calibration))
                            and then
                              (if Calibration.Mode
                                    = Mode_Perspective_And_Radial_Warp
                               then Valid_Model (Calibration.Model)
                                    and then Count_Of (Calibration)
                                               >= Min_Warp_Points
                                    and then Calibration_Image /= null
                                    and then Calibration.Model.Image_Width
                                               = Calibration_Image.Width
                                    and then Calibration.Model.Image_Height
                                               = Calibration_Image.Height)
                       elsif Calibration /= null
                         and then Valid_Calibration (Calibration)
                       then Calibration.Calibrated = False_Value)
             and then (if Valid_Calibration (Calibration)
                         and then Calibration.Kind = Kind_N_Point_To_N_Point
                         and then Calibration.Mode
                                    = Mode_Perspective_And_Radial_Warp
                         and then Count_Of (Calibration) < Min_Warp_Points
                       then Status.Failure = Failure_Bad_Parameter);
   --  Calibrate. An N-point calibration in the linear mode fits its pairs
   --  (the image and the transform are not used; pass null and the
   --  identity). In PerspectiveAndRadialWarp mode it fits the nonlinear
   --  model to its pairs (see above): Bad_Parameter for fewer than
   --  Min_Warp_Points pairs (before anything else is checked: Gold) or
   --  more than Max_Warp_Points ("Calibrate: PerspectiveAndRadialWarp
   --  needs at least 8 point pairs", ...), then as for a checkerboard
   --  Image_No_Pixels for a null Calibration_Image and Bad_Parameter for
   --  an inconsistent image or a transform beyond the bounds; then
   --  Bad_Parameter when Selected_From_Pixel has no inverse within the
   --  bounds, for an uncalibrated point off the image ("Calibrate: an
   --  uncalibrated point lies outside CalibrationImage
   --  (PerspectiveAndRadialWarp)"), for degenerate points and for
   --  transforms beyond the bounds. It stores the model, the output's
   --  transform as for a checkerboard (with tiles of size 1) and the
   --  image's size (Gold: the model has it). A checkerboard
   --  calibration finds the corners in Calibration_Image (Image_No_Pixels
   --  for null: "CalibrationImage has no pixels"), maps their pixel
   --  positions to the image's selected space with Selected_From_Pixel
   --  (the uncalibrated points; it must be within the bounds of
   --  AMV.Kernels.Transforms), gives them the raw calibrated points
   --  (I * PhysicalTileSizeX, J * PhysicalTileSizeY) and fits the
   --  transform; Bad_Parameter ("CalibrationImage: fewer than 9
   --  checkerboard corners were found") when it finds fewer than
   --  Min_Corners corners. In PerspectiveAndRadialWarp mode it fits the
   --  nonlinear model to the corners' pixel positions instead (see above;
   --  Bad_Parameter for degenerate corners, tile sizes more than
   --  Max_Tile_Aspect apart and transforms beyond the bounds) and stores
   --  the output's UncalibratedFromCalibrated transform, Selected_From_
   --  Pixel composed with the model's Output_Pixel_From_Calibrated, with
   --  its decomposition and the model's RMS error. A failed call leaves
   --  the calibration uncalibrated (and a checkerboard calibration without
   --  corners; an N-point calibration keeps its pairs).

   procedure Calibration_Calibrated
     (Calibration : access constant Ks_Calibration_Data;
      Result      : out Int32;
      Status      : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_calibration_calibrated",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Result in False_Value | True_Value;
   --  Calibrated (False_Value for null).

   procedure Calibration_Uncalibrate
     (Calibration : Ks_Calibration;
      Status      : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_calibration_uncalibrate",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status) and then Calibration /= null
                       then Valid_Calibration (Calibration)
                            and then Calibration.Calibrated = False_Value);
   --  Uncalibrate (a checkerboard calibration also forgets its corners).
   --  Nothing for null.

   procedure Calibration_Computed_Fit
     (Calibration : access constant Ks_Calibration_Data;
      Fit         : out Ks_N_Point_To_N_Point_Fit;
      Status      : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_calibration_computed_fit",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Operator_Not_Trained
             and then (if Succeeded (Status)
                       then Valid_Calibration (Calibration)
                            and then Gold_Fit
                                       (Fit, Fit_DOF (Calibration.Mode,
                                                      Calibration.DOF)));
   --  GetComputedUncalibratedFromRawCalibratedTransform (the transform F,
   --  which the origin adjustment does not change; with the default
   --  adjustment it is also GetComputedUncalibratedFromCalibrated-
   --  Transform) and ComputedRMSError. Operator_Not_Trained for a
   --  calibration that is not calibrated, Bad_Parameter for null. In
   --  PerspectiveAndRadialWarp mode: the linear transform of the warped
   --  output (see Calibration_Calibrate) and the model's RMS error in
   --  pixels.

   procedure Calibration_Get_Corner
     (Calibration      : access constant Ks_Calibration_Data;
      Index            : Int32;
      Pixel_X, Pixel_Y : out Long_Float;
      Grid_I, Grid_J   : out Int32;
      Status           : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_calibration_get_corner",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then (if Succeeded (Status)
                       then Valid_Calibration (Calibration)
                            and then Pixel_X >= 0.0
                            and then Pixel_X
                                       <= Long_Float
                                            (Calibration.Image_Width - 1)
                            and then Pixel_Y >= 0.0
                            and then Pixel_Y
                                       <= Long_Float
                                            (Calibration.Image_Height - 1)
                            and then Grid_I in Grid_Index
                            and then Grid_J in Grid_Index
                       else Pixel_X = 0.0 and then Pixel_Y = 0.0
                            and then Grid_I = 0 and then Grid_J = 0);
   --  (AMV name) Corner Index of a checkerboard calibration: its position
   --  in pixel space (inside the calibration image; a stored corner that
   --  is not gives Bad_Parameter) and its grid indices (the raw calibrated
   --  point is (Grid_I * PhysicalTileSizeX, Grid_J * PhysicalTileSizeY)).

   procedure Calibration_Corner_Image_Size
     (Calibration   : access constant Ks_Calibration_Data;
      Width, Height : out Int32;
      Status        : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_calibration_corner_image_size",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Width >= 0 and then Height >= 0;
   --  (AMV name) The size of the image a checkerboard calibration found
   --  its corners in (0 x 0 without corners and for an N-point
   --  calibration).

   ---------------------------------------------------------------------
   --  The origin adjustment (CalibratedOriginX/Y, CalibratedOriginSpace,
   --  CalibratedXAxisRotation, CalibratedXAxisRotationSpace,
   --  SwapCalibratedHandedness)
   ---------------------------------------------------------------------

   procedure Calibration_Adjustment_Default
     (Adjustment : out Ks_Calibration_Adjustment;
      Status     : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_calibration_adjustment_default",
     Post => Valid (Status) and then Succeeded (Status)
             and then Adjustment = Default_Adjustment
             and then Valid_Adjustment (Adjustment)
             and then Is_Identity_Adjustment (Adjustment);
   --  The defaults (AMV's): RawCalibrated, 0, 0, RawCalibrated, 0, not
   --  swapped. Never fails.

   procedure Calibration_Get_Adjustment
     (Calibration : access constant Ks_Calibration_Data;
      Adjustment  : out Ks_Calibration_Adjustment;
      Status      : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_calibration_get_adjustment",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Succeeded (Status) = Valid_Calibration (Calibration)
             and then Adjustment = Adjustment_Of (Calibration)
             and then Valid_Adjustment (Adjustment);
   --  The origin adjustment of the calibration (Bad_Parameter, and the
   --  defaults, for null).

   procedure Calibration_Set_Adjustment
     (Calibration : Ks_Calibration;
      Adjustment  : Ks_Calibration_Adjustment;
      Status      : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_calibration_set_adjustment",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Is_Calibrated (Calibration)
                        = Is_Calibrated (Calibration)'Old
             and then Fit_Of (Calibration) = Fit_Of (Calibration)'Old
             and then Count_Of (Calibration) = Count_Of (Calibration)'Old
             and then
               (if Succeeded (Status)
                then Valid_Calibration (Calibration)
                     and then Calibration.Adjustment.Calibrated_Origin_X
                                = Adjustment.Calibrated_Origin_X
                     and then Calibration.Adjustment.Calibrated_Origin_Y
                                = Adjustment.Calibrated_Origin_Y
                     and then Calibration.Adjustment.Calibrated_Origin_Space
                                = Adjustment.Calibrated_Origin_Space
                     and then Calibration.Adjustment
                                .Calibrated_X_Axis_Rotation_Space
                                = Adjustment.Calibrated_X_Axis_Rotation_Space
                     and then Calibration.Adjustment
                                .Swap_Calibrated_Handedness
                                = Adjustment.Swap_Calibrated_Handedness
                     and then
                       (if Adjustment.Calibrated_X_Axis_Rotation > -Pi
                          and then Adjustment.Calibrated_X_Axis_Rotation
                                     <= Pi
                        then Calibration.Adjustment.Calibrated_X_Axis_Rotation
                               = Adjustment.Calibrated_X_Axis_Rotation)
                else Adjustment_Of (Calibration)
                       = Adjustment_Of (Calibration)'Old);
   --  Sets the origin adjustment. It does not uncalibrate: the fit, the
   --  points and the calibrated state stay as they are. Bad_Parameter
   --  (nothing changed) for null and for a value out of range:
   --  "CalibratedOriginSpace must be 0 (RawCalibrated) or 1
   --  (Uncalibrated)", the same for CalibratedXAxisRotationSpace,
   --  "SwapCalibratedHandedness must be 0 or 1", "CalibratedOriginX must
   --  be finite and within +/-1.0E150" (Y the same), "CalibratedXAxis-
   --  Rotation must be finite". The rotation is stored reduced to
   --  (-Pi, Pi] (unchanged when it lies there).

   procedure Calibration_Computed_Uncalibrated_From_Calibrated
     (Calibration : access constant Ks_Calibration_Data;
      Transform   : out KT.Ks_Transform_2D_Linear;
      Status      : out Ks_Status)
   with
     Export, Convention => C,
     External_Name =>
       "ks_calibration_computed_uncalibrated_from_calibrated_transform",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Operator_Not_Trained
             and then (if Is_Calibrated (Calibration)
                         and then Is_Identity_Adjustment
                                    (Adjustment_Of (Calibration))
                       then Succeeded (Status)
                            and then KT."=" (Transform,
                                             Fit_Of (Calibration).Transform))
             and then (if Succeeded (Status)
                       then Is_Calibrated (Calibration)
                            and then KT.Bounded (Transform)
                            and then Det_Of (Transform) /= 0.0
                            and then
                              (if Calibration.Mode
                                    = Mode_Perspective_And_Radial_Warp
                               then In_Raw_Calibrated_Space
                                      (Calibration.Adjustment))
                       else KT."=" (Transform, (others => <>)));
   --  GetComputedUncalibratedFromCalibratedTransform: F * R (see above),
   --  exactly F with the default adjustment. Operator_Not_Trained for a
   --  calibration that is not calibrated, Bad_Parameter for null, for an
   --  Uncalibrated adjustment space in PerspectiveAndRadialWarp mode
   --  ("CalibratedOriginSpace and CalibratedXAxisRotationSpace must be
   --  RawCalibrated in ComputationMode PerspectiveAndRadialWarp") and when
   --  a transform leaves the bounds (see above). Transform is the identity
   --  when the call fails.

   ---------------------------------------------------------------------
   --  The calibration tools (CogCalibNPointToNPointTool and
   --  CogCalibCheckerboardTool)
   ---------------------------------------------------------------------

   Default_N_Point_Calibration_Name : constant KC.Ks_Space_Name :=
     (Length => 19,
      Text   => ['N', '-', 'P', 'o', 'i', 'n', 't', ' ', 'C', 'a', 'l', 'i',
                 'b', 'r', 'a', 't', 'i', 'o', 'n', others => ASCII.NUL]);
   --  "N-Point Calibration", VisionPro's default.

   Default_Checkerboard_Calibration_Name : constant KC.Ks_Space_Name :=
     (Length => 24,
      Text   => ['C', 'h', 'e', 'c', 'k', 'e', 'r', 'b', 'o', 'a', 'r', 'd',
                 ' ', 'C', 'a', 'l', 'i', 'b', 'r', 'a', 't', 'i', 'o', 'n',
                 others => ASCII.NUL]);
   --  "Checkerboard Calibration", VisionPro's default.

   type Ks_Calibration_Run_Params is record
      Calibrated_Space_Name : KC.Ks_Space_Name :=
        Default_N_Point_Calibration_Name;
      Space_To_Output       : Int32 := Space_To_Output_New;
   end record
     with Convention => C;
   --  CogCalibNPointToNPointRunParams and CogCalibCheckerboardRunParams
   --  (C: ks_calibration_run_params): the name of the calibrated space (a
   --  valid space name component) and SpaceToOutput.

   procedure Calibration_Run_Params_Default
     (Kind   : Int32;
      Params : out Ks_Calibration_Run_Params;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_calibration_run_params_default",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter;
   --  The defaults of the tool of Kind (the name above for an N-point
   --  calibration, "Checkerboard Calibration" for a checkerboard).

   procedure Calibration_Tool_Execute
     (Input_Image     : access constant KI.Ks_Image_8_Grey_Data;
      Calibration     : access constant Ks_Calibration_Data;
      Params          : Ks_Calibration_Run_Params;
      Tree            : in out KC.Ks_Coordinate_Space_Tree;
      Selected        : in out KC.Ks_Space_Name;
      Pixel_From_Root : KT.Ks_Transform_2D_Linear;
      Status          : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_calibration_tool_execute",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter
                         | Failure_Operator_Not_Trained
                         | Failure_Image_Bad_Selected_Space_Name
                         | Failure_Transform_Singular | Failure_Other
             and then (if Succeeded (Status)
                       then Valid_Calibration (Calibration)
                            and then Calibration.Calibrated = True_Value
                            and then Calibration.Mode = Mode_Linear
                            and then KC.Valid_Tree (Tree)
                            and then KC.Fits (Selected));
   --  The run of CogCalibNPointToNPointTool and CogCalibCheckerboardTool
   --  in the linear mode: adds the calibrated space
   --  (Params.Calibrated_Space_Name) with the calibration's
   --  UncalibratedFromCalibrated transform F * R (with its origin
   --  adjustment, as ks_calibration_computed_uncalibrated_from_
   --  calibrated_transform gives it and fails), as ks_fixture_execute
   --  adds a fixtured space. Image_No_Pixels for a null Input_Image,
   --  Bad_Parameter for a null Calibration ("Calibration is null") and for
   --  one in PerspectiveAndRadialWarp mode, whose output image is a new
   --  image (ks_calibration_n_point_tool_execute,
   --  ks_calibration_checkerboard_tool_execute), Operator_Not_Trained for
   --  one that is not calibrated ("Calibration is not calibrated").

   ---------------------------------------------------------------------
   --  The computation mode and the nonlinear model
   ---------------------------------------------------------------------

   procedure Calibration_Computation_Mode
     (Calibration : access constant Ks_Calibration_Data;
      Mode        : out Int32;
      Status      : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_calibration_computation_mode",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Valid_Calibration (Calibration)
                            and then Mode = Calibration.Mode
                       else Mode = Mode_Linear);
   --  ComputationMode (Bad_Parameter for null).

   procedure Calibration_Set_Computation_Mode
     (Calibration : Ks_Calibration;
      Mode        : Int32;
      Status      : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_calibration_set_computation_mode",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Valid_Calibration (Calibration)
                            and then Calibration.Mode = Mode
                            and then Calibration.Calibrated = False_Value);
   --  Sets ComputationMode (a CogCalibFixComputationModeConstants value);
   --  uncalibrates. Bad_Parameter for null, for a code out of range
   --  ("ComputationMode must be a CogCalibFixComputationModeConstants
   --  value (1 .. 7)") and for the nonlinear members AMV does not
   --  implement ("ComputationMode LinescanWarp is not supported", ...).
   --  PerspectiveAndRadialWarp is taken by both kinds.

   procedure Calibration_Computed_Warp_Model
     (Calibration : access constant Ks_Calibration_Data;
      Model       : out Ks_Radial_Warp_Model;
      Status      : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_calibration_computed_warp_model",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Operator_Not_Trained
             and then (if Succeeded (Status) then Valid_Model (Model));
   --  (AMV name) The nonlinear model of a calibration calibrated in
   --  PerspectiveAndRadialWarp mode (Gold: Valid_Model). Bad_Parameter for
   --  null and for a calibration in the linear mode, Operator_Not_Trained
   --  for one that is not calibrated; Model is the default record then.

   procedure Calibration_Map_Output_Pixel
     (Calibration      : access constant Ks_Calibration_Data;
      Output_X         : Long_Float;
      Output_Y         : Long_Float;
      Input_X, Input_Y : out Long_Float;
      Inside           : out Int32;
      Status           : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_calibration_map_output_pixel",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Operator_Not_Trained
             and then Inside in False_Value | True_Value
             and then (if Succeeded (Status) and then Inside = True_Value
                       then abs Input_X <= 2.0 ** 38
                            and then abs Input_Y <= 2.0 ** 38
                       else Input_X = 0.0 and then Input_Y = 0.0);
   --  (AMV name; VisionPro's warp parameters give the nonlinear
   --  GetInputPixelFromOutputPixelTransform) The input pixel that the
   --  output pixel (Output_X, Output_Y) of the warped output image shows,
   --  with Inside = True_Value; Inside = False_Value (and 0, 0) when it
   --  shows no point of the model's range (it gets the unfilled value).
   --  The output pixel coordinates must be finite and within
   --  Max_Output_Coordinate (Bad_Parameter); Bad_Parameter for null and
   --  the linear mode, Operator_Not_Trained when not calibrated.

   procedure Calibration_Map_Input_Pixel
     (Calibration        : access constant Ks_Calibration_Data;
      Input_X            : Long_Float;
      Input_Y            : Long_Float;
      Output_X, Output_Y : out Long_Float;
      Inside             : out Int32;
      Status             : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_calibration_map_input_pixel",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Operator_Not_Trained
             and then Inside in False_Value | True_Value
             and then (if Succeeded (Status) and then Inside = True_Value
                       then abs Output_X <= Max_Output_Coordinate
                            and then abs Output_Y <= Max_Output_Coordinate
                       else Output_X = 0.0 and then Output_Y = 0.0);
   --  (AMV name) The inverse of Calibration_Map_Output_Pixel: the pixel of
   --  the warped output image that shows the input pixel (Input_X,
   --  Input_Y), with Inside = True_Value; Inside = False_Value (and 0, 0)
   --  when the input pixel lies beyond the model's valid radius or does
   --  not map to a grid point in front of the camera (Warp.
   --  Output_From_Input). Mapped on by the output's linear calibrated
   --  space, it gives the calibrated coordinates of a point measured in
   --  the distorted input. The input pixel coordinates must be finite and
   --  within Max_Output_Coordinate (Bad_Parameter); other failures as
   --  Calibration_Map_Output_Pixel.

   ---------------------------------------------------------------------
   --  The checkerboard calibration tool in every mode
   --  (CogCalibCheckerboardTool, run parameters
   --  CogCalibCheckerboardRunParams)
   ---------------------------------------------------------------------

   type Ks_Calibration_Checkerboard_Run_Params is record
      Calibrated_Space_Name      : KC.Ks_Space_Name :=
        Default_Checkerboard_Calibration_Name;
      Space_To_Output            : Int32 := Space_To_Output_New;
      Unfilled_Pel_Value         : Int32 := 0;
      Unfilled_Pel_Value_Enabled : Int32 := False_Value;
   end record
     with Convention => C;
   --  CogCalibCheckerboardRunParams (C:
   --  ks_calibration_checkerboard_run_params): the name of the calibrated
   --  space, SpaceToOutput, UnfilledPelValue (0 .. 255) and
   --  UnfilledPelValueEnabled (0 or 1). The value of an output pixel of
   --  the warp that shows no input pixel is UnfilledPelValue when
   --  UnfilledPelValueEnabled is 1, otherwise 0 (AMV's choice; the
   --  defaults 0 and 0 are AMV's too).

   procedure Calibration_Checkerboard_Run_Params_Default
     (Params : out Ks_Calibration_Checkerboard_Run_Params;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_calibration_checkerboard_run_params_default",
     Post => Valid (Status) and then Succeeded (Status);
   --  The defaults above. Never fails.

   procedure Calibration_Checkerboard_Tool_Execute
     (Input_Image     : access constant KI.Ks_Image_8_Grey_Data;
      Calibration     : access constant Ks_Calibration_Data;
      Params          : Ks_Calibration_Checkerboard_Run_Params;
      Tree            : in out KC.Ks_Coordinate_Space_Tree;
      Selected        : in out KC.Ks_Space_Name;
      Pixel_From_Root : KT.Ks_Transform_2D_Linear;
      Output          : out KI.Ks_Image_8_Grey;
      Status          : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_calibration_checkerboard_tool_execute",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter
                         | Failure_Operator_Not_Trained
                         | Failure_Image_Bad_Selected_Space_Name
                         | Failure_Transform_Singular
                         | Failure_Out_Of_Memory | Failure_Other
             and then (if Succeeded (Status)
                       then Valid_Calibration (Calibration)
                            and then Calibration.Calibrated = True_Value
                            and then KC.Valid_Tree (Tree)
                            and then KC.Fits (Selected)
                            and then
                              (if Calibration.Mode = Mode_Linear
                               then Output = null
                               else KI.Valid_Image (Input_Image)
                                    and then KI.Valid_Image (Output)
                                    and then Output.Width
                                               = Input_Image.Width
                                    and then Output.Height
                                               = Input_Image.Height
                                    and then In_Raw_Calibrated_Space
                                               (Calibration.Adjustment))
                       else Output = null);
   --  The run of CogCalibCheckerboardTool in every mode. The linear mode
   --  adds the calibrated space as ks_calibration_tool_execute does and
   --  returns no image (Output null: the output image shares the input's
   --  pixels). PerspectiveAndRadialWarp returns the warped image (Gold:
   --  the input's size, sampled only inside the input; the caller owns
   --  it) and adds the calibrated space with the calibration's
   --  UncalibratedFromCalibrated transform F * R, which is linear in the
   --  warped pixels. Failures as ks_calibration_tool_execute, and
   --  Bad_Parameter for RunParams.UnfilledPelValue out of 0 .. 255,
   --  RunParams.UnfilledPelValueEnabled not 0 or 1, and (warp) an input
   --  image whose size is not the calibration image's and an origin
   --  adjustment in the uncalibrated space (before anything is warped);
   --  Out_Of_Memory. The calibration may be of either kind (the N-point
   --  tool's entry point below calls this one).

   ---------------------------------------------------------------------
   --  The N-point calibration tool in every mode
   --  (CogCalibNPointToNPointTool, run parameters
   --  CogCalibNPointToNPointRunParams)
   ---------------------------------------------------------------------

   procedure Calibration_N_Point_Tool_Execute
     (Input_Image     : access constant KI.Ks_Image_8_Grey_Data;
      Calibration     : access constant Ks_Calibration_Data;
      Params          : Ks_Calibration_Run_Params;
      Tree            : in out KC.Ks_Coordinate_Space_Tree;
      Selected        : in out KC.Ks_Space_Name;
      Pixel_From_Root : KT.Ks_Transform_2D_Linear;
      Output          : out KI.Ks_Image_8_Grey;
      Status          : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_calibration_n_point_tool_execute",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter
                         | Failure_Operator_Not_Trained
                         | Failure_Image_Bad_Selected_Space_Name
                         | Failure_Transform_Singular
                         | Failure_Out_Of_Memory | Failure_Other
             and then (if Succeeded (Status)
                       then Valid_Calibration (Calibration)
                            and then Calibration.Calibrated = True_Value
                            and then KC.Valid_Tree (Tree)
                            and then KC.Fits (Selected)
                            and then
                              (if Calibration.Mode = Mode_Linear
                               then Output = null
                               else KI.Valid_Image (Input_Image)
                                    and then KI.Valid_Image (Output)
                                    and then Output.Width
                                               = Input_Image.Width
                                    and then Output.Height
                                               = Input_Image.Height
                                    and then In_Raw_Calibrated_Space
                                               (Calibration.Adjustment))
                       else Output = null);
   --  (AMV) The run of CogCalibNPointToNPointTool in every mode:
   --  ks_calibration_checkerboard_tool_execute with the name and
   --  SpaceToOutput of Params and the unfilled value 0 (VisionPro's
   --  N-point run parameters have no UnfilledPelValue). The linear mode
   --  adds the calibrated space as ks_calibration_tool_execute does and
   --  returns no image (Output null); PerspectiveAndRadialWarp returns
   --  the warped image (the caller owns it). Failures as
   --  ks_calibration_checkerboard_tool_execute.

   ---------------------------------------------------------------------
   --  For the Ada API only (not exported): streams
   ---------------------------------------------------------------------

   Pairs_Stream_Code         : constant Int32 := 16#4B50_5000#;
   Calibration_Stream_Code   : constant Int32 := 16#4B43_4C00#;
   Calibration_Stream_Code_1 : constant Int32 := 16#4B43_4C01#;
   Calibration_Stream_Code_2 : constant Int32 := 16#4B43_4C02#;
   --  "KPP" and "KCL" followed by the layout version: 0 for the point
   --  pairs and for a calibration in the linear mode (the layout before
   --  the computation modes), 1 for a calibration in another mode (the
   --  mode follows the header, the model the fit), 2 for a calibration
   --  with an origin adjustment other than the defaults (the mode and the
   --  adjustment follow the header, the model the fit in a mode other than
   --  the linear one). A calibration is written in the oldest layout that
   --  holds it (Stream_Code), so that the older layouts read back; they
   --  give the default adjustment.

   function Stream_Code
     (Mode       : Int32;
      Adjustment : Ks_Calibration_Adjustment) return Int32
   is (if not Is_Identity_Adjustment (Adjustment)
       then Calibration_Stream_Code_2
       elsif Mode = Mode_Linear then Calibration_Stream_Code
       else Calibration_Stream_Code_1);
   --  The layout a calibration of Mode and Adjustment is written in.

   function Stream_Has_Model (Code, Mode : Int32) return Boolean is
     (Code = Calibration_Stream_Code_1
      or else (Code = Calibration_Stream_Code_2 and then Mode /= Mode_Linear));
   --  A calibrated calibration in the layout Code and the mode Mode has
   --  its model after its fit.

   procedure Check_Pairs_Header
     (Code, Count : Int32;
      Status      : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Image_File
             and then (if Succeeded (Status)
                       then Code = Pairs_Stream_Code
                            and then Count in 0 .. Max_Pairs);
   --  Image_File unless Code is Pairs_Stream_Code and Count can be a
   --  number of pairs.

   procedure Check_Calibration_Header
     (Code, Kind, Expected_Kind, Count, Calibrated : Int32;
      Status                                     : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Image_File
             and then (if Succeeded (Status)
                       then Code in Calibration_Stream_Code
                                  | Calibration_Stream_Code_1
                                  | Calibration_Stream_Code_2
                            and then Kind = Expected_Kind
                            and then Count in 0 .. Max_Pairs
                            and then Calibrated in False_Value | True_Value);
   --  Image_File unless the header can be that of a calibration of
   --  Expected_Kind (in any layout).

   procedure Read_Pair
     (Pairs              : in out Ks_Point_Pairs;
      A_X, A_Y, B_X, B_Y : Long_Float;
      Status             : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_File
                         | Failure_Out_Of_Memory;
   --  Appends a pair read from a stream, as ks_point_pairs_add_point_pair
   --  does; a pair it rejects gives Image_File.

   procedure Restore_Settings
     (Calibration          : Ks_Calibration;
      DOF                  : Int32;
      Tile_Size_X          : Long_Float;
      Tile_Size_Y          : Long_Float;
      Status               : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Image_File;
   --  Sets the DOF (and, for a checkerboard calibration, the tile sizes)
   --  of a calibration being read; values out of range give Image_File.

   procedure Restore_Pair
     (Calibration        : Ks_Calibration;
      A_X, A_Y, B_X, B_Y : Long_Float;
      Status             : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_File
                         | Failure_Out_Of_Memory;
   --  Appends a pair read from a stream to an N-point calibration, as
   --  ks_calibration_add_point_pair does; a pair it rejects gives
   --  Image_File.

   procedure Restore_Corner
     (Calibration          : Ks_Calibration;
      Image_Width          : Int32;
      Image_Height         : Int32;
      Capacity             : Int32;
      Pixel_X, Pixel_Y     : Long_Float;
      Grid_I, Grid_J       : Int32;
      Uncalibrated_X       : Long_Float;
      Uncalibrated_Y       : Long_Float;
      Status               : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_File
                         | Failure_Out_Of_Memory;
   --  Appends a corner read from a stream to an uncalibrated checkerboard
   --  calibration (the first call makes room for Capacity corners and
   --  records the image size): the corner must lie inside the image, its
   --  grid indices within Max_Grid_Index and its point within Max_Value;
   --  the raw calibrated point is computed from the tile sizes. Image_File
   --  for anything out of place.

   procedure Restore_Fit
     (Calibration : Ks_Calibration;
      Fit         : Ks_N_Point_To_N_Point_Fit;
      Status      : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Image_File
             and then (if Succeeded (Status)
                       then Valid_Calibration (Calibration)
                            and then Calibration.Calibrated = True_Value);
   --  Marks a calibration in the linear mode read from a stream
   --  calibrated with Fit, after checking that it holds enough points and
   --  that Fit is valid and of its DOF's structure (Image_File
   --  otherwise).

   procedure Restore_Mode
     (Calibration : Ks_Calibration;
      Mode        : Int32;
      Status      : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Image_File;
   --  Sets the computation mode of a calibration being read, as
   --  ks_calibration_set_computation_mode does; a mode it rejects gives
   --  Image_File.

   procedure Restore_Adjustment
     (Calibration : Ks_Calibration;
      Adjustment  : Ks_Calibration_Adjustment;
      Status      : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Image_File
             and then (if Succeeded (Status)
                       then Valid_Calibration (Calibration)
                            and then Calibration.Adjustment = Adjustment);
   --  Sets the origin adjustment of a calibration being read. Image_File
   --  unless the adjustment is one a calibration stores (Valid_Adjustment:
   --  the rotation already reduced to (-Pi, Pi]) and the handle is
   --  consistent.

   procedure Restore_Model
     (Calibration : Ks_Calibration;
      Fit         : Ks_N_Point_To_N_Point_Fit;
      Model       : Ks_Radial_Warp_Model;
      Status      : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Image_File
             and then (if Succeeded (Status)
                       then Valid_Calibration (Calibration)
                            and then Calibration.Calibrated = True_Value);
   --  Marks a calibration in PerspectiveAndRadialWarp mode read from a
   --  stream (a checkerboard with its corners, an N-point calibration
   --  with at least Min_Warp_Points pairs) calibrated with Fit and Model,
   --  after checking that Fit is valid, that Model is (Valid_Model) and
   --  belongs to the corners' image (a checkerboard; an N-point
   --  calibration takes the model's image size), and that its centre,
   --  normaliser and valid radius are those the fit computes for that
   --  image and those coefficients (Image_File otherwise).

end AMV.Kernels.Calib_Fix;
