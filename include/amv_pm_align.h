/*
 * AdaMachineVision (AMV) C API: geometric pattern location
 * (Cognex.VisionPro.PMAlign: CogPMAlignTool, CogPMAlignPattern,
 * CogPMAlignRunParams, CogPMAlignZoneAngle, CogPMAlignZoneScale,
 * CogPMAlignResults, CogPMAlignResult). Included by amv.h; the entry points
 * belong to the SPARK kernel AMV.Kernels.PM_Align, whose spec describes
 * the method (our own: gradient-direction shape matching on a pyramid with
 * a least squares refinement; not Cognex's PatMax or PatQuick), every
 * measure and every bound in full.
 *
 * A pattern is an owned handle: create it, set its train parameters,
 * train it on an 8-bit image within a pixel region (with the transform from
 * pixel space to the train image's selected space and Origin, the
 * transform from pattern coordinates to that space), then search with
 * ks_pm_align_execute. A pose maps pattern coordinates to the space that
 * selected_from_pixel maps pixel space to. Every double must be finite
 * (KS_FAILURE_BAD_PARAMETER otherwise) and within the documented bounds.
 */

#ifndef AMV_PM_ALIGN_H
#define AMV_PM_ALIGN_H

#include "amv.h"

#ifdef __cplusplus
extern "C" {
#endif

/* CogPMAlignTrainAlgorithmConstants (only the first three are
   supported). */
#define KS_PM_ALIGN_TRAIN_ALGORITHM_PAT_MAX                  0
#define KS_PM_ALIGN_TRAIN_ALGORITHM_PAT_QUICK                1
#define KS_PM_ALIGN_TRAIN_ALGORITHM_PAT_MAX_AND_PAT_QUICK    2
#define KS_PM_ALIGN_TRAIN_ALGORITHM_PAT_FLEX                 3
#define KS_PM_ALIGN_TRAIN_ALGORITHM_PAT_MAX_HIGH_SENSITIVITY 4
#define KS_PM_ALIGN_TRAIN_ALGORITHM_PAT_MAX_PERSPECTIVE      5

/* CogPMAlignRunAlgorithmConstants (PAT_FLEX and PAT_MAX_PERSPECTIVE are
   not supported). */
#define KS_PM_ALIGN_RUN_ALGORITHM_PAT_MAX             0
#define KS_PM_ALIGN_RUN_ALGORITHM_PAT_QUICK           1
#define KS_PM_ALIGN_RUN_ALGORITHM_BEST_TRAINED        2
#define KS_PM_ALIGN_RUN_ALGORITHM_PAT_FLEX            3
#define KS_PM_ALIGN_RUN_ALGORITHM_PAT_MAX_PERSPECTIVE 4

/* CogPMAlignZoneConstants. */
#define KS_PM_ALIGN_ZONE_NOMINAL  0
#define KS_PM_ALIGN_ZONE_LOW_HIGH 1

/* Limits. */
#define KS_PM_ALIGN_MAX_LEVELS             6
#define KS_PM_ALIGN_MAX_FEATURES           2048
#define KS_PM_ALIGN_MIN_FEATURES           8
#define KS_PM_ALIGN_MIN_COARSE_SIZE        8
#define KS_PM_ALIGN_MAX_RESULTS            256
#define KS_PM_ALIGN_MAX_CANDIDATES         512
#define KS_PM_ALIGN_TRACKED_CANDIDATES     64
#define KS_PM_ALIGN_MAX_ANGLE_STEPS        2048
#define KS_PM_ALIGN_MAX_SCALE_STEPS        64
#define KS_PM_ALIGN_REFINE_ITERATIONS      6
#define KS_PM_ALIGN_MAX_PATTERN_COORDINATE 1.0e9
#define KS_PM_ALIGN_MAX_OFFSET             1048576.0
#define KS_PM_ALIGN_MAX_CONTRAST_THRESHOLD 1000.0
#define KS_PM_ALIGN_MIN_ZONE_SCALE         0.1
#define KS_PM_ALIGN_MAX_ZONE_SCALE         10.0
#define KS_PM_ALIGN_MAX_ZONE_ANGLE         1.0e4
#define KS_PM_ALIGN_MAX_TIMEOUT            1.0e9
#define KS_PM_ALIGN_MAX_GRAIN_LIMIT        32.0

/* The train parameters of CogPMAlignPattern (AMV defaults:
   ks_pm_align_train_params_default). */
typedef struct {
    int32_t train_algorithm;         /* PAT_MAX */
    int32_t grain_limit_auto_select; /* 1 */
    int32_t ignore_polarity;         /* 0 */
    double  grain_limit_coarse;      /* 8.0 */
    double  grain_limit_fine;        /* 1.0 */
} ks_pm_align_train_params;

/* CogPMAlignZoneAngle (radians) and CogPMAlignZoneScale. */
typedef struct {
    int32_t configuration; /* NOMINAL */
    double  low;           /* -pi (scale: 0.9) */
    double  high;          /* pi (scale: 1.1) */
    double  nominal;       /* 0.0 (scale: 1.0) */
} ks_pm_align_zone_angle;

typedef struct {
    int32_t configuration;
    double  low, high, nominal;
} ks_pm_align_zone_scale;

/* CogPMAlignRunParams (AMV defaults: ks_pm_align_run_params_default). */
typedef struct {
    double                 accept_threshold;                /* 0.5 */
    double                 coarse_accept_threshold;         /* 0.3 */
    double                 contrast_threshold;              /* 10.0 */
    double                 outside_region_threshold;        /* 0.1 */
    double                 timeout;                         /* 10000 ms */
    int32_t                approximate_number_to_find;      /* 1 */
    int32_t                run_algorithm;                   /* PAT_MAX */
    int32_t                score_using_clutter;             /* 1 */
    int32_t                timeout_enabled;                 /* 0 */
    int32_t                coarse_accept_threshold_enabled; /* 0 */
    ks_pm_align_zone_angle zone_angle;
    ks_pm_align_zone_scale zone_scale;
    double                 xy_overlap;                      /* 1.0, 0 .. 1 */
} ks_pm_align_run_params;

/* A trained feature: a point on an edge and the unit normal of the edge
   (towards the brighter side), in pattern coordinates. */
typedef struct {
    double x, y, normal_x, normal_y;
} ks_pm_align_feature;

/* CogPMAlignResult: the measures and the pose (GetPose builds the
   transform: scaling * R (rotation), then the translation). */
typedef struct {
    double  score, coverage, clutter, fit_error, contrast;
    double  outside_region_feature_proportion;
    double  translation_x, translation_y, rotation, scaling;
    int32_t id;
    int32_t fine_stage;
} ks_pm_align_result;

typedef struct ks_pm_align_pattern ks_pm_align_pattern; /* opaque */
typedef struct ks_pm_align_results ks_pm_align_results; /* opaque */

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
_Static_assert(sizeof(ks_pm_align_train_params) == 32,
               "ks_pm_align_train_params must be 32 bytes");
_Static_assert(offsetof(ks_pm_align_train_params, grain_limit_coarse) == 16,
               "ks_pm_align_train_params.grain_limit_coarse offset");
_Static_assert(sizeof(ks_pm_align_zone_angle) == 32,
               "ks_pm_align_zone_angle must be 32 bytes");
_Static_assert(sizeof(ks_pm_align_run_params) == 136,
               "ks_pm_align_run_params must be 136 bytes");
_Static_assert(offsetof(ks_pm_align_run_params, zone_angle) == 64,
               "ks_pm_align_run_params.zone_angle offset");
_Static_assert(sizeof(ks_pm_align_result) == 88,
               "ks_pm_align_result must be 88 bytes");
_Static_assert(sizeof(ks_pm_align_feature) == 32,
               "ks_pm_align_feature must be 32 bytes");
#endif

/* Parameters. */
void ks_pm_align_train_params_default(ks_pm_align_train_params *params,
                                      ks_status *status);
void ks_pm_align_run_params_default(ks_pm_align_run_params *params,
                                    ks_status *status);
/* The checks of the run parameters that ks_pm_align_execute makes
   (KS_FAILURE_BAD_PARAMETER naming the property). */
void ks_pm_align_check_run_params(const ks_pm_align_run_params *params,
                                  ks_status *status);

/* The pattern. A NULL pattern reads as an untrained pattern with the
   default parameters; set_train_params and train need a handle. */
void ks_pm_align_pattern_create(ks_pm_align_pattern **pattern,
                                ks_status *status);
void ks_pm_align_pattern_destroy(ks_pm_align_pattern **pattern);
void ks_pm_align_pattern_duplicate(const ks_pm_align_pattern *pattern,
                                   ks_pm_align_pattern **copy,
                                   ks_status *status);
void ks_pm_align_pattern_get_train_params(const ks_pm_align_pattern *pattern,
                                          ks_pm_align_train_params *params,
                                          ks_status *status);
/* Stores the parameters (checked) and untrains the pattern. */
void ks_pm_align_pattern_set_train_params(
    ks_pm_align_pattern *pattern, const ks_pm_align_train_params *params,
    ks_status *status);
/* Train. region: the train region's pixels (NULL, the empty region,
   fails). The pattern is untrained when the call fails. */
void ks_pm_align_pattern_train(ks_pm_align_pattern *pattern,
                               const ks_image_8_grey *image,
                               const ks_pixel_region *region,
                               const ks_transform_2d_linear
                                   *selected_from_pixel,
                               const ks_transform_2d_linear *origin,
                               ks_status *status);
/* Train with TrainImageMask (mask; NULL: none) at TrainImageMaskOffsetX /
   TrainImageMaskOffsetY: mask pixel (u, v) covers train image pixel
   (u + mask_offset_x, v + mask_offset_y); a mask pixel of 0 marks it
   "don't care" (training takes no feature near it, and the clutter of a
   result does not count the edges where that part of the pattern lies),
   any other value, and every pixel the mask does not cover, "care".
   KS_FAILURE_BAD_PARAMETER also for an inconsistent mask handle. */
void ks_pm_align_pattern_train_masked(ks_pm_align_pattern *pattern,
                                      const ks_image_8_grey *image,
                                      const ks_pixel_region *region,
                                      const ks_transform_2d_linear
                                          *selected_from_pixel,
                                      const ks_transform_2d_linear *origin,
                                      const ks_image_8_grey *mask,
                                      int32_t mask_offset_x,
                                      int32_t mask_offset_y,
                                      ks_status *status);
void ks_pm_align_pattern_trained(const ks_pm_align_pattern *pattern,
                                 int32_t *result, ks_status *status);
void ks_pm_align_pattern_untrain(ks_pm_align_pattern *pattern,
                                 ks_status *status);
/* The model's levels and features (KS_FAILURE_OPERATOR_NOT_TRAINED for an
   untrained pattern; KS_FAILURE_INDEX_OUT_OF_RANGE outside them). */
void ks_pm_align_pattern_levels(const ks_pm_align_pattern *pattern,
                                int32_t *finest, int32_t *coarsest,
                                ks_status *status);
void ks_pm_align_pattern_feature_count(const ks_pm_align_pattern *pattern,
                                       int32_t level, int32_t *count,
                                       ks_status *status);
void ks_pm_align_pattern_feature(const ks_pm_align_pattern *pattern,
                                 int32_t level, int32_t index,
                                 ks_pm_align_feature *feature,
                                 ks_status *status);

/* Runs the search on image within region (the search region's pixels;
   NULL gives no results). *results is a new handle (NULL on failure):
   KS_FAILURE_OPERATOR_NOT_TRAINED for an untrained pattern,
   KS_FAILURE_BAD_PARAMETER for bad run parameters,
   KS_FAILURE_IMAGE_NO_PIXELS for a NULL image, KS_FAILURE_TRANSFORM_SINGULAR
   for a selected_from_pixel without inverse. The results are sorted by
   score (best first), at most approximate_number_to_find of them. */
void ks_pm_align_execute(const ks_image_8_grey *image,
                         const ks_pixel_region *region,
                         const ks_transform_2d_linear *selected_from_pixel,
                         const ks_pm_align_pattern *pattern,
                         const ks_pm_align_run_params *params,
                         ks_pm_align_results **results, ks_status *status);
/* Frees *results (nothing for NULL) and sets it to NULL. */
void ks_pm_align_results_destroy(ks_pm_align_results **results);
void ks_pm_align_results_count(const ks_pm_align_results *results,
                               int32_t *count, ks_status *status);
void ks_pm_align_results_item(const ks_pm_align_results *results,
                              int32_t index, ks_pm_align_result *item,
                              ks_status *status);
/* GetPose. */
void ks_pm_align_result_get_pose(const ks_pm_align_result *item,
                                 ks_transform_2d_linear *pose,
                                 ks_status *status);

#ifdef __cplusplus
}
#endif

#endif /* AMV_PM_ALIGN_H */
