/*
 * Tests of the pattern location tool's C API (include/amv_shape_match.h): a
 * pattern trained on a drawn L-shaped figure (sharp, pixel-aligned edges)
 * is found shifted and turned by a quarter turn, then the failures and
 * the accessors.
 */

#include <math.h>
#include <stdio.h>

#include "amv.h"
#include "c_test_support.h"

void test_c_shape_match(void);

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

void test_c_shape_match(void)
{
    ks_status status;
    ks_shape_match_train_params train;
    ks_shape_match_run_params params;
    ks_shape_match_pattern *pattern = NULL, *copy = NULL;
    ks_shape_match_results *results = NULL;
    ks_shape_match_result item;
    ks_shape_match_feature feature;
    ks_transform_2d_linear pose;
    ks_transform_2d_linear origin = {1.0, 0.0, 0.0, 1.0, 60.0, 60.0};
    ks_pixel_region *train_region = NULL, *region = NULL;
    ks_image_8_grey *train_image, *scene, *turned;
    int32_t flag = -1, count = -1, finest = -1, coarsest = -1;
    double nan_value = 0.0;

    nan_value = nan_value / nan_value;

    ks_shape_match_train_params_default(&train, &status);
    check(status.failure == KS_FAILURE_NONE
          && train.train_algorithm == KS_SHAPE_MATCH_TRAIN_ALGORITHM_EDGE_FIT
          && train.grain_limit_auto_select == 1
          && train.grain_limit_coarse == 8.0
          && train.grain_limit_fine == 1.0,
          "shape match: train params default");
    ks_shape_match_run_params_default(&params, &status);
    check(status.failure == KS_FAILURE_NONE
          && params.accept_threshold == 0.5
          && params.xy_overlap == 1.0
          && params.approximate_number_to_find == 1
          && params.run_algorithm == KS_SHAPE_MATCH_RUN_ALGORITHM_EDGE_FIT
          && params.zone_angle.configuration == KS_SHAPE_MATCH_ZONE_NOMINAL
          && params.zone_scale.nominal == 1.0,
          "shape match: run params default");

    /* A NULL pattern is untrained. */
    ks_shape_match_pattern_trained(NULL, &flag, &status);
    check(status.failure == KS_FAILURE_NONE && flag == 0,
          "shape match: trained (NULL) = 0");
    ks_shape_match_execute(NULL, NULL, &identity, NULL, &params, &results,
                           &status);
    check(is_failure(&status, KS_FAILURE_OPERATOR_NOT_TRAINED,
                     "Pattern is not trained")
          && results == NULL,
          "shape match: execute with a NULL pattern");

    /* Train on the figure at (60, 60) of a 120 x 120 image, the origin at
       its reference point. */
    train_image = figure_image(120, 120, 60, 60, 0);
    ks_pixel_region_whole_image(120, 120, &train_region, &status);
    ks_shape_match_pattern_create(&pattern, &status);
    check(status.failure == KS_FAILURE_NONE && pattern != NULL,
          "shape match: pattern create");
    ks_shape_match_pattern_train(pattern, NULL, train_region, &identity,
                                 &origin, &status);
    check(is_failure(&status, KS_FAILURE_IMAGE_NO_PIXELS,
                     "TrainImage has no pixels"),
          "shape match: train without image");
    ks_shape_match_pattern_train(pattern, train_image, train_region, &identity,
                                 &origin, &status);
    check(status.failure == KS_FAILURE_NONE, "shape match: train");
    ks_shape_match_pattern_trained(pattern, &flag, &status);
    check(flag == 1, "shape match: trained");
    ks_shape_match_pattern_levels(pattern, &finest, &coarsest, &status);
    check(status.failure == KS_FAILURE_NONE && finest == 0 && coarsest >= 1,
          "shape match: levels");
    ks_shape_match_pattern_feature_count(pattern, 0, &count, &status);
    check(count >= KS_SHAPE_MATCH_MIN_FEATURES, "shape match: feature count");
    ks_shape_match_pattern_feature(pattern, 0, 0, &feature, &status);
    check(status.failure == KS_FAILURE_NONE
          && fabs(hypot(feature.normal_x, feature.normal_y) - 1.0) < 1e-9
          && fabs(feature.x) <= 31.0 && fabs(feature.y) <= 26.0,
          "shape match: a feature");
    ks_shape_match_pattern_feature(pattern, 0, count, &feature, &status);
    check(status.failure == KS_FAILURE_INDEX_OUT_OF_RANGE,
          "shape match: a feature out of range");

    /* The train image mask: the left half "don't care" (a 60 x 120 mask
       of zeros at offset (0, 0)) leaves fewer features, all on the right
       of the origin; a NULL mask gives the plain model. */
    {
        ks_image_8_grey *mask = NULL;
        ks_shape_match_pattern *masked = NULL;
        int32_t masked_count = 0, i, left = 0;

        ks_image_8_grey_create(60, 120, 0, &mask, &status);
        ks_shape_match_pattern_create(&masked, &status);
        ks_shape_match_pattern_train_masked(masked, train_image, train_region,
                                            &identity, &origin, mask, 0, 0,
                                            &status);
        check(status.failure == KS_FAILURE_NONE, "shape match: train_masked");
        ks_shape_match_pattern_feature_count(masked, 0, &masked_count,
                                             &status);
        for (i = 0; i < masked_count; i++) {
            ks_shape_match_pattern_feature(masked, 0, i, &feature, &status);
            if (feature.x < 0.0) {
                left++;
            }
        }
        check(masked_count > 0 && masked_count < count && left == 0,
              "shape match: train_masked leaves out the masked half");
        ks_shape_match_pattern_train_masked(masked, train_image, train_region,
                                            &identity, &origin, NULL, 0, 0,
                                            &status);
        ks_shape_match_pattern_feature_count(masked, 0, &masked_count,
                                             &status);
        check(status.failure == KS_FAILURE_NONE && masked_count == count,
              "shape match: train_masked without a mask");
        ks_shape_match_pattern_destroy(&masked);
        ks_image_8_grey_destroy(&mask, &status);
    }

    /* The figure shifted to (101, 83) in a 220 x 200 scene. */
    scene = figure_image(220, 200, 101, 83, 0);
    ks_pixel_region_whole_image(220, 200, &region, &status);
    ks_shape_match_execute(scene, region, &identity, pattern, &params,
                           &results, &status);
    check(status.failure == KS_FAILURE_NONE && results != NULL,
          "shape match: execute");
    ks_shape_match_results_count(results, &count, &status);
    ks_shape_match_results_item(results, 0, &item, &status);
    check(count == 1 && fabs(item.translation_x - 101.0) < 0.05
          && fabs(item.translation_y - 83.0) < 0.05 && item.rotation == 0.0
          && item.scaling == 1.0 && item.score > 0.9 && item.score <= 1.0
          && item.fine_stage == 1 && item.id == 0,
          "shape match: the shifted figure");
    ks_shape_match_result_get_pose(&item, &pose, &status);
    check(status.failure == KS_FAILURE_NONE && pose.a == 1.0
          && pose.translation_x == item.translation_x,
          "shape match: get pose");
    ks_shape_match_results_item(results, 1, &item, &status);
    check(status.failure == KS_FAILURE_INDEX_OUT_OF_RANGE,
          "shape match: item out of range");
    ks_shape_match_results_destroy(&results);
    check(results == NULL, "shape match: results destroy");

    /* The figure turned by a quarter turn, searched over the whole
       circle. */
    turned = figure_image(220, 200, 120, 100, 1);
    params.zone_angle.configuration = KS_SHAPE_MATCH_ZONE_LOW_HIGH;
    ks_shape_match_execute(turned, region, &identity, pattern, &params,
                           &results, &status);
    ks_shape_match_results_count(results, &count, &status);
    ks_shape_match_results_item(results, 0, &item, &status);
    check(count == 1 && fabs(item.translation_x - 120.0) < 0.05
          && fabs(item.translation_y - 100.0) < 0.05
          && fabs(item.rotation - 1.5707963267948966) < 0.002,
          "shape match: the turned figure");
    ks_shape_match_results_destroy(&results);

    /* The empty region gives no results. */
    ks_shape_match_execute(turned, NULL, &identity, pattern, &params, &results,
                           &status);
    ks_shape_match_results_count(results, &count, &status);
    check(status.failure == KS_FAILURE_NONE && results != NULL && count == 0,
          "shape match: the empty region");
    ks_shape_match_results_destroy(&results);

    /* Failures. */
    params.accept_threshold = nan_value;
    ks_shape_match_execute(scene, region, &identity, pattern, &params,
                           &results, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "RunParams.AcceptThreshold must be in [0, 1]")
          && results == NULL,
          "shape match: AcceptThreshold NaN");
    ks_shape_match_check_run_params(&params, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER,
          "shape match: check run params");
    ks_shape_match_run_params_default(&params, &status);
    params.run_algorithm = KS_SHAPE_MATCH_RUN_ALGORITHM_GRID_SEARCH;
    ks_shape_match_execute(scene, region, &identity, pattern, &params,
                           &results, &status);
    check(is_failure(&status, KS_FAILURE_OPERATOR_NOT_TRAINED,
                     "Pattern is not trained for GridSearch"),
          "shape match: GridSearch with a EdgeFit pattern");
    ks_shape_match_run_params_default(&params, &status);
    ks_shape_match_execute(NULL, region, &identity, pattern, &params, &results,
                           &status);
    check(is_failure(&status, KS_FAILURE_IMAGE_NO_PIXELS,
                     "InputImage has no pixels"),
          "shape match: a NULL image");

    /* Duplicate, set the parameters (untrains), destroy. */
    ks_shape_match_pattern_duplicate(pattern, &copy, &status);
    check(status.failure == KS_FAILURE_NONE && copy != NULL,
          "shape match: duplicate");
    train.grain_limit_fine = 64.0;
    ks_shape_match_pattern_set_train_params(copy, &train, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER,
          "shape match: GrainLimitFine 64");
    train.grain_limit_fine = 1.0;
    train.train_algorithm =
        KS_SHAPE_MATCH_TRAIN_ALGORITHM_EDGE_FIT_AND_GRID_SEARCH;
    ks_shape_match_pattern_set_train_params(copy, &train, &status);
    ks_shape_match_pattern_trained(copy, &flag, &status);
    check(status.failure == KS_FAILURE_NONE && flag == 0,
          "shape match: setting the parameters untrains");
    ks_shape_match_pattern_untrain(pattern, &status);
    ks_shape_match_pattern_trained(pattern, &flag, &status);
    check(flag == 0, "shape match: untrain");
    ks_shape_match_pattern_destroy(&copy);
    ks_shape_match_pattern_destroy(&pattern);
    check(copy == NULL && pattern == NULL, "shape match: pattern destroy");

    ks_pixel_region_destroy(&train_region, &status);
    ks_pixel_region_destroy(&region, &status);
    ks_image_8_grey_destroy(&train_image, &status);
    ks_image_8_grey_destroy(&scene, &status);
    ks_image_8_grey_destroy(&turned, &status);
}
