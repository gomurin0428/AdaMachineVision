/*
 * Tests of the shape creation tools' C API (include/amv_create_shapes.h):
 * each entry point on a hand-computed case, the mapping of the input by
 * its transform, and the failures (NaN, equal points, a radius of 0, a
 * circle under a non-similarity, a singular line transform) with the
 * default shape written on failure.
 */

#include <math.h>
#include <stdio.h>
#include <string.h>

#include "amv.h"
#include "c_test_support.h"

void test_c_create_shapes(void);

static const ks_transform_2d_linear identity = {1.0, 0.0, 0.0, 1.0, 0.0,
                                                0.0};

/* A translation by (10, 0), a stretch along x (not a similarity), and the
   all-zero (singular) matrix. */
static const ks_transform_2d_linear shift = {1.0, 0.0, 0.0, 1.0, 10.0, 0.0};
static const ks_transform_2d_linear stretch = {2.0, 0.0, 0.0, 1.0, 0.0,
                                               0.0};
static const ks_transform_2d_linear zero = {0.0, 0.0, 0.0, 0.0, 0.0, 0.0};

static const double pi = 3.14159265358979323846;

static void test_copies(void)
{
    ks_status status;
    const ks_circle circle = {1.0, 2.0, 3.0};
    const ks_ellipse ellipse = {1.0, 2.0, 5.0, 3.0, 0.25};
    const ks_line line = {1.0, 2.0, 0.5};
    const ks_line_segment segment = {1.0, 2.0, 4.0, 6.0};
    ks_circle c;
    ks_ellipse e;
    ks_line l;
    ks_line_segment s;

    ks_create_circle_execute(&circle, &shift, &c, &status);
    check(status.failure == KS_FAILURE_NONE && c.center_x == 11.0
          && c.center_y == 2.0 && c.radius == 3.0,
          "create shapes: a circle moved by (10, 0)");
    ks_create_circle_execute(&circle, &stretch, &c, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "InputCircle: its transform to the selected space is"
                     " not a similarity (the circle would become an"
                     " ellipse)")
          && c.center_x == 0.0 && c.radius == 50.0,
          "create shapes: a circle under a stretch, the default circle");

    ks_create_ellipse_execute(&ellipse, &stretch, &e, &status);
    check(status.failure == KS_FAILURE_NONE && fabs(e.center_x - 2.0) < 1e-12
          && e.radius_x > 0.0 && e.radius_y > 0.0
          && e.rotation > -pi && e.rotation <= pi,
          "create shapes: a stretched ellipse");
    {
        ks_ellipse flat = ellipse;
        flat.radius_x = 0.0;
        ks_create_ellipse_execute(&flat, &identity, &e, &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "Ellipse.RadiusX and Ellipse.RadiusY must be > 0"),
              "create shapes: an ellipse with a radius of 0");
    }

    ks_create_line_execute(&line, &shift, &l, &status);
    check(status.failure == KS_FAILURE_NONE && l.x == 11.0 && l.y == 2.0
          && fabs(l.rotation - 0.5) < 1e-15,
          "create shapes: a line moved by (10, 0)");
    ks_create_line_execute(&line, &zero, &l, &status);
    check(is_failure(&status, KS_FAILURE_TRANSFORM_SINGULAR,
                     "the transform of Line is singular"),
          "create shapes: a line under a singular transform");

    ks_create_segment_execute(&segment, &stretch, &s, &status);
    check(status.failure == KS_FAILURE_NONE && s.start_x == 2.0
          && s.start_y == 2.0 && s.end_x == 8.0 && s.end_y == 6.0,
          "create shapes: a stretched segment");
    {
        ks_line_segment bad = segment;
        bad.end_y = NAN;
        ks_create_segment_execute(&bad, &identity, &s, &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "Segment must be finite and within +/-1.0E150")
              && s.end_x == 100.0,
              "create shapes: a NaN segment, the default segment");
    }
}

static void test_constructions(void)
{
    ks_status status;
    const ks_line line = {-3.0, 1.0, 0.25};
    const ks_line_segment seg_a = {0.0, 0.0, 10.0, 0.0};
    const ks_line_segment seg_b = {2.0, 4.0, 12.0, 4.0};
    ks_line l;
    ks_line_segment s;

    ks_create_line_bisect_points_execute(0.0, 0.0, 4.0, 2.0, &l, &status);
    check(status.failure == KS_FAILURE_NONE && l.x == 2.0 && l.y == 1.0
          && fabs(l.rotation - (atan2(2.0, 4.0) + pi / 2.0)) < 1e-15,
          "create shapes: the bisector of (0, 0) and (4, 2)");
    ks_create_line_bisect_points_execute(1.0, 1.0, 1.0, 1.0, &l, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "StartX, StartY and EndX, EndY are the same point"
                     " (the bisector needs a direction)")
          && l.x == 0.0 && l.rotation == 0.0,
          "create shapes: the bisector of one point");
    ks_create_line_bisect_points_execute(NAN, 1.0, 1.0, 1.0, &l, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "StartX must be finite and within +/-1.0E150"),
          "create shapes: a NaN StartX");

    ks_create_line_parallel_execute(5.0, 7.0, &line, &identity, &l, &status);
    check(status.failure == KS_FAILURE_NONE && l.x == 5.0 && l.y == 7.0
          && fabs(l.rotation - 0.25) < 1e-15,
          "create shapes: a parallel line");
    ks_create_line_parallel_execute(INFINITY, 7.0, &line, &identity, &l,
                                    &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "X must be finite and within +/-1.0E150"),
          "create shapes: an infinite X");

    ks_create_line_perpendicular_execute(5.0, 7.0, &line, &identity, &l,
                                         &status);
    check(status.failure == KS_FAILURE_NONE && l.x == 5.0 && l.y == 7.0
          && fabs(l.rotation - (0.25 + pi / 2.0)) < 1e-15,
          "create shapes: a perpendicular line");
    {
        ks_line steep = line;
        steep.rotation = 2.0;
        ks_create_line_perpendicular_execute(5.0, 7.0, &steep, &identity, &l,
                                             &status);
        check(status.failure == KS_FAILURE_NONE
              && fabs(l.rotation - (2.0 - 1.5 * pi)) < 1e-14,
              "create shapes: a perpendicular brought into (-pi, pi]");
    }

    ks_create_segment_avg_segs_execute(&seg_a, &seg_b, &identity, &identity,
                                       &s, &status);
    check(status.failure == KS_FAILURE_NONE && s.start_x == 1.0
          && s.start_y == 2.0 && s.end_x == 11.0 && s.end_y == 2.0,
          "create shapes: the average of two segments");
    ks_create_segment_avg_segs_execute(&seg_a, &seg_b, &identity, &shift,
                                       &s, &status);
    check(status.failure == KS_FAILURE_NONE && s.start_x == 6.0
          && s.end_x == 16.0, "create shapes: SegmentB moved first");
    {
        ks_transform_2d_linear bad = identity;
        bad.translation_y = NAN;
        ks_create_segment_avg_segs_execute(&seg_a, &seg_b, &identity, &bad,
                                           &s, &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "the transform of SegmentB must be finite and"
                         " within +/-1.0E150"),
              "create shapes: a NaN transform of SegmentB");
    }
}

void test_c_create_shapes(void)
{
    test_copies();
    test_constructions();
}
