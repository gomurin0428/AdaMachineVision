/*
 * AdaMachineVision (AMV) C API: the CNL search (AMV.Kernels.CNL_Search,
 * the counterpart of CogCNLSearchTool, CogCNLSearchPattern,
 * CogCNLSearchRunParams and CogCNLSearchResults). Included by amv.h; the
 * conventions of amv.h apply (ks_status, adainit).
 *
 * The pattern is an owned handle (ks_cnl_search_pattern *, NULL is an
 * untrained pattern with the default training parameters). The entry
 * points that change it take ks_cnl_search_pattern ** and create the
 * pattern when the handle is NULL. Training copies the pixels of the
 * bounding box of the train region (a pixel region of the train image,
 * 8 .. 1024 pixels along each side) into the handle, with their pyramid
 * levels and statistics; the train image may change afterwards. Setting
 * the training parameters untrains the pattern; so does a failed
 * training. The origin (origin_x, origin_y) is given in the train
 * image's selected space; pixel_from_selected maps it to pixel space.
 * ks_cnl_search_pattern_train_masked also takes a train image mask
 * (TrainImageMask and its offsets, AMV's meaning): its pixels of value 0
 * mark train image pixels "don't care", and the score is then taken over
 * the cared-for pixels of the pattern only.
 *
 * A run scores every window of the image as large as the pattern inside
 * the bounding box of the search region (NULL: no position, no results)
 * with r * r, r the zero-mean normalised cross-correlation (0 for a
 * window of the opposite contrast unless ignore_polarity is set and the
 * algorithm is LinearSearch), and reports the best local maxima scoring
 * at least accept_threshold, best first, at most max_results of them,
 * without windows overlapping by more than xy_overlap of their area.
 * LINEAR_SEARCH scores every position; LINEAR_CNLPAS searches a
 * coarse-to-fine pyramid. Locations are the pattern's origin at each
 * match, mapped with selected_from_pixel (ks_image_get_transform with "."
 * as the target and "#" as the source). A run with an untrained pattern
 * fails with KS_FAILURE_OPERATOR_NOT_TRAINED.
 *
 * The AffineTransform region mode (TrainRegionMode and SearchRegionMode
 * AFFINE_TRANSFORM): an affine rectangle is resampled into an upright
 * image (ks_affine_transform_execute with its default run parameters).
 * ks_cnl_search_pattern_train_affine trains a pattern whose
 * train_region_mode is AFFINE_TRANSFORM on the resampled train region,
 * which must lie entirely in the train image; its origin is carried into
 * the resampled pattern, so a result's location is the same physical
 * point. ks_cnl_search_execute_affine (search_region_mode
 * AFFINE_TRANSFORM) searches the resampled search rectangle and maps every
 * location back into the image's selected space; the pattern is searched
 * for in the rectangle's frame (results have no angle).
 * ks_cnl_search_execute searches the bounding box of its pixel region with
 * either search region mode, as VisionPro does for every region but an
 * affine rectangle.
 *
 * Partial matches (LINEAR_SEARCH only): partial_match_limit_left / _right
 * (at most half the trained pattern's width) and _up / _down (at most half
 * its height) let that many of the pattern's columns or rows lie outside
 * the search area (the region's bounding box) on that side. Such a window
 * is scored over the part inside the area only (0 when fewer than a
 * quarter of the pattern's cared-for pixels lie there); with
 * partial_match_reduce_score its score is multiplied by the fraction of
 * the cared-for pixels inside. A result's edge_hit has the flags of the
 * sides of the search area its window crosses (NONE inside). The defaults
 * (0) score the windows inside the area only.
 *
 * The meaning of every field and operation is documented in
 * src/amv-kernels-cnl_search.ads and src/amv-cnl_search.ads.
 *
 * AMV is not affiliated with or endorsed by Cognex Corporation; "Cognex"
 * and "VisionPro" are trademarks of Cognex Corporation.
 */

#ifndef AMV_CNL_SEARCH_H
#define AMV_CNL_SEARCH_H

#include "amv.h"

#ifdef __cplusplus
extern "C" {
#endif

/* CogCNLSearchAlgorithmConstants (flags; NON_LINEAR_CNLPAS is not
   supported). */
#define KS_CNL_SEARCH_ALGORITHM_LINEAR_SEARCH     1
#define KS_CNL_SEARCH_ALGORITHM_LINEAR_CNLPAS     2
#define KS_CNL_SEARCH_ALGORITHM_NON_LINEAR_CNLPAS 4

/* CogCNLSearchAccuracyConstants (flags). */
#define KS_CNL_SEARCH_ACCURACY_VERY_FINE 1
#define KS_CNL_SEARCH_ACCURACY_FINE      2
#define KS_CNL_SEARCH_ACCURACY_COARSE    4

/* CogCNLSearchEdgeHitConstants (flags: the sides of the search area a
   result's window crosses; UNKNOWN is never reported). */
#define KS_CNL_SEARCH_EDGE_HIT_NONE    0
#define KS_CNL_SEARCH_EDGE_HIT_UNKNOWN 1
#define KS_CNL_SEARCH_EDGE_HIT_LEFT    2
#define KS_CNL_SEARCH_EDGE_HIT_TOP     4
#define KS_CNL_SEARCH_EDGE_HIT_RIGHT   8
#define KS_CNL_SEARCH_EDGE_HIT_BOTTOM  16

/* CogRegionModeConstants, for train_region_mode (all three) and
   search_region_mode (PIXEL_ALIGNED_BOUNDING_BOX or AFFINE_TRANSFORM). */
#define KS_CNL_SEARCH_REGION_MODE_PIXEL_ALIGNED_BOUNDING_BOX_ADJUST_MASK 0
#define KS_CNL_SEARCH_REGION_MODE_PIXEL_ALIGNED_BOUNDING_BOX             1
#define KS_CNL_SEARCH_REGION_MODE_AFFINE_TRANSFORM                       2

/* Limits. */
#define KS_CNL_SEARCH_MIN_PATTERN_SIDE  8
#define KS_CNL_SEARCH_MAX_PATTERN_SIDE  1024
#define KS_CNL_SEARCH_MAX_SEARCH_PIXELS 16777216
#define KS_CNL_SEARCH_MAX_LEVELS        6
#define KS_CNL_SEARCH_MIN_COARSE_SIDE   8
#define KS_CNL_SEARCH_MAX_RESULTS       1000
#define KS_CNL_SEARCH_MAX_CANDIDATES    4096
#define KS_CNL_SEARCH_MAX_CLIMB_STEPS   16
#define KS_CNL_SEARCH_MIN_CARED_PIXELS  64

/* The training parameters of CogCNLSearchPattern;
   ks_cnl_search_train_params_default fills in the defaults. */
typedef struct {
    int32_t algorithms;      /* LINEAR_SEARCH; 1 .. 3 */
    int32_t accuracies;      /* VERY_FINE; 1 .. 7 */
    int32_t ignore_polarity; /* 0 */
    double  origin_x;        /* 70.0 */
    double  origin_y;        /* 70.0 */
    int32_t train_region_mode; /* REGION_MODE_PIXEL_ALIGNED_BOUNDING_BOX_
                                  ADJUST_MASK: the box's pixels outside the
                                  region are don't-care (LinearSearch);
                                  PIXEL_ALIGNED_BOUNDING_BOX; or
                                  AFFINE_TRANSFORM (train with
                                  ks_cnl_search_pattern_train_affine) */
} ks_cnl_search_train_params;

/* CogCNLSearchRunParams; ks_cnl_search_run_params_default fills in the
   defaults. */
typedef struct {
    int32_t algorithm;            /* LINEAR_SEARCH */
    int32_t accuracy;             /* VERY_FINE */
    int32_t max_results;          /* 1, 1 .. KS_CNL_SEARCH_MAX_RESULTS */
    int32_t search_region_mode;   /* PIXEL_ALIGNED_BOUNDING_BOX, or
                                     AFFINE_TRANSFORM */
    double  accept_threshold;     /* 0.3, 0 .. 1 */
    double  confusion_threshold;  /* 0.5, accept_threshold .. 1 */
    double  xy_overlap;           /* 1.0, 0 .. 1 */
    int32_t partial_match_limit_left;   /* 0, 0 .. pattern width / 2 */
    int32_t partial_match_limit_right;  /* 0, 0 .. pattern width / 2 */
    int32_t partial_match_limit_up;     /* 0, 0 .. pattern height / 2 */
    int32_t partial_match_limit_down;   /* 0, 0 .. pattern height / 2 */
    int32_t partial_match_reduce_score; /* 0, 0 or 1 */
} ks_cnl_search_run_params;

/* CogCNLSearchResult. */
typedef struct {
    int32_t id;                /* the index */
    int32_t accepted;          /* 1 */
    int32_t contrast_computed; /* 1 */
    int32_t edge_hit;          /* KS_CNL_SEARCH_EDGE_HIT_* flags */
    double  score;             /* 0 .. 1 */
    double  location_x, location_y;
    double  contrast;          /* window / pattern standard deviation */
} ks_cnl_search_result;

typedef struct ks_cnl_search_pattern ks_cnl_search_pattern; /* opaque */
typedef struct ks_cnl_search_results ks_cnl_search_results; /* opaque */

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
_Static_assert(sizeof(ks_cnl_search_train_params) == 40,
               "ks_cnl_search_train_params must be 40 bytes");
_Static_assert(offsetof(ks_cnl_search_train_params, train_region_mode) == 32,
               "ks_cnl_search_train_params.train_region_mode offset");
_Static_assert(offsetof(ks_cnl_search_train_params, origin_x) == 16,
               "ks_cnl_search_train_params.origin_x offset");
_Static_assert(sizeof(ks_cnl_search_run_params) == 64,
               "ks_cnl_search_run_params must be 64 bytes");
_Static_assert(offsetof(ks_cnl_search_run_params, accept_threshold) == 16,
               "ks_cnl_search_run_params.accept_threshold offset");
_Static_assert(offsetof(ks_cnl_search_run_params, partial_match_limit_left)
                   == 40,
               "ks_cnl_search_run_params.partial_match_limit_left offset");
_Static_assert(offsetof(ks_cnl_search_run_params, partial_match_reduce_score)
                   == 56,
               "ks_cnl_search_run_params.partial_match_reduce_score offset");
_Static_assert(sizeof(ks_cnl_search_result) == 48,
               "ks_cnl_search_result must be 48 bytes");
_Static_assert(offsetof(ks_cnl_search_result, score) == 16,
               "ks_cnl_search_result.score offset");
#endif

/* The default training parameters. */
void ks_cnl_search_train_params_default(ks_cnl_search_train_params *params,
                                        ks_status *status);
/* A new untrained pattern with the default training parameters. */
void ks_cnl_search_pattern_create(ks_cnl_search_pattern **pattern,
                                  ks_status *status);
/* Frees *pattern (nothing for NULL) and sets it to NULL. */
void ks_cnl_search_pattern_destroy(ks_cnl_search_pattern **pattern,
                                   ks_status *status);
/* An independent copy (NULL for NULL). */
void ks_cnl_search_pattern_duplicate(const ks_cnl_search_pattern *pattern,
                                     ks_cnl_search_pattern **copy,
                                     ks_status *status);
/* The training parameters (the defaults for NULL). */
void ks_cnl_search_pattern_get_train_params(
    const ks_cnl_search_pattern *pattern, ks_cnl_search_train_params *params,
    ks_status *status);
/* Stores the training parameters and untrains (KS_FAILURE_BAD_PARAMETER
   for values out of range, the pattern unchanged). */
void ks_cnl_search_pattern_set_train_params(
    ks_cnl_search_pattern **pattern, const ks_cnl_search_train_params *params,
    ks_status *status);
/* Train: KS_FAILURE_IMAGE_NO_PIXELS for a NULL image,
   KS_FAILURE_BAD_PARAMETER for a pattern whose train_region_mode is
   AFFINE_TRANSFORM (use ks_cnl_search_pattern_train_affine), a NULL
   region, a region outside the image, a box smaller than 8 x 8 or larger
   than 1024 x 1024, a flat pattern or an origin too far away. Untrained on
   failure. */
void ks_cnl_search_pattern_train(
    ks_cnl_search_pattern **pattern, const ks_image_8_grey *image,
    const ks_pixel_region *region,
    const ks_transform_2d_linear *pixel_from_selected, ks_status *status);
/* Train with TrainImageMask (mask; NULL: none, the same as
   ks_cnl_search_pattern_train) at TrainImageMaskOffsetX / OffsetY: mask
   pixel (u, v) covers train image pixel (u + mask_offset_x, v +
   mask_offset_y); a mask pixel of 0 marks that pixel "don't care", any
   other value, and every pixel the mask does not cover, "care". The
   score of a window, its contrast and the pyramid levels use the
   cared-for pixels of the pattern only, so whatever lies in a window
   under the don't-care pixels changes nothing. KS_FAILURE_BAD_PARAMETER
   also for an inconsistent mask handle and for a mask that leaves fewer
   than KS_CNL_SEARCH_MIN_CARED_PIXELS pixels of the pattern cared for. */
void ks_cnl_search_pattern_train_masked(
    ks_cnl_search_pattern **pattern, const ks_image_8_grey *image,
    const ks_pixel_region *region,
    const ks_transform_2d_linear *pixel_from_selected,
    const ks_image_8_grey *mask, int32_t mask_offset_x,
    int32_t mask_offset_y, ks_status *status);
/* Train in the mode AFFINE_TRANSFORM (the pattern's train_region_mode
   must be AFFINE_TRANSFORM; a NULL *pattern, which has the default mode,
   stays NULL and fails): the affine rectangle region (in the space that
   pixel_from_region maps to pixel space) is resampled into an upright
   pattern of round(side length in pixels) pixels along each side, which
   must be 8 .. 1024. Every sample must lie in the image
   (KS_FAILURE_BAD_PARAMETER "TrainRegion must lie entirely in TrainImage
   for TrainRegionMode AffineTransform"). The origin (origin_x, origin_y
   in the train image's selected space, which pixel_from_selected maps to
   pixel space) is carried into the pattern's pixels by the resampling.
   The mask (NULL: none; mask pixel (u, v) covers train image pixel
   (u + mask_offset_x, v + mask_offset_y)) is resampled with the same
   rectangle by nearest neighbour: a pattern pixel is don't-care when the
   train pixel nearest to its sample point is covered by a mask pixel of
   0. KS_FAILURE_TRANSFORM_SINGULAR for a rectangle too flat to resample.
   Untrained on failure. */
void ks_cnl_search_pattern_train_affine(
    ks_cnl_search_pattern **pattern, const ks_image_8_grey *image,
    const ks_rectangle_affine *region,
    const ks_transform_2d_linear *pixel_from_region,
    const ks_transform_2d_linear *pixel_from_selected,
    const ks_image_8_grey *mask, int32_t mask_offset_x,
    int32_t mask_offset_y, ks_status *status);
/* Trained: *trained is 1 or 0. */
void ks_cnl_search_pattern_trained(const ks_cnl_search_pattern *pattern,
                                   int32_t *trained, ks_status *status);
/* Untrain (nothing for NULL). */
void ks_cnl_search_pattern_untrain(ks_cnl_search_pattern *pattern,
                                   ks_status *status);
/* TrainedPatternWidth and TrainedPatternHeight, the trained origin in the
   pattern's pixel coordinates and GetTrainedPatternImage (a new image):
   KS_FAILURE_OPERATOR_NOT_TRAINED for an untrained pattern. */
void ks_cnl_search_pattern_trained_size(const ks_cnl_search_pattern *pattern,
                                        int32_t *width, int32_t *height,
                                        ks_status *status);
void ks_cnl_search_pattern_trained_origin(
    const ks_cnl_search_pattern *pattern, double *x, double *y,
    ks_status *status);
void ks_cnl_search_pattern_get_trained_pattern_image(
    const ks_cnl_search_pattern *pattern, ks_image_8_grey **image,
    ks_status *status);

/* The defaults of CogCNLSearchRunParams. */
void ks_cnl_search_run_params_default(ks_cnl_search_run_params *params,
                                      ks_status *status);
/* Runs the search. *results is a new handle (NULL on failure):
   KS_FAILURE_IMAGE_NO_PIXELS for a NULL image,
   KS_FAILURE_OPERATOR_NOT_TRAINED for a NULL or untrained pattern,
   KS_FAILURE_BAD_PARAMETER for bad arguments (partial match limits beyond
   half the pattern's side, or not 0 with LINEAR_CNLPAS, included), a
   region outside the image, a search box of more than
   KS_CNL_SEARCH_MAX_SEARCH_PIXELS pixels or a location beyond 1e150. */
void ks_cnl_search_execute(const ks_image_8_grey *image,
                           const ks_pixel_region *region,
                           const ks_cnl_search_pattern *pattern,
                           const ks_cnl_search_run_params *params,
                           const ks_transform_2d_linear *selected_from_pixel,
                           ks_cnl_search_results **results,
                           ks_status *status);
/* Runs the search in the mode AFFINE_TRANSFORM (params->
   search_region_mode must be AFFINE_TRANSFORM): the affine rectangle
   region (in the space that pixel_from_region maps to pixel space) is
   resampled into an upright image (samples outside the image are 0) and
   searched whole, the partial match limits and edge_hit counting from the
   rectangle's sides; every location is mapped back through the
   resampling into pixel space and then with selected_from_pixel. A
   rectangle smaller than the pattern gives no results. The failures of
   ks_cnl_search_execute, KS_FAILURE_BAD_PARAMETER for a resampled
   rectangle of more than KS_CNL_SEARCH_MAX_SEARCH_PIXELS pixels and
   KS_FAILURE_TRANSFORM_SINGULAR for a rectangle too flat to resample. */
void ks_cnl_search_execute_affine(
    const ks_image_8_grey *image, const ks_rectangle_affine *region,
    const ks_transform_2d_linear *pixel_from_region,
    const ks_cnl_search_pattern *pattern,
    const ks_cnl_search_run_params *params,
    const ks_transform_2d_linear *selected_from_pixel,
    ks_cnl_search_results **results, ks_status *status);
/* Frees *results (nothing for NULL) and sets it to NULL. */
void ks_cnl_search_results_destroy(ks_cnl_search_results **results);
/* The number of results (0 for NULL) and result index (0-based,
   KS_FAILURE_INDEX_OUT_OF_RANGE outside 0 .. count - 1). */
void ks_cnl_search_results_count(const ks_cnl_search_results *results,
                                 int32_t *count, ks_status *status);
void ks_cnl_search_results_item(const ks_cnl_search_results *results,
                                int32_t index, ks_cnl_search_result *item,
                                ks_status *status);

#ifdef __cplusplus
}
#endif

#endif /* AMV_CNL_SEARCH_H */
