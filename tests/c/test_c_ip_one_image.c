/*
 * C tests of the IP one-image tool (include/amv_ip_one_image.h): the
 * operator list, the operators on small images whose results are known
 * exactly, a quarter turn with its transform, a region, NULL handles, bad
 * parameters and the layouts of the structs.
 */

#include <math.h>
#include <stdio.h>
#include <string.h>

#include "amv.h"
#include "c_test_support.h"

void test_c_ip_one_image(void);

static int pixel(const ks_image_8_grey *image, int32_t x, int32_t y)
{
    ks_status status;
    uint8_t value = 0;

    ks_image_8_grey_get_pixel(image, x, y, &value, &status);
    return status.failure == KS_FAILURE_NONE ? value : -1;
}

/* A width x height image whose pixel (x, y) is 10 * y + x. */
static ks_image_8_grey *ramp_image(int32_t width, int32_t height)
{
    ks_image_8_grey *image = NULL;
    ks_status status;
    int32_t x, y;

    ks_image_8_grey_create(width, height, 0, &image, &status);
    for (y = 0; y < height; y++)
        for (x = 0; x < width; x++)
            ks_image_8_grey_set_pixel(image, x, y, (uint8_t)(10 * y + x),
                                      &status);
    return image;
}

/* A list of one operator of the given kind (its defaults). */
static void one_operator(ks_ip_one_image_operators *ops, int32_t kind,
                         ks_ip_one_image_operator *op)
{
    ks_status status;

    ks_ip_one_image_operators_default(ops);
    ks_ip_one_image_operator_default(kind, op, &status);
}

static void test_list(void)
{
    static ks_ip_one_image_operators ops;
    static ks_ip_one_image_operator op, item;
    ks_status status;
    int32_t kind, i;

    memset(&ops, 0xFF, sizeof ops);
    ks_ip_one_image_operators_default(&ops);
    check(ops.count == 0 && ops.items[0].enabled == 1
              && ops.items[0].kind == KS_IP_ONE_IMAGE_KIND_ADD_SUBTRACT_CONSTANT,
          "ip one image: an empty list");
    for (kind = KS_IP_ONE_IMAGE_KIND_ADD_SUBTRACT_CONSTANT;
         kind <= KS_IP_ONE_IMAGE_KIND_UNSHARP_MASK; kind++) {
        ks_ip_one_image_operator_default(kind, &op, &status);
        ks_ip_one_image_operators_add(&ops, &op, &status);
    }
    check(status.failure == KS_FAILURE_NONE && ops.count == 15,
          "ip one image: one operator of each kind");
    ks_ip_one_image_check_operators(&ops, &status);
    check(status.failure == KS_FAILURE_NONE,
          "ip one image: every default operator is valid");
    check(ops.items[KS_IP_ONE_IMAGE_KIND_GAUSS_SAMPLER].gauss_sampler
                  .smoothness_x
              == 2
              && ops.items[KS_IP_ONE_IMAGE_KIND_MULTIPLY_CONSTANT]
                         .multiply_constant.constant_value
                     == 1.0
              && ops.items[KS_IP_ONE_IMAGE_KIND_THRESHOLD].threshold.threshold
                     == 128
              && ops.items[KS_IP_ONE_IMAGE_KIND_CONVOLVE_NXM]
                         .convolve_nxm.kernel[16]
                     == 1.0
              && ops.items[KS_IP_ONE_IMAGE_KIND_PIXEL_MAP].pixel_map.map[200]
                     == 200,
          "ip one image: the defaults of the classes");
    ks_ip_one_image_operator_default(KS_IP_ONE_IMAGE_KIND_MEDIAN_3X3, &op,
                                     &status);
    ks_ip_one_image_operators_add(&ops, &op, &status);
    check(ops.count == 16, "ip one image: 16 operators");
    ks_ip_one_image_operators_add(&ops, &op, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Add: the operator list is full (16 operators)")
              && ops.count == 16,
          "ip one image: a full list");
    ks_ip_one_image_operators_remove_at(&ops, 0, &status);
    check(status.failure == KS_FAILURE_NONE && ops.count == 15
              && ops.items[0].kind == KS_IP_ONE_IMAGE_KIND_CONVOLVE_3X3,
          "ip one image: remove_at moves the later items down");
    ks_ip_one_image_operators_move(&ops, 14, 0, &status);
    check(status.failure == KS_FAILURE_NONE
              && ops.items[0].kind == KS_IP_ONE_IMAGE_KIND_MEDIAN_3X3
              && ops.items[1].kind == KS_IP_ONE_IMAGE_KIND_CONVOLVE_3X3,
          "ip one image: move");
    ks_ip_one_image_operator_default(KS_IP_ONE_IMAGE_KIND_EQUALIZE, &op,
                                     &status);
    ks_ip_one_image_operators_insert(&ops, &op, 2, &status);
    ks_ip_one_image_operators_item(&ops, 2, &item, &status);
    check(status.failure == KS_FAILURE_NONE
              && item.kind == KS_IP_ONE_IMAGE_KIND_EQUALIZE && ops.count == 16,
          "ip one image: insert and item");
    ks_ip_one_image_operators_item(&ops, 16, &item, &status);
    check(is_failure(&status, KS_FAILURE_INDEX_OUT_OF_RANGE,
                     "Item: index 16 is outside 0 .. Count - 1"),
          "ip one image: item beyond count");
    ks_ip_one_image_operators_set_item(&ops, 0, &op, &status);
    check(status.failure == KS_FAILURE_NONE
              && ops.items[0].kind == KS_IP_ONE_IMAGE_KIND_EQUALIZE,
          "ip one image: set_item");
    ks_ip_one_image_operator_default(19, &op, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Kind 19 is not a known operator kind"),
          "ip one image: an unknown kind");

    /* Reading a count, a kind and a flag that may have been set by hand. */
    ks_ip_one_image_operators_count(&ops, &i, &status);
    check(status.failure == KS_FAILURE_NONE && i == 16,
          "ip one image: count");
    ops.count = 17;
    ks_ip_one_image_operators_count(&ops, &i, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Operators.Count must be in 0 .. 16")
              && i == 0,
          "ip one image: a count beyond the limit");
    ops.count = 16;
    ks_ip_one_image_operator_get_kind(&ops.items[0], &kind, &status);
    check(status.failure == KS_FAILURE_NONE
              && kind == KS_IP_ONE_IMAGE_KIND_EQUALIZE,
          "ip one image: get_kind");
    item = ops.items[0];
    item.kind = 19;
    ks_ip_one_image_operator_get_kind(&item, &kind, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER && kind == 0,
          "ip one image: get_kind of an unknown kind");
    item.enabled = -1;
    ks_ip_one_image_operator_get_enabled(&item, &i, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER && i == 0,
          "ip one image: get_enabled of a flag that is not 0 or 1");
    ks_ip_one_image_operator_get_enabled(&ops.items[0], &i, &status);
    check(status.failure == KS_FAILURE_NONE && i == 1,
          "ip one image: get_enabled");

    /* Kernel values. */
    ks_ip_one_image_operator_default(KS_IP_ONE_IMAGE_KIND_CONVOLVE_NXM, &op,
                                     &status);
    op.convolve_nxm.kernel_width = 5;
    ks_ip_one_image_convolve_nxm_set_kernel_value(&op.convolve_nxm, 4, 2,
                                                  -2.5, &status);
    check(status.failure == KS_FAILURE_NONE
              && op.convolve_nxm.kernel[2 * 15 + 4] == -2.5,
          "ip one image: set_kernel_value (col, row)");
    ks_ip_one_image_convolve_nxm_set_kernel_value(&op.convolve_nxm, 5, 0,
                                                  1.0, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER,
          "ip one image: a column beyond kernel_width");
    ks_ip_one_image_convolve_nxm_set_kernel_value(&op.convolve_nxm, 0, 0,
                                                  nan(""), &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER
              && op.convolve_nxm.kernel[0] == 0.0,
          "ip one image: a NaN kernel value is rejected");
    {
        double value = -1.0;

        ks_ip_one_image_convolve_3x3_get_kernel_value(
            &op.convolve_3x3, KS_IP_ONE_IMAGE_POSITION_CENTER, &value,
            &status);
        check(status.failure == KS_FAILURE_NONE && value == 1.0,
              "ip one image: the 3x3 kernel's centre");
    }

    /* The checks of execute. */
    ks_ip_one_image_operators_default(&ops);
    ks_ip_one_image_operator_default(KS_IP_ONE_IMAGE_KIND_MEDIAN_NXM, &op,
                                     &status);
    op.median_nxm.kernel_height = 4;
    ks_ip_one_image_operators_add(&ops, &op, &status);
    ks_ip_one_image_check_operators(&ops, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Operators(0).KernelHeight must be an odd number in 1 "
                     ".. 1001"),
          "ip one image: an even kernel height");
    for (i = 0; i < ops.count; i++)
        ops.items[i].enabled = 7;
    ks_ip_one_image_check_operators(&ops, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Operators(0).Enabled must be 0 or 1"),
          "ip one image: a bad enabled flag");
}

static void test_operators(void)
{
    static ks_ip_one_image_operators ops;
    static ks_ip_one_image_operator op;
    ks_status status;
    ks_image_8_grey *image = ramp_image(4, 3);
    ks_image_8_grey *output = NULL;
    ks_pixel_region *region = NULL;
    ks_transform_2d_linear t;
    int32_t width = 0, height = 0;

    ks_pixel_region_whole_image(4, 3, &region, &status);

    /* Threshold: >= 12 gives 200, below gives 5. */
    one_operator(&ops, KS_IP_ONE_IMAGE_KIND_THRESHOLD, &op);
    op.threshold.threshold = 12;
    op.threshold.low_value = 5;
    op.threshold.high_value = 200;
    ks_ip_one_image_operators_add(&ops, &op, &status);
    ks_ip_one_image_execute(image, region, &ops, &output, &t, &status);
    check(status.failure == KS_FAILURE_NONE && pixel(output, 1, 1) == 5
              && pixel(output, 3, 0) == 5 && pixel(output, 2, 1) == 200
              && pixel(output, 0, 2) == 200
              && t.a == 1.0 && t.b == 0.0 && t.translation_x == 0.0,
          "ip one image: threshold, and the identity transform");
    ks_image_8_grey_destroy(&output, &status);

    /* Erode 3 x 3: the minimum of the reflected neighbourhood. */
    one_operator(&ops, KS_IP_ONE_IMAGE_KIND_GREY_MORPHOLOGY_NXM, &op);
    ks_ip_one_image_operators_add(&ops, &op, &status);
    ks_ip_one_image_execute(image, region, &ops, &output, &t, &status);
    check(status.failure == KS_FAILURE_NONE && pixel(output, 2, 1) == 1
              && pixel(output, 0, 0) == 0 && pixel(output, 3, 2) == 12,
          "ip one image: erosion");
    ks_image_8_grey_destroy(&output, &status);

    /* Rotate90Deg: 4 x 3 becomes 3 x 4, (x, y) goes to (2 - y, x). */
    one_operator(&ops, KS_IP_ONE_IMAGE_KIND_FLIP_ROTATE, &op);
    op.flip_rotate.operation_in_pixel_space =
        KS_IP_ONE_IMAGE_FLIP_ROTATE_ROTATE_90_DEG;
    ks_ip_one_image_operators_add(&ops, &op, &status);
    ks_ip_one_image_execute(image, region, &ops, &output, &t, &status);
    ks_image_8_grey_width(output, &width, &status);
    ks_image_8_grey_height(output, &height, &status);
    check(width == 3 && height == 4 && pixel(output, 2, 0) == 0
              && pixel(output, 0, 3) == 23 && pixel(output, 1, 2) == 12,
          "ip one image: a quarter turn");
    check(t.a == 0.0 && t.b == -1.0 && t.c == 1.0 && t.d == 0.0
              && t.translation_x == 2.0 && t.translation_y == 0.0,
          "ip one image: the transform of the quarter turn");
    ks_image_8_grey_destroy(&output, &status);
    ks_ip_one_image_execute(image, NULL, &ops, &output, &t, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER && output == NULL
              && t.b == 0.0 && t.a == 1.0,
          "ip one image: a quarter turn needs the whole image");

    /* SubSampler 2 x 2: 4 x 3 becomes 2 x 2, (x, y) is input (2x, 2y). */
    one_operator(&ops, KS_IP_ONE_IMAGE_KIND_SUB_SAMPLER, &op);
    ks_ip_one_image_operators_add(&ops, &op, &status);
    ks_ip_one_image_execute(image, region, &ops, &output, &t, &status);
    ks_image_8_grey_width(output, &width, &status);
    ks_image_8_grey_height(output, &height, &status);
    check(width == 2 && height == 2 && pixel(output, 1, 0) == 2
              && pixel(output, 0, 1) == 20 && pixel(output, 1, 1) == 22,
          "ip one image: subsampling");
    check(t.a == 0.5 && t.b == 0.0 && t.c == 0.0 && t.d == 0.5
              && t.translation_x == 0.0 && t.translation_y == 0.0,
          "ip one image: the transform of the subsampling");
    ks_image_8_grey_destroy(&output, &status);
    /* With the mean: the block (0 .. 1, 0 .. 1) holds 0, 1, 10, 11 (5.5,
       rounded half up to 6); the last row of blocks is cut (22, 23). */
    ops.items[0].sub_sampler.spatial_average = 1;
    ks_ip_one_image_execute(image, region, &ops, &output, &t, &status);
    check(status.failure == KS_FAILURE_NONE && pixel(output, 0, 0) == 6
              && pixel(output, 1, 1) == 23,
          "ip one image: subsampling with the mean");
    check(t.a == 0.5 && t.translation_x == -0.25 && t.translation_y == -0.25,
          "ip one image: the transform of the mean (block centres)");
    ks_image_8_grey_destroy(&output, &status);
    ops.items[0].sub_sampler.sample_x = 0;
    ks_ip_one_image_execute(image, region, &ops, &output, &t, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Operators(0).SampleX must be in 1 .. 256")
              && output == NULL,
          "ip one image: a sampling of 0");

    /* Expand 2 x 2: 4 x 3 becomes 8 x 6, (x, y) is input (x / 2, y / 2). */
    one_operator(&ops, KS_IP_ONE_IMAGE_KIND_EXPAND, &op);
    ks_ip_one_image_operators_add(&ops, &op, &status);
    ks_ip_one_image_execute(image, region, &ops, &output, &t, &status);
    ks_image_8_grey_width(output, &width, &status);
    ks_image_8_grey_height(output, &height, &status);
    check(width == 8 && height == 6 && pixel(output, 7, 5) == 23
              && pixel(output, 3, 2) == 11 && pixel(output, 2, 3) == 11,
          "ip one image: expansion");
    check(t.a == 2.0 && t.d == 2.0 && t.translation_x == 0.5
              && t.translation_y == 0.5,
          "ip one image: the transform of the expansion");
    ks_image_8_grey_destroy(&output, &status);
    /* Two expansions by 256 x 256 would make 262144 x 196608 pixels. */
    ks_ip_one_image_operators_default(&ops);
    op.expand.expansion_x = 256;
    op.expand.expansion_y = 256;
    ks_ip_one_image_operators_add(&ops, &op, &status);
    ks_ip_one_image_operators_add(&ops, &op, &status);
    ks_ip_one_image_execute(image, region, &ops, &output, &t, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Operators(1) makes an image of more than 2147483647 "
                     "pixels")
              && output == NULL,
          "ip one image: an image too large");

    /* HighPassFilter (Mean 3 x 3): the ramp is linear, so inside the image
       its mean is the pixel itself and the output 128. */
    one_operator(&ops, KS_IP_ONE_IMAGE_KIND_HIGH_PASS_FILTER, &op);
    op.high_pass_filter.processing_mode = KS_IP_ONE_IMAGE_HIGH_PASS_MEAN;
    ks_ip_one_image_operators_add(&ops, &op, &status);
    ks_ip_one_image_execute(image, region, &ops, &output, &t, &status);
    check(status.failure == KS_FAILURE_NONE && pixel(output, 1, 1) == 128
              && pixel(output, 2, 1) == 128,
          "ip one image: a high-pass filter");
    ks_image_8_grey_destroy(&output, &status);
    ops.items[0].high_pass_filter.processing_mode = 3;
    ks_ip_one_image_check_operators(&ops, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Operators(0).ProcessingMode must be Gauss (0), Mean "
                     "(1) or Median (2)"),
          "ip one image: a bad processing mode");
    /* PelSet with a 2 x 1 mask over pixels (1, 0) (0: don't care) and
       (2, 0) (9: care); every pixel the mask does not cover is "care". */
    {
        const ks_image_8_grey *masks[KS_IP_ONE_IMAGE_MAX_OPERATORS] = {0};
        ks_image_8_grey *mask = NULL;

        ks_image_8_grey_create(2, 1, 9, &mask, &status);
        ks_image_8_grey_set_pixel(mask, 0, 0, 0, &status);
        one_operator(&ops, KS_IP_ONE_IMAGE_KIND_PEL_SET, &op);
        op.pel_set.pel_value = 200;
        op.pel_set.input_image_mask_offset_x = 1;
        ks_ip_one_image_operators_add(&ops, &op, &status);
        ks_ip_one_image_execute(image, region, &ops, &output, &t, &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "Operators(0).InputImageMask is not set")
                  && output == NULL,
              "ip one image: PelSet needs a mask");
        ks_ip_one_image_execute_masked(image, region, &ops, NULL, &output,
                                       &t, &status);
        check(status.failure == KS_FAILURE_BAD_PARAMETER && output == NULL,
              "ip one image: PelSet without masks");
        masks[0] = mask;
        ks_ip_one_image_execute_masked(image, region, &ops, masks, &output,
                                       &t, &status);
        check(status.failure == KS_FAILURE_NONE && pixel(output, 1, 0) == 1
                  && pixel(output, 2, 0) == 200 && pixel(output, 0, 0) == 200
                  && pixel(output, 3, 2) == 200,
              "ip one image: PelSet of the care pixels");
        ks_image_8_grey_destroy(&output, &status);
        ops.items[0].pel_set.operation =
            KS_IP_ONE_IMAGE_PEL_SET_DONT_CARE_PELS;
        ks_ip_one_image_execute_masked(image, region, &ops, masks, &output,
                                       &t, &status);
        check(status.failure == KS_FAILURE_NONE && pixel(output, 1, 0) == 200
                  && pixel(output, 2, 0) == 2 && pixel(output, 3, 2) == 23,
              "ip one image: PelSet of the don't-care pixels");
        ks_image_8_grey_destroy(&output, &status);
        ops.items[0].pel_set.pel_value = 256;
        ks_ip_one_image_check_operators(&ops, &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "Operators(0).PelValue must be in 0 .. 255"),
              "ip one image: a PelValue of 256");
        ks_image_8_grey_destroy(&mask, &status);
    }
    check(ks_ip_one_image_sigma(2) == 1.0 && ks_ip_one_image_sigma(0) == 0.0
              && ks_ip_one_image_sigma(25) == 0.0
              && fabs(ks_ip_one_image_sigma(1) - sqrt(0.5)) < 1e-15,
          "ip one image: sigma of a smoothness");

    /* A region: the median changes only the pixels of the rectangle. */
    {
        ks_rectangle r;
        ks_transform_2d_linear identity = {1.0, 0.0, 0.0, 1.0, 0.0, 0.0};
        ks_pixel_region *part = NULL;

        ks_rectangle_set_xy_width_height(-0.5, -0.5, 2.0, 1.0, &r, &status);
        ks_pixel_region_rasterize_rectangle(4, 3, &identity, &r, &part,
                                            &status);
        one_operator(&ops, KS_IP_ONE_IMAGE_KIND_MEDIAN_3X3, &op);
        ks_ip_one_image_operators_add(&ops, &op, &status);
        ks_ip_one_image_execute(image, part, &ops, &output, &t, &status);
        check(status.failure == KS_FAILURE_NONE && pixel(output, 0, 0) == 1
                  && pixel(output, 1, 0) == 2 && pixel(output, 2, 0) == 2
                  && pixel(output, 1, 1) == 11,
              "ip one image: a median inside a region");
        ks_image_8_grey_destroy(&output, &status);
        ks_pixel_region_destroy(&part, &status);
    }

    /* Failures. */
    ks_ip_one_image_execute(NULL, region, &ops, &output, &t, &status);
    check(is_failure(&status, KS_FAILURE_IMAGE_NO_PIXELS,
                     "InputImage has no pixels")
              && output == NULL,
          "ip one image: a NULL image");
    ops.count = 17;
    ks_ip_one_image_execute(image, region, &ops, &output, &t, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Operators.Count must be in 0 .. 16")
              && output == NULL,
          "ip one image: a bad count");
    one_operator(&ops, KS_IP_ONE_IMAGE_KIND_MULTIPLY_CONSTANT, &op);
    op.multiply_constant.constant_value = nan("");
    ks_ip_one_image_operators_add(&ops, &op, &status);
    ks_ip_one_image_execute(image, region, &ops, &output, &t, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Operators(0).ConstantValue must be finite, >= 0 and "
                     "<= 1.0E6")
              && output == NULL,
          "ip one image: a NaN constant");

    ks_pixel_region_destroy(&region, &status);
    ks_image_8_grey_destroy(&image, &status);
}

static void test_region_modes(void)
{
    static ks_ip_one_image_operators ops;
    static ks_ip_one_image_operator op;
    ks_status status;
    ks_image_8_grey *image = ramp_image(6, 5);
    ks_image_8_grey *output = NULL, *expected = NULL, *mask = NULL;
    ks_pixel_region *box = NULL, *disc = NULL;
    ks_transform_2d_linear identity = {1.0, 0.0, 0.0, 1.0, 0.0, 0.0};
    ks_transform_2d_linear t, te;
    ks_rectangle rect = {0.5, 0.5, 3.0, 2.0};
    ks_circle circle = {2.0, 2.0, 1.2};
    ks_rectangle_affine affine = {2.0, 1.5, 3.0, 2.0, 0.3, 0.0};
    ks_affine_transform params;
    int32_t width = 0, height = 0, w2 = 0, h2 = 0, x, y, same = 1;

    /* The rectangle covers pixels 1 .. 3 x 1 .. 2; the circle the cross
       around (2, 2), whose box is 1 .. 3 x 1 .. 3. */
    ks_pixel_region_rasterize_rectangle(6, 5, &identity, &rect, &box,
                                        &status);
    ks_pixel_region_rasterize_circle(6, 5, &identity, &circle, &disc,
                                     &status);

    one_operator(&ops, KS_IP_ONE_IMAGE_KIND_THRESHOLD, &op);
    op.threshold.threshold = 12;
    op.threshold.low_value = 5;
    op.threshold.high_value = 200;
    ks_ip_one_image_operators_add(&ops, &op, &status);
    ks_ip_one_image_execute_in_box(image, box,
                                   KS_REGION_MODE_PIXEL_ALIGNED_BOUNDING_BOX,
                                   &ops, NULL, &output, &t, &status);
    ks_image_8_grey_width(output, &width, &status);
    ks_image_8_grey_height(output, &height, &status);
    check(width == 3 && height == 2 && pixel(output, 0, 0) == 5
              && pixel(output, 1, 0) == 200 && pixel(output, 2, 1) == 200
              && t.a == 1.0 && t.d == 1.0 && t.translation_x == -1.0
              && t.translation_y == -1.0,
          "ip one image: the box of the region, shifted to its corner");
    ks_image_8_grey_destroy(&output, &status);

    ks_ip_one_image_execute_in_box(
        image, disc, KS_REGION_MODE_PIXEL_ALIGNED_BOUNDING_BOX_ADJUST_MASK,
        &ops, NULL, &output, &t, &status);
    check(status.failure == KS_FAILURE_NONE && pixel(output, 0, 0) == 11
              && pixel(output, 1, 1) == 200 && pixel(output, 0, 1) == 200
              && pixel(output, 1, 0) == 200 && pixel(output, 2, 2) == 33,
          "ip one image: adjust mask, only the region's pixels change");
    ks_image_8_grey_destroy(&output, &status);

    ks_ip_one_image_execute_in_box(image, NULL,
                                   KS_REGION_MODE_PIXEL_ALIGNED_BOUNDING_BOX,
                                   &ops, NULL, &output, &t, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER && output == NULL
              && strcmp(status.message,
                        "Region covers no pixel of InputImage") == 0,
          "ip one image: the box of no region");
    ks_ip_one_image_execute_in_box(image, box,
                                   KS_REGION_MODE_AFFINE_TRANSFORM, &ops,
                                   NULL, &output, &t, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER && output == NULL,
          "ip one image: the box with AFFINE_TRANSFORM");

    one_operator(&ops, KS_IP_ONE_IMAGE_KIND_FLIP_ROTATE, &op);
    op.flip_rotate.operation_in_pixel_space =
        KS_IP_ONE_IMAGE_FLIP_ROTATE_ROTATE_90_DEG;
    ks_ip_one_image_operators_add(&ops, &op, &status);
    ks_ip_one_image_execute_in_box(image, box,
                                   KS_REGION_MODE_PIXEL_ALIGNED_BOUNDING_BOX,
                                   &ops, NULL, &output, &t, &status);
    ks_image_8_grey_width(output, &width, &status);
    ks_image_8_grey_height(output, &height, &status);
    /* Input (1, 1) is box (0, 0), which the quarter turn moves to (1, 0). */
    check(width == 2 && height == 3 && pixel(output, 1, 0) == 11
              && t.a == 0.0 && t.b == -1.0 && t.c == 1.0 && t.d == 0.0
              && t.translation_x == 2.0 && t.translation_y == -1.0,
          "ip one image: a quarter turn of the box, and its transform");
    ks_image_8_grey_destroy(&output, &status);
    ks_ip_one_image_execute_in_box(
        image, disc, KS_REGION_MODE_PIXEL_ALIGNED_BOUNDING_BOX_ADJUST_MASK,
        &ops, NULL, &output, &t, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER && output == NULL,
          "ip one image: adjust mask, a quarter turn first needs a region"
          " that fills its box");

    /* AFFINE_TRANSFORM: the resampling of ks_affine_transform_execute with
       its defaults, then the operators (none enabled here). */
    ops.items[0].enabled = 0;
    ks_affine_transform_run_params_default(&params);
    ks_affine_transform_execute(image, &affine, &identity, &identity,
                                &params, 0, &expected, &mask, &te, &status);
    ks_ip_one_image_execute_affine(image, &affine, &identity, &identity,
                                   &ops, NULL, &output, &t, &status);
    ks_image_8_grey_width(output, &width, &status);
    ks_image_8_grey_height(output, &height, &status);
    ks_image_8_grey_width(expected, &w2, &status);
    ks_image_8_grey_height(expected, &h2, &status);
    for (y = 0; y < height && y < h2; y++)
        for (x = 0; x < width && x < w2; x++)
            same = same && pixel(output, x, y) == pixel(expected, x, y);
    check(output != NULL && width == w2 && height == h2 && same
              && t.a == te.a && t.b == te.b && t.translation_x
                                                   == te.translation_x
              && t.translation_y == te.translation_y,
          "ip one image: affine transform, the resampled rectangle");
    ks_image_8_grey_destroy(&output, &status);
    ks_image_8_grey_destroy(&expected, &status);

    one_operator(&ops, KS_IP_ONE_IMAGE_KIND_PEL_SET, &op);
    ks_ip_one_image_operators_add(&ops, &op, &status);
    ks_ip_one_image_execute_affine(image, &affine, &identity, &identity,
                                   &ops, NULL, &output, &t, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER && output == NULL
              && t.a == 1.0 && t.translation_x == 0.0,
          "ip one image: affine transform, no PelSet first");

    ks_pixel_region_destroy(&box, &status);
    ks_pixel_region_destroy(&disc, &status);
    ks_image_8_grey_destroy(&image, &status);
}

void test_c_ip_one_image(void)
{
    check(sizeof(ks_ip_one_image_operator) == 2328
              && sizeof(ks_ip_one_image_operators) == 37256,
          "ip one image: the struct sizes");
    test_list();
    test_operators();
    test_region_modes();
}
