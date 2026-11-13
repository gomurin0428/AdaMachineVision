/*
 * C tests of the CNL search (include/amv_cnl_search.h): a textured
 * pattern trained on a whole image and found again, copied at a whole
 * pixel position into a larger image; the pattern entry points; the
 * train image mask; partial matches (a pattern partly outside the image)
 * and the layout of the run parameters; the AffineTransform region mode
 * (an upright affine rectangle on whole pixels resamples exactly the
 * pixels of its box); NULL handles, an untrained pattern, bad codes and
 * NaN.
 */

#include <math.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

#include "amv.h"
#include "c_test_support.h"

void test_c_cnl_search(void);

static const ks_transform_2d_linear identity = {1.0, 0.0, 0.0, 1.0, 0.0,
                                                0.0};

/* The grey level of the pattern at (x, y): a texture without symmetry. */
static uint8_t texture(int32_t x, int32_t y)
{
    return (uint8_t)(40 + (x * x + 3 * y + x * y) % 23 * 8);
}

/* A width x height image of value background, with the 16 x 12 pattern
   at (x0, y0) when x0 >= 0. */
static ks_image_8_grey *scene(int32_t width, int32_t height, int32_t x0,
                              int32_t y0, uint8_t background)
{
    ks_status status;
    ks_image_8_grey *image = NULL;
    int32_t x, y;

    ks_image_8_grey_create(width, height, background, &image, &status);
    if (x0 >= 0) {
        for (y = 0; y < 12; y++) {
            for (x = 0; x < 16; x++) {
                ks_image_8_grey_set_pixel(image, x0 + x, y0 + y,
                                          texture(x, y), &status);
            }
        }
    }
    return image;
}

static int same_pixels(const ks_image_8_grey *a, const ks_image_8_grey *b,
                       int32_t width, int32_t height)
{
    ks_status status;
    uint8_t va = 0, vb = 0;
    int32_t x, y;

    for (y = 0; y < height; y++) {
        for (x = 0; x < width; x++) {
            ks_image_8_grey_get_pixel(a, x, y, &va, &status);
            ks_image_8_grey_get_pixel(b, x, y, &vb, &status);
            if (va != vb) {
                return 0;
            }
        }
    }
    return 1;
}

/* TrainRegionMode: a disc in the 16 x 12 pattern image (its box is
   pixels 3 .. 12 x 1 .. 10). The search image holds the pattern at
   (10, 8) with the four corners of the disc's box changed: with
   ADJUST_MASK (the default) they are not part of the pattern and the
   match scores 1; with PIXEL_ALIGNED_BOUNDING_BOX it scores less. */
static double region_mode_score(int32_t mode)
{
    ks_status status;
    ks_cnl_search_train_params train;
    ks_cnl_search_run_params params;
    ks_cnl_search_pattern *pattern = NULL;
    ks_cnl_search_results *results = NULL;
    ks_cnl_search_result item;
    ks_pixel_region *disc = NULL, *whole = NULL;
    ks_image_8_grey *image = scene(16, 12, 0, 0, 0);
    ks_image_8_grey *search = scene(40, 30, 10, 8, 120);
    ks_circle circle = {7.5, 5.5, 5.4};
    double score = -1.0;

    ks_image_8_grey_set_pixel(search, 13, 9, 250, &status);
    ks_image_8_grey_set_pixel(search, 22, 9, 250, &status);
    ks_image_8_grey_set_pixel(search, 13, 18, 250, &status);
    ks_image_8_grey_set_pixel(search, 22, 18, 250, &status);
    ks_pixel_region_rasterize_circle(16, 12, &identity, &circle, &disc,
                                     &status);
    ks_pixel_region_whole_image(40, 30, &whole, &status);
    ks_cnl_search_train_params_default(&train, &status);
    train.train_region_mode = mode;
    ks_cnl_search_pattern_set_train_params(&pattern, &train, &status);
    ks_cnl_search_pattern_train(&pattern, image, disc, &identity, &status);
    ks_cnl_search_run_params_default(&params, &status);
    ks_cnl_search_execute(search, whole, pattern, &params, &identity,
                          &results, &status);
    ks_cnl_search_results_item(results, 0, &item, &status);
    if (status.failure == KS_FAILURE_NONE)
        score = item.score;
    ks_cnl_search_results_destroy(&results);
    ks_cnl_search_pattern_destroy(&pattern, &status);
    ks_pixel_region_destroy(&disc, &status);
    ks_pixel_region_destroy(&whole, &status);
    ks_image_8_grey_destroy(&image, &status);
    ks_image_8_grey_destroy(&search, &status);
    return score;
}

static void test_train_region_mode(void)
{
    ks_status status;
    ks_cnl_search_train_params train;
    ks_cnl_search_pattern *pattern = NULL;
    double masked = region_mode_score(
        KS_CNL_SEARCH_REGION_MODE_PIXEL_ALIGNED_BOUNDING_BOX_ADJUST_MASK);
    double whole = region_mode_score(
        KS_CNL_SEARCH_REGION_MODE_PIXEL_ALIGNED_BOUNDING_BOX);

    check(fabs(masked - 1.0) < 1e-9,
          "cnl search: ADJUST_MASK, the box's corners are not cared for");
    check(whole > 0.0 && whole < 0.99,
          "cnl search: PIXEL_ALIGNED_BOUNDING_BOX, the whole box");

    ks_cnl_search_train_params_default(&train, &status);
    train.train_region_mode = 3;
    ks_cnl_search_pattern_set_train_params(&pattern, &train, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Pattern.TrainRegionMode must be "
                     "PixelAlignedBoundingBoxAdjustMask (0), "
                     "PixelAlignedBoundingBox (1) or AffineTransform (2)"),
          "cnl search: train_region_mode 3");
    ks_cnl_search_pattern_destroy(&pattern, &status);
}

/* The AffineTransform region mode: the 16 x 12 pattern image trained as
   an upright affine rectangle on whole pixels (exactly its pixels), and
   searched for in an upright rectangle on whole pixels of the image
   holding it at (37, 21). */
static void test_affine_region_mode(void)
{
    ks_status status;
    ks_cnl_search_train_params train;
    ks_cnl_search_run_params params;
    ks_cnl_search_pattern *pattern = NULL;
    ks_cnl_search_results *results = NULL;
    ks_cnl_search_result item;
    ks_pixel_region *whole = NULL;
    ks_image_8_grey *pattern_image = scene(16, 12, 0, 0, 0);
    ks_image_8_grey *image = scene(100, 80, 37, 21, 120);
    ks_image_8_grey *trained_image = NULL;
    ks_rectangle_affine all = {7.5, 5.5, 16.0, 12.0, 0.0, 0.0};
    ks_rectangle_affine area = {49.5, 39.5, 60.0, 50.0, 0.0, 0.0};
    ks_rectangle_affine bad = {NAN, 39.5, 60.0, 50.0, 0.0, 0.0};
    int32_t count = -1, width = 0, height = 0;
    double x = -1.0, y = -1.0;

    /* A pattern in another mode. */
    ks_cnl_search_pattern_train_affine(&pattern, pattern_image, &all,
                                       &identity, &identity, NULL, 0, 0,
                                       &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Pattern.TrainRegionMode must be AffineTransform (2) "
                     "for ks_cnl_search_pattern_train_affine")
          && pattern == NULL,
          "cnl search: train_affine needs the mode AFFINE_TRANSFORM");

    ks_cnl_search_train_params_default(&train, &status);
    train.train_region_mode = KS_CNL_SEARCH_REGION_MODE_AFFINE_TRANSFORM;
    train.accuracies = KS_CNL_SEARCH_ACCURACY_VERY_FINE
                       | KS_CNL_SEARCH_ACCURACY_COARSE;
    train.origin_x = 3.0;
    train.origin_y = 2.0;
    ks_cnl_search_pattern_set_train_params(&pattern, &train, &status);
    check(status.failure == KS_FAILURE_NONE,
          "cnl search: train_region_mode AFFINE_TRANSFORM accepted");
    ks_pixel_region_whole_image(16, 12, &whole, &status);
    ks_cnl_search_pattern_train(&pattern, pattern_image, whole, &identity,
                                &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Pattern.TrainRegionMode AffineTransform needs an "
                     "affine rectangle TrainRegion "
                     "(ks_cnl_search_pattern_train_affine)"),
          "cnl search: train with a pixel region in the mode "
          "AFFINE_TRANSFORM");
    ks_cnl_search_pattern_train_affine(&pattern, pattern_image, &all,
                                       &identity, &identity, NULL, 0, 0,
                                       &status);
    ks_cnl_search_pattern_trained_size(pattern, &width, &height, &status);
    ks_cnl_search_pattern_trained_origin(pattern, &x, &y, &status);
    ks_cnl_search_pattern_get_trained_pattern_image(pattern, &trained_image,
                                                    &status);
    check(status.failure == KS_FAILURE_NONE && width == 16 && height == 12
          && fabs(x - 3.0) < 1e-12 && fabs(y - 2.0) < 1e-12
          && trained_image != NULL
          && same_pixels(trained_image, pattern_image, 16, 12),
          "cnl search: train_affine on whole pixels: the image's pixels");

    /* The search. */
    /* Whole pixels (COARSE): the texture's neighbours are not
       symmetric. */
    ks_cnl_search_run_params_default(&params, &status);
    params.search_region_mode = KS_CNL_SEARCH_REGION_MODE_AFFINE_TRANSFORM;
    params.accuracy = KS_CNL_SEARCH_ACCURACY_COARSE;
    ks_cnl_search_execute_affine(image, &area, &identity, pattern, &params,
                                 &identity, &results, &status);
    ks_cnl_search_results_count(results, &count, &status);
    ks_cnl_search_results_item(results, 0, &item, &status);
    check(status.failure == KS_FAILURE_NONE && count == 1
          && fabs(item.score - 1.0) < 1e-9
          && fabs(item.location_x - 40.0) < 1e-6
          && fabs(item.location_y - 23.0) < 1e-6
          && item.edge_hit == KS_CNL_SEARCH_EDGE_HIT_NONE,
          "cnl search: execute_affine finds the pattern at its origin");
    ks_cnl_search_results_destroy(&results);
    ks_cnl_search_execute_affine(image, &bad, &identity, pattern, &params,
                                 &identity, &results, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "SearchRegion.CenterX must be finite and within "
                     "1.0E150")
          && results == NULL,
          "cnl search: execute_affine with a NaN centre");
    params.search_region_mode =
        KS_CNL_SEARCH_REGION_MODE_PIXEL_ALIGNED_BOUNDING_BOX;
    ks_cnl_search_execute_affine(image, &area, &identity, pattern, &params,
                                 &identity, &results, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "RunParams.SearchRegionMode PixelAlignedBoundingBox "
                     "needs a pixel region (ks_cnl_search_execute)")
          && results == NULL,
          "cnl search: execute_affine needs AFFINE_TRANSFORM");
    ks_cnl_search_execute_affine(NULL, &area, &identity, pattern, &params,
                                 &identity, &results, &status);
    check(status.failure == KS_FAILURE_IMAGE_NO_PIXELS && results == NULL,
          "cnl search: execute_affine with a NULL image");

    /* A pixel region in the mode AFFINE_TRANSFORM: its bounding box. */
    ks_pixel_region_destroy(&whole, &status);
    ks_pixel_region_whole_image(100, 80, &whole, &status);
    params.search_region_mode = KS_CNL_SEARCH_REGION_MODE_AFFINE_TRANSFORM;
    ks_cnl_search_execute(image, whole, pattern, &params, &identity,
                          &results, &status);
    ks_cnl_search_results_count(results, &count, &status);
    ks_cnl_search_results_item(results, 0, &item, &status);
    check(status.failure == KS_FAILURE_NONE && count == 1
          && fabs(item.location_x - 40.0) < 1e-6,
          "cnl search: execute with AFFINE_TRANSFORM searches the box");
    ks_cnl_search_results_destroy(&results);

    ks_cnl_search_pattern_destroy(&pattern, &status);
    ks_pixel_region_destroy(&whole, &status);
    ks_image_8_grey_destroy(&trained_image, &status);
    ks_image_8_grey_destroy(&pattern_image, &status);
    ks_image_8_grey_destroy(&image, &status);
}

void test_c_cnl_search(void)
{
    ks_status status;
    ks_cnl_search_train_params train;
    ks_cnl_search_run_params params;
    ks_cnl_search_pattern *pattern = NULL, *copy = NULL;
    ks_cnl_search_results *results = NULL;
    ks_cnl_search_result item;
    ks_pixel_region *whole = NULL, *search_region = NULL;
    ks_image_8_grey *pattern_image = scene(16, 12, 0, 0, 0);
    ks_image_8_grey *image = scene(100, 80, 37, 21, 120);
    ks_image_8_grey *trained_image = NULL;
    int32_t count = -1, trained = -1, width = 0, height = 0;
    double x = -1.0, y = -1.0;

    /* Defaults. */
    ks_cnl_search_train_params_default(&train, &status);
    check(status.failure == KS_FAILURE_NONE
          && train.algorithms == KS_CNL_SEARCH_ALGORITHM_LINEAR_SEARCH
          && train.accuracies == KS_CNL_SEARCH_ACCURACY_VERY_FINE
          && train.ignore_polarity == 0 && train.origin_x == 70.0
          && train.origin_y == 70.0
          && train.train_region_mode
               == KS_CNL_SEARCH_REGION_MODE_PIXEL_ALIGNED_BOUNDING_BOX_ADJUST_MASK,
          "cnl search: train params default");
    ks_cnl_search_run_params_default(&params, &status);
    check(status.failure == KS_FAILURE_NONE
          && params.algorithm == KS_CNL_SEARCH_ALGORITHM_LINEAR_SEARCH
          && params.accuracy == KS_CNL_SEARCH_ACCURACY_VERY_FINE
          && params.max_results == 1
          && params.search_region_mode
               == KS_CNL_SEARCH_REGION_MODE_PIXEL_ALIGNED_BOUNDING_BOX
          && params.accept_threshold == 0.3
          && params.confusion_threshold == 0.5 && params.xy_overlap == 1.0
          && params.partial_match_limit_left == 0
          && params.partial_match_limit_right == 0
          && params.partial_match_limit_up == 0
          && params.partial_match_limit_down == 0
          && params.partial_match_reduce_score == 0,
          "cnl search: run params default");
    check(sizeof(ks_cnl_search_run_params) == 64
          && offsetof(ks_cnl_search_run_params, xy_overlap) == 32
          && offsetof(ks_cnl_search_run_params, partial_match_limit_left)
               == 40
          && offsetof(ks_cnl_search_run_params, partial_match_limit_down)
               == 52
          && offsetof(ks_cnl_search_run_params, partial_match_reduce_score)
               == 56
          && sizeof(ks_cnl_search_result) == 48
          && sizeof(ks_cnl_search_train_params) == 40
          && offsetof(ks_cnl_search_train_params, train_region_mode) == 32,
          "cnl search: run params, train params and result layout");

    /* NULL handles. */
    ks_pixel_region_whole_image(100, 80, &search_region, &status);
    ks_cnl_search_execute(image, search_region, NULL, &params, &identity,
                          &results, &status);
    check(is_failure(&status, KS_FAILURE_OPERATOR_NOT_TRAINED,
                     "Pattern is not trained")
          && results == NULL,
          "cnl search: a NULL pattern is not trained");
    ks_cnl_search_pattern_trained(NULL, &trained, &status);
    check(status.failure == KS_FAILURE_NONE && trained == 0,
          "cnl search: a NULL pattern is untrained");
    ks_cnl_search_pattern_trained_size(NULL, &width, &height, &status);
    check(status.failure == KS_FAILURE_OPERATOR_NOT_TRAINED,
          "cnl search: trained size of NULL");

    /* Training (the handle is created by set_train_params). */
    train.origin_x = 0.0;
    train.origin_y = 0.0;
    train.algorithms = KS_CNL_SEARCH_ALGORITHM_LINEAR_SEARCH
                       | KS_CNL_SEARCH_ALGORITHM_LINEAR_CNLPAS;
    train.accuracies = KS_CNL_SEARCH_ACCURACY_VERY_FINE
                       | KS_CNL_SEARCH_ACCURACY_FINE
                       | KS_CNL_SEARCH_ACCURACY_COARSE;
    ks_cnl_search_pattern_set_train_params(&pattern, &train, &status);
    check(status.failure == KS_FAILURE_NONE && pattern != NULL,
          "cnl search: set train params creates the pattern");
    ks_cnl_search_execute(image, search_region, pattern, &params, &identity,
                          &results, &status);
    check(status.failure == KS_FAILURE_OPERATOR_NOT_TRAINED
          && results == NULL,
          "cnl search: an untrained pattern yields no results");
    ks_pixel_region_whole_image(16, 12, &whole, &status);
    ks_cnl_search_pattern_train(&pattern, NULL, whole, &identity, &status);
    check(is_failure(&status, KS_FAILURE_IMAGE_NO_PIXELS,
                     "TrainImage has no pixels"),
          "cnl search: train without an image");
    ks_cnl_search_pattern_train(&pattern, pattern_image, NULL, &identity,
                                &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "TrainRegion lies entirely outside TrainImage"),
          "cnl search: train with the empty region");
    ks_cnl_search_pattern_train(&pattern, pattern_image, whole, &identity,
                                &status);
    check(status.failure == KS_FAILURE_NONE, "cnl search: train");
    ks_cnl_search_pattern_trained(pattern, &trained, &status);
    ks_cnl_search_pattern_trained_size(pattern, &width, &height, &status);
    check(trained == 1 && width == 16 && height == 12,
          "cnl search: trained, 16 x 12");
    ks_cnl_search_pattern_trained_origin(pattern, &x, &y, &status);
    check(status.failure == KS_FAILURE_NONE && x == 0.0 && y == 0.0,
          "cnl search: trained origin");
    ks_cnl_search_pattern_get_trained_pattern_image(pattern, &trained_image,
                                                    &status);
    check(status.failure == KS_FAILURE_NONE && trained_image != NULL
          && same_pixels(trained_image, pattern_image, 16, 12),
          "cnl search: the trained pattern image");
    ks_image_8_grey_destroy(&trained_image, &status);

    /* Searching: whole pixels with COARSE, both algorithms. */
    params.accuracy = KS_CNL_SEARCH_ACCURACY_COARSE;
    ks_cnl_search_execute(image, search_region, pattern, &params, &identity,
                          &results, &status);
    ks_cnl_search_results_count(results, &count, &status);
    ks_cnl_search_results_item(results, 0, &item, &status);
    check(count == 1 && status.failure == KS_FAILURE_NONE
          && item.location_x == 37.0 && item.location_y == 21.0
          && fabs(item.score - 1.0) < 1e-12 && item.id == 0
          && item.accepted == 1 && item.contrast_computed == 1
          && item.edge_hit == KS_CNL_SEARCH_EDGE_HIT_NONE
          && fabs(item.contrast - 1.0) < 1e-12,
          "cnl search: found at (37, 21), score 1");
    ks_cnl_search_results_item(results, 1, &item, &status);
    check(status.failure == KS_FAILURE_INDEX_OUT_OF_RANGE,
          "cnl search: item 1 out of range");
    ks_cnl_search_results_destroy(&results);
    check(results == NULL, "cnl search: results destroyed");

    params.algorithm = KS_CNL_SEARCH_ALGORITHM_LINEAR_CNLPAS;
    params.accuracy = KS_CNL_SEARCH_ACCURACY_VERY_FINE;
    ks_cnl_search_execute(image, search_region, pattern, &params, &identity,
                          &results, &status);
    ks_cnl_search_results_count(results, &count, &status);
    ks_cnl_search_results_item(results, 0, &item, &status);
    check(count == 1 && fabs(item.location_x - 37.0) < 0.5
          && fabs(item.location_y - 21.0) < 0.5,
          "cnl search: LinearCNLPAS, VeryFine near (37, 21)");
    ks_cnl_search_results_destroy(&results);

    /* Partial matches: the pattern with 5 of its 16 columns outside the
       left side of the image is found at x = -5 with the limit 8 (half
       the width), EdgeHit LEFT, score 1 over its 11 columns inside, or
       11/16 with partial_match_reduce_score. */
    {
        ks_image_8_grey *edge = scene(100, 80, -1, 0, 120);
        int32_t xx, yy;

        for (yy = 0; yy < 12; yy++) {
            for (xx = 5; xx < 16; xx++) {
                ks_image_8_grey_set_pixel(edge, xx - 5, 30 + yy,
                                          texture(xx, yy), &status);
            }
        }
        ks_cnl_search_run_params_default(&params, &status);
        params.accuracy = KS_CNL_SEARCH_ACCURACY_COARSE;
        ks_cnl_search_execute(edge, search_region, pattern, &params,
                              &identity, &results, &status);
        ks_cnl_search_results_count(results, &count, &status);
        ks_cnl_search_results_item(results, 0, &item, &status);
        check(count == 0 || item.score < 0.9,
              "cnl search: limits 0, the partial instance is not found");
        ks_cnl_search_results_destroy(&results);
        params.partial_match_limit_left = 8;
        ks_cnl_search_execute(edge, search_region, pattern, &params,
                              &identity, &results, &status);
        ks_cnl_search_results_count(results, &count, &status);
        ks_cnl_search_results_item(results, 0, &item, &status);
        check(status.failure == KS_FAILURE_NONE && count == 1
              && item.location_x == -5.0 && item.location_y == 30.0
              && fabs(item.score - 1.0) < 1e-12
              && item.edge_hit == KS_CNL_SEARCH_EDGE_HIT_LEFT,
              "cnl search: partial match at (-5, 30), edge hit LEFT");
        ks_cnl_search_results_destroy(&results);
        params.partial_match_reduce_score = 1;
        ks_cnl_search_execute(edge, search_region, pattern, &params,
                              &identity, &results, &status);
        ks_cnl_search_results_item(results, 0, &item, &status);
        check(status.failure == KS_FAILURE_NONE
              && item.location_x == -5.0
              && fabs(item.score - 11.0 / 16.0) < 1e-12,
              "cnl search: partial match, score reduced to 11/16");
        ks_cnl_search_results_destroy(&results);
        params.partial_match_limit_left = 9;
        ks_cnl_search_execute(edge, search_region, pattern, &params,
                              &identity, &results, &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "RunParams.PartialMatchLimitLeft must be in 0 .. "
                         "TrainedPatternWidth / 2")
              && results == NULL,
              "cnl search: a limit beyond half the pattern's width");
        params.partial_match_limit_left = 8;
        params.partial_match_reduce_score = 2;
        ks_cnl_search_execute(edge, search_region, pattern, &params,
                              &identity, &results, &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "RunParams.PartialMatchReduceScore must be 0 or 1"),
              "cnl search: partial_match_reduce_score 2");
        params.partial_match_reduce_score = 0;
        params.algorithm = KS_CNL_SEARCH_ALGORITHM_LINEAR_CNLPAS;
        ks_cnl_search_execute(edge, search_region, pattern, &params,
                              &identity, &results, &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "RunParams.PartialMatchLimitLeft, Right, Up and "
                         "Down must be 0 with LinearCNLPAS")
              && results == NULL,
              "cnl search: partial matches with LINEAR_CNLPAS");
        ks_image_8_grey_destroy(&edge, &status);
        ks_cnl_search_run_params_default(&params, &status);
        params.algorithm = KS_CNL_SEARCH_ALGORITHM_LINEAR_CNLPAS;
    }

    /* The empty region gives no results. */
    ks_cnl_search_execute(image, NULL, pattern, &params, &identity,
                          &results, &status);
    ks_cnl_search_results_count(results, &count, &status);
    check(status.failure == KS_FAILURE_NONE && results != NULL && count == 0,
          "cnl search: the empty region");
    ks_cnl_search_results_destroy(&results);

    /* Failures. */
    params.max_results = 0;
    ks_cnl_search_execute(image, search_region, pattern, &params, &identity,
                          &results, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "RunParams.MaxResults must be in 1 .. 1000")
          && results == NULL,
          "cnl search: MaxResults 0");
    ks_cnl_search_run_params_default(&params, &status);
    params.accept_threshold = NAN;
    ks_cnl_search_execute(image, search_region, pattern, &params, &identity,
                          &results, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "RunParams.AcceptThreshold must be in 0 .. 1"),
          "cnl search: a NaN AcceptThreshold");
    ks_cnl_search_run_params_default(&params, &status);
    params.algorithm = 3;
    ks_cnl_search_execute(image, search_region, pattern, &params, &identity,
                          &results, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER && results == NULL,
          "cnl search: an algorithm code that is not one flag");
    ks_cnl_search_run_params_default(&params, &status);
    ks_cnl_search_execute(NULL, search_region, pattern, &params, &identity,
                          &results, &status);
    check(is_failure(&status, KS_FAILURE_IMAGE_NO_PIXELS,
                     "InputImage has no pixels"),
          "cnl search: a NULL image");
    train.origin_x = NAN;
    ks_cnl_search_pattern_set_train_params(&pattern, &train, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Pattern.OriginX must be finite and within 1.0E150"),
          "cnl search: a NaN origin is rejected");
    ks_cnl_search_pattern_trained(pattern, &trained, &status);
    check(trained == 1, "cnl search: the pattern is unchanged");
    ks_cnl_search_results_count(NULL, &count, &status);
    check(status.failure == KS_FAILURE_NONE && count == 0,
          "cnl search: count of NULL");

    /* The train image mask: an 8 x 12 mask of zeros at offset (8, 0)
       leaves the right half of the pattern out. In an image where that
       half of the instance is blank, the masked pattern still scores 1
       there and the plain one less. */
    {
        ks_image_8_grey *mask = NULL, *none = NULL;
        ks_image_8_grey *half = scene(100, 80, 37, 21, 120);
        ks_cnl_search_pattern *masked = NULL;
        ks_cnl_search_train_params masked_train;
        ks_cnl_search_result plain_item, masked_item;
        int32_t xx, yy;

        for (yy = 0; yy < 12; yy++) {
            for (xx = 8; xx < 16; xx++) {
                ks_image_8_grey_set_pixel(half, 37 + xx, 21 + yy, 200,
                                          &status);
            }
        }
        ks_image_8_grey_create(8, 12, 0, &mask, &status);
        ks_cnl_search_run_params_default(&params, &status);
        params.accuracy = KS_CNL_SEARCH_ACCURACY_COARSE;
        params.accept_threshold = 0.0;
        ks_cnl_search_pattern_get_train_params(pattern, &masked_train,
                                               &status);
        ks_cnl_search_pattern_set_train_params(&masked, &masked_train,
                                               &status);
        ks_cnl_search_pattern_train_masked(&masked, pattern_image, whole,
                                           &identity, mask, 8, 0, &status);
        check(status.failure == KS_FAILURE_NONE, "cnl search: train_masked");
        ks_cnl_search_execute(half, search_region, masked, &params,
                              &identity, &results, &status);
        ks_cnl_search_results_count(results, &count, &status);
        ks_cnl_search_results_item(results, 0, &masked_item, &status);
        ks_cnl_search_results_destroy(&results);
        ks_cnl_search_execute(half, search_region, pattern, &params,
                              &identity, &results, &status);
        ks_cnl_search_results_item(results, 0, &plain_item, &status);
        ks_cnl_search_results_destroy(&results);
        check(count == 1 && masked_item.location_x == 37.0
              && masked_item.location_y == 21.0
              && fabs(masked_item.score - 1.0) < 1e-12
              && plain_item.score < 0.5,
              "cnl search: the masked half does not count");
        ks_cnl_search_pattern_train_masked(&masked, pattern_image, whole,
                                           &identity, NULL, 8, 0, &status);
        ks_cnl_search_execute(half, search_region, masked, &params,
                              &identity, &results, &status);
        ks_cnl_search_results_item(results, 0, &masked_item, &status);
        ks_cnl_search_results_destroy(&results);
        check(status.failure == KS_FAILURE_NONE
              && masked_item.score == plain_item.score
              && masked_item.location_x == plain_item.location_x,
              "cnl search: train_masked without a mask");
        ks_image_8_grey_create(16, 12, 0, &none, &status);
        ks_cnl_search_pattern_train_masked(&masked, pattern_image, whole,
                                           &identity, none, 0, 0, &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "TrainImageMask leaves fewer than 64 pixels of the "
                         "pattern cared for"),
              "cnl search: a mask that leaves no pixel cared for");
        ks_cnl_search_pattern_trained(masked, &trained, &status);
        check(trained == 0, "cnl search: untrained after it");
        ks_cnl_search_pattern_destroy(&masked, &status);
        ks_image_8_grey_destroy(&none, &status);
        ks_image_8_grey_destroy(&mask, &status);
        ks_image_8_grey_destroy(&half, &status);
        ks_cnl_search_run_params_default(&params, &status);
    }

    /* Duplicate, untrain, destroy. */
    ks_cnl_search_pattern_duplicate(pattern, &copy, &status);
    ks_cnl_search_pattern_untrain(pattern, &status);
    ks_cnl_search_pattern_trained(pattern, &trained, &status);
    check(status.failure == KS_FAILURE_NONE && trained == 0,
          "cnl search: untrained");
    ks_cnl_search_pattern_trained(copy, &trained, &status);
    check(trained == 1, "cnl search: the duplicate stays trained");
    ks_cnl_search_execute(image, search_region, pattern, &params, &identity,
                          &results, &status);
    check(status.failure == KS_FAILURE_OPERATOR_NOT_TRAINED,
          "cnl search: an untrained pattern again");
    ks_cnl_search_pattern_destroy(&pattern, &status);
    ks_cnl_search_pattern_destroy(&copy, &status);
    check(pattern == NULL && copy == NULL, "cnl search: patterns destroyed");

    ks_pixel_region_destroy(&whole, &status);
    ks_pixel_region_destroy(&search_region, &status);
    ks_image_8_grey_destroy(&pattern_image, &status);
    ks_image_8_grey_destroy(&image, &status);
    test_train_region_mode();
    test_affine_region_mode();
}
