/*
 * The blob tool from C (include/amv_blob.h): the run parameters, a run on
 * a drawn image (a rectangle with a hole and a small square), the results
 * and their accessors (the extrema-angle measures, the boxes at an angle
 * and the medians included), and the failures for NULL handles and bad
 * codes.
 */

#include <math.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

#include "amv.h"
#include "c_test_support.h"

void test_c_blob(void);

/* Sets the pixels x0 .. x1 by y0 .. y1 to value. */
static void fill_box(ks_image_8_grey *image, int32_t x0, int32_t y0,
                     int32_t x1, int32_t y1, uint8_t value)
{
    ks_status status;
    int32_t x, y;

    for (y = y0; y <= y1; y++) {
        for (x = x0; x <= x1; x++) {
            ks_image_8_grey_set_pixel(image, x, y, value, &status);
        }
    }
}

/* The pixel (x, y) of an 8-bit image, -1 when it cannot be read. */
static int pixel(const ks_image_8_grey *image, int32_t x, int32_t y)
{
    ks_status status;
    uint8_t value = 0;

    ks_image_8_grey_get_pixel(image, x, y, &value, &status);
    return status.failure == KS_FAILURE_NONE ? (int) value : -1;
}

/* The blob image and the segmented images (CreateBlobImage,
   CreateSegmentedImage). */
static void test_c_blob_images(void)
{
    ks_status status;
    ks_blob_run_params params;
    ks_blob_results *results = NULL;
    ks_image_8_grey *image = NULL;
    ks_image_8_grey *out = NULL;
    ks_pixel_region *region = NULL;
    const ks_transform_2d_linear identity = {1.0, 0.0, 0.0, 1.0, 0.0, 0.0};

    /* A: 10 x 10 of 255 with a 4 x 4 hole; B: 6 x 6 of 150 (soft level
       3 of 5 below). */
    ks_image_8_grey_create(40, 20, 0, &image, &status);
    fill_box(image, 2, 2, 11, 11, 255);
    fill_box(image, 5, 5, 8, 8, 0);
    fill_box(image, 20, 2, 25, 7, 255);
    ks_pixel_region_whole_image(40, 20, &region, &status);
    ks_blob_run_params_default(&params, &status);
    params.segmentation_params.mode = KS_BLOB_SEGMENTATION_HARD_FIXED_THRESHOLD;
    params.segmentation_params.polarity = KS_BLOB_POLARITY_LIGHT_BLOBS;
    params.save_segmented_image_before_masking = 1;
    ks_blob_execute(image, region, &params, &identity, &results, &status);
    check(status.failure == KS_FAILURE_NONE, "blob images: a run");

    ks_blob_results_create_blob_image(results, 1, 1, 0, &out, &status);
    check(status.failure == KS_FAILURE_NONE && pixel(out, 0, 0) == 128
          && pixel(out, 2, 2) == 255 && pixel(out, 6, 6) == 0
          && pixel(out, 21, 3) == 255,
          "blob images: viewable blob image (128, 255, holes 0)");
    ks_image_8_grey_destroy(&out, &status);
    ks_blob_results_create_blob_image(results, 0, 0, 9, &out, &status);
    check(status.failure == KS_FAILURE_NONE && pixel(out, 0, 0) == 9
          && pixel(out, 2, 2) == 1 && pixel(out, 6, 6) == 0,
          "blob images: blob image with a background");
    ks_image_8_grey_destroy(&out, &status);
    ks_blob_results_create_blob_image(results, 0, 0, 256, &out, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "CreateBlobImage: Background must be in 0 .. 255")
          && out == NULL,
          "blob images: background 256");

    ks_blob_results_create_segmented_image(
        results, KS_BLOB_SEGMENTED_FINAL_IMAGE, 1, &out, &status);
    check(status.failure == KS_FAILURE_NONE && out == NULL,
          "blob images: the final image was not saved (NULL)");
    ks_blob_results_create_segmented_image(
        results, KS_BLOB_SEGMENTED_BEFORE_MASKING, 1, &out, &status);
    check(status.failure == KS_FAILURE_NONE && out != NULL
          && pixel(out, 2, 2) == 255 && pixel(out, 6, 6) == 0
          && pixel(out, 0, 0) == 0,
          "blob images: the segmented image before masking, stretched");
    ks_image_8_grey_destroy(&out, &status);
    ks_blob_results_create_segmented_image(results, 3, 1, &out, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER && out == NULL,
          "blob images: which 3");
    ks_blob_results_destroy(&results, &status);

    ks_blob_results_create_blob_image(NULL, 1, 1, 0, &out, &status);
    check(status.failure == KS_FAILURE_IMAGE_NO_PIXELS && out == NULL,
          "blob images: NULL results");

    /* Soft: [100, 200) with softness 4; grey 150 is level 3 of 5. */
    fill_box(image, 20, 2, 25, 7, 150);
    ks_blob_segmentation_params_set_soft_fixed_threshold(
        &params.segmentation_params, 100, 200, 4,
        KS_BLOB_POLARITY_LIGHT_BLOBS, &status);
    params.save_segmented_image = 1;
    ks_blob_execute(image, region, &params, &identity, &results, &status);
    ks_blob_results_create_blob_image(results, 0, 0, 0, &out, &status);
    check(status.failure == KS_FAILURE_NONE && pixel(out, 21, 3) == 3
          && pixel(out, 2, 2) == 5,
          "blob images: soft levels in the blob image");
    ks_image_8_grey_destroy(&out, &status);
    ks_blob_results_create_blob_image(results, 0, 1, 0, &out, &status);
    check(pixel(out, 21, 3) == 235 && pixel(out, 2, 2) == 255,
          "blob images: soft levels, viewable");
    ks_image_8_grey_destroy(&out, &status);
    ks_blob_results_create_segmented_image(
        results, KS_BLOB_SEGMENTED_FINAL_IMAGE, 0, &out, &status);
    check(status.failure == KS_FAILURE_NONE && pixel(out, 21, 3) == 3,
          "blob images: soft segmented image");
    ks_image_8_grey_destroy(&out, &status);
    ks_blob_results_destroy(&results, &status);

    ks_pixel_region_destroy(&region, &status);
    ks_image_8_grey_destroy(&image, &status);
}

/* Soft segmentation: the default fields, the setters and a run with
   known weights. */
static void test_c_blob_soft(void)
{
    ks_status status;
    ks_blob_run_params params;
    ks_blob_segmentation_params before;
    ks_blob_results *results = NULL;
    ks_blob_result item;
    ks_image_8_grey *image = NULL;
    ks_pixel_region *region = NULL;
    const ks_transform_2d_linear identity = {1.0, 0.0, 0.0, 1.0, 0.0, 0.0};
    int32_t count = -1;

    ks_blob_run_params_default(&params, &status);
    check(status.failure == KS_FAILURE_NONE
          && params.segmentation_params.soft_fixed_threshold_low == 102
          && params.segmentation_params.soft_fixed_threshold_high == 153
          && params.segmentation_params.soft_relative_threshold_low == 40
          && params.segmentation_params.soft_relative_threshold_high == 60
          && params.segmentation_params.softness == 254,
          "blob soft: the default soft fields");

    /* The setters: a failure leaves the parameters unchanged. */
    before = params.segmentation_params;
    ks_blob_segmentation_params_set_soft_fixed_threshold(
        &params.segmentation_params, 100, 100, 3,
        KS_BLOB_POLARITY_LIGHT_BLOBS, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "SetSegmentationSoftFixedThreshold: "
                     "softFixedThresholdLow must be < "
                     "softFixedThresholdHigh")
          && memcmp(&before, &params.segmentation_params,
                    sizeof before) == 0,
          "blob soft: set_soft_fixed_threshold rejects low = high");
    ks_blob_segmentation_params_set_soft_fixed_threshold(
        &params.segmentation_params, 100, 200, 255,
        KS_BLOB_POLARITY_LIGHT_BLOBS, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "SetSegmentationSoftFixedThreshold: softness must be "
                     "in 0 .. 254"),
          "blob soft: set_soft_fixed_threshold rejects softness 255");
    ks_blob_segmentation_params_set_soft_fixed_threshold(
        &params.segmentation_params, 100, 200, 3, 2, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "SetSegmentationSoftFixedThreshold: polarity must be "
                     "DarkBlobs (0) or LightBlobs (1)"),
          "blob soft: set_soft_fixed_threshold rejects polarity 2");
    ks_blob_segmentation_params_set_soft_relative_threshold(
        &params.segmentation_params, 60, 41, 40, 60, 3,
        KS_BLOB_POLARITY_LIGHT_BLOBS, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "SetSegmentationSoftRelativeThreshold: tailLow + "
                     "tailHigh must be <= 100")
          && memcmp(&before, &params.segmentation_params,
                    sizeof before) == 0,
          "blob soft: set_soft_relative_threshold rejects tails 60 + 41");
    ks_blob_segmentation_params_set_soft_relative_threshold(
        &params.segmentation_params, 0, 0, 61, 60, 3,
        KS_BLOB_POLARITY_LIGHT_BLOBS, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "SetSegmentationSoftRelativeThreshold: "
                     "softRelativeThresholdLow must be <= "
                     "softRelativeThresholdHigh"),
          "blob soft: set_soft_relative_threshold rejects low > high");
    ks_blob_segmentation_params_set_hard_fixed_threshold(
        &params.segmentation_params, 65536, KS_BLOB_POLARITY_LIGHT_BLOBS,
        &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER,
          "blob soft: set_hard_fixed_threshold rejects 65536");
    ks_blob_segmentation_params_set_hard_relative_threshold(
        &params.segmentation_params, 0, 0, 101, KS_BLOB_POLARITY_LIGHT_BLOBS,
        &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER,
          "blob soft: set_hard_relative_threshold rejects 101");
    ks_blob_segmentation_params_set_hard_dynamic_threshold(
        &params.segmentation_params, 50, 51, KS_BLOB_POLARITY_LIGHT_BLOBS,
        &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER
          && memcmp(&before, &params.segmentation_params,
                    sizeof before) == 0,
          "blob soft: set_hard_dynamic_threshold rejects tails 50 + 51");
    ks_blob_segmentation_params_set_hard_dynamic_threshold(
        &params.segmentation_params, 2, 3, KS_BLOB_POLARITY_LIGHT_BLOBS,
        &status);
    check(status.failure == KS_FAILURE_NONE
          && params.segmentation_params.mode
               == KS_BLOB_SEGMENTATION_HARD_DYNAMIC_THRESHOLD
          && params.segmentation_params.tail_low == 2
          && params.segmentation_params.tail_high == 3,
          "blob soft: set_hard_dynamic_threshold");
    ks_blob_segmentation_params_set_hard_relative_threshold(
        &params.segmentation_params, 0, 0, 30, KS_BLOB_POLARITY_DARK_BLOBS,
        &status);
    check(status.failure == KS_FAILURE_NONE
          && params.segmentation_params.mode
               == KS_BLOB_SEGMENTATION_HARD_RELATIVE_THRESHOLD
          && params.segmentation_params.hard_relative_threshold == 30
          && params.segmentation_params.polarity
               == KS_BLOB_POLARITY_DARK_BLOBS,
          "blob soft: set_hard_relative_threshold");
    ks_blob_segmentation_params_set_hard_fixed_threshold(
        &params.segmentation_params, 7, KS_BLOB_POLARITY_LIGHT_BLOBS,
        &status);
    check(status.failure == KS_FAILURE_NONE
          && params.segmentation_params.mode
               == KS_BLOB_SEGMENTATION_HARD_FIXED_THRESHOLD
          && params.segmentation_params.hard_fixed_threshold == 7,
          "blob soft: set_hard_fixed_threshold");
    ks_blob_segmentation_params_set_soft_fixed_threshold(
        &params.segmentation_params, 100, 200, 3,
        KS_BLOB_POLARITY_LIGHT_BLOBS, &status);
    check(status.failure == KS_FAILURE_NONE
          && params.segmentation_params.mode
               == KS_BLOB_SEGMENTATION_SOFT_FIXED_THRESHOLD
          && params.segmentation_params.soft_fixed_threshold_low == 100
          && params.segmentation_params.soft_fixed_threshold_high == 200
          && params.segmentation_params.softness == 3
          && params.segmentation_params.polarity
               == KS_BLOB_POLARITY_LIGHT_BLOBS,
          "blob soft: set_soft_fixed_threshold");

    /* Band [100, 200) with softness 3: grey 100 has level 1 (weight 1/4),
       255 level 4 (weight 1). A: 10 x 10 of 100; B: 6 x 6 of 255; C: two
       columns of 5, x = 30 of 255 and x = 31 of 100. */
    ks_image_8_grey_create(40, 20, 0, &image, &status);
    fill_box(image, 2, 2, 11, 11, 100);
    fill_box(image, 20, 2, 25, 7, 255);
    fill_box(image, 30, 10, 30, 14, 255);
    fill_box(image, 31, 10, 31, 14, 100);
    ks_pixel_region_whole_image(40, 20, &region, &status);
    params.connectivity_cleanup = KS_BLOB_CLEANUP_NONE;
    params.sort_enabled = 0;
    ks_blob_execute(image, region, &params, &identity, &results, &status);
    ks_blob_results_count(results, 0, &count, &status);
    check(status.failure == KS_FAILURE_NONE && count == 3,
          "blob soft: three blobs");
    ks_blob_results_item(results, 0, 0, &item, &status);
    check(item.pixel_count == 100 && item.area == 25.0
          && fabs(item.center_of_mass_x - 6.5) < 1e-12,
          "blob soft: A weighs 1/4 a pixel (area 25)");
    ks_blob_results_item(results, 0, 1, &item, &status);
    check(item.pixel_count == 36 && item.area == 36.0,
          "blob soft: B weighs fully (area 36)");
    ks_blob_results_item(results, 0, 2, &item, &status);
    check(item.pixel_count == 10 && item.area == 6.25
          && fabs(item.center_of_mass_x - 30.2) < 1e-12
          && fabs(item.center_of_mass_y - 12.0) < 1e-12
          && fabs(item.inertia_y - (5.0 * 0.04 + 1.25 * 0.64 + 6.25 / 12.0))
               < 1e-12,
          "blob soft: C's centre of mass and moment are weighted");
    ks_blob_results_destroy(&results, &status);

    /* The relative band 40 .. 60 percent of 0 .. 255: [102, 153), so grey
       100 is background. */
    ks_blob_segmentation_params_set_soft_relative_threshold(
        &params.segmentation_params, 0, 0, 40, 60, 3,
        KS_BLOB_POLARITY_LIGHT_BLOBS, &status);
    ks_blob_execute(image, region, &params, &identity, &results, &status);
    ks_blob_results_count(results, 0, &count, &status);
    check(status.failure == KS_FAILURE_NONE && count == 2,
          "blob soft relative: grey 100 is below the band");
    ks_blob_results_item(results, 0, 1, &item, &status);
    check(item.pixel_count == 5 && item.area == 5.0
          && fabs(item.center_of_mass_x - 30.0) < 1e-12,
          "blob soft relative: C's bright column");
    ks_blob_results_destroy(&results, &status);

    params.segmentation_params.softness = 255;
    ks_blob_execute(image, region, &params, &identity, &results, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "RunParams.SegmentationParams.Softness must be in "
                     "0 .. 254")
          && results == NULL,
          "blob soft: execute checks softness");

    ks_pixel_region_destroy(&region, &status);
    ks_image_8_grey_destroy(&image, &status);
}

void test_c_blob(void)
{
    ks_status status;
    ks_blob_run_params params;
    ks_blob_results *results = NULL;
    ks_blob_result item;
    ks_image_8_grey *image = NULL;
    ks_image_16_grey *ids = NULL;
    ks_pixel_region *region = NULL;
    ks_polygon *boundary = NULL;
    ks_rectangle_affine box;
    const ks_transform_2d_linear identity = {1.0, 0.0, 0.0, 1.0, 0.0, 0.0};
    ks_transform_2d_linear scaled = {0.5, 0.0, 0.0, 0.5, 10.0, 20.0};
    ks_blob_measure measure;
    int32_t count = -1, parent = -2, vertices = 0;
    uint16_t id_pixel = 99;
    double value = -1.0, area = 0.0, median = -1.0;
    const double quarter = 0.78539816339744830962; /* pi / 4 */
    const double c5 = cos(0.5), s5 = sin(0.5);

    /* Run parameters. */
    memset(&params, 0xff, sizeof params);
    ks_blob_run_params_default(&params, &status);
    check(status.failure == KS_FAILURE_NONE
          && params.segmentation_params.mode
               == KS_BLOB_SEGMENTATION_HARD_DYNAMIC_THRESHOLD
          && params.segmentation_params.polarity == KS_BLOB_POLARITY_DARK_BLOBS
          && params.segmentation_params.hard_fixed_threshold == 128
          && params.segmentation_params.hard_relative_threshold == 50
          && params.segmentation_params.tail_low == 0
          && params.segmentation_params.tail_high == 0
          && params.connectivity_mode == KS_BLOB_CONNECTIVITY_GREY_SCALE
          && params.connectivity_cleanup == KS_BLOB_CLEANUP_FILL
          && params.connectivity_min_pixels == 10
          && params.sort_enabled == 1
          && params.sort_measure == KS_BLOB_MEASURE_AREA
          && params.sort_ascending == 0
          && params.run_time_measures.count == 0
          && params.morphology_operations.count == 0
          && params.extrema_angle == 0.0,
          "blob: run_params_default (the layout matches)");
    check(sizeof(ks_blob_run_params) == 2288
          && offsetof(ks_blob_run_params, extrema_angle) == 2264
          && offsetof(ks_blob_run_params, save_segmented_image) == 2272
          && params.save_segmented_image == 0
          && params.save_segmented_image_before_masking == 0
          && params.save_segmented_image_before_morphology == 0
          && sizeof(ks_blob_result) == 528
          && offsetof(ks_blob_result, extrema_angle_box) == 480,
          "blob: the layout of the run parameters and the result");
    memset(&measure, 0, sizeof measure);
    measure.measure = KS_BLOB_MEASURE_AREA;
    measure.mode = KS_BLOB_MEASURE_MODE_FILTER;
    measure.filter_mode = KS_BLOB_FILTER_INCLUDE_BLOBS_IN_RANGE;
    measure.filter_range_low = 50.0;
    measure.filter_range_high = 1.0e9;
    ks_blob_measure_collection_add(&params.run_time_measures, &measure,
                                   &status);
    check(status.failure == KS_FAILURE_NONE
          && params.run_time_measures.count == 1
          && params.run_time_measures.items[0].filter_range_low == 50.0,
          "blob: measure_collection_add");
    ks_blob_morphology_collection_add(&params.morphology_operations, 12,
                                      &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "MorphologyOperations.Add: the operation must be a "
                     "CogBlobMorphologyConstants value (0 .. 11)")
          && params.morphology_operations.count == 0,
          "blob: morphology_collection_add rejects 12");

    /* A 40 x 30 image: a 20 x 10 light rectangle (pixels 5 .. 24 by
       5 .. 14) with a 3 x 3 dark hole, and a 3 x 3 light square. */
    ks_image_8_grey_create(40, 30, 0, &image, &status);
    fill_box(image, 5, 5, 24, 14, 255);
    fill_box(image, 9, 8, 11, 10, 0);
    fill_box(image, 30, 20, 32, 22, 255);
    ks_pixel_region_whole_image(40, 30, &region, &status);
    params.segmentation_params.mode = KS_BLOB_SEGMENTATION_HARD_FIXED_THRESHOLD;
    params.segmentation_params.polarity = KS_BLOB_POLARITY_LIGHT_BLOBS;
    params.connectivity_cleanup = KS_BLOB_CLEANUP_NONE;

    ks_blob_execute(image, region, &params, &identity, &results, &status);
    check(status.failure == KS_FAILURE_NONE && results != NULL,
          "blob: execute");
    ks_blob_results_count(results, 0, &count, &status);
    check(status.failure == KS_FAILURE_NONE && count == 3,
          "blob: three features (blob, hole, square)");
    ks_blob_results_count(results, 1, &count, &status);
    check(count == 1, "blob: one passes the area filter");
    ks_blob_results_item(results, 1, 0, &item, &status);
    check(status.failure == KS_FAILURE_NONE && item.id == 0
          && item.pixel_count == 191 && item.area == 191.0
          && item.label == KS_BLOB_LABEL_BLOB && item.parent_id == -1
          && item.num_unfiltered_children == 1 && item.num_children == 0
          && item.filtered_out == 0 && item.not_clipped == 1,
          "blob: the filtered item");
    ks_blob_results_get_blob_by_id(results, 1, &item, &status);
    check(status.failure == KS_FAILURE_NONE && item.label == KS_BLOB_LABEL_HOLE
          && item.pixel_count == 9 && item.parent_id == 0
          && item.filtered_out == 1
          && fabs(item.center_of_mass_x - 10.0) < 1e-12,
          "blob: the hole");
    ks_blob_results_get_parent(results, 1, &parent, &status);
    check(status.failure == KS_FAILURE_NONE && parent == 0,
          "blob: get_parent");

    /* The tree: 0 the rectangle and 2 the square at the top, 1 the hole
       of 0; only 0 passes the filter. */
    ks_blob_results_related_count(results, KS_BLOB_RELATION_CHILDREN, 0, 0,
                                  &count, &status);
    ks_blob_results_related_id(results, KS_BLOB_RELATION_CHILDREN, 0, 0, 0,
                               &parent, &status);
    check(count == 1 && status.failure == KS_FAILURE_NONE && parent == 1,
          "blob: the children of 0");
    ks_blob_results_related_id(results, KS_BLOB_RELATION_CHILDREN, 0, 0, 1,
                               &parent, &status);
    check(status.failure == KS_FAILURE_INDEX_OUT_OF_RANGE && parent == -1,
          "blob: related_id outside the children");
    ks_blob_results_related_count(results, KS_BLOB_RELATION_CHILDREN, 0, 1,
                                  &count, &status);
    check(status.failure == KS_FAILURE_NONE && count == 0,
          "blob: no filtered child of 0");
    ks_blob_results_related_count(results, KS_BLOB_RELATION_SIBLINGS, 0, 0,
                                  &count, &status);
    ks_blob_results_related_id(results, KS_BLOB_RELATION_SIBLINGS, 0, 0, 0,
                               &parent, &status);
    check(count == 1 && parent == 2, "blob: the sibling of 0");
    ks_blob_results_related_count(results, KS_BLOB_RELATION_TOP_LEVEL, 0, 0,
                                  &count, &status);
    ks_blob_results_related_id(results, KS_BLOB_RELATION_TOP_LEVEL, 0, 0, 1,
                               &parent, &status);
    check(count == 2 && parent == 2, "blob: two top-level features");
    ks_blob_results_related_count(results, KS_BLOB_RELATION_TOP_LEVEL, 0, 1,
                                  &count, &status);
    check(count == 1, "blob: one filtered top-level feature");
    ks_blob_results_related_count(results, KS_BLOB_RELATION_CHILDREN, 3, 0,
                                  &count, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER && count == 0,
          "blob: the children of an unknown ID");
    ks_blob_results_related_count(results, 4, 0, 0, &count, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER,
          "blob: an unknown relation");
    ks_blob_results_related_count(NULL, KS_BLOB_RELATION_ALL, 0, 1, &count,
                                  &status);
    check(status.failure == KS_FAILURE_NONE && count == 0,
          "blob: no features in null results");
    ks_blob_results_get_blob_measure(results, KS_BLOB_MEASURE_CENTER_MASS_Y,
                                     2, &value, &status);
    check(status.failure == KS_FAILURE_NONE && value == 21.0,
          "blob: get_blob_measure");
    ks_blob_results_get_blob_measure(results, KS_BLOB_MEASURE_ACIRCULARITY_RMS,
                                     2, &value, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER && value == 0.0,
          "blob: get_blob_measure of a measure that is not computed");
    ks_blob_results_get_blob_by_id(results, 2, &item, &status);
    check(item.pixel_count == 9 && item.label == KS_BLOB_LABEL_BLOB,
          "blob: the small square");
    ks_blob_result_get_measure(&item, KS_BLOB_MEASURE_CENTER_MASS_Y, &value,
                               &status);
    check(status.failure == KS_FAILURE_NONE && value == 21.0,
          "blob: get_measure");
    ks_blob_result_get_measure(&item, KS_BLOB_MEASURE_ACIRCULARITY_RMS,
                               &value, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER && value == 0.0,
          "blob: get_measure of a measure that is not computed");
    ks_blob_result_get_bounding_box(&item, KS_BLOB_AXIS_PIXEL_ALIGNED, &box,
                                    &status);
    check(status.failure == KS_FAILURE_NONE && box.center_x == 31.0
          && box.side_x_length == 3.0 && box.side_y_length == 3.0,
          "blob: get_bounding_box");
    ks_blob_results_get_boundary(results, 0, &boundary, &status);
    ks_polygon_num_vertices(boundary, &vertices, &status);
    ks_polygon_area(boundary, &area, &status);
    check(vertices == 4 && area == 200.0,
          "blob: get_boundary of the blob (its outer boundary)");
    ks_polygon_destroy(&boundary, &status);

    /* Boxes at an angle and medians: the 3 x 3 square (id 2, pixels
       30 .. 32 by 20 .. 22, an odd count) and the rectangle with its hole
       (id 0, 191 pixels). */
    ks_blob_results_get_bounding_box_at_angle(results, 2, 0.0, &box,
                                              &status);
    check(status.failure == KS_FAILURE_NONE && box.center_x == 31.0
          && box.center_y == 21.0 && box.side_x_length == 3.0
          && box.side_y_length == 3.0 && box.rotation == 0.0
          && box.skew == 0.0,
          "blob: get_bounding_box_at_angle 0");
    ks_blob_results_get_bounding_box_at_angle(results, 2, quarter, &box,
                                              &status);
    check(status.failure == KS_FAILURE_NONE
          && fabs(box.center_x - 31.0) < 1e-12
          && fabs(box.center_y - 21.0) < 1e-12
          && fabs(box.side_x_length - 3.0 * sqrt(2.0)) < 1e-12
          && fabs(box.side_y_length - 3.0 * sqrt(2.0)) < 1e-12
          && box.rotation == quarter,
          "blob: get_bounding_box_at_angle pi/4 (the square's diagonals)");
    ks_blob_results_get_bounding_box_at_angle(results, 2, NAN, &box, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "GetBoundingBoxAtAngle: Angle must be finite and "
                     "within +/-1.0E6"),
          "blob: get_bounding_box_at_angle of a NaN");
    ks_blob_results_get_bounding_box_at_angle(NULL, 0, 0.0, &box, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "GetBoundingBoxAtAngle: no blob has ID 0"),
          "blob: get_bounding_box_at_angle on NULL results");
    ks_blob_results_get_median_x(results, 2, KS_BLOB_AXIS_SELECTED_SPACE,
                                 &median, &status);
    check(status.failure == KS_FAILURE_NONE && median == 31.0,
          "blob: get_median_x of the square");
    ks_blob_results_get_median_y(results, 2, KS_BLOB_AXIS_PIXEL_ALIGNED,
                                 &median, &status);
    check(status.failure == KS_FAILURE_NONE && median == 21.0,
          "blob: get_median_y of the square");
    ks_blob_results_get_median_x(results, 2, KS_BLOB_AXIS_PRINCIPAL,
                                 &median, &status);
    check(status.failure == KS_FAILURE_NONE && median == 0.0,
          "blob: get_median_x along the principal axis (from the centre)");
    ks_blob_results_get_median_x(results, 0, KS_BLOB_AXIS_SELECTED_SPACE,
                                 &median, &status);
    check(status.failure == KS_FAILURE_NONE && fabs(median - 15.0) < 1e-12,
          "blob: get_median_x of the rectangle with a hole");
    ks_blob_results_get_median_y(results, 0, KS_BLOB_AXIS_SELECTED_SPACE,
                                 &median, &status);
    check(status.failure == KS_FAILURE_NONE && fabs(median - 10.0) < 1e-12,
          "blob: get_median_y of the rectangle with a hole");
    ks_blob_results_get_median_y(results, 0, 5, &median, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "GetMedianY: Axis must be a CogBlobAxisConstants "
                     "value (0 .. 4)"),
          "blob: get_median_y of a bad axis");
    ks_blob_results_get_median_x(results, 3, KS_BLOB_AXIS_PRINCIPAL,
                                 &median, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "GetMedianX: no blob has ID 3"),
          "blob: get_median_x of an unknown id");
    ks_blob_results_create_blob_id_image(results, 0, &ids, &status);
    check(status.failure == KS_FAILURE_NONE && ids != NULL,
          "blob: create_blob_id_image");
    ks_image_16_grey_get_pixel(ids, 10, 9, &id_pixel, &status);
    check(id_pixel == 2, "blob: the hole's pixels hold its id + 1");
    ks_image_16_grey_get_pixel(ids, 0, 0, &id_pixel, &status);
    check(id_pixel == 0, "blob: background pixels hold 0");
    ks_image_16_grey_destroy(&ids, &status);
    ks_blob_results_item(results, 1, 1, &item, &status);
    check(is_failure(&status, KS_FAILURE_INDEX_OUT_OF_RANGE,
                     "GetBlobs: index 1 is outside 0 .. 0"),
          "blob: item beyond the filtered collection");
    ks_blob_results_destroy(&results, &status);
    check(status.failure == KS_FAILURE_NONE && results == NULL,
          "blob: destroy");

    /* The selected space scaled by 1/2 and moved. */
    params.connectivity_cleanup = KS_BLOB_CLEANUP_FILL;
    ks_blob_execute(image, region, &params, &scaled, &results, &status);
    ks_blob_results_item(results, 1, 0, &item, &status);
    check(status.failure == KS_FAILURE_NONE && item.area == 50.0
          && fabs(item.center_of_mass_x - (10.0 + 0.5 * 14.5)) < 1e-12
          && fabs(item.center_of_mass_y - (20.0 + 0.5 * 9.5)) < 1e-12,
          "blob: fill, measured in the selected space");
    ks_blob_results_destroy(&results, &status);

    /* The extrema-angle measures at 0.5 rad (identity transform): the
       square spans u = x cos + y sin and v = -x sin + y cos over its
       corners 29.5 .. 32.5 by 19.5 .. 22.5. */
    params.extrema_angle = 0.5;
    params.connectivity_cleanup = KS_BLOB_CLEANUP_NONE;
    ks_blob_execute(image, region, &params, &identity, &results, &status);
    check(status.failure == KS_FAILURE_NONE, "blob: execute at 0.5 rad");
    ks_blob_results_get_blob_by_id(results, 2, &item, &status);
    check(fabs(item.extrema_angle_min_x - (29.5 * c5 + 19.5 * s5)) < 1e-12
          && fabs(item.extrema_angle_max_x - (32.5 * c5 + 22.5 * s5)) < 1e-12
          && fabs(item.extrema_angle_min_y - (-32.5 * s5 + 19.5 * c5)) < 1e-12
          && fabs(item.extrema_angle_max_y - (-29.5 * s5 + 22.5 * c5)) < 1e-12
          && fabs(item.extrema_angle_width - 3.0 * (c5 + s5)) < 1e-12
          && fabs(item.extrema_angle_height - 3.0 * (c5 + s5)) < 1e-12
          && fabs(item.extrema_angle_aspect - 1.0) < 1e-12
          && fabs(item.extrema_angle_center_x - (31.0 * c5 + 21.0 * s5))
               < 1e-12
          && fabs(item.median_extrema_angle_x - (31.0 * c5 + 21.0 * s5))
               < 1e-12
          && fabs(item.median_extrema_angle_y - (-31.0 * s5 + 21.0 * c5))
               < 1e-12
          && item.extrema_angle_box.rotation == 0.5
          && fabs(item.extrema_angle_box.center_x - 31.0) < 1e-12,
          "blob: the extrema-angle measures of the square");
    ks_blob_result_get_measure(&item, KS_BLOB_MEASURE_MEDIAN_EXTREMA_ANGLE_Y,
                               &value, &status);
    check(status.failure == KS_FAILURE_NONE
          && value == item.median_extrema_angle_y,
          "blob: get_measure of an extrema-angle measure");
    ks_blob_result_get_bounding_box(&item, KS_BLOB_AXIS_EXTREMA_ANGLE, &box,
                                    &status);
    check(status.failure == KS_FAILURE_NONE && box.rotation == 0.5
          && box.side_x_length == item.extrema_angle_width,
          "blob: get_bounding_box along the extrema angle");
    ks_blob_results_get_median_x(results, 2, KS_BLOB_AXIS_EXTREMA_ANGLE,
                                 &median, &status);
    check(status.failure == KS_FAILURE_NONE
          && median == item.median_extrema_angle_x,
          "blob: get_median_x along the extrema angle");
    ks_blob_results_destroy(&results, &status);
    params.extrema_angle = NAN;
    ks_blob_execute(image, region, &params, &identity, &results, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "RunParams.ExtremaAngle must be finite and within "
                     "+/-1.0E6") && results == NULL,
          "blob: a NaN extrema angle");
    params.extrema_angle = 0.0;
    params.connectivity_cleanup = KS_BLOB_CLEANUP_FILL;

    /* Failures. */
    ks_blob_execute(NULL, region, &params, &identity, &results, &status);
    check(is_failure(&status, KS_FAILURE_IMAGE_NO_PIXELS,
                     "InputImage has no pixels") && results == NULL,
          "blob: execute without an image");
    scaled.a = NAN;
    ks_blob_execute(image, region, &params, &scaled, &results, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER && results == NULL,
          "blob: a NaN transform");
    params.connectivity_min_pixels = -1;
    ks_blob_execute(image, region, &params, &identity, &results, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "RunParams.ConnectivityMinPixels must be >= 0")
          && results == NULL,
          "blob: a negative minimum");
    params.connectivity_min_pixels = 10;
    params.segmentation_params.mode = KS_BLOB_SEGMENTATION_MAP;
    ks_blob_execute(image, region, &params, &identity, &results, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER && results == NULL,
          "blob: map segmentation is not supported");
    params.segmentation_params.mode = KS_BLOB_SEGMENTATION_HARD_FIXED_THRESHOLD;
    ks_blob_execute(image, NULL, &params, &identity, &results, &status);
    ks_blob_results_count(results, 0, &count, &status);
    check(status.failure == KS_FAILURE_NONE && count == 0,
          "blob: the empty region finds nothing");
    ks_blob_results_destroy(&results, &status);
    ks_blob_results_count(NULL, 1, &count, &status);
    check(status.failure == KS_FAILURE_NONE && count == 0,
          "blob: NULL results have no features");
    ks_blob_results_get_blob_by_id(NULL, 0, &item, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "GetBlobByID: no blob has ID 0"),
          "blob: get_blob_by_id on NULL results");
    ks_blob_results_create_blob_id_image(NULL, 1, &ids, &status);
    check(status.failure == KS_FAILURE_IMAGE_NO_PIXELS && ids == NULL,
          "blob: create_blob_id_image on NULL results");
    ks_blob_results_destroy(&results, &status);
    check(status.failure == KS_FAILURE_NONE && results == NULL,
          "blob: destroy NULL");

    ks_pixel_region_destroy(&region, &status);
    ks_image_8_grey_destroy(&image, &status);

    test_c_blob_soft();
    test_c_blob_images();
}
