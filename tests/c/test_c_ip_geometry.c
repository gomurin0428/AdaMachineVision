/*
 * C tests of the image processing geometry tools (include/amv_ip_geometry.h):
 * the affine transform, copy region, two-image, image convert and polar
 * unwrap tools, on small images whose results are known exactly, with NULL
 * handles, bad codes, NaN and the layouts of the run parameter structs.
 */

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "amv.h"
#include "c_test_support.h"

void test_c_ip_geometry(void);

/* A width x height image whose pixel (x, y) is (7 x + 13 y) mod 256. */
static ks_image_8_grey *pattern_image(int32_t width, int32_t height)
{
    ks_image_8_grey *image = NULL;
    ks_status status;
    int32_t x, y;

    ks_image_8_grey_create(width, height, 0, &image, &status);
    for (y = 0; y < height; y++)
        for (x = 0; x < width; x++)
            ks_image_8_grey_set_pixel(image, x, y,
                                      (uint8_t)((7 * x + 13 * y) % 256),
                                      &status);
    return image;
}

static int pixel(const ks_image_8_grey *image, int32_t x, int32_t y)
{
    ks_status status;
    uint8_t value = 0;

    ks_image_8_grey_get_pixel(image, x, y, &value, &status);
    return status.failure == KS_FAILURE_NONE ? value : -1;
}

static int size_is(const ks_image_8_grey *image, int32_t width,
                   int32_t height)
{
    ks_status status;
    int32_t w = -1, h = -1;

    ks_image_8_grey_width(image, &w, &status);
    ks_image_8_grey_height(image, &h, &status);
    return w == width && h == height;
}

static const ks_transform_2d_linear identity = {1.0, 0.0, 0.0, 1.0, 0.0,
                                                0.0};

static void test_affine_transform(void)
{
    ks_status status;
    ks_affine_transform params;
    ks_rectangle_affine region = {14.5, 11.5, 20.0, 12.0, 0.0, 0.0};
    ks_image_8_grey *image = pattern_image(40, 30);
    ks_image_8_grey *output = NULL, *mask = NULL;
    ks_transform_2d_linear root;
    int x, y, same = 1;

    memset(&params, 0xFF, sizeof params);
    ks_affine_transform_run_params_default(&params);
    check(params.scaling_x == 1.0 && params.scaling_y == 1.0
              && params.sampling_mode
                     == KS_AFFINE_TRANSFORM_SAMPLING_MODE_BILINEAR_ACCURATE
              && params.clip_mode == KS_AFFINE_TRANSFORM_CLIP_MODE_ZEROES
              && params.clip_fill_value == 0,
          "affine transform: the defaults");

    /* Corner origin (4.5, 5.5): output (i, j) is input (5 + i, 6 + j). */
    ks_affine_transform_execute(image, &region, &identity, &identity,
                                &params, 1, &output, &mask, &root, &status);
    check(status.failure == KS_FAILURE_NONE && size_is(output, 20, 12)
              && size_is(mask, 20, 12),
          "affine transform: a 20 x 12 crop with its mask");
    for (y = 0; y < 12; y++)
        for (x = 0; x < 20; x++)
            same = same && pixel(output, x, y) == pixel(image, 5 + x, 6 + y)
                && pixel(mask, x, y) == 255;
    check(same, "affine transform: the exact crop, nothing clipped");
    check(root.a == 1.0 && root.d == 1.0 && root.b == 0.0 && root.c == 0.0
              && fabs(root.translation_x + 5.0) < 1e-12
              && fabs(root.translation_y + 6.0) < 1e-12,
          "affine transform: the output's pixel-from-root transform");
    ks_image_8_grey_destroy(&output, &status);
    ks_image_8_grey_destroy(&mask, &status);

    /* Errors. */
    ks_affine_transform_execute(NULL, &region, &identity, &identity, &params,
                                0, &output, &mask, &root, &status);
    check(is_failure(&status, KS_FAILURE_IMAGE_NO_PIXELS,
                     "InputImage has no pixels")
              && output == NULL && mask == NULL,
          "affine transform: a NULL image");
    params.sampling_mode = KS_AFFINE_TRANSFORM_SAMPLING_MODE_HIGH_PRECISION;
    ks_affine_transform_execute(image, &region, &identity, &identity,
                                &params, 0, &output, &mask, &root, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "RunParams.SamplingMode HighPrecision is not "
                     "implemented"),
          "affine transform: HighPrecision is not implemented");
    ks_affine_transform_run_params_default(&params);
    params.scaling_y = NAN;
    ks_affine_transform_execute(image, &region, &identity, &identity,
                                &params, 0, &output, &mask, &root, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "RunParams.ScalingY must be in 0.001 .. 1000"),
          "affine transform: a NaN scaling");
    ks_affine_transform_run_params_default(&params);
    region.side_x_length = 40000.0;
    ks_affine_transform_execute(image, &region, &identity, &identity,
                                &params, 0, &output, &mask, &root, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER && output == NULL,
          "affine transform: an output above 32767 pixels");
    region.side_x_length = 20.0;
    params.clip_mode = KS_AFFINE_TRANSFORM_CLIP_MODE_ERROR;
    region.center_x = 5.0;
    ks_affine_transform_execute(image, &region, &identity, &identity,
                                &params, 0, &output, &mask, &root, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Region lies partly outside InputImage "
                     "(RunParams.ClipMode is Error)")
              && output == NULL,
          "affine transform: clipping with ClipMode Error");
    ks_image_8_grey_destroy(&image, &status);
}

static void test_copy_region(void)
{
    ks_status status;
    ks_copy_region params;
    ks_image_8_grey *image = pattern_image(20, 10);
    ks_image_8_grey *output = NULL;
    ks_pixel_region *region = NULL;
    ks_rectangle rectangle = {4.6, 3.2, 5.0, 3.0};
    ks_transform_2d_linear root;
    int x, y, same = 1;

    memset(&params, 0xFF, sizeof params);
    ks_copy_region_run_params_default(&params);
    check(params.fill_bounding_box == 1 && params.fill_bounding_box_value == 0
              && params.fill_region == 0 && params.fill_region_value == 255
              && params.region_mode
                     == KS_REGION_MODE_PIXEL_ALIGNED_BOUNDING_BOX_ADJUST_MASK,
          "copy region: the defaults");

    /* Pixel centres 5 .. 9 by 4 .. 6. */
    ks_pixel_region_rasterize_rectangle(20, 10, &identity, &rectangle,
                                        &region, &status);
    ks_copy_region_execute(image, region, &identity, &params, &output, &root,
                           &status);
    check(status.failure == KS_FAILURE_NONE && size_is(output, 5, 3),
          "copy region: the bounding box of a rectangle");
    for (y = 0; y < 3; y++)
        for (x = 0; x < 5; x++)
            same = same && pixel(output, x, y) == pixel(image, 5 + x, 4 + y);
    check(same && root.translation_x == -5.0 && root.translation_y == -4.0,
          "copy region: the exact crop and its pixel-from-root transform");
    ks_image_8_grey_destroy(&output, &status);

    params.fill_region = 1;
    params.fill_region_value = 99;
    ks_copy_region_execute(image, region, &identity, &params, &output, &root,
                           &status);
    check(status.failure == KS_FAILURE_NONE && pixel(output, 0, 0) == 99
              && pixel(output, 4, 2) == 99,
          "copy region: FillRegion");
    ks_image_8_grey_destroy(&output, &status);
    ks_pixel_region_destroy(&region, &status);

    ks_copy_region_execute(image, NULL, &identity, &params, &output, &root,
                           &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Region covers no pixel of InputImage")
              && output == NULL,
          "copy region: the empty region");
    ks_copy_region_execute(NULL, NULL, &identity, &params, &output, &root,
                           &status);
    check(status.failure == KS_FAILURE_IMAGE_NO_PIXELS && output == NULL,
          "copy region: a NULL image");
    ks_pixel_region_whole_image(20, 10, &region, &status);
    params.region_mode = KS_REGION_MODE_AFFINE_TRANSFORM;
    ks_copy_region_execute(image, region, &identity, &params, &output, &root,
                           &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "RunParams.RegionMode AffineTransform is not "
                     "implemented"),
          "copy region: RegionMode AffineTransform");
    ks_pixel_region_destroy(&region, &status);
    ks_image_8_grey_destroy(&image, &status);
}

static void test_two_image(void)
{
    ks_status status;
    ks_ip_two_image_add add;
    ks_ip_two_image_subtract subtract;
    ks_ip_two_image_min_max min_max;
    ks_image_8_grey *a = pattern_image(9, 5);
    ks_image_8_grey *b = NULL, *c = pattern_image(8, 5);
    ks_image_8_grey *output = NULL;
    int x, y, same = 1;

    ks_image_8_grey_create(9, 5, 200, &b, &status);
    memset(&add, 0xFF, sizeof add);
    memset(&subtract, 0xFF, sizeof subtract);
    memset(&min_max, 0xFF, sizeof min_max);
    ks_ip_two_image_add_run_params_default(&add);
    ks_ip_two_image_subtract_run_params_default(&subtract);
    ks_ip_two_image_min_max_run_params_default(&min_max);
    check(add.overflow_mode == KS_IP_TWO_IMAGE_ADD_OVERFLOW_MODE_BOUNDED
              && subtract.overflow_mode
                     == KS_IP_TWO_IMAGE_SUBTRACT_OVERFLOW_MODE_BOUNDED
              && min_max.operation == KS_IP_TWO_IMAGE_MIN_MAX_OPERATION_MIN,
          "two images: the defaults");

    ks_ip_two_image_add_execute(a, b, &add, &output, &status);
    check(status.failure == KS_FAILURE_NONE && size_is(output, 9, 5),
          "two images: add");
    for (y = 0; y < 5; y++)
        for (x = 0; x < 9; x++) {
            int p = pixel(a, x, y);
            same = same && pixel(output, x, y) == (p + 200 > 255 ? 255
                                                                 : p + 200);
        }
    check(same, "two images: add bounded");
    ks_image_8_grey_destroy(&output, &status);

    subtract.overflow_mode = KS_IP_TWO_IMAGE_SUBTRACT_OVERFLOW_MODE_ABSOLUTE;
    ks_ip_two_image_subtract_execute(a, b, &subtract, &output, &status);
    same = status.failure == KS_FAILURE_NONE;
    for (y = 0; y < 5 && same; y++)
        for (x = 0; x < 9; x++)
            same = same
                && pixel(output, x, y) == abs(pixel(a, x, y) - 200);
    check(same, "two images: subtract absolute");
    ks_image_8_grey_destroy(&output, &status);

    min_max.operation = KS_IP_TWO_IMAGE_MIN_MAX_OPERATION_MAX;
    ks_ip_two_image_min_max_execute(a, a, &min_max, &output, &status);
    check(status.failure == KS_FAILURE_NONE && pixel(output, 3, 2) == 47,
          "two images: max of an image with itself");
    ks_image_8_grey_destroy(&output, &status);

    ks_ip_two_image_add_execute(a, c, &add, &output, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "InputImageB is 8 x 5 pixels but InputImageA is 9 x 5")
              && output == NULL,
          "two images: sizes differ");
    ks_ip_two_image_add_execute(a, NULL, &add, &output, &status);
    check(is_failure(&status, KS_FAILURE_IMAGE_NO_PIXELS,
                     "InputImageB has no pixels"),
          "two images: a NULL B");
    add.overflow_mode = 7;
    ks_ip_two_image_add_execute(a, b, &add, &output, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER && output == NULL,
          "two images: a bad overflow mode");
    ks_image_8_grey_destroy(&a, &status);
    ks_image_8_grey_destroy(&b, &status);
    ks_image_8_grey_destroy(&c, &status);
}

static void test_image_convert(void)
{
    ks_status status;
    ks_image_convert_run_params params;
    ks_image_8_grey *red = NULL, *green = NULL, *blue = NULL;
    ks_image_16_grey *deep = NULL;
    ks_image_8_grey *output = NULL;

    memset(&params, 0xFF, sizeof params);
    ks_image_convert_run_params_default(&params);
    check(params.run_mode == KS_IMAGE_CONVERT_RUN_MODE_INTENSITY
              && params.bayer_type == KS_IMAGE_CONVERT_BAYER_TYPE_GR
              && params.share_pels_if_possible == 0
              && params.intensity_from_weighted_rgb_red_weight == 0.299
              && params.color_from_bayer_blue_scale == 1.0,
          "image convert: the defaults");
    ks_image_24_planar_color_create(4, 3, 255, 128, 0, &red, &green, &blue,
                                    &status);
    ks_image_convert_execute(NULL, NULL, red, green, blue, &params, &output,
                             &status);
    /* (299 * 255 + 587 * 128 + 114 * 0 + 500) / 1000 = 151. */
    check(status.failure == KS_FAILURE_NONE && size_is(output, 4, 3)
              && pixel(output, 2, 1) == 151,
          "image convert: the intensity of a colour image");
    ks_image_8_grey_destroy(&output, &status);
    params.run_mode = KS_IMAGE_CONVERT_RUN_MODE_PLANE1;
    ks_image_convert_execute(NULL, NULL, red, green, blue, &params, &output,
                             &status);
    check(status.failure == KS_FAILURE_NONE && pixel(output, 0, 0) == 128,
          "image convert: Plane1");
    ks_image_8_grey_destroy(&output, &status);
    params.run_mode = KS_IMAGE_CONVERT_RUN_MODE_INTENSITY_FROM_WEIGHTED_RGB;
    params.intensity_from_weighted_rgb_red_weight = 0.5;
    params.intensity_from_weighted_rgb_green_weight = 0.5;
    params.intensity_from_weighted_rgb_blue_weight = 0.5;
    ks_image_convert_execute(NULL, NULL, red, green, blue, &params, &output,
                             &status);
    /* 0.5 * 255 + 0.5 * 128 = 191.5, rounded away from zero. */
    check(status.failure == KS_FAILURE_NONE && pixel(output, 3, 2) == 192,
          "image convert: IntensityFromWeightedRGB");
    ks_image_8_grey_destroy(&output, &status);

    ks_image_16_grey_create(3, 2, 0xABCD, &deep, &status);
    ks_image_convert_run_params_default(&params);
    ks_image_convert_execute(NULL, deep, NULL, NULL, NULL, &params, &output,
                             &status);
    check(status.failure == KS_FAILURE_NONE && pixel(output, 1, 1) == 0xAB,
          "image convert: the high byte of a 16-bit image");
    ks_image_8_grey_destroy(&output, &status);

    ks_image_convert_execute(NULL, NULL, NULL, NULL, NULL, &params, &output,
                             &status);
    check(is_failure(&status, KS_FAILURE_IMAGE_NO_PIXELS,
                     "InputImage has no pixels")
              && output == NULL,
          "image convert: no image");
    params.run_mode = KS_IMAGE_CONVERT_RUN_MODE_RGB;
    ks_image_convert_execute(NULL, NULL, red, green, blue, &params, &output,
                             &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "RunParams.RunMode RGB is not implemented"),
          "image convert: RGB is not implemented");
    ks_image_convert_run_params_default(&params);
    params.color_from_bayer_red_scale = NAN;
    ks_image_convert_execute(NULL, NULL, red, green, blue, &params, &output,
                             &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER && output == NULL,
          "image convert: a NaN scale");
    ks_image_16_grey_destroy(&deep, &status);
    ks_image_8_grey_destroy(&red, &status);
    ks_image_8_grey_destroy(&green, &status);
    ks_image_8_grey_destroy(&blue, &status);
}

static void test_polar_unwrap(void)
{
    ks_status status;
    ks_polar_unwrap params;
    ks_circular_annulus_section region = {50.0, 40.0, 10.0, 0.0,
                                          2.0 * 3.141592653589793, 2.0};
    ks_image_8_grey *image = NULL;
    ks_image_8_grey *output = NULL;
    double x = 0.0, y = 0.0, ox = 0.0, oy = 0.0;

    memset(&params, 0xFF, sizeof params);
    ks_polar_unwrap_run_params_default(&params);
    check(params.scaling_x == 1.0 && params.scaling_y == 1.0
              && params.sampling_mode
                     == KS_POLAR_UNWRAP_SAMPLING_MODE_BILINEAR_INTERPOLATION,
          "polar unwrap: the defaults");
    ks_image_8_grey_create(100, 80, 33, &image, &status);
    ks_polar_unwrap_execute(image, &region, &identity, &params, &output,
                            &status);
    /* Middle arc 2 pi 15 = 94.2 pixels, radial extent 10. */
    check(status.failure == KS_FAILURE_NONE && size_is(output, 94, 10)
              && pixel(output, 50, 5) == 33,
          "polar unwrap: a 94 x 10 strip of a flat image");
    ks_image_8_grey_destroy(&output, &status);

    ks_polar_unwrap_get_input_point_from_output_point(
        &region, &identity, &identity, &params, 23.0, 4.5, &x, &y, &status);
    /* Angle 23.5 / 94 * 2 pi = pi / 2, radius 10 + 5 = 15. */
    check(status.failure == KS_FAILURE_NONE && fabs(x - 50.0) < 1e-9
              && fabs(y - 55.0) < 1e-9,
          "polar unwrap: an output point maps to the input");
    ks_polar_unwrap_get_output_point_from_input_point(
        &region, &identity, &identity, &params, x, y, 0, &ox, &oy, &status);
    check(status.failure == KS_FAILURE_NONE && fabs(ox - 23.0) < 1e-9
              && fabs(oy - 4.5) < 1e-9,
          "polar unwrap: and back");
    ks_polar_unwrap_get_output_point_from_input_point(
        &region, &identity, &identity, &params, 50.0, 40.0, 0, &ox, &oy,
        &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "the centre of Region has no output point"),
          "polar unwrap: the centre");

    ks_polar_unwrap_execute(NULL, &region, &identity, &params, &output,
                            &status);
    check(status.failure == KS_FAILURE_IMAGE_NO_PIXELS && output == NULL,
          "polar unwrap: a NULL image");
    region.radius = 45.0;
    ks_polar_unwrap_execute(image, &region, &identity, &params, &output,
                            &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Region lies partly outside InputImage")
              && output == NULL,
          "polar unwrap: a section reaching outside the image");
    region.radius = 10.0;
    region.radial_scale = 1.0;
    ks_polar_unwrap_execute(image, &region, &identity, &params, &output,
                            &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER && output == NULL,
          "polar unwrap: RadialScale 1");
    region.radial_scale = 2.0;
    ks_polar_unwrap_get_input_point_from_output_point(
        &region, &identity, &identity, &params, NAN, 0.0, &x, &y, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER && x == 0.0 && y == 0.0,
          "polar unwrap: a NaN output point");
    ks_image_8_grey_destroy(&image, &status);
}

void test_c_ip_geometry(void)
{
    test_affine_transform();
    test_copy_region();
    test_two_image();
    test_image_convert();
    test_polar_unwrap();
}
