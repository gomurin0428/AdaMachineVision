/*
 * Tests of the dimensioning tools' C API (include/amv_dimensioning.h): a
 * few measuring tools on hand-computed cases, the mapping of a shape by
 * its transform, failures (NaN, a radius of 0, a circle under a
 * non-similarity), then the fits through the point list handle and the
 * result accessors, null handles included.
 */

#include <math.h>
#include <stdio.h>
#include <string.h>

#include "amv.h"
#include "c_test_support.h"

void test_c_dimensioning(void);

static const ks_transform_2d_linear identity = {1.0, 0.0, 0.0, 1.0, 0.0,
                                                0.0};

static void test_measuring(void)
{
    ks_status status;
    ks_distance_point_point_result pp;
    ks_distance_point_line_result pl;
    ks_distance_point_ellipse_result pe;
    ks_distance_circle_circle_result cc;
    ks_intersect_line_line_result ll;
    ks_intersect_circle_circle_result ic;
    ks_intersect_segment_segment_result ss;
    ks_intersect_line_ellipse_result le;
    const ks_line x_axis = {0.0, 0.0, 0.0};
    const ks_line vertical = {2.0, 0.0, 1.5707963267948966};
    const ks_circle circle_a = {0.0, 0.0, 5.0};
    const ks_circle circle_b = {8.0, 0.0, 5.0};
    const ks_ellipse ellipse = {0.0, 0.0, 5.0, 3.0, 0.0};
    const ks_line_segment seg_a = {0.0, 0.0, 2.0, 2.0};
    const ks_line_segment seg_b = {0.0, 2.0, 2.0, 0.0};
    /* A translation by (10, 0) and a stretch along x (not a similarity). */
    const ks_transform_2d_linear shift = {1.0, 0.0, 0.0, 1.0, 10.0, 0.0};
    const ks_transform_2d_linear stretch = {2.0, 0.0, 0.0, 1.0, 0.0, 0.0};
    double angle = -1.0;

    ks_distance_point_point_execute(1.0, 2.0, 4.0, 6.0, &pp, &status);
    check(status.failure == KS_FAILURE_NONE && pp.distance == 5.0
          && fabs(pp.angle - atan2(4.0, 3.0)) < 1e-15,
          "dimensioning: point to point");
    ks_distance_point_point_execute(NAN, 2.0, 4.0, 6.0, &pp, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "StartX must be finite and within +/-1.0E150")
          && pp.distance == 0.0,
          "dimensioning: a NaN coordinate");

    ks_distance_point_line_execute(5.0, 3.0, &x_axis, &identity, &pl,
                                   &status);
    check(status.failure == KS_FAILURE_NONE && pl.distance == 3.0
          && pl.line_x == 5.0 && pl.line_y == 0.0,
          "dimensioning: point to line");
    /* The line moved by (10, 0) into the measuring space. */
    ks_distance_point_line_execute(5.0, 3.0, &vertical, &shift, &pl,
                                   &status);
    check(status.failure == KS_FAILURE_NONE
          && fabs(pl.distance - 7.0) < 1e-12
          && fabs(pl.line_x - 12.0) < 1e-12,
          "dimensioning: a mapped line");

    ks_distance_point_ellipse_execute(0.0, 7.0, &ellipse, &identity, &pe,
                                      &status);
    check(status.failure == KS_FAILURE_NONE
          && fabs(pe.distance - 4.0) < 1e-12
          && fabs(pe.ellipse_y - 3.0) < 1e-12,
          "dimensioning: point to ellipse");
    {
        ks_ellipse flat = ellipse;
        flat.radius_y = 0.0;
        ks_distance_point_ellipse_execute(0.0, 7.0, &flat, &identity, &pe,
                                          &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "Ellipse.RadiusX and Ellipse.RadiusY must be > 0"),
              "dimensioning: an ellipse with a radius of 0");
    }

    ks_distance_circle_circle_execute(&circle_a, &circle_b, &identity,
                                      &identity, &cc, &status);
    check(status.failure == KS_FAILURE_NONE && cc.distance == 0.0
          && cc.circle_a_x == 0.0, "dimensioning: crossing circles");
    ks_distance_circle_circle_execute(&circle_a, &circle_b, &identity,
                                      &stretch, &cc, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER,
          "dimensioning: a circle under a non-similarity");

    ks_angle_line_line_execute(&x_axis, &vertical, &identity, &identity,
                               &angle, &status);
    check(status.failure == KS_FAILURE_NONE
          && fabs(angle - 1.5707963267948966) < 1e-15,
          "dimensioning: angle between lines");

    ks_intersect_line_line_execute(&x_axis, &vertical, &identity, &identity,
                                   &ll, &status);
    check(status.failure == KS_FAILURE_NONE && ll.intersects == 1
          && ll.num_points == 1 && fabs(ll.x - 2.0) < 1e-15,
          "dimensioning: crossing lines");
    ks_intersect_line_line_execute(&x_axis, &x_axis, &identity, &identity,
                                   &ll, &status);
    check(status.failure == KS_FAILURE_NONE && ll.intersects == 1
          && ll.num_points == -1 && ll.x == 0.0,
          "dimensioning: coincident lines");

    ks_intersect_circle_circle_execute(&circle_a, &circle_b, &identity,
                                       &identity, &ic, &status);
    check(status.failure == KS_FAILURE_NONE && ic.num_points == 2
          && fabs(ic.x0 - 4.0) < 1e-12 && fabs(ic.y0 - 3.0) < 1e-12
          && fabs(ic.y1 + 3.0) < 1e-12 && ic.x2 == 0.0 && ic.y3 == 0.0,
          "dimensioning: two circles meet twice");
    ks_intersect_circle_circle_execute(&circle_a, &circle_a, &identity,
                                       &identity, &ic, &status);
    check(status.failure == KS_FAILURE_NONE && ic.intersects == 1
          && ic.num_points == -1, "dimensioning: identical circles");

    ks_intersect_segment_segment_execute(&seg_a, &seg_b, &identity,
                                         &identity, &ss, &status);
    check(status.failure == KS_FAILURE_NONE && ss.num_points == 1
          && ss.x == 1.0 && ss.y == 1.0,
          "dimensioning: crossing segments");

    ks_intersect_line_ellipse_execute(&x_axis, &ellipse, &identity,
                                      &identity, &le, &status);
    check(status.failure == KS_FAILURE_NONE && le.num_points == 2
          && fabs(le.x0 + 5.0) < 1e-12 && fabs(le.x1 - 5.0) < 1e-12,
          "dimensioning: a line through an ellipse");
}

static void test_fitting(void)
{
    ks_status status;
    ks_fit_points *points = NULL, *copy = NULL;
    ks_fit_line_run_params line_params;
    ks_fit_circle_run_params circle_params;
    ks_fit_ellipse_run_params ellipse_params;
    ks_fit_result *result = NULL;
    ks_line line;
    ks_circle circle;
    ks_ellipse ellipse;
    int32_t count = -1, used = -1, kind = -1;
    double x = -1.0, y = -1.0, distance = -1.0, rms = -1.0;
    int i;

    ks_fit_line_run_params_default(&line_params, &status);
    ks_fit_circle_run_params_default(&circle_params, &status);
    ks_fit_ellipse_run_params_default(&ellipse_params, &status);
    check(line_params.num_to_ignore == 0
          && circle_params.radius_constraint_enabled == 0
          && circle_params.radius_constraint == 100.0
          && ellipse_params.rotation_constraint_enabled == 0,
          "fit: default run parameters");

    ks_fit_points_num_points(NULL, &count, &status);
    check(status.failure == KS_FAILURE_NONE && count == 0,
          "fit: a null point list is empty");
    for (i = 0; i < 10; i++) {
        ks_fit_points_add_point(&points, i, 0.5 * i + 3.0, &status);
    }
    ks_fit_points_add_point(&points, 5.0, 40.0, &status);
    ks_fit_points_num_points(points, &count, &status);
    check(status.failure == KS_FAILURE_NONE && count == 11,
          "fit: eleven points");
    ks_fit_points_get_point(points, 11, &x, &y, &status);
    check(status.failure == KS_FAILURE_INDEX_OUT_OF_RANGE,
          "fit: no point 11");

    line_params.num_to_ignore = 1;
    ks_fit_line_execute(points, &line_params, &result, &status);
    check(status.failure == KS_FAILURE_NONE && result != NULL,
          "fit: a line, one outlier");
    ks_fit_result_kind(result, &kind, &status);
    ks_fit_result_num_points_used(result, &count, &status);
    check(kind == KS_FIT_LINE && count == 10, "fit: ten points used");
    ks_fit_result_get_xy_used_distance(result, 10, &x, &y, &used,
                                       &distance, &status);
    check(status.failure == KS_FAILURE_NONE && x == 5.0 && y == 40.0
          && used == 0 && distance > 30.0, "fit: the outlier left out");
    ks_fit_result_get_line(result, &line, &status);
    check(status.failure == KS_FAILURE_NONE
          && fabs(line.y - 0.5 * line.x - 3.0) < 1e-12,
          "fit: the line");
    ks_fit_result_get_circle(result, &circle, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER,
          "fit: a line result has no circle");
    ks_fit_result_destroy(&result);
    check(result == NULL, "fit: destroy");

    ks_fit_points_set_num_points(&points, 0, &status);
    for (i = 0; i < 24; i++) {
        double t = 6.283185307179586 * i / 24.0;
        double u = 30.0 * cos(t), v = 12.0 * sin(t);
        ks_fit_points_add_point(&points, 40.0 + u * cos(0.6) - v * sin(0.6),
                                -20.0 + u * sin(0.6) + v * cos(0.6),
                                &status);
    }
    ks_fit_points_duplicate(points, &copy, &status);
    ks_fit_ellipse_execute(copy, &ellipse_params, &result, &status);
    check(status.failure == KS_FAILURE_NONE && result != NULL,
          "fit: an ellipse");
    ks_fit_result_get_ellipse(result, &ellipse, &status);
    ks_fit_result_rms_error(result, &rms, &status);
    check(fabs(ellipse.center_x - 40.0) < 1e-7
          && fabs(ellipse.radius_x - 30.0) < 1e-7
          && fabs(ellipse.radius_y - 12.0) < 1e-7
          && fabs(ellipse.rotation - 0.6) < 1e-9 && rms < 1e-7,
          "fit: the ellipse recovered");
    ks_fit_result_destroy(&result);

    circle_params.radius_constraint_enabled = 2;
    ks_fit_circle_execute(points, &circle_params, &result, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "RunParams.RadiusConstraintEnabled must be 0 or 1")
          && result == NULL, "fit: a bad flag");

    ks_fit_result_num_points(NULL, &count, &status);
    ks_fit_result_rms_error(NULL, &rms, &status);
    check(status.failure == KS_FAILURE_NONE && count == 0 && rms == 0.0,
          "fit: a null result");
    ks_fit_result_get_ellipse(NULL, &ellipse, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER,
          "fit: a null result has no ellipse");

    ks_fit_points_destroy(&copy);
    ks_fit_points_destroy(&points);
    check(points == NULL && copy == NULL, "fit: points destroyed");
}

void test_c_dimensioning(void)
{
    test_measuring();
    test_fitting();
}
