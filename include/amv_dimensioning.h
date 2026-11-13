/*
 * AdaMachineVision (AMV) C API: the dimensioning tools
 * (Cognex.VisionPro.Dimensioning: CogDistance*Tool, CogAngle*Tool,
 * CogIntersect*Tool) and the fitting tools (CogFitLineTool,
 * CogFitCircleTool, CogFitEllipseTool, which VisionPro keeps in
 * Cognex.VisionPro). Included by amv.h; the entry points belong to the
 * SPARK kernels AMV.Kernels.Dimensioning and
 * AMV.Kernels.Dimensioning.Fitting, whose specs describe every result,
 * tolerance and bound in full.
 *
 * The measuring tools work in one space, the "measuring space" (the
 * selected space of the tool's InputImage in the Ada API): each shape
 * comes with the transform from its own space into it
 * (selected_from_<shape>; pass the identity when everything is in one
 * space) and is mapped before it is measured; plain coordinates are taken
 * in the measuring space. A circle must stay a circle under its transform.
 * Every coordinate and radius must be finite and within 1.0e150
 * (KS_DIMENSIONING_MAX_VALUE), and every result lies within the bounds:
 * coordinates 1.0e150, distances 4.0e150, angles in (-pi, pi]. Signs and
 * degenerate cases follow the VisionPro reference: distances are negative
 * where one shape lies inside a circle or an ellipse, touching or crossing
 * shapes are at distance 0 with points (0, 0), num_points is -1
 * (intersects 1) for coincident shapes, and points that are not reported
 * are (0, 0). Every result of a failed call is 0.
 */

#ifndef AMV_DIMENSIONING_H
#define AMV_DIMENSIONING_H

#include "amv.h"

#ifdef __cplusplus
extern "C" {
#endif

#define KS_DIMENSIONING_MAX_VALUE  1.0e150
#define KS_DIMENSIONING_MAX_LENGTH 4.0e150

/* ------------------------------------------------------------------ */
/* Results of the measuring tools (their read-only properties)         */
/* ------------------------------------------------------------------ */

/* CogDistancePointPointTool. */
typedef struct {
    double  distance;
    double  angle;
} ks_distance_point_point_result;

/* CogDistancePointLineTool. */
typedef struct {
    double  distance;
    double  line_x;
    double  line_y;
} ks_distance_point_line_result;

/* CogDistancePointSegmentTool. */
typedef struct {
    double  distance;
    double  segment_x;
    double  segment_y;
} ks_distance_point_segment_result;

/* CogDistancePointCircleTool. */
typedef struct {
    double  distance;
    double  circle_x;
    double  circle_y;
} ks_distance_point_circle_result;

/* CogDistancePointEllipseTool. */
typedef struct {
    double  distance;
    double  ellipse_x;
    double  ellipse_y;
} ks_distance_point_ellipse_result;

/* CogDistanceSegmentSegmentTool. */
typedef struct {
    double  distance;
    double  segment_a_x;
    double  segment_a_y;
    double  segment_b_x;
    double  segment_b_y;
} ks_distance_segment_segment_result;

/* CogDistanceSegmentLineTool. */
typedef struct {
    double  distance;
    double  segment_x;
    double  segment_y;
    double  line_x;
    double  line_y;
} ks_distance_segment_line_result;

/* CogDistanceLineCircleTool. */
typedef struct {
    double  distance;
    double  line_x;
    double  line_y;
    double  circle_x;
    double  circle_y;
} ks_distance_line_circle_result;

/* CogDistanceSegmentCircleTool. */
typedef struct {
    double  distance;
    double  segment_x;
    double  segment_y;
    double  circle_x;
    double  circle_y;
} ks_distance_segment_circle_result;

/* CogDistanceCircleCircleTool. */
typedef struct {
    double  distance;
    double  circle_a_x;
    double  circle_a_y;
    double  circle_b_x;
    double  circle_b_y;
} ks_distance_circle_circle_result;

/* CogDistanceLineEllipseTool. */
typedef struct {
    double  distance;
    double  line_x;
    double  line_y;
    double  ellipse_x;
    double  ellipse_y;
} ks_distance_line_ellipse_result;

/* CogDistanceSegmentEllipseTool. */
typedef struct {
    double  distance;
    double  segment_x;
    double  segment_y;
    double  ellipse_x;
    double  ellipse_y;
} ks_distance_segment_ellipse_result;

/* CogIntersectLineLineTool. */
typedef struct {
    int32_t intersects;
    int32_t num_points;
    double  x;
    double  y;
    double  angle;
} ks_intersect_line_line_result;

/* CogIntersectSegmentLineTool. */
typedef struct {
    int32_t intersects;
    int32_t num_points;
    double  x;
    double  y;
} ks_intersect_segment_line_result;

/* CogIntersectSegmentSegmentTool. */
typedef struct {
    int32_t intersects;
    int32_t num_points;
    double  x;
    double  y;
} ks_intersect_segment_segment_result;

/* CogIntersectCircleCircleTool. */
typedef struct {
    int32_t intersects;
    int32_t num_points;
    double  x0;
    double  y0;
    double  x1;
    double  y1;
    double  x2;
    double  y2;
    double  x3;
    double  y3;
} ks_intersect_circle_circle_result;

/* CogIntersectLineCircleTool, CogIntersectSegmentCircleTool,
   CogIntersectLineEllipseTool and CogIntersectSegmentEllipseTool: at most
   two points, (x0, y0) first. */
typedef struct {
    int32_t intersects;
    int32_t num_points;
    double  x0;
    double  y0;
    double  x1;
    double  y1;
} ks_intersect_two_points_result;

typedef ks_intersect_two_points_result ks_intersect_line_circle_result;
typedef ks_intersect_two_points_result ks_intersect_segment_circle_result;
typedef ks_intersect_two_points_result ks_intersect_line_ellipse_result;
typedef ks_intersect_two_points_result ks_intersect_segment_ellipse_result;

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
_Static_assert(sizeof(ks_distance_point_point_result) == 16,
               "ks_distance_point_point_result must be 16 bytes");
_Static_assert(sizeof(ks_distance_segment_segment_result) == 40,
               "ks_distance_segment_segment_result must be 40 bytes");
_Static_assert(sizeof(ks_intersect_line_line_result) == 32,
               "ks_intersect_line_line_result must be 32 bytes");
_Static_assert(offsetof(ks_intersect_line_line_result, x) == 8,
               "ks_intersect_line_line_result.x offset");
_Static_assert(sizeof(ks_intersect_two_points_result) == 40,
               "ks_intersect_two_points_result must be 40 bytes");
_Static_assert(sizeof(ks_intersect_circle_circle_result) == 72,
               "ks_intersect_circle_circle_result must be 72 bytes");
#endif

/* ------------------------------------------------------------------ */
/* The measuring tools                                                 */
/* ------------------------------------------------------------------ */

/* CogDistancePointPointTool. */
void ks_distance_point_point_execute(double start_x, double start_y,
                                     double end_x, double end_y,
                                     ks_distance_point_point_result *result,
                                     ks_status *status);

/* CogAnglePointPointTool. */
void ks_angle_point_point_execute(double start_x, double start_y, double end_x,
                                  double end_y, double *angle,
                                  ks_status *status);

/* CogAngleLineLineTool. */
void ks_angle_line_line_execute(
    const ks_line *line_a, const ks_line *line_b,
    const ks_transform_2d_linear *selected_from_line_a,
    const ks_transform_2d_linear *selected_from_line_b, double *angle,
    ks_status *status);

/* CogDistancePointLineTool. */
void ks_distance_point_line_execute(
    double x, double y, const ks_line *line,
    const ks_transform_2d_linear *selected_from_line,
    ks_distance_point_line_result *result, ks_status *status);

/* CogDistancePointSegmentTool. */
void ks_distance_point_segment_execute(
    double x, double y, const ks_line_segment *segment,
    const ks_transform_2d_linear *selected_from_segment,
    ks_distance_point_segment_result *result, ks_status *status);

/* CogDistancePointCircleTool. */
void ks_distance_point_circle_execute(
    double x, double y, const ks_circle *input_circle,
    const ks_transform_2d_linear *selected_from_input_circle,
    ks_distance_point_circle_result *result, ks_status *status);

/* CogDistancePointEllipseTool. */
void ks_distance_point_ellipse_execute(
    double x, double y, const ks_ellipse *ellipse,
    const ks_transform_2d_linear *selected_from_ellipse,
    ks_distance_point_ellipse_result *result, ks_status *status);

/* CogDistanceSegmentSegmentTool. */
void ks_distance_segment_segment_execute(
    const ks_line_segment *segment_a, const ks_line_segment *segment_b,
    const ks_transform_2d_linear *selected_from_segment_a,
    const ks_transform_2d_linear *selected_from_segment_b,
    ks_distance_segment_segment_result *result, ks_status *status);

/* CogDistanceSegmentLineTool. */
void ks_distance_segment_line_execute(
    const ks_line_segment *segment, const ks_line *line,
    const ks_transform_2d_linear *selected_from_segment,
    const ks_transform_2d_linear *selected_from_line,
    ks_distance_segment_line_result *result, ks_status *status);

/* CogDistanceLineCircleTool. */
void ks_distance_line_circle_execute(
    const ks_line *line, const ks_circle *input_circle,
    const ks_transform_2d_linear *selected_from_line,
    const ks_transform_2d_linear *selected_from_input_circle,
    ks_distance_line_circle_result *result, ks_status *status);

/* CogDistanceSegmentCircleTool. */
void ks_distance_segment_circle_execute(
    const ks_line_segment *segment, const ks_circle *input_circle,
    const ks_transform_2d_linear *selected_from_segment,
    const ks_transform_2d_linear *selected_from_input_circle,
    ks_distance_segment_circle_result *result, ks_status *status);

/* CogDistanceCircleCircleTool. */
void ks_distance_circle_circle_execute(
    const ks_circle *circle_a, const ks_circle *circle_b,
    const ks_transform_2d_linear *selected_from_circle_a,
    const ks_transform_2d_linear *selected_from_circle_b,
    ks_distance_circle_circle_result *result, ks_status *status);

/* CogDistanceLineEllipseTool. */
void ks_distance_line_ellipse_execute(
    const ks_line *line, const ks_ellipse *ellipse,
    const ks_transform_2d_linear *selected_from_line,
    const ks_transform_2d_linear *selected_from_ellipse,
    ks_distance_line_ellipse_result *result, ks_status *status);

/* CogDistanceSegmentEllipseTool. */
void ks_distance_segment_ellipse_execute(
    const ks_line_segment *segment, const ks_ellipse *ellipse,
    const ks_transform_2d_linear *selected_from_segment,
    const ks_transform_2d_linear *selected_from_ellipse,
    ks_distance_segment_ellipse_result *result, ks_status *status);

/* CogIntersectLineLineTool. */
void ks_intersect_line_line_execute(
    const ks_line *line_a, const ks_line *line_b,
    const ks_transform_2d_linear *selected_from_line_a,
    const ks_transform_2d_linear *selected_from_line_b,
    ks_intersect_line_line_result *result, ks_status *status);

/* CogIntersectSegmentLineTool. */
void ks_intersect_segment_line_execute(
    const ks_line_segment *segment, const ks_line *line,
    const ks_transform_2d_linear *selected_from_segment,
    const ks_transform_2d_linear *selected_from_line,
    ks_intersect_segment_line_result *result, ks_status *status);

/* CogIntersectSegmentSegmentTool. */
void ks_intersect_segment_segment_execute(
    const ks_line_segment *segment_a, const ks_line_segment *segment_b,
    const ks_transform_2d_linear *selected_from_segment_a,
    const ks_transform_2d_linear *selected_from_segment_b,
    ks_intersect_segment_segment_result *result, ks_status *status);

/* CogIntersectLineCircleTool. */
void ks_intersect_line_circle_execute(
    const ks_line *line, const ks_circle *input_circle,
    const ks_transform_2d_linear *selected_from_line,
    const ks_transform_2d_linear *selected_from_input_circle,
    ks_intersect_line_circle_result *result, ks_status *status);

/* CogIntersectSegmentCircleTool. */
void ks_intersect_segment_circle_execute(
    const ks_line_segment *segment, const ks_circle *input_circle,
    const ks_transform_2d_linear *selected_from_segment,
    const ks_transform_2d_linear *selected_from_input_circle,
    ks_intersect_segment_circle_result *result, ks_status *status);

/* CogIntersectCircleCircleTool. */
void ks_intersect_circle_circle_execute(
    const ks_circle *circle_a, const ks_circle *circle_b,
    const ks_transform_2d_linear *selected_from_circle_a,
    const ks_transform_2d_linear *selected_from_circle_b,
    ks_intersect_circle_circle_result *result, ks_status *status);

/* CogIntersectLineEllipseTool. */
void ks_intersect_line_ellipse_execute(
    const ks_line *line, const ks_ellipse *ellipse,
    const ks_transform_2d_linear *selected_from_line,
    const ks_transform_2d_linear *selected_from_ellipse,
    ks_intersect_line_ellipse_result *result, ks_status *status);

/* CogIntersectSegmentEllipseTool. */
void ks_intersect_segment_ellipse_execute(
    const ks_line_segment *segment, const ks_ellipse *ellipse,
    const ks_transform_2d_linear *selected_from_segment,
    const ks_transform_2d_linear *selected_from_ellipse,
    ks_intersect_segment_ellipse_result *result, ks_status *status);

/* ------------------------------------------------------------------ */
/* Fitting (CogFitLineTool, CogFitCircleTool, CogFitEllipseTool)       */
/* ------------------------------------------------------------------ */

/* The points of a fit: a polygon handle whose vertices are the points
   (AddPoint, DeletePoint, NumPoints, ... of CogFitLine, CogFitCircle and
   CogFitEllipse). NULL is a list without points; ks_fit_points_add_point
   and ks_fit_points_set_num_points create the handle. At most
   KS_FIT_MAX_POINTS points, each coordinate finite and within 1.0e150.
   An index outside 0 .. NumPoints - 1 gives KS_FAILURE_INDEX_OUT_OF_RANGE;
   a failed call changes nothing. */
typedef ks_polygon ks_fit_points;

#define KS_FIT_MAX_POINTS 1048576

void ks_fit_points_num_points(const ks_fit_points *points, int32_t *count,
                              ks_status *status);
/* Appends points (0, 0) or removes points from the end. */
void ks_fit_points_set_num_points(ks_fit_points **points, int32_t count,
                                  ks_status *status);
void ks_fit_points_add_point(ks_fit_points **points, double x, double y,
                             ks_status *status);
void ks_fit_points_delete_point(ks_fit_points *points, int32_t index,
                                ks_status *status);
void ks_fit_points_get_point(const ks_fit_points *points, int32_t index,
                             double *x, double *y, ks_status *status);
void ks_fit_points_set_point(ks_fit_points *points, int32_t index, double x,
                             double y, ks_status *status);
void ks_fit_points_set_x(ks_fit_points *points, int32_t index, double value,
                         ks_status *status);
void ks_fit_points_set_y(ks_fit_points *points, int32_t index, double value,
                         ks_status *status);
void ks_fit_points_clear(ks_fit_points *points, ks_status *status);
void ks_fit_points_duplicate(const ks_fit_points *points,
                             ks_fit_points **copy, ks_status *status);
void ks_fit_points_destroy(ks_fit_points **points);

/* CogFitLine, CogFitCircle and CogFitEllipse without their points.
   num_to_ignore >= 0; the flags 0 or 1; radius_constraint in
   (0, 1.0e150] when enabled; rotation_constraint (radians) within
   1.0e150. */
typedef struct {
    int32_t num_to_ignore;                /* 0 */
} ks_fit_line_run_params;

typedef struct {
    int32_t num_to_ignore;                /* 0 */
    int32_t radius_constraint_enabled;    /* 0 */
    double  radius_constraint;            /* 100.0 */
} ks_fit_circle_run_params;

typedef struct {
    int32_t num_to_ignore;                /* 0 */
    int32_t rotation_constraint_enabled;  /* 0 */
    double  rotation_constraint;          /* 0.0 */
} ks_fit_ellipse_run_params;

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
_Static_assert(sizeof(ks_fit_line_run_params) == 4,
               "ks_fit_line_run_params must be 4 bytes");
_Static_assert(sizeof(ks_fit_circle_run_params) == 16,
               "ks_fit_circle_run_params must be 16 bytes");
_Static_assert(offsetof(ks_fit_circle_run_params, radius_constraint) == 8,
               "ks_fit_circle_run_params.radius_constraint offset");
_Static_assert(sizeof(ks_fit_ellipse_run_params) == 16,
               "ks_fit_ellipse_run_params must be 16 bytes");
#endif

void ks_fit_line_run_params_default(ks_fit_line_run_params *params,
                                    ks_status *status);
void ks_fit_circle_run_params_default(ks_fit_circle_run_params *params,
                                      ks_status *status);
void ks_fit_ellipse_run_params_default(ks_fit_ellipse_run_params *params,
                                       ks_status *status);

/* The result of a fit (CogFitLineResult, CogFitCircleResult,
   CogFitEllipseResult): an owned handle that the execute functions
   return (NULL on failure) and ks_fit_result_destroy frees. */
typedef struct ks_fit_result ks_fit_result;   /* opaque */

/* The kind of a result. */
#define KS_FIT_LINE    1
#define KS_FIT_CIRCLE  2
#define KS_FIT_ELLIPSE 3

/* CogFitLine.Execute, CogFitCircle.Execute, CogFitEllipse.Execute: the fit
   of the points (see AMV.Kernels.Dimensioning.Fitting for the methods and
   for how num_to_ignore points are left out). Too few points for the fit
   after num_to_ignore (2, 3, 5, or 4 for an ellipse with its rotation
   fixed), degenerate points and bad parameters give
   KS_FAILURE_BAD_PARAMETER. */
void ks_fit_line_execute(const ks_fit_points *points,
                         const ks_fit_line_run_params *params,
                         ks_fit_result **result, ks_status *status);
void ks_fit_circle_execute(const ks_fit_points *points,
                           const ks_fit_circle_run_params *params,
                           ks_fit_result **result, ks_status *status);
void ks_fit_ellipse_execute(const ks_fit_points *points,
                            const ks_fit_ellipse_run_params *params,
                            ks_fit_result **result, ks_status *status);

void ks_fit_result_destroy(ks_fit_result **result);
/* KS_FIT_LINE, KS_FIT_CIRCLE or KS_FIT_ELLIPSE (0 for NULL). */
void ks_fit_result_kind(const ks_fit_result *result, int32_t *kind,
                        ks_status *status);
/* NumPoints (the points given), the number of points used (AMV), RMSError
   (over the used points); 0 for NULL. */
void ks_fit_result_num_points(const ks_fit_result *result, int32_t *count,
                              ks_status *status);
void ks_fit_result_num_points_used(const ks_fit_result *result,
                                   int32_t *count, ks_status *status);
void ks_fit_result_rms_error(const ks_fit_result *result, double *rms_error,
                             ks_status *status);
/* GetXYUsedDistance of point index: its coordinates, whether the fit used
   it (0 or 1) and its distance to the fitted shape (>= 0). */
void ks_fit_result_get_xy_used_distance(const ks_fit_result *result,
                                        int32_t index, double *x, double *y,
                                        int32_t *used, double *distance,
                                        ks_status *status);
/* GetLine, GetCircle, GetEllipse: KS_FAILURE_BAD_PARAMETER for NULL or a
   result of another kind. */
void ks_fit_result_get_line(const ks_fit_result *result, ks_line *line,
                            ks_status *status);
void ks_fit_result_get_circle(const ks_fit_result *result, ks_circle *circle,
                              ks_status *status);
void ks_fit_result_get_ellipse(const ks_fit_result *result,
                               ks_ellipse *ellipse, ks_status *status);

#ifdef __cplusplus
}
#endif

#endif /* AMV_DIMENSIONING_H */
