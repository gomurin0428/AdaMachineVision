/*
 * AdaMachineVision (AMV) C API: image processing geometry tools
 * (Cognex.VisionPro.ImageProcessing): the affine transform tool, the copy
 * region tool, the two-image tools (add, subtract, min/max), the image
 * convert tool and the polar unwrap tool.
 *
 * The functions are the entry points of the SPARK kernels
 * AMV.Kernels.Affine_Transform, AMV.Kernels.Copy_Region,
 * AMV.Kernels.IP_Two_Image, AMV.Kernels.Image_Convert and
 * AMV.Kernels.Polar_Unwrap; their specs (src/amv-kernels-*.ads) describe
 * every result in detail. The conventions of amv.h apply.
 *
 * Inputs. An 8-bit image NULL fails with KS_FAILURE_IMAGE_NO_PIXELS
 * ("InputImage has no pixels"). A region the tool takes as any region
 * (copy region) is a pixel region (ks_pixel_region_whole_image or a
 * ks_pixel_region_rasterize_* result) that lies in the image; the tools
 * that need one shape (affine transform, polar unwrap) take the shape
 * struct and the transform from the shape's space to pixel space.
 *
 * Outputs. Every output image is a new handle the caller owns (NULL when
 * the call fails). The affine transform and the copy region tools also
 * return the pixel-from-root transform the output needs so that root
 * space names the same places in input and output (pass it to
 * ks_image_set_pixel_from_root_transform for the output's state); the
 * output keeps the input's tree and selection. The polar unwrap output
 * gets a fresh tree (its root is its pixel space).
 *
 * Run parameters are structs that ks_<tool>_run_params_default fills with
 * the defaults; enumerations are int32_t codes with VisionPro's values;
 * flags are int32_t 0 or 1.
 */

#ifndef AMV_IP_GEOMETRY_H
#define AMV_IP_GEOMETRY_H

#include "amv.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ------------------------------------------------------------------ */
/* Affine transform tool (CogAffineTransformTool, CogAffineTransform)   */
/* ------------------------------------------------------------------ */

/* CogAffineTransformSamplingModeConstants (NEAREST_NEIGHBOR is AMV's;
   HIGH_PRECISION is not implemented: KS_FAILURE_BAD_PARAMETER). */
#define KS_AFFINE_TRANSFORM_SAMPLING_MODE_NEAREST_NEIGHBOR       1
#define KS_AFFINE_TRANSFORM_SAMPLING_MODE_BILINEAR_INTERPOLATION 2
#define KS_AFFINE_TRANSFORM_SAMPLING_MODE_HIGH_PRECISION         3
#define KS_AFFINE_TRANSFORM_SAMPLING_MODE_BILINEAR_ACCURATE      4

/* CogAffineTransformClipModeConstants. */
#define KS_AFFINE_TRANSFORM_CLIP_MODE_ZEROES 0
#define KS_AFFINE_TRANSFORM_CLIP_MODE_FILL   1
#define KS_AFFINE_TRANSFORM_CLIP_MODE_ERROR  2

#define KS_AFFINE_TRANSFORM_MIN_SCALING     0.001
#define KS_AFFINE_TRANSFORM_MAX_SCALING     1000.0
#define KS_AFFINE_TRANSFORM_MAX_OUTPUT_SIDE 32767

typedef struct {
    double  scaling_x;       /* 1.0, 0.001 .. 1000 */
    double  scaling_y;       /* 1.0, 0.001 .. 1000 */
    int32_t sampling_mode;   /* BILINEAR_ACCURATE */
    int32_t clip_mode;       /* ZEROES */
    int32_t clip_fill_value; /* 0, 0 .. 255 */
} ks_affine_transform;

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
_Static_assert(sizeof(ks_affine_transform) == 32,
               "ks_affine_transform must be 32 bytes");
_Static_assert(offsetof(ks_affine_transform, clip_fill_value) == 24,
               "ks_affine_transform.clip_fill_value offset");
#endif

void ks_affine_transform_run_params_default(ks_affine_transform *params);
/* Resamples region (in the space pixel_from_region maps to pixel space)
   into an upright image of round (scaling_x * side X in pixels) x
   round (scaling_y * side Y in pixels) pixels (1 .. 32767 each, else
   KS_FAILURE_BAD_PARAMETER). pixel_from_root is the input's transform;
   output_pixel_from_root the output's. With create_mask = 1, *output_mask
   is 255 where the output was sampled from the input, 0 where clipped
   (NULL with create_mask = 0). */
void ks_affine_transform_execute(const ks_image_8_grey *image,
                                 const ks_rectangle_affine *region,
                                 const ks_transform_2d_linear
                                     *pixel_from_region,
                                 const ks_transform_2d_linear
                                     *pixel_from_root,
                                 const ks_affine_transform *params,
                                 int32_t create_mask,
                                 ks_image_8_grey **output,
                                 ks_image_8_grey **output_mask,
                                 ks_transform_2d_linear
                                     *output_pixel_from_root,
                                 ks_status *status);

/* ------------------------------------------------------------------ */
/* Copy region tool (CogCopyRegionTool, CogCopyRegion)                  */
/* ------------------------------------------------------------------ */

/* CogRegionModeConstants (AFFINE_TRANSFORM is not implemented). */
#define KS_REGION_MODE_PIXEL_ALIGNED_BOUNDING_BOX_ADJUST_MASK 0
#define KS_REGION_MODE_PIXEL_ALIGNED_BOUNDING_BOX             1
#define KS_REGION_MODE_AFFINE_TRANSFORM                       2

typedef struct {
    int32_t fill_bounding_box;       /* 1 */
    int32_t fill_bounding_box_value; /* 0, 0 .. 255 */
    int32_t fill_region;             /* 0 */
    int32_t fill_region_value;       /* 255, 0 .. 255 */
    int32_t region_mode;             /* ..._ADJUST_MASK */
} ks_copy_region;

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
_Static_assert(sizeof(ks_copy_region) == 20,
               "ks_copy_region must be 20 bytes");
#endif

void ks_copy_region_run_params_default(ks_copy_region *params);
/* A new image of the size of the region's bounding box: region pixels
   copied (fill_region_value with fill_region = 1), the other pixels of
   the box fill_bounding_box_value (with fill_bounding_box = 1) or copied.
   A NULL (empty) region fails with KS_FAILURE_BAD_PARAMETER. */
void ks_copy_region_execute(const ks_image_8_grey *image,
                            const ks_pixel_region *region,
                            const ks_transform_2d_linear *pixel_from_root,
                            const ks_copy_region *params,
                            ks_image_8_grey **output,
                            ks_transform_2d_linear *output_pixel_from_root,
                            ks_status *status);

/* ------------------------------------------------------------------ */
/* Two-image tools (CogIPTwoImageAddTool, CogIPTwoImageSubtractTool,   */
/* CogIPTwoImageMinMaxTool)                                            */
/* ------------------------------------------------------------------ */

/* CogIPTwoImageAddOverflowModeConstants. */
#define KS_IP_TWO_IMAGE_ADD_OVERFLOW_MODE_BOUNDED 0 /* min (A + B, 255) */
#define KS_IP_TWO_IMAGE_ADD_OVERFLOW_MODE_WRAP    1 /* (A + B) mod 256 */
#define KS_IP_TWO_IMAGE_ADD_OVERFLOW_MODE_SHIFT   2 /* (A + B) / 2 */

/* CogIPTwoImageSubtractOverflowModeConstants. */
#define KS_IP_TWO_IMAGE_SUBTRACT_OVERFLOW_MODE_BOUNDED  0 /* max (A-B, 0) */
#define KS_IP_TWO_IMAGE_SUBTRACT_OVERFLOW_MODE_WRAP     1 /* (A-B) mod 256 */
#define KS_IP_TWO_IMAGE_SUBTRACT_OVERFLOW_MODE_SHIFT    2 /* (A-B+256)/2 */
#define KS_IP_TWO_IMAGE_SUBTRACT_OVERFLOW_MODE_ABSOLUTE 3 /* abs (A - B) */

/* CogIPTwoImageMinMaxOperationConstants. */
#define KS_IP_TWO_IMAGE_MIN_MAX_OPERATION_MIN 0
#define KS_IP_TWO_IMAGE_MIN_MAX_OPERATION_MAX 1

typedef struct {
    int32_t overflow_mode; /* BOUNDED */
} ks_ip_two_image_add;

typedef struct {
    int32_t overflow_mode; /* BOUNDED */
} ks_ip_two_image_subtract;

typedef struct {
    int32_t operation; /* MIN */
} ks_ip_two_image_min_max;

void ks_ip_two_image_add_run_params_default(ks_ip_two_image_add *params);
void ks_ip_two_image_subtract_run_params_default(
    ks_ip_two_image_subtract *params);
void ks_ip_two_image_min_max_run_params_default(
    ks_ip_two_image_min_max *params);
/* A new image of the size of image_a and image_b (which must be equal:
   KS_FAILURE_BAD_PARAMETER otherwise), each pixel the formula of the tool
   applied to the two pixels at its place (rounded down for SHIFT). */
void ks_ip_two_image_add_execute(const ks_image_8_grey *image_a,
                                 const ks_image_8_grey *image_b,
                                 const ks_ip_two_image_add *params,
                                 ks_image_8_grey **output,
                                 ks_status *status);
void ks_ip_two_image_subtract_execute(const ks_image_8_grey *image_a,
                                      const ks_image_8_grey *image_b,
                                      const ks_ip_two_image_subtract *params,
                                      ks_image_8_grey **output,
                                      ks_status *status);
void ks_ip_two_image_min_max_execute(const ks_image_8_grey *image_a,
                                     const ks_image_8_grey *image_b,
                                     const ks_ip_two_image_min_max *params,
                                     ks_image_8_grey **output,
                                     ks_status *status);

/* ------------------------------------------------------------------ */
/* Image convert tool (CogImageConvertTool, CogImageConvertRunParams)   */
/* ------------------------------------------------------------------ */

/* CogImageConvertRunModeConstants. Implemented: INTENSITY, PLANE0 ..
   PLANE2 and INTENSITY_FROM_WEIGHTED_RGB; the others fail with
   KS_FAILURE_BAD_PARAMETER. */
#define KS_IMAGE_CONVERT_RUN_MODE_INTENSITY                   1
#define KS_IMAGE_CONVERT_RUN_MODE_HSI                         2
#define KS_IMAGE_CONVERT_RUN_MODE_INTENSITY_FROM_BAYER        3
#define KS_IMAGE_CONVERT_RUN_MODE_RGB_FROM_BAYER              4
#define KS_IMAGE_CONVERT_RUN_MODE_HSI_FROM_BAYER              5
#define KS_IMAGE_CONVERT_RUN_MODE_PLANE0                      6
#define KS_IMAGE_CONVERT_RUN_MODE_PLANE1                      7
#define KS_IMAGE_CONVERT_RUN_MODE_PLANE2                      8
#define KS_IMAGE_CONVERT_RUN_MODE_RGB                         9
#define KS_IMAGE_CONVERT_RUN_MODE_INTENSITY_FROM_WEIGHTED_RGB 10
#define KS_IMAGE_CONVERT_RUN_MODE_PIXEL_FROM_RANGE            11
#define KS_IMAGE_CONVERT_RUN_MODE_MASK_FROM_RANGE             12

/* CogImageConvertBayerTypeConstants. */
#define KS_IMAGE_CONVERT_BAYER_TYPE_GR 0
#define KS_IMAGE_CONVERT_BAYER_TYPE_RG 1
#define KS_IMAGE_CONVERT_BAYER_TYPE_BG 2
#define KS_IMAGE_CONVERT_BAYER_TYPE_GB 3

typedef struct {
    int32_t run_mode;                                 /* INTENSITY */
    int32_t bayer_type;                               /* GR */
    int32_t share_pels_if_possible;                   /* 0 (ignored) */
    double  intensity_from_weighted_rgb_red_weight;   /* 0.299 */
    double  intensity_from_weighted_rgb_green_weight; /* 0.587 */
    double  intensity_from_weighted_rgb_blue_weight;  /* 0.114 */
    double  intensity_from_bayer_red_weight;          /* 0.299 */
    double  intensity_from_bayer_green_weight;        /* 0.587 */
    double  intensity_from_bayer_blue_weight;         /* 0.114 */
    double  color_from_bayer_red_scale;               /* 1.0 */
    double  color_from_bayer_green_scale;             /* 1.0 */
    double  color_from_bayer_blue_scale;              /* 1.0 */
} ks_image_convert_run_params;

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
_Static_assert(sizeof(ks_image_convert_run_params) == 88,
               "ks_image_convert_run_params must be 88 bytes");
_Static_assert(offsetof(ks_image_convert_run_params,
                        intensity_from_weighted_rgb_red_weight) == 16,
               "ks_image_convert_run_params weights offset");
#endif

void ks_image_convert_run_params_default(ks_image_convert_run_params *params);
/* The input is one image of any type: grey_8, or grey_16, or the three
   planes red, green and blue of a colour image; the other handles are
   NULL (all NULL: KS_FAILURE_IMAGE_NO_PIXELS). INTENSITY: a copy of an
   8-bit image, the high byte of a 16-bit one, (299 R + 587 G + 114 B +
   500) / 1000 of a colour one; PLANEn: one plane; INTENSITY_FROM_WEIGHTED_
   RGB: round (wr R + wg G + wb B) limited to 0 .. 255. */
void ks_image_convert_execute(const ks_image_8_grey *grey_8,
                              const ks_image_16_grey *grey_16,
                              const ks_image_8_grey *red,
                              const ks_image_8_grey *green,
                              const ks_image_8_grey *blue,
                              const ks_image_convert_run_params *params,
                              ks_image_8_grey **output, ks_status *status);

/* ------------------------------------------------------------------ */
/* Polar unwrap tool (CogPolarUnwrapTool, CogPolarUnwrap)               */
/* ------------------------------------------------------------------ */

/* CogPolarUnwrapSamplingModeConstants. */
#define KS_POLAR_UNWRAP_SAMPLING_MODE_BILINEAR_INTERPOLATION 0
#define KS_POLAR_UNWRAP_SAMPLING_MODE_NEAREST_NEIGHBOR       1

#define KS_POLAR_UNWRAP_MIN_SCALING     0.001
#define KS_POLAR_UNWRAP_MAX_SCALING     1000.0
#define KS_POLAR_UNWRAP_MAX_OUTPUT_SIDE 32767

typedef struct {
    double  scaling_x;     /* 1.0, 0.001 .. 1000 (angular) */
    double  scaling_y;     /* 1.0, 0.001 .. 1000 (radial) */
    int32_t sampling_mode; /* BILINEAR_INTERPOLATION */
} ks_polar_unwrap;

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
_Static_assert(sizeof(ks_polar_unwrap) == 24,
               "ks_polar_unwrap must be 24 bytes");
#endif

void ks_polar_unwrap_run_params_default(ks_polar_unwrap *params);
/* Unwraps region (radius > 0, radial_scale > 0 and not 1, angle_span not
   0) into an image with the angle along x and the radius along y; width
   round (scaling_x * middle arc in pixels), height round (scaling_y *
   radial extent in pixels). A sample outside the image fails with
   KS_FAILURE_BAD_PARAMETER ("Region lies partly outside InputImage"). */
void ks_polar_unwrap_execute(const ks_image_8_grey *image,
                             const ks_circular_annulus_section *region,
                             const ks_transform_2d_linear *pixel_from_region,
                             const ks_polar_unwrap *params,
                             ks_image_8_grey **output, ks_status *status);
/* The input point (in the space selected_from_region maps the region's
   space to) that the output point (within the output image's area)
   samples. */
void ks_polar_unwrap_get_input_point_from_output_point(
    const ks_circular_annulus_section *region,
    const ks_transform_2d_linear *pixel_from_region,
    const ks_transform_2d_linear *selected_from_region,
    const ks_polar_unwrap *params, double output_point_x,
    double output_point_y, double *input_point_x, double *input_point_y,
    ks_status *status);
/* The output point that samples the input point; its angle from
   angle_start in the sense of angle_span lies in [0, 2 pi) plus
   revolution turns. */
void ks_polar_unwrap_get_output_point_from_input_point(
    const ks_circular_annulus_section *region,
    const ks_transform_2d_linear *pixel_from_region,
    const ks_transform_2d_linear *region_from_selected,
    const ks_polar_unwrap *params, double input_point_x,
    double input_point_y, int32_t revolution, double *output_point_x,
    double *output_point_y, ks_status *status);

#ifdef __cplusplus
}
#endif

#endif /* AMV_IP_GEOMETRY_H */
