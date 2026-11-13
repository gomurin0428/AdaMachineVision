--  The fixture tools and the calibrations: the counterparts of
--  Cognex.VisionPro.CalibFix (CogNPointToNPoint, CogFixture and
--  CogFixtureTool, CogFixtureNPointToNPoint with its result and tool,
--  CogCalibNPointToNPoint with its run parameters and tool,
--  CogCalibCheckerboard with its run parameters and tool).
--
--     Fixture.Run_Params.Unfixtured_From_Fixtured_Transform := Pose;
--     Fixture.Input_Image := Image;
--     Fixture.Run;
--     Out := Fixture.Output_Image;  --  the same pixels, "@\Fixture" selected
--
--     Calib.Calibration.Set_Calibration_Image (Plate_Image);
--     Calib.Calibration.Set_Physical_Tile_Size_X (5.0);  --  mm
--     Calib.Calibration.Set_Physical_Tile_Size_Y (5.0);
--     Calib.Calibration.Calibrate;
--     Calib.Input_Image := Image;
--     Calib.Run;                    --  millimetres in the selected space
--
--  The fits. A transform from point pairs (group A from group B:
--  unfixtured from fixtured, uncalibrated from calibrated) is fitted by
--  least squares with the degrees of freedom of a
--  Ks_N_Point_To_N_Point_DOF_Constants value: none (the identity), a
--  translation along x, y or both, a rotation and translation (unit
--  scale), a similarity, a rotation with independent scalings along the
--  two axes (no skew) or the general affine transform. Closed forms
--  throughout (AMV.Kernels.Calib_Fix describes them); each DOF needs a
--  minimum number of pairs (0, 1, 1, 1, 2, 2, 3, 3) and points that
--  determine it (Ks_Bad_Parameter_Exception otherwise: VisionPro raises
--  CogCalibFixNPointTooFewPointsException and
--  CogCalibFixNPointUnstableException there).
--
--  Output images. A fixture or calibration tool's output image shares the
--  input's pixels (assignment) and gets the input's coordinate space tree
--  with the new space added as a child of the input's selected space,
--  with Parent_From_New = the transform from the new space into the
--  selected space (UnfixturedFromFixtured, UncalibratedFromCalibrated),
--  passed unchanged as AMV.Coordinate_Spaces.Add_Space takes it. With
--  Space_To_Output Fixtured_Space / Calibrated_Space (the default) the new
--  space is selected, otherwise the input's selection stays. A space of
--  the same name is replaced (its descendants stay); with Enhanced
--  duplicate handling it makes the run fail instead (AMV does not record
--  which tool added a space, so it cannot allow the same tool's space as
--  VisionPro does). When the input's selected space is "#" (pixel space,
--  not a space of the tree), the new space is added under "@" with
--  Get_Transform ("@", "#") composed with the transform, so that it still
--  means "the given transform from pixel space"; the same rule holds for
--  every tool here.
--
--  Calibrations are trained objects: changing any input (points, DOF,
--  tile sizes, the computation mode, the calibration image; not the
--  origin adjustment, below) uncalibrates; a tool whose
--  calibration is not calibrated fails with
--  Ks_Operator_Not_Trained_Exception. Their stream attributes store the
--  inputs and the computed state by value (a read checks every value,
--  raises Ks_Image_File_Exception for malformed data, a stream that ends
--  early included, and leaves the target as it was then). The uncalibrated
--  space of a calibration is the selected space of the image it is
--  measured in (the checkerboard's corners are mapped into the selected
--  space of the calibration image). The nonlinear computation modes
--  other than Perspective_And_Radial_Warp, fiducials and the other
--  feature finders are not implemented.
--
--  The origin adjustment. The fit maps raw calibrated coordinates (the
--  raw calibrated points, or the board's tile grid) to the uncalibrated
--  space; the calibrated space is the raw calibrated space moved rigidly,
--  so that its origin and its x axis lie where the properties put them:
--
--     Calib.Calibration.Set_Calibrated_Origin_Space (Uncalibrated);
--     Calib.Calibration.Set_Calibrated_Origin_X (412.0);  --  a pixel
--     Calib.Calibration.Set_Calibrated_Origin_Y (305.0);
--     Calib.Calibration.Set_Calibrated_X_Axis_Rotation_Space (Uncalibrated);
--     Calib.Calibration.Set_Calibrated_X_Axis_Rotation (0.0);  --  along +x
--     Calib.Run;   --  the pixel (412, 305) is (0, 0) in millimetres
--
--  Calibrated_Origin_X/Y is the calibrated origin, a raw calibrated point
--  (Raw_Calibrated, the default) or a point of the uncalibrated space
--  (Uncalibrated); Calibrated_X_Axis_Rotation (radians) is the direction
--  of the calibrated x axis, against the raw calibrated x axis
--  (Raw_Calibrated) or as seen in the uncalibrated space (Uncalibrated);
--  Swap_Calibrated_Handedness turns the calibrated y axis the other way.
--  The calibrated units are the raw calibrated ones. The defaults (AMV's:
--  Raw_Calibrated, 0, 0, Raw_Calibrated, 0, False) keep the raw
--  calibrated space. The adjustment does not change the fit: setting it
--  does not uncalibrate, the transform from raw calibrated coordinates
--  stays the fit, and the transform from calibrated coordinates and the
--  tools use the adjustment as it is when they are called. With
--  Perspective_And_Radial_Warp only Raw_Calibrated is supported
--  (Ks_Bad_Parameter_Exception there otherwise). AMV.Kernels.Calib_Fix
--  gives the formulas.
--
--  Lens distortion. A checkerboard calibration in the computation mode
--  Perspective_And_Radial_Warp fits a model of perspective (a homography
--  of the plate) and radial lens distortion (two coefficients about the
--  image centre) to the corners, and its tool outputs a new image, the
--  input resampled so that the plate is seen undistorted and without
--  perspective, whose calibrated space is linear:
--
--     Calib.Calibration.Set_Computation_Mode (Perspective_And_Radial_Warp);
--     Calib.Calibration.Calibrate;
--     Calib.Input_Image := Image;   --  the calibration image's size
--     Calib.Run;                    --  Output_Image: the corrected image
--
--  An N-point calibration does the same with its own target: arbitrary
--  plate points, not a grid. Its raw calibrated points are the plate, its
--  uncalibrated points their positions in the calibration image's
--  selected space; the mode needs that image at Calibrate (its size fixes
--  the model, an AMV addition: VisionPro's CogCalibNPointToNPoint has no
--  calibration image), at least 8 point pairs and every uncalibrated
--  point on the image:
--
--     Calib.Calibration.Set_Computation_Mode (Perspective_And_Radial_Warp);
--     Calib.Calibration.Calibrate (Plate_Image);
--     Calib.Input_Image := Image;   --  the plate image's size
--     Calib.Run;                    --  Output_Image: the corrected image
--
--  AMV.Kernels.Calib_Fix describes the model, its estimate and the warp.
--
--  The work is done by the SPARK kernel AMV.Kernels.Calib_Fix (C API:
--  include/amv_calib_fix.h). Proved there, besides the absence of
--  run-time errors: the minimum point count of each DOF is checked before
--  fitting; every fitted transform is within the bounds of AMV.Transforms,
--  has a non-zero determinant (and an inverse within the bounds) and
--  exactly the structure of its DOF; RMS errors are >= 0; a checkerboard
--  calibration keeps 9 to 65536 corners, each inside its image; a
--  Perspective_And_Radial_Warp model has every parameter finite and
--  within its documented bound and the size of the calibration image (an
--  N-point calibration in that mode has at least 8 pairs), and its
--  warped output image has the input's size and is sampled only inside
--  the input.
--
--  Input images are 8-bit grey images (VisionPro takes any ICogImage).

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with Ada.Strings.Unbounded;

with AMV.Images;
with AMV.Kernels.Calib_Fix;
with AMV.Tools;
with AMV.Transforms;

private with Ada.Finalization;
private with Ada.Streams;
private with AMV.Kernels;

package AMV.Calib_Fix is

   ---------------------------------------------------------------------
   --  Enumerations
   ---------------------------------------------------------------------

   type Ks_N_Point_To_N_Point_DOF_Constants is
     (None,
      Translation_X,
      Translation_Y,
      Translation,
      Rotation_And_Translation,
      Scaling_Rotation_And_Translation,
      Scaling_Aspect_Rotation_And_Translation,
      Scaling_Aspect_Rotation_Skew_And_Translation);
   --  CogNPointToNPointDOFConstants; the positions are VisionPro's values.

   subtype Ks_Calib_Checkerboard_DOF_Constants is
     Ks_N_Point_To_N_Point_DOF_Constants;
   --  CogCalibCheckerboardDOFConstants has the same members and values.

   type Ks_Fixture_Space_To_Output_Constants is
     (Fixtured_Space, Unfixtured_Space);
   --  CogFixtureSpaceToOutputConstants (VisionPro's values).

   type Ks_Calib_Space_To_Output_Constants is
     (Calibrated_Space, Uncalibrated_Space);
   --  CogCalibSpaceToOutputConstants (VisionPro's values).

   type Ks_Calib_Fix_Computation_Mode_Constants is
     (Linear,
      Perspective_And_Radial_Warp,
      Linescan_Warp,
      Linescan_2D_Warp,
      Sine_Tan_Law_Projection_Warp,
      Three_Param_Radial_Warp,
      No_Distortion_Warp);
   for Ks_Calib_Fix_Computation_Mode_Constants use
     (Linear                       => 1,
      Perspective_And_Radial_Warp  => 2,
      Linescan_Warp                => 3,
      Linescan_2D_Warp             => 4,
      Sine_Tan_Law_Projection_Warp => 5,
      Three_Param_Radial_Warp      => 6,
      No_Distortion_Warp           => 7);
   --  CogCalibFixComputationModeConstants (VisionPro's values). AMV
   --  implements Linear and Perspective_And_Radial_Warp (both kinds of
   --  calibration); the others raise Ks_Bad_Parameter_Exception.

   type Ks_Calib_N_Point_Adjustment_Space_Constants is
     (Raw_Calibrated, Uncalibrated);
   --  CogCalibNPointAdjustmentSpaceConstants: the space the calibrated
   --  origin and the x axis rotation are given in (the positions are
   --  VisionPro's values).

   subtype Ks_Calib_Checkerboard_Adjustment_Space_Constants is
     Ks_Calib_N_Point_Adjustment_Space_Constants;
   --  CogCalibCheckerboardAdjustmentSpaceConstants has the same members and
   --  values.

   type Ks_Fixtured_Space_Name_Duplicate_Handling_Constants is
     (Compatibility, Enhanced);
   for Ks_Fixtured_Space_Name_Duplicate_Handling_Constants use
     (Compatibility => 1, Enhanced => 2);
   --  CogFixturedSpaceNameDuplicateHandlingConstants (VisionPro's values):
   --  Compatibility replaces an existing space; Enhanced makes the run
   --  fail (Ks_Bad_Parameter_Exception) when the space exists already.

   ---------------------------------------------------------------------
   --  CogNPointToNPoint
   ---------------------------------------------------------------------

   type Ks_N_Point_To_N_Point is tagged private;
   --  Point pairs (group A, group B) and DOFsToCompute. Default: no pairs,
   --  Scaling_Aspect_Rotation_Skew_And_Translation (VisionPro's default).
   --  Copies are independent.

   function Num_Points (Params : Ks_N_Point_To_N_Point) return Natural;

   procedure Add_Point_Pair
     (Params               : in out Ks_N_Point_To_N_Point;
      Group_A_X, Group_A_Y : Real;
      Group_B_X, Group_B_Y : Real);
   --  AddPointPair: appends a pair (coordinates within 1.0E150; at most
   --  524288 pairs; Ks_Bad_Parameter_Exception otherwise).

   procedure Delete_Point_Pair
     (Params : in out Ks_N_Point_To_N_Point;
      Index  : Natural);
   --  DeletePointPair: removes pair Index (0-based; Constraint_Error
   --  outside 0 .. Num_Points - 1); the later pairs move down.

   procedure Get_Group_A_Point
     (Params : Ks_N_Point_To_N_Point;
      Index  : Natural;
      X, Y   : out Real);
   function Get_Group_A_Point_X
     (Params : Ks_N_Point_To_N_Point; Index : Natural) return Real;
   function Get_Group_A_Point_Y
     (Params : Ks_N_Point_To_N_Point; Index : Natural) return Real;
   procedure Set_Group_A_Point
     (Params : in out Ks_N_Point_To_N_Point;
      Index  : Natural;
      X, Y   : Real);
   procedure Get_Group_B_Point
     (Params : Ks_N_Point_To_N_Point;
      Index  : Natural;
      X, Y   : out Real);
   function Get_Group_B_Point_X
     (Params : Ks_N_Point_To_N_Point; Index : Natural) return Real;
   function Get_Group_B_Point_Y
     (Params : Ks_N_Point_To_N_Point; Index : Natural) return Real;
   procedure Set_Group_B_Point
     (Params : in out Ks_N_Point_To_N_Point;
      Index  : Natural;
      X, Y   : Real);
   --  The points of pair Index (Constraint_Error outside 0 .. Num_Points -
   --  1).

   function DOFs_To_Compute
     (Params : Ks_N_Point_To_N_Point)
      return Ks_N_Point_To_N_Point_DOF_Constants;
   procedure Set_DOFs_To_Compute
     (Params : in out Ks_N_Point_To_N_Point;
      Value  : Ks_N_Point_To_N_Point_DOF_Constants);

   function Compute_Group_A_From_Group_B_Transform
     (Params    : Ks_N_Point_To_N_Point;
      RMS_Error : out Real) return AMV.Transforms.Ks_Transform_2D_Linear;
   function Compute_Group_A_From_Group_B_Transform
     (Params : Ks_N_Point_To_N_Point)
      return AMV.Transforms.Ks_Transform_2D_Linear;
   --  ComputeGroupAFromGroupBTransform (out rmsError; the second form
   --  leaves the RMS error out): the least squares transform of
   --  DOFsToCompute that maps the group B points onto the group A points,
   --  and the RMS of the distances |T (B) - A| (group A units).
   --  Ks_Bad_Parameter_Exception for too few or degenerate points.

   ---------------------------------------------------------------------
   --  CogFixture and CogFixtureTool
   ---------------------------------------------------------------------

   type Ks_Fixture is record
      Unfixtured_From_Fixtured_Transform     :
        AMV.Transforms.Ks_Transform_2D_Linear;
      Fixtured_Space_Name                    :
        Ada.Strings.Unbounded.Unbounded_String :=
          Ada.Strings.Unbounded.To_Unbounded_String ("Fixture");
      Space_To_Output                        :
        Ks_Fixture_Space_To_Output_Constants := Fixtured_Space;
      Fixtured_Space_Name_Duplicate_Handling :
        Ks_Fixtured_Space_Name_Duplicate_Handling_Constants := Compatibility;
   end record;
   --  CogFixture: the transform from the fixtured space into the input's
   --  selected space (the identity by default), the fixtured space's name
   --  (a path component: not empty, no '\', not "@", "#" or "."; "Fixture"
   --  is an AMV default) and the codes above. A public record (the run
   --  parameters of the other tools are the kernel's C records; a name and
   --  a transform are easier to set here as an Unbounded_String and an
   --  AMV.Transforms object).

   function Execute
     (Params      : Ks_Fixture;
      Input_Image : AMV.Images.Ks_Image_8_Grey)
      return AMV.Images.Ks_Image_8_Grey;
   --  CogFixture.Execute: the output image (see above). Raises
   --  Ks_Image_No_Pixels_Exception for an unallocated Input_Image,
   --  Ks_Bad_Parameter_Exception for a bad name or transform, a tree that
   --  is full, an existing space with Enhanced, and
   --  Ks_Transform_Singular_Exception for a singular transform.

   type Ks_Fixture_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image  : AMV.Images.Ks_Image_8_Grey;
      Run_Params   : Ks_Fixture;
      Output_Image : AMV.Images.Ks_Image_8_Grey;
      --  Set by Run; unallocated after a run that failed.
   end record;
   --  CogFixtureTool.

   overriding procedure Execute (Tool : in out Ks_Fixture_Tool);
   overriding procedure Reset_Results (Tool : in out Ks_Fixture_Tool);

   ---------------------------------------------------------------------
   --  CogFixtureNPointToNPoint, its result and its tool
   ---------------------------------------------------------------------

   type Ks_Fixture_N_Point_To_N_Point is tagged private;
   --  Point pairs (unfixtured, raw fixtured), DOFsToCompute
   --  (Rotation_And_Translation), FixturedSpaceName ("N-Point Fixture"),
   --  SpaceToOutput and FixturedSpaceNameDuplicateHandling, with
   --  VisionPro's defaults. Copies are independent.

   function Num_Points (Params : Ks_Fixture_N_Point_To_N_Point) return Natural;

   procedure Add_Point_Pair
     (Params                       : in out Ks_Fixture_N_Point_To_N_Point;
      Unfixtured_X, Unfixtured_Y   : Real;
      Raw_Fixtured_X, Raw_Fixtured_Y : Real);
   procedure Delete_Point_Pair
     (Params : in out Ks_Fixture_N_Point_To_N_Point;
      Index  : Natural);
   procedure Get_Unfixtured_Point
     (Params : Ks_Fixture_N_Point_To_N_Point;
      Index  : Natural;
      X, Y   : out Real);
   function Get_Unfixtured_Point_X
     (Params : Ks_Fixture_N_Point_To_N_Point; Index : Natural) return Real;
   function Get_Unfixtured_Point_Y
     (Params : Ks_Fixture_N_Point_To_N_Point; Index : Natural) return Real;
   procedure Set_Unfixtured_Point
     (Params : in out Ks_Fixture_N_Point_To_N_Point;
      Index  : Natural;
      X, Y   : Real);
   procedure Get_Raw_Fixtured_Point
     (Params : Ks_Fixture_N_Point_To_N_Point;
      Index  : Natural;
      X, Y   : out Real);
   function Get_Raw_Fixtured_Point_X
     (Params : Ks_Fixture_N_Point_To_N_Point; Index : Natural) return Real;
   function Get_Raw_Fixtured_Point_Y
     (Params : Ks_Fixture_N_Point_To_N_Point; Index : Natural) return Real;
   procedure Set_Raw_Fixtured_Point
     (Params : in out Ks_Fixture_N_Point_To_N_Point;
      Index  : Natural;
      X, Y   : Real);
   --  As for Ks_N_Point_To_N_Point.

   function DOFs_To_Compute
     (Params : Ks_Fixture_N_Point_To_N_Point)
      return Ks_N_Point_To_N_Point_DOF_Constants;
   procedure Set_DOFs_To_Compute
     (Params : in out Ks_Fixture_N_Point_To_N_Point;
      Value  : Ks_N_Point_To_N_Point_DOF_Constants);
   function Fixtured_Space_Name
     (Params : Ks_Fixture_N_Point_To_N_Point) return String;
   procedure Set_Fixtured_Space_Name
     (Params : in out Ks_Fixture_N_Point_To_N_Point;
      Value  : String);
   function Space_To_Output
     (Params : Ks_Fixture_N_Point_To_N_Point)
      return Ks_Fixture_Space_To_Output_Constants;
   procedure Set_Space_To_Output
     (Params : in out Ks_Fixture_N_Point_To_N_Point;
      Value  : Ks_Fixture_Space_To_Output_Constants);
   function Fixtured_Space_Name_Duplicate_Handling
     (Params : Ks_Fixture_N_Point_To_N_Point)
      return Ks_Fixtured_Space_Name_Duplicate_Handling_Constants;
   procedure Set_Fixtured_Space_Name_Duplicate_Handling
     (Params : in out Ks_Fixture_N_Point_To_N_Point;
      Value  : Ks_Fixtured_Space_Name_Duplicate_Handling_Constants);
   --  The name is checked when the fixture runs.

   type Ks_Fixture_N_Point_To_N_Point_Result is tagged private;
   --  CogFixtureNPointToNPointResult. Empty before a run: an unallocated
   --  image, RMS_Error 0, the identity.

   function Output_Image
     (Result : Ks_Fixture_N_Point_To_N_Point_Result)
      return AMV.Images.Ks_Image_8_Grey;
   function RMS_Error
     (Result : Ks_Fixture_N_Point_To_N_Point_Result) return Real;
   function Get_Unfixtured_From_Fixtured_Transform
     (Result : Ks_Fixture_N_Point_To_N_Point_Result)
      return AMV.Transforms.Ks_Transform_2D_Linear;
   --  The output image, the RMS error of the fit (unfixtured units) and
   --  the fitted transform.

   function Execute
     (Params      : Ks_Fixture_N_Point_To_N_Point'Class;
      Input_Image : AMV.Images.Ks_Image_8_Grey)
      return Ks_Fixture_N_Point_To_N_Point_Result;
   --  CogFixtureNPointToNPoint.Execute: fits UnfixturedFromFixtured and
   --  fixtures the image with it (exceptions as for the fit and for
   --  Execute of a Ks_Fixture).

   type Ks_Fixture_N_Point_To_N_Point_Tool is new AMV.Tools.Ks_Tool with
   record
      Input_Image : AMV.Images.Ks_Image_8_Grey;
      Run_Params  : Ks_Fixture_N_Point_To_N_Point;
      Result      : Ks_Fixture_N_Point_To_N_Point_Result;
      --  Set by Run; empty after a run that failed.
   end record;
   --  CogFixtureNPointToNPointTool.

   overriding procedure Execute
     (Tool : in out Ks_Fixture_N_Point_To_N_Point_Tool);
   overriding procedure Reset_Results
     (Tool : in out Ks_Fixture_N_Point_To_N_Point_Tool);

   ---------------------------------------------------------------------
   --  CogCalibNPointToNPoint and its tool
   ---------------------------------------------------------------------

   type Ks_Calib_N_Point_To_N_Point is tagged private;
   --  Point pairs (uncalibrated, raw calibrated), DOFsToCompute
   --  (Scaling_Aspect_Rotation_Skew_And_Translation, an AMV default), the
   --  computation mode (Linear), the origin adjustment and the computed
   --  state. Copies are independent.

   function Num_Points (Calibration : Ks_Calib_N_Point_To_N_Point)
      return Natural;
   procedure Add_Point_Pair
     (Calibration                        : in out Ks_Calib_N_Point_To_N_Point;
      Uncalibrated_X, Uncalibrated_Y     : Real;
      Raw_Calibrated_X, Raw_Calibrated_Y : Real);
   procedure Delete_Point_Pair
     (Calibration : in out Ks_Calib_N_Point_To_N_Point;
      Index       : Natural);
   procedure Get_Uncalibrated_Point
     (Calibration : Ks_Calib_N_Point_To_N_Point;
      Index       : Natural;
      X, Y        : out Real);
   function Get_Uncalibrated_Point_X
     (Calibration : Ks_Calib_N_Point_To_N_Point; Index : Natural) return Real;
   function Get_Uncalibrated_Point_Y
     (Calibration : Ks_Calib_N_Point_To_N_Point; Index : Natural) return Real;
   procedure Set_Uncalibrated_Point
     (Calibration : in out Ks_Calib_N_Point_To_N_Point;
      Index       : Natural;
      X, Y        : Real);
   procedure Get_Raw_Calibrated_Point
     (Calibration : Ks_Calib_N_Point_To_N_Point;
      Index       : Natural;
      X, Y        : out Real);
   function Get_Raw_Calibrated_Point_X
     (Calibration : Ks_Calib_N_Point_To_N_Point; Index : Natural) return Real;
   function Get_Raw_Calibrated_Point_Y
     (Calibration : Ks_Calib_N_Point_To_N_Point; Index : Natural) return Real;
   procedure Set_Raw_Calibrated_Point
     (Calibration : in out Ks_Calib_N_Point_To_N_Point;
      Index       : Natural;
      X, Y        : Real);
   --  As for Ks_N_Point_To_N_Point; every change uncalibrates. The
   --  uncalibrated points are in the space the calibration will be used
   --  in (the input image's selected space when the tool runs).

   function DOFs_To_Compute
     (Calibration : Ks_Calib_N_Point_To_N_Point)
      return Ks_N_Point_To_N_Point_DOF_Constants;
   procedure Set_DOFs_To_Compute
     (Calibration : in out Ks_Calib_N_Point_To_N_Point;
      Value       : Ks_N_Point_To_N_Point_DOF_Constants);
   --  Setting it uncalibrates.

   function Computation_Mode (Calibration : Ks_Calib_N_Point_To_N_Point)
      return Ks_Calib_Fix_Computation_Mode_Constants;
   procedure Set_Computation_Mode
     (Calibration : in out Ks_Calib_N_Point_To_N_Point;
      Value       : Ks_Calib_Fix_Computation_Mode_Constants);
   --  ComputationMode: Linear (the default) or Perspective_And_Radial_Warp
   --  (the others raise Ks_Bad_Parameter_Exception); setting it
   --  uncalibrates. DOFsToCompute is not used by
   --  Perspective_And_Radial_Warp.

   procedure Calibrate (Calibration : in out Ks_Calib_N_Point_To_N_Point);
   --  Calibrate: fits UncalibratedFromCalibrated (Ks_Bad_Parameter_
   --  Exception for too few or degenerate points; the calibration is then
   --  not calibrated). Perspective_And_Radial_Warp needs the calibration
   --  image: this form raises Ks_Image_No_Pixels_Exception there.

   procedure Calibrate
     (Calibration       : in out Ks_Calib_N_Point_To_N_Point;
      Calibration_Image : AMV.Images.Ks_Image_8_Grey);
   --  (AMV addition) Calibrate with the image the points were measured in.
   --  The linear mode does not use it. Perspective_And_Radial_Warp fits
   --  the perspective and radial distortion model of the checkerboard
   --  (AMV.Kernels.Calib_Fix) to the pairs: the raw calibrated points are
   --  the plate points and the uncalibrated points, in the image's
   --  selected space, their positions; the image's size fixes the
   --  distortion centre and normaliser (and the size of the images the
   --  tool warps). Ks_Image_No_Pixels_Exception for an unallocated image;
   --  Ks_Bad_Parameter_Exception for fewer than 8 or more than 65536
   --  pairs, an uncalibrated point off the image (outside
   --  [-0.5, Width - 0.5] x [-0.5, Height - 0.5] in pixels), points that
   --  do not determine the model (all on one line, say) and a model beyond
   --  its bounds. The calibration is then not calibrated.

   function Calibrated (Calibration : Ks_Calib_N_Point_To_N_Point)
      return Boolean;
   procedure Uncalibrate (Calibration : in out Ks_Calib_N_Point_To_N_Point);

   function Get_Computed_Uncalibrated_From_Calibrated_Transform
     (Calibration : Ks_Calib_N_Point_To_N_Point)
      return AMV.Transforms.Ks_Transform_2D_Linear;
   function Get_Computed_Uncalibrated_From_Raw_Calibrated_Transform
     (Calibration : Ks_Calib_N_Point_To_N_Point)
      return AMV.Transforms.Ks_Transform_2D_Linear;
   function Computed_RMS_Error (Calibration : Ks_Calib_N_Point_To_N_Point)
      return Real;
   --  The computed transforms and the RMS error (uncalibrated units):
   --  uncalibrated from raw calibrated is the fit, uncalibrated from
   --  calibrated the fit with the origin adjustment below (the same with
   --  the defaults). Ks_Operator_Not_Trained_Exception when not
   --  calibrated; Ks_Bad_Parameter_Exception when the adjusted transform
   --  would exceed the bounds of AMV.Transforms (an origin far away, say).
   --  In Perspective_And_Radial_Warp mode, as for Ks_Calib_Checkerboard:
   --  the transforms of the warped output image (linear) and the RMS
   --  distance in pixels between the pairs and the model.

   function Calibrated_Origin_X (Calibration : Ks_Calib_N_Point_To_N_Point)
      return Real;
   procedure Set_Calibrated_Origin_X
     (Calibration : in out Ks_Calib_N_Point_To_N_Point;
      Value       : Real);
   function Calibrated_Origin_Y (Calibration : Ks_Calib_N_Point_To_N_Point)
      return Real;
   procedure Set_Calibrated_Origin_Y
     (Calibration : in out Ks_Calib_N_Point_To_N_Point;
      Value       : Real);
   function Calibrated_Origin_Space
     (Calibration : Ks_Calib_N_Point_To_N_Point)
      return Ks_Calib_N_Point_Adjustment_Space_Constants;
   procedure Set_Calibrated_Origin_Space
     (Calibration : in out Ks_Calib_N_Point_To_N_Point;
      Value       : Ks_Calib_N_Point_Adjustment_Space_Constants);
   function Calibrated_X_Axis_Rotation
     (Calibration : Ks_Calib_N_Point_To_N_Point) return Real;
   procedure Set_Calibrated_X_Axis_Rotation
     (Calibration : in out Ks_Calib_N_Point_To_N_Point;
      Value       : Real);
   function Calibrated_X_Axis_Rotation_Space
     (Calibration : Ks_Calib_N_Point_To_N_Point)
      return Ks_Calib_N_Point_Adjustment_Space_Constants;
   procedure Set_Calibrated_X_Axis_Rotation_Space
     (Calibration : in out Ks_Calib_N_Point_To_N_Point;
      Value       : Ks_Calib_N_Point_Adjustment_Space_Constants);
   function Swap_Calibrated_Handedness
     (Calibration : Ks_Calib_N_Point_To_N_Point) return Boolean;
   procedure Set_Swap_Calibrated_Handedness
     (Calibration : in out Ks_Calib_N_Point_To_N_Point;
      Value       : Boolean);
   --  The origin adjustment (see above; defaults 0.0, 0.0, Raw_Calibrated,
   --  0.0, Raw_Calibrated, False: AMV's). The setters keep the calibration
   --  calibrated. Ks_Bad_Parameter_Exception for an origin coordinate that
   --  is not finite or beyond 1.0E150 and a rotation that is not finite;
   --  the rotation reads back reduced to (-Pi, Pi].

   subtype Ks_Calib_N_Point_To_N_Point_Warp_Model is
     AMV.Kernels.Calib_Fix.Ks_Radial_Warp_Model;
   --  (AMV name) The fitted model of Perspective_And_Radial_Warp, as for
   --  Ks_Calib_Checkerboard_Warp_Model, its plate normalisation
   --  (Grid_Center_X, Grid_Center_Y, Grid_Scale) in raw calibrated units.

   function Get_Computed_Warp_Model
     (Calibration : Ks_Calib_N_Point_To_N_Point)
      return Ks_Calib_N_Point_To_N_Point_Warp_Model;
   function Get_Output_Pixel_From_Calibrated_Transform
     (Calibration : Ks_Calib_N_Point_To_N_Point)
      return AMV.Transforms.Ks_Transform_2D_Linear;
   procedure Map_Output_Pixel
     (Calibration      : Ks_Calib_N_Point_To_N_Point;
      Output_X         : Real;
      Output_Y         : Real;
      Input_X, Input_Y : out Real;
      Inside           : out Boolean);
   procedure Map_Input_Pixel
     (Calibration        : Ks_Calib_N_Point_To_N_Point;
      Input_X            : Real;
      Input_Y            : Real;
      Output_X, Output_Y : out Real;
      Inside             : out Boolean);
   --  (AMV names) As for Ks_Calib_Checkerboard: the model, the similarity
   --  from calibrated coordinates to the warped output's pixels, and the
   --  maps between output and input pixels (Ks_Operator_Not_Trained_
   --  Exception when not calibrated, Ks_Bad_Parameter_Exception in the
   --  linear mode and for coordinates beyond 2**32).

   type Ks_Calib_N_Point_To_N_Point_Run_Params is record
      Calibrated_Space_Name : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.To_Unbounded_String ("N-Point Calibration");
      Space_To_Output       : Ks_Calib_Space_To_Output_Constants :=
        Calibrated_Space;
   end record;
   --  CogCalibNPointToNPointRunParams, with VisionPro's defaults.

   type Ks_Calib_N_Point_To_N_Point_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image       : AMV.Images.Ks_Image_8_Grey;
      Calibration_Image : AMV.Images.Ks_Image_8_Grey;
      --  For display only, as in VisionPro; not used by Run (pass it to
      --  Calibration.Calibrate for Perspective_And_Radial_Warp).
      Calibration       : Ks_Calib_N_Point_To_N_Point;
      Run_Params        : Ks_Calib_N_Point_To_N_Point_Run_Params;
      Output_Image      : AMV.Images.Ks_Image_8_Grey;
      --  Set by Run; unallocated after a run that failed.
   end record;
   --  CogCalibNPointToNPointTool. Run fails with
   --  Ks_Operator_Not_Trained_Exception when Calibration is not
   --  calibrated. In Perspective_And_Radial_Warp mode the output image is
   --  a new image, the input warped as by Ks_Calib_Checkerboard_Tool (the
   --  input must have the calibration image's size), whose pixels that
   --  show no input pixel are 0 (VisionPro's run parameters of this tool
   --  have no UnfilledPelValue).

   overriding procedure Execute
     (Tool : in out Ks_Calib_N_Point_To_N_Point_Tool);
   overriding procedure Reset_Results
     (Tool : in out Ks_Calib_N_Point_To_N_Point_Tool);

   ---------------------------------------------------------------------
   --  CogCalibCheckerboard and its tool
   ---------------------------------------------------------------------

   type Ks_Calib_Checkerboard is tagged private;
   --  CalibrationImage (unallocated), PhysicalTileSizeX and Y (1.0),
   --  DOFsToCompute (Scaling_Aspect_Rotation_Skew_And_Translation), with
   --  VisionPro's defaults, the origin adjustment and the computed state.
   --  Copies are independent (the image's pixels are shared, as by
   --  assignment).

   function Calibration_Image (Calibration : Ks_Calib_Checkerboard)
      return AMV.Images.Ks_Image_8_Grey;
   procedure Set_Calibration_Image
     (Calibration : in out Ks_Calib_Checkerboard;
      Image       : AMV.Images.Ks_Image_8_Grey);
   function Physical_Tile_Size_X (Calibration : Ks_Calib_Checkerboard)
      return Real;
   procedure Set_Physical_Tile_Size_X
     (Calibration : in out Ks_Calib_Checkerboard;
      Value       : Real);
   function Physical_Tile_Size_Y (Calibration : Ks_Calib_Checkerboard)
      return Real;
   procedure Set_Physical_Tile_Size_Y
     (Calibration : in out Ks_Calib_Checkerboard;
      Value       : Real);
   function DOFs_To_Compute (Calibration : Ks_Calib_Checkerboard)
      return Ks_Calib_Checkerboard_DOF_Constants;
   procedure Set_DOFs_To_Compute
     (Calibration : in out Ks_Calib_Checkerboard;
      Value       : Ks_Calib_Checkerboard_DOF_Constants);
   function Computation_Mode (Calibration : Ks_Calib_Checkerboard)
      return Ks_Calib_Fix_Computation_Mode_Constants;
   procedure Set_Computation_Mode
     (Calibration : in out Ks_Calib_Checkerboard;
      Value       : Ks_Calib_Fix_Computation_Mode_Constants);
   --  ComputationMode: Linear (the default) or Perspective_And_Radial_Warp
   --  (the others raise Ks_Bad_Parameter_Exception). DOFsToCompute is not
   --  used by Perspective_And_Radial_Warp, whose tile sizes must be
   --  within a factor of 1024 of each other (Calibrate raises
   --  Ks_Bad_Parameter_Exception otherwise). Every setter above
   --  uncalibrates. A tile size must be > 0 and at most 1.0E140
   --  (Ks_Bad_Parameter_Exception; VisionPro raises ArgumentException
   --  too); it is the physical size of a tile along the grid's x and y
   --  axes, which run along the tile edges closest to the image's x and y
   --  axes.

   procedure Calibrate (Calibration : in out Ks_Calib_Checkerboard);
   --  Calibrate: finds the checkerboard's corners in Calibration_Image
   --  (see AMV.Kernels.Calib_Fix.Checkerboard: an X-corner detector, the
   --  grid of the largest board in the image, grown by local predictions
   --  so that perspective and lens distortion do not stop it, grid
   --  coordinates with the origin at the corner nearest the image centre),
   --  maps them into the image's selected space (the uncalibrated points),
   --  gives each the raw calibrated point (I * PhysicalTileSizeX,
   --  J * PhysicalTileSizeY) and fits UncalibratedFromCalibrated.
   --  Ks_Image_No_Pixels_Exception for an unallocated image,
   --  Ks_Bad_Parameter_Exception when fewer than 9 corners are found or
   --  the fit fails (the calibration is then not calibrated).

   function Calibrated (Calibration : Ks_Calib_Checkerboard) return Boolean;
   procedure Uncalibrate (Calibration : in out Ks_Calib_Checkerboard);

   function Num_Points (Calibration : Ks_Calib_Checkerboard) return Natural;
   procedure Get_Uncalibrated_Point
     (Calibration : Ks_Calib_Checkerboard;
      Index       : Natural;
      X, Y        : out Real);
   function Get_Uncalibrated_Point_X
     (Calibration : Ks_Calib_Checkerboard; Index : Natural) return Real;
   function Get_Uncalibrated_Point_Y
     (Calibration : Ks_Calib_Checkerboard; Index : Natural) return Real;
   procedure Get_Raw_Calibrated_Point
     (Calibration : Ks_Calib_Checkerboard;
      Index       : Natural;
      X, Y        : out Real);
   function Get_Raw_Calibrated_Point_X
     (Calibration : Ks_Calib_Checkerboard; Index : Natural) return Real;
   function Get_Raw_Calibrated_Point_Y
     (Calibration : Ks_Calib_Checkerboard; Index : Natural) return Real;
   --  The corners found by the last Calibrate (none before): NumPoints,
   --  their positions in the calibration image's selected space and their
   --  raw calibrated points (Constraint_Error outside 0 .. Num_Points -
   --  1). The corners come in rows of increasing grid index J, each of
   --  increasing I, so no grid index occurs twice.

   procedure Get_Corner
     (Calibration      : Ks_Calib_Checkerboard;
      Index            : Natural;
      Pixel_X, Pixel_Y : out Real;
      Grid_I, Grid_J   : out Integer);
   --  (AMV name) Corner Index in pixel space and its grid indices.

   function Get_Computed_Uncalibrated_From_Calibrated_Transform
     (Calibration : Ks_Calib_Checkerboard)
      return AMV.Transforms.Ks_Transform_2D_Linear;
   function Get_Computed_Uncalibrated_From_Raw_Calibrated_Transform
     (Calibration : Ks_Calib_Checkerboard)
      return AMV.Transforms.Ks_Transform_2D_Linear;
   function Computed_RMS_Error (Calibration : Ks_Calib_Checkerboard)
      return Real;
   --  As for Ks_Calib_N_Point_To_N_Point. In Perspective_And_Radial_Warp
   --  mode the transforms are the ones of the warped output image (from
   --  raw calibrated or calibrated coordinates to its uncalibrated space,
   --  the calibration image's selected space over the corrected pixels;
   --  linear; an adjustment in the Uncalibrated space raises
   --  Ks_Bad_Parameter_Exception there) and the RMS error is the RMS
   --  distance in pixels between the corners and the model.

   function Calibrated_Origin_X (Calibration : Ks_Calib_Checkerboard)
      return Real;
   procedure Set_Calibrated_Origin_X
     (Calibration : in out Ks_Calib_Checkerboard;
      Value       : Real);
   function Calibrated_Origin_Y (Calibration : Ks_Calib_Checkerboard)
      return Real;
   procedure Set_Calibrated_Origin_Y
     (Calibration : in out Ks_Calib_Checkerboard;
      Value       : Real);
   function Calibrated_Origin_Space (Calibration : Ks_Calib_Checkerboard)
      return Ks_Calib_Checkerboard_Adjustment_Space_Constants;
   procedure Set_Calibrated_Origin_Space
     (Calibration : in out Ks_Calib_Checkerboard;
      Value       : Ks_Calib_Checkerboard_Adjustment_Space_Constants);
   function Calibrated_X_Axis_Rotation (Calibration : Ks_Calib_Checkerboard)
      return Real;
   procedure Set_Calibrated_X_Axis_Rotation
     (Calibration : in out Ks_Calib_Checkerboard;
      Value       : Real);
   function Calibrated_X_Axis_Rotation_Space
     (Calibration : Ks_Calib_Checkerboard)
      return Ks_Calib_Checkerboard_Adjustment_Space_Constants;
   procedure Set_Calibrated_X_Axis_Rotation_Space
     (Calibration : in out Ks_Calib_Checkerboard;
      Value       : Ks_Calib_Checkerboard_Adjustment_Space_Constants);
   function Swap_Calibrated_Handedness (Calibration : Ks_Calib_Checkerboard)
      return Boolean;
   procedure Set_Swap_Calibrated_Handedness
     (Calibration : in out Ks_Calib_Checkerboard;
      Value       : Boolean);
   --  The origin adjustment, as for Ks_Calib_N_Point_To_N_Point. The raw
   --  calibrated space is the board's tile grid (I * PhysicalTileSizeX,
   --  J * PhysicalTileSizeY, the origin at the corner nearest the image
   --  centre).

   subtype Ks_Calib_Checkerboard_Warp_Model is
     AMV.Kernels.Calib_Fix.Ks_Radial_Warp_Model;
   --  (AMV name) The fitted model of Perspective_And_Radial_Warp: the
   --  homography (H11 .. H32) and the radial coefficients K1 and K2 in
   --  normalised coordinates, the distortion centre and the normaliser
   --  (pixels), the grid's normalisation, the valid radius, the RMS error
   --  (pixels), the warp's transforms, the size of the calibration image
   --  and the number of Levenberg-Marquardt steps (AMV.Kernels.Calib_Fix
   --  gives the formulas).

   function Get_Computed_Warp_Model (Calibration : Ks_Calib_Checkerboard)
      return Ks_Calib_Checkerboard_Warp_Model;
   --  (AMV name) The model of a calibration calibrated in
   --  Perspective_And_Radial_Warp mode (Ks_Operator_Not_Trained_Exception
   --  when not calibrated, Ks_Bad_Parameter_Exception in the linear
   --  mode).

   function Get_Output_Pixel_From_Calibrated_Transform
     (Calibration : Ks_Calib_Checkerboard)
      return AMV.Transforms.Ks_Transform_2D_Linear;
   --  (AMV name; VisionPro's warp parameters have
   --  GetOutputImageRootFromCalibratedTransform) The similarity that maps
   --  calibrated coordinates to the pixels of the warped output image
   --  (exceptions as Get_Computed_Warp_Model).

   procedure Map_Output_Pixel
     (Calibration      : Ks_Calib_Checkerboard;
      Output_X         : Real;
      Output_Y         : Real;
      Input_X, Input_Y : out Real;
      Inside           : out Boolean);
   --  (AMV name; VisionPro's warp parameters have
   --  GetInputPixelFromOutputPixelTransform) The pixel of the input image
   --  that the pixel (Output_X, Output_Y) of the warped output image
   --  shows; Inside is False (and the pixel 0, 0) when it shows nothing
   --  (it gets the unfilled value). Output coordinates within 2**32
   --  (Ks_Bad_Parameter_Exception); exceptions as Get_Computed_Warp_Model.

   procedure Map_Input_Pixel
     (Calibration        : Ks_Calib_Checkerboard;
      Input_X            : Real;
      Input_Y            : Real;
      Output_X, Output_Y : out Real;
      Inside             : out Boolean);
   --  (AMV name) The inverse of Map_Output_Pixel: the pixel of the warped
   --  output image that shows the input pixel (Input_X, Input_Y); Inside
   --  is False (and the pixel 0, 0) when the input pixel lies beyond the
   --  model's valid radius or maps behind the camera. Mapped on into the
   --  output's calibrated space (Get_Transform of the output image), it
   --  gives the calibrated coordinates of a point measured in the
   --  distorted input image, without warping it. Input coordinates within
   --  2**32 (Ks_Bad_Parameter_Exception); exceptions as
   --  Get_Computed_Warp_Model.

   type Ks_Calib_Checkerboard_Run_Params is record
      Calibrated_Space_Name      : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.To_Unbounded_String
          ("Checkerboard Calibration");
      Space_To_Output            : Ks_Calib_Space_To_Output_Constants :=
        Calibrated_Space;
      Unfilled_Pel_Value         : Integer := 0;
      Unfilled_Pel_Value_Enabled : Boolean := False;
   end record;
   --  CogCalibCheckerboardRunParams: the name and SpaceToOutput (VisionPro's
   --  defaults), and for the warp of Perspective_And_Radial_Warp the value
   --  of an output pixel that shows no input pixel: Unfilled_Pel_Value
   --  (0 .. 255, Ks_Bad_Parameter_Exception otherwise) when
   --  Unfilled_Pel_Value_Enabled, otherwise 0 (AMV's choice and
   --  defaults).

   type Ks_Calib_Checkerboard_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image  : AMV.Images.Ks_Image_8_Grey;
      Calibration  : Ks_Calib_Checkerboard;
      Run_Params   : Ks_Calib_Checkerboard_Run_Params;
      Output_Image : AMV.Images.Ks_Image_8_Grey;
      --  Set by Run; unallocated after a run that failed.
   end record;
   --  CogCalibCheckerboardTool, as Ks_Calib_N_Point_To_N_Point_Tool in the
   --  linear mode. In Perspective_And_Radial_Warp mode the output image is
   --  a new image of the input's size (which must be the calibration
   --  image's: Ks_Bad_Parameter_Exception otherwise), the input warped so
   --  that the plate is seen undistorted and without perspective, with
   --  the input's coordinate space tree, selection and pixel-from-root
   --  transform and the calibrated space added as in the linear mode.

   overriding procedure Execute (Tool : in out Ks_Calib_Checkerboard_Tool);
   overriding procedure Reset_Results
     (Tool : in out Ks_Calib_Checkerboard_Tool);

private

   package KF renames AMV.Kernels.Calib_Fix;

   --  The point pairs: a list handle of the kernel that each object owns.
   --  Assignment duplicates it, finalization destroys it, the stream
   --  attributes write and read the pairs by value.

   type Point_Pairs is new Ada.Finalization.Controlled with record
      Handle : KF.Ks_Point_Pairs;
   end record;

   overriding procedure Adjust (Pairs : in out Point_Pairs);
   overriding procedure Finalize (Pairs : in out Point_Pairs);

   procedure Write_Pairs
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : Point_Pairs);
   procedure Read_Pairs
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Point_Pairs);

   for Point_Pairs'Write use Write_Pairs;
   for Point_Pairs'Read use Read_Pairs;

   type Ks_N_Point_To_N_Point is tagged record
      Pairs           : Point_Pairs;
      DOFs_To_Compute : Ks_N_Point_To_N_Point_DOF_Constants :=
        Scaling_Aspect_Rotation_Skew_And_Translation;
   end record;

   procedure Read_N_Point
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_N_Point_To_N_Point);
   for Ks_N_Point_To_N_Point'Read use Read_N_Point;
   --  The 'Read of the records below reads the components in the order
   --  of the predefined 'Write into a fresh object, checks every
   --  enumeration value, and assigns the object to Item only when all
   --  were read; a malformed stream (one that ends early, an invalid
   --  value) raises Ks_Image_File_Exception and leaves Item as it was.

   type Ks_Fixture_N_Point_To_N_Point is tagged record
      Pairs                                  : Point_Pairs;
      DOFs_To_Compute                        :
        Ks_N_Point_To_N_Point_DOF_Constants := Rotation_And_Translation;
      Fixtured_Space_Name                    :
        Ada.Strings.Unbounded.Unbounded_String :=
          Ada.Strings.Unbounded.To_Unbounded_String ("N-Point Fixture");
      Space_To_Output                        :
        Ks_Fixture_Space_To_Output_Constants := Fixtured_Space;
      Fixtured_Space_Name_Duplicate_Handling :
        Ks_Fixtured_Space_Name_Duplicate_Handling_Constants := Compatibility;
   end record;

   procedure Read_Fixture
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Fixture_N_Point_To_N_Point);
   for Ks_Fixture_N_Point_To_N_Point'Read use Read_Fixture;

   type Ks_Fixture_N_Point_To_N_Point_Result is tagged record
      Output_Image : AMV.Images.Ks_Image_8_Grey;
      Transform    : AMV.Transforms.Ks_Transform_2D_Linear;
      RMS_Error    : Real := 0.0;
   end record;

   procedure Read_Fixture_Result
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Fixture_N_Point_To_N_Point_Result);
   for Ks_Fixture_N_Point_To_N_Point_Result'Read use Read_Fixture_Result;

   --  A calibration: a kernel calibration handle of the given kind, created
   --  with the object. Assignment duplicates it, finalization destroys it,
   --  the stream attributes write and read its inputs and computed state.

   type Calibration_Handle (Kind : AMV.Kernels.Int32) is
     new Ada.Finalization.Controlled with
   record
      Handle : KF.Ks_Calibration;
   end record;

   overriding procedure Initialize (Item : in out Calibration_Handle);
   overriding procedure Adjust (Item : in out Calibration_Handle);
   overriding procedure Finalize (Item : in out Calibration_Handle);

   procedure Write_Calibration
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : Calibration_Handle);
   procedure Read_Calibration
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Calibration_Handle);

   for Calibration_Handle'Write use Write_Calibration;
   for Calibration_Handle'Read use Read_Calibration;

   type Ks_Calib_N_Point_To_N_Point is tagged record
      Handle : Calibration_Handle (KF.Kind_N_Point_To_N_Point);
   end record;

   procedure Read_Calib_N_Point
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Calib_N_Point_To_N_Point);
   for Ks_Calib_N_Point_To_N_Point'Read use Read_Calib_N_Point;

   type Ks_Calib_Checkerboard is tagged record
      Image  : AMV.Images.Ks_Image_8_Grey;
      Handle : Calibration_Handle (KF.Kind_Checkerboard);
   end record;

   procedure Read_Calib_Checkerboard
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Calib_Checkerboard);
   for Ks_Calib_Checkerboard'Read use Read_Calib_Checkerboard;

end AMV.Calib_Fix;
