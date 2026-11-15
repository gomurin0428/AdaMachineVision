/*
 * Tests of the code reader's C API (include/amv_code_reader.h): the
 * default run parameters, an EAN-13 symbol and an ITF symbol painted here
 * from the symbology definitions (along x, along y and turned by half a
 * turn), the region, the transform to the selected space, the failures
 * and the results handle.
 */

#include <math.h>
#include <stdio.h>
#include <string.h>

#include "amv.h"
#include "c_test_support.h"

void test_c_code_reader(void);

static const ks_transform_2d_linear identity = {1.0, 0.0, 0.0, 1.0, 0.0,
                                                0.0};

static const double pi = 3.14159265358979323846;

/* ------------------------------------------------------------------ */
/* Symbols                                                             */
/* ------------------------------------------------------------------ */

#define MAX_MODULES 400

/* A symbol as its modules, first to last: 1 for dark, 0 for light. */
typedef struct {
    int  count;
    char dark[MAX_MODULES];
} symbol;

static void append_run(symbol *s, int dark, int width)
{
    int i;

    for (i = 0; i < width && s->count < MAX_MODULES; i++) {
        s->dark[s->count++] = (char)dark;
    }
}

/* Appends the modules of a string of '0' and '1'; with invert, a '1'
   becomes light and a '0' dark; with reverse, the string is read from
   its end. */
static void append_code(symbol *s, const char *code, int invert, int reverse)
{
    int length = (int)strlen(code);
    int i;

    for (i = 0; i < length; i++) {
        int dark = code[reverse ? length - 1 - i : i] == '1';

        append_run(s, invert ? !dark : dark, 1);
    }
}

/* The seven modules of the digits in number set A (odd parity). Number
   set C is its complement, number set B is C read backwards. */
static const char *const ean_set_a[10] = {
    "0001101", "0011001", "0010011", "0111101", "0100011",
    "0110001", "0101111", "0111011", "0110111", "0001011"};

/* The number sets (A or B) of the six left digits, by the first digit. */
static const char *const ean_sets[10] = {
    "AAAAAA", "AABABB", "AABBAB", "AABBBA", "ABAABB",
    "ABBAAB", "ABBBAA", "ABABAB", "ABABBA", "ABBABA"};

/* The EAN-13 symbol of 13 digits (the check digit as given). */
static symbol ean_13(const char *digits)
{
    symbol s;
    int i;

    s.count = 0;
    append_code(&s, "101", 0, 0);
    for (i = 1; i <= 6; i++) {
        int set_b = ean_sets[digits[0] - '0'][i - 1] == 'B';

        append_code(&s, ean_set_a[digits[i] - '0'], set_b, set_b);
    }
    append_code(&s, "01010", 0, 0);
    for (i = 7; i <= 12; i++) {
        append_code(&s, ean_set_a[digits[i] - '0'], 1, 0);
    }
    append_code(&s, "101", 0, 0);
    return s;
}

/* The wide runs ('1') of the five runs of an ITF digit. */
static const char *const itf_wide[10] = {
    "00110", "10001", "01001", "11000", "00101",
    "10100", "01100", "00011", "10010", "01010"};

/* The ITF symbol of an even number of digits: the first digit of a pair
   in the bars, the second in the spaces; wide runs are three modules. */
static symbol itf(const char *digits)
{
    symbol s;
    int i, k;

    s.count = 0;
    append_run(&s, 1, 1);
    append_run(&s, 0, 1);
    append_run(&s, 1, 1);
    append_run(&s, 0, 1);
    for (i = 0; digits[i] != '\0' && digits[i + 1] != '\0'; i += 2) {
        for (k = 0; k < 5; k++) {
            append_run(&s, 1, itf_wide[digits[i] - '0'][k] == '1' ? 3 : 1);
            append_run(&s, 0,
                       itf_wide[digits[i + 1] - '0'][k] == '1' ? 3 : 1);
        }
    }
    append_run(&s, 1, 3);
    append_run(&s, 0, 1);
    append_run(&s, 1, 1);
    return s;
}

/* Directions of a painted symbol. */
#define ALONG_X          0 /* from its first module towards greater x */
#define ALONG_Y          1 /* towards greater y */
#define ALONG_X_BACKWARD 2 /* towards smaller x */

/* A white width x height image with the symbol in black: each module is
   size pixels long, the symbol starts at the pixel first along its
   direction (ends there for ALONG_X_BACKWARD) and covers the pixels
   across_first .. across_last across it. */
static ks_image_8_grey *paint(int32_t width, int32_t height, const symbol *s,
                              int32_t first, int32_t size,
                              int32_t across_first, int32_t across_last,
                              int direction)
{
    ks_status status;
    ks_image_8_grey *image = NULL;
    int32_t m, along, across;

    ks_image_8_grey_create(width, height, 255, &image, &status);
    for (m = 0; m < s->count; m++) {
        int32_t place = direction == ALONG_X_BACKWARD ? s->count - 1 - m : m;

        if (!s->dark[m]) {
            continue;
        }
        for (along = first + place * size;
             along < first + (place + 1) * size; along++) {
            for (across = across_first; across <= across_last; across++) {
                if (direction == ALONG_Y) {
                    ks_image_8_grey_set_pixel(image, across, along, 0,
                                              &status);
                } else {
                    ks_image_8_grey_set_pixel(image, along, across, 0,
                                              &status);
                }
            }
        }
    }
    return image;
}

/* Runs the reader on the whole image and returns the number of results
   (-1 when the run fails), with the first one in *item when there is
   one. */
static int32_t read_all(const ks_image_8_grey *image,
                        const ks_code_reader_run_params *params,
                        ks_code_reader_result *item)
{
    ks_status status;
    ks_pixel_region *region = NULL;
    ks_code_reader_results *results = NULL;
    int32_t width = 0, height = 0, count = -1;

    ks_image_8_grey_width(image, &width, &status);
    ks_image_8_grey_height(image, &height, &status);
    ks_pixel_region_whole_image(width, height, &region, &status);
    ks_code_reader_execute(image, region, params, &identity, &results,
                           &status);
    if (status.failure == KS_FAILURE_NONE) {
        ks_code_reader_results_count(results, &count, &status);
        if (count > 0) {
            ks_code_reader_results_item(results, 0, item, &status);
        }
    }
    ks_code_reader_results_destroy(&results);
    ks_pixel_region_destroy(&region, &status);
    return count;
}

/* 1 when the item is that symbology and exactly that text, followed by
   NUL to the end of the array. */
static int is_text(const ks_code_reader_result *item, int32_t symbology,
                   const char *text)
{
    size_t length = strlen(text);
    size_t i;

    if (item->symbology != symbology || item->length != (int32_t)length
        || memcmp(item->text, text, length) != 0) {
        return 0;
    }
    for (i = length; i < sizeof item->text; i++) {
        if (item->text[i] != '\0') {
            return 0;
        }
    }
    return 1;
}

/* ------------------------------------------------------------------ */
/* Tests                                                               */
/* ------------------------------------------------------------------ */

static void test_defaults(void)
{
    ks_status status;
    ks_code_reader_run_params params;

    memset(&params, 0xFF, sizeof params);
    ks_code_reader_run_params_default(&params, &status);
    check(status.failure == KS_FAILURE_NONE
          && params.symbologies == KS_CODE_READER_SYMBOLOGY_ALL_LINEAR
          && params.num_directions == 12
          && params.first_direction == 0.0
          && params.line_spacing == 4.0
          && params.contrast_threshold == 12
          && params.min_scan_lines == 2
          && params.code_39_check_digit == 0
          && params.itf_check_digit == 0
          && params.itf_min_digits == 6,
          "code reader: run params default");
    check(KS_CODE_READER_SYMBOLOGY_ALL_LINEAR
            == (KS_CODE_READER_SYMBOLOGY_EAN_13
                | KS_CODE_READER_SYMBOLOGY_EAN_8
                | KS_CODE_READER_SYMBOLOGY_UPC_A
                | KS_CODE_READER_SYMBOLOGY_UPC_E
                | KS_CODE_READER_SYMBOLOGY_CODE_128
                | KS_CODE_READER_SYMBOLOGY_CODE_39
                | KS_CODE_READER_SYMBOLOGY_ITF),
          "code reader: ALL_LINEAR is every symbology");
}

/* The EAN-13 symbol 5901234123457, three pixels a module: 285 pixels
   long, from x = 49.5 to x = 334.5 and from y = 19.5 to y = 99.5 in a
   400 x 120 image. */
static void test_ean_13(void)
{
    ks_status status;
    ks_code_reader_run_params params;
    ks_code_reader_results *results = NULL;
    ks_code_reader_result item;
    ks_pixel_region *whole = NULL, *region = NULL;
    const symbol s = ean_13("5901234123457");
    ks_image_8_grey *image = paint(400, 120, &s, 50, 3, 20, 99, ALONG_X);
    ks_image_8_grey *other;
    const ks_transform_2d_linear scaled = {2.0, 0.0, 0.0, 2.0, 10.0, 20.0};
    ks_rectangle band = {0.0, 30.0, 400.0, 30.0};
    ks_rectangle left = {0.0, 0.0, 200.0, 120.0};
    int32_t count = -1;

    check(s.count == 95, "code reader: an EAN-13 symbol has 95 modules");
    ks_code_reader_run_params_default(&params, &status);
    ks_pixel_region_whole_image(400, 120, &whole, &status);

    ks_code_reader_execute(image, whole, &params, &identity, &results,
                           &status);
    check(status.failure == KS_FAILURE_NONE && results != NULL,
          "code reader: execute");
    ks_code_reader_results_count(results, &count, &status);
    memset(&item, 0xFF, sizeof item);
    ks_code_reader_results_item(results, 0, &item, &status);
    check(status.failure == KS_FAILURE_NONE && count == 1
          && is_text(&item, KS_CODE_READER_SYMBOLOGY_EAN_13,
                     "5901234123457")
          && strcmp(item.text, "5901234123457") == 0,
          "code reader: the EAN-13 text");
    check(fabs(item.center_x - 192.0) < 1.0
          && fabs(item.center_y - 59.5) < 3.0 && fabs(item.angle) < 0.01,
          "code reader: the EAN-13 centre and angle");
    check(fabs(item.corner_0_x - 49.5) < 1.0
          && fabs(item.corner_1_x - 334.5) < 1.0
          && fabs(item.corner_2_x - 334.5) < 1.0
          && fabs(item.corner_3_x - 49.5) < 1.0
          && fabs(item.corner_0_y - item.corner_1_y) < 1.0
          && fabs(item.corner_2_y - item.corner_3_y) < 1.0
          && item.corner_0_y >= 19.5 && item.corner_0_y < 24.0
          && item.corner_3_y <= 99.5 && item.corner_3_y > 95.0,
          "code reader: the EAN-13 corners");
    check(item.num_scan_lines == 20,
          "code reader: 20 scan lines cross 80 rows");
    ks_code_reader_results_item(results, 1, &item, &status);
    check(is_failure(&status, KS_FAILURE_INDEX_OUT_OF_RANGE,
                     "Item: index outside the results"),
          "code reader: item beyond count");
    ks_code_reader_results_item(results, -1, &item, &status);
    check(status.failure == KS_FAILURE_INDEX_OUT_OF_RANGE,
          "code reader: item at a negative index");
    ks_code_reader_results_destroy(&results);
    check(results == NULL, "code reader: destroy");
    ks_code_reader_results_destroy(&results);

    /* Positions in the selected space. */
    ks_code_reader_execute(image, whole, &params, &scaled, &results,
                           &status);
    ks_code_reader_results_count(results, &count, &status);
    ks_code_reader_results_item(results, 0, &item, &status);
    check(count == 1 && fabs(item.center_x - 394.0) < 2.0
          && fabs(item.center_y - 139.0) < 6.0 && fabs(item.angle) < 0.01
          && fabs(item.corner_0_x - 109.0) < 2.0
          && fabs(item.corner_1_x - 679.0) < 2.0,
          "code reader: positions in the selected space");
    ks_code_reader_results_destroy(&results);

    /* The region: none, a band across the symbol, its left half. */
    ks_code_reader_execute(image, NULL, &params, &identity, &results,
                           &status);
    ks_code_reader_results_count(results, &count, &status);
    check(status.failure == KS_FAILURE_NONE && results != NULL && count == 0,
          "code reader: a NULL region reads nothing");
    ks_code_reader_results_destroy(&results);

    ks_pixel_region_rasterize_rectangle(400, 120, &identity, &band, &region,
                                        &status);
    ks_code_reader_execute(image, region, &params, &identity, &results,
                           &status);
    ks_code_reader_results_count(results, &count, &status);
    ks_code_reader_results_item(results, 0, &item, &status);
    check(count == 1
          && is_text(&item, KS_CODE_READER_SYMBOLOGY_EAN_13,
                     "5901234123457")
          && item.num_scan_lines >= 5 && item.num_scan_lines <= 9
          && item.corner_0_y >= 29.5 && item.corner_3_y <= 60.5,
          "code reader: a band of the symbol");
    ks_code_reader_results_destroy(&results);
    ks_pixel_region_destroy(&region, &status);

    ks_pixel_region_rasterize_rectangle(400, 120, &identity, &left, &region,
                                        &status);
    ks_code_reader_execute(image, region, &params, &identity, &results,
                           &status);
    ks_code_reader_results_count(results, &count, &status);
    check(status.failure == KS_FAILURE_NONE && count == 0,
          "code reader: half a symbol is not read");
    ks_code_reader_results_destroy(&results);
    ks_pixel_region_destroy(&region, &status);

    /* The symbologies to read. */
    params.symbologies = KS_CODE_READER_SYMBOLOGY_EAN_8
                         | KS_CODE_READER_SYMBOLOGY_CODE_128;
    check(read_all(image, &params, &item) == 0,
          "code reader: EAN-13 is not read when it is not asked for");
    params.symbologies = KS_CODE_READER_SYMBOLOGY_EAN_13;
    check(read_all(image, &params, &item) == 1
          && is_text(&item, KS_CODE_READER_SYMBOLOGY_EAN_13,
                     "5901234123457"),
          "code reader: EAN-13 alone");
    params.symbologies = KS_CODE_READER_SYMBOLOGY_ALL_LINEAR;

    /* One direction along the symbol, and one across it. */
    params.num_directions = 1;
    check(read_all(image, &params, &item) == 1
          && item.num_scan_lines == 20,
          "code reader: one direction along the symbol");
    params.first_direction = pi / 2.0;
    check(read_all(image, &params, &item) == 0,
          "code reader: one direction across the symbol");
    params.num_directions = 12;
    params.first_direction = 0.0;

    /* More scan lines than cross the symbol. */
    params.min_scan_lines = 21;
    check(read_all(image, &params, &item) == 0,
          "code reader: MinScanLines above the lines of the symbol");
    params.min_scan_lines = 2;
    ks_image_8_grey_destroy(&image, &status);

    /* A wrong check digit. */
    {
        const symbol wrong = ean_13("5901234123458");

        other = paint(400, 120, &wrong, 50, 3, 20, 99, ALONG_X);
        check(read_all(other, &params, &item) == 0,
              "code reader: a wrong EAN-13 check digit");
        ks_image_8_grey_destroy(&other, &status);
    }

    /* Along y: from y = 49.5 to y = 334.5. */
    other = paint(120, 400, &s, 50, 3, 20, 99, ALONG_Y);
    check(read_all(other, &params, &item) == 1
          && is_text(&item, KS_CODE_READER_SYMBOLOGY_EAN_13,
                     "5901234123457")
          && fabs(item.center_x - 59.5) < 3.0
          && fabs(item.center_y - 192.0) < 1.0
          && fabs(item.angle - pi / 2.0) < 0.01
          && fabs(item.corner_0_y - 49.5) < 1.0
          && fabs(item.corner_1_y - 334.5) < 1.0,
          "code reader: a symbol along y");
    ks_image_8_grey_destroy(&other, &status);

    /* Turned by half a turn: it starts at x = 334.5. */
    other = paint(400, 120, &s, 50, 3, 20, 99, ALONG_X_BACKWARD);
    check(read_all(other, &params, &item) == 1
          && is_text(&item, KS_CODE_READER_SYMBOLOGY_EAN_13,
                     "5901234123457")
          && fabs(item.center_x - 192.0) < 1.0
          && fabs(fabs(item.angle) - pi) < 0.01
          && fabs(item.corner_0_x - 334.5) < 1.0
          && fabs(item.corner_1_x - 49.5) < 1.0,
          "code reader: a symbol turned by half a turn");
    ks_image_8_grey_destroy(&other, &status);

    ks_pixel_region_destroy(&whole, &status);
}

/* ITF symbols of ten digits, three pixels a module: 99 modules. */
static void test_itf(void)
{
    ks_status status;
    ks_code_reader_run_params params;
    ks_code_reader_result item;
    const symbol checked = itf("1234567895");
    const symbol plain = itf("1234567890");
    ks_image_8_grey *image;

    check(checked.count == 99, "code reader: ten ITF digits are 99 modules");
    ks_code_reader_run_params_default(&params, &status);

    image = paint(400, 120, &checked, 50, 3, 20, 99, ALONG_X);
    check(read_all(image, &params, &item) == 1
          && is_text(&item, KS_CODE_READER_SYMBOLOGY_ITF, "1234567895")
          && fabs(item.center_x - 198.0) < 1.0 && fabs(item.angle) < 0.01,
          "code reader: an ITF symbol");
    params.itf_check_digit = 1;
    check(read_all(image, &params, &item) == 1
          && is_text(&item, KS_CODE_READER_SYMBOLOGY_ITF, "1234567895"),
          "code reader: an ITF symbol with its check digit");
    params.itf_check_digit = 0;
    params.itf_min_digits = 12;
    check(read_all(image, &params, &item) == 0,
          "code reader: an ITF symbol shorter than ITFMinDigits");
    params.itf_min_digits = 10;
    check(read_all(image, &params, &item) == 1,
          "code reader: an ITF symbol of ITFMinDigits digits");
    params.itf_min_digits = 6;
    ks_image_8_grey_destroy(&image, &status);

    image = paint(400, 120, &plain, 50, 3, 20, 99, ALONG_X);
    check(read_all(image, &params, &item) == 1
          && is_text(&item, KS_CODE_READER_SYMBOLOGY_ITF, "1234567890"),
          "code reader: an ITF symbol without a check digit");
    params.itf_check_digit = 1;
    check(read_all(image, &params, &item) == 0,
          "code reader: an ITF symbol whose last digit is not its check");
    ks_image_8_grey_destroy(&image, &status);
}

/* A run with one changed run parameter fails with that message. */
static void check_bad(const ks_image_8_grey *image,
                      const ks_pixel_region *region,
                      const ks_code_reader_run_params *params,
                      const char *message, const char *description)
{
    ks_status status;
    ks_code_reader_results *results = NULL;

    ks_code_reader_execute(image, region, params, &identity, &results,
                           &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER, message)
          && results == NULL, description);
    ks_code_reader_results_destroy(&results);
}

static void test_failures(void)
{
    ks_status status;
    ks_code_reader_run_params defaults, params;
    ks_code_reader_results *results = NULL;
    ks_code_reader_result item;
    ks_pixel_region *region = NULL;
    ks_image_8_grey *image = NULL;
    ks_transform_2d_linear transform = identity;
    int32_t count = -1;

    ks_code_reader_run_params_default(&defaults, &status);
    ks_image_8_grey_create(64, 48, 255, &image, &status);
    ks_pixel_region_whole_image(64, 48, &region, &status);

    /* The image comes first. */
    params = defaults;
    params.symbologies = 0;
    ks_code_reader_execute(NULL, region, &params, &identity, &results,
                           &status);
    check(is_failure(&status, KS_FAILURE_IMAGE_NO_PIXELS,
                     "InputImage has no pixels")
          && results == NULL,
          "code reader: a NULL image");

    check_bad(image, region, &params,
              "RunParams.Symbologies must be a sum of"
              " KS_CODE_READER_SYMBOLOGY_*, in 1 .. 127",
              "code reader: Symbologies 0");
    params.symbologies = 128;
    check_bad(image, region, &params,
              "RunParams.Symbologies must be a sum of"
              " KS_CODE_READER_SYMBOLOGY_*, in 1 .. 127",
              "code reader: Symbologies 128");

    params = defaults;
    params.num_directions = 0;
    check_bad(image, region, &params,
              "RunParams.NumDirections must be in 1 .. 180",
              "code reader: NumDirections 0");
    params.num_directions = KS_CODE_READER_MAX_DIRECTIONS + 1;
    check_bad(image, region, &params,
              "RunParams.NumDirections must be in 1 .. 180",
              "code reader: NumDirections 181");

    params = defaults;
    params.first_direction = NAN;
    check_bad(image, region, &params,
              "RunParams.FirstDirection must be finite and within"
              " +/-1.0E150",
              "code reader: FirstDirection NaN");
    params.first_direction = 1.0e151;
    check_bad(image, region, &params,
              "RunParams.FirstDirection must be finite and within"
              " +/-1.0E150",
              "code reader: FirstDirection 1e151");

    params = defaults;
    params.line_spacing = 0.5;
    check_bad(image, region, &params,
              "RunParams.LineSpacing must be in 1.0 .. 1000.0",
              "code reader: LineSpacing 0.5");
    params.line_spacing = NAN;
    check_bad(image, region, &params,
              "RunParams.LineSpacing must be in 1.0 .. 1000.0",
              "code reader: LineSpacing NaN");
    params.line_spacing = KS_CODE_READER_MAX_LINE_SPACING + 1.0;
    check_bad(image, region, &params,
              "RunParams.LineSpacing must be in 1.0 .. 1000.0",
              "code reader: LineSpacing 1001");

    params = defaults;
    params.contrast_threshold = 0;
    check_bad(image, region, &params,
              "RunParams.ContrastThreshold must be in 1 .. 255",
              "code reader: ContrastThreshold 0");
    params.contrast_threshold = 256;
    check_bad(image, region, &params,
              "RunParams.ContrastThreshold must be in 1 .. 255",
              "code reader: ContrastThreshold 256");

    params = defaults;
    params.min_scan_lines = 0;
    check_bad(image, region, &params,
              "RunParams.MinScanLines must be in 1 .. 1000",
              "code reader: MinScanLines 0");
    params.min_scan_lines = 1001;
    check_bad(image, region, &params,
              "RunParams.MinScanLines must be in 1 .. 1000",
              "code reader: MinScanLines 1001");

    params = defaults;
    params.code_39_check_digit = 2;
    check_bad(image, region, &params,
              "RunParams.Code39CheckDigit must be 0 or 1",
              "code reader: Code39CheckDigit 2");

    params = defaults;
    params.itf_check_digit = -1;
    check_bad(image, region, &params,
              "RunParams.ITFCheckDigit must be 0 or 1",
              "code reader: ITFCheckDigit -1");

    params = defaults;
    params.itf_min_digits = 1;
    check_bad(image, region, &params,
              "RunParams.ITFMinDigits must be in 2 .. 254",
              "code reader: ITFMinDigits 1");
    params.itf_min_digits = 255;
    check_bad(image, region, &params,
              "RunParams.ITFMinDigits must be in 2 .. 254",
              "code reader: ITFMinDigits 255");

    /* The limits of the parameters are accepted, and a blank image has no
       symbol. */
    params = defaults;
    params.symbologies = KS_CODE_READER_SYMBOLOGY_ITF;
    params.num_directions = KS_CODE_READER_MAX_DIRECTIONS;
    params.first_direction = -1.0e150;
    params.line_spacing = KS_CODE_READER_MAX_LINE_SPACING;
    params.contrast_threshold = 255;
    params.min_scan_lines = 1000;
    params.code_39_check_digit = 1;
    params.itf_check_digit = 1;
    params.itf_min_digits = 254;
    ks_code_reader_execute(image, region, &params, &identity, &results,
                           &status);
    ks_code_reader_results_count(results, &count, &status);
    check(status.failure == KS_FAILURE_NONE && results != NULL && count == 0,
          "code reader: the limits of the run parameters");
    ks_code_reader_results_destroy(&results);

    /* The transform. */
    transform.translation_x = NAN;
    ks_code_reader_execute(image, region, &defaults, &transform, &results,
                           &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Selected_From_Pixel must be finite and within"
                     " +/-1.0E150")
          && results == NULL,
          "code reader: a transform that is not finite");
    ks_pixel_region_destroy(&region, &status);
    ks_image_8_grey_destroy(&image, &status);

    /* An area to scan whose width plus height is above the limit. */
    ks_image_8_grey_create(KS_CODE_READER_MAX_LINE_SAMPLES, 1, 255, &image,
                           &status);
    ks_pixel_region_whole_image(KS_CODE_READER_MAX_LINE_SAMPLES, 1, &region,
                                &status);
    check(image != NULL && region != NULL,
          "code reader: an image 1048576 pixels wide");
    check_bad(image, region, &defaults,
              "CodeReader: the width plus the height of the area to scan"
              " must not exceed 1048576",
              "code reader: an area to scan above the limit");
    ks_pixel_region_destroy(&region, &status);
    ks_image_8_grey_destroy(&image, &status);

    /* The results handle. */
    count = -1;
    ks_code_reader_results_count(NULL, &count, &status);
    check(status.failure == KS_FAILURE_NONE && count == 0,
          "code reader: the count of NULL results");
    ks_code_reader_results_item(NULL, 0, &item, &status);
    check(is_failure(&status, KS_FAILURE_INDEX_OUT_OF_RANGE,
                     "Item: index outside the results"),
          "code reader: an item of NULL results");
    results = NULL;
    ks_code_reader_results_destroy(&results);
    check(results == NULL, "code reader: destroy of NULL results");
}

void test_c_code_reader(void)
{
    test_defaults();
    test_ean_13();
    test_itf();
    test_failures();
}
