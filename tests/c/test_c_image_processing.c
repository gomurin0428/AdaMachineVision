/*
 * C tests of the image processing filters (include/amv_image_processing.h):
 * the histogram, pixel map, Sobel edge and image sharpness tools, on small
 * images whose results are known exactly, with NULL handles, bad
 * parameters and the layouts of the run parameter structs.
 */

#include <math.h>
#include <stdio.h>
#include <string.h>

#include "amv.h"
#include "c_test_support.h"

void test_c_image_processing(void);

/* A width x height image: left in the columns before first_right, right
   from it on. */
static ks_image_8_grey *step_image(int32_t width, int32_t height,
                                   uint8_t left, uint8_t right,
                                   int32_t first_right)
{
    ks_image_8_grey *image = NULL;
    ks_status status;
    int32_t x, y;

    ks_image_8_grey_create(width, height, left, &image, &status);
    for (y = 0; y < height; y++)
        for (x = first_right; x < width; x++)
            ks_image_8_grey_set_pixel(image, x, y, right, &status);
    return image;
}

static int pixel(const ks_image_8_grey *image, int32_t x, int32_t y)
{
    ks_status status;
    uint8_t value = 0;

    ks_image_8_grey_get_pixel(image, x, y, &value, &status);
    return status.failure == KS_FAILURE_NONE ? value : -1;
}

static void test_histogram(void)
{
    ks_status status;
    ks_histogram params;
    ks_histogram_result *result = NULL;
    ks_histogram_statistics st;
    ks_pixel_region *region = NULL;
    ks_image_8_grey *image = step_image(10, 8, 10, 30, 5);
    int32_t count = -1, level = -1;

    memset(&params, 0xFF, sizeof params);
    ks_histogram_run_params_default(&params);
    check(params.bin_mode == KS_HISTOGRAM_BIN_MODE_AUTO
              && params.num_bins == 256,
          "histogram: the defaults");

    /* 40 pixels of 10 and 40 of 30. */
    ks_pixel_region_whole_image(10, 8, &region, &status);
    ks_histogram_execute(image, region, &params, &result, &status);
    check(status.failure == KS_FAILURE_NONE && result != NULL,
          "histogram: execute succeeds");
    ks_histogram_result_statistics(result, &st, &status);
    check(status.failure == KS_FAILURE_NONE && st.num_samples == 80
              && st.mean == 20.0 && st.variance == 100.0
              && st.standard_deviation == 10.0 && st.minimum == 10
              && st.maximum == 30 && st.median == 10 && st.mode == 10
              && st.num_bins == 256,
          "histogram: the statistics of two levels");
    ks_histogram_result_bin(result, 30, &count, &status);
    check(status.failure == KS_FAILURE_NONE && count == 40,
          "histogram: bin 30");
    ks_histogram_result_bin(result, 11, &count, &status);
    check(status.failure == KS_FAILURE_NONE && count == 0,
          "histogram: an empty bin");
    ks_histogram_result_bin(result, 256, &count, &status);
    check(is_failure(&status, KS_FAILURE_INDEX_OUT_OF_RANGE,
                     "GetHistogram: index 256 is outside 0 .. 255")
              && count == 0,
          "histogram: a bin index beyond the bins");
    ks_histogram_result_inverse_cumulative_grey_level(result, 51, &level,
                                                      &status);
    check(status.failure == KS_FAILURE_NONE && level == 30,
          "histogram: 51 percent of the samples are <= 30");
    ks_histogram_result_inverse_cumulative_grey_level(result, 101, &level,
                                                      &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "GetInverseCumulativeGreyLevel: percent must be in "
                     "0 .. 100"),
          "histogram: percent 101");
    /* 40 pixels of 10 and 40 of 30: every T in 11 .. 30 splits them, the
       smallest wins. */
    ks_histogram_result_minimum_wgv_threshold(result, &level, &status);
    check(status.failure == KS_FAILURE_NONE && level == 11,
          "histogram: the minimum within-group variance threshold");
    ks_histogram_result_minimum_wgv_threshold(NULL, &level, &status);
    check(status.failure == KS_FAILURE_OTHER && level == 0,
          "histogram: the threshold of no result");
    ks_histogram_result_destroy(&result, &status);
    check(status.failure == KS_FAILURE_NONE && result == NULL,
          "histogram: destroy");

    /* Uniform bins: 10 and 30 fall into bin 0 of 4 (0 .. 63). */
    params.bin_mode = KS_HISTOGRAM_BIN_MODE_UNIFORM;
    params.num_bins = 4;
    ks_histogram_execute(image, region, &params, &result, &status);
    ks_histogram_result_bin(result, 0, &count, &status);
    check(status.failure == KS_FAILURE_NONE && count == 80,
          "histogram: uniform bins");
    ks_histogram_result_destroy(&result, &status);

    /* No samples, bad parameters, NULL handles. */
    ks_histogram_run_params_default(&params);
    ks_histogram_execute(image, NULL, &params, &result, &status);
    ks_histogram_result_statistics(result, &st, &status);
    check(status.failure == KS_FAILURE_NONE && st.num_samples == 0
              && st.mean == 0.0 && st.num_bins == 256,
          "histogram: the empty region has no samples");
    ks_histogram_result_destroy(&result, &status);
    params.num_bins = 0;
    ks_histogram_execute(image, region, &params, &result, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "RunParams.NumBins must be in 1 .. 65536")
              && result == NULL,
          "histogram: num_bins 0");
    ks_histogram_run_params_default(&params);
    ks_histogram_execute(NULL, region, &params, &result, &status);
    check(is_failure(&status, KS_FAILURE_IMAGE_NO_PIXELS,
                     "InputImage has no pixels")
              && result == NULL,
          "histogram: a NULL image");
    ks_histogram_result_statistics(NULL, &st, &status);
    check(is_failure(&status, KS_FAILURE_OTHER,
                     "Result: the histogram tool has no result"),
          "histogram: the statistics of a NULL result");

    /* An input image mask: restrict the region first. A 4 x 8 mask of 0
       over columns 6 .. 9 leaves the 40 pixels of 10 and column 5 of 30. */
    {
        ks_image_8_grey *mask = NULL;
        ks_pixel_region *masked = NULL;

        ks_image_8_grey_create(4, 8, 0, &mask, &status);
        ks_pixel_region_restrict_to_mask(region, mask, 6, 0, &masked,
                                         &status);
        ks_histogram_execute(image, masked, &params, &result, &status);
        ks_histogram_result_statistics(result, &st, &status);
        check(status.failure == KS_FAILURE_NONE && st.num_samples == 48
                  && st.minimum == 10 && st.maximum == 30 && st.mode == 10,
              "histogram: the samples a mask leaves");
        ks_histogram_result_bin(result, 30, &count, &status);
        check(status.failure == KS_FAILURE_NONE && count == 8,
              "histogram: bin 30 with a mask");
        ks_histogram_result_destroy(&result, &status);
        ks_pixel_region_destroy(&masked, &status);
        ks_image_8_grey_destroy(&mask, &status);
    }

    /* RegionMode PixelAlignedBoundingBox: a region without column 3
       (72 pixels) has the whole image as its box (80 pixels). */
    {
        ks_image_8_grey *mask = NULL;
        ks_pixel_region *holed = NULL;
        ks_pixel_region *box = NULL;
        int32_t pixels = -1;

        ks_image_8_grey_create(1, 8, 0, &mask, &status);
        ks_pixel_region_restrict_to_mask(region, mask, 3, 0, &holed,
                                         &status);
        ks_pixel_region_pixel_count(holed, &pixels, &status);
        check(pixels == 72, "histogram: a region without column 3");
        ks_pixel_region_bounding_box(holed, &box, &status);
        ks_pixel_region_pixel_count(box, &pixels, &status);
        check(status.failure == KS_FAILURE_NONE && pixels == 80,
              "histogram: the bounding box of that region");
        ks_pixel_region_destroy(&box, &status);
        ks_pixel_region_bounding_box(NULL, &box, &status);
        check(status.failure == KS_FAILURE_NONE && box == NULL,
              "histogram: the bounding box of the empty region");
        ks_pixel_region_destroy(&holed, &status);
        ks_image_8_grey_destroy(&mask, &status);
    }

    /* RegionMode AffineTransform: a 5 x 8 rectangle over columns 0 .. 4
       (40 pixels of 10). */
    {
        const ks_rectangle_affine rect = {2.0, 3.5, 5.0, 8.0, 0.0, 0.0};
        const ks_transform_2d_linear identity =
            {1.0, 0.0, 0.0, 1.0, 0.0, 0.0};

        ks_histogram_execute_affine(image, &rect, &identity, &params,
                                    &result, &status);
        ks_histogram_result_statistics(result, &st, &status);
        check(status.failure == KS_FAILURE_NONE && st.num_samples == 40
                  && st.minimum == 10 && st.maximum == 10,
              "histogram: execute_affine");
        ks_histogram_result_destroy(&result, &status);
        params.num_bins = 0;
        params.bin_mode = KS_HISTOGRAM_BIN_MODE_COMPATIBILITY;
        ks_histogram_execute_affine(image, &rect, &identity, &params,
                                    &result, &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "RunParams.NumBins must be in 1 .. 65536")
                  && result == NULL,
              "histogram: execute_affine checks the parameters");
        ks_histogram_run_params_default(&params);
    }

    ks_pixel_region_destroy(&region, &status);
    ks_image_8_grey_destroy(&image, &status);
}

static void test_pixel_map(void)
{
    ks_status status;
    ks_ip_one_image_pixel_map params;
    ks_image_8_grey *image = step_image(10, 8, 10, 30, 5);
    ks_image_8_grey *output = NULL;
    ks_pixel_region *region = NULL;
    ks_transform_2d_linear identity = {1.0, 0.0, 0.0, 1.0, 0.0, 0.0};
    ks_rectangle rectangle = {0.0, 0.0, 6.0, 3.0};
    int i, identity_map = 1;

    memset(&params, 0, sizeof params);
    ks_pixel_map_run_params_default(&params);
    for (i = 0; i < 256; i++)
        identity_map = identity_map && params.map[i] == i;
    check(identity_map, "pixel map: the default map is the identity");

    params.map[10] = 200;
    params.map[30] = 1;
    ks_pixel_region_rasterize_rectangle(10, 8, &identity, &rectangle,
                                        &region, &status);
    ks_pixel_map_execute(image, region, &params, &output, &status);
    check(status.failure == KS_FAILURE_NONE && output != NULL
              && pixel(output, 0, 0) == 200 && pixel(output, 6, 3) == 1
              && pixel(output, 7, 0) == 30 && pixel(output, 6, 4) == 30
              && pixel(output, 2, 7) == 10 && pixel(image, 0, 0) == 10,
          "pixel map: mapped inside the region, copied outside");
    ks_image_8_grey_destroy(&output, &status);
    ks_pixel_map_execute(image, NULL, &params, &output, &status);
    check(status.failure == KS_FAILURE_NONE && pixel(output, 0, 0) == 10,
          "pixel map: the empty region copies the image");
    ks_image_8_grey_destroy(&output, &status);
    ks_pixel_map_execute(NULL, region, &params, &output, &status);
    check(is_failure(&status, KS_FAILURE_IMAGE_NO_PIXELS,
                     "InputImage has no pixels")
              && output == NULL,
          "pixel map: a NULL image");

    ks_pixel_region_destroy(&region, &status);
    ks_image_8_grey_destroy(&image, &status);
}

static void test_sobel_edge(void)
{
    ks_status status;
    ks_sobel_edge params;
    ks_image_8_grey *image = step_image(64, 48, 50, 150, 32);
    ks_image_8_grey *magnitude = NULL, *angle = NULL, *final = NULL;
    double zero = 0.0;

    memset(&params, 0, sizeof params);
    ks_sobel_edge_run_params_default(&params);
    check(params.magnitude_scale == 1.0
              && params.post_process_mode
                     == KS_SOBEL_EDGE_POST_PROCESS_MODE_NONE
              && params.peak_detect_threshold == 20
              && params.hysteresis_threshold_low == 10
              && params.hysteresis_threshold_high == 20
              && params.hysteresis_survivor_pel_value == 255
              && params.hysteresis_non_survivor_pel_value == 0
              && params.region_mode
                     == KS_REGION_MODE_PIXEL_ALIGNED_BOUNDING_BOX,
          "sobel: the defaults");

    ks_sobel_edge_execute(image, NULL, &params, &magnitude, &angle, &final,
                          &status);
    check(status.failure == KS_FAILURE_NONE && pixel(magnitude, 32, 5) == 0
              && pixel(final, 31, 5) == 0,
          "sobel: the empty region gives zeros");
    ks_image_8_grey_destroy(&magnitude, &status);
    ks_image_8_grey_destroy(&angle, &status);
    ks_image_8_grey_destroy(&final, &status);

    {
        ks_pixel_region *region = NULL;

        ks_pixel_region_whole_image(64, 48, &region, &status);
        ks_sobel_edge_execute(image, region, &params, &magnitude, &angle,
                              &final, &status);
        check(status.failure == KS_FAILURE_NONE
                  && pixel(magnitude, 31, 5) == 100
                  && pixel(magnitude, 32, 5) == 100
                  && pixel(magnitude, 30, 5) == 0
                  && pixel(angle, 32, 5) == 0
                  && pixel(final, 32, 5) == 100,
              "sobel: a step of 100 towards +x");
        ks_image_8_grey_destroy(&magnitude, &status);
        ks_image_8_grey_destroy(&angle, &status);
        ks_image_8_grey_destroy(&final, &status);

        params.post_process_mode = KS_SOBEL_EDGE_POST_PROCESS_MODE_PEAK_DETECT;
        ks_sobel_edge_execute(image, region, &params, &magnitude, &angle,
                              &final, &status);
        check(status.failure == KS_FAILURE_NONE && pixel(final, 32, 5) == 100
                  && pixel(final, 31, 5) == 0,
              "sobel: peak detection keeps one column");
        ks_image_8_grey_destroy(&magnitude, &status);
        ks_image_8_grey_destroy(&angle, &status);
        ks_image_8_grey_destroy(&final, &status);

        params.magnitude_scale = zero / zero;
        ks_sobel_edge_execute(image, region, &params, &magnitude, &angle,
                              &final, &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "RunParams.MagnitudeScale must be in 0 .. 50")
                  && magnitude == NULL && angle == NULL && final == NULL,
              "sobel: a NaN magnitude scale");
        ks_sobel_edge_run_params_default(&params);
        ks_sobel_edge_execute(NULL, region, &params, &magnitude, &angle,
                              &final, &status);
        check(is_failure(&status, KS_FAILURE_IMAGE_NO_PIXELS,
                         "InputImage has no pixels")
                  && magnitude == NULL,
              "sobel: a NULL image");
        ks_pixel_region_destroy(&region, &status);
    }

    /* The box of a rectangle around the step: columns 20 .. 50, rows
       0 .. 10; the step's columns 31 and 32 are box columns 11 and 12. */
    {
        ks_pixel_region *box = NULL;
        ks_transform_2d_linear identity = {1.0, 0.0, 0.0, 1.0, 0.0, 0.0};
        ks_transform_2d_linear t, te;
        ks_rectangle rect = {20.0, 0.0, 30.0, 10.0};
        ks_rectangle_affine affine = {32.0, 20.0, 24.0, 16.0, 0.0, 0.0};
        ks_affine_transform aparams;
        ks_image_8_grey *expected = NULL, *mask = NULL;
        int32_t width = 0, height = 0, w2 = 0, h2 = 0;

        ks_pixel_region_rasterize_rectangle(64, 48, &identity, &rect, &box,
                                            &status);
        ks_sobel_edge_execute_in_box(image, box, &params, &magnitude, &angle,
                                     &final, &t, &status);
        ks_image_8_grey_width(magnitude, &width, &status);
        ks_image_8_grey_height(magnitude, &height, &status);
        check(width == 31 && height == 11 && pixel(magnitude, 11, 5) == 100
                  && pixel(magnitude, 12, 5) == 100
                  && pixel(magnitude, 10, 5) == 0
                  && pixel(final, 12, 0) == 100 && t.a == 1.0
                  && t.translation_x == -20.0 && t.translation_y == 0.0,
              "sobel: the region's box, and its shift");
        ks_image_8_grey_destroy(&magnitude, &status);
        ks_image_8_grey_destroy(&angle, &status);
        ks_image_8_grey_destroy(&final, &status);

        ks_sobel_edge_execute_in_box(image, NULL, &params, &magnitude,
                                     &angle, &final, &t, &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "Region covers no pixel of InputImage")
                  && magnitude == NULL,
              "sobel: the box of no region");
        params.region_mode = KS_REGION_MODE_PIXEL_ALIGNED_BOUNDING_BOX_ADJUST_MASK;
        ks_sobel_edge_execute_in_box(image, box, &params, &magnitude, &angle,
                                     &final, &t, &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "RunParams.RegionMode must be PixelAlignedBoundingBox"
                         " (1) or AffineTransform (2)")
                  && magnitude == NULL,
              "sobel: ADJUST_MASK is not a mode of the Sobel tool");

        params.region_mode = KS_REGION_MODE_AFFINE_TRANSFORM;
        ks_affine_transform_run_params_default(&aparams);
        ks_affine_transform_execute(image, &affine, &identity, &identity,
                                    &aparams, 0, &expected, &mask, &te,
                                    &status);
        ks_sobel_edge_execute_affine(image, &affine, &identity, &identity,
                                     &params, &magnitude, &angle, &final, &t,
                                     &status);
        ks_image_8_grey_width(magnitude, &width, &status);
        ks_image_8_grey_height(magnitude, &height, &status);
        ks_image_8_grey_width(expected, &w2, &status);
        ks_image_8_grey_height(expected, &h2, &status);
        {
            ks_pixel_region *whole = NULL;
            ks_image_8_grey *m2 = NULL, *a2 = NULL, *f2 = NULL;
            int32_t x, y, same = 1;
            ks_status s2;

            ks_pixel_region_whole_image(w2, h2, &whole, &s2);
            ks_sobel_edge_execute(expected, whole, &params, &m2, &a2, &f2,
                                  &s2);
            for (y = 0; y < height && y < h2; y++)
                for (x = 0; x < width && x < w2; x++)
                    same = same && pixel(magnitude, x, y) == pixel(m2, x, y)
                           && pixel(angle, x, y) == pixel(a2, x, y);
            check(status.failure == KS_FAILURE_NONE && width == w2
                      && height == h2 && same
                      && t.translation_x == te.translation_x
                      && t.translation_y == te.translation_y,
                  "sobel: the affine rectangle, resampled, then processed");
            ks_image_8_grey_destroy(&m2, &s2);
            ks_image_8_grey_destroy(&a2, &s2);
            ks_image_8_grey_destroy(&f2, &s2);
            ks_pixel_region_destroy(&whole, &s2);
        }
        ks_image_8_grey_destroy(&magnitude, &status);
        ks_image_8_grey_destroy(&angle, &status);
        ks_image_8_grey_destroy(&final, &status);
        ks_image_8_grey_destroy(&expected, &status);
        params.region_mode = KS_REGION_MODE_PIXEL_ALIGNED_BOUNDING_BOX;
        ks_sobel_edge_execute_affine(image, &affine, &identity, &identity,
                                     &params, &magnitude, &angle, &final, &t,
                                     &status);
        check(status.failure == KS_FAILURE_BAD_PARAMETER && magnitude == NULL
                  && t.a == 1.0 && t.translation_x == 0.0,
              "sobel: the affine entry needs AFFINE_TRANSFORM");
        ks_pixel_region_destroy(&box, &status);
    }
    ks_image_8_grey_destroy(&image, &status);
}

static void test_image_sharpness(void)
{
    ks_status status;
    ks_image_sharpness params;
    ks_image_8_grey *image = step_image(64, 48, 50, 150, 32);
    ks_pixel_region *region = NULL;
    double score = -1.0;

    memset(&params, 0, sizeof params);
    ks_image_sharpness_run_params_default(&params);
    check(params.mode == KS_IMAGE_SHARPNESS_MODE_GRADIENT_ENERGY
              && params.abs_diff_distance_x == 1
              && params.abs_diff_distance_y == 1
              && params.gradient_energy_low_pass_smoothing == 0
              && params.auto_correlation_noise_level == 0.0
              && params.band_pass_max_frequency == 0.45
              && params.band_pass_min_frequency == 0.25,
          "sharpness: the defaults");

    /* Dx = 50 in 2 of 64 columns: the mean of Dx^2 is 78.125. */
    ks_pixel_region_whole_image(64, 48, &region, &status);
    ks_image_sharpness_execute(image, region, &params, &score, &status);
    check(status.failure == KS_FAILURE_NONE && score == 78.125,
          "sharpness: the gradient energy of a step");
    /* One difference of 100 per row among 63 pairs. */
    params.mode = KS_IMAGE_SHARPNESS_MODE_ABS_DIFF;
    params.abs_diff_distance_y = 0;
    ks_image_sharpness_execute(image, region, &params, &score, &status);
    check(status.failure == KS_FAILURE_NONE
              && fabs(score - 100.0 / 63.0) < 1e-12,
          "sharpness: the absolute differences of a step");
    params.mode = KS_IMAGE_SHARPNESS_MODE_BAND_PASS;
    ks_image_sharpness_execute(image, region, &params, &score, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "RunParams.Mode: BandPass is not implemented")
              && score == 0.0,
          "sharpness: band pass is not implemented");
    ks_image_sharpness_run_params_default(&params);
    ks_image_sharpness_execute(image, NULL, &params, &score, &status);
    check(status.failure == KS_FAILURE_NONE && score == 0.0,
          "sharpness: the empty region scores 0");
    ks_image_sharpness_execute(NULL, region, &params, &score, &status);
    check(is_failure(&status, KS_FAILURE_IMAGE_NO_PIXELS,
                     "InputImage has no pixels"),
          "sharpness: a NULL image");

    ks_pixel_region_destroy(&region, &status);
    ks_image_8_grey_destroy(&image, &status);
}

void test_c_image_processing(void)
{
    test_histogram();
    test_pixel_map();
    test_sobel_edge();
    test_image_sharpness();
}
