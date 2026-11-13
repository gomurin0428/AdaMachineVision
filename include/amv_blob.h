/*
 * AdaMachineVision (AMV) C API: blob analysis (AMV.Kernels.Blob, the
 * counterpart of CogBlobTool, CogBlob and CogBlobResults). Included by
 * amv.h; the conventions of amv.h apply (ks_status, adainit).
 *
 * A run takes an 8-bit image, the pixels to analyse as a pixel region
 * (ks_pixel_region_whole_image for the whole image; NULL is the empty
 * region and finds nothing), the run parameters and the transform from
 * pixel space to the image's selected space (ks_image_get_transform with
 * "." as the target and "#" as the source). It returns an owned results
 * handle (NULL when it fails) that ks_blob_results_destroy frees.
 *
 * 1. Segmentation: a pixel of the region is foreground when its grey
 *    value is >= the threshold T (KS_BLOB_POLARITY_LIGHT_BLOBS) or < T
 *    (KS_BLOB_POLARITY_DARK_BLOBS). T is hard_fixed_threshold; or, for
 *    the relative threshold, low + ceil((high - low) *
 *    hard_relative_threshold / 100) with low and high the grey levels at
 *    the ends of the region's histogram once tail_low and tail_high
 *    percent of its pixels are set aside; or Otsu's threshold of the
 *    histogram (the dynamic threshold; no foreground when the region
 *    holds fewer than two grey levels); or 1 for KS_BLOB_SEGMENTATION_NONE.
 *    The soft thresholds give each pixel a level 0 .. softness + 1 and
 *    the weight level / (softness + 1) by AMV's rule over the grey band
 *    [low, high) (soft_fixed_threshold_low/high, or the
 *    soft_relative_threshold_low/high percentages placed between the
 *    tail levels as for the relative threshold): for light blobs 0 below
 *    the band, softness + 1 from high on, 1 + floor((g - low) * softness
 *    / (high - low)) inside it; for dark blobs the reverse (softness + 1
 *    below, 0 from high on, softness - floor(...) inside); softness 0
 *    makes the band background. A pixel with a level above 0 is
 *    foreground. Map and subtraction image are not supported. The
 *    morphology operations then apply to the foreground inside the
 *    region (to the levels for a soft segmentation: erosion takes the
 *    least level of the element, dilation the greatest).
 * 2. Connectivity: grey scale gives 8-connected blobs and 4-connected
 *    holes (background enclosed by a blob) as their children; labeled
 *    gives 8-connected blobs of equal grey value (label = the value);
 *    whole image gives one blob. Cleanup removes features with fewer than
 *    connectivity_min_pixels pixels (prune: with what lies inside them;
 *    fill: their pixels join the feature around them).
 * 3. Results: the features numbered (id) in raster order of their first
 *    pixel, every measure in the selected space (see ks_blob_result).
 *    The filtered collection holds the features accepted by every
 *    run-time measure with mode KS_BLOB_MEASURE_MODE_FILTER, sorted by
 *    sort_measure when sort_enabled (proved sorted). The extrema-angle
 *    measures are coordinates in the selected space turned by
 *    extrema_angle (E) about its origin: u = x cos E + y sin E,
 *    v = -x sin E + y cos E (the principal-axis ones are measured from
 *    the centre of mass instead). For a soft segmentation the area, the
 *    centre of mass, the second moments and what derives from them
 *    (inertia, angle, elongation, the principal axes, acircularity, and
 *    filtering and sorting by them) are weighted for blobs; pixel_count,
 *    the perimeter, the boxes' extents, the extrema-angle measures, the
 *    medians and connectivity (with connectivity_min_pixels) count
 *    pixels. A hole filled into a blob weighs fully; holes are measured
 *    as in the hard modes.
 *
 * The meaning of every field and operation is documented in
 * src/amv-kernels-blob.ads and src/amv-blob.ads.
 *
 * AMV is not affiliated with or endorsed by Cognex Corporation; "Cognex"
 * and "VisionPro" are trademarks of Cognex Corporation.
 */

#ifndef AMV_BLOB_H
#define AMV_BLOB_H

#include "amv.h"

#ifdef __cplusplus
extern "C" {
#endif

/* CogBlobSegmentationModeConstants */
#define KS_BLOB_SEGMENTATION_NONE                    0
#define KS_BLOB_SEGMENTATION_MAP                     1
#define KS_BLOB_SEGMENTATION_HARD_FIXED_THRESHOLD    2
#define KS_BLOB_SEGMENTATION_HARD_RELATIVE_THRESHOLD 3
#define KS_BLOB_SEGMENTATION_HARD_DYNAMIC_THRESHOLD  4
#define KS_BLOB_SEGMENTATION_SOFT_FIXED_THRESHOLD    5
#define KS_BLOB_SEGMENTATION_SOFT_RELATIVE_THRESHOLD 6
#define KS_BLOB_SEGMENTATION_SUBTRACTION_IMAGE       7

/* CogBlobSegmentationPolarityConstants */
#define KS_BLOB_POLARITY_DARK_BLOBS  0
#define KS_BLOB_POLARITY_LIGHT_BLOBS 1

/* CogBlobConnectivityModeConstants */
#define KS_BLOB_CONNECTIVITY_GREY_SCALE             0
#define KS_BLOB_CONNECTIVITY_LABELED                1
#define KS_BLOB_CONNECTIVITY_WHOLE_IMAGE_GREY_SCALE 2

/* CogBlobConnectivityCleanupConstants */
#define KS_BLOB_CLEANUP_NONE  0
#define KS_BLOB_CLEANUP_PRUNE 1
#define KS_BLOB_CLEANUP_FILL  2

/* CogBlobMeasureConstants (2 and 14 are not computed) */
#define KS_BLOB_MEASURE_LABEL                     0
#define KS_BLOB_MEASURE_AREA                      1
#define KS_BLOB_MEASURE_BOUNDARY_PIXEL_LENGTH     2
#define KS_BLOB_MEASURE_PERIMETER                 3
#define KS_BLOB_MEASURE_NUM_UNFILTERED_CHILDREN   4
#define KS_BLOB_MEASURE_CENTER_MASS_X             5
#define KS_BLOB_MEASURE_CENTER_MASS_Y             6
#define KS_BLOB_MEASURE_INERTIA_X                 7
#define KS_BLOB_MEASURE_INERTIA_Y                 8
#define KS_BLOB_MEASURE_INERTIA_MIN               9
#define KS_BLOB_MEASURE_INERTIA_MAX               10
#define KS_BLOB_MEASURE_ELONGATION                11
#define KS_BLOB_MEASURE_ANGLE                     12
#define KS_BLOB_MEASURE_ACIRCULARITY              13
#define KS_BLOB_MEASURE_ACIRCULARITY_RMS          14
#define KS_BLOB_MEASURE_BOUNDING_BOX_PIXEL_ALIGNED_NO_EXCLUDE_CENTER_X 15
#define KS_BLOB_MEASURE_BOUNDING_BOX_PIXEL_ALIGNED_NO_EXCLUDE_CENTER_Y 16
#define KS_BLOB_MEASURE_BOUNDING_BOX_PIXEL_ALIGNED_NO_EXCLUDE_MIN_X    17
#define KS_BLOB_MEASURE_BOUNDING_BOX_PIXEL_ALIGNED_NO_EXCLUDE_MAX_X    18
#define KS_BLOB_MEASURE_BOUNDING_BOX_PIXEL_ALIGNED_NO_EXCLUDE_MIN_Y    19
#define KS_BLOB_MEASURE_BOUNDING_BOX_PIXEL_ALIGNED_NO_EXCLUDE_MAX_Y    20
#define KS_BLOB_MEASURE_BOUNDING_BOX_PIXEL_ALIGNED_NO_EXCLUDE_WIDTH    21
#define KS_BLOB_MEASURE_BOUNDING_BOX_PIXEL_ALIGNED_NO_EXCLUDE_HEIGHT   22
#define KS_BLOB_MEASURE_BOUNDING_BOX_PIXEL_ALIGNED_NO_EXCLUDE_ASPECT   23
#define KS_BLOB_MEASURE_MEDIAN_EXTREMA_ANGLE_X          24
#define KS_BLOB_MEASURE_MEDIAN_EXTREMA_ANGLE_Y          25
#define KS_BLOB_MEASURE_BOUNDING_BOX_EXTREMA_ANGLE_CENTER_X 26
#define KS_BLOB_MEASURE_BOUNDING_BOX_EXTREMA_ANGLE_CENTER_Y 27
#define KS_BLOB_MEASURE_BOUNDING_BOX_EXTREMA_ANGLE_MIN_X    28
#define KS_BLOB_MEASURE_BOUNDING_BOX_EXTREMA_ANGLE_MAX_X    29
#define KS_BLOB_MEASURE_BOUNDING_BOX_EXTREMA_ANGLE_MIN_Y    30
#define KS_BLOB_MEASURE_BOUNDING_BOX_EXTREMA_ANGLE_MAX_Y    31
#define KS_BLOB_MEASURE_BOUNDING_BOX_EXTREMA_ANGLE_WIDTH    32
#define KS_BLOB_MEASURE_BOUNDING_BOX_EXTREMA_ANGLE_HEIGHT   33
#define KS_BLOB_MEASURE_BOUNDING_BOX_EXTREMA_ANGLE_ASPECT   34
#define KS_BLOB_MEASURE_BOUNDING_BOX_PRINCIPAL_AXIS_MIN_X   35
#define KS_BLOB_MEASURE_BOUNDING_BOX_PRINCIPAL_AXIS_MAX_X   36
#define KS_BLOB_MEASURE_BOUNDING_BOX_PRINCIPAL_AXIS_MIN_Y   37
#define KS_BLOB_MEASURE_BOUNDING_BOX_PRINCIPAL_AXIS_MAX_Y   38
#define KS_BLOB_MEASURE_BOUNDING_BOX_PRINCIPAL_AXIS_WIDTH   39
#define KS_BLOB_MEASURE_BOUNDING_BOX_PRINCIPAL_AXIS_HEIGHT  40
#define KS_BLOB_MEASURE_BOUNDING_BOX_PRINCIPAL_AXIS_ASPECT  41
#define KS_BLOB_MEASURE_NOT_CLIPPED                         42

/* CogBlobMeasureModeConstants */
#define KS_BLOB_MEASURE_MODE_NONE        0
#define KS_BLOB_MEASURE_MODE_PRE_COMPUTE 1
#define KS_BLOB_MEASURE_MODE_FILTER      2

/* CogBlobFilterModeConstants */
#define KS_BLOB_FILTER_EXCLUDE_BLOBS_IN_RANGE 0
#define KS_BLOB_FILTER_INCLUDE_BLOBS_IN_RANGE 1

/* CogBlobAxisConstants */
#define KS_BLOB_AXIS_PRINCIPAL                0
#define KS_BLOB_AXIS_SELECTED_SPACE           1
#define KS_BLOB_AXIS_EXTREMA_ANGLE            2
#define KS_BLOB_AXIS_PIXEL_ALIGNED            3
#define KS_BLOB_AXIS_PIXEL_ALIGNED_NO_EXCLUDE 4

/* CogBlobMorphologyConstants */
#define KS_BLOB_MORPHOLOGY_ERODE_HORIZONTAL  0
#define KS_BLOB_MORPHOLOGY_ERODE_VERTICAL    1
#define KS_BLOB_MORPHOLOGY_ERODE_SQUARE      2
#define KS_BLOB_MORPHOLOGY_DILATE_HORIZONTAL 3
#define KS_BLOB_MORPHOLOGY_DILATE_VERTICAL   4
#define KS_BLOB_MORPHOLOGY_DILATE_SQUARE     5
#define KS_BLOB_MORPHOLOGY_CLOSE_HORIZONTAL  6
#define KS_BLOB_MORPHOLOGY_CLOSE_VERTICAL    7
#define KS_BLOB_MORPHOLOGY_CLOSE_SQUARE      8
#define KS_BLOB_MORPHOLOGY_OPEN_HORIZONTAL   9
#define KS_BLOB_MORPHOLOGY_OPEN_VERTICAL     10
#define KS_BLOB_MORPHOLOGY_OPEN_SQUARE       11

/* CogBlobLabelConstants (grey scale connectivity) */
#define KS_BLOB_LABEL_HOLE 0
#define KS_BLOB_LABEL_BLOB 1

/* CogBlobSegmentedImageConstants */
#define KS_BLOB_SEGMENTED_FINAL_IMAGE       0
#define KS_BLOB_SEGMENTED_BEFORE_MORPHOLOGY 1
#define KS_BLOB_SEGMENTED_BEFORE_MASKING    2

/* Limits */
#define KS_BLOB_MAX_RUN_TIME_MEASURES     64
#define KS_BLOB_MAX_MORPHOLOGY_OPERATIONS 32
#define KS_BLOB_MAX_FIXED_THRESHOLD       65535
#define KS_BLOB_MAX_SOFTNESS              254
#define KS_BLOB_MAX_SCALE                 18446744073709551616.0 /* 2**64 */
#define KS_BLOB_MAX_TRANSLATION           1.0e140
#define KS_BLOB_MAX_REGION_PIXELS         2147483645
#define KS_BLOB_MAX_ID_IMAGE_BLOBS        65535
#define KS_BLOB_MAX_EXTREMA_ANGLE         1.0e6 /* radians */

/* CogBlobSegmentationParams. Every field is checked by ks_blob_execute,
   whatever the mode. The soft fixed defaults (102, 153) are AMV's;
   VisionPro does not state them. */
typedef struct {
    int32_t mode;                    /* KS_BLOB_SEGMENTATION_* */
    int32_t polarity;                /* KS_BLOB_POLARITY_* */
    int32_t hard_fixed_threshold;    /* 0 .. 65535 */
    int32_t hard_relative_threshold; /* percent, 0 .. 100 */
    int32_t tail_low;                /* percent, 0 .. 100 */
    int32_t tail_high;               /* percent, 0 .. 100 */
    int32_t soft_fixed_threshold_low;     /* 0 .. 65534, < high */
    int32_t soft_fixed_threshold_high;    /* 1 .. 65535 */
    int32_t soft_relative_threshold_low;  /* percent, 0 .. 100, <= high */
    int32_t soft_relative_threshold_high; /* percent, 0 .. 100 */
    int32_t softness;                     /* 0 .. KS_BLOB_MAX_SOFTNESS */
} ks_blob_segmentation_params;

/* CogBlobMeasure */
typedef struct {
    int32_t measure;            /* KS_BLOB_MEASURE_* */
    int32_t mode;               /* KS_BLOB_MEASURE_MODE_* */
    int32_t filter_mode;        /* KS_BLOB_FILTER_* */
    double  filter_range_low;
    double  filter_range_high;
} ks_blob_measure;

/* CogBlobMeasureCollection: items[0 .. count - 1] */
typedef struct {
    int32_t         count;
    ks_blob_measure items[KS_BLOB_MAX_RUN_TIME_MEASURES];
} ks_blob_measure_collection;

/* CogBlobMorphologyCollection: items[0 .. count - 1] */
typedef struct {
    int32_t count;
    int32_t items[KS_BLOB_MAX_MORPHOLOGY_OPERATIONS]; /* KS_BLOB_MORPHOLOGY_* */
} ks_blob_morphology_collection;

/* CogBlob (the run parameters) */
typedef struct {
    ks_blob_segmentation_params   segmentation_params;
    int32_t                       connectivity_mode;
    int32_t                       connectivity_cleanup;
    int32_t                       connectivity_min_pixels; /* >= 0 */
    int32_t                       sort_enabled;            /* 0 or 1 */
    int32_t                       sort_measure;
    int32_t                       sort_ascending;          /* 0 or 1 */
    ks_blob_measure_collection    run_time_measures;
    ks_blob_morphology_collection morphology_operations;
    double                        extrema_angle; /* radians, default 0 */
    /* 0 or 1, default 0 (since ABI version 3) */
    int32_t                       save_segmented_image;
    int32_t                       save_segmented_image_before_masking;
    int32_t                       save_segmented_image_before_morphology;
} ks_blob_run_params;

/* CogBlobResult: one feature, every measure in the selected space. */
typedef struct {
    int32_t id;                      /* 0-based, raster order */
    int32_t label;                   /* KS_BLOB_LABEL_* or grey value */
    int32_t parent_id;               /* -1 for none */
    int32_t num_children;            /* that passed the filter */
    int32_t num_unfiltered_children;
    int32_t filtered_out;            /* 1 when it did not pass */
    int32_t not_clipped;             /* 1 when it does not touch the edge */
    int32_t pixel_count;
    double  area;
    double  center_of_mass_x, center_of_mass_y;
    double  angle;                   /* least inertia axis, (-pi/2, pi/2] */
    double  perimeter;
    double  inertia_x, inertia_y, inertia_min, inertia_max;
    double  elongation;              /* inertia_max / inertia_min */
    double  acircularity;            /* perimeter**2 / (4 pi area) */
    double  pixel_aligned_center_x, pixel_aligned_center_y;
    double  pixel_aligned_min_x, pixel_aligned_max_x;
    double  pixel_aligned_min_y, pixel_aligned_max_y;
    double  pixel_aligned_width, pixel_aligned_height, pixel_aligned_aspect;
    double  principal_axis_min_x, principal_axis_max_x;
    double  principal_axis_min_y, principal_axis_max_y;
    double  principal_axis_width, principal_axis_height;
    double  principal_axis_aspect;
    ks_rectangle_affine pixel_aligned_box;
    ks_rectangle_affine principal_axis_box;
    ks_rectangle_affine selected_space_box;
    /* Along the axes at extrema_angle (u, v as above): the box's centre,
       bounds and sides in u and v, aspect = height / width, the medians
       of u and v over the pixel centres, and the box itself. */
    double  extrema_angle_center_x, extrema_angle_center_y;
    double  extrema_angle_min_x, extrema_angle_max_x;
    double  extrema_angle_min_y, extrema_angle_max_y;
    double  extrema_angle_width, extrema_angle_height, extrema_angle_aspect;
    double  median_extrema_angle_x, median_extrema_angle_y;
    ks_rectangle_affine extrema_angle_box;
} ks_blob_result;

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
_Static_assert(sizeof(ks_blob_segmentation_params) == 44,
               "ks_blob_segmentation_params must be 44 bytes");
_Static_assert(sizeof(ks_blob_measure) == 32,
               "ks_blob_measure must be 32 bytes");
_Static_assert(sizeof(ks_blob_measure_collection) == 2056,
               "ks_blob_measure_collection must be 2056 bytes");
_Static_assert(sizeof(ks_blob_morphology_collection) == 132,
               "ks_blob_morphology_collection must be 132 bytes");
_Static_assert(offsetof(ks_blob_run_params, connectivity_mode) == 44,
               "ks_blob_run_params.connectivity_mode offset");
_Static_assert(offsetof(ks_blob_run_params, run_time_measures) == 72,
               "ks_blob_run_params.run_time_measures offset");
_Static_assert(offsetof(ks_blob_run_params, extrema_angle) == 2264,
               "ks_blob_run_params.extrema_angle offset");
_Static_assert(offsetof(ks_blob_run_params, save_segmented_image) == 2272,
               "ks_blob_run_params.save_segmented_image offset");
_Static_assert(sizeof(ks_blob_run_params) == 2288,
               "ks_blob_run_params must be 2288 bytes");
_Static_assert(offsetof(ks_blob_result, area) == 32,
               "ks_blob_result.area offset");
_Static_assert(offsetof(ks_blob_result, pixel_aligned_box) == 248,
               "ks_blob_result.pixel_aligned_box offset");
_Static_assert(offsetof(ks_blob_result, extrema_angle_center_x) == 392,
               "ks_blob_result.extrema_angle_center_x offset");
_Static_assert(offsetof(ks_blob_result, extrema_angle_box) == 480,
               "ks_blob_result.extrema_angle_box offset");
_Static_assert(sizeof(ks_blob_result) == 528,
               "ks_blob_result must be 528 bytes");
#endif

typedef struct ks_blob_results ks_blob_results; /* opaque */

/* VisionPro's defaults: hard dynamic threshold, dark blobs, fixed 128,
   relative 50, no tails, soft fixed 102 .. 153 (AMV's), soft relative
   40 .. 60, softness 254, grey scale, fill, min pixels 10, sorted by area
   descending, no run-time measures, no morphology. */
void ks_blob_run_params_default(ks_blob_run_params *params,
                                ks_status *status);

/* The setters of CogBlobSegmentationParams (SetSegmentation*): each
   checks its arguments, then sets mode and the fields it names. On
   KS_FAILURE_BAD_PARAMETER (VisionPro's ArgumentException; the message
   names the argument) *params is unchanged: a value out of its range
   (percentages 0 .. 100, hard_fixed_threshold 0 .. 65535, soft fixed low
   0 .. 65534 and high 1 .. 65535, softness 0 .. 254), tail_low +
   tail_high > 100, soft fixed low >= high, soft relative low > high, or a
   polarity that is not KS_BLOB_POLARITY_*. (AMV's dynamic threshold does
   not use the tails.) */
void ks_blob_segmentation_params_set_hard_fixed_threshold(
    ks_blob_segmentation_params *params, int32_t hard_fixed_threshold,
    int32_t polarity, ks_status *status);
void ks_blob_segmentation_params_set_hard_relative_threshold(
    ks_blob_segmentation_params *params, int32_t tail_low, int32_t tail_high,
    int32_t hard_relative_threshold, int32_t polarity, ks_status *status);
void ks_blob_segmentation_params_set_hard_dynamic_threshold(
    ks_blob_segmentation_params *params, int32_t tail_low, int32_t tail_high,
    int32_t polarity, ks_status *status);
void ks_blob_segmentation_params_set_soft_fixed_threshold(
    ks_blob_segmentation_params *params, int32_t soft_fixed_threshold_low,
    int32_t soft_fixed_threshold_high, int32_t softness, int32_t polarity,
    ks_status *status);
void ks_blob_segmentation_params_set_soft_relative_threshold(
    ks_blob_segmentation_params *params, int32_t tail_low, int32_t tail_high,
    int32_t soft_relative_threshold_low, int32_t soft_relative_threshold_high,
    int32_t softness, int32_t polarity, ks_status *status);

/* Append to a collection (KS_FAILURE_BAD_PARAMETER when it is full or,
   for morphology, for a code outside KS_BLOB_MORPHOLOGY_*). */
void ks_blob_measure_collection_add(ks_blob_measure_collection *collection,
                                    const ks_blob_measure *measure,
                                    ks_status *status);
void ks_blob_morphology_collection_add(
    ks_blob_morphology_collection *collection, int32_t operation,
    ks_status *status);

/* CogBlob.Execute. Failures, in this order: KS_FAILURE_IMAGE_NO_PIXELS
   for a NULL image; KS_FAILURE_BAD_PARAMETER for run parameters that are
   not valid (the message names the property; extrema_angle must be
   finite and within +/-KS_BLOB_MAX_EXTREMA_ANGLE), a transform whose
   matrix
   entries exceed KS_BLOB_MAX_SCALE or whose translation exceeds
   KS_BLOB_MAX_TRANSLATION, a region that is not valid or does not lie in
   the image; KS_FAILURE_OUT_OF_MEMORY. */
void ks_blob_execute(const ks_image_8_grey *image,
                     const ks_pixel_region *region,
                     const ks_blob_run_params *params,
                     const ks_transform_2d_linear *selected_from_pixel,
                     ks_blob_results **results, ks_status *status);

void ks_blob_results_destroy(ks_blob_results **results, ks_status *status);

/* GetBlobs(filtered).Count and .Item(index): filtered = 1 gives the
   filtered collection in its order, 0 every feature in id order. NULL
   results have no features. KS_FAILURE_INDEX_OUT_OF_RANGE outside
   0 .. count - 1. */
void ks_blob_results_count(const ks_blob_results *results, int32_t filtered,
                           int32_t *count, ks_status *status);
void ks_blob_results_item(const ks_blob_results *results, int32_t filtered,
                          int32_t index, ks_blob_result *item,
                          ks_status *status);

/* GetBlobByID and GetParent (parent_id -1 for none);
   KS_FAILURE_BAD_PARAMETER for an id no feature has. */
void ks_blob_results_get_blob_by_id(const ks_blob_results *results,
                                    int32_t id, ks_blob_result *item,
                                    ks_status *status);
void ks_blob_results_get_parent(const ks_blob_results *results, int32_t id,
                                int32_t *parent_id, ks_status *status);

/* The feature tree (AMV.Kernels.Blob.Tree): GetChildren, GetSiblings,
   GetTopLevelBlobs and GetBlobIDs as a query (relation, id, filtered) whose
   features are counted and read one ID at a time. KS_BLOB_RELATION_ALL
   picks every feature, CHILDREN the features whose parent is feature id,
   SIBLINGS the features other than id that have its parent, TOP_LEVEL the
   features without a parent; filtered = 1 takes them from the filtered
   collection in its order, 0 from every feature in ID order. id is read by
   CHILDREN and SIBLINGS only (KS_FAILURE_BAD_PARAMETER for an ID no
   feature has). related_id fails with KS_FAILURE_INDEX_OUT_OF_RANGE (and
   *feature_id = -1) outside 0 .. count - 1. get_blob_measure is
   GetBlobMeasure: the measure of feature id, as ks_blob_result_get_measure
   gives it. */
#define KS_BLOB_RELATION_ALL       0
#define KS_BLOB_RELATION_CHILDREN  1
#define KS_BLOB_RELATION_SIBLINGS  2
#define KS_BLOB_RELATION_TOP_LEVEL 3

void ks_blob_results_related_count(const ks_blob_results *results,
                                   int32_t relation, int32_t id,
                                   int32_t filtered, int32_t *count,
                                   ks_status *status);
void ks_blob_results_related_id(const ks_blob_results *results,
                                int32_t relation, int32_t id,
                                int32_t filtered, int32_t index,
                                int32_t *feature_id, ks_status *status);
void ks_blob_results_get_blob_measure(const ks_blob_results *results,
                                      int32_t measure, int32_t id,
                                      double *value, ks_status *status);

/* CogBlobResult.GetMeasure (KS_FAILURE_BAD_PARAMETER for a measure that is
   not computed) and GetBoundingBox (principal, selected space, extrema
   angle, pixel aligned). */
void ks_blob_result_get_measure(const ks_blob_result *result,
                                int32_t measure, double *value,
                                ks_status *status);
void ks_blob_result_get_bounding_box(const ks_blob_result *result,
                                     int32_t axis, ks_rectangle_affine *box,
                                     ks_status *status);

/* CogBlobResult.GetBoundary: a new polygon (ks_polygon_destroy frees it),
   the outer boundary of the feature along its pixel edges in the selected
   space. */
void ks_blob_results_get_boundary(const ks_blob_results *results, int32_t id,
                                  ks_polygon **boundary, ks_status *status);

/* CogBlobResult.GetBoundingBoxAtAngle (on the results, by id): the
   smallest rectangle around the feature's pixel squares along the axes at
   angle (radians, finite, within +/-KS_BLOB_MAX_EXTREMA_ANGLE) in the
   selected space, rotation = angle, no skew. KS_FAILURE_BAD_PARAMETER for
   an id no feature has or a bad angle. */
void ks_blob_results_get_bounding_box_at_angle(const ks_blob_results *results,
                                               int32_t id, double angle,
                                               ks_rectangle_affine *box,
                                               ks_status *status);

/* CogBlobResult.GetMedianX / GetMedianY (on the results, by id): the
   median of the x (y) coordinates of the feature's pixel centres in the
   frame of the measures of the box of axis (KS_BLOB_AXIS_*): principal,
   along the principal axes from the centre of mass; selected space and
   pixel aligned, the selected space; extrema angle, the measure
   median_extrema_angle_x (_y). The middle value, or the mean of the two
   middle values for an even number of pixels. KS_FAILURE_BAD_PARAMETER
   for an id no feature has or a bad axis; KS_FAILURE_OUT_OF_MEMORY. */
void ks_blob_results_get_median_x(const ks_blob_results *results, int32_t id,
                                  int32_t axis, double *median,
                                  ks_status *status);
void ks_blob_results_get_median_y(const ks_blob_results *results, int32_t id,
                                  int32_t axis, double *median,
                                  ks_status *status);

/* A new 16-bit image of the input image's size: id + 1 at the pixels of
   each feature (of those that passed the filter when filtered = 1), 0
   elsewhere. KS_FAILURE_IMAGE_NO_PIXELS for NULL results. */
void ks_blob_results_create_blob_id_image(const ks_blob_results *results,
                                          int32_t filtered,
                                          ks_image_16_grey **image,
                                          ks_status *status);

/* CogBlobResults.CreateBlobImage (filtered, viewable, background): a new
   8-bit image of the input image's size with the features (all, or those
   that passed the filter when filtered = 1) painted onto a background.
   viewable = 1: background 128, holes 0, blobs 255 (soft segmentation:
   192 .. 255 by level; Labeled: 96 .. 255 by label). viewable = 0:
   background `background` (0 .. 255), holes 0, blobs their segmented
   value (1, or the level 1 .. softness + 1), Labeled blobs their label.
   KS_FAILURE_IMAGE_NO_PIXELS for NULL results. */
void ks_blob_results_create_blob_image(const ks_blob_results *results,
                                       int32_t filtered, int32_t viewable,
                                       int32_t background,
                                       ks_image_8_grey **image,
                                       ks_status *status);

/* CogBlobResults.CreateSegmentedImage (whichImage, stretchIt): a new 8-bit
   image of the input image's size holding the segmented image of stage
   which (KS_BLOB_SEGMENTED_*): the levels (0 or 1, or 0 .. softness + 1),
   0 outside the region's bounding rectangle, or with stretch_it = 1
   level * 255 / (softness + 1). *image is NULL (with success) when the
   run did not save that stage (run parameters save_segmented_image*).
   KS_FAILURE_IMAGE_NO_PIXELS for NULL results. */
void ks_blob_results_create_segmented_image(const ks_blob_results *results,
                                            int32_t which,
                                            int32_t stretch_it,
                                            ks_image_8_grey **image,
                                            ks_status *status);

#ifdef __cplusplus
}
#endif

#endif /* AMV_BLOB_H */
