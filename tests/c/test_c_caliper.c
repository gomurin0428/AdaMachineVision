/*
 * Tests of the caliper tools' C API (include/amv_caliper.h): the caliper
 * on axis-aligned steps and bars whose edges lie exactly between pixel
 * centres, the scorer lists, failures; then find line and find circle.
 */

#include <math.h>
#include <stdio.h>
#include <string.h>

#include "amv.h"
#include "c_test_support.h"

void test_c_caliper(void);

static const ks_transform_2d_linear identity = {1.0, 0.0, 0.0, 1.0, 0.0,
                                                0.0};

/* A width x height image of value low, with value high in the columns
   x_first .. x_last. */
static ks_image_8_grey *columns(int32_t width, int32_t height, int32_t x_first,
                                int32_t x_last, uint8_t low, uint8_t high)
{
    ks_status status;
    ks_image_8_grey *image = NULL;
    int32_t x, y;

    ks_image_8_grey_create(width, height, low, &image, &status);
    for (y = 0; y < height; y++) {
        for (x = x_first; x <= x_last; x++) {
            ks_image_8_grey_set_pixel(image, x, y, high, &status);
        }
    }
    return image;
}

static void test_caliper_run(void)
{
    ks_status status;
    ks_caliper_run_params params;
    ks_caliper_results *results = NULL, *copy = NULL;
    ks_caliper_result item;
    ks_rectangle_affine region = {50.0, 50.0, 40.0, 10.0, 0.0, 0.0};
    ks_image_8_grey *image;
    int32_t count = -1, length = -1;
    double value = -1.0;

    ks_caliper_run_params_default(&params, &status);
    check(status.failure == KS_FAILURE_NONE
          && params.edge_mode == KS_CALIPER_EDGE_MODE_SINGLE_EDGE
          && params.edge_0_polarity == KS_CALIPER_POLARITY_DONT_CARE
          && params.edge_1_position == 10.0
          && params.contrast_threshold == 5.0
          && params.filter_half_size_in_pixels == 2
          && params.max_results == 1
          && params.single_edge_scorers.count == 1
          && params.single_edge_scorers.items[0].kind
               == KS_CALIPER_SCORER_CONTRAST
          && params.two_edge_scorers.count == 1
          && params.two_edge_scorers.items[0].kind
               == KS_CALIPER_SCORER_SIZE_DIFF_NORM,
          "caliper: run params default");

    ks_caliper_execute(NULL, &region, &identity, &identity, &params,
                       &results, &status);
    check(is_failure(&status, KS_FAILURE_IMAGE_NO_PIXELS,
                     "InputImage has no pixels")
          && results == NULL,
          "caliper: a NULL image");

    /* A step between columns 51 and 52 (x = 51.5). */
    image = columns(100, 100, 52, 99, 40, 200);
    ks_caliper_execute(image, &region, &identity, &identity, &params,
                       &results, &status);
    check(status.failure == KS_FAILURE_NONE && results != NULL,
          "caliper: execute");
    ks_caliper_results_count(results, &count, &status);
    ks_caliper_results_item(results, 0, &item, &status);
    check(count == 1 && fabs(item.position - 1.5) < 1e-9
          && fabs(item.position_x - 51.5) < 1e-9
          && fabs(item.position_y - 50.0) < 1e-9
          && item.edge_0.contrast > 0.0 && item.width == 0.0,
          "caliper: the step at 51.5");
    ks_caliper_results_item(results, 1, &item, &status);
    check(status.failure == KS_FAILURE_INDEX_OUT_OF_RANGE,
          "caliper: item beyond count");
    ks_caliper_results_profile_length(results, &length, &status);
    ks_caliper_results_projection_value(results, 0, &value, &status);
    check(length == 40 && value == 40.0, "caliper: projection profile");
    ks_caliper_results_filtered_value(results, 21, &value, &status);
    check(status.failure == KS_FAILURE_NONE && value == 120.0,
          "caliper: filtered value at the step");
    ks_caliper_results_duplicate(results, &copy, &status);
    ks_caliper_results_count(copy, &count, &status);
    check(copy != NULL && count == 1, "caliper: duplicate");
    ks_caliper_results_destroy(&copy);
    ks_caliper_results_destroy(&results);
    check(results == NULL && copy == NULL, "caliper: destroy");
    ks_caliper_results_destroy(&results);
    ks_image_8_grey_destroy(&image, &status);

    /* A bar over columns 45 .. 54: edges at 44.5 and 54.5. */
    image = columns(100, 100, 45, 54, 30, 220);
    params.edge_mode = KS_CALIPER_EDGE_MODE_PAIR;
    params.edge_0_polarity = KS_CALIPER_POLARITY_DARK_TO_LIGHT;
    params.edge_1_polarity = KS_CALIPER_POLARITY_LIGHT_TO_DARK;
    ks_caliper_execute(image, &region, &identity, &identity, &params,
                       &results, &status);
    ks_caliper_results_count(results, &count, &status);
    ks_caliper_results_item(results, 0, &item, &status);
    check(count == 1 && fabs(item.width - 10.0) < 1e-9
          && fabs(item.position + 0.5) < 1e-9
          && fabs(item.edge_0.position + 5.5) < 1e-9
          && fabs(item.edge_1.position - 4.5) < 1e-9
          && fabs(item.score - 1.0) < 1e-12,
          "caliper: the pair of the bar");
    ks_caliper_results_destroy(&results);

    params.contrast_threshold = NAN;
    ks_caliper_execute(image, &region, &identity, &identity, &params,
                       &results, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "RunParams.ContrastThreshold must be >= 0")
          && results == NULL,
          "caliper: a NaN threshold");
    ks_caliper_check_run_params(&params, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER,
          "caliper: check_run_params");
    ks_caliper_run_params_default(&params, &status);
    region.side_x_length = 0.0;
    ks_caliper_execute(image, &region, &identity, &identity, &params,
                       &results, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Region.SideXLength must be > 0"),
          "caliper: a side of length 0");
    ks_image_8_grey_destroy(&image, &status);
}

static void test_caliper_scorers(void)
{
    ks_status status;
    ks_caliper_scorer scorer, changed;
    ks_caliper_scorers list;
    int32_t value;
    int i;

    memset(&list, 0, sizeof list);
    ks_caliper_scorer_default(KS_CALIPER_SCORER_POSITION, &scorer, &status);
    check(status.failure == KS_FAILURE_NONE
          && scorer.kind == KS_CALIPER_SCORER_POSITION && scorer.enabled == 1,
          "scorers: default position scorer");
    ks_caliper_scorer_default(42, &scorer, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER,
          "scorers: unknown kind");
    ks_caliper_scorer_default(KS_CALIPER_SCORER_CONTRAST, &scorer, &status);
    ks_caliper_scorer_set_xy_parameters(&scorer, 1.0, 2.0, 3.0, 0.25, 0.75,
                                        &changed, &status);
    check(status.failure == KS_FAILURE_NONE && changed.x0 == 1.0
          && changed.x1 == 2.0 && changed.xc == 3.0 && changed.y0 == 0.25
          && changed.y1 == 0.75 && changed.kind == scorer.kind,
          "scorers: set_xy_parameters");
    ks_caliper_scorer_set_xy_parameters(&scorer, 1.0, 2.0, 3.0, 1.5, 0.75,
                                        &changed, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "SetXYParameters: y0 must be within [0, 1]"),
          "scorers: y0 out of range");
    for (i = 0; i < KS_CALIPER_MAX_SCORERS; i++) {
        ks_caliper_scorers_add(&list, &scorer, &status);
    }
    check(list.count == KS_CALIPER_MAX_SCORERS, "scorers: a full list");
    ks_caliper_scorers_add(&list, &scorer, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER
          && list.count == KS_CALIPER_MAX_SCORERS,
          "scorers: adding to a full list fails");
    ks_caliper_scorers_remove_at(&list, 0, &status);
    check(status.failure == KS_FAILURE_NONE && list.count == 7,
          "scorers: remove_at");
    ks_caliper_scorers_remove_at(&list, 7, &status);
    check(status.failure == KS_FAILURE_INDEX_OUT_OF_RANGE,
          "scorers: remove_at beyond count");

    /* Reading a count, a kind and a flag that may have been set by hand. */
    ks_caliper_scorers_count(&list, &value, &status);
    check(status.failure == KS_FAILURE_NONE && value == 7, "scorers: count");
    list.count = -1;
    ks_caliper_scorers_count(&list, &value, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Scorers.Count must be in 0 .. 8")
          && value == 0,
          "scorers: a negative count");
    ks_caliper_scorer_get_kind(&scorer, &value, &status);
    check(status.failure == KS_FAILURE_NONE
          && value == KS_CALIPER_SCORER_CONTRAST,
          "scorers: get_kind");
    scorer.kind = 9;
    ks_caliper_scorer_get_kind(&scorer, &value, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER && value == 0,
          "scorers: get_kind of an unknown kind");
    ks_caliper_scorer_get_enabled(&scorer, &value, &status);
    check(status.failure == KS_FAILURE_NONE && value == 1,
          "scorers: get_enabled");
    scorer.enabled = 2;
    ks_caliper_scorer_get_enabled(&scorer, &value, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER && value == 0,
          "scorers: get_enabled of a flag that is not 0 or 1");
}

static void test_find_line(void)
{
    ks_status status;
    ks_find_line_run_params params;
    ks_find_line_results *results = NULL;
    ks_find_line_result item;
    ks_caliper_results *caliper = NULL;
    ks_rectangle_affine region;
    ks_line line;
    ks_line_segment segment;
    ks_image_8_grey *image = NULL;
    int32_t count = -1, found = -1, used = -1, x, y;
    double rms = -1.0;

    /* Rows 50 .. 99 bright: an edge at y = 49.5. */
    ks_image_8_grey_create(100, 100, 40, &image, &status);
    for (y = 50; y < 100; y++) {
        for (x = 0; x < 100; x++) {
            ks_image_8_grey_set_pixel(image, x, y, 200, &status);
        }
    }
    ks_find_line_run_params_default(&params, &status);
    check(status.failure == KS_FAILURE_NONE && params.num_calipers == 6
          && params.caliper_search_length == 30.0
          && params.caliper_run_params.max_results == 1,
          "find line: run params default");
    params.num_calipers = 5;
    params.expected_line_segment.start_x = 10.0;
    params.expected_line_segment.start_y = 52.0;
    params.expected_line_segment.end_x = 90.0;
    params.expected_line_segment.end_y = 52.0;
    ks_find_line_caliper_region(&params, 4, &region, &status);
    check(status.failure == KS_FAILURE_NONE && region.center_x == 90.0
          && region.center_y == 52.0 && region.side_x_length == 30.0,
          "find line: the last caliper sits on the end point");
    ks_find_line_caliper_region(&params, 5, &region, &status);
    check(status.failure == KS_FAILURE_INDEX_OUT_OF_RANGE,
          "find line: caliper region beyond num_calipers");

    ks_find_line_execute(image, &params, &identity, &identity, &results,
                         &status);
    check(status.failure == KS_FAILURE_NONE && results != NULL,
          "find line: execute");
    ks_find_line_results_count(results, &count, &status);
    ks_find_line_results_fit(results, &rms, &found, &used, &status);
    check(count == 5 && found == 5 && used == 5 && rms < 1e-9,
          "find line: five points on the line");
    ks_find_line_results_line(results, &line, &segment, &status);
    check(status.failure == KS_FAILURE_NONE && fabs(line.y - 49.5) < 1e-9
          && fabs(line.rotation) < 1e-9
          && fabs(segment.start_x - 10.0) < 1e-9
          && fabs(segment.end_x - 90.0) < 1e-9
          && fabs(segment.start_y - 49.5) < 1e-9,
          "find line: the line y = 49.5 and its segment");
    ks_find_line_results_item(results, 2, &item, &status);
    check(item.found == 1 && item.used == 1 && fabs(item.x - 50.0) < 1e-9
          && fabs(item.y - 49.5) < 1e-9 && item.distance_to_line < 1e-9,
          "find line: an item");
    ks_find_line_results_caliper_results(results, 2, &caliper, &status);
    ks_caliper_results_count(caliper, &count, &status);
    check(caliper != NULL && count == 1,
          "find line: an item's caliper results");
    ks_caliper_results_destroy(&caliper);
    ks_find_line_results_destroy(&results);
    check(results == NULL, "find line: destroy");

    params.num_calipers = 1;
    ks_find_line_execute(image, &params, &identity, &identity, &results,
                         &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "RunParams.NumCalipers must be in 2 .. 1000")
          && results == NULL,
          "find line: one caliper");
    params.num_calipers = 5;
    params.expected_line_segment.start_y = 10.0;
    params.expected_line_segment.end_y = 10.0;
    ks_find_line_execute(image, &params, &identity, &identity, &results,
                         &status);
    check(is_failure(&status, KS_FAILURE_OTHER,
                     "FindLine: fewer than 2 points remain to fit"
                     " (NumPointsFound = 0, NumToIgnore = 0)")
          && results == NULL,
          "find line: no edge in reach");
    ks_image_8_grey_destroy(&image, &status);
}

static void test_find_circle(void)
{
    ks_status status;
    ks_find_circle_run_params params;
    ks_find_circle_results *results = NULL;
    ks_find_circle_result item;
    ks_circle circle;
    ks_circular_arc arc;
    ks_image_8_grey *image = NULL;
    int32_t count = -1, found = -1, used = -1, x, y;
    double rms = -1.0;

    /* A disc of radius 30 around (60, 50), pixel centres inside. */
    ks_image_8_grey_create(120, 100, 30, &image, &status);
    for (y = 0; y < 100; y++) {
        for (x = 0; x < 120; x++) {
            if ((x - 60.0) * (x - 60.0) + (y - 50.0) * (y - 50.0)
                <= 30.0 * 30.0) {
                ks_image_8_grey_set_pixel(image, x, y, 220, &status);
            }
        }
    }
    ks_find_circle_run_params_default(&params, &status);
    check(status.failure == KS_FAILURE_NONE && params.num_calipers == 6
          && params.caliper_search_direction
               == KS_FIND_CIRCLE_SEARCH_DIRECTION_INWARD
          && params.radius_constraint == 100.0,
          "find circle: run params default");
    params.num_calipers = 12;
    params.caliper_projection_length = 4.0;
    params.expected_circular_arc.center_x = 61.0;
    params.expected_circular_arc.center_y = 49.0;
    params.expected_circular_arc.radius = 28.0;
    params.expected_circular_arc.angle_start = 0.1;
    params.expected_circular_arc.angle_span = 6.3;
    ks_find_circle_execute(image, &params, &identity, &identity, &results,
                           &status);
    check(status.failure == KS_FAILURE_NONE && results != NULL,
          "find circle: execute");
    ks_find_circle_results_count(results, &count, &status);
    ks_find_circle_results_fit(results, &rms, &found, &used, &status);
    check(count == 12 && found == 12 && used == 12 && rms < 0.5,
          "find circle: twelve points");
    ks_find_circle_results_circle(results, &circle, &arc, &status);
    check(status.failure == KS_FAILURE_NONE
          && fabs(circle.center_x - 60.0) < 0.2
          && fabs(circle.center_y - 50.0) < 0.2
          && fabs(circle.radius - 30.0) < 0.3
          && arc.radius == circle.radius,
          "find circle: the circle of the disc");
    ks_find_circle_results_item(results, 0, &item, &status);
    check(item.found == 1 && item.used == 1 && item.distance_to_circle < 0.5,
          "find circle: an item");
    ks_find_circle_results_destroy(&results);
    check(results == NULL, "find circle: destroy");

    params.radius_constraint_enabled = 1;
    params.radius_constraint = 30.0;
    params.num_to_ignore = 2;
    ks_find_circle_execute(image, &params, &identity, &identity, &results,
                           &status);
    ks_find_circle_results_circle(results, &circle, &arc, &status);
    ks_find_circle_results_fit(results, &rms, &found, &used, &status);
    check(status.failure == KS_FAILURE_NONE && circle.radius == 30.0
          && fabs(circle.center_x - 60.0) < 0.2
          && fabs(circle.center_y - 50.0) < 0.2 && used == 10,
          "find circle: the radius constraint, two points ignored");
    ks_find_circle_results_destroy(&results);

    params.caliper_search_direction = 2;
    ks_find_circle_execute(image, &params, &identity, &identity, &results,
                           &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "RunParams.CaliperSearchDirection must be Inward (0) or"
                     " Outward (1)")
          && results == NULL,
          "find circle: a bad search direction");
    ks_image_8_grey_destroy(&image, &status);
}

void test_c_caliper(void)
{
    test_caliper_run();
    test_caliper_scorers();
    test_find_line();
    test_find_circle();
}
