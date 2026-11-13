/*
 * AdaMachineVision (AMV) C API: the caliper tools (Cognex.VisionPro.Caliper:
 * CogCaliperTool, CogFindLineTool, CogFindCircleTool). Included by amv.h;
 * the entry points belong to the SPARK kernels AMV.Kernels.Caliper,
 * AMV.Kernels.Find_Line and AMV.Kernels.Find_Circle, whose specs describe
 * the algorithms, the scorers and every bound in full.
 *
 * Positions are reported in the space that selected_from_pixel maps pixel
 * space to (the input image's selected space in the Ada API); regions and
 * expected shapes are given in the space that the pixel_from_* transform
 * maps to pixel space. Every double must be finite and within the bounds
 * of the shape and transform kernels (1.0e150; lengths 4.0e150).
 */

#ifndef AMV_CALIPER_H
#define AMV_CALIPER_H

#include "amv.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ------------------------------------------------------------------ */
/* Caliper (CogCaliperTool, CogCaliper, CogCaliperResults)             */
/* ------------------------------------------------------------------ */

/* CogCaliperEdgeModeConstants. */
#define KS_CALIPER_EDGE_MODE_SINGLE_EDGE 1
#define KS_CALIPER_EDGE_MODE_PAIR        2

/* CogCaliperPolarityConstants (dark to light: the grey level rises along
   the search direction). */
#define KS_CALIPER_POLARITY_DARK_TO_LIGHT 1
#define KS_CALIPER_POLARITY_LIGHT_TO_DARK 2
#define KS_CALIPER_POLARITY_DONT_CARE     3

/* CogCaliperSamplingModeConstants (both sample bilinearly here). */
#define KS_CALIPER_SAMPLING_MODE_BILINEAR_INTERPOLATION 2
#define KS_CALIPER_SAMPLING_MODE_BILINEAR_ACCURATE      4

/* Scorer kinds, one per CogCaliperScorer* class (AMV codes). */
#define KS_CALIPER_SCORER_CONTRAST            0
#define KS_CALIPER_SCORER_POSITION            1
#define KS_CALIPER_SCORER_POSITION_NEG        2
#define KS_CALIPER_SCORER_POSITION_NORM       3
#define KS_CALIPER_SCORER_POSITION_NORM_NEG   4
#define KS_CALIPER_SCORER_SIZE_NORM           5
#define KS_CALIPER_SCORER_SIZE_DIFF_NORM      6
#define KS_CALIPER_SCORER_SIZE_DIFF_NORM_ASYM 7
#define KS_CALIPER_SCORER_STRADDLE            8

/* Limits. */
#define KS_CALIPER_MAX_SCORERS            8
#define KS_CALIPER_MAX_RESULTS            1000
#define KS_CALIPER_MAX_FILTER_HALF_SIZE   1000
#define KS_CALIPER_MAX_SEARCH_SAMPLES     32768
#define KS_CALIPER_MAX_PROJECTION_SAMPLES 32768
#define KS_CALIPER_MAX_SAMPLES            16777216
#define KS_CALIPER_MAX_EDGES              1024

/* One scorer: a measure m of a candidate mapped through a tent that is y1
   at m = xc, falls linearly to y0 at xc - x0 and at xc + x1, and stays y0
   beyond (SetXYParameters (x0, x1, xc, y0, y1); our own definition). */
typedef struct {
    int32_t kind;      /* KS_CALIPER_SCORER_* */
    int32_t enabled;   /* 0 or 1 */
    double  x0, x1, xc, y0, y1;
} ks_caliper_scorer;

/* CogCaliperScorers: items[0 .. count - 1]. */
typedef struct {
    int32_t           count;
    ks_caliper_scorer items[KS_CALIPER_MAX_SCORERS];
} ks_caliper_scorers;

/* CogCaliper; ks_caliper_run_params_default fills in the defaults. */
typedef struct {
    int32_t            edge_mode;                   /* SINGLE_EDGE */
    int32_t            edge_0_polarity;             /* DONT_CARE */
    int32_t            edge_1_polarity;             /* DONT_CARE */
    int32_t            filter_half_size_in_pixels;  /* 2 */
    int32_t            max_results;                 /* 1 */
    int32_t            sampling_mode;               /* BILINEAR_INTERP. */
    double             edge_0_position;             /* 0.0 */
    double             edge_1_position;             /* 10.0 */
    double             contrast_threshold;          /* 5.0 */
    ks_caliper_scorers single_edge_scorers;         /* one contrast scorer */
    ks_caliper_scorers two_edge_scorers;            /* one SizeDiffNorm */
} ks_caliper_run_params;

/* CogCaliperEdge (contrast is signed: positive for dark to light). */
typedef struct {
    double position, position_x, position_y, contrast;
} ks_caliper_edge;

/* CogCaliperResult (a single edge result has width 0 and edge_1 equal
   to edge_0). */
typedef struct {
    double          score, position, position_x, position_y, width;
    ks_caliper_edge edge_0, edge_1;
} ks_caliper_result;

typedef struct ks_caliper_results ks_caliper_results;   /* opaque */

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
_Static_assert(sizeof(ks_caliper_scorer) == 48,
               "ks_caliper_scorer must be 48 bytes");
_Static_assert(sizeof(ks_caliper_scorers) == 392,
               "ks_caliper_scorers must be 392 bytes");
_Static_assert(offsetof(ks_caliper_scorers, items) == 8,
               "ks_caliper_scorers.items offset");
_Static_assert(sizeof(ks_caliper_run_params) == 832,
               "ks_caliper_run_params must be 832 bytes");
_Static_assert(offsetof(ks_caliper_run_params, edge_0_position) == 24,
               "ks_caliper_run_params.edge_0_position offset");
_Static_assert(offsetof(ks_caliper_run_params, two_edge_scorers) == 440,
               "ks_caliper_run_params.two_edge_scorers offset");
_Static_assert(sizeof(ks_caliper_result) == 104,
               "ks_caliper_result must be 104 bytes");
#endif

/* The defaults of CogCaliper. */
void ks_caliper_run_params_default(ks_caliper_run_params *params,
                                   ks_status *status);
/* A new enabled scorer of that kind with its default parameters. */
void ks_caliper_scorer_default(int32_t kind, ks_caliper_scorer *scorer,
                               ks_status *status);
/* SetXYParameters: x0, x1 in [0, 1e150], xc within 1e150, y0, y1 in
   [0, 1]; *result is *scorer with these parameters (unchanged on
   failure). */
void ks_caliper_scorer_set_xy_parameters(const ks_caliper_scorer *scorer,
                                         double x0, double x1, double xc,
                                         double y0, double y1,
                                         ks_caliper_scorer *result,
                                         ks_status *status);
/* Add (KS_FAILURE_BAD_PARAMETER when full) and RemoveAt
   (KS_FAILURE_INDEX_OUT_OF_RANGE outside 0 .. count - 1). */
void ks_caliper_scorers_add(ks_caliper_scorers *scorers,
                            const ks_caliper_scorer *scorer,
                            ks_status *status);
void ks_caliper_scorers_remove_at(ks_caliper_scorers *scorers, int32_t index,
                                  ks_status *status);
/* The count of a list and the kind and enabled flag of a scorer, checked:
   KS_FAILURE_BAD_PARAMETER (and 0) when count is not in
   0 .. KS_CALIPER_MAX_SCORERS, kind not a scorer kind, enabled not 0 or 1
   (a record changed by hand). */
void ks_caliper_scorers_count(const ks_caliper_scorers *scorers,
                              int32_t *count, ks_status *status);
void ks_caliper_scorer_get_kind(const ks_caliper_scorer *scorer,
                                int32_t *kind, ks_status *status);
void ks_caliper_scorer_get_enabled(const ks_caliper_scorer *scorer,
                                   int32_t *enabled, ks_status *status);
/* The checks of the run parameters that ks_caliper_execute makes. */
void ks_caliper_check_run_params(const ks_caliper_run_params *params,
                                 ks_status *status);

/* Runs the caliper on image within region (side x: the search direction).
   *results is a new handle (NULL on failure): KS_FAILURE_IMAGE_NO_PIXELS
   for a NULL image, KS_FAILURE_BAD_PARAMETER for bad arguments, a side of
   length 0, a region of more than KS_CALIPER_MAX_* samples, or a result
   beyond 1e150. The results are sorted by score (best first), at most
   max_results of them. */
void ks_caliper_execute(const ks_image_8_grey *image,
                        const ks_rectangle_affine *region,
                        const ks_transform_2d_linear *pixel_from_region,
                        const ks_transform_2d_linear *selected_from_pixel,
                        const ks_caliper_run_params *params,
                        ks_caliper_results **results, ks_status *status);
/* Frees *results (nothing for NULL) and sets it to NULL. */
void ks_caliper_results_destroy(ks_caliper_results **results);
void ks_caliper_results_duplicate(const ks_caliper_results *results,
                                  ks_caliper_results **copy,
                                  ks_status *status);
/* The number of results (0 for NULL) and result index (0-based). */
void ks_caliper_results_count(const ks_caliper_results *results,
                              int32_t *count, ks_status *status);
void ks_caliper_results_item(const ks_caliper_results *results,
                             int32_t index, ks_caliper_result *item,
                             ks_status *status);
/* GetProjectionValues and GetFilteredValues, one value at a time: the
   profiles have *length values (one per sample along the search
   direction; the last filtered value is 0). */
void ks_caliper_results_profile_length(const ks_caliper_results *results,
                                       int32_t *length, ks_status *status);
void ks_caliper_results_projection_value(const ks_caliper_results *results,
                                         int32_t index, double *value,
                                         ks_status *status);
void ks_caliper_results_filtered_value(const ks_caliper_results *results,
                                       int32_t index, double *value,
                                       ks_status *status);

/* ------------------------------------------------------------------ */
/* Find line (CogFindLineTool, CogFindLine, CogFindLineResults)        */
/* ------------------------------------------------------------------ */

#define KS_FIND_LINE_MAX_CALIPERS 1000

/* CogFindLine; ks_find_line_run_params_default fills in the defaults. */
typedef struct {
    int32_t               num_calipers;              /* 6, 2 .. 1000 */
    int32_t               num_to_ignore;             /* 0 */
    int32_t               decrement_num_to_ignore;   /* 0 */
    ks_line_segment       expected_line_segment;     /* (0,0)-(100,0) */
    double                caliper_search_length;     /* 30.0 */
    double                caliper_projection_length; /* 10.0 */
    double                caliper_search_direction;  /* pi / 2 */
    ks_caliper_run_params caliper_run_params;
} ks_find_line_run_params;

/* CogFindLineResult (its CaliperResults: ks_find_line_results_caliper_
   results). found and used are 0 or 1. */
typedef struct {
    int32_t found, used;
    double  x, y, distance_to_line;
} ks_find_line_result;

typedef struct ks_find_line_results ks_find_line_results;   /* opaque */

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
_Static_assert(offsetof(ks_find_line_run_params, expected_line_segment)
                 == 16,
               "ks_find_line_run_params.expected_line_segment offset");
_Static_assert(offsetof(ks_find_line_run_params, caliper_run_params) == 72,
               "ks_find_line_run_params.caliper_run_params offset");
_Static_assert(sizeof(ks_find_line_run_params) == 904,
               "ks_find_line_run_params must be 904 bytes");
_Static_assert(sizeof(ks_find_line_result) == 32,
               "ks_find_line_result must be 32 bytes");
#endif

void ks_find_line_run_params_default(ks_find_line_run_params *params,
                                     ks_status *status);
/* The region of caliper index (0-based) in the expected segment's space. */
void ks_find_line_caliper_region(const ks_find_line_run_params *params,
                                 int32_t index, ks_rectangle_affine *region,
                                 ks_status *status);
/* Runs the calipers along the expected segment (in the space that
   pixel_from_segment maps to pixel space) and fits the line. *results is
   a new handle (NULL on failure); KS_FAILURE_OTHER when fewer than 2
   points remain for the fit. */
void ks_find_line_execute(const ks_image_8_grey *image,
                          const ks_find_line_run_params *params,
                          const ks_transform_2d_linear *pixel_from_segment,
                          const ks_transform_2d_linear *selected_from_pixel,
                          ks_find_line_results **results, ks_status *status);
void ks_find_line_results_destroy(ks_find_line_results **results);
void ks_find_line_results_count(const ks_find_line_results *results,
                                int32_t *count, ks_status *status);
void ks_find_line_results_item(const ks_find_line_results *results,
                               int32_t index, ks_find_line_result *item,
                               ks_status *status);
/* A new handle with a copy of the results of caliper index. */
void ks_find_line_results_caliper_results(
    const ks_find_line_results *results, int32_t index,
    ks_caliper_results **copy, ks_status *status);
/* GetLine and GetLineSegment. */
void ks_find_line_results_line(const ks_find_line_results *results,
                               ks_line *line, ks_line_segment *segment,
                               ks_status *status);
/* RMSError, NumPointsFound and NumPointsUsed. */
void ks_find_line_results_fit(const ks_find_line_results *results,
                              double *rms_error, int32_t *num_points_found,
                              int32_t *num_points_used, ks_status *status);

/* ------------------------------------------------------------------ */
/* Find circle (CogFindCircleTool, CogFindCircle, CogFindCircleResults) */
/* ------------------------------------------------------------------ */

#define KS_FIND_CIRCLE_MAX_CALIPERS 1000

/* CogFindCircleSearchDirectionConstants. */
#define KS_FIND_CIRCLE_SEARCH_DIRECTION_INWARD  0
#define KS_FIND_CIRCLE_SEARCH_DIRECTION_OUTWARD 1

/* CogFindCircle; ks_find_circle_run_params_default fills in the
   defaults. */
typedef struct {
    int32_t               num_calipers;              /* 6, 3 .. 1000 */
    int32_t               num_to_ignore;             /* 0 */
    int32_t               decrement_num_to_ignore;   /* 0 */
    int32_t               caliper_search_direction;  /* INWARD */
    int32_t               radius_constraint_enabled; /* 0 */
    ks_circular_arc       expected_circular_arc;     /* (0,0) r 50, 0, pi */
    double                caliper_search_length;     /* 30.0 */
    double                caliper_projection_length; /* 10.0 */
    double                radius_constraint;         /* 100.0 */
    ks_caliper_run_params caliper_run_params;
} ks_find_circle_run_params;

/* CogFindCircleResult (its CaliperResults: ks_find_circle_results_
   caliper_results). x, y: the caliper's edge moved away from the centre
   by the curvature correction L*L / (24 R) (L the projection length, R
   the radius; see AMV.Kernels.Find_Circle); the caliper results keep the
   edge as found. */
typedef struct {
    int32_t found, used;
    double  x, y, distance_to_circle;
} ks_find_circle_result;

typedef struct ks_find_circle_results ks_find_circle_results; /* opaque */

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
_Static_assert(offsetof(ks_find_circle_run_params, expected_circular_arc)
                 == 24,
               "ks_find_circle_run_params.expected_circular_arc offset");
_Static_assert(offsetof(ks_find_circle_run_params, caliper_run_params)
                 == 88,
               "ks_find_circle_run_params.caliper_run_params offset");
_Static_assert(sizeof(ks_find_circle_run_params) == 920,
               "ks_find_circle_run_params must be 920 bytes");
_Static_assert(sizeof(ks_find_circle_result) == 32,
               "ks_find_circle_result must be 32 bytes");
#endif

void ks_find_circle_run_params_default(ks_find_circle_run_params *params,
                                       ks_status *status);
/* The region of caliper index (0-based) in the expected arc's space. */
void ks_find_circle_caliper_region(const ks_find_circle_run_params *params,
                                   int32_t index,
                                   ks_rectangle_affine *region,
                                   ks_status *status);
/* Runs the calipers around the expected arc (in the space that
   pixel_from_arc maps to pixel space) and fits the circle. *results is a
   new handle (NULL on failure); KS_FAILURE_OTHER when too few points
   remain for the fit (3, or 2 with the radius constraint). */
void ks_find_circle_execute(const ks_image_8_grey *image,
                            const ks_find_circle_run_params *params,
                            const ks_transform_2d_linear *pixel_from_arc,
                            const ks_transform_2d_linear *selected_from_pixel,
                            ks_find_circle_results **results,
                            ks_status *status);
void ks_find_circle_results_destroy(ks_find_circle_results **results);
void ks_find_circle_results_count(const ks_find_circle_results *results,
                                  int32_t *count, ks_status *status);
void ks_find_circle_results_item(const ks_find_circle_results *results,
                                 int32_t index, ks_find_circle_result *item,
                                 ks_status *status);
void ks_find_circle_results_caliper_results(
    const ks_find_circle_results *results, int32_t index,
    ks_caliper_results **copy, ks_status *status);
/* GetCircle and GetCircularArc. */
void ks_find_circle_results_circle(const ks_find_circle_results *results,
                                   ks_circle *circle, ks_circular_arc *arc,
                                   ks_status *status);
/* RMSError, NumPointsFound and NumPointsUsed. */
void ks_find_circle_results_fit(const ks_find_circle_results *results,
                                double *rms_error, int32_t *num_points_found,
                                int32_t *num_points_used, ks_status *status);

#ifdef __cplusplus
}
#endif

#endif /* AMV_CALIPER_H */
