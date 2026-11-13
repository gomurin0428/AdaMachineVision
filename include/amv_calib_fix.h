/*
 * AdaMachineVision (AMV) C API: the fixture tools and the calibrations
 * (Cognex.VisionPro.CalibFix: CogNPointToNPoint, CogFixtureTool with
 * CogFixture, CogFixtureNPointToNPointTool with CogFixtureNPointToNPoint,
 * CogCalibNPointToNPoint and CogCalibCheckerboard with their tools).
 *
 * The functions are the entry points of the SPARK kernel
 * AMV.Kernels.Calib_Fix, whose spec (src/amv-kernels-calib_fix.ads)
 * describes every fit, rule and bound in full. The conventions of amv.h
 * apply.
 *
 * Point pairs. A ks_point_pairs * is an owned list of pairs (A, B), NULL
 * being the empty list: A is the unfixtured / uncalibrated point (the
 * space the image measures in), B the raw fixtured / raw calibrated point.
 * Coordinates must be finite and within KS_CALIB_FIX_MAX_VALUE.
 *
 * Fits. ks_n_point_to_n_point_compute fits the transform of a DOF code
 * (KS_DOF_*, VisionPro's CogNPointToNPointDOFConstants values) that maps
 * B onto A with the least sum of squared distances; each DOF needs at
 * least 0, 1, 1, 1, 2, 2, 3, 3 pairs (in the order of the codes), and
 * points that do not determine the transform give
 * KS_FAILURE_BAD_PARAMETER. The
 * result holds the transform (within KS_TRANSFORM_MAX_VALUE, with a
 * non-zero determinant and an inverse within the bounds, and exactly the
 * structure of its DOF), the RMS error (B mapped minus A, A units) and the
 * fit's parameters.
 *
 * Spaces. The fixture and calibration tools take the coordinate space
 * state of the input image (tree, selected name as stored,
 * pixel_from_root, as the ks_image_* functions do), add the new space as
 * a child of the input's selected space with parent_from_new = the
 * fitted or given transform, and update the selection (SpaceToOutput 0:
 * the new space, 1: as it was). An input whose selection is "#" gets the
 * new space under "@" with the transform composed with root_from_pixel.
 * The output image is the input's pixels with the new tree and selection.
 *
 * Calibrations. A ks_calibration * is an owned trained object of one of
 * two kinds (KS_CALIBRATION_N_POINT_TO_N_POINT, KS_CALIBRATION_CHECKERBOARD;
 * AMV's single type for CogCalibNPointToNPoint and CogCalibCheckerboard).
 * Changing an input uncalibrates it; the tools fail with
 * KS_FAILURE_OPERATOR_NOT_TRAINED for an uncalibrated one. The
 * checkerboard calibration finds the X-corners of a checkerboard in an
 * 8-bit image, organises them in a grid (the largest board in the image;
 * origin at the corner nearest the image centre, axes along the tile edges
 * closest to the image's x and y; the corners in rows of increasing j,
 * each of increasing i) and fits the transform from (i * tile_size_x,
 * j * tile_size_y) to the corners in the image's selected space
 * (selected_from_pixel maps pixel positions there). The corners are found
 * under perspective and lens distortion; in the computation mode
 * KS_COMPUTATION_MODE_LINEAR (the default) the fit is a linear model: no
 * lens distortion, no perspective.
 *
 * The origin adjustment (ks_calibration_adjustment). The fit F maps raw
 * calibrated coordinates (the raw calibrated points, or the board's
 * (i * tile_size_x, j * tile_size_y)) to the uncalibrated space. The
 * calibrated space is the raw calibrated space moved rigidly: raw
 * calibrated from calibrated is R = translate (o) * rotate (phi) * m, m
 * the mirror diag (1, -1) when swap_calibrated_handedness is 1 and the
 * identity otherwise; o is (calibrated_origin_x, calibrated_origin_y) in
 * raw calibrated space (KS_ADJUSTMENT_SPACE_RAW_CALIBRATED) or that point
 * of the uncalibrated space mapped back by F^-1
 * (KS_ADJUSTMENT_SPACE_UNCALIBRATED); phi is calibrated_x_axis_rotation
 * (radians) in raw calibrated space, or the raw calibrated direction that
 * F maps onto the direction calibrated_x_axis_rotation of the
 * uncalibrated space. Uncalibrated from calibrated is F * R
 * (ks_calibration_computed_uncalibrated_from_calibrated_transform, and
 * the space the tools add); ks_calibration_computed_fit stays F. The
 * defaults (all zero) give exactly F. Setting the adjustment does not
 * uncalibrate. In KS_COMPUTATION_MODE_PERSPECTIVE_AND_RADIAL_WARP only
 * the raw calibrated space is supported (KS_FAILURE_BAD_PARAMETER where
 * F * R is needed otherwise).
 *
 * Lens distortion. In KS_COMPUTATION_MODE_PERSPECTIVE_AND_RADIAL_WARP (both
 * kinds) the calibration fits a homography of the plate and two radial
 * distortion coefficients about the image centre to the points' pixel
 * positions (a direct linear transform, then Levenberg-Marquardt; the RMS
 * error is in pixels), and ks_calibration_checkerboard_tool_execute or
 * ks_calibration_n_point_tool_execute returns the input warped so that
 * the plate is seen undistorted and without perspective, with the
 * calibrated space linear in its pixels. The plate points are the
 * checkerboard's grid indices, or the raw calibrated points of an N-point
 * calibration, whose uncalibrated points (in the calibration image's
 * selected space) are their positions: an N-point calibration then takes
 * the calibration image at ks_calibration_calibrate as a checkerboard
 * does (its size fixes the model), at least KS_CALIB_FIX_MIN_WARP_POINTS
 * pairs and every uncalibrated point on the image. ks_radial_warp_model
 * holds the model in normalised coordinates;
 * src/amv-kernels-calib_fix.ads gives the formulas, the sources and the
 * bounds.
 */

#ifndef AMV_CALIB_FIX_H
#define AMV_CALIB_FIX_H

#include "amv.h"

#ifdef __cplusplus
extern "C" {
#endif

#define KS_CALIB_FIX_MAX_VALUE     1.0e150
#define KS_CALIB_FIX_MAX_PAIRS     524288
#define KS_CALIB_FIX_MAX_RMS       4.0e150
#define KS_CALIB_FIX_MAX_TILE_SIZE 1.0e140
#define KS_CALIB_FIX_MAX_CORNERS   65536
#define KS_CALIB_FIX_MIN_CORNERS   9

/* The bounds of the nonlinear model (normalised coordinates). */
#define KS_CALIB_FIX_MAX_HOMOGRAPHY_ENTRY   1024.0
#define KS_CALIB_FIX_MAX_PERSPECTIVE_ENTRY  16.0
#define KS_CALIB_FIX_MAX_RADIAL_COEFFICIENT 4.0
#define KS_CALIB_FIX_MAX_RADIUS_SQUARED     16.0
#define KS_CALIB_FIX_MAX_FIT_ITERATIONS     50
#define KS_CALIB_FIX_MAX_MODEL_SIDE         16777216
#define KS_CALIB_FIX_MAX_OUTPUT_COORDINATE  4294967296.0
#define KS_CALIB_FIX_MAX_TILE_ASPECT        1024.0
/* The point pairs of an N-point calibration in PERSPECTIVE_AND_RADIAL_WARP
   (at least 8: sixteen equations for the ten parameters, so that the RMS
   error measures the fit), and the smallest half extent of its raw
   calibrated points. */
#define KS_CALIB_FIX_MIN_WARP_POINTS        8
#define KS_CALIB_FIX_MAX_WARP_POINTS        65536
#define KS_CALIB_FIX_MIN_PLATE_SCALE        1.0e-150

/* CogNPointToNPointDOFConstants and CogCalibCheckerboardDOFConstants. */
#define KS_DOF_NONE                                          0
#define KS_DOF_TRANSLATION_X                                 1
#define KS_DOF_TRANSLATION_Y                                 2
#define KS_DOF_TRANSLATION                                   3
#define KS_DOF_ROTATION_AND_TRANSLATION                      4
#define KS_DOF_SCALING_ROTATION_AND_TRANSLATION              5
#define KS_DOF_SCALING_ASPECT_ROTATION_AND_TRANSLATION       6
#define KS_DOF_SCALING_ASPECT_ROTATION_SKEW_AND_TRANSLATION  7

/* Which point of a pair. */
#define KS_POINT_GROUP_A 0 /* unfixtured, uncalibrated */
#define KS_POINT_GROUP_B 1 /* raw fixtured, raw calibrated */

/* SpaceToOutput: CogFixtureSpaceToOutputConstants FixturedSpace /
   UnfixturedSpace, CogCalibSpaceToOutputConstants CalibratedSpace /
   UncalibratedSpace. */
#define KS_SPACE_TO_OUTPUT_NEW 0
#define KS_SPACE_TO_OUTPUT_OLD 1

/* CogFixturedSpaceNameDuplicateHandlingConstants: COMPATIBILITY replaces
   an existing space, ENHANCED fails (KS_FAILURE_BAD_PARAMETER) when the
   space exists. */
#define KS_FIXTURED_SPACE_NAME_DUPLICATE_COMPATIBILITY 1
#define KS_FIXTURED_SPACE_NAME_DUPLICATE_ENHANCED      2

/* The kinds of calibrations. */
#define KS_CALIBRATION_N_POINT_TO_N_POINT 0
#define KS_CALIBRATION_CHECKERBOARD       1

/* CogCalibFixComputationModeConstants (VisionPro's values). AMV implements
   LINEAR and PERSPECTIVE_AND_RADIAL_WARP (checkerboard only); the others
   give KS_FAILURE_BAD_PARAMETER. */
#define KS_COMPUTATION_MODE_LINEAR                        1
#define KS_COMPUTATION_MODE_PERSPECTIVE_AND_RADIAL_WARP   2
#define KS_COMPUTATION_MODE_LINESCAN_WARP                 3
#define KS_COMPUTATION_MODE_LINESCAN_2D_WARP              4
#define KS_COMPUTATION_MODE_SINE_TAN_LAW_PROJECTION_WARP  5
#define KS_COMPUTATION_MODE_THREE_PARAM_RADIAL_WARP       6
#define KS_COMPUTATION_MODE_NO_DISTORTION_WARP            7

/* CogCalibNPointAdjustmentSpaceConstants and
   CogCalibCheckerboardAdjustmentSpaceConstants (VisionPro's values): the
   space the calibrated origin and x axis rotation are given in. */
#define KS_ADJUSTMENT_SPACE_RAW_CALIBRATED 0
#define KS_ADJUSTMENT_SPACE_UNCALIBRATED   1

/* The result of a fit. transform maps group B to group A. The parameters:
   scalings 1, rotation 0 and skew 0 without a rotation DOF; the angle for
   ROTATION_AND_TRANSLATION; the scaling twice and the angle for
   SCALING_ROTATION_AND_TRANSLATION; sx (> 0), sy and the angle for
   SCALING_ASPECT_ROTATION_AND_TRANSLATION (columns sx (cos, sin) and
   sy (-sin, cos)); ks_transform_2d_linear_decompose's values (scaling_x,
   scaling_y, rotation_x, skew) for the affine fit. */
typedef struct {
    ks_transform_2d_linear transform;
    double                 rms_error;
    double                 scaling_x;
    double                 scaling_y;
    double                 rotation;
    double                 skew;
} ks_n_point_to_n_point_fit;

/* ------------------------------------------------------------------ */
/* Point pairs                                                         */
/* ------------------------------------------------------------------ */

typedef struct ks_point_pairs ks_point_pairs; /* opaque */

/* NumPoints (0 for NULL). */
void ks_point_pairs_num_points(const ks_point_pairs *pairs, int32_t *count,
                               ks_status *status);
/* AddPointPair: appends (a_x, a_y, b_x, b_y); creates the list when *pairs
   is NULL. KS_FAILURE_BAD_PARAMETER for a coordinate out of bounds or a
   full list. */
void ks_point_pairs_add_point_pair(ks_point_pairs **pairs, double a_x,
                                   double a_y, double b_x, double b_y,
                                   ks_status *status);
/* DeletePointPair: the later pairs move down. */
void ks_point_pairs_delete_point_pair(ks_point_pairs *pairs, int32_t index,
                                      ks_status *status);
/* The point of group (KS_POINT_GROUP_*) of pair index. */
void ks_point_pairs_get_point(const ks_point_pairs *pairs, int32_t index,
                              int32_t group, double *x, double *y,
                              ks_status *status);
void ks_point_pairs_set_point(ks_point_pairs *pairs, int32_t index,
                              int32_t group, double x, double y,
                              ks_status *status);
/* Removes every pair (AMV name). */
void ks_point_pairs_clear(ks_point_pairs *pairs, ks_status *status);
/* A new list with the same pairs (NULL for NULL). */
void ks_point_pairs_duplicate(const ks_point_pairs *pairs,
                              ks_point_pairs **copy, ks_status *status);
/* Frees the list and sets *pairs to NULL (nothing for NULL). */
void ks_point_pairs_destroy(ks_point_pairs **pairs);

/* ------------------------------------------------------------------ */
/* The fit (CogNPointToNPoint.ComputeGroupAFromGroupBTransform)         */
/* ------------------------------------------------------------------ */

void ks_n_point_to_n_point_compute(const ks_point_pairs *pairs,
                                   int32_t dofs_to_compute,
                                   ks_n_point_to_n_point_fit *fit,
                                   ks_status *status);

/* ------------------------------------------------------------------ */
/* The fixture tool (CogFixtureTool, CogFixture)                        */
/* ------------------------------------------------------------------ */

typedef struct {
    ks_transform_2d_linear unfixtured_from_fixtured_transform;
    ks_space_name          fixtured_space_name;   /* a path component */
    int32_t                space_to_output;       /* KS_SPACE_TO_OUTPUT_* */
    int32_t                fixtured_space_name_duplicate_handling;
} ks_fixture_run_params;

/* The defaults: the identity, "Fixture", the new space, COMPATIBILITY. */
void ks_fixture_run_params_default(ks_fixture_run_params *params,
                                   ks_status *status);
/* Adds the fixtured space to the input's state (tree, selected) and
   updates the selection. input_image NULL: KS_FAILURE_IMAGE_NO_PIXELS. */
void ks_fixture_execute(const ks_image_8_grey *input_image,
                        const ks_fixture_run_params *params,
                        ks_coordinate_space_tree *tree,
                        ks_space_name *selected,
                        const ks_transform_2d_linear *pixel_from_root,
                        ks_status *status);

/* ------------------------------------------------------------------ */
/* The N-point fixture tool (CogFixtureNPointToNPointTool)              */
/* ------------------------------------------------------------------ */

typedef struct {
    int32_t       dofs_to_compute;     /* KS_DOF_ROTATION_AND_TRANSLATION */
    ks_space_name fixtured_space_name; /* "N-Point Fixture" */
    int32_t       space_to_output;
    int32_t       fixtured_space_name_duplicate_handling;
} ks_fixture_n_point_to_n_point_run_params;

void ks_fixture_n_point_to_n_point_run_params_default(
    ks_fixture_n_point_to_n_point_run_params *params, ks_status *status);
/* Fits unfixtured (A) from fixtured (B) and adds the fixtured space with
   it; fit is the identity when the call fails. */
void ks_fixture_n_point_to_n_point_execute(
    const ks_image_8_grey *input_image, const ks_point_pairs *pairs,
    const ks_fixture_n_point_to_n_point_run_params *params,
    ks_coordinate_space_tree *tree, ks_space_name *selected,
    const ks_transform_2d_linear *pixel_from_root,
    ks_n_point_to_n_point_fit *fit, ks_status *status);

/* ------------------------------------------------------------------ */
/* Calibrations (CogCalibNPointToNPoint, CogCalibCheckerboard)          */
/* ------------------------------------------------------------------ */

typedef struct ks_calibration ks_calibration; /* opaque */

/* A new calibration of kind: no points, DOF
   KS_DOF_SCALING_ASPECT_ROTATION_SKEW_AND_TRANSLATION, tile sizes 1.0,
   not calibrated. */
void ks_calibration_create(int32_t kind, ks_calibration **calibration,
                           ks_status *status);
void ks_calibration_destroy(ks_calibration **calibration);
void ks_calibration_duplicate(const ks_calibration *calibration,
                              ks_calibration **copy, ks_status *status);
void ks_calibration_kind(const ks_calibration *calibration, int32_t *kind,
                         ks_status *status);
/* NumPoints: the pairs of an N-point calibration, the corners a
   checkerboard calibration found. */
void ks_calibration_num_points(const ks_calibration *calibration,
                               int32_t *count, ks_status *status);
/* GetUncalibratedPoint (KS_POINT_GROUP_A), GetRawCalibratedPoint (B). */
void ks_calibration_get_point(const ks_calibration *calibration,
                              int32_t index, int32_t group, double *x,
                              double *y, ks_status *status);
/* The point pairs of an N-point calibration (KS_FAILURE_BAD_PARAMETER for
   a checkerboard); every change uncalibrates. */
void ks_calibration_add_point_pair(ks_calibration *calibration,
                                   double uncalibrated_x,
                                   double uncalibrated_y,
                                   double raw_calibrated_x,
                                   double raw_calibrated_y,
                                   ks_status *status);
void ks_calibration_delete_point_pair(ks_calibration *calibration,
                                      int32_t index, ks_status *status);
void ks_calibration_set_point(ks_calibration *calibration, int32_t index,
                              int32_t group, double x, double y,
                              ks_status *status);
void ks_calibration_dofs_to_compute(const ks_calibration *calibration,
                                    int32_t *dof, ks_status *status);
void ks_calibration_set_dofs_to_compute(ks_calibration *calibration,
                                        int32_t dof, ks_status *status);
/* PhysicalTileSizeX and Y (each in (0, KS_CALIB_FIX_MAX_TILE_SIZE]; set
   only for a checkerboard calibration). */
void ks_calibration_physical_tile_size(const ks_calibration *calibration,
                                       double *tile_size_x,
                                       double *tile_size_y,
                                       ks_status *status);
void ks_calibration_set_physical_tile_size(ks_calibration *calibration,
                                           double tile_size_x,
                                           double tile_size_y,
                                           ks_status *status);
/* Calibrate. A checkerboard calibration takes its image (NULL:
   KS_FAILURE_IMAGE_NO_PIXELS) and the transform from its pixel space to
   its selected space; fewer than KS_CALIB_FIX_MIN_CORNERS corners:
   KS_FAILURE_BAD_PARAMETER. An N-point calibration ignores both in the
   linear mode. In PERSPECTIVE_AND_RADIAL_WARP it needs
   KS_CALIB_FIX_MIN_WARP_POINTS to KS_CALIB_FIX_MAX_WARP_POINTS pairs
   (KS_FAILURE_BAD_PARAMETER, checked first), then the image (NULL:
   KS_FAILURE_IMAGE_NO_PIXELS) and its selected_from_pixel, which must be
   invertible: the uncalibrated points are mapped to pixel space with its
   inverse and must lie on the image ([-0.5, width - 0.5] x
   [-0.5, height - 0.5]); points on one line (raw calibrated or
   uncalibrated) or that do not determine the model:
   KS_FAILURE_BAD_PARAMETER. */
void ks_calibration_calibrate(ks_calibration *calibration,
                              const ks_image_8_grey *calibration_image,
                              const ks_transform_2d_linear *selected_from_pixel,
                              ks_status *status);
void ks_calibration_calibrated(const ks_calibration *calibration,
                               int32_t *result, ks_status *status);
void ks_calibration_uncalibrate(ks_calibration *calibration,
                                ks_status *status);
/* GetComputedUncalibratedFromRawCalibratedTransform (the fit F, which the
   origin adjustment does not change) and ComputedRMSError;
   KS_FAILURE_OPERATOR_NOT_TRAINED when not calibrated. */
void ks_calibration_computed_fit(const ks_calibration *calibration,
                                 ks_n_point_to_n_point_fit *fit,
                                 ks_status *status);
/* (AMV) Corner index of a checkerboard calibration: its pixel position
   (inside the image) and grid indices. */
void ks_calibration_get_corner(const ks_calibration *calibration,
                               int32_t index, double *pixel_x,
                               double *pixel_y, int32_t *grid_i,
                               int32_t *grid_j, ks_status *status);
/* (AMV) The size of the image the corners were found in (0 x 0 without
   corners). */
void ks_calibration_corner_image_size(const ks_calibration *calibration,
                                      int32_t *width, int32_t *height,
                                      ks_status *status);

/* ------------------------------------------------------------------ */
/* The origin adjustment (CalibratedOriginX/Y, CalibratedOriginSpace,   */
/* CalibratedXAxisRotation, CalibratedXAxisRotationSpace,               */
/* SwapCalibratedHandedness)                                            */
/* ------------------------------------------------------------------ */

/* (AMV name for the group of properties.) The defaults (AMV's) are all
   zero: the origin (0, 0) and the rotation 0 in raw calibrated space, not
   swapped. */
typedef struct {
    double  calibrated_origin_x;              /* within 1.0e150 */
    double  calibrated_origin_y;              /* within 1.0e150 */
    double  calibrated_x_axis_rotation;       /* radians, finite */
    int32_t calibrated_origin_space;          /* KS_ADJUSTMENT_SPACE_* */
    int32_t calibrated_x_axis_rotation_space; /* KS_ADJUSTMENT_SPACE_* */
    int32_t swap_calibrated_handedness;       /* 0 or 1 */
} ks_calibration_adjustment;

/* The defaults. Never fails. */
void ks_calibration_adjustment_default(ks_calibration_adjustment *adjustment,
                                       ks_status *status);
/* The adjustment of the calibration (the defaults and
   KS_FAILURE_BAD_PARAMETER for NULL). */
void ks_calibration_get_adjustment(const ks_calibration *calibration,
                                   ks_calibration_adjustment *adjustment,
                                   ks_status *status);
/* Sets the adjustment; the calibration stays calibrated (the fit does not
   change). KS_FAILURE_BAD_PARAMETER, and nothing changed, for a space
   code other than 0 or 1, a swap flag other than 0 or 1, an origin that
   is not finite or beyond KS_CALIB_FIX_MAX_VALUE and a rotation that is
   not finite; the rotation is stored reduced to (-pi, pi]. */
void ks_calibration_set_adjustment(ks_calibration *calibration,
                                   const ks_calibration_adjustment *adjustment,
                                   ks_status *status);
/* GetComputedUncalibratedFromCalibratedTransform: F * R (exactly F with
   the defaults). KS_FAILURE_OPERATOR_NOT_TRAINED when not calibrated;
   KS_FAILURE_BAD_PARAMETER when a transform leaves KS_TRANSFORM_MAX_VALUE
   (or F * R has no inverse within it) and for an uncalibrated space in
   KS_COMPUTATION_MODE_PERSPECTIVE_AND_RADIAL_WARP. *transform is the
   identity when the call fails. */
void ks_calibration_computed_uncalibrated_from_calibrated_transform(
    const ks_calibration *calibration, ks_transform_2d_linear *transform,
    ks_status *status);

/* ------------------------------------------------------------------ */
/* The computation mode and the nonlinear model                         */
/* ------------------------------------------------------------------ */

/* (AMV) The model of PERSPECTIVE_AND_RADIAL_WARP. With
   g = ((x - grid_center_x) / grid_scale, (y - grid_center_y) / grid_scale)
   for the plate point (x, y) (the grid indices (i, j) of a checkerboard's
   corner, the raw calibrated point of an N-point calibration's pair; the
   plate normalisation is in those units), n_x = h11 g_x + h12 g_y + h13,
   n_y = h21 g_x + h22 g_y + h23, w = 1 + h31 g_x + h32 g_y,
   h = (n_x / w, n_y / w) and rho = |h|^2, the point is seen at the pixel
   (center_x, center_y) + normalizer (1 + k1 rho + k2 rho^2) h (center: the
   image centre; normalizer: half its diagonal). The model is valid for
   rho up to valid_radius_squared. rms_error is in pixels. The warped
   output's pixel u shows the normalised plate point g =
   grid_from_output (u), and its
   pixels come from calibrated coordinates by output_pixel_from_calibrated
   (a similarity). image_width and image_height are the size of the
   calibration image (and of the images the tool warps); iterations the
   number of accepted Levenberg-Marquardt steps. */
typedef struct {
    double                 h11, h12, h13, h21, h22, h23, h31, h32;
    double                 k1, k2;
    double                 center_x, center_y;
    double                 normalizer;
    double                 grid_center_x, grid_center_y;
    double                 grid_scale;
    double                 valid_radius_squared;
    double                 rms_error;
    ks_transform_2d_linear output_pixel_from_calibrated;
    ks_transform_2d_linear grid_from_output;
    int32_t                image_width;
    int32_t                image_height;
    int32_t                iterations;
} ks_radial_warp_model;

/* ComputationMode (KS_COMPUTATION_MODE_*). Setting it uncalibrates;
   KS_FAILURE_BAD_PARAMETER for a mode AMV does not implement.
   PERSPECTIVE_AND_RADIAL_WARP is taken by both kinds. In that mode
   DOFsToCompute is not used, the tile sizes must be within
   KS_CALIB_FIX_MAX_TILE_ASPECT of each other, and ks_calibration_
   computed_fit gives the output image's transform (raw calibrated to the
   calibration image's selected space over the warped pixels) and the
   model's RMS error in pixels. */
void ks_calibration_computation_mode(const ks_calibration *calibration,
                                     int32_t *mode, ks_status *status);
void ks_calibration_set_computation_mode(ks_calibration *calibration,
                                         int32_t mode, ks_status *status);
/* (AMV) The model; KS_FAILURE_BAD_PARAMETER in the linear mode,
   KS_FAILURE_OPERATOR_NOT_TRAINED when not calibrated. */
void ks_calibration_computed_warp_model(const ks_calibration *calibration,
                                        ks_radial_warp_model *model,
                                        ks_status *status);
/* (AMV) The input pixel that the output pixel (output_x, output_y) of the
   warped image shows (*inside 1), or *inside 0 (and 0, 0) when it shows
   nothing. The output coordinates must be finite and within
   KS_CALIB_FIX_MAX_OUTPUT_COORDINATE. */
void ks_calibration_map_output_pixel(const ks_calibration *calibration,
                                     double output_x, double output_y,
                                     double *input_x, double *input_y,
                                     int32_t *inside, ks_status *status);
/* (AMV) The inverse: the output pixel of the warped image that shows the
   input pixel (input_x, input_y) (*inside 1), or *inside 0 (and 0, 0)
   when it lies beyond the model's valid radius or maps behind the camera.
   Mapped on by the output's linear calibrated space, it gives the
   calibrated coordinates of a point measured in the distorted input. */
void ks_calibration_map_input_pixel(const ks_calibration *calibration,
                                    double input_x, double input_y,
                                    double *output_x, double *output_y,
                                    int32_t *inside, ks_status *status);

/* ------------------------------------------------------------------ */
/* The calibration tools (CogCalibNPointToNPointTool,                   */
/* CogCalibCheckerboardTool)                                            */
/* ------------------------------------------------------------------ */

typedef struct {
    ks_space_name calibrated_space_name; /* a path component */
    int32_t       space_to_output;       /* KS_SPACE_TO_OUTPUT_* */
} ks_calibration_run_params;

/* The defaults of the tool of kind: "N-Point Calibration" or
   "Checkerboard Calibration", the new space. */
void ks_calibration_run_params_default(int32_t kind,
                                       ks_calibration_run_params *params,
                                       ks_status *status);
/* Adds the calibrated space (parent_from_new = the calibration's
   uncalibrated from calibrated transform F * R, failing as
   ks_calibration_computed_uncalibrated_from_calibrated_transform) to the
   input's state and updates the selection (the linear mode only:
   KS_FAILURE_BAD_PARAMETER for a calibration that warps; see
   ks_calibration_n_point_tool_execute). */
void ks_calibration_tool_execute(const ks_image_8_grey *input_image,
                                 const ks_calibration *calibration,
                                 const ks_calibration_run_params *params,
                                 ks_coordinate_space_tree *tree,
                                 ks_space_name *selected,
                                 const ks_transform_2d_linear *pixel_from_root,
                                 ks_status *status);

/* CogCalibCheckerboardRunParams. An output pixel of the warp that shows
   no input pixel gets unfilled_pel_value (0 .. 255) when
   unfilled_pel_value_enabled is 1, otherwise 0. */
typedef struct {
    ks_space_name calibrated_space_name;      /* a path component */
    int32_t       space_to_output;            /* KS_SPACE_TO_OUTPUT_* */
    int32_t       unfilled_pel_value;         /* 0 */
    int32_t       unfilled_pel_value_enabled; /* 0 */
} ks_calibration_checkerboard_run_params;

/* The defaults: "Checkerboard Calibration", the new space, 0, 0. */
void ks_calibration_checkerboard_run_params_default(
    ks_calibration_checkerboard_run_params *params, ks_status *status);
/* The checkerboard tool in every mode. The linear mode adds the calibrated
   space as ks_calibration_tool_execute and sets *output to NULL (the
   output shares the input's pixels). PERSPECTIVE_AND_RADIAL_WARP sets
   *output to a new image of the input's size (the caller destroys it;
   the input must have the calibration image's size), the input warped,
   and adds the calibrated space with the calibration's transform F * R
   (an origin adjustment in the uncalibrated space gives
   KS_FAILURE_BAD_PARAMETER). *output is NULL when the call fails. The
   calibration may be of either kind. */
void ks_calibration_checkerboard_tool_execute(
    const ks_image_8_grey *input_image, const ks_calibration *calibration,
    const ks_calibration_checkerboard_run_params *params,
    ks_coordinate_space_tree *tree, ks_space_name *selected,
    const ks_transform_2d_linear *pixel_from_root, ks_image_8_grey **output,
    ks_status *status);
/* (AMV) The N-point tool (CogCalibNPointToNPointTool) in every mode:
   ks_calibration_checkerboard_tool_execute with the name and
   space_to_output of params and unfilled pixels 0 (VisionPro's N-point
   run parameters have no UnfilledPelValue). The linear mode sets *output
   to NULL; PERSPECTIVE_AND_RADIAL_WARP to the warped image (the caller
   destroys it). */
void ks_calibration_n_point_tool_execute(
    const ks_image_8_grey *input_image, const ks_calibration *calibration,
    const ks_calibration_run_params *params, ks_coordinate_space_tree *tree,
    ks_space_name *selected, const ks_transform_2d_linear *pixel_from_root,
    ks_image_8_grey **output, ks_status *status);

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
_Static_assert(sizeof(ks_n_point_to_n_point_fit) == 88,
               "ks_n_point_to_n_point_fit must be 88 bytes");
_Static_assert(sizeof(ks_fixture_run_params) == 320,
               "ks_fixture_run_params must be 320 bytes");
_Static_assert(sizeof(ks_calibration_run_params) == 264,
               "ks_calibration_run_params must be 264 bytes");
_Static_assert(sizeof(ks_calibration_checkerboard_run_params) == 272,
               "ks_calibration_checkerboard_run_params must be 272 bytes");
_Static_assert(sizeof(ks_radial_warp_model) == 256,
               "ks_radial_warp_model must be 256 bytes");
_Static_assert(sizeof(ks_calibration_adjustment) == 40,
               "ks_calibration_adjustment must be 40 bytes");
#endif

#ifdef __cplusplus
}
#endif

#endif /* AMV_CALIB_FIX_H */
