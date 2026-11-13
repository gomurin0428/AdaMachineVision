/*
 * AdaMachineVision (AMV) C API: the IP one-image tool
 * (Cognex.VisionPro.ImageProcessing: CogIPOneImageTool, its operator
 * collection CogIPOneImageOperators and the operator classes). Included by
 * amv.h; the entry points belong to the SPARK kernel AMV.Kernels.
 * IP_One_Image, whose spec describes every operator, definition and bound
 * in full.
 *
 * An operator is one struct, ks_ip_one_image_operator: a kind
 * (KS_IP_ONE_IMAGE_KIND_*), enabled (0 or 1; a disabled operator is
 * skipped) and one member per operator class holding that class's
 * properties; only the member of the operator's own kind is used and
 * checked. ks_ip_one_image_operator_default makes the default operator of
 * a kind. The operators of a run are a list of at most
 * KS_IP_ONE_IMAGE_MAX_OPERATORS (ks_ip_one_image_operators: count, then
 * items[0 .. count - 1]), applied in order, each to the image the
 * previous one produced.
 *
 * ks_ip_one_image_execute reads an 8-bit image (NULL fails with
 * KS_FAILURE_IMAGE_NO_PIXELS, "InputImage has no pixels") and a pixel
 * region (ks_pixel_region_whole_image for the whole image, or a
 * ks_pixel_region_rasterize_* result; NULL, the empty region, gives an
 * unchanged copy): each operator changes only the pixels of the region.
 * The operators that change the pixel grid (a FLIP_ROTATE other than
 * NONE, a SUB_SAMPLER or an EXPAND with a factor above 1, a GAUSS_SAMPLER
 * with sample_x or sample_y above 1) work on the whole image; they need a
 * region that contains every pixel of the image (KS_FAILURE_BAD_PARAMETER
 * otherwise), and output_from_input then maps input pixel coordinates to
 * output pixel coordinates (the identity otherwise).
 */

#ifndef AMV_IP_ONE_IMAGE_H
#define AMV_IP_ONE_IMAGE_H

#include "amv.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Operator kinds (AMV codes: the VisionPro classes in the order of their
   names, then BOX_FILTER, THRESHOLD and UNSHARP_MASK, our own, then the
   VisionPro classes added later, in the order they were added). */
#define KS_IP_ONE_IMAGE_KIND_ADD_SUBTRACT_CONSTANT 0
#define KS_IP_ONE_IMAGE_KIND_CONVOLVE_3X3          1
#define KS_IP_ONE_IMAGE_KIND_CONVOLVE_NXM          2
#define KS_IP_ONE_IMAGE_KIND_EQUALIZE              3
#define KS_IP_ONE_IMAGE_KIND_FLIP_ROTATE           4
#define KS_IP_ONE_IMAGE_KIND_GAUSS_SAMPLER         5
#define KS_IP_ONE_IMAGE_KIND_GREY_MORPHOLOGY_NXM   6
#define KS_IP_ONE_IMAGE_KIND_MEDIAN_3X3            7
#define KS_IP_ONE_IMAGE_KIND_MEDIAN_NXM            8
#define KS_IP_ONE_IMAGE_KIND_MULTIPLY_CONSTANT     9
#define KS_IP_ONE_IMAGE_KIND_PIXEL_MAP             10
#define KS_IP_ONE_IMAGE_KIND_QUANTIZE              11
#define KS_IP_ONE_IMAGE_KIND_BOX_FILTER            12
#define KS_IP_ONE_IMAGE_KIND_THRESHOLD             13
#define KS_IP_ONE_IMAGE_KIND_UNSHARP_MASK          14
#define KS_IP_ONE_IMAGE_KIND_EXPAND                15
#define KS_IP_ONE_IMAGE_KIND_HIGH_PASS_FILTER      16
#define KS_IP_ONE_IMAGE_KIND_SUB_SAMPLER           17
#define KS_IP_ONE_IMAGE_KIND_PEL_SET               18

/* CogIPOneImageAddSubtractConstantOverflowModeConstants and
   CogIPOneImageMultiplyConstantOverflowModeConstants. */
#define KS_IP_ONE_IMAGE_OVERFLOW_MODE_BOUNDED 0
#define KS_IP_ONE_IMAGE_OVERFLOW_MODE_WRAP    1

/* CogIPOneImageBoundaryModeConstants (only REFLECTED is supported). */
#define KS_IP_ONE_IMAGE_BOUNDARY_MODE_CLIPPED   1
#define KS_IP_ONE_IMAGE_BOUNDARY_MODE_REFLECTED 2

/* CogIPOneImageConvolve3x3PositionConstants (also the index of the cell in
   kernel[]). */
#define KS_IP_ONE_IMAGE_POSITION_NORTH_WEST 0
#define KS_IP_ONE_IMAGE_POSITION_NORTH      1
#define KS_IP_ONE_IMAGE_POSITION_NORTH_EAST 2
#define KS_IP_ONE_IMAGE_POSITION_WEST       3
#define KS_IP_ONE_IMAGE_POSITION_CENTER     4
#define KS_IP_ONE_IMAGE_POSITION_EAST       5
#define KS_IP_ONE_IMAGE_POSITION_SOUTH_WEST 6
#define KS_IP_ONE_IMAGE_POSITION_SOUTH      7
#define KS_IP_ONE_IMAGE_POSITION_SOUTH_EAST 8

/* CogIPOneImageFlipRotateOperationConstants (clockwise as displayed; the
   flip, a left-right mirror, comes first). */
#define KS_IP_ONE_IMAGE_FLIP_ROTATE_NONE                    0
#define KS_IP_ONE_IMAGE_FLIP_ROTATE_ROTATE_90_DEG           1
#define KS_IP_ONE_IMAGE_FLIP_ROTATE_ROTATE_180_DEG          2
#define KS_IP_ONE_IMAGE_FLIP_ROTATE_ROTATE_270_DEG          3
#define KS_IP_ONE_IMAGE_FLIP_ROTATE_FLIP                    4
#define KS_IP_ONE_IMAGE_FLIP_ROTATE_FLIP_AND_ROTATE_90_DEG  5
#define KS_IP_ONE_IMAGE_FLIP_ROTATE_FLIP_AND_ROTATE_180_DEG 6
#define KS_IP_ONE_IMAGE_FLIP_ROTATE_FLIP_AND_ROTATE_270_DEG 7

/* CogIPOneImageMorphologyOperationConstants. */
#define KS_IP_ONE_IMAGE_MORPHOLOGY_ERODE                1
#define KS_IP_ONE_IMAGE_MORPHOLOGY_DILATE               2
#define KS_IP_ONE_IMAGE_MORPHOLOGY_OPEN                 3
#define KS_IP_ONE_IMAGE_MORPHOLOGY_CLOSE                4
#define KS_IP_ONE_IMAGE_MORPHOLOGY_DILATE_MINUS_ERODE   5
#define KS_IP_ONE_IMAGE_MORPHOLOGY_CLOSE_MINUS_ORIGINAL 6
#define KS_IP_ONE_IMAGE_MORPHOLOGY_ORIGINAL_MINUS_OPEN  7

/* CogIPOneImageQuantizeLevelConstants: 2^(code + 1) grey levels. */
#define KS_IP_ONE_IMAGE_QUANTIZE_LEVEL_S2   0
#define KS_IP_ONE_IMAGE_QUANTIZE_LEVEL_S4   1
#define KS_IP_ONE_IMAGE_QUANTIZE_LEVEL_S8   2
#define KS_IP_ONE_IMAGE_QUANTIZE_LEVEL_S16  3
#define KS_IP_ONE_IMAGE_QUANTIZE_LEVEL_S32  4
#define KS_IP_ONE_IMAGE_QUANTIZE_LEVEL_S64  5
#define KS_IP_ONE_IMAGE_QUANTIZE_LEVEL_S128 6

/* CogIPOneImageHighPassFilterProcessingModeConstants: the smoothing whose
   result HIGH_PASS_FILTER subtracts. */
#define KS_IP_ONE_IMAGE_HIGH_PASS_GAUSS  0
#define KS_IP_ONE_IMAGE_HIGH_PASS_MEAN   1
#define KS_IP_ONE_IMAGE_HIGH_PASS_MEDIAN 2

/* CogIPOneImagePelSetOperationConstants: the pixels PEL_SET writes. */
#define KS_IP_ONE_IMAGE_PEL_SET_CARE_PELS      1
#define KS_IP_ONE_IMAGE_PEL_SET_DONT_CARE_PELS 2

/* Limits. */
#define KS_IP_ONE_IMAGE_MAX_OPERATORS       16
#define KS_IP_ONE_IMAGE_MAX_KERNEL_SIZE     1001 /* morphology, median, box */
#define KS_IP_ONE_IMAGE_MAX_CONVOLVE_SIZE   15
#define KS_IP_ONE_IMAGE_MAX_CONVOLVE_VALUES 225
#define KS_IP_ONE_IMAGE_MAX_KERNEL_VALUE    1.0e6
#define KS_IP_ONE_IMAGE_MAX_SMOOTHNESS      24
#define KS_IP_ONE_IMAGE_MAX_MAGNITUDE_SHIFT 7
#define KS_IP_ONE_IMAGE_MAX_MULTIPLY_VALUE  1.0e6
#define KS_IP_ONE_IMAGE_MAX_AMOUNT          1000.0
#define KS_IP_ONE_IMAGE_MAX_SAMPLE          256 /* sample_x/y, expansion_x/y */

/* The properties of each operator class (defaults in comments). */

typedef struct {
    int32_t constant_value; /* 0; any value */
    int32_t overflow_mode;  /* BOUNDED */
} ks_ip_one_image_add_subtract_constant;

typedef struct {
    int32_t kernel_origin; /* CENTER */
    double  kernel[9];     /* by position; 1 at CENTER, 0 elsewhere */
} ks_ip_one_image_convolve_3x3;

/* Cell (col, row) is kernel[row * KS_IP_ONE_IMAGE_MAX_CONVOLVE_SIZE + col]
   whatever the size; the default has 1 at (1, 1), 0 elsewhere. */
typedef struct {
    int32_t kernel_width;  /* 3, odd, 1 .. 15 */
    int32_t kernel_height; /* 3, odd, 1 .. 15 */
    int32_t boundary_mode; /* REFLECTED */
    double  kernel[KS_IP_ONE_IMAGE_MAX_CONVOLVE_VALUES];
} ks_ip_one_image_convolve_nxm;

typedef struct {
    int32_t operation_in_pixel_space; /* NONE */
} ks_ip_one_image_flip_rotate;

/* Binomial smoothing (see AMV.Kernels.IP_One_Image): the standard
   deviation is sqrt(smoothness / 2) pixels. */
typedef struct {
    int32_t smoothness_x;    /* 2, 0 .. 24 */
    int32_t smoothness_y;    /* 2, 0 .. 24 */
    int32_t magnitude_shift; /* 0, -7 .. 7 */
    int32_t sample_x;        /* 1, 1 .. 256: keeps every sample_x-th pixel */
    int32_t sample_y;        /* 1, 1 .. 256 */
} ks_ip_one_image_gauss_sampler;

typedef struct {
    int32_t operation;     /* ERODE */
    int32_t kernel_width;  /* 3, odd, 1 .. 1001 */
    int32_t kernel_height; /* 3, odd, 1 .. 1001 */
} ks_ip_one_image_grey_morphology_nxm;

typedef struct {
    int32_t kernel_width;  /* 3, odd, 1 .. 1001 */
    int32_t kernel_height; /* 3, odd, 1 .. 1001 */
} ks_ip_one_image_median_nxm;

typedef struct {
    double  constant_value; /* 1.0, 0 .. 1.0e6 */
    int32_t overflow_mode;  /* BOUNDED */
} ks_ip_one_image_multiply_constant;

/* ks_ip_one_image_pixel_map: see amv_image_processing.h. */

typedef struct {
    int32_t levels; /* S2 */
} ks_ip_one_image_quantize;

typedef struct {
    int32_t kernel_width;  /* 3, odd, 1 .. 1001 */
    int32_t kernel_height; /* 3, odd, 1 .. 1001 */
} ks_ip_one_image_box_filter;

/* high_value where the grey level is >= threshold, low_value elsewhere. */
typedef struct {
    int32_t threshold;  /* 128, 0 .. 256 */
    int32_t low_value;  /* 0, 0 .. 255 */
    int32_t high_value; /* 255, 0 .. 255 */
} ks_ip_one_image_threshold;

/* value + amount * (value - smoothed value). */
typedef struct {
    double  amount;       /* 1.0, 0 .. 1000 */
    int32_t smoothness_x; /* 2, 0 .. 24 */
    int32_t smoothness_y; /* 2, 0 .. 24 */
} ks_ip_one_image_unsharp_mask;

/* Each pixel repeated expansion_x times along x, expansion_y along y. */
typedef struct {
    int32_t expansion_x; /* 2, 1 .. 256 */
    int32_t expansion_y; /* 2, 1 .. 256 */
} ks_ip_one_image_expand;

/* value - smoothed value + 128, limited to 0 .. 255; GAUSS uses the
   smoothness, MEAN and MEDIAN the kernel size. */
typedef struct {
    int32_t processing_mode; /* GAUSS */
    int32_t smoothness_x;    /* 2, 0 .. 24 */
    int32_t smoothness_y;    /* 2, 0 .. 24 */
    int32_t kernel_width;    /* 3, odd, 1 .. 1001 */
    int32_t kernel_height;   /* 3, odd, 1 .. 1001 */
} ks_ip_one_image_high_pass_filter;

/* Every sample_x-th pixel along x and sample_y-th along y, or with
   spatial_average the mean of each sample_x x sample_y block. */
typedef struct {
    int32_t sample_x;        /* 2, 1 .. 256 */
    int32_t sample_y;        /* 2, 1 .. 256 */
    int32_t spatial_average; /* 0 or 1, default 0 */
} ks_ip_one_image_sub_sampler;

/* pel_value in the pixels the operator's mask marks "care" (CARE_PELS) or
   "don't care" (DONT_CARE_PELS). The mask is passed with the list
   (ks_ip_one_image_execute_masked): mask pixel (u, v) lies over pixel
   (u + offset_x, v + offset_y); 0 is "don't care", any other value, and
   every pixel no mask pixel lies over, "care". */
typedef struct {
    int32_t operation;                 /* CARE_PELS */
    int32_t pel_value;                 /* 0, 0 .. 255 */
    int32_t input_image_mask_offset_x; /* 0 */
    int32_t input_image_mask_offset_y; /* 0 */
} ks_ip_one_image_pel_set;

typedef struct {
    int32_t kind;    /* KS_IP_ONE_IMAGE_KIND_*, default ADD_SUBTRACT_CONSTANT */
    int32_t enabled; /* 1 */
    ks_ip_one_image_add_subtract_constant add_subtract_constant;
    ks_ip_one_image_convolve_3x3          convolve_3x3;
    ks_ip_one_image_convolve_nxm          convolve_nxm;
    ks_ip_one_image_flip_rotate           flip_rotate;
    ks_ip_one_image_gauss_sampler         gauss_sampler;
    ks_ip_one_image_grey_morphology_nxm   grey_morphology_nxm;
    ks_ip_one_image_median_nxm            median_nxm;
    ks_ip_one_image_multiply_constant     multiply_constant;
    ks_ip_one_image_pixel_map             pixel_map;
    ks_ip_one_image_quantize              quantize;
    ks_ip_one_image_box_filter            box_filter;
    ks_ip_one_image_threshold             threshold;
    ks_ip_one_image_unsharp_mask          unsharp_mask;
    ks_ip_one_image_expand                expand;
    ks_ip_one_image_high_pass_filter      high_pass_filter;
    ks_ip_one_image_sub_sampler           sub_sampler;
    ks_ip_one_image_pel_set               pel_set;
} ks_ip_one_image_operator;

typedef struct {
    int32_t                  count; /* 0 .. KS_IP_ONE_IMAGE_MAX_OPERATORS */
    ks_ip_one_image_operator items[KS_IP_ONE_IMAGE_MAX_OPERATORS];
} ks_ip_one_image_operators;

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
_Static_assert(sizeof(ks_ip_one_image_convolve_3x3) == 80,
               "ks_ip_one_image_convolve_3x3 must be 80 bytes");
_Static_assert(sizeof(ks_ip_one_image_convolve_nxm) == 1816,
               "ks_ip_one_image_convolve_nxm must be 1816 bytes");
_Static_assert(sizeof(ks_ip_one_image_multiply_constant) == 16,
               "ks_ip_one_image_multiply_constant must be 16 bytes");
_Static_assert(sizeof(ks_ip_one_image_unsharp_mask) == 16,
               "ks_ip_one_image_unsharp_mask must be 16 bytes");
_Static_assert(sizeof(ks_ip_one_image_operator) == 2328,
               "ks_ip_one_image_operator must be 2328 bytes");
_Static_assert(offsetof(ks_ip_one_image_operator, convolve_nxm) == 96,
               "ks_ip_one_image_operator.convolve_nxm offset");
_Static_assert(offsetof(ks_ip_one_image_operator, multiply_constant)
                   == 1960,
               "ks_ip_one_image_operator.multiply_constant offset");
_Static_assert(offsetof(ks_ip_one_image_operator, pixel_map) == 1976,
               "ks_ip_one_image_operator.pixel_map offset");
_Static_assert(offsetof(ks_ip_one_image_operator, unsharp_mask) == 2256,
               "ks_ip_one_image_operator.unsharp_mask offset");
_Static_assert(offsetof(ks_ip_one_image_operator, sub_sampler) == 2300,
               "ks_ip_one_image_operator.sub_sampler offset");
_Static_assert(offsetof(ks_ip_one_image_operator, pel_set) == 2312,
               "ks_ip_one_image_operator.pel_set offset");
_Static_assert(sizeof(ks_ip_one_image_operators) == 8 + 16 * 2328,
               "ks_ip_one_image_operators must be 37256 bytes");
#endif

/* An empty list. */
void ks_ip_one_image_operators_default(ks_ip_one_image_operators *operators);

/* The default operator of a kind (the constructor of its class), enabled;
   KS_FAILURE_BAD_PARAMETER for an unknown kind. */
void ks_ip_one_image_operator_default(int32_t kind,
                                      ks_ip_one_image_operator *op,
                                      ks_status *status);

/* Item (get and set): KS_FAILURE_INDEX_OUT_OF_RANGE unless index is in
   0 .. count - 1; KS_FAILURE_BAD_PARAMETER for a count outside 0 ..
   KS_IP_ONE_IMAGE_MAX_OPERATORS (also for the functions below). */
void ks_ip_one_image_operators_item(const ks_ip_one_image_operators *operators,
                                    int32_t index,
                                    ks_ip_one_image_operator *op,
                                    ks_status *status);
void ks_ip_one_image_operators_set_item(ks_ip_one_image_operators *operators,
                                        int32_t index,
                                        const ks_ip_one_image_operator *op,
                                        ks_status *status);
/* Add: appends; KS_FAILURE_BAD_PARAMETER when the list is full. */
void ks_ip_one_image_operators_add(ks_ip_one_image_operators *operators,
                                   const ks_ip_one_image_operator *op,
                                   ks_status *status);
/* Insert (value, index): index in 0 .. count. */
void ks_ip_one_image_operators_insert(ks_ip_one_image_operators *operators,
                                      const ks_ip_one_image_operator *op,
                                      int32_t index, ks_status *status);
/* RemoveAt: index in 0 .. count - 1. */
void ks_ip_one_image_operators_remove_at(
    ks_ip_one_image_operators *operators, int32_t index, ks_status *status);
/* Move: the item at from_index ends at to_index (both in 0 .. count - 1). */
void ks_ip_one_image_operators_move(ks_ip_one_image_operators *operators,
                                    int32_t from_index, int32_t to_index,
                                    ks_status *status);
/* The count of a list and the kind and enabled flag of an operator,
   checked: KS_FAILURE_BAD_PARAMETER (and 0) when count is not valid, kind
   not an operator kind, enabled not 0 or 1 (a record changed by hand). */
void ks_ip_one_image_operators_count(
    const ks_ip_one_image_operators *operators, int32_t *count,
    ks_status *status);
void ks_ip_one_image_operator_get_kind(const ks_ip_one_image_operator *op,
                                       int32_t *kind, ks_status *status);
void ks_ip_one_image_operator_get_enabled(const ks_ip_one_image_operator *op,
                                          int32_t *enabled,
                                          ks_status *status);

/* GetKernelValue / SetKernelValue (col, row) of ConvolveNxM:
   KS_FAILURE_BAD_PARAMETER unless 0 <= col < kernel_width and 0 <= row <
   kernel_height (and, for set, the value is finite and within
   +/-KS_IP_ONE_IMAGE_MAX_KERNEL_VALUE). */
void ks_ip_one_image_convolve_nxm_get_kernel_value(
    const ks_ip_one_image_convolve_nxm *params, int32_t col, int32_t row,
    double *value, ks_status *status);
void ks_ip_one_image_convolve_nxm_set_kernel_value(
    ks_ip_one_image_convolve_nxm *params, int32_t col, int32_t row,
    double new_value, ks_status *status);
/* GetKernelValue / SetKernelValue (position) of Convolve3x3. */
void ks_ip_one_image_convolve_3x3_get_kernel_value(
    const ks_ip_one_image_convolve_3x3 *params, int32_t position,
    double *value, ks_status *status);
void ks_ip_one_image_convolve_3x3_set_kernel_value(
    ks_ip_one_image_convolve_3x3 *params, int32_t position, double value,
    ks_status *status);

/* SigmaX / SigmaY of GAUSS_SAMPLER and HIGH_PASS_FILTER (read only): the
   standard deviation in pixels of the binomial smoothing, sqrt(smoothness
   / 2); 0.0 for a smoothness outside 0 .. 24. */
double ks_ip_one_image_sigma(int32_t smoothness);

/* The checks ks_ip_one_image_execute makes of the list
   (KS_FAILURE_BAD_PARAMETER, "Operators(2).KernelWidth must be an odd
   number in 1 .. 1001"). */
void ks_ip_one_image_check_operators(
    const ks_ip_one_image_operators *operators, ks_status *status);

/* Runs the enabled operators in order. *output is a new image the caller
   owns (NULL when the call fails); its size is the input's, with width
   and height swapped by each ROTATE_90_DEG, ROTATE_270_DEG,
   FLIP_AND_ROTATE_90_DEG and FLIP_AND_ROTATE_270_DEG, divided (rounding
   up) by the sampling of SUB_SAMPLER and GAUSS_SAMPLER and multiplied by
   EXPAND. KS_FAILURE_BAD_PARAMETER when an image of the list would have
   more than KS_IMAGE_MAX_PIXELS pixels. */
void ks_ip_one_image_execute(const ks_image_8_grey *image,
                             const ks_pixel_region *region,
                             const ks_ip_one_image_operators *operators,
                             ks_image_8_grey **output,
                             ks_transform_2d_linear *output_from_input,
                             ks_status *status);

/* ks_ip_one_image_execute with the InputImageMask of each operator:
   masks[i] (NULL for none) belongs to operators->items[i]; masks may be
   NULL (no masks at all) or must point at KS_IP_ONE_IMAGE_MAX_OPERATORS
   handles. An enabled PEL_SET needs a mask (KS_FAILURE_BAD_PARAMETER,
   "Operators(2).InputImageMask is not set"); ks_ip_one_image_execute
   passes no masks. */
void ks_ip_one_image_execute_masked(
    const ks_image_8_grey *image, const ks_pixel_region *region,
    const ks_ip_one_image_operators *operators,
    const ks_image_8_grey *const masks[KS_IP_ONE_IMAGE_MAX_OPERATORS],
    ks_image_8_grey **output, ks_transform_2d_linear *output_from_input,
    ks_status *status);

/* Region modes of CogIPOneImageTool.RegionMode (CogRegionModeConstants;
   the same values as in amv_ip_geometry.h). */
#ifndef KS_REGION_MODE_PIXEL_ALIGNED_BOUNDING_BOX_ADJUST_MASK
#define KS_REGION_MODE_PIXEL_ALIGNED_BOUNDING_BOX_ADJUST_MASK 0
#define KS_REGION_MODE_PIXEL_ALIGNED_BOUNDING_BOX             1
#define KS_REGION_MODE_AFFINE_TRANSFORM                       2
#endif

/* The tool's run with a region in the mode region_mode
   (PIXEL_ALIGNED_BOUNDING_BOX or PIXEL_ALIGNED_BOUNDING_BOX_ADJUST_MASK):
   the operators run on the bounding box of the region, as if the box were
   the whole image, and *output is the box (NULL when the call fails).
   With ADJUST_MASK the first enabled operator changes only the region's
   pixels of the box and the others process the whole box; that first
   operator may change the pixel grid only when the region fills its box.
   *output_from_input maps input pixel coordinates to output pixel
   coordinates (a shift by the box's corner, then the operators' changes
   of the pixel grid). masks as for ks_ip_one_image_execute_masked; the
   offsets of a PEL_SET mask count from the box's corner. A NULL region
   fails ("Region covers no pixel of InputImage"). */
void ks_ip_one_image_execute_in_box(
    const ks_image_8_grey *image, const ks_pixel_region *region,
    int32_t region_mode, const ks_ip_one_image_operators *operators,
    const ks_image_8_grey *const masks[KS_IP_ONE_IMAGE_MAX_OPERATORS],
    ks_image_8_grey **output, ks_transform_2d_linear *output_from_input,
    ks_status *status);

/* The tool's run in the mode AFFINE_TRANSFORM: the affine rectangle region
   (in the space pixel_from_region maps to pixel coordinates) is resampled
   as ks_affine_transform_execute does with its default run parameters,
   then the operators run on the result. *output is a new image (NULL when
   the call fails) and *output_pixel_from_root its pixel-from-root
   transform (pixel_from_root is the input image's). A PEL_SET cannot be
   the first enabled operator (KS_FAILURE_BAD_PARAMETER). */
void ks_ip_one_image_execute_affine(
    const ks_image_8_grey *image, const ks_rectangle_affine *region,
    const ks_transform_2d_linear *pixel_from_region,
    const ks_transform_2d_linear *pixel_from_root,
    const ks_ip_one_image_operators *operators,
    const ks_image_8_grey *const masks[KS_IP_ONE_IMAGE_MAX_OPERATORS],
    ks_image_8_grey **output, ks_transform_2d_linear *output_pixel_from_root,
    ks_status *status);

#ifdef __cplusplus
}
#endif

#endif /* AMV_IP_ONE_IMAGE_H */
