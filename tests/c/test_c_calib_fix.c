/*
 * Tests of the fixture and calibration C API (include/amv_calib_fix.h):
 * the point pair list, the fits of every DOF on points made from a known
 * transform, the fixture tools on a coordinate space tree, the N-point
 * calibration, the checkerboard calibration on a checkerboard drawn
 * here with its corners between pixels, the origin adjustment of an
 * N-point calibration with an aspect (a pixel as the origin, an axis
 * given in pixels, swapped), and the nonlinear mode on a board drawn
 * through a barrel lens, of a checkerboard calibration and of an N-point
 * calibration whose pairs come from that lens; failures, NULL handles and
 * NaN included.
 */

#include <math.h>
#include <stdio.h>
#include <string.h>

#include "amv.h"
#include "c_test_support.h"

void test_c_calib_fix(void);

static const ks_transform_2d_linear identity = {1.0, 0.0, 0.0, 1.0, 0.0,
                                                0.0};

static const double b_x[6] = {-40.0, -10.0, 25.0, 60.0, -55.0, 12.0};
static const double b_y[6] = {-30.0, -45.0, -25.0, 40.0, 10.0, 55.0};

static void map(const ks_transform_2d_linear *t, double x, double y,
                double *u, double *v)
{
    *u = t->a * x + t->b * y + t->translation_x;
    *v = t->c * x + t->d * y + t->translation_y;
}

static int near(double a, double b, double tolerance)
{
    return fabs(a - b) <= tolerance;
}

static int same_transform(const ks_transform_2d_linear *a,
                          const ks_transform_2d_linear *b, double tolerance)
{
    return near(a->a, b->a, tolerance) && near(a->b, b->b, tolerance)
        && near(a->c, b->c, tolerance) && near(a->d, b->d, tolerance)
        && near(a->translation_x, b->translation_x, 100.0 * tolerance)
        && near(a->translation_y, b->translation_y, 100.0 * tolerance);
}

static void test_pairs_and_fits(void)
{
    ks_status status;
    ks_point_pairs *pairs = NULL, *copy = NULL;
    ks_n_point_to_n_point_fit fit;
    int32_t count = -1;
    double x, y, u, v;
    int i;
    /* A similarity: scale 2, rotation 0.5, shift (10, -5). */
    const double s = 2.0, r = 0.5;
    const ks_transform_2d_linear truth = {s * cos(r), -s * sin(r),
                                          s * sin(r), s * cos(r), 10.0, -5.0};

    ks_point_pairs_num_points(NULL, &count, &status);
    check(status.failure == KS_FAILURE_NONE && count == 0,
          "calib fix: NULL pairs are empty");
    for (i = 0; i < 6; i++) {
        map(&truth, b_x[i], b_y[i], &u, &v);
        ks_point_pairs_add_point_pair(&pairs, u, v, b_x[i], b_y[i], &status);
    }
    ks_point_pairs_num_points(pairs, &count, &status);
    check(status.failure == KS_FAILURE_NONE && count == 6,
          "calib fix: six pairs");
    ks_point_pairs_get_point(pairs, 3, KS_POINT_GROUP_B, &x, &y, &status);
    check(status.failure == KS_FAILURE_NONE && x == 60.0 && y == 40.0,
          "calib fix: a group B point");
    ks_point_pairs_get_point(pairs, 6, KS_POINT_GROUP_A, &x, &y, &status);
    check(status.failure == KS_FAILURE_INDEX_OUT_OF_RANGE && x == 0.0,
          "calib fix: an index beyond the end");
    ks_point_pairs_add_point_pair(&pairs, NAN, 0.0, 0.0, 0.0, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "AddPointPair: every coordinate must be finite and "
                     "within +/-1.0E150"),
          "calib fix: a NaN coordinate");

    ks_n_point_to_n_point_compute(pairs,
                                  KS_DOF_SCALING_ROTATION_AND_TRANSLATION,
                                  &fit, &status);
    check(status.failure == KS_FAILURE_NONE
          && same_transform(&fit.transform, &truth, 1e-12)
          && fit.rms_error < 1e-12 && near(fit.scaling_x, 2.0, 1e-12)
          && fit.scaling_y == fit.scaling_x && near(fit.rotation, r, 1e-12)
          && fit.transform.a == fit.transform.d
          && fit.transform.b == -fit.transform.c,
          "calib fix: similarity recovered with its parameters");
    ks_n_point_to_n_point_compute(
        pairs, KS_DOF_SCALING_ASPECT_ROTATION_SKEW_AND_TRANSLATION, &fit,
        &status);
    check(status.failure == KS_FAILURE_NONE
          && same_transform(&fit.transform, &truth, 1e-12),
          "calib fix: affine fit of a similarity");
    ks_n_point_to_n_point_compute(pairs, KS_DOF_ROTATION_AND_TRANSLATION,
                                  &fit, &status);
    check(status.failure == KS_FAILURE_NONE && near(fit.rotation, r, 1e-12)
          && fit.transform.a == cos(fit.rotation)
          && fit.transform.c == sin(fit.rotation) && fit.rms_error > 1.0,
          "calib fix: rigid fit, unit scale (scale 2 leaves an error)");
    ks_n_point_to_n_point_compute(pairs, 8, &fit, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "DOFsToCompute must be a CogNPointToNPointDOFConstants "
                     "value (0 .. 7)")
          && fit.transform.a == 1.0 && fit.rms_error == 0.0,
          "calib fix: a bad DOF code, identity result");

    ks_point_pairs_duplicate(pairs, &copy, &status);
    ks_point_pairs_delete_point_pair(copy, 0, &status);
    ks_point_pairs_delete_point_pair(copy, 0, &status);
    ks_point_pairs_delete_point_pair(copy, 0, &status);
    ks_point_pairs_delete_point_pair(copy, 0, &status);
    ks_point_pairs_delete_point_pair(copy, 0, &status);
    ks_n_point_to_n_point_compute(
        copy, KS_DOF_SCALING_ASPECT_ROTATION_AND_TRANSLATION, &fit, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "NumPoints must be at least 3 for these DOFsToCompute"),
          "calib fix: too few pairs for the aspect fit");
    ks_point_pairs_destroy(&copy);
    ks_point_pairs_destroy(&pairs);
    check(pairs == NULL && copy == NULL, "calib fix: destroy");
}

static void test_fixtures(void)
{
    ks_status status;
    ks_coordinate_space_tree tree;
    ks_space_name selected = space_name("@");
    ks_space_name root = space_name("@");
    ks_fixture_run_params params;
    ks_fixture_n_point_to_n_point_run_params np;
    ks_image_8_grey *image = NULL;
    ks_point_pairs *pairs = NULL;
    ks_n_point_to_n_point_fit fit;
    ks_transform_2d_linear t;
    const ks_transform_2d_linear pose = {0.0, -1.0, 1.0, 0.0, 30.0, 20.0};
    int32_t exists = 0;
    double u, v;
    int i;

    ks_coordinate_space_tree_init(&tree, &status);
    ks_image_8_grey_create(16, 16, 0, &image, &status);
    ks_fixture_run_params_default(&params, &status);
    check(has_name(&params.fixtured_space_name, "Fixture")
          && params.space_to_output == KS_SPACE_TO_OUTPUT_NEW
          && params.fixtured_space_name_duplicate_handling
                 == KS_FIXTURED_SPACE_NAME_DUPLICATE_COMPATIBILITY,
          "calib fix: fixture defaults");
    params.unfixtured_from_fixtured_transform = pose;
    ks_fixture_execute(NULL, &params, &tree, &selected, &identity, &status);
    check(is_failure(&status, KS_FAILURE_IMAGE_NO_PIXELS,
                     "InputImage has no pixels"),
          "calib fix: fixture of NULL");
    ks_fixture_execute(image, &params, &tree, &selected, &identity, &status);
    check(status.failure == KS_FAILURE_NONE
          && has_name(&selected, "@\\Fixture") && tree.count == 2,
          "calib fix: the fixtured space added and selected");
    ks_coordinate_space_tree_get_transform(&tree, &root, &selected, &t,
                                           &status);
    check(status.failure == KS_FAILURE_NONE
          && memcmp(&t, &pose, sizeof t) == 0,
          "calib fix: root from fixtured is the pose");

    /* The N-point fixture under the new selection. */
    ks_fixture_n_point_to_n_point_run_params_default(&np, &status);
    check(np.dofs_to_compute == KS_DOF_ROTATION_AND_TRANSLATION
          && has_name(&np.fixtured_space_name, "N-Point Fixture"),
          "calib fix: N-point fixture defaults");
    for (i = 0; i < 3; i++) {
        map(&pose, b_x[i], b_y[i], &u, &v);
        ks_point_pairs_add_point_pair(&pairs, u, v, b_x[i], b_y[i], &status);
    }
    np.space_to_output = KS_SPACE_TO_OUTPUT_OLD;
    ks_fixture_n_point_to_n_point_execute(image, pairs, &np, &tree, &selected,
                                          &identity, &fit, &status);
    check(status.failure == KS_FAILURE_NONE
          && same_transform(&fit.transform, &pose, 1e-12)
          && has_name(&selected, "@\\Fixture") && tree.count == 3,
          "calib fix: N-point fixture added, selection kept");
    {
        ks_space_name name = space_name("@\\Fixture\\N-Point Fixture");
        ks_coordinate_space_tree_space_exists(&tree, &name, &exists, &status);
        check(exists == 1, "calib fix: the N-point fixtured space");
    }
    np.fixtured_space_name_duplicate_handling =
        KS_FIXTURED_SPACE_NAME_DUPLICATE_ENHANCED;
    ks_fixture_n_point_to_n_point_execute(image, pairs, &np, &tree, &selected,
                                          &identity, &fit, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER && tree.count == 3
          && fit.transform.a == 1.0,
          "calib fix: Enhanced refuses an existing space");
    np.fixtured_space_name_duplicate_handling =
        KS_FIXTURED_SPACE_NAME_DUPLICATE_COMPATIBILITY;
    np.fixtured_space_name = space_name("#");
    ks_fixture_n_point_to_n_point_execute(image, pairs, &np, &tree, &selected,
                                          &identity, &fit, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER,
          "calib fix: \"#\" is no space name");

    ks_point_pairs_destroy(&pairs);
    ks_image_8_grey_destroy(&image, &status);
}

/* An axis-aligned checkerboard with squares of `square` pixels whose
   corners lie between pixels, at (ox - 0.5 + i square, oy - 0.5 + j
   square). */
static ks_image_8_grey *checkerboard(int width, int height, int ox, int oy,
                                     int square)
{
    ks_status status;
    ks_image_8_grey *image = NULL;
    uint8_t row[512];
    int x, y;

    ks_image_8_grey_create(width, height, 0, &image, &status);
    for (y = 0; y < height; y++) {
        for (x = 0; x < width; x++) {
            int i = (int)floor((double)(x - ox) / square);
            int j = (int)floor((double)(y - oy) / square);
            row[x] = ((i + j) % 2 == 0) ? 220 : 30;
        }
        ks_image_8_grey_set_row(image, y, row, width, &status);
    }
    return image;
}

static void test_calibrations(void)
{
    ks_status status;
    ks_calibration *calibration = NULL, *copy = NULL;
    ks_n_point_to_n_point_fit fit;
    ks_calibration_run_params run;
    ks_coordinate_space_tree tree;
    ks_space_name selected = space_name("@");
    ks_image_8_grey *image = NULL;
    int32_t flag = -1, count = 0, i = 0, j = 0, width = 0, height = 0;
    double x, y, tx = 0.0, ty = 0.0;
    /* 20 pixels per mm along x, 25 along y. */
    const ks_transform_2d_linear truth = {20.0, 0.0, 0.0, 25.0, 100.0, 50.0};
    double u, v;
    int k;

    /* N-point. */
    ks_calibration_create(KS_CALIBRATION_N_POINT_TO_N_POINT, &calibration,
                          &status);
    check(status.failure == KS_FAILURE_NONE, "calib fix: N-point created");
    ks_calibration_computed_fit(calibration, &fit, &status);
    check(status.failure == KS_FAILURE_OPERATOR_NOT_TRAINED,
          "calib fix: not trained");
    for (k = 0; k < 4; k++) {
        map(&truth, b_x[k] / 10.0, b_y[k] / 10.0, &u, &v);
        ks_calibration_add_point_pair(calibration, u, v, b_x[k] / 10.0,
                                      b_y[k] / 10.0, &status);
    }
    ks_calibration_set_dofs_to_compute(
        calibration, KS_DOF_SCALING_ASPECT_ROTATION_AND_TRANSLATION, &status);
    ks_calibration_calibrate(calibration, NULL, &identity, &status);
    ks_calibration_calibrated(calibration, &flag, &status);
    check(flag == 1, "calib fix: N-point calibrated");
    ks_calibration_computed_fit(calibration, &fit, &status);
    check(status.failure == KS_FAILURE_NONE
          && same_transform(&fit.transform, &truth, 1e-12)
          && near(fit.scaling_x, 20.0, 1e-12)
          && near(fit.scaling_y, 25.0, 1e-12),
          "calib fix: pixel sizes recovered");
    ks_calibration_duplicate(calibration, &copy, &status);
    ks_calibration_set_point(calibration, 0, KS_POINT_GROUP_A, 0.0, 0.0,
                             &status);
    ks_calibration_calibrated(calibration, &flag, &status);
    check(flag == 0, "calib fix: a moved point uncalibrates");
    ks_calibration_calibrated(copy, &flag, &status);
    check(flag == 1, "calib fix: the duplicate stays calibrated");

    ks_coordinate_space_tree_init(&tree, &status);
    ks_image_8_grey_create(8, 8, 0, &image, &status);
    ks_calibration_run_params_default(KS_CALIBRATION_N_POINT_TO_N_POINT, &run,
                                      &status);
    ks_calibration_tool_execute(image, calibration, &run, &tree, &selected,
                                &identity, &status);
    check(is_failure(&status, KS_FAILURE_OPERATOR_NOT_TRAINED,
                     "Calibration is not calibrated"),
          "calib fix: the tool needs a calibrated calibration");
    ks_calibration_tool_execute(image, copy, &run, &tree, &selected,
                                &identity, &status);
    check(status.failure == KS_FAILURE_NONE
          && has_name(&selected, "@\\N-Point Calibration"),
          "calib fix: the calibrated space selected");
    ks_image_8_grey_destroy(&image, &status);
    ks_calibration_destroy(&copy);
    ks_calibration_destroy(&calibration);

    /* Checkerboard: squares of 24 pixels, a tile of 3 mm. */
    image = checkerboard(320, 240, 153, 110, 24);
    ks_calibration_create(KS_CALIBRATION_CHECKERBOARD, &calibration, &status);
    ks_calibration_add_point_pair(calibration, 0.0, 0.0, 0.0, 0.0, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER,
          "calib fix: no point pairs for a checkerboard");
    ks_calibration_set_physical_tile_size(calibration, 3.0, 3.0, &status);
    ks_calibration_physical_tile_size(calibration, &tx, &ty, &status);
    check(tx == 3.0 && ty == 3.0, "calib fix: tile sizes");
    ks_calibration_calibrate(calibration, NULL, &identity, &status);
    check(status.failure == KS_FAILURE_IMAGE_NO_PIXELS,
          "calib fix: no calibration image");
    ks_calibration_calibrate(calibration, image, &identity, &status);
    check(status.failure == KS_FAILURE_NONE, "calib fix: checkerboard");
    ks_calibration_num_points(calibration, &count, &status);
    check(count >= 9, "calib fix: corners found");
    ks_calibration_computed_fit(calibration, &fit, &status);
    /* 24 pixels per 3 mm; the corner nearest the image centre (159.5,
       119.5) is (152.5, 109.5), 12.2 pixels away ((152.5, 133.5) is 15.7
       away, (176.5, 109.5) 19.7). */
    check(status.failure == KS_FAILURE_NONE && near(fit.transform.a, 8.0, 0.01)
          && near(fit.transform.d, 8.0, 0.01) && near(fit.transform.b, 0.0, 0.01)
          && near(fit.transform.c, 0.0, 0.01)
          && near(fit.transform.translation_x, 152.5, 0.05)
          && near(fit.transform.translation_y, 109.5, 0.05),
          "calib fix: 8 pixels per mm, origin at the central corner");
    {
        /* The corners come in rows of increasing j, each of increasing i;
           one of them is the origin. */
        int32_t k, last_i = 0, last_j = 0;
        int ordered = 1, origin = 0;
        for (k = 0; k < count; k++) {
            ks_calibration_get_corner(calibration, k, &x, &y, &i, &j, &status);
            if (status.failure != KS_FAILURE_NONE)
                ordered = 0;
            if (k > 0 && !(j > last_j || (j == last_j && i > last_i)))
                ordered = 0;
            if (i == 0 && j == 0 && near(x, 152.5, 0.05) && near(y, 109.5, 0.05))
                origin = 1;
            last_i = i;
            last_j = j;
        }
        check(ordered, "calib fix: the corners in rows of increasing j and i");
        check(origin, "calib fix: the corner (0, 0) is the origin");
    }
    ks_calibration_corner_image_size(calibration, &width, &height, &status);
    check(width == 320 && height == 240, "calib fix: the corners' image");
    ks_calibration_get_corner(calibration, count, &x, &y, &i, &j, &status);
    check(status.failure == KS_FAILURE_INDEX_OUT_OF_RANGE,
          "calib fix: a corner beyond the end");
    ks_calibration_uncalibrate(calibration, &status);
    ks_calibration_num_points(calibration, &count, &status);
    check(count == 0, "calib fix: uncalibrate forgets the corners");
    ks_calibration_destroy(&calibration);
    ks_image_8_grey_destroy(&image, &status);

    ks_calibration_destroy(&calibration);
    check(calibration == NULL, "calib fix: destroy NULL");
}

static int same_exactly(const ks_transform_2d_linear *a,
                        const ks_transform_2d_linear *b)
{
    return a->a == b->a && a->b == b->b && a->c == b->c && a->d == b->d
        && a->translation_x == b->translation_x
        && a->translation_y == b->translation_y;
}

static void test_origin_adjustment(void)
{
    ks_status status;
    ks_calibration *calibration = NULL, *copy = NULL;
    ks_calibration_adjustment adjustment, got;
    ks_n_point_to_n_point_fit fit;
    ks_transform_2d_linear t, stored;
    ks_calibration_run_params run;
    ks_coordinate_space_tree tree;
    ks_space_name selected = space_name("@");
    ks_image_8_grey *image = NULL;
    int32_t flag = -1;
    double u, v;
    int k;
    /* 20 pixels per mm along x, 25 along y. */
    const ks_transform_2d_linear truth = {20.0, 0.0, 0.0, 25.0, 100.0, 50.0};

    ks_calibration_adjustment_default(&adjustment, &status);
    check(status.failure == KS_FAILURE_NONE
          && adjustment.calibrated_origin_x == 0.0
          && adjustment.calibrated_origin_y == 0.0
          && adjustment.calibrated_x_axis_rotation == 0.0
          && adjustment.calibrated_origin_space
                 == KS_ADJUSTMENT_SPACE_RAW_CALIBRATED
          && adjustment.calibrated_x_axis_rotation_space
                 == KS_ADJUSTMENT_SPACE_RAW_CALIBRATED
          && adjustment.swap_calibrated_handedness == 0,
          "calib fix: the default adjustment");
    ks_calibration_get_adjustment(NULL, &got, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER
          && got.calibrated_origin_x == 0.0,
          "calib fix: the adjustment of NULL");
    ks_calibration_computed_uncalibrated_from_calibrated_transform(NULL, &t,
                                                                   &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER
          && same_exactly(&t, &identity),
          "calib fix: the adjusted transform of NULL");

    ks_calibration_create(KS_CALIBRATION_N_POINT_TO_N_POINT, &calibration,
                          &status);
    for (k = 0; k < 4; k++) {
        map(&truth, b_x[k] / 10.0, b_y[k] / 10.0, &u, &v);
        ks_calibration_add_point_pair(calibration, u, v, b_x[k] / 10.0,
                                      b_y[k] / 10.0, &status);
    }
    ks_calibration_set_dofs_to_compute(
        calibration, KS_DOF_SCALING_ASPECT_ROTATION_AND_TRANSLATION, &status);
    ks_calibration_computed_uncalibrated_from_calibrated_transform(
        calibration, &t, &status);
    check(status.failure == KS_FAILURE_OPERATOR_NOT_TRAINED
          && same_exactly(&t, &identity),
          "calib fix: the adjusted transform needs a calibration");
    ks_calibration_calibrate(calibration, NULL, &identity, &status);
    ks_calibration_computed_fit(calibration, &fit, &status);
    ks_calibration_computed_uncalibrated_from_calibrated_transform(
        calibration, &t, &status);
    check(status.failure == KS_FAILURE_NONE
          && same_exactly(&t, &fit.transform),
          "calib fix: the default adjustment gives the fit exactly");

    /* The calibrated origin at the pixel (140, 100), the raw calibrated
       point (2, 2); the calibrated x axis along +y in pixels, the raw
       calibrated y axis; swapped. Raw from calibrated is (x, y) ->
       (2 + y, 2 + x), so uncalibrated from calibrated is
       (x, y) -> (140 + 20 y, 100 + 25 x). */
    adjustment.calibrated_origin_space = KS_ADJUSTMENT_SPACE_UNCALIBRATED;
    adjustment.calibrated_origin_x = 140.0;
    adjustment.calibrated_origin_y = 100.0;
    adjustment.calibrated_x_axis_rotation_space =
        KS_ADJUSTMENT_SPACE_UNCALIBRATED;
    adjustment.calibrated_x_axis_rotation = 2.0 * atan(1.0);
    adjustment.swap_calibrated_handedness = 1;
    ks_calibration_set_adjustment(calibration, &adjustment, &status);
    ks_calibration_calibrated(calibration, &flag, &status);
    check(status.failure == KS_FAILURE_NONE && flag == 1,
          "calib fix: setting the adjustment keeps the calibration");
    ks_calibration_get_adjustment(calibration, &got, &status);
    check(status.failure == KS_FAILURE_NONE
          && got.calibrated_origin_x == 140.0
          && got.calibrated_origin_y == 100.0
          && got.calibrated_x_axis_rotation
                 == adjustment.calibrated_x_axis_rotation
          && got.calibrated_origin_space == KS_ADJUSTMENT_SPACE_UNCALIBRATED
          && got.calibrated_x_axis_rotation_space
                 == KS_ADJUSTMENT_SPACE_UNCALIBRATED
          && got.swap_calibrated_handedness == 1,
          "calib fix: the adjustment reads back");
    ks_calibration_computed_uncalibrated_from_calibrated_transform(
        calibration, &t, &status);
    check(status.failure == KS_FAILURE_NONE && near(t.a, 0.0, 1e-12)
          && near(t.b, 20.0, 1e-12) && near(t.c, 25.0, 1e-12)
          && near(t.d, 0.0, 1e-12) && near(t.translation_x, 140.0, 1e-9)
          && near(t.translation_y, 100.0, 1e-9),
          "calib fix: the origin at a pixel, the x axis along +y, swapped");
    ks_calibration_computed_fit(calibration, &fit, &status);
    check(status.failure == KS_FAILURE_NONE
          && same_transform(&fit.transform, &truth, 1e-12),
          "calib fix: the computed fit stays the raw calibrated one");

    /* The tool adds the calibrated space with that transform. */
    ks_coordinate_space_tree_init(&tree, &status);
    ks_image_8_grey_create(8, 8, 0, &image, &status);
    ks_calibration_run_params_default(KS_CALIBRATION_N_POINT_TO_N_POINT, &run,
                                      &status);
    ks_calibration_tool_execute(image, calibration, &run, &tree, &selected,
                                &identity, &status);
    check(status.failure == KS_FAILURE_NONE
          && has_name(&selected, "@\\N-Point Calibration"),
          "calib fix: the tool runs with the adjustment");
    ks_coordinate_space_tree_parent_from_child_transform(&tree, &selected,
                                                         &stored, &status);
    check(status.failure == KS_FAILURE_NONE && same_exactly(&stored, &t),
          "calib fix: the tool's space is the adjusted transform");
    ks_image_8_grey_destroy(&image, &status);

    /* Bad values change nothing. */
    got = adjustment;
    got.calibrated_origin_space = 2;
    ks_calibration_set_adjustment(calibration, &got, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "CalibratedOriginSpace must be 0 (RawCalibrated) or 1 "
                     "(Uncalibrated)"),
          "calib fix: origin space 2");
    got = adjustment;
    got.swap_calibrated_handedness = -1;
    ks_calibration_set_adjustment(calibration, &got, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "SwapCalibratedHandedness must be 0 or 1"),
          "calib fix: swap -1");
    got = adjustment;
    got.calibrated_origin_y = NAN;
    ks_calibration_set_adjustment(calibration, &got, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "CalibratedOriginY must be finite and within "
                     "+/-1.0E150"),
          "calib fix: a NaN origin");
    got = adjustment;
    got.calibrated_x_axis_rotation = INFINITY;
    ks_calibration_set_adjustment(calibration, &got, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "CalibratedXAxisRotation must be finite"),
          "calib fix: an infinite rotation");
    ks_calibration_get_adjustment(calibration, &got, &status);
    check(got.calibrated_origin_y == 100.0
          && got.calibrated_x_axis_rotation
                 == adjustment.calibrated_x_axis_rotation,
          "calib fix: refused adjustments change nothing");
    got = adjustment;
    got.calibrated_x_axis_rotation =
        -3.0 * adjustment.calibrated_x_axis_rotation;
    ks_calibration_set_adjustment(calibration, &got, &status);
    ks_calibration_get_adjustment(calibration, &got, &status);
    check(status.failure == KS_FAILURE_NONE
          && near(got.calibrated_x_axis_rotation,
                  adjustment.calibrated_x_axis_rotation, 1e-12),
          "calib fix: -270 degrees reads back as 90");

    /* A duplicate keeps the adjustment; uncalibrated, it has no transform. */
    ks_calibration_duplicate(calibration, &copy, &status);
    ks_calibration_get_adjustment(copy, &got, &status);
    check(status.failure == KS_FAILURE_NONE
          && got.calibrated_origin_x == 140.0
          && got.swap_calibrated_handedness == 1,
          "calib fix: a duplicate keeps the adjustment");
    ks_calibration_uncalibrate(copy, &status);
    ks_calibration_computed_uncalibrated_from_calibrated_transform(copy, &t,
                                                                   &status);
    check(status.failure == KS_FAILURE_OPERATOR_NOT_TRAINED,
          "calib fix: no adjusted transform when not calibrated");
    ks_calibration_destroy(&copy);
    ks_calibration_destroy(&calibration);
}

/* A board of 10 x 7 tiles of tile pixels, its tile (0, 0) at the ideal
   pixel (ox, oy), seen through the radial distortion (k1, k2) of AMV's
   normalisation (centre the image centre, radius over half the diagonal);
   4 x 4 samples per pixel, a grey background. */
static ks_image_8_grey *distorted_board(int width, int height, double tile,
                                        double ox, double oy, double k1,
                                        double k2)
{
    ks_status status;
    ks_image_8_grey *image = NULL;
    uint8_t row[512];
    const double cx = (width - 1) / 2.0, cy = (height - 1) / 2.0;
    const double s = sqrt((double)width * width + (double)height * height)
                     / 2.0;
    int x, y, sx, sy, n;

    ks_image_8_grey_create(width, height, 0, &image, &status);
    for (y = 0; y < height; y++) {
        for (x = 0; x < width; x++) {
            double sum = 0.0;
            for (sy = 0; sy < 4; sy++) {
                for (sx = 0; sx < 4; sx++) {
                    const double px = x - 0.375 + 0.25 * sx;
                    const double py = y - 0.375 + 0.25 * sy;
                    const double rd = sqrt((px - cx) * (px - cx)
                                           + (py - cy) * (py - cy)) / s;
                    double r = rd, hx = px, hy = py, u, v;
                    for (n = 0; n < 12; n++)
                        r -= (r * (1.0 + k1 * r * r + k2 * r * r * r * r) - rd)
                             / (1.0 + 3.0 * k1 * r * r
                                + 5.0 * k2 * r * r * r * r);
                    if (rd > 0.0) {
                        hx = cx + (px - cx) * r / rd;
                        hy = cy + (py - cy) * r / rd;
                    }
                    u = (hx - ox) / tile;
                    v = (hy - oy) / tile;
                    if (u >= 0.0 && u < 10.0 && v >= 0.0 && v < 7.0)
                        sum += (((int)floor(u) + (int)floor(v)) % 2 == 0)
                                   ? 30.0 : 220.0;
                    else if (u >= -0.4 && u < 10.4 && v >= -0.4 && v < 7.4)
                        sum += 220.0;
                    else
                        sum += 90.0;
                }
            }
            row[x] = (uint8_t)(sum / 16.0 + 0.5);
        }
        ks_image_8_grey_set_row(image, y, row, width, &status);
    }
    return image;
}

static void test_radial_warp(void)
{
    ks_status status;
    ks_calibration *calibration = NULL, *linear = NULL, *npoint = NULL;
    ks_radial_warp_model model;
    ks_n_point_to_n_point_fit fit, linear_fit;
    ks_calibration_checkerboard_run_params run;
    ks_calibration_run_params old_run;
    ks_coordinate_space_tree tree;
    ks_space_name selected = space_name("@");
    ks_image_8_grey *image, *small = NULL, *output = NULL;
    ks_calibration *again = NULL;
    int32_t mode = 0, inside = -1, width = 0, height = 0;
    double x = -1.0, y = -1.0;
    uint8_t pixel = 0;

    /* Barrel distortion, K1 -0.15 and K2 0.03; tiles of 26 pixels. */
    image = distorted_board(320, 240, 26.0, 30.0, 29.0, -0.15, 0.03);
    ks_calibration_create(KS_CALIBRATION_CHECKERBOARD, &calibration, &status);
    ks_calibration_computation_mode(calibration, &mode, &status);
    check(status.failure == KS_FAILURE_NONE
          && mode == KS_COMPUTATION_MODE_LINEAR,
          "calib fix: the default mode is linear");
    ks_calibration_computation_mode(NULL, &mode, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER
          && mode == KS_COMPUTATION_MODE_LINEAR,
          "calib fix: the mode of NULL");
    ks_calibration_set_computation_mode(calibration, 0, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "ComputationMode must be a "
                     "CogCalibFixComputationModeConstants value (1 .. 7)"),
          "calib fix: mode 0");
    ks_calibration_set_computation_mode(
        calibration, KS_COMPUTATION_MODE_THREE_PARAM_RADIAL_WARP, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "ComputationMode ThreeParamRadialWarp is not supported"),
          "calib fix: ThreeParamRadialWarp is not supported");
    ks_calibration_create(KS_CALIBRATION_N_POINT_TO_N_POINT, &npoint,
                          &status);
    ks_calibration_set_computation_mode(
        npoint, KS_COMPUTATION_MODE_PERSPECTIVE_AND_RADIAL_WARP, &status);
    check(status.failure == KS_FAILURE_NONE,
          "calib fix: the warp mode for an N-point calibration");
    ks_calibration_destroy(&npoint);

    ks_calibration_set_computation_mode(
        calibration, KS_COMPUTATION_MODE_PERSPECTIVE_AND_RADIAL_WARP, &status);
    ks_calibration_computed_warp_model(calibration, &model, &status);
    check(status.failure == KS_FAILURE_OPERATOR_NOT_TRAINED,
          "calib fix: no model before calibrate");
    ks_calibration_set_physical_tile_size(calibration, 2.0, 2.0, &status);
    ks_calibration_calibrate(calibration, image, &identity, &status);
    check(status.failure == KS_FAILURE_NONE, "calib fix: warp calibrated");
    ks_calibration_computed_warp_model(calibration, &model, &status);
    ks_calibration_computed_warp_model(calibration, &model, &status);
    check(status.failure == KS_FAILURE_NONE && fabs(model.k1 + 0.15) < 0.02
          && fabs(model.k2 - 0.03) < 0.04 && model.rms_error < 0.1
          && model.image_width == 320 && model.image_height == 240
          && model.center_x == 159.5 && model.center_y == 119.5
          && near(model.normalizer, 200.0, 1e-9),
          "calib fix: the model of a barrel lens");
    ks_calibration_computed_fit(calibration, &fit, &status);
    check(status.failure == KS_FAILURE_NONE
          && fit.rms_error == model.rms_error
          && same_transform(&fit.transform,
                            &model.output_pixel_from_calibrated, 1e-12),
          "calib fix: the fit is the output's transform");
    /* The linear model leaves the distortion. */
    ks_calibration_create(KS_CALIBRATION_CHECKERBOARD, &linear, &status);
    ks_calibration_calibrate(linear, image, &identity, &status);
    ks_calibration_computed_fit(linear, &linear_fit, &status);
    check(status.failure == KS_FAILURE_NONE
          && linear_fit.rms_error > 5.0 * model.rms_error,
          "calib fix: the linear fit leaves the distortion");

    ks_calibration_map_output_pixel(calibration, 160.0, 120.0, &x, &y,
                                    &inside, &status);
    check(status.failure == KS_FAILURE_NONE && inside == 1 && x > 100.0
          && x < 220.0 && y > 60.0 && y < 180.0,
          "calib fix: an output pixel shows an input pixel");
    {
        double u = 0.0, v = 0.0;
        int32_t back = 0;
        ks_calibration_map_input_pixel(calibration, x, y, &u, &v, &back,
                                       &status);
        check(status.failure == KS_FAILURE_NONE && back == 1
              && fabs(u - 160.0) < 1e-6 && fabs(v - 120.0) < 1e-6,
              "calib fix: map_input_pixel inverts map_output_pixel");
        ks_calibration_map_input_pixel(linear, 1.0, 1.0, &u, &v, &back,
                                       &status);
        check(status.failure == KS_FAILURE_BAD_PARAMETER && back == 0,
              "calib fix: no input map in the linear mode");
    }
    ks_calibration_map_output_pixel(calibration, NAN, 120.0, &x, &y,
                                    &inside, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER && inside == 0
          && x == 0.0 && y == 0.0,
          "calib fix: a NaN output pixel");
    ks_calibration_map_output_pixel(linear, 1.0, 1.0, &x, &y, &inside,
                                    &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER,
          "calib fix: no output pixels in the linear mode");

    /* The tools. */
    ks_calibration_checkerboard_run_params_default(&run, &status);
    check(status.failure == KS_FAILURE_NONE
          && has_name(&run.calibrated_space_name, "Checkerboard Calibration")
          && run.space_to_output == KS_SPACE_TO_OUTPUT_NEW
          && run.unfilled_pel_value == 0
          && run.unfilled_pel_value_enabled == 0,
          "calib fix: the checkerboard tool's defaults");
    ks_calibration_run_params_default(KS_CALIBRATION_CHECKERBOARD, &old_run,
                                      &status);
    ks_coordinate_space_tree_init(&tree, &status);
    ks_calibration_tool_execute(image, calibration, &old_run, &tree,
                                &selected, &identity, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER,
          "calib fix: the linear tool refuses a warp calibration");
    ks_calibration_checkerboard_tool_execute(NULL, calibration, &run, &tree,
                                             &selected, &identity, &output,
                                             &status);
    check(status.failure == KS_FAILURE_IMAGE_NO_PIXELS && output == NULL,
          "calib fix: the warp needs an input image");
    ks_image_8_grey_create(32, 24, 0, &small, &status);
    ks_calibration_checkerboard_tool_execute(small, calibration, &run, &tree,
                                             &selected, &identity, &output,
                                             &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER && output == NULL,
          "calib fix: the warp needs the calibration image's size");
    run.unfilled_pel_value_enabled = 2;
    ks_calibration_checkerboard_tool_execute(image, calibration, &run, &tree,
                                             &selected, &identity, &output,
                                             &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "RunParams.UnfilledPelValueEnabled must be 0 or 1")
          && output == NULL,
          "calib fix: UnfilledPelValueEnabled 2");
    run.unfilled_pel_value_enabled = 1;
    run.unfilled_pel_value = 200;
    ks_calibration_checkerboard_tool_execute(image, calibration, &run, &tree,
                                             &selected, &identity, &output,
                                             &status);
    check(status.failure == KS_FAILURE_NONE && output != NULL
          && has_name(&selected, "@\\Checkerboard Calibration"),
          "calib fix: the warp");
    ks_image_8_grey_width(output, &width, &status);
    ks_image_8_grey_height(output, &height, &status);
    check(width == 320 && height == 240,
          "calib fix: the warped image has the input's size");
    /* The warped image shows a board without distortion: its corners fit
       a linear grid. */
    ks_calibration_create(KS_CALIBRATION_CHECKERBOARD, &again, &status);
    ks_calibration_calibrate(again, output, &identity,
                             &status);
    ks_calibration_computed_fit(again, &fit, &status);
    check(status.failure == KS_FAILURE_NONE && fit.rms_error < 0.15,
          "calib fix: the warped board fits a linear grid");
    ks_calibration_destroy(&again);
    ks_image_8_grey_get_pixel(output, 160, 120, &pixel, &status);
    check(status.failure == KS_FAILURE_NONE, "calib fix: a warped pixel");
    ks_image_8_grey_destroy(&output, &status);

    /* The linear mode returns no image. */
    ks_calibration_checkerboard_tool_execute(image, linear, &run, &tree,
                                             &selected, &identity, &output,
                                             &status);
    check(status.failure == KS_FAILURE_NONE && output == NULL,
          "calib fix: the linear tool keeps the input's pixels");

    ks_image_8_grey_destroy(&small, &status);
    ks_image_8_grey_destroy(&image, &status);
    ks_calibration_destroy(&linear);
    ks_calibration_destroy(&calibration);
}

/* The ideal pixel (hx, hy) seen through the lens (k1, k2) about the centre
   of a width x height image (the model of the kernel's spec). */
static void distort(int width, int height, double k1, double k2, double hx,
                    double hy, double *px, double *py)
{
    const double cx = (width - 1) / 2.0, cy = (height - 1) / 2.0;
    const double s = sqrt((double)width * width + (double)height * height)
                     / 2.0;
    const double r2 = ((hx - cx) * (hx - cx) + (hy - cy) * (hy - cy))
                      / (s * s);
    const double f = 1.0 + k1 * r2 + k2 * r2 * r2;
    *px = cx + (hx - cx) * f;
    *py = cy + (hy - cy) * f;
}

/* The pixel where the model sees the plate point (x, y), by the formulas
   of ks_radial_warp_model. */
static void model_pixel(const ks_radial_warp_model *m, double x, double y,
                        double *px, double *py)
{
    const double gx = (x - m->grid_center_x) / m->grid_scale;
    const double gy = (y - m->grid_center_y) / m->grid_scale;
    const double w = 1.0 + m->h31 * gx + m->h32 * gy;
    const double a = (m->h11 * gx + m->h12 * gy + m->h13) / w;
    const double b = (m->h21 * gx + m->h22 * gy + m->h23) / w;
    const double rho = a * a + b * b;
    const double f = 1.0 + m->k1 * rho + m->k2 * rho * rho;
    *px = m->center_x + m->normalizer * f * a;
    *py = m->center_y + m->normalizer * f * b;
}

/* An N-point calibration in PERSPECTIVE_AND_RADIAL_WARP: pairs made from
   the barrel lens of test_radial_warp and the board's plate (tiles of
   26 pixels, 2 mm), at points that are not a grid. The model holds the
   truth, so it is recovered to the fit's convergence (far below the
   1e-6 pixel allowed here). */
static void plate_point(int i, double *x, double *y)
{
    *x = 2.0 * (0.6 + 2.2 * (i % 5) + 0.3 * sin(1.3 * i));
    *y = 2.0 * (0.6 + 1.9 * (i / 5) + 0.3 * cos(1.7 * i));
}

static void plate_pixel(double x, double y, double *px, double *py)
{
    distort(320, 240, -0.15, 0.03, 30.0 + 13.0 * x, 29.0 + 13.0 * y, px,
            py);
}

static void test_n_point_warp(void)
{
    ks_status status;
    ks_calibration *calibration = NULL, *linear = NULL;
    ks_radial_warp_model model;
    ks_n_point_to_n_point_fit fit;
    ks_calibration_run_params run;
    ks_coordinate_space_tree tree;
    ks_space_name selected = space_name("@");
    ks_image_8_grey *image, *output = NULL;
    ks_transform_2d_linear singular = identity;
    int32_t width = 0, height = 0, inside = 0, count = 0;
    double x, y, px, py, mx, my, u, v, worst_model = 0.0, worst_map = 0.0;
    int i;

    image = distorted_board(320, 240, 26.0, 30.0, 29.0, -0.15, 0.03);
    ks_calibration_create(KS_CALIBRATION_N_POINT_TO_N_POINT, &calibration,
                          &status);
    ks_calibration_set_computation_mode(
        calibration, KS_COMPUTATION_MODE_PERSPECTIVE_AND_RADIAL_WARP, &status);
    check(status.failure == KS_FAILURE_NONE,
          "calib fix: an N-point calibration takes the warp mode");
    for (i = 0; i < 20; i++) {
        plate_point(i, &x, &y);
        plate_pixel(x, y, &px, &py);
        ks_calibration_add_point_pair(calibration, px, py, x, y, &status);
        if (i == KS_CALIB_FIX_MIN_WARP_POINTS - 2) {
            ks_calibration_calibrate(calibration, image, &identity, &status);
            check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                             "Calibrate: PerspectiveAndRadialWarp needs at "
                             "least 8 point pairs"),
                  "calib fix: an N-point warp needs 8 pairs");
        }
    }
    ks_calibration_calibrate(calibration, NULL, &identity, &status);
    check(is_failure(&status, KS_FAILURE_IMAGE_NO_PIXELS,
                     "CalibrationImage has no pixels"),
          "calib fix: an N-point warp needs the calibration image");
    singular.a = 0.0;
    ks_calibration_calibrate(calibration, image, &singular, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER,
          "calib fix: an N-point warp needs an invertible selected space");
    ks_calibration_calibrate(calibration, image, &identity, &status);
    check(status.failure == KS_FAILURE_NONE,
          "calib fix: an N-point warp calibrated");
    ks_calibration_computed_warp_model(calibration, &model, &status);
    check(status.failure == KS_FAILURE_NONE && fabs(model.k1 + 0.15) < 1e-6
          && fabs(model.k2 - 0.03) < 1e-6 && model.rms_error < 1e-6
          && model.image_width == 320 && model.image_height == 240,
          "calib fix: the N-point warp recovers the lens");
    for (i = 0; i < 40; i++) {
        /* Other points of the plate (between the pairs). */
        x = 2.0 * (0.7 + 0.21 * i);
        y = 2.0 * (0.8 + 0.12 * i);
        plate_pixel(x, y, &px, &py);
        model_pixel(&model, x, y, &mx, &my);
        worst_model = fmax(worst_model, hypot(mx - px, my - py));
        map(&model.output_pixel_from_calibrated, x, y, &u, &v);
        ks_calibration_map_output_pixel(calibration, u, v, &mx, &my, &inside,
                                        &status);
        worst_map = fmax(worst_map, inside == 1 ? hypot(mx - px, my - py)
                                                : 1e9);
    }
    check(worst_model < 1e-6,
          "calib fix: the N-point model is the truth at other points");
    check(worst_map < 1e-6,
          "calib fix: the N-point warp's output pixel of a plate point "
          "shows its true pixel");
    ks_calibration_computed_fit(calibration, &fit, &status);
    check(status.failure == KS_FAILURE_NONE
          && fit.rms_error == model.rms_error
          && same_transform(&fit.transform,
                            &model.output_pixel_from_calibrated, 1e-12),
          "calib fix: the N-point fit is the output's transform");
    ks_calibration_num_points(calibration, &count, &status);
    ks_calibration_corner_image_size(calibration, &width, &height, &status);
    check(count == 20 && width == 0 && height == 0,
          "calib fix: the N-point warp keeps its pairs and has no corners");

    /* The tools. */
    ks_calibration_run_params_default(KS_CALIBRATION_N_POINT_TO_N_POINT, &run,
                                      &status);
    ks_coordinate_space_tree_init(&tree, &status);
    ks_calibration_tool_execute(image, calibration, &run, &tree, &selected,
                                &identity, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER,
          "calib fix: the linear tool refuses an N-point warp");
    ks_calibration_n_point_tool_execute(NULL, calibration, &run, &tree,
                                        &selected, &identity, &output,
                                        &status);
    check(status.failure == KS_FAILURE_IMAGE_NO_PIXELS && output == NULL,
          "calib fix: the N-point tool needs an input image");
    ks_calibration_n_point_tool_execute(image, calibration, &run, &tree,
                                        &selected, &identity, &output,
                                        &status);
    check(status.failure == KS_FAILURE_NONE && output != NULL
          && has_name(&selected, "@\\N-Point Calibration"),
          "calib fix: the N-point tool warps");
    ks_image_8_grey_width(output, &width, &status);
    ks_image_8_grey_height(output, &height, &status);
    check(width == 320 && height == 240,
          "calib fix: the N-point tool's image has the input's size");
    {
        /* The warped board's corners fit a linear grid. */
        ks_calibration *again = NULL;
        ks_calibration_create(KS_CALIBRATION_CHECKERBOARD, &again, &status);
        ks_calibration_calibrate(again, output, &identity, &status);
        ks_calibration_computed_fit(again, &fit, &status);
        check(status.failure == KS_FAILURE_NONE && fit.rms_error < 0.15,
              "calib fix: the N-point tool's board fits a linear grid");
        ks_calibration_destroy(&again);
    }
    ks_image_8_grey_destroy(&output, &status);
    ks_calibration_create(KS_CALIBRATION_N_POINT_TO_N_POINT, &linear,
                          &status);
    ks_calibration_set_dofs_to_compute(linear, KS_DOF_NONE, &status);
    ks_calibration_calibrate(linear, NULL, &identity, &status);
    ks_calibration_n_point_tool_execute(image, linear, &run, &tree,
                                        &selected, &identity, &output,
                                        &status);
    check(status.failure == KS_FAILURE_NONE && output == NULL,
          "calib fix: the linear N-point tool keeps the input's pixels");
    ks_calibration_destroy(&linear);

    /* An uncalibrated point off the image. */
    ks_calibration_set_point(calibration, 0, KS_POINT_GROUP_A, -1.0, 10.0,
                             &status);
    ks_calibration_calibrate(calibration, image, &identity, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Calibrate: an uncalibrated point lies outside "
                     "CalibrationImage (PerspectiveAndRadialWarp)"),
          "calib fix: an N-point warp point off the image");
    ks_image_8_grey_destroy(&image, &status);
    ks_calibration_destroy(&calibration);
}

void test_c_calib_fix(void)
{
    test_pairs_and_fits();
    test_fixtures();
    test_calibrations();
    test_origin_adjustment();
    test_radial_warp();
    test_n_point_warp();
}
