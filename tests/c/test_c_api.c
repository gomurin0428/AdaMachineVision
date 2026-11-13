/*
 * Calls the AMV C API (include/amv.h) from C: checks the ABI version, the
 * status layout and a few entry points, on success and on failure, then
 * runs the tests of each tool (test_c_<tool>.c). Exit status 0 when every
 * check passes.
 */

#include <math.h>
#include <stdio.h>
#include <string.h>

#include "amv.h"
#include "c_test_support.h"

extern void adainit(void);
extern void adafinal(void);

/* The tests of the tools (test_c_<tool>.c), called at the end of main. */
void test_c_image_processing(void);
void test_c_blob(void);
void test_c_caliper(void);
void test_c_ip_one_image(void);
void test_c_ip_geometry(void);
void test_c_dimensioning(void);
void test_c_create_shapes(void);
void test_c_calib_fix(void);
void test_c_cnl_search(void);
void test_c_pm_align(void);
void test_c_tool_group(void);

static ks_coordinate_space_tree tree;

/* ------------------------------------------------------------------ */
/* Real images (ks_real_image_*)                                       */
/* ------------------------------------------------------------------ */

static double real_pixel(const ks_real_image *image, int32_t x, int32_t y)
{
    ks_status status;
    double value = -1.0;

    ks_real_image_get_pixel(image, x, y, &value, &status);
    return status.failure == KS_FAILURE_NONE ? value : -999.0;
}

static void test_real_image(void)
{
    ks_status status;
    ks_real_image *image = NULL, *copy = NULL, *result = NULL;
    ks_real_image *gx = NULL, *gy = NULL;
    ks_image_8_grey *grey = NULL;
    int32_t width = -1, height = -1, inside = -1;
    double value = 0.0, mean, std_dev, minimum, maximum;
    const ks_transform_2d_linear identity = {1.0, 0.0, 0.0, 1.0, 0.0, 0.0};
    int x, y, all_one;

    /* Lifecycle and pixels. */
    ks_real_image_create(3, 2, 1.5, &image, &status);
    check(status.failure == KS_FAILURE_NONE && image != NULL,
          "real image: create");
    ks_real_image_width(image, &width, &status);
    ks_real_image_height(image, &height, &status);
    check(width == 3 && height == 2, "real image: size");
    ks_real_image_set_pixel(image, 2, 1, -7.25, &status);
    check(status.failure == KS_FAILURE_NONE
          && real_pixel(image, 2, 1) == -7.25
          && real_pixel(image, 0, 0) == 1.5,
          "real image: set and get");
    ks_real_image_get_pixel(image, 3, 0, &value, &status);
    check(is_failure(&status, KS_FAILURE_INDEX_OUT_OF_RANGE,
                     "Get: pixel (3, 0) is outside the 3 x 2 image")
          && value == 0.0,
          "real image: get outside");
    ks_real_image_set_pixel(image, 0, 0, NAN, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Set: Value must be finite and within +/-1.0E100")
          && real_pixel(image, 0, 0) == 1.5,
          "real image: NaN rejected, pixel unchanged");
    ks_real_image_set_pixel(image, 0, 0, 2.0e100, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER,
          "real image: value beyond the bound rejected");
    ks_real_image_create(65536, 65536, 0.0, &copy, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Create: Width * Height is too large") && copy == NULL,
          "real image: too large");
    ks_real_image_duplicate(image, &copy, &status);
    check(status.failure == KS_FAILURE_NONE && copy != NULL && copy != image
          && real_pixel(copy, 2, 1) == -7.25,
          "real image: duplicate");
    ks_real_image_fill(copy, 4.0, &status);
    check(real_pixel(copy, 1, 1) == 4.0 && real_pixel(image, 1, 1) == 1.5,
          "real image: fill changes the copy only");
    ks_real_image_destroy(&copy, &status);
    check(status.failure == KS_FAILURE_NONE && copy == NULL,
          "real image: destroy sets NULL");
    ks_real_image_width(NULL, &width, &status);
    check(status.failure == KS_FAILURE_NONE && width == 0,
          "real image: NULL is 0 x 0");

    /* Sampling. */
    ks_real_image_bilinear(image, 1.5, 1.0, &value, &status);
    check(status.failure == KS_FAILURE_NONE
          && fabs(value - 0.5 * (1.5 - 7.25)) <= 1e-15,
          "real image: bilinear between centres");
    ks_real_image_bilinear(image, NAN, 0.0, &value, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Bilinear: X must be finite"),
          "real image: bilinear rejects NaN");
    ks_real_image_bilinear(NULL, 0.0, 0.0, &value, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Bilinear: the image is empty"),
          "real image: bilinear of the empty image");
    ks_real_image_is_inside(image, 2.0, 1.0, &inside, &status);
    check(status.failure == KS_FAILURE_NONE && inside == 1,
          "real image: is_inside at the last centre");
    ks_real_image_is_inside(image, 2.0000001, 1.0, &inside, &status);
    check(inside == 0, "real image: is_inside beyond it");
    ks_real_image_resample(image, &identity, 3, 2, &result, &status);
    check(status.failure == KS_FAILURE_NONE
          && real_pixel(result, 2, 1) == -7.25,
          "real image: resample through the identity");
    ks_real_image_destroy(&result, &status);
    ks_real_image_destroy(&image, &status);

    /* A box filter on a 3 x 3 image with one 9 in the middle: with
       replicated borders every window holds it once. */
    ks_real_image_create(3, 3, 0.0, &image, &status);
    ks_real_image_set_pixel(image, 1, 1, 9.0, &status);
    ks_real_image_box_smooth(image, 1, &result, &status);
    all_one = status.failure == KS_FAILURE_NONE;
    for (y = 0; y < 3; y++)
        for (x = 0; x < 3; x++)
            all_one = all_one && fabs(real_pixel(result, x, y) - 1.0) <= 1e-15;
    check(all_one, "real image: box filter values");
    ks_real_image_destroy(&result, &status);
    ks_real_image_box_smooth(image, -1, &result, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Box_Smooth: Half_Size must be >= 0") && result == NULL,
          "real image: negative half size");
    ks_real_image_gaussian_smooth(image, NAN, &result, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Gaussian_Smooth: Sigma must be finite")
          && result == NULL,
          "real image: gaussian rejects NaN");
    ks_real_image_destroy(&image, &status);

    /* Gaussian of a constant image, Sobel of a ramp, downsampling. */
    ks_real_image_create(5, 4, 3.0, &image, &status);
    ks_real_image_gaussian_smooth(image, 1.2, &result, &status);
    check(status.failure == KS_FAILURE_NONE
          && fabs(real_pixel(result, 0, 0) - 3.0) <= 1e-14
          && fabs(real_pixel(result, 2, 2) - 3.0) <= 1e-14,
          "real image: gaussian keeps a constant");
    ks_real_image_destroy(&result, &status);
    for (y = 0; y < 4; y++)
        for (x = 0; x < 5; x++)
            ks_real_image_set_pixel(image, x, y, (double)(2 * x), &status);
    ks_real_image_sobel(image, &gx, &gy, &status);
    check(status.failure == KS_FAILURE_NONE
          && real_pixel(gx, 2, 1) == 2.0 && real_pixel(gx, 0, 1) == 1.0
          && real_pixel(gy, 2, 1) == 0.0,
          "real image: sobel of a ramp");
    ks_real_image_destroy(&gx, &status);
    ks_real_image_destroy(&gy, &status);
    ks_real_image_downsample_2(image, &result, &status);
    ks_real_image_width(result, &width, &status);
    ks_real_image_height(result, &height, &status);
    check(width == 2 && height == 2 && real_pixel(result, 1, 0) == 5.0,
          "real image: downsample size and mean");
    ks_real_image_destroy(&result, &status);

    /* Statistics. */
    ks_real_image_statistics(image, &mean, &std_dev, &minimum, &maximum,
                             &status);
    check(status.failure == KS_FAILURE_NONE && fabs(mean - 4.0) <= 1e-15
          && fabs(std_dev - sqrt(8.0)) <= 1e-14 && minimum == 0.0
          && maximum == 8.0,
          "real image: statistics");
    ks_real_image_destroy(&image, &status);
    ks_real_image_create(0, 3, 0.0, &image, &status);
    ks_real_image_height(image, &height, &status);
    check(image != NULL && height == 3, "real image: 0 x 3 keeps its size");
    ks_real_image_statistics(image, &mean, &std_dev, &minimum, &maximum,
                             &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Statistics: the image is empty"),
          "real image: statistics of an empty image");
    ks_real_image_gaussian_smooth(image, 2.0, &result, &status);
    ks_real_image_height(result, &height, &status);
    check(status.failure == KS_FAILURE_NONE && result != NULL && height == 3,
          "real image: a filter keeps an empty image's size");
    ks_real_image_destroy(&result, &status);
    ks_real_image_destroy(&image, &status);

    /* From and to 8-bit images. */
    ks_image_8_grey_create(4, 3, 7, &grey, &status);
    ks_image_8_grey_set_pixel(grey, 3, 2, 200, &status);
    ks_real_image_from_8_grey_window(grey, 2, 1, 2, 2, &image, &status);
    check(status.failure == KS_FAILURE_NONE && real_pixel(image, 1, 1) == 200.0
          && real_pixel(image, 0, 0) == 7.0,
          "real image: from an 8-bit window");
    ks_real_image_from_8_grey_window(grey, 3, 1, 2, 2, &result, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "From_Grey_8: the window must lie inside the image")
          && result == NULL,
          "real image: window outside the 8-bit image");
    ks_real_image_from_8_grey(NULL, &result, &status);
    check(is_failure(&status, KS_FAILURE_IMAGE_NO_PIXELS,
                     "From_Grey_8: the image has no pixels"),
          "real image: from an 8-bit image without pixels");
    ks_real_image_set_pixel(image, 0, 0, 254.5, &status);
    ks_image_8_grey_destroy(&grey, &status);
    ks_real_image_to_8_grey(image, &grey, &status);
    {
        uint8_t pixel = 0;

        ks_image_8_grey_get_pixel(grey, 0, 0, &pixel, &status);
        check(status.failure == KS_FAILURE_NONE && pixel == 255,
              "real image: to 8-bit rounds halves away from zero");
    }
    ks_real_image_bilinear_8_grey(grey, 0.5, 0.0, &value, &status);
    check(status.failure == KS_FAILURE_NONE && value == 0.5 * (255.0 + 7.0),
          "real image: bilinear of an 8-bit image");
    ks_image_8_grey_destroy(&grey, &status);
    ks_real_image_destroy(&image, &status);
}

/* ------------------------------------------------------------------ */
/* Geometry (ks_geometry_*)                                            */
/* ------------------------------------------------------------------ */

static void test_geometry(void)
{
    const double pi = 3.14159265358979323846;
    ks_status status;
    double result = -1.0, rms = -1.0;
    int32_t parallel = -1, count = -1;
    int32_t used[10];
    ks_point_2d p = {3.0, 4.0}, q = {0.0, 0.0}, r1, r2;
    ks_line_2d line = {0.0, 0.0, 0.0}, other = {3.0, -1.0, pi / 2.0};
    ks_line_2d fitted;
    ks_circle_2d circle = {0.0, 0.0, 5.0}, circle_2 = {8.0, 0.0, 5.0};
    ks_circle_2d fitted_circle;
    ks_point_2d points[10];
    int i, all_used;

    /* Distances and projections. */
    ks_geometry_distance(&p, &q, &result, &status);
    check(status.failure == KS_FAILURE_NONE && result == 5.0,
          "geometry: distance 3-4-5");
    ks_geometry_signed_distance(&p, &line, &result, &status);
    check(status.failure == KS_FAILURE_NONE && result == 4.0,
          "geometry: signed distance to the x axis");
    ks_geometry_project(&p, &line, &r1, &status);
    check(status.failure == KS_FAILURE_NONE && r1.x == 3.0 && r1.y == 0.0,
          "geometry: projection");
    ks_geometry_distance_to_circle(&p, &circle, &result, &status);
    check(status.failure == KS_FAILURE_NONE && result == 0.0,
          "geometry: a point on the circle");
    p.x = NAN;
    ks_geometry_distance(&p, &q, &result, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Distance: P.X must be finite and within +/-1.0E150")
          && result == 0.0,
          "geometry: NaN rejected");
    p.x = 2.0e150;
    ks_geometry_distance(&p, &q, &result, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER,
          "geometry: a coordinate beyond the bound rejected");
    p.x = -1.0e150;
    p.y = -1.0e150;
    q.x = 1.0e150;
    q.y = 1.0e150;
    ks_geometry_distance(&p, &q, &result, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Distance: the result would exceed +/-1.0E150"),
          "geometry: a distance beyond the bound");

    /* Intersections and angles. */
    ks_geometry_intersect_lines(&line, &other, &r1, &parallel, &status);
    check(status.failure == KS_FAILURE_NONE && parallel == 0
          && fabs(r1.x - 3.0) <= 1e-15 && fabs(r1.y) <= 1e-15,
          "geometry: line intersection");
    ks_geometry_intersect_lines(&line, &line, &r1, &parallel, &status);
    check(status.failure == KS_FAILURE_NONE && parallel == 1
          && r1.x == 0.0 && r1.y == 0.0,
          "geometry: parallel lines");
    ks_geometry_intersect_circles(&circle, &circle_2, &r1, &r2, &count,
                                  &status);
    check(status.failure == KS_FAILURE_NONE && count == 2
          && fabs(r1.x - 4.0) <= 1e-14 && fabs(r1.y - 3.0) <= 1e-14
          && fabs(r2.y + 3.0) <= 1e-14,
          "geometry: circle intersection");
    line.y = 3.0;
    ks_geometry_intersect_line_circle(&line, &circle, &r1, &r2, &count,
                                      &status);
    check(status.failure == KS_FAILURE_NONE && count == 2
          && fabs(r1.x + 4.0) <= 1e-14 && fabs(r2.x - 4.0) <= 1e-14,
          "geometry: line-circle intersection");
    circle.radius = -1.0;
    ks_geometry_intersect_line_circle(&line, &circle, &r1, &r2, &count,
                                      &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Intersect: Circle.Radius must be >= 0") && count == 0,
          "geometry: a negative radius");
    line.rotation = 3.0;
    other.rotation = -3.0;
    ks_geometry_angle_between(&line, &other, &result, &status);
    check(status.failure == KS_FAILURE_NONE
          && fabs(result - (2.0 * pi - 6.0)) <= 1e-14,
          "geometry: angle between wraps");

    /* Fits on known points. */
    for (i = 0; i < 5; i++) {
        points[i].x = (double)i;
        points[i].y = 2.0 * i + 1.0;
    }
    ks_geometry_fit_line(points, 5, &fitted, &rms, &status);
    check(status.failure == KS_FAILURE_NONE
          && fabs(fitted.rotation - atan(2.0)) <= 1e-15
          && fabs(fitted.x - 2.0) <= 1e-15 && fabs(fitted.y - 5.0) <= 1e-15
          && rms <= 1e-15,
          "geometry: fit_line on a line");
    ks_geometry_fit_line(points, 1, &fitted, &rms, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Fit_Line: at least 2 points are required, got 1"),
          "geometry: fit_line of one point");
    ks_geometry_fit_line(NULL, 3, &fitted, &rms, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Fit_Line: Points must not be null"),
          "geometry: fit_line of NULL");
    points[1] = points[0];
    points[2] = points[0];
    ks_geometry_fit_line(points, 3, &fitted, &rms, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Fit_Line: the points coincide"),
          "geometry: fit_line of coinciding points");
    points[2].y = NAN;
    ks_geometry_fit_line(points, 3, &fitted, &rms, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Fit_Line: Points (2) must be finite and within "
                     "+/-1.0E150"),
          "geometry: fit_line rejects NaN");

    /* A circle through 8 points of radius 10 around (3, -2), plus an
       outlier for the robust fit. */
    for (i = 0; i < 8; i++) {
        points[i].x = 3.0 + 10.0 * cos(0.7 * i);
        points[i].y = -2.0 + 10.0 * sin(0.7 * i);
    }
    points[8].x = 3.0;
    points[8].y = 15.0;
    ks_geometry_fit_circle(points, 8, &fitted_circle, &rms, &status);
    check(status.failure == KS_FAILURE_NONE
          && fabs(fitted_circle.center_x - 3.0) <= 1e-12
          && fabs(fitted_circle.center_y + 2.0) <= 1e-12
          && fabs(fitted_circle.radius - 10.0) <= 1e-12 && rms <= 1e-12,
          "geometry: fit_circle on a circle");
    ks_geometry_fit_circle_robust(points, 9, 1, &fitted_circle, &rms, used,
                                  &status);
    all_used = 1;
    for (i = 0; i < 8; i++)
        all_used = all_used && used[i] == 1;
    check(status.failure == KS_FAILURE_NONE && all_used && used[8] == 0
          && fabs(fitted_circle.radius - 10.0) <= 1e-12,
          "geometry: robust fit_circle drops the outlier");
    ks_geometry_fit_line_robust(points, 9, 8, &fitted, &rms, used, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Fit_Line: Num_To_Ignore must leave at least 2 of the "
                     "9 points"),
          "geometry: robust fit_line ignoring too many");
    for (i = 0; i < 3; i++) {
        points[i].x = (double)i;
        points[i].y = 0.0;
    }
    ks_geometry_fit_circle(points, 3, &fitted_circle, &rms, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Fit_Circle: the points are collinear"),
          "geometry: fit_circle of collinear points");
}

int main(void)
{
    const double pi = 3.14159265358979323846;
    double result = 123.0;
    ks_status status;

    adainit();

    check(ks_abi_version() == KS_ABI_VERSION, "ks_abi_version");
    check(KS_FAILURE_OPERATOR_NOT_TRAINED == 3,
          "KS_FAILURE_OPERATOR_NOT_TRAINED is 3");

    memset(&status, 0x55, sizeof status);
    ks_misc_norm_angle(4.0, &result, &status);
    check(status.failure == KS_FAILURE_NONE && status.length == 0
          && status.message[0] == '\0',
          "norm_angle(4): success status overwrites a stale one");
    check(fabs(result - (4.0 - 2.0 * pi)) <= 1e-15, "norm_angle(4) value");

    ks_misc_norm_angle(-pi, &result, &status);
    check(status.failure == KS_FAILURE_NONE && result == pi,
          "norm_angle(-pi) is +pi");

    ks_misc_norm_angle_pi(2.0, &result, &status);
    check(status.failure == KS_FAILURE_NONE
          && fabs(result - (2.0 - pi)) <= 1e-15, "norm_angle_pi(2)");

    ks_misc_deg_to_rad(180.0, &result, &status);
    check(status.failure == KS_FAILURE_NONE && result == pi,
          "deg_to_rad(180)");

    ks_misc_rad_to_deg(pi, &result, &status);
    check(status.failure == KS_FAILURE_NONE && result == 180.0,
          "rad_to_deg(pi)");

    ks_misc_rad_to_deg(1e307, &result, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Radians is too large to be converted to degrees"),
          "rad_to_deg(1e307) fails with a message");

    ks_misc_angle_difference(0.25, -0.5, &result, &status);
    check(status.failure == KS_FAILURE_NONE && result == 0.75,
          "angle_difference(0.25, -0.5)");

    ks_misc_hypot(3e300, 4e300, &result, &status);
    check(status.failure == KS_FAILURE_NONE
          && fabs(result / 5e300 - 1.0) <= 1e-15, "hypot(3e300, 4e300)");

    /* Around 2**(-500) neither component may be dropped (exact in binary). */
    ks_misc_hypot(ldexp(6.0, -503), ldexp(8.0, -503), &result, &status);
    check(status.failure == KS_FAILURE_NONE && result == ldexp(10.0, -503),
          "hypot(0.75 * 2**(-500), 2**(-500))");

    ks_misc_hypot(1.7e308, 1.7e308, &result, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER,
          "hypot beyond DBL_MAX fails");

    ks_misc_norm_angle(NAN, &result, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Radians must be finite") && result == 0.0,
          "norm_angle(NaN) fails, result 0");

    ks_misc_hypot(1.0, INFINITY, &result, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER, "Y must be finite"),
          "hypot(1, inf) names Y");

    ks_misc_angle_difference(-INFINITY, 1.0, &result, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER, "A must be finite"),
          "angle_difference(-inf, 1) names A");

    /* Transforms */
    {
        const ks_transform_2d_linear t = {2.0, 0.0, 0.0, 4.0, 1.0, 1.0};
        const ks_transform_2d_linear shift = {1.0, 0.0, 0.0, 1.0, 3.0, 0.0};
        ks_transform_2d_linear r;
        ks_transform_2d_linear_decomposition dec;
        double mx, my;
        int32_t flag = 7;

        ks_transform_2d_linear_invert(&t, &r, &status);
        check(status.failure == KS_FAILURE_NONE && r.a == 0.5 && r.d == 0.25
              && r.b == 0.0 && r.c == 0.0 && r.translation_x == -0.5
              && r.translation_y == -0.25, "transform invert");

        ks_transform_2d_linear_compose(&t, &shift, &r, &status);
        check(status.failure == KS_FAILURE_NONE && r.a == 2.0
              && r.translation_x == 7.0 && r.translation_y == 1.0,
              "transform compose (shift first)");

        ks_transform_2d_linear_map_point(&t, 1.0, -1.0, &mx, &my, &status);
        check(status.failure == KS_FAILURE_NONE && mx == 3.0 && my == -3.0,
              "transform map_point");

        ks_transform_2d_linear_decompose(&t, &dec, &status);
        check(status.failure == KS_FAILURE_NONE && dec.scaling_x == 2.0
              && dec.scaling_y == 4.0 && dec.rotation_x == 0.0
              && dec.skew == 0.0, "transform decompose");

        ks_transform_2d_linear_set_property(
            &t, KS_TRANSFORM_PROPERTY_SCALING_X, 3.0, &r, &status);
        check(status.failure == KS_FAILURE_NONE && r.a == 3.0 && r.d == 4.0,
              "transform set_property scaling_x");

        ks_transform_2d_linear_set_property(&t, 99, 1.0, &r, &status);
        check(status.failure == KS_FAILURE_BAD_PARAMETER,
              "transform set_property rejects an unknown code");

        ks_transform_2d_linear_is_similarity(&t, 1e-9, &flag, &status);
        check(status.failure == KS_FAILURE_NONE && flag == 0,
              "diag (2, 4) is not a similarity");

        ks_transform_2d_linear_matrix_determinant(&t, &result, &status);
        check(status.failure == KS_FAILURE_NONE && result == 8.0,
              "transform matrix_determinant");

        ks_transform_2d_linear_map_area(&t, -0.5, &result, &status);
        check(status.failure == KS_FAILURE_NONE && result == -4.0,
              "transform map_area");
        {
            const ks_transform_2d_linear big = {1e150, 0.0, 0.0, 1e150,
                                                0.0, 0.0};
            ks_transform_2d_linear_map_area(&big, 2.0, &result, &status);
            check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                             "the mapped area would exceed the supported "
                             "range"),
                  "transform map_area beyond the bound");
        }

        ks_transform_2d_linear_get_matrix_element(&t, 1, 1, &result,
                                                  &status);
        check(status.failure == KS_FAILURE_NONE && result == 4.0,
              "transform get_matrix_element (1, 1) is d");
        ks_transform_2d_linear_get_matrix_element(&t, 2, 0, &result,
                                                  &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "Row must be 0 or 1") && result == 0.0,
              "transform get_matrix_element rejects row 2");
        ks_transform_2d_linear_set_matrix_element(&t, 0, 1, 3.0, &r,
                                                  &status);
        check(status.failure == KS_FAILURE_NONE && r.a == 2.0 && r.b == 3.0
              && r.c == 0.0 && r.d == 4.0 && r.translation_x == 1.0
              && r.translation_y == 1.0,
              "transform set_matrix_element (0, 1) replaces b");
        ks_transform_2d_linear_set_matrix_element(&t, 0, -1, 3.0, &r,
                                                  &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "Column must be 0 or 1"),
              "transform set_matrix_element rejects column -1");

        ks_transform_2d_linear_identity(&shift, 0.0, &flag, &status);
        check(status.failure == KS_FAILURE_NONE && flag == 0,
              "a shift is not an identity");
        ks_transform_2d_linear_matrix_identity(&shift, 0.0, &flag, &status);
        check(status.failure == KS_FAILURE_NONE && flag == 1,
              "a shift is a matrix identity");
        ks_transform_2d_linear_singular(&t, 7.5, &flag, &status);
        check(status.failure == KS_FAILURE_NONE && flag == 0,
              "det 8 is not singular within 7.5");
        ks_transform_2d_linear_singular(&t, -1.0, &flag, &status);
        check(status.failure == KS_FAILURE_BAD_PARAMETER,
              "singular rejects a negative tolerance");

        {
            const ks_transform_2d_linear singular = {1.0, 2.0, 2.0, 4.0,
                                                     0.0, 0.0};
            ks_transform_2d_linear_invert(&singular, &r, &status);
            check(status.failure == KS_FAILURE_TRANSFORM_SINGULAR,
                  "transform invert of a singular matrix");
            ks_transform_2d_linear_singular(&singular, 0.0, &flag, &status);
            check(status.failure == KS_FAILURE_NONE && flag == 1,
                  "transform singular of a rank one matrix");
        }
        {
            const ks_transform_2d_linear huge = {1e200, 0.0, 0.0, 1.0,
                                                 0.0, 0.0};
            ks_transform_2d_linear_map_point(&huge, 1.0, 1.0, &mx, &my,
                                             &status);
            check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                             "Transform must be finite and within "
                             "+/-1.0E150"),
                  "transform entries beyond the bound are rejected");
        }
        ks_transform_2d_linear_map_point(&t, NAN, 1.0, &mx, &my, &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "X must be finite and within +/-1.0E150"),
              "transform map_point(NaN) names X");
    }

    /* Coordinate space trees */
    {
        const ks_transform_2d_linear shift = {1.0, 0.0, 0.0, 1.0, 3.0, 0.0};
        const ks_transform_2d_linear twice = {2.0, 0.0, 0.0, 2.0, 0.0, 0.0};
        const ks_transform_2d_linear ten = {1.0, 0.0, 0.0, 1.0, 10.0, 0.0};
        const ks_transform_2d_linear zero = {0.0, 0.0, 0.0, 0.0, 1.0, 1.0};
        const ks_space_name root = space_name("@");
        const ks_space_name fix = space_name("@\\Fix");
        const ks_space_name part = space_name("@\\Fix\\Part");
        ks_space_name name;
        ks_space_name found;
        ks_transform_2d_linear r;
        double mx, my;
        int32_t value = 7;

        ks_coordinate_space_tree_init(&tree, &status);
        check(status.failure == KS_FAILURE_NONE && tree.count == 1
              && has_name(&tree.spaces[0].name, "@")
              && tree.spaces[0].parent == -1,
              "tree init: only the root");

        /* Fix maps into the root by +3 along x, Part into Fix by 2. */
        name = space_name("Fix");
        ks_coordinate_space_tree_add_space(&tree, &root, &name, &shift,
                                           KS_ADD_SPACE_DUPLICATE_IS_ERROR,
                                           &status);
        check(status.failure == KS_FAILURE_NONE, "tree add @\\Fix");
        name = space_name("Part");
        ks_coordinate_space_tree_add_space(&tree, &fix, &name, &twice,
                                           KS_ADD_SPACE_REPLACE_DUPLICATE,
                                           &status);
        check(status.failure == KS_FAILURE_NONE && tree.count == 3
              && tree.spaces[2].parent == 1
              && memcmp(&tree.spaces[2].parent_from_child, &twice,
                        sizeof twice) == 0,
              "tree add @\\Fix\\Part, stored as given");

        ks_coordinate_space_tree_get_transform(&tree, &root, &part, &r,
                                               &status);
        check(status.failure == KS_FAILURE_NONE && r.a == 2.0 && r.d == 2.0
              && r.b == 0.0 && r.translation_x == 3.0
              && r.translation_y == 0.0,
              "tree get_transform composes up the path");
        ks_coordinate_space_tree_get_transform(&tree, &part, &root, &r,
                                               &status);
        check(status.failure == KS_FAILURE_NONE && r.a == 0.5
              && r.translation_x == -1.5, "tree get_transform inverts");

        /* The direction: (0, 0) of a space added with the translation
           (10, 0) is (10, 0) in its parent. */
        name = space_name("New");
        ks_coordinate_space_tree_add_space(&tree, &root, &name, &ten,
                                           KS_ADD_SPACE_DUPLICATE_IS_ERROR,
                                           &status);
        name = space_name("@\\New");
        ks_coordinate_space_tree_get_transform(&tree, &root, &name, &r,
                                               &status);
        ks_transform_2d_linear_map_point(&r, 0.0, 0.0, &mx, &my, &status);
        check(status.failure == KS_FAILURE_NONE && mx == 10.0 && my == 0.0,
              "tree parent_from_new direction");
        ks_coordinate_space_tree_delete_subtree(&tree, &name, &status);
        check(status.failure == KS_FAILURE_NONE && tree.count == 3,
              "tree delete_subtree of a leaf");

        /* Duplicates. */
        name = space_name("Fix");
        ks_coordinate_space_tree_add_space(&tree, &root, &name, &twice,
                                           KS_ADD_SPACE_DUPLICATE_IS_ERROR,
                                           &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "Add_Space: the space \"@\\Fix\" already exists")
              && tree.spaces[1].parent_from_child.translation_x == 3.0,
              "tree add_space duplicate is an error");
        ks_coordinate_space_tree_add_space(&tree, &root, &name, &twice,
                                           KS_ADD_SPACE_IGNORE_DUPLICATE,
                                           &status);
        check(status.failure == KS_FAILURE_NONE
              && tree.spaces[1].parent_from_child.translation_x == 3.0,
              "tree add_space ignores a duplicate");
        ks_coordinate_space_tree_add_space(&tree, &root, &name, &twice,
                                           KS_ADD_SPACE_REPLACE_DUPLICATE,
                                           &status);
        check(status.failure == KS_FAILURE_NONE && tree.count == 3
              && tree.spaces[1].parent_from_child.a == 2.0,
              "tree add_space replaces a duplicate");
        ks_coordinate_space_tree_add_space(&tree, &root, &name, &shift, 3,
                                           &status);
        check(status.failure == KS_FAILURE_BAD_PARAMETER
              && tree.spaces[1].parent_from_child.a == 2.0,
              "tree add_space rejects duplicate_handling 3");
        ks_coordinate_space_tree_change_transform(&tree, &fix, &shift,
                                                  &status);
        check(status.failure == KS_FAILURE_NONE
              && memcmp(&tree.spaces[1].parent_from_child, &shift,
                        sizeof shift) == 0,
              "tree change_transform");
        ks_coordinate_space_tree_parent_from_child_transform(&tree, &part,
                                                             &r, &status);
        check(status.failure == KS_FAILURE_NONE
              && memcmp(&r, &twice, sizeof r) == 0,
              "tree parent_from_child_transform");

        /* Names. */
        ks_coordinate_space_tree_space_count(&tree, &value, &status);
        check(status.failure == KS_FAILURE_NONE && value == 3,
              "tree space_count");
        ks_coordinate_space_tree_space_name(&tree, 1, &name, &status);
        check(status.failure == KS_FAILURE_NONE && has_name(&name, "@\\Fix"),
              "tree space_name(1)");
        ks_coordinate_space_tree_root_name(&tree, &name, &status);
        check(status.failure == KS_FAILURE_NONE && has_name(&name, "@"),
              "tree root_name");
        ks_coordinate_space_tree_parent_name(&tree, &part,
                                             KS_SPACE_TREE_PATHNAME_FULL,
                                             &name, &status);
        check(status.failure == KS_FAILURE_NONE && has_name(&name, "@\\Fix"),
              "tree parent_name, full");
        ks_coordinate_space_tree_parent_name(&tree, &part,
                                             KS_SPACE_TREE_PATHNAME_NONE,
                                             &name, &status);
        check(status.failure == KS_FAILURE_NONE && has_name(&name, "Fix"),
              "tree parent_name, none");
        ks_coordinate_space_tree_parent_name(&tree, &part, 3, &name,
                                             &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "Parent_Name: Pathname_Format must be 0 (None), "
                         "1 (Full) or 2 (Partial)")
              && name.length == 0,
              "tree parent_name rejects the format 3");
        ks_coordinate_space_tree_child_names_count(&tree, &root, &value,
                                                   &status);
        check(status.failure == KS_FAILURE_NONE && value == 1,
              "tree child_names_count");
        ks_coordinate_space_tree_child_name(&tree, &root,
                                            KS_SPACE_TREE_PATHNAME_PARTIAL,
                                            0, &name, &status);
        check(status.failure == KS_FAILURE_NONE && has_name(&name, "Fix"),
              "tree child_name, partial");
        ks_coordinate_space_tree_child_name(&tree, &root,
                                            KS_SPACE_TREE_PATHNAME_FULL, 1,
                                            &name, &status);
        check(is_failure(&status, KS_FAILURE_INDEX_OUT_OF_RANGE,
                         "Child_Names: index 1 is not in 0 .. 0"),
              "tree child_name beyond the count");
        ks_coordinate_space_tree_all_child_names_count(&tree, &root, 1,
                                                       &value, &status);
        check(status.failure == KS_FAILURE_NONE && value == 2,
              "tree all_child_names_count");
        ks_coordinate_space_tree_all_child_names_count(&tree, &root, 0,
                                                       &value, &status);
        check(status.failure == KS_FAILURE_NONE && value == 3,
              "tree all_child_names_count with the space itself");
        ks_coordinate_space_tree_all_child_names_count(&tree, &root, 2,
                                                       &value, &status);
        check(status.failure == KS_FAILURE_BAD_PARAMETER && value == 0,
              "tree all_child_names_count rejects children_only 2");
        ks_coordinate_space_tree_all_child_name(
            &tree, &root, KS_SPACE_TREE_PATHNAME_PARTIAL, 1, 1, &name,
            &status);
        check(status.failure == KS_FAILURE_NONE
              && has_name(&name, "Fix\\Part"),
              "tree all_child_name, partial");
        ks_coordinate_space_tree_verify_name(&tree, &part,
                                             KS_SPACE_TREE_PATHNAME_NONE,
                                             &value, &name, &status);
        check(status.failure == KS_FAILURE_NONE && value == 1
              && has_name(&name, "Part"),
              "tree verify_name");
        ks_coordinate_space_tree_space_exists(&tree, &part, &value, &status);
        check(status.failure == KS_FAILURE_NONE && value == 1,
              "tree space_exists");

        name = space_name("@\\Nope");
        ks_coordinate_space_tree_get_transform(&tree, &name, &root, &r,
                                               &status);
        check(is_failure(&status, KS_FAILURE_IMAGE_BAD_SELECTED_SPACE_NAME,
                         "Get_Transform: no space named \"@\\Nope\"")
              && r.a == 1.0 && r.translation_x == 0.0,
              "tree get_transform of an unknown name");
        ks_coordinate_space_tree_space_exists(&tree, &name, &value, &status);
        check(status.failure == KS_FAILURE_NONE && value == 0,
              "tree space_exists of an unknown name");
        ks_coordinate_space_tree_verify_name(&tree, &name,
                                             KS_SPACE_TREE_PATHNAME_FULL,
                                             &value, &found, &status);
        check(status.failure == KS_FAILURE_NONE && value == 0
              && found.length == 0,
              "tree verify_name of an unknown name");
        ks_coordinate_space_tree_space_name(&tree, 3, &name, &status);
        check(is_failure(&status, KS_FAILURE_INDEX_OUT_OF_RANGE,
                         "Space_Name: index 3 is not in 0 .. 2"),
              "tree space_name beyond the count");
        ks_coordinate_space_tree_change_transform(&tree, &part, &zero,
                                                  &status);
        check(status.failure == KS_FAILURE_TRANSFORM_SINGULAR,
              "tree change_transform of a singular one");
        ks_coordinate_space_tree_change_transform(&tree, &root, &shift,
                                                  &status);
        check(status.failure == KS_FAILURE_BAD_PARAMETER,
              "tree change_transform of the root");

        ks_coordinate_space_tree_delete_subtree(&tree, &fix, &status);
        check(status.failure == KS_FAILURE_NONE && tree.count == 1,
              "tree delete_subtree takes the subtree");

        tree.count = 0;
        ks_coordinate_space_tree_space_count(&tree, &value, &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "Tree is not a valid coordinate space tree"),
              "tree with a count of 0 is rejected");
        ks_coordinate_space_tree_clear(&tree, &status);
        check(status.failure == KS_FAILURE_BAD_PARAMETER && tree.count == 0,
              "clear of an invalid tree fails and changes nothing");
    }

    /* 8-bit images */
    {
        ks_image_8_grey *image = NULL;
        ks_image_8_grey *copy = NULL;
        ks_image_8_grey *none = NULL;
        uint8_t row[4] = {10, 20, 30, 40};
        uint8_t back[4] = {0, 0, 0, 0};
        uint8_t long_row[5] = {0, 0, 0, 0, 0};
        uint8_t value = 99;
        int32_t w = -1, h = -1;
        int ok = 1;

        ks_image_8_grey_create(4, 3, 7, &image, &status);
        check(status.failure == KS_FAILURE_NONE && image != NULL,
              "image create 4 x 3");
        ks_image_8_grey_width(image, &w, &status);
        ks_image_8_grey_height(image, &h, &status);
        check(status.failure == KS_FAILURE_NONE && w == 4 && h == 3,
              "image width and height");
        ks_image_8_grey_get_pixel(image, 3, 2, &value, &status);
        check(status.failure == KS_FAILURE_NONE && value == 7,
              "image created with the value");

        ks_image_8_grey_set_pixel(image, 1, 2, 200, &status);
        ks_image_8_grey_get_pixel(image, 1, 2, &value, &status);
        check(status.failure == KS_FAILURE_NONE && value == 200,
              "image set_pixel / get_pixel");
        ks_image_8_grey_get_pixel(image, 0, 2, &value, &status);
        check(status.failure == KS_FAILURE_NONE && value == 7,
              "image set_pixel changes one pixel");

        ks_image_8_grey_get_pixel(image, 4, 0, &value, &status);
        check(is_failure(&status, KS_FAILURE_INDEX_OUT_OF_RANGE,
                         "Get_Pixel: pixel (4, 0) is outside the 4 x 3 "
                         "image") && value == 0,
              "image get_pixel at x = width");
        ks_image_8_grey_set_pixel(image, 0, -1, 1, &status);
        check(is_failure(&status, KS_FAILURE_INDEX_OUT_OF_RANGE,
                         "Set_Pixel: pixel (0, -1) is outside the 4 x 3 "
                         "image"),
              "image set_pixel at y = -1");

        /* Rows through C arrays. */
        ks_image_8_grey_set_row(image, 1, row, 4, &status);
        check(status.failure == KS_FAILURE_NONE, "image set_row");
        ks_image_8_grey_get_row(image, 1, back, 4, &status);
        check(status.failure == KS_FAILURE_NONE
              && memcmp(row, back, sizeof row) == 0,
              "image get_row gives the row set");
        ks_image_8_grey_get_pixel(image, 3, 1, &value, &status);
        check(value == 40, "image set_row writes pixel (3, 1)");
        ks_image_8_grey_get_row(image, 0, back, 4, &status);
        check(status.failure == KS_FAILURE_NONE && back[0] == 7
              && back[3] == 7, "image set_row leaves row 0");
        ks_image_8_grey_get_row(image, 1, long_row, 5, &status);
        check(is_failure(&status, KS_FAILURE_INDEX_OUT_OF_RANGE,
                         "Get_Row: the row array has 5 elements but the "
                         "image is 4 pixels wide")
              && long_row[0] == 0,
              "image get_row with a wrong length writes nothing");
        ks_image_8_grey_set_row(image, 3, row, 4, &status);
        check(is_failure(&status, KS_FAILURE_INDEX_OUT_OF_RANGE,
                         "Set_Row: row 3 is outside the 4 x 3 image"),
              "image set_row beyond the last row");
        ks_image_8_grey_get_row(image, 0, NULL, 4, &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "Get_Row: Row must not be null"),
              "image get_row into NULL");

        /* Duplicate is independent. */
        ks_image_8_grey_duplicate(image, &copy, &status);
        check(status.failure == KS_FAILURE_NONE && copy != NULL
              && copy != image, "image duplicate");
        ks_image_8_grey_fill(copy, 5, &status);
        ks_image_8_grey_get_pixel(image, 2, 1, &value, &status);
        check(value == 30, "image fill of the copy leaves the original");
        for (int32_t y = 0; y < 3; y++) {
            for (int32_t x = 0; x < 4; x++) {
                ks_image_8_grey_get_pixel(copy, x, y, &value, &status);
                ok = ok && status.failure == KS_FAILURE_NONE && value == 5;
            }
        }
        check(ok, "image fill sets every pixel");

        /* NULL is an image without pixels. */
        ks_image_8_grey_width(none, &w, &status);
        check(status.failure == KS_FAILURE_NONE && w == 0,
              "image width of NULL is 0");
        ks_image_8_grey_get_pixel(none, 0, 0, &value, &status);
        check(is_failure(&status, KS_FAILURE_IMAGE_NO_PIXELS,
                         "Get_Pixel: the image has no pixels"),
              "image get_pixel of NULL");
        ks_image_8_grey_fill(none, 1, &status);
        check(status.failure == KS_FAILURE_IMAGE_NO_PIXELS,
              "image fill of NULL");
        ks_image_8_grey_destroy(&copy, &status);
        ks_image_8_grey_duplicate(none, &copy, &status);
        check(status.failure == KS_FAILURE_NONE && copy == NULL,
              "image duplicate of NULL is NULL");

        /* Sizes. */
        ks_image_8_grey_create(0, 3, 1, &none, &status);
        check(status.failure == KS_FAILURE_BAD_PARAMETER && none == NULL,
              "image create with width 0");
        ks_image_8_grey_create(65536, 65536, 1, &none, &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "Create: the image size 65536 x 65536 is too large")
              && none == NULL,
              "image create beyond KS_IMAGE_MAX_PIXELS");

        ks_image_8_grey_destroy(&image, &status);
        check(status.failure == KS_FAILURE_NONE && image == NULL,
              "image destroy sets the handle to NULL");
        ks_image_8_grey_destroy(&image, &status);
        check(status.failure == KS_FAILURE_NONE,
              "image destroy of NULL does nothing");
    }

    /* 16-bit images */
    {
        ks_image_16_grey *image = NULL;
        uint16_t row[3] = {1, 65535, 256};
        uint16_t back[3] = {0, 0, 0};
        uint16_t value = 0;

        ks_image_16_grey_create(3, 2, 1000, &image, &status);
        check(status.failure == KS_FAILURE_NONE && image != NULL,
              "16-bit create");
        ks_image_16_grey_get_pixel(image, 2, 1, &value, &status);
        check(status.failure == KS_FAILURE_NONE && value == 1000,
              "16-bit created with the value");
        ks_image_16_grey_set_row(image, 0, row, 3, &status);
        ks_image_16_grey_get_row(image, 0, back, 3, &status);
        check(status.failure == KS_FAILURE_NONE
              && memcmp(row, back, sizeof row) == 0,
              "16-bit rows through C arrays");
        ks_image_16_grey_set_pixel(image, 2, 1, 65534, &status);
        ks_image_16_grey_get_pixel(image, 2, 1, &value, &status);
        check(value == 65534, "16-bit set_pixel");
        ks_image_16_grey_destroy(&image, &status);
        check(image == NULL, "16-bit destroy");
    }

    /* Colour images */
    {
        ks_image_8_grey *red = NULL, *green = NULL, *blue = NULL;
        ks_image_8_grey *red2 = NULL, *green2 = NULL, *blue2 = NULL;
        ks_image_8_grey *other = NULL;
        uint8_t r = 0, g = 0, b = 0;

        ks_image_24_planar_color_create(2, 2, 10, 20, 30, &red, &green,
                                        &blue, &status);
        check(status.failure == KS_FAILURE_NONE && red && green && blue,
              "colour create");
        ks_image_24_planar_color_set_pixel(red, green, blue, 1, 1, 1, 2, 3,
                                           &status);
        ks_image_24_planar_color_get_pixel(red, green, blue, 1, 1, &r, &g,
                                           &b, &status);
        check(status.failure == KS_FAILURE_NONE && r == 1 && g == 2
              && b == 3, "colour set_pixel / get_pixel");
        ks_image_24_planar_color_get_pixel(red, green, blue, 0, 0, &r, &g,
                                           &b, &status);
        check(r == 10 && g == 20 && b == 30, "colour other pixel kept");
        ks_image_24_planar_color_duplicate(red, green, blue, &red2, &green2,
                                           &blue2, &status);
        check(status.failure == KS_FAILURE_NONE && red2 && green2 && blue2,
              "colour duplicate");
        ks_image_8_grey_create(2, 2, 77, &other, &status);
        ks_image_24_planar_color_set_plane(green2, other, &status);
        ks_image_24_planar_color_get_pixel(red2, green2, blue2, 1, 1, &r, &g,
                                           &b, &status);
        check(status.failure == KS_FAILURE_NONE && r == 1 && g == 77
              && b == 3, "colour set_plane copies into the plane");
        ks_image_24_planar_color_get_pixel(red, green, blue, 1, 1, &r, &g,
                                           &b, &status);
        check(g == 2, "colour duplicate is independent");
        ks_image_24_planar_color_get_pixel(red, NULL, blue, 0, 0, &r, &g, &b,
                                           &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "Get_Pixel: Red, Green and Blue must be planes of "
                         "the same size"),
              "colour get_pixel with a missing plane");
        ks_image_24_planar_color_get_pixel(NULL, NULL, NULL, 0, 0, &r, &g,
                                           &b, &status);
        check(status.failure == KS_FAILURE_IMAGE_NO_PIXELS,
              "colour get_pixel without pixels");
        ks_image_24_planar_color_set_plane(NULL, other, &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "Set_Plane: Pixels is 2 x 2 but the colour image "
                         "is 0 x 0"),
              "colour set_plane into an image without pixels");
        ks_image_8_grey_destroy(&red, &status);
        ks_image_8_grey_destroy(&green, &status);
        ks_image_8_grey_destroy(&blue, &status);
        ks_image_8_grey_destroy(&red2, &status);
        ks_image_8_grey_destroy(&green2, &status);
        ks_image_8_grey_destroy(&blue2, &status);
        ks_image_8_grey_destroy(&other, &status);
        check(!red && !green && !blue && !red2 && !green2 && !blue2
              && !other, "colour planes destroyed");
    }

    /* Coordinate space state of an image */
    {
        const ks_transform_2d_linear shift = {1.0, 0.0, 0.0, 1.0, 3.0, 0.0};
        const ks_transform_2d_linear pixel_from_root = {2.0, 0.0, 0.0, 2.0,
                                                        0.0, 0.0};
        const ks_transform_2d_linear singular = {1.0, 2.0, 2.0, 4.0,
                                                 0.0, 0.0};
        ks_transform_2d_linear p = {1.0, 0.0, 0.0, 1.0, 0.0, 0.0};
        ks_transform_2d_linear r;
        ks_space_name selected = space_name("@");
        ks_space_name name = space_name("Fix");
        const ks_space_name root = space_name("@");
        const ks_space_name fix = space_name("@\\Fix");
        const ks_space_name pixel = space_name("#");
        const ks_space_name dot = space_name(".");
        static ks_coordinate_space_tree empty;

        ks_coordinate_space_tree_init(&tree, &status);
        ks_coordinate_space_tree_init(&empty, &status);
        ks_coordinate_space_tree_add_space(&tree, &root, &name, &shift,
                                           KS_ADD_SPACE_DUPLICATE_IS_ERROR,
                                           &status);
        ks_image_set_selected_space_name(&tree, &selected, &fix, &status);
        check(status.failure == KS_FAILURE_NONE
              && has_name(&selected, "@\\Fix"),
              "image selects @\\Fix");
        name = space_name("@\\Nope");
        ks_image_set_selected_space_name(&tree, &selected, &name, &status);
        check(status.failure == KS_FAILURE_IMAGE_BAD_SELECTED_SPACE_NAME
              && has_name(&selected, "@\\Fix"),
              "image selection of an unknown space fails");
        ks_image_resolve_space_name(&tree, &selected, &dot, &name, &status);
        check(status.failure == KS_FAILURE_NONE
              && has_name(&name, "@\\Fix"), "image resolves \".\"");

        ks_image_set_pixel_from_root_transform(&p, &singular, &status);
        check(status.failure == KS_FAILURE_TRANSFORM_SINGULAR && p.a == 1.0,
              "image rejects a singular pixel_from_root");
        ks_image_set_pixel_from_root_transform(&p, &pixel_from_root,
                                               &status);
        check(status.failure == KS_FAILURE_NONE && p.a == 2.0,
              "image stores pixel_from_root");
        /* (0, 0) of "." (@\Fix) is (3, 0) in the root, (6, 0) in pixels. */
        ks_image_get_transform(&tree, &selected, &p, &pixel, &dot, &r,
                               &status);
        check(status.failure == KS_FAILURE_NONE && r.a == 2.0
              && r.translation_x == 6.0 && r.translation_y == 0.0,
              "image get_transform from \".\" to \"#\"");
        ks_image_get_transform(&tree, &selected, &p, &dot, &fix, &r,
                               &status);
        check(status.failure == KS_FAILURE_NONE && r.a == 1.0 && r.b == 0.0
              && r.translation_x == 0.0, "image get_transform of one space "
              "is the identity");

        ks_image_selection_for_new_tree(&tree, &selected, &empty, &status);
        check(status.failure == KS_FAILURE_NONE && has_name(&selected, "@"),
              "image selection for a tree without the space is \"@\"");
        ks_coordinate_space_tree_delete_subtree(&tree, &fix, &status);
        selected = space_name("@\\Fix");
        ks_image_selected_space_name(&tree, &selected, &name, &status);
        check(status.failure == KS_FAILURE_NONE && has_name(&name, "@"),
              "image: a removed selected space reads as \"@\"");
    }


    /* Image files: codecs on bytes in memory */
    {
        /* Two PNM images: a P5 2 x 2 8-bit image and a P2 1 x 2 16-bit
           image with maxval 1000. */
        static const uint8_t pnm[] = {
            'P', '5', ' ', '2', ' ', '2', ' ', '2', '5', '5', '\n',
            10, 20, 30, 40, '\n',
            'P', '2', ' ', '1', ' ', '2', ' ', '1', '0', '0', '0', '\n',
            '1', '0', '0', '0', ' ', '5', '0', '0', '\n'};
        /* A 24-bit BMP of 2 x 1 pixels, bottom-up: blue, green, red. */
        static const uint8_t bmp[] = {
            'B', 'M', 62, 0, 0, 0, 0, 0, 0, 0, 54, 0, 0, 0,
            40, 0, 0, 0, 2, 0, 0, 0, 1, 0, 0, 0, 1, 0, 24, 0,
            0, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            3, 2, 1, 6, 5, 4, 0, 0};
        static const uint8_t truncated[] = {
            'P', '5', ' ', '2', ' ', '2', ' ', '2', '5', '5', '\n', 1, 2, 3};
        static const uint8_t expected_pgm[] = {
            'P', '5', '\n', '3', ' ', '2', '\n', '2', '5', '5', '\n',
            0, 1, 2, 3, 4, 5};
        ks_image_file_contents *contents = NULL;
        ks_image_8_grey *grey = NULL, *red = NULL, *green = NULL,
                        *blue = NULL;
        ks_image_16_grey *grey16 = NULL;
        int32_t count = -1, kind = -1, type = -1, maxval = -1, format = -1;
        int32_t encoding = -1, separator = -1, new_count = -1, index = -1;
        int32_t next = -1, x;
        int64_t size = -1;
        uint8_t value = 0, r = 0, g = 0, b = 0;
        uint16_t value16 = 0;
        uint8_t out[64];

        ks_image_file_decode(pnm, (int64_t)sizeof pnm, &contents, &status);
        check(status.failure == KS_FAILURE_NONE && contents != NULL,
              "image file: decode two PNM images");
        ks_image_file_contents_count(contents, &count, &status);
        ks_image_file_contents_kind(contents, &kind, &status);
        check(count == 2 && kind == KS_IMAGE_FILE_KIND_PNM,
              "image file: count and kind");
        ks_image_file_contents_image_info(contents, 1, &type, &maxval,
                                          &status);
        check(status.failure == KS_FAILURE_NONE
              && type == KS_IMAGE_FILE_IMAGE_16_GREY && maxval == 1000,
              "image file: type and maxval of image 1");
        ks_image_file_contents_get_8_grey(contents, 0, &grey, &status);
        ks_image_8_grey_get_pixel(grey, 1, 1, &value, &status);
        check(status.failure == KS_FAILURE_NONE && value == 40,
              "image file: pixel of the 8-bit image");
        ks_image_8_grey_destroy(&grey, &status);
        ks_image_file_contents_get_16_grey(contents, 1, &grey16, &status);
        ks_image_16_grey_get_pixel(grey16, 0, 1, &value16, &status);
        check(status.failure == KS_FAILURE_NONE && value16 == 500,
              "image file: pixel of the 16-bit image");
        ks_image_16_grey_destroy(&grey16, &status);
        ks_image_file_contents_get_8_grey_converted(contents, 1, &grey,
                                                    &status);
        ks_image_8_grey_get_pixel(grey, 0, 1, &value, &status);
        check(status.failure == KS_FAILURE_NONE && value == 128,
              "image file: 16-bit sample converted (500 of 1000 is 128)");
        ks_image_8_grey_destroy(&grey, &status);
        ks_image_file_contents_get_8_grey(contents, 1, &grey, &status);
        check(status.failure == KS_FAILURE_BAD_PARAMETER && grey == NULL,
              "image file: get_8_grey of a 16-bit image fails");
        ks_image_file_contents_get_8_grey(contents, 2, &grey, &status);
        check(is_failure(&status, KS_FAILURE_INDEX_OUT_OF_RANGE,
                         "Item: index 2 is not below Count (2)"),
              "image file: index beyond the count");
        ks_image_file_contents_check_read_index(contents, 5, &status);
        check(is_failure(&status, KS_FAILURE_IMAGE_FILE,
                         "the file holds 2 image(s); there is no image "
                         "with index 5"),
              "image file: check_read_index");
        ks_image_file_contents_destroy(&contents, &status);
        check(contents == NULL, "image file: destroy");

        ks_image_file_decode(bmp, (int64_t)sizeof bmp, &contents, &status);
        ks_image_file_contents_kind(contents, &kind, &status);
        check(kind == KS_IMAGE_FILE_KIND_BMP, "image file: decode a BMP");
        ks_image_file_contents_get_24_planar_color(contents, 0, &red, &green,
                                                   &blue, &status);
        ks_image_24_planar_color_get_pixel(red, green, blue, 1, 0, &r, &g,
                                           &b, &status);
        check(status.failure == KS_FAILURE_NONE && r == 4 && g == 5
              && b == 6, "image file: BMP pixel (1, 0)");
        ks_image_file_contents_destroy(&contents, &status);

        ks_image_file_decode(truncated, (int64_t)sizeof truncated, &contents,
                             &status);
        check(is_failure(&status, KS_FAILURE_IMAGE_FILE,
                         "image 0: truncated pixel data: 4 bytes needed "
                         "but only 3 present")
              && contents == NULL,
              "image file: a truncated raster is rejected");
        ks_image_file_decode(truncated, 3, &contents, &status);
        check(status.failure == KS_FAILURE_IMAGE_FILE && contents == NULL,
              "image file: a truncated header is rejected");
        ks_image_file_decode(pnm, 0, &contents, &status);
        check(is_failure(&status, KS_FAILURE_IMAGE_FILE, "the file is empty"),
              "image file: no bytes");
        ks_image_file_decode(NULL, 5, &contents, &status);
        check(status.failure == KS_FAILURE_BAD_PARAMETER && contents == NULL,
              "image file: NULL bytes");
        ks_image_file_decode(pnm, -1, &contents, &status);
        check(status.failure == KS_FAILURE_BAD_PARAMETER,
              "image file: negative length");

        /* NULL contents: no images. */
        ks_image_file_contents_count(NULL, &count, &status);
        check(status.failure == KS_FAILURE_NONE && count == 0,
              "image file: count of NULL is 0");
        ks_image_file_contents_get_8_grey(NULL, 0, &grey, &status);
        check(status.failure == KS_FAILURE_INDEX_OUT_OF_RANGE && grey == NULL,
              "image file: no image in NULL");
        ks_image_file_contents_destroy(&contents, &status);
        check(status.failure == KS_FAILURE_NONE,
              "image file: destroy NULL");

        /* Formats from names. */
        ks_image_file_format_from_name("dir/a.PGM", 9, &format, &status);
        check(status.failure == KS_FAILURE_NONE
              && format == KS_IMAGE_FILE_FORMAT_PGM,
              "image file: .PGM is PGM");
        ks_image_file_format_from_name("x.png", 5, &format, &status);
        check(is_failure(&status, KS_FAILURE_IMAGE_FILE,
                         "cannot choose an image format for writing from "
                         "the extension \"png\" (use .pgm, .ppm, .pnm or "
                         ".bmp)")
              && format == 0,
              "image file: .png has no format");
        ks_image_file_format_from_name("d.bmp/none", 10, &format, &status);
        check(status.failure == KS_FAILURE_IMAGE_FILE,
              "image file: a dot in a directory is not an extension");

        /* Encoding: byte for byte. */
        ks_image_file_choose_encoding(KS_IMAGE_FILE_FORMAT_PGM,
                                      KS_IMAGE_FILE_IMAGE_8_GREY, 3, 2,
                                      &encoding, &status);
        check(status.failure == KS_FAILURE_NONE
              && encoding == KS_IMAGE_FILE_ENCODING_P5_8,
              "image file: an 8-bit image in .pgm is P5_8");
        ks_image_file_choose_encoding(KS_IMAGE_FILE_FORMAT_PGM,
                                      KS_IMAGE_FILE_IMAGE_24_PLANAR_COLOR, 3,
                                      2, &encoding, &status);
        check(is_failure(&status, KS_FAILURE_IMAGE_FILE,
                         "a .pgm file cannot hold a colour image (use .ppm, "
                         ".pnm or .bmp)"),
              "image file: no colour image in .pgm");
        ks_image_file_choose_encoding(KS_IMAGE_FILE_FORMAT_BMP,
                                      KS_IMAGE_FILE_IMAGE_8_GREY, 0, 0,
                                      &encoding, &status);
        check(status.failure == KS_FAILURE_IMAGE_NO_PIXELS,
              "image file: no pixels to write");
        ks_image_8_grey_create(3, 2, 0, &grey, &status);
        for (x = 0; x < 6; x++)
            ks_image_8_grey_set_pixel(grey, x % 3, x / 3, (uint8_t)x,
                                      &status);
        ks_image_file_encoded_size(KS_IMAGE_FILE_ENCODING_P5_8, 3, 2, 0,
                                   &size, &status);
        check(status.failure == KS_FAILURE_NONE
              && size == (int64_t)sizeof expected_pgm,
              "image file: encoded size");
        memset(out, 0xEE, sizeof out);
        ks_image_file_encode_8_grey(KS_IMAGE_FILE_ENCODING_P5_8, 0, grey, out,
                                    size, &status);
        check(status.failure == KS_FAILURE_NONE
              && memcmp(out, expected_pgm, sizeof expected_pgm) == 0
              && out[sizeof expected_pgm] == 0xEE,
              "image file: P5 bytes");
        ks_image_file_encode_8_grey(KS_IMAGE_FILE_ENCODING_P5_8, 0, grey, out,
                                    size - 1, &status);
        check(status.failure == KS_FAILURE_BAD_PARAMETER,
              "image file: encode into too few bytes");
        ks_image_8_grey_destroy(&grey, &status);
        ks_image_file_encode_8_grey(KS_IMAGE_FILE_ENCODING_P5_8, 0, NULL, out,
                                    size, &status);
        check(status.failure == KS_FAILURE_IMAGE_NO_PIXELS,
              "image file: encode an image without pixels");

        /* Re-encoding the decoded BMP gives the same bytes. */
        ks_image_file_encoded_size(KS_IMAGE_FILE_ENCODING_BMP_24, 2, 1, 0,
                                   &size, &status);
        check(size == (int64_t)sizeof bmp, "image file: BMP size");
        ks_image_file_encode_24_planar_color(KS_IMAGE_FILE_ENCODING_BMP_24, 0,
                                             red, green, blue, out, size,
                                             &status);
        /* Only the pixel and data size fields differ from the input: the
           writer fills in the data size and 72 dots per inch. */
        check(status.failure == KS_FAILURE_NONE
              && memcmp(out, bmp, 34) == 0 && out[34] == 8
              && out[38] == 0x13 && out[39] == 0x0B
              && memcmp(out + 54, bmp + 54, 8) == 0,
              "image file: BMP bytes");
        ks_image_8_grey_destroy(&red, &status);
        ks_image_8_grey_destroy(&green, &status);
        ks_image_8_grey_destroy(&blue, &status);

        /* The rules of appending and of the file object. */
        ks_image_file_check_append(KS_IMAGE_FILE_ENCODING_P5_8, 1, 10, '9',
                                   &separator, &new_count, &status);
        check(status.failure == KS_FAILURE_NONE && separator == 1
              && new_count == 2,
              "image file: a line feed after a plain raster");
        ks_image_file_check_append(KS_IMAGE_FILE_ENCODING_P5_8, 1, 10, '\n',
                                   &separator, &new_count, &status);
        check(separator == 0, "image file: no line feed after whitespace");
        ks_image_file_check_append(KS_IMAGE_FILE_ENCODING_BMP_8, 0, 100, 0,
                                   &separator, &new_count, &status);
        check(is_failure(&status, KS_FAILURE_IMAGE_FILE,
                         "a BMP file holds only one image and this file is "
                         "not empty"),
              "image file: one image per BMP file");
        ks_image_file_check_open_mode(KS_IMAGE_FILE_MODE_CLOSED, &status);
        check(status.failure == KS_FAILURE_BAD_PARAMETER,
              "image file: Open rejects Closed");
        ks_image_file_require_mode(KS_IMAGE_FILE_MODE_WRITE,
                                   KS_IMAGE_FILE_OPERATION_ITEM, &status);
        check(is_failure(&status, KS_FAILURE_IMAGE_FILE,
                         "Item needs Read mode but the file is open in "
                         "WRITE mode"),
              "image file: Item needs Read mode");
        ks_image_file_require_open(KS_IMAGE_FILE_MODE_CLOSED,
                                   KS_IMAGE_FILE_OPERATION_RUN, &status);
        check(is_failure(&status, KS_FAILURE_IMAGE_FILE,
                         "Operator: the image file is not open"),
              "image file: a closed tool operator");
        ks_image_file_tool_next_index(7, 4, &index, &next, &status);
        check(status.failure == KS_FAILURE_NONE && index == 3 && next == 0,
              "image file: tool index 7 of 4");
        ks_image_file_count_for_update(KS_IMAGE_FILE_FORMAT_BMP, pnm,
                                       (int64_t)sizeof pnm, &count, &status);
        check(status.failure == KS_FAILURE_IMAGE_FILE && count == 0,
              "image file: PNM contents under .bmp");
        ks_image_file_count_for_update(KS_IMAGE_FILE_FORMAT_PNM, pnm,
                                       (int64_t)sizeof pnm, &count, &status);
        check(status.failure == KS_FAILURE_NONE && count == 2,
              "image file: count for update");
    }

    /* Shapes: every type is set and checked, a point tested, a box, an
       area and a map taken; the polygon handle goes through its life;
       NaN and out-of-bound arguments are rejected. */
    {
        const double nan_value = nan("");
        const ks_transform_2d_linear identity = {1, 0, 0, 1, 0, 0};
        const ks_transform_2d_linear shift = {1, 0, 0, 1, 10, 20};
        const ks_transform_2d_linear rotate = {0, -1, 1, 0, 0, 0};
        const ks_transform_2d_linear stretch = {2, 0, 0, 1, 0, 0};
        const ks_transform_2d_linear mirror = {1, 0, 0, -1, 0, 0};
        const ks_transform_2d_linear huge = {1e150, 0, 0, 1e150, 0, 0};
        ks_rectangle rect, rect_out;
        ks_rectangle_affine affine, affine_out;
        ks_rectangle_affine_corners corners;
        ks_circle circle, circle_out;
        ks_ellipse ellipse, ellipse_out;
        ks_circular_annulus_section section, section_out;
        ks_line line, line_out;
        ks_line_segment segment, segment_out;
        ks_point_marker marker, marker_out;
        ks_circular_arc arc, arc_out;
        ks_polygon *polygon = NULL, *copy = NULL, *mapped = NULL;
        ks_transform_2d_linear frame;
        int32_t inside = 7, kind = 7, count = 7;
        double min_x, min_y, max_x, max_y, value, x, y, a, b;

        /* Rectangle. */
        ks_rectangle_set_xy_width_height(1, 2, 3, 4, &rect, &status);
        check(status.failure == KS_FAILURE_NONE && rect.x == 1
              && rect.y == 2 && rect.width == 3 && rect.height == 4,
              "rectangle: set_xy_width_height");
        ks_rectangle_set_xy_width_height(1, 2, -3, 4, &rect_out, &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "Ks_Rectangle.Width must be >= 0"),
              "rectangle: a negative width is rejected");
        ks_rectangle_set_xy_width_height(nan_value, 2, 3, 4, &rect_out,
                                         &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "Ks_Rectangle.X must be finite and within "
                         "+/-1.0E150"),
              "rectangle: a NaN x is rejected");
        ks_rectangle_set_xy_width_height(1, 2, 5e150, 4, &rect_out, &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "Ks_Rectangle.Width must be finite and at most "
                         "4.0E150"),
              "rectangle: a width beyond 4e150 is rejected");
        ks_rectangle_set_center_width_height(10, 20, 8, 2, &rect, &status);
        check(status.failure == KS_FAILURE_NONE && rect.x == 6
              && rect.y == 19, "rectangle: set_center_width_height");
        ks_rectangle_get_center_width_height(&rect, &x, &y, &a, &b, &status);
        check(status.failure == KS_FAILURE_NONE && x == 10 && y == 20
              && a == 8 && b == 2, "rectangle: get_center_width_height");
        ks_rectangle_contains_point(&rect, 13.9, 20.5, &inside, &status);
        check(status.failure == KS_FAILURE_NONE && inside == 1,
              "rectangle: a point inside");
        ks_rectangle_contains_point(&rect, 14.1, 20.5, &inside, &status);
        check(status.failure == KS_FAILURE_NONE && inside == 0,
              "rectangle: a point outside");
        ks_rectangle_contains_point(&rect, 13.0, nan_value, &inside,
                                    &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "Y must be finite and within +/-1.0E150")
              && inside == 0, "rectangle: a NaN point is rejected");
        ks_rectangle_get_bounding_box(&rect, &min_x, &min_y, &max_x, &max_y,
                                      &status);
        check(status.failure == KS_FAILURE_NONE && min_x == 6 && min_y == 19
              && max_x == 14 && max_y == 21, "rectangle: bounding box");
        ks_rectangle_area(&rect, &value, &status);
        check(status.failure == KS_FAILURE_NONE && value == 16,
              "rectangle: area");
        ks_rectangle_perimeter(&rect, &value, &status);
        check(status.failure == KS_FAILURE_NONE && value == 20,
              "rectangle: perimeter");
        ks_rectangle_boundary_slack(&rect, &value, &status);
        check(status.failure == KS_FAILURE_NONE && value > 0 && value < 1e-7,
              "rectangle: boundary slack");
        ks_rectangle_map(&rect, &shift, &kind, &rect_out, &affine_out,
                         &status);
        check(status.failure == KS_FAILURE_NONE && kind == KS_SHAPE_RECTANGLE
              && rect_out.x == 16 && rect_out.y == 39
              && rect_out.width == 8, "rectangle: map by a shift");
        ks_rectangle_map(&rect, &rotate, &kind, &rect_out, &affine_out,
                         &status);
        check(status.failure == KS_FAILURE_NONE
              && kind == KS_SHAPE_RECTANGLE_AFFINE
              && fabs(affine_out.side_x_length - 8) <= 1e-12
              && fabs(affine_out.rotation - pi / 2) <= 1e-12,
              "rectangle: a rotation gives an affine rectangle");
        ks_rectangle_map(&rect, &huge, &kind, &rect_out, &affine_out,
                         &status);
        check(status.failure == KS_FAILURE_BAD_PARAMETER && kind == 0,
              "rectangle: a map beyond the bound is rejected");
        ks_rectangle_from_bounding_box(-1, -2, 3, 4, &rect_out, &status);
        check(status.failure == KS_FAILURE_NONE && rect_out.x == -1
              && rect_out.width == 4 && rect_out.height == 6,
              "rectangle: from bounding box");
        ks_rectangle_from_bounding_box(3, -2, -1, 4, &rect_out, &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "Max_X must be >= Min_X"),
              "rectangle: an inverted bounding box is rejected");

        /* Affine rectangle. */
        ks_rectangle_affine_set_origin_corner_x_corner_y(0, 0, 4, 0, 1, 3,
                                                         &affine, &status);
        check(status.failure == KS_FAILURE_NONE
              && affine.side_x_length == 4
              && fabs(affine.center_x - 2.5) <= 1e-12,
              "affine: set from three corners");
        ks_rectangle_affine_get_corners(&affine, &corners, &status);
        check(status.failure == KS_FAILURE_NONE
              && fabs(corners.corner_opposite_x - 5) <= 1e-12
              && fabs(corners.corner_opposite_y - 3) <= 1e-12,
              "affine: the opposite corner");
        ks_rectangle_affine_contains_point(&affine, 2.5, 1.5, &inside,
                                           &status);
        check(status.failure == KS_FAILURE_NONE && inside == 1,
              "affine: the centre is inside");
        ks_rectangle_affine_contains_point(&affine, 0.0, 3.0, &inside,
                                           &status);
        check(status.failure == KS_FAILURE_NONE && inside == 0,
              "affine: a point left of the slanted side is outside");
        ks_rectangle_affine_area(&affine, &value, &status);
        check(status.failure == KS_FAILURE_NONE && fabs(value - 12) <= 1e-12,
              "affine: area");
        ks_rectangle_affine_get_bounding_box(&affine, &min_x, &min_y, &max_x,
                                             &max_y, &status);
        check(status.failure == KS_FAILURE_NONE && fabs(min_x) <= 1e-12
              && fabs(max_x - 5) <= 1e-12 && fabs(max_y - 3) <= 1e-12,
              "affine: bounding box");
        ks_rectangle_affine_get_parent_from_child_transform(&affine, &frame,
                                                            &status);
        check(status.failure == KS_FAILURE_NONE && fabs(frame.a - 1) <= 1e-12
              && fabs(frame.translation_x) <= 1e-12,
              "affine: parent from child transform");
        ks_rectangle_affine_map(&affine, &stretch, &affine_out, &status);
        check(status.failure == KS_FAILURE_NONE
              && fabs(affine_out.side_x_length - 8) <= 1e-12,
              "affine: map");
        affine_out = affine;
        affine_out.skew = nan_value;
        ks_rectangle_affine_area(&affine_out, &value, &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "Ks_Rectangle_Affine.Skew must be finite and "
                         "within +/-1.0E150"),
              "affine: a NaN skew is rejected");

        /* Circle. */
        ks_circle_set_center_radius(1, 2, 3, &circle, &status);
        check(status.failure == KS_FAILURE_NONE && circle.radius == 3,
              "circle: set_center_radius");
        ks_circle_set_center_radius(1, 2, -3, &circle_out, &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "Ks_Circle.Radius must be >= 0"),
              "circle: a negative radius is rejected");
        ks_circle_contains_point(&circle, 4, 2, &inside, &status);
        check(status.failure == KS_FAILURE_NONE && inside == 1,
              "circle: a point on the boundary");
        ks_circle_contains_point(&circle, 4.01, 2, &inside, &status);
        check(status.failure == KS_FAILURE_NONE && inside == 0,
              "circle: a point outside");
        ks_circle_get_bounding_box(&circle, &min_x, &min_y, &max_x, &max_y,
                                   &status);
        check(status.failure == KS_FAILURE_NONE && min_x == -2 && max_y == 5,
              "circle: bounding box");
        ks_circle_area(&circle, &value, &status);
        check(status.failure == KS_FAILURE_NONE
              && fabs(value - 9 * pi) <= 1e-12, "circle: area");
        ks_circle_map(&circle, &mirror, &kind, &circle_out, &ellipse_out,
                      &status);
        check(status.failure == KS_FAILURE_NONE && kind == KS_SHAPE_CIRCLE
              && circle_out.center_y == -2 && circle_out.radius == 3,
              "circle: a mirror keeps a circle");
        ks_circle_map(&circle, &stretch, &kind, &circle_out, &ellipse_out,
                      &status);
        check(status.failure == KS_FAILURE_NONE && kind == KS_SHAPE_ELLIPSE
              && fabs(ellipse_out.radius_x - 6) <= 1e-12
              && fabs(ellipse_out.radius_y - 3) <= 1e-12,
              "circle: a stretch gives an ellipse");

        /* Ellipse. */
        ks_ellipse_set_center_xy_radius_xy_rotation(0, 0, 4, 2, pi / 2,
                                                    &ellipse, &status);
        check(status.failure == KS_FAILURE_NONE && ellipse.radius_x == 4,
              "ellipse: set");
        ks_ellipse_contains_point(&ellipse, 0, 3.9, &inside, &status);
        check(status.failure == KS_FAILURE_NONE && inside == 1,
              "ellipse: a point along the rotated major axis");
        ks_ellipse_contains_point(&ellipse, 3.9, 0, &inside, &status);
        check(status.failure == KS_FAILURE_NONE && inside == 0,
              "ellipse: a point beyond the minor axis");
        ks_ellipse_get_bounding_box(&ellipse, &min_x, &min_y, &max_x, &max_y,
                                    &status);
        check(status.failure == KS_FAILURE_NONE && fabs(max_x - 2) <= 1e-12
              && fabs(max_y - 4) <= 1e-12, "ellipse: bounding box");
        ks_ellipse_area(&ellipse, &value, &status);
        check(status.failure == KS_FAILURE_NONE
              && fabs(value - 8 * pi) <= 1e-12, "ellipse: area");
        ks_ellipse_map(&ellipse, &shift, &ellipse_out, &status);
        check(status.failure == KS_FAILURE_NONE && ellipse_out.center_x == 10
              && fabs(ellipse_out.radius_x - 4) <= 1e-12,
              "ellipse: map");

        /* Polygon: the handle's life. */
        ks_polygon_num_vertices(NULL, &count, &status);
        check(status.failure == KS_FAILURE_NONE && count == 0,
              "polygon: NULL has no vertices");
        ks_polygon_add_vertex(&polygon, 0, 0, KS_POLYGON_APPEND, &status);
        check(status.failure == KS_FAILURE_NONE && polygon != NULL,
              "polygon: add_vertex creates the handle");
        ks_polygon_add_vertex(&polygon, 10, 0, KS_POLYGON_APPEND, &status);
        ks_polygon_add_vertex(&polygon, 10, 10, KS_POLYGON_APPEND, &status);
        ks_polygon_add_vertex(&polygon, 0, 10, KS_POLYGON_APPEND, &status);
        ks_polygon_num_vertices(polygon, &count, &status);
        check(status.failure == KS_FAILURE_NONE && count == 4,
              "polygon: four vertices");
        ks_polygon_add_vertex(&polygon, 5, 5, 7, &status);
        check(status.failure == KS_FAILURE_INDEX_OUT_OF_RANGE,
              "polygon: add_vertex past the end");
        ks_polygon_add_vertex(&polygon, nan_value, 5, 0, &status);
        check(status.failure == KS_FAILURE_BAD_PARAMETER,
              "polygon: a NaN vertex is rejected");
        ks_polygon_get_vertex(polygon, 2, &x, &y, &status);
        check(status.failure == KS_FAILURE_NONE && x == 10 && y == 10,
              "polygon: get_vertex");
        ks_polygon_get_vertex(polygon, 4, &x, &y, &status);
        check(status.failure == KS_FAILURE_INDEX_OUT_OF_RANGE && x == 0,
              "polygon: get_vertex past the end");
        ks_polygon_contains_point(polygon, 5, 5, &inside, &status);
        check(status.failure == KS_FAILURE_NONE && inside == 1,
              "polygon: a point inside");
        ks_polygon_contains_point(polygon, 15, 5, &inside, &status);
        check(status.failure == KS_FAILURE_NONE && inside == 0,
              "polygon: a point outside");
        ks_polygon_area(polygon, &value, &status);
        check(status.failure == KS_FAILURE_NONE && value == 100,
              "polygon: area");
        ks_polygon_perimeter(polygon, &value, &status);
        check(status.failure == KS_FAILURE_NONE && value == 40,
              "polygon: perimeter");
        ks_polygon_get_bounding_box(polygon, &min_x, &min_y, &max_x, &max_y,
                                    &status);
        check(status.failure == KS_FAILURE_NONE && max_x == 10
              && max_y == 10, "polygon: bounding box");
        ks_polygon_duplicate(polygon, &copy, &status);
        check(status.failure == KS_FAILURE_NONE && copy != NULL
              && copy != polygon, "polygon: duplicate");
        ks_polygon_set_vertex(copy, 0, -5, -5, &status);
        ks_polygon_get_vertex(polygon, 0, &x, &y, &status);
        check(x == 0 && y == 0, "polygon: the duplicate shares nothing");
        ks_polygon_remove_vertex(copy, 0, &status);
        ks_polygon_num_vertices(copy, &count, &status);
        check(status.failure == KS_FAILURE_NONE && count == 3,
              "polygon: remove_vertex");
        ks_polygon_clear(copy, &status);
        ks_polygon_num_vertices(copy, &count, &status);
        check(status.failure == KS_FAILURE_NONE && count == 0,
              "polygon: clear");
        ks_polygon_map(polygon, &shift, &mapped, &status);
        ks_polygon_get_vertex(mapped, 3, &x, &y, &status);
        check(status.failure == KS_FAILURE_NONE && x == 10 && y == 30,
              "polygon: map");
        ks_polygon_destroy(&mapped, &status);
        ks_polygon_map(polygon, &huge, &mapped, &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "Ks_Polygon.Map: a mapped vertex would exceed the "
                         "supported range")
              && mapped == NULL,
              "polygon: a map beyond the bound fails and gives NULL");
        ks_polygon_destroy(&copy, &status);
        ks_polygon_destroy(&polygon, &status);
        check(status.failure == KS_FAILURE_NONE && polygon == NULL
              && copy == NULL && mapped == NULL,
              "polygon: destroy sets the handles to NULL");
        ks_polygon_create(&polygon, &status);
        ks_polygon_area(polygon, &value, &status);
        check(status.failure == KS_FAILURE_NONE && polygon != NULL
              && value == 0, "polygon: create gives an empty polygon");
        ks_polygon_destroy(&polygon, &status);

        /* Circular annulus section. */
        ks_circular_annulus_section_set_center_radius_angle_start_angle_span_radial_scale(
            0, 0, 10, 0, pi / 2, 2, &section, &status);
        check(status.failure == KS_FAILURE_NONE && section.radial_scale == 2,
              "annulus: set");
        ks_circular_annulus_section_contains_point(&section, 10, 10, &inside,
                                                   &status);
        check(status.failure == KS_FAILURE_NONE && inside == 1,
              "annulus: a point inside");
        ks_circular_annulus_section_contains_point(&section, -15, 0, &inside,
                                                   &status);
        check(status.failure == KS_FAILURE_NONE && inside == 0,
              "annulus: a point outside the span");
        ks_circular_annulus_section_get_bounding_box(&section, &min_x, &min_y,
                                                     &max_x, &max_y,
                                                     &status);
        check(status.failure == KS_FAILURE_NONE && fabs(min_x) <= 1e-12
              && fabs(max_x - 20) <= 1e-12 && fabs(max_y - 20) <= 1e-12,
              "annulus: bounding box");
        ks_circular_annulus_section_area(&section, &value, &status);
        check(status.failure == KS_FAILURE_NONE
              && fabs(value - 75 * pi) <= 1e-12, "annulus: area");
        ks_circular_annulus_section_map(&section, &mirror, &section_out,
                                        &status);
        check(status.failure == KS_FAILURE_NONE
              && section_out.angle_span == -pi / 2,
              "annulus: a mirror negates the span");
        ks_circular_annulus_section_map(&section, &stretch, &section_out,
                                        &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "Ks_Circular_Annulus_Section.Map: the transform "
                         "is not a similarity"),
              "annulus: a stretch is rejected");

        /* Line, segment and point marker. */
        ks_line_set_from_start_xy_end_xy(1, 1, 1, 5, &line, &status);
        check(status.failure == KS_FAILURE_NONE && line.x == 1
              && fabs(line.rotation - pi / 2) <= 1e-12,
              "line: set from two points");
        ks_line_set_from_start_xy_end_xy(1, 1, 1, 1, &line_out, &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "Ks_Line.Set_From_Start_XY_End_XY: the start and "
                         "end points must differ"),
              "line: two equal points are rejected");
        ks_line_get_distance_rotation(&line, &value, &a, &status);
        check(status.failure == KS_FAILURE_NONE && fabs(value + 1) <= 1e-12,
              "line: get_distance_rotation");
        ks_line_set_distance_rotation(-1, pi / 2, &line_out, &status);
        check(status.failure == KS_FAILURE_NONE
              && fabs(line_out.x - 1) <= 1e-12 && fabs(line_out.y) <= 1e-12,
              "line: set_distance_rotation");
        ks_line_map(&line, &rotate, &line_out, &status);
        check(status.failure == KS_FAILURE_NONE
              && fabs(line_out.rotation - pi) <= 1e-12, "line: map");
        ks_line_segment_set_start_length_rotation(1, 2, 5, 0, &segment,
                                                  &status);
        check(status.failure == KS_FAILURE_NONE && segment.end_x == 6
              && segment.end_y == 2, "segment: set start length rotation");
        ks_line_set_from_line_segment(&segment, &line_out, &status);
        check(status.failure == KS_FAILURE_NONE && line_out.x == 1
              && line_out.rotation == 0, "line: set from a segment");
        ks_line_segment_get_start_length_rotation(&segment, &x, &y, &value,
                                                  &a, &status);
        check(status.failure == KS_FAILURE_NONE && value == 5 && a == 0,
              "segment: length and rotation");
        ks_line_segment_get_midpoint(&segment, &x, &y, &status);
        check(status.failure == KS_FAILURE_NONE && x == 3.5 && y == 2,
              "segment: midpoint");
        ks_line_segment_map(&segment, &shift, &segment_out, &status);
        check(status.failure == KS_FAILURE_NONE && segment_out.end_x == 16,
              "segment: map");
        ks_line_segment_set_start_end(0, 0, 2e150, 0, &segment_out, &status);
        check(status.failure == KS_FAILURE_BAD_PARAMETER,
              "segment: an end beyond the bound is rejected");
        ks_point_marker_set_xy_rotation(3, 4, 0.5, &marker, &status);
        ks_point_marker_map(&marker, &identity, &marker_out, &status);
        check(status.failure == KS_FAILURE_NONE && marker_out.x == 3
              && fabs(marker_out.rotation - 0.5) <= 1e-15,
              "point marker: map");
        {
            const ks_transform_2d_linear flat = {1, -1, 1, -1, 0, 0};
            ks_point_marker_set_xy_rotation(0, 0, pi / 4, &marker, &status);
            ks_point_marker_map(&marker, &flat, &marker_out, &status);
            check(status.failure == KS_FAILURE_TRANSFORM_SINGULAR,
                  "point marker: a direction mapped to zero");
        }

        /* Circular arc. */
        ks_circular_arc_set_center_radius_angle_start_angle_span(
            0, 0, 2, 0, pi / 2, &arc, &status);
        ks_circular_arc_get_start_end(&arc, &x, &y, &a, &b, &status);
        check(status.failure == KS_FAILURE_NONE && x == 2 && y == 0
              && fabs(a) <= 1e-12 && fabs(b - 2) <= 1e-12,
              "arc: end points");
        ks_circular_arc_map(&arc, &rotate, &arc_out, &status);
        check(status.failure == KS_FAILURE_NONE
              && fabs(arc_out.angle_start - pi / 2) <= 1e-12,
              "arc: map by a rotation");
        ks_circular_arc_set_center_radius_angle_start_angle_span(
            0, 0, 2, 0, INFINITY, &arc_out, &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "Ks_Circular_Arc.Angle_Span must be finite and "
                         "within +/-1.0E150"),
              "arc: an infinite span is rejected");
    }

    /* Pixel regions. */
    {
        const ks_transform_2d_linear identity = {1, 0, 0, 1, 0, 0};
        const ks_transform_2d_linear doubling = {2, 0, 0, 2, 0, 0};
        const ks_transform_2d_linear flat = {0, 0, 0, 0, 0, 0};
        const ks_transform_2d_linear not_finite = {NAN, 0, 0, 1, 0, 0};
        ks_pixel_region *region = NULL, *copy = NULL;
        ks_rectangle rectangle;
        ks_circle circle;
        ks_polygon *triangle = NULL;
        int32_t count = -1, empty = -1, x_min = -1, y_min = -1;
        int32_t width = -1, height = -1;
        int all = 1, x, y;

        ks_pixel_region_whole_image(4, 3, &region, &status);
        check(status.failure == KS_FAILURE_NONE && region != NULL,
              "region: whole image");
        ks_pixel_region_pixel_count(region, &count, &status);
        ks_pixel_region_bounds(region, &x_min, &y_min, &width, &height,
                               &status);
        check(count == 12 && x_min == 0 && y_min == 0 && width == 4
              && height == 3, "region: whole image count and bounds");
        ks_pixel_region_is_empty(region, &empty, &status);
        check(status.failure == KS_FAILURE_NONE && empty == 0,
              "region: whole image is not empty");
        check(ks_pixel_region_contains(region, 3, 2) == 1
              && ks_pixel_region_contains(region, 0, 0) == 1
              && ks_pixel_region_contains(region, 4, 0) == 0
              && ks_pixel_region_contains(region, 0, -1) == 0,
              "region: whole image contains");
        ks_pixel_region_destroy(&region, &status);
        check(status.failure == KS_FAILURE_NONE && region == NULL,
              "region: destroy sets the handle to NULL");

        ks_pixel_region_whole_image(0, 0, &region, &status);
        check(is_failure(&status, KS_FAILURE_IMAGE_NO_PIXELS,
                         "Whole_Image: the image has no pixels")
              && region == NULL, "region: whole image without pixels");
        ks_pixel_region_whole_image(-1, 5, &region, &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "Whole_Image: the image size -1 x 5 is not valid")
              && region == NULL, "region: a negative size is rejected");
        ks_pixel_region_whole_image(65536, 65536, &region, &status);
        check(status.failure == KS_FAILURE_BAD_PARAMETER && region == NULL,
              "region: more than KS_PIXEL_REGION_MAX_PIXELS is rejected");

        /* An axis-aligned rectangle: x in [2, 6], y in [3, 5]. */
        ks_rectangle_set_xy_width_height(2, 3, 4, 2, &rectangle, &status);
        ks_pixel_region_rasterize_rectangle(10, 8, &identity, &rectangle,
                                            &region, &status);
        ks_pixel_region_pixel_count(region, &count, &status);
        ks_pixel_region_bounds(region, &x_min, &y_min, &width, &height,
                               &status);
        check(status.failure == KS_FAILURE_NONE && count == 15 && x_min == 2
              && y_min == 3 && width == 5 && height == 3,
              "region: rectangle count and bounds");
        for (y = 0; y < 8; y++) {
            for (x = 0; x < 10; x++) {
                int expected = x >= 2 && x <= 6 && y >= 3 && y <= 5;
                if (ks_pixel_region_contains(region, x, y) != expected) {
                    all = 0;
                }
            }
        }
        check(all, "region: rectangle pixels");
        ks_pixel_region_destroy(&region, &status);

        /* A circle of radius 2: the 13 lattice points of the disc. */
        ks_circle_set_center_radius(5, 5, 2, &circle, &status);
        ks_pixel_region_rasterize_circle(11, 11, &identity, &circle, &region,
                                         &status);
        ks_pixel_region_pixel_count(region, &count, &status);
        ks_pixel_region_bounds(region, &x_min, &y_min, &width, &height,
                               &status);
        check(status.failure == KS_FAILURE_NONE && count == 13 && x_min == 3
              && y_min == 3 && width == 5 && height == 5,
              "region: circle count and bounds");
        all = 1;
        for (y = 0; y < 11; y++) {
            for (x = 0; x < 11; x++) {
                int expected = (x - 5) * (x - 5) + (y - 5) * (y - 5) <= 4;
                if (ks_pixel_region_contains(region, x, y) != expected) {
                    all = 0;
                }
            }
        }
        check(all, "region: circle pixels");

        ks_pixel_region_duplicate(region, &copy, &status);
        ks_pixel_region_destroy(&region, &status);
        ks_pixel_region_pixel_count(copy, &count, &status);
        check(status.failure == KS_FAILURE_NONE && count == 13
              && ks_pixel_region_contains(copy, 5, 3) == 1
              && ks_pixel_region_contains(copy, 3, 3) == 0,
              "region: a duplicate outlives the original");
        ks_pixel_region_destroy(&copy, &status);

        /* The same circle given in a space where pixels are half as
           large: radius 4 in pixel space, 49 lattice points. */
        ks_circle_set_center_radius(2.5, 2.5, 2, &circle, &status);
        ks_pixel_region_rasterize_circle(11, 11, &doubling, &circle, &region,
                                         &status);
        ks_pixel_region_pixel_count(region, &count, &status);
        check(status.failure == KS_FAILURE_NONE && count == 49
              && ks_pixel_region_contains(region, 9, 5) == 1
              && ks_pixel_region_contains(region, 10, 5) == 0,
              "region: circle through a scaling transform");
        ks_pixel_region_destroy(&region, &status);

        /* A triangle: x, y >= 0 and x + y <= 4, 15 pixels. */
        ks_polygon_add_vertex(&triangle, 0, 0, KS_POLYGON_APPEND, &status);
        ks_polygon_add_vertex(&triangle, 4, 0, KS_POLYGON_APPEND, &status);
        ks_polygon_add_vertex(&triangle, 0, 4, KS_POLYGON_APPEND, &status);
        ks_pixel_region_rasterize_polygon(10, 10, &identity, triangle,
                                          &region, &status);
        ks_pixel_region_pixel_count(region, &count, &status);
        ks_pixel_region_bounds(region, &x_min, &y_min, &width, &height,
                               &status);
        check(status.failure == KS_FAILURE_NONE && count == 15 && x_min == 0
              && y_min == 0 && width == 5 && height == 5,
              "region: triangle count and bounds");
        check(ks_pixel_region_contains(region, 4, 0) == 1
              && ks_pixel_region_contains(region, 2, 2) == 1
              && ks_pixel_region_contains(region, 4, 1) == 0,
              "region: triangle pixels");
        ks_pixel_region_destroy(&region, &status);
        ks_polygon_destroy(&triangle, &status);
        ks_pixel_region_rasterize_polygon(10, 10, &identity, NULL, &region,
                                          &status);
        check(status.failure == KS_FAILURE_NONE && region == NULL,
              "region: a polygon without vertices gives the empty region");

        /* A region outside the image: the empty region, not a failure. */
        ks_circle_set_center_radius(100, 100, 1, &circle, &status);
        region = (ks_pixel_region *)&status; /* overwritten */
        ks_pixel_region_rasterize_circle(10, 10, &identity, &circle, &region,
                                         &status);
        check(status.failure == KS_FAILURE_NONE && region == NULL,
              "region: a region outside the image is empty");
        ks_pixel_region_is_empty(NULL, &empty, &status);
        ks_pixel_region_pixel_count(NULL, &count, &status);
        ks_pixel_region_bounds(NULL, &x_min, &y_min, &width, &height,
                               &status);
        check(status.failure == KS_FAILURE_NONE && empty == 1 && count == 0
              && x_min == 0 && y_min == 0 && width == 0 && height == 0
              && ks_pixel_region_contains(NULL, 0, 0) == 0,
              "region: the empty region (NULL)");
        copy = (ks_pixel_region *)&status; /* overwritten */
        ks_pixel_region_duplicate(NULL, &copy, &status);
        check(status.failure == KS_FAILURE_NONE && copy == NULL,
              "region: duplicate of NULL is NULL");
        ks_pixel_region_destroy(&copy, &status);
        check(status.failure == KS_FAILURE_NONE, "region: destroy NULL");

        /* Restriction by a mask: a 3 x 3 mask with 0 in the middle over
           (2, 1) .. (4, 3) of a whole 6 x 5 image. */
        {
            ks_image_8_grey *mask = NULL;
            ks_pixel_region *restricted = NULL;

            ks_pixel_region_whole_image(6, 5, &region, &status);
            ks_image_8_grey_create(3, 3, 255, &mask, &status);
            ks_image_8_grey_set_pixel(mask, 1, 1, 0, &status);
            ks_pixel_region_restrict_to_mask(region, mask, 2, 1, &restricted,
                                             &status);
            ks_pixel_region_pixel_count(restricted, &count, &status);
            ks_pixel_region_bounds(restricted, &x_min, &y_min, &width,
                                   &height, &status);
            check(status.failure == KS_FAILURE_NONE && count == 29
                  && x_min == 0 && y_min == 0 && width == 6 && height == 5,
                  "region: restrict removes the pixel under the 0");
            all = 1;
            for (y = 0; y < 5; y++) {
                for (x = 0; x < 6; x++) {
                    int expected = !(x == 3 && y == 2);
                    if (ks_pixel_region_contains(restricted, x, y)
                        != expected) {
                        all = 0;
                    }
                }
            }
            check(all, "region: restrict pixels");
            ks_pixel_region_destroy(&restricted, &status);

            /* Offsets that lay the mask over no pixel, a NULL mask. */
            ks_pixel_region_restrict_to_mask(region, mask, -3, 5,
                                             &restricted, &status);
            ks_pixel_region_pixel_count(restricted, &count, &status);
            check(status.failure == KS_FAILURE_NONE && count == 30,
                  "region: restrict by a mask outside the image");
            ks_pixel_region_destroy(&restricted, &status);
            ks_pixel_region_restrict_to_mask(region, mask, INT32_MAX,
                                             INT32_MIN, &restricted,
                                             &status);
            ks_pixel_region_pixel_count(restricted, &count, &status);
            check(status.failure == KS_FAILURE_NONE && count == 30,
                  "region: restrict with extreme offsets");
            ks_pixel_region_destroy(&restricted, &status);
            ks_pixel_region_restrict_to_mask(region, NULL, 0, 0, &restricted,
                                             &status);
            ks_pixel_region_pixel_count(restricted, &count, &status);
            check(status.failure == KS_FAILURE_NONE && count == 30,
                  "region: restrict by a NULL mask keeps every pixel");
            ks_pixel_region_destroy(&restricted, &status);
            ks_image_8_grey_destroy(&mask, &status);

            /* The first row removed: the rectangle shrinks. */
            ks_image_8_grey_create(6, 1, 0, &mask, &status);
            ks_pixel_region_restrict_to_mask(region, mask, 0, 0, &restricted,
                                             &status);
            ks_pixel_region_pixel_count(restricted, &count, &status);
            ks_pixel_region_bounds(restricted, &x_min, &y_min, &width,
                                   &height, &status);
            check(status.failure == KS_FAILURE_NONE && count == 24
                  && x_min == 0 && y_min == 1 && width == 6 && height == 4,
                  "region: restrict trims a border");
            ks_pixel_region_destroy(&restricted, &status);
            ks_image_8_grey_destroy(&mask, &status);

            /* Every pixel removed, and the empty region: NULL. */
            ks_image_8_grey_create(6, 5, 0, &mask, &status);
            restricted = (ks_pixel_region *)&status; /* overwritten */
            ks_pixel_region_restrict_to_mask(region, mask, 0, 0, &restricted,
                                             &status);
            check(status.failure == KS_FAILURE_NONE && restricted == NULL,
                  "region: restrict removing every pixel gives NULL");
            restricted = (ks_pixel_region *)&status; /* overwritten */
            ks_pixel_region_restrict_to_mask(NULL, mask, 0, 0, &restricted,
                                             &status);
            check(status.failure == KS_FAILURE_NONE && restricted == NULL,
                  "region: restrict of NULL is NULL");
            ks_image_8_grey_destroy(&mask, &status);
            ks_pixel_region_destroy(&region, &status);
        }

        /* Failures, in their documented order. */
        ks_pixel_region_rasterize_circle(0, 0, &not_finite, &circle, &region,
                                         &status);
        check(status.failure == KS_FAILURE_IMAGE_NO_PIXELS && region == NULL,
              "region: rasterize into an image without pixels");
        ks_pixel_region_rasterize_circle(10, 10, &not_finite, &circle,
                                         &region, &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "Rasterize: Pixel_From_Region must be finite and "
                         "within +/-1.0E150") && region == NULL,
              "region: a NaN in the transform is rejected");
        ks_pixel_region_rasterize_circle(10, 10, &flat, &circle, &region,
                                         &status);
        check(status.failure == KS_FAILURE_TRANSFORM_SINGULAR
              && region == NULL, "region: a singular transform is rejected");
        circle.radius = -1;
        ks_pixel_region_rasterize_circle(10, 10, &identity, &circle, &region,
                                         &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "Ks_Circle.Radius must be >= 0") && region == NULL,
              "region: an invalid circle is rejected");
    }

    test_real_image();
    test_geometry();

    /* The tools, one function per tool (test_c_<tool>.c, declared above
       main). */
    test_c_image_processing();
    test_c_blob();
    test_c_caliper();
    test_c_ip_one_image();
    test_c_ip_geometry();
    test_c_dimensioning();
    test_c_create_shapes();
    test_c_calib_fix();
    test_c_cnl_search();
    test_c_pm_align();
    test_c_tool_group();

    adafinal();

    printf("%d checks, %d failures\n", c_test_checks, c_test_failures);
    return c_test_failures == 0 ? 0 : 1;
}
