/*
 * AdaMachineVision (AMV) C API: image processing filters
 * (Cognex.VisionPro.ImageProcessing): the histogram tool, the pixel map
 * tool, the Sobel edge tool and the image sharpness tool.
 *
 * The functions are the entry points of the SPARK kernels
 * AMV.Kernels.Histogram, AMV.Kernels.Pixel_Map, AMV.Kernels.Sobel_Edge
 * and AMV.Kernels.Image_Sharpness; their specs (src/amv-kernels-*.ads)
 * describe every result in detail. The conventions of amv.h apply.
 *
 * Inputs. Every tool reads an 8-bit image (NULL fails with
 * KS_FAILURE_IMAGE_NO_PIXELS, "InputImage has no pixels") and a pixel
 * region (ks_pixel_region_whole_image for the whole image, or a
 * ks_pixel_region_rasterize_* result). NULL is the empty region and is
 * not an error: the histogram then has no samples, the pixel map copies
 * the image, the Sobel images are all 0 and the sharpness score is 0.
 * Pixels of the region outside the image are ignored.
 *
 * Run parameters are structs that ks_<tool>_run_params_default fills with
 * the defaults; enumerations are int32_t codes with VisionPro's values.
 */

#ifndef AMV_IMAGE_PROCESSING_H
#define AMV_IMAGE_PROCESSING_H

#include "amv.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ------------------------------------------------------------------ */
/* Histogram tool (CogHistogramTool, CogHistogram, CogHistogramResult) */
/* ------------------------------------------------------------------ */

/* The input image mask of the histogram (CogHistogram.InputImageMask,
   InputImageMaskOffsetX, InputImageMaskOffsetY) is not a parameter of
   ks_histogram_execute: restrict the region by the mask first with
   ks_pixel_region_restrict_to_mask (amv.h) and pass the result as the
   region. This is what the Ada API does. */

/* CogHistogramBinModeConstants. */
#define KS_HISTOGRAM_BIN_MODE_COMPATIBILITY 1 /* num_bins bins; levels >=
                                                 num_bins - 1 in the last */
#define KS_HISTOGRAM_BIN_MODE_UNIFORM       2 /* num_bins (<= 256) equal
                                                 bins over 0 .. 255 */
#define KS_HISTOGRAM_BIN_MODE_AUTO          3 /* one bin per grey level */

#define KS_HISTOGRAM_MAX_BINS 65536

typedef struct {
    int32_t bin_mode; /* KS_HISTOGRAM_BIN_MODE_*, default AUTO */
    int32_t num_bins; /* 1 .. KS_HISTOGRAM_MAX_BINS, default 256 */
} ks_histogram;

/* The scalar properties of a result. Statistics are those of the grey
   levels counted (population variance); all 0 without samples. */
typedef struct {
    double  mean;
    double  standard_deviation;
    double  variance;
    int32_t minimum;
    int32_t maximum;
    int32_t median;      /* inverse cumulative grey level at 50 % */
    int32_t mode;        /* most frequent grey level, the smallest on a tie */
    int32_t num_samples; /* pixels of the region inside the image */
    int32_t num_bins;    /* 256 in AUTO mode, num_bins otherwise */
} ks_histogram_statistics;

typedef struct ks_histogram_result ks_histogram_result; /* opaque */

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
_Static_assert(sizeof(ks_histogram) == 8, "ks_histogram must be 8 bytes");
_Static_assert(sizeof(ks_histogram_statistics) == 48,
               "ks_histogram_statistics must be 48 bytes");
_Static_assert(offsetof(ks_histogram_statistics, minimum) == 24,
               "ks_histogram_statistics.minimum offset");
_Static_assert(offsetof(ks_histogram_statistics, num_bins) == 44,
               "ks_histogram_statistics.num_bins offset");
#endif

void ks_histogram_run_params_default(ks_histogram *params);
/* A new result the caller owns (NULL when the call fails). */
void ks_histogram_execute(const ks_image_8_grey *image,
                          const ks_pixel_region *region,
                          const ks_histogram *params,
                          ks_histogram_result **result, ks_status *status);
/* RegionMode AffineTransform: the histogram of every pixel of the affine
   rectangle region (in the space pixel_from_region maps to pixel
   coordinates) resampled upright as ks_affine_transform_execute does with
   its default run parameters. (RegionMode PixelAlignedBoundingBox: pass
   ks_pixel_region_bounding_box of the region to ks_histogram_execute.) */
void ks_histogram_execute_affine(
    const ks_image_8_grey *image, const ks_rectangle_affine *region,
    const ks_transform_2d_linear *pixel_from_region,
    const ks_histogram *params, ks_histogram_result **result,
    ks_status *status);
void ks_histogram_result_destroy(ks_histogram_result **result,
                                 ks_status *status);
/* The accessors fail with KS_FAILURE_OTHER for NULL ("Result: the
   histogram tool has no result"). */
void ks_histogram_result_statistics(const ks_histogram_result *result,
                                    ks_histogram_statistics *statistics,
                                    ks_status *status);
/* The count of bin index (0 .. num_bins - 1, otherwise
   KS_FAILURE_INDEX_OUT_OF_RANGE). */
void ks_histogram_result_bin(const ks_histogram_result *result,
                             int32_t index, int32_t *count,
                             ks_status *status);
/* The smallest grey level L with 100 * (samples <= L) >= percent *
   num_samples (0 without samples); percent in 0 .. 100. */
void ks_histogram_result_inverse_cumulative_grey_level(
    const ks_histogram_result *result, int32_t percent, int32_t *grey_level,
    ks_status *status);
/* GetMinimumWGVThreshold: Otsu's threshold T (1 .. 255) that minimises
   the within-group variance of the samples < T and >= T (the threshold of
   the blob tool's HARD_DYNAMIC_THRESHOLD); the minimum grey level when
   the samples hold one level, 0 without samples. */
void ks_histogram_result_minimum_wgv_threshold(
    const ks_histogram_result *result, int32_t *threshold,
    ks_status *status);

/* ------------------------------------------------------------------ */
/* Pixel map tool (CogIPOneImagePixelMap as a tool of its own)          */
/* ------------------------------------------------------------------ */

typedef struct {
    uint8_t map[256]; /* default: the identity */
} ks_ip_one_image_pixel_map;

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
_Static_assert(sizeof(ks_ip_one_image_pixel_map) == 256,
               "ks_ip_one_image_pixel_map must be 256 bytes");
#endif

void ks_pixel_map_run_params_default(ks_ip_one_image_pixel_map *params);
/* A new image of the size of image: map[value] for the pixels of the
   region, the input value elsewhere. */
void ks_pixel_map_execute(const ks_image_8_grey *image,
                          const ks_pixel_region *region,
                          const ks_ip_one_image_pixel_map *params,
                          ks_image_8_grey **output, ks_status *status);

/* ------------------------------------------------------------------ */
/* Sobel edge tool (CogSobelEdgeTool, CogSobelEdge, CogSobelEdgeResult) */
/* ------------------------------------------------------------------ */

/* CogSobelEdgePostProcessModeConstants. */
#define KS_SOBEL_EDGE_POST_PROCESS_MODE_NONE                 0
#define KS_SOBEL_EDGE_POST_PROCESS_MODE_PEAK_DETECT          1
#define KS_SOBEL_EDGE_POST_PROCESS_MODE_HYSTERESIS_THRESHOLD 2

#define KS_SOBEL_EDGE_MAX_MAGNITUDE_SCALE 50.0

typedef struct {
    double  magnitude_scale;                   /* 1.0, 0 .. 50 */
    int32_t post_process_mode;                 /* NONE */
    int32_t peak_detect_threshold;             /* 20, 0 .. 255 */
    int32_t hysteresis_threshold_low;          /* 10, 0 .. 255 */
    int32_t hysteresis_threshold_high;         /* 20, low .. 255 */
    int32_t hysteresis_survivor_pel_value;     /* 255, 0 .. 255 */
    int32_t hysteresis_non_survivor_pel_value; /* 0, 0 .. 255 */
    int32_t region_mode; /* KS_REGION_MODE_PIXEL_ALIGNED_BOUNDING_BOX or
                            AFFINE_TRANSFORM; read by the _in_box and
                            _affine entry points only */
} ks_sobel_edge;

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
_Static_assert(sizeof(ks_sobel_edge) == 40, "ks_sobel_edge must be 40 bytes");
_Static_assert(offsetof(ks_sobel_edge, region_mode) == 32,
               "ks_sobel_edge.region_mode offset");
_Static_assert(offsetof(ks_sobel_edge, post_process_mode) == 8,
               "ks_sobel_edge.post_process_mode offset");
_Static_assert(offsetof(ks_sobel_edge, hysteresis_non_survivor_pel_value)
                   == 28,
               "ks_sobel_edge.hysteresis_non_survivor_pel_value offset");
#endif

void ks_sobel_edge_run_params_default(ks_sobel_edge *params);
/* Three new images of the size of image (all NULL when the call fails):
   the edge magnitude (magnitude_scale times the grey level difference
   across the edge, rounded, at most 255), the edge angle (the gradient
   direction as a binary angle: 0 along +x, 64 along +y, 128 along -x)
   and the final magnitude after post-processing. Pixels outside the
   region are 0 in all three. */
void ks_sobel_edge_execute(const ks_image_8_grey *image,
                           const ks_pixel_region *region,
                           const ks_sobel_edge *params,
                           ks_image_8_grey **edge_magnitude_image,
                           ks_image_8_grey **edge_angle_image,
                           ks_image_8_grey **final_magnitude_image,
                           ks_status *status);

/* Region modes of CogSobelEdge.RegionMode (CogRegionModeConstants; the
   same values as in amv_ip_geometry.h). */
#ifndef KS_REGION_MODE_PIXEL_ALIGNED_BOUNDING_BOX_ADJUST_MASK
#define KS_REGION_MODE_PIXEL_ALIGNED_BOUNDING_BOX_ADJUST_MASK 0
#define KS_REGION_MODE_PIXEL_ALIGNED_BOUNDING_BOX             1
#define KS_REGION_MODE_AFFINE_TRANSFORM                       2
#endif

/* The tool's run with a region and params->region_mode
   PIXEL_ALIGNED_BOUNDING_BOX: the three images of the region's bounding
   box (every pixel of the box processed, as if the box were the whole
   image), and *output_from_input, the shift from the input's pixel
   coordinates to the box's. A NULL region fails ("Region covers no pixel
   of InputImage"). */
void ks_sobel_edge_execute_in_box(const ks_image_8_grey *image,
                                  const ks_pixel_region *region,
                                  const ks_sobel_edge *params,
                                  ks_image_8_grey **edge_magnitude_image,
                                  ks_image_8_grey **edge_angle_image,
                                  ks_image_8_grey **final_magnitude_image,
                                  ks_transform_2d_linear *output_from_input,
                                  ks_status *status);

/* The tool's run with params->region_mode AFFINE_TRANSFORM: the affine
   rectangle region (in the space pixel_from_region maps to pixel
   coordinates) resampled as ks_affine_transform_execute does with its
   default run parameters, then processed whole. *output_pixel_from_root
   is the three images' pixel-from-root transform (pixel_from_root is the
   input's). */
void ks_sobel_edge_execute_affine(
    const ks_image_8_grey *image, const ks_rectangle_affine *region,
    const ks_transform_2d_linear *pixel_from_region,
    const ks_transform_2d_linear *pixel_from_root,
    const ks_sobel_edge *params, ks_image_8_grey **edge_magnitude_image,
    ks_image_8_grey **edge_angle_image,
    ks_image_8_grey **final_magnitude_image,
    ks_transform_2d_linear *output_pixel_from_root, ks_status *status);

/* ------------------------------------------------------------------ */
/* Image sharpness tool (CogImageSharpnessTool, CogImageSharpness)      */
/* ------------------------------------------------------------------ */

/* CogImageSharpnessModeConstants. AUTO_CORRELATION and BAND_PASS are not
   implemented (KS_FAILURE_BAD_PARAMETER). */
#define KS_IMAGE_SHARPNESS_MODE_AUTO_CORRELATION 1
#define KS_IMAGE_SHARPNESS_MODE_ABS_DIFF         2
#define KS_IMAGE_SHARPNESS_MODE_BAND_PASS        4
#define KS_IMAGE_SHARPNESS_MODE_GRADIENT_ENERGY  8

#define KS_IMAGE_SHARPNESS_MAX_LOW_PASS_SMOOTHING 100

typedef struct {
    int32_t mode;                               /* GRADIENT_ENERGY */
    int32_t abs_diff_distance_x;                /* 1, >= 0 */
    int32_t abs_diff_distance_y;                /* 1, >= 0 */
    int32_t gradient_energy_low_pass_smoothing; /* 0, 0 .. 100 (sigma) */
    double  auto_correlation_noise_level;       /* 0.0, 0 .. 255 */
    double  band_pass_max_frequency;            /* 0.45, 0 .. 0.5 */
    double  band_pass_min_frequency;            /* 0.25, 0 .. max */
} ks_image_sharpness;

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
_Static_assert(sizeof(ks_image_sharpness) == 40,
               "ks_image_sharpness must be 40 bytes");
_Static_assert(offsetof(ks_image_sharpness, auto_correlation_noise_level)
                   == 16,
               "ks_image_sharpness.auto_correlation_noise_level offset");
#endif

void ks_image_sharpness_run_params_default(ks_image_sharpness *params);
/* GRADIENT_ENERGY: the mean of dx^2 + dy^2 (Sobel, grey levels per pixel)
   over the region, in [0, 32512.5]; ABS_DIFF: the mean absolute
   difference to the pixel (distance_x, distance_y) away, in [0, 255]. */
void ks_image_sharpness_execute(const ks_image_8_grey *image,
                                const ks_pixel_region *region,
                                const ks_image_sharpness *params,
                                double *score, ks_status *status);

#ifdef __cplusplus
}
#endif

#endif /* AMV_IMAGE_PROCESSING_H */
