/*
 * Tests of the pattern location tool's C API (include/amv_pm_align.h): a
 * pattern trained on a drawn L-shaped figure (sharp, pixel-aligned edges)
 * is found shifted and turned by a quarter turn, then the failures and
 * the accessors.
 */

#include <math.h>
#include <stdio.h>

#include "amv.h"
#include "c_test_support.h"

void test_c_pm_align(void);

static const ks_transform_2d_linear identity = {1.0, 0.0, 0.0, 1.0, 0.0,
                                                0.0};

/* 1 when the cell (x, y) of the figure (around its reference point
   (0, 0)) is bright: an L of two bars and a separate square. */
static int in_figure(int32_t x, int32_t y)
{
    return (x >= -20 && x < 30 && y >= -20 && y < -5)
        || (x >= -20 && x < -5 && y >= -20 && y < 25)
        || (x >= 10 && x < 20 && y >= 5 && y < 15);
}

/* A width x height image of grey 40 with the figure in grey 200, its
   reference point at pixel (cx, cy), turned by a quarter turn
   (counter-clockwise in a y-down image) when quarter is 1. */
static ks_image_8_grey *figure_image(int32_t width, int32_t height,
                                     int32_t cx, int32_t cy, int quarter)
{
    ks_status status;
    ks_image_8_grey *image = NULL;
    int32_t x, y;

    ks_image_8_grey_create(width, height, 40, &image, &status);
    for (y = 0; y < height; y++) {
        for (x = 0; x < width; x++) {
            int32_t u = x - cx, v = y - cy;
            /* Pixel (u, v) shows the figure's cell turned back. */
            int bright = quarter ? in_figure(v, -u) : in_figure(u, v);
            if (bright) {
                ks_image_8_grey_set_pixel(image, x, y, 200, &status);
            }
        }
    }
    return image;
}

void test_c_pm_align(void)
{
    ks_status status;
    ks_pm_align_train_params train;
    ks_pm_align_run_params params;
    ks_pm_align_pattern *pattern = NULL, *copy = NULL;
    ks_pm_align_results *results = NULL;
    ks_pm_align_result item;
    ks_pm_align_feature feature;
    ks_transform_2d_linear pose;
    ks_transform_2d_linear origin = {1.0, 0.0, 0.0, 1.0, 60.0, 60.0};
    ks_pixel_region *train_region = NULL, *region = NULL;
    ks_image_8_grey *train_image, *scene, *turned;
    int32_t flag = -1, count = -1, finest = -1, coarsest = -1;
    double nan_value = 0.0;

    nan_value = nan_value / nan_value;

    ks_pm_align_train_params_default(&train, &status);
    check(status.failure == KS_FAILURE_NONE
          && train.train_algorithm == KS_PM_ALIGN_TRAIN_ALGORITHM_PAT_MAX
          && train.grain_limit_auto_select == 1
          && train.grain_limit_coarse == 8.0
          && train.grain_limit_fine == 1.0,
          "pmalign: train params default");
    ks_pm_align_run_params_default(&params, &status);
    check(status.failure == KS_FAILURE_NONE
          && params.accept_threshold == 0.5
          && params.xy_overlap == 1.0
          && params.approximate_number_to_find == 1
          && params.run_algorithm == KS_PM_ALIGN_RUN_ALGORITHM_PAT_MAX
          && params.zone_angle.configuration == KS_PM_ALIGN_ZONE_NOMINAL
          && params.zone_scale.nominal == 1.0,
          "pmalign: run params default");

    /* A NULL pattern is untrained. */
    ks_pm_align_pattern_trained(NULL, &flag, &status);
    check(status.failure == KS_FAILURE_NONE && flag == 0,
          "pmalign: trained (NULL) = 0");
    ks_pm_align_execute(NULL, NULL, &identity, NULL, &params, &results,
                        &status);
    check(is_failure(&status, KS_FAILURE_OPERATOR_NOT_TRAINED,
                     "Pattern is not trained")
          && results == NULL,
          "pmalign: execute with a NULL pattern");

    /* Train on the figure at (60, 60) of a 120 x 120 image, the origin at
       its reference point. */
    train_image = figure_image(120, 120, 60, 60, 0);
    ks_pixel_region_whole_image(120, 120, &train_region, &status);
    ks_pm_align_pattern_create(&pattern, &status);
    check(status.failure == KS_FAILURE_NONE && pattern != NULL,
          "pmalign: pattern create");
    ks_pm_align_pattern_train(pattern, NULL, train_region, &identity,
                              &origin, &status);
    check(is_failure(&status, KS_FAILURE_IMAGE_NO_PIXELS,
                     "TrainImage has no pixels"),
          "pmalign: train without image");
    ks_pm_align_pattern_train(pattern, train_image, train_region, &identity,
                              &origin, &status);
    check(status.failure == KS_FAILURE_NONE, "pmalign: train");
    ks_pm_align_pattern_trained(pattern, &flag, &status);
    check(flag == 1, "pmalign: trained");
    ks_pm_align_pattern_levels(pattern, &finest, &coarsest, &status);
    check(status.failure == KS_FAILURE_NONE && finest == 0 && coarsest >= 1,
          "pmalign: levels");
    ks_pm_align_pattern_feature_count(pattern, 0, &count, &status);
    check(count >= KS_PM_ALIGN_MIN_FEATURES, "pmalign: feature count");
    ks_pm_align_pattern_feature(pattern, 0, 0, &feature, &status);
    check(status.failure == KS_FAILURE_NONE
          && fabs(hypot(feature.normal_x, feature.normal_y) - 1.0) < 1e-9
          && fabs(feature.x) <= 31.0 && fabs(feature.y) <= 26.0,
          "pmalign: a feature");
    ks_pm_align_pattern_feature(pattern, 0, count, &feature, &status);
    check(status.failure == KS_FAILURE_INDEX_OUT_OF_RANGE,
          "pmalign: a feature out of range");

    /* The train image mask: the left half "don't care" (a 60 x 120 mask
       of zeros at offset (0, 0)) leaves fewer features, all on the right
       of the origin; a NULL mask gives the plain model. */
    {
        ks_image_8_grey *mask = NULL;
        ks_pm_align_pattern *masked = NULL;
        int32_t masked_count = 0, i, left = 0;

        ks_image_8_grey_create(60, 120, 0, &mask, &status);
        ks_pm_align_pattern_create(&masked, &status);
        ks_pm_align_pattern_train_masked(masked, train_image, train_region,
                                         &identity, &origin, mask, 0, 0,
                                         &status);
        check(status.failure == KS_FAILURE_NONE, "pmalign: train_masked");
        ks_pm_align_pattern_feature_count(masked, 0, &masked_count, &status);
        for (i = 0; i < masked_count; i++) {
            ks_pm_align_pattern_feature(masked, 0, i, &feature, &status);
            if (feature.x < 0.0) {
                left++;
            }
        }
        check(masked_count > 0 && masked_count < count && left == 0,
              "pmalign: train_masked leaves out the masked half");
        ks_pm_align_pattern_train_masked(masked, train_image, train_region,
                                         &identity, &origin, NULL, 0, 0,
                                         &status);
        ks_pm_align_pattern_feature_count(masked, 0, &masked_count, &status);
        check(status.failure == KS_FAILURE_NONE && masked_count == count,
              "pmalign: train_masked without a mask");
        ks_pm_align_pattern_destroy(&masked);
        ks_image_8_grey_destroy(&mask, &status);
    }

    /* The figure shifted to (101, 83) in a 220 x 200 scene. */
    scene = figure_image(220, 200, 101, 83, 0);
    ks_pixel_region_whole_image(220, 200, &region, &status);
    ks_pm_align_execute(scene, region, &identity, pattern, &params,
                        &results, &status);
    check(status.failure == KS_FAILURE_NONE && results != NULL,
          "pmalign: execute");
    ks_pm_align_results_count(results, &count, &status);
    ks_pm_align_results_item(results, 0, &item, &status);
    check(count == 1 && fabs(item.translation_x - 101.0) < 0.05
          && fabs(item.translation_y - 83.0) < 0.05 && item.rotation == 0.0
          && item.scaling == 1.0 && item.score > 0.9 && item.score <= 1.0
          && item.fine_stage == 1 && item.id == 0,
          "pmalign: the shifted figure");
    ks_pm_align_result_get_pose(&item, &pose, &status);
    check(status.failure == KS_FAILURE_NONE && pose.a == 1.0
          && pose.translation_x == item.translation_x,
          "pmalign: get pose");
    ks_pm_align_results_item(results, 1, &item, &status);
    check(status.failure == KS_FAILURE_INDEX_OUT_OF_RANGE,
          "pmalign: item out of range");
    ks_pm_align_results_destroy(&results);
    check(results == NULL, "pmalign: results destroy");

    /* The figure turned by a quarter turn, searched over the whole
       circle. */
    turned = figure_image(220, 200, 120, 100, 1);
    params.zone_angle.configuration = KS_PM_ALIGN_ZONE_LOW_HIGH;
    ks_pm_align_execute(turned, region, &identity, pattern, &params,
                        &results, &status);
    ks_pm_align_results_count(results, &count, &status);
    ks_pm_align_results_item(results, 0, &item, &status);
    check(count == 1 && fabs(item.translation_x - 120.0) < 0.05
          && fabs(item.translation_y - 100.0) < 0.05
          && fabs(item.rotation - 1.5707963267948966) < 0.002,
          "pmalign: the turned figure");
    ks_pm_align_results_destroy(&results);

    /* The empty region gives no results. */
    ks_pm_align_execute(turned, NULL, &identity, pattern, &params, &results,
                        &status);
    ks_pm_align_results_count(results, &count, &status);
    check(status.failure == KS_FAILURE_NONE && results != NULL && count == 0,
          "pmalign: the empty region");
    ks_pm_align_results_destroy(&results);

    /* Failures. */
    params.accept_threshold = nan_value;
    ks_pm_align_execute(scene, region, &identity, pattern, &params,
                        &results, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "RunParams.AcceptThreshold must be in [0, 1]")
          && results == NULL,
          "pmalign: AcceptThreshold NaN");
    ks_pm_align_check_run_params(&params, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER,
          "pmalign: check run params");
    ks_pm_align_run_params_default(&params, &status);
    params.run_algorithm = KS_PM_ALIGN_RUN_ALGORITHM_PAT_QUICK;
    ks_pm_align_execute(scene, region, &identity, pattern, &params,
                        &results, &status);
    check(is_failure(&status, KS_FAILURE_OPERATOR_NOT_TRAINED,
                     "Pattern is not trained for PatQuick"),
          "pmalign: PatQuick with a PatMax pattern");
    ks_pm_align_run_params_default(&params, &status);
    ks_pm_align_execute(NULL, region, &identity, pattern, &params, &results,
                        &status);
    check(is_failure(&status, KS_FAILURE_IMAGE_NO_PIXELS,
                     "InputImage has no pixels"),
          "pmalign: a NULL image");

    /* Duplicate, set the parameters (untrains), destroy. */
    ks_pm_align_pattern_duplicate(pattern, &copy, &status);
    check(status.failure == KS_FAILURE_NONE && copy != NULL,
          "pmalign: duplicate");
    train.grain_limit_fine = 64.0;
    ks_pm_align_pattern_set_train_params(copy, &train, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER,
          "pmalign: GrainLimitFine 64");
    train.grain_limit_fine = 1.0;
    train.train_algorithm = KS_PM_ALIGN_TRAIN_ALGORITHM_PAT_MAX_AND_PAT_QUICK;
    ks_pm_align_pattern_set_train_params(copy, &train, &status);
    ks_pm_align_pattern_trained(copy, &flag, &status);
    check(status.failure == KS_FAILURE_NONE && flag == 0,
          "pmalign: setting the parameters untrains");
    ks_pm_align_pattern_untrain(pattern, &status);
    ks_pm_align_pattern_trained(pattern, &flag, &status);
    check(flag == 0, "pmalign: untrain");
    ks_pm_align_pattern_destroy(&copy);
    ks_pm_align_pattern_destroy(&pattern);
    check(copy == NULL && pattern == NULL, "pmalign: pattern destroy");

    ks_pixel_region_destroy(&train_region, &status);
    ks_pixel_region_destroy(&region, &status);
    ks_image_8_grey_destroy(&train_image, &status);
    ks_image_8_grey_destroy(&scene, &status);
    ks_image_8_grey_destroy(&turned, &status);
}
