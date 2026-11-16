/*
 * AdaMachineVision (AMV) C API: the code reader (AMV.Kernels.Code_Reader).
 * Included by amv.h; the conventions of amv.h apply (ks_status, adainit).
 *
 * The code reader reads the linear barcodes of an 8-bit grey image, at
 * any orientation and any number of them per image: EAN-13, EAN-8, UPC-A,
 * UPC-E, Code 128, Code 39 and Interleaved 2 of 5 (ITF); and its Data
 * Matrix symbols (ECC 200), when the run parameters ask for them.
 *
 * A run takes the image, the pixels to read as a pixel region
 * (ks_pixel_region_whole_image for the whole image; NULL is the empty
 * region and reads nothing), the run parameters and the transform from
 * pixel space to the image's selected space (ks_image_get_transform with
 * "." as the target and "#" as the source). It returns an owned results
 * handle (NULL when it fails) that ks_code_reader_results_destroy frees.
 *
 * 1. Scan lines. The reader scans the bounding box of the pixels of the
 *    region that lie in the image, along num_directions directions;
 *    direction k makes the angle first_direction + k * pi /
 *    num_directions with the x axis of pixel space. The scan lines of a
 *    direction are parallel, line_spacing pixels apart and centred on the
 *    box; each is sampled bilinearly at steps of one pixel. A sample
 *    outside the image or outside the region is not a sample, and splits
 *    its line into segments that are read separately.
 *
 *    The nearest scan direction is at most 90 / num_directions degrees
 *    away from the direction of a symbol: the default 12 directions
 *    (every 15 degrees) read symbols whose bars are at least a fifth as
 *    tall as the symbol is long, and 24 directions read bars a tenth as
 *    tall. When the direction of the symbols is known, num_directions = 1
 *    with first_direction reads them along it, in a twelfth of the time.
 *
 * 2. Edges. A rise or a fall of at least contrast_threshold grey levels
 *    between a local minimum and the next local maximum (or the reverse)
 *    is an edge, located to a fraction of a pixel where the profile
 *    crosses the level halfway between the light and the dark level of
 *    the surroundings. A rise or fall of less than a quarter of the
 *    steepest step between two samples nearby is ignored as well (the
 *    overshoot next to the edges of a sharpened photograph, the texture
 *    of the print); an overshoot of more than about a fifth of the
 *    contrast of the bars is not, and gives edges where there are none.
 *    contrast_threshold is an absolute number of grey levels: it must be
 *    below the contrast of the symbols and above the swing of the noise;
 *    raise it in a noisy image. The modules of a symbol (its narrowest
 *    bars and spaces) should be at least 1.5 pixels wide.
 *
 * 3. Symbols. Every enabled symbology is tried at every bar, reading the
 *    runs forwards and backwards. A symbol must have its start and stop
 *    patterns, its check character (EAN/UPC and Code 128 always; Code 39
 *    and ITF when the run parameters ask for it) and a light margin on
 *    both sides.
 *
 * 4. Results. Readings of the same text by neighbouring scan lines of one
 *    direction form one candidate: a reading joins the candidate whose
 *    last reading is at most three lines back and at a matching position
 *    (a symbol that cannot be read over three or more neighbouring lines
 *    in its middle gives a result for each part). A candidate read by
 *    fewer than min_scan_lines lines is dropped. Of the candidates that
 *    lie on top of each other or whose scan lines cross only the one read
 *    by the most lines is kept. The results are ordered by the number of
 *    scan lines, greatest first.
 *
 * 5. Data Matrix. When KS_CODE_READER_SYMBOLOGY_DATA_MATRIX is among the
 *    symbologies, a pass of its own (without the scan lines) follows. The
 *    pixels of the area to scan are marked dark or light against a
 *    threshold of their neighbourhood: the level halfway between the
 *    lightest and the darkest pixel of the blocks of 8 by 8 pixels around
 *    them whose lightest and darkest pixel differ by contrast_threshold or
 *    more (an area that has no such difference has no dark pixel); pixels
 *    outside the region are light. Every connected dark area is followed
 *    along its outline. An area whose convex hull has two solid sides that
 *    meet (the "L" of a symbol) and two sides that are not solid gives the
 *    four corners of a symbol; they are refined with all dark pixels near
 *    that outline. The numbers of modules are counted along the two
 *    alternating sides, the modules are looked up at their middles (the
 *    symbol may be seen at an angle: the grid is that of the four corners,
 *    in perspective; the columns of a symbol at least twice as wide as
 *    high are spaced as its alternating upper side shows them, which the
 *    corners of a long symbol do not give exactly), and the codewords are
 *    corrected (Reed-Solomon) and decoded; sizes one or two modules off
 *    the count, and the mirror image of the symbol, are tried as well.
 *
 *    A symbol must be dark on light, with a light margin of two pixels or
 *    more all around (the border of the image and the pixels outside the
 *    region count as light); its L must be one solid dark area that
 *    touches nothing else dark, so a symbol of separate dots is not read,
 *    nor one printed light on dark; its modules should be two pixels or
 *    more. The 24 square sizes (10 x 10 to 144 x 144 modules) and the 6
 *    rectangular ones of ECC 200 are read, and the 18 sizes of the
 *    rectangular extension (DMRE, ISO/IEC 21471: 8 x 48 to 26 x 64
 *    modules); the older ECC 000 to 140 are not. A symbol whose text is
 *    empty is not reported.
 *
 *    The Data Matrix results follow those of the linear barcodes, in the
 *    order in which a scan of the area from its top, left to right, meets
 *    their dark areas. The corners are those of the symbol as it is
 *    printed (0: upper left, 1: upper right, 2: lower right, 3: lower
 *    left, the corner of the L; in the image the symbol may be turned or
 *    mirrored), the angle is the direction from corner 3 to corner 2, the
 *    centre is the middle of the symbol as it is printed (where the
 *    diagonals cross; for a symbol at least twice as wide as high, the
 *    middle of its columns as they were read), and num_scan_lines is 0.
 *
 * Text:
 *  - Data Matrix: the characters of the ASCII, C40, Text, X12, EDIFACT
 *    and Base 256 encodations, each as one char (0 .. 255; no character
 *    set is applied). FNC1 in the first position (GS1) adds nothing to
 *    the text, a later FNC1 is the character GS (29). The macro codewords
 *    05 and 06 add their header "[)>" RS "05" (or "06") GS and their
 *    trailer RS EOT. ECI, structured append and reader programming
 *    codewords are passed over. The text can have up to 3125 characters:
 *    the result holds its first 255 and its whole length, and
 *    ks_code_reader_results_text gives all of it.
 *  - EAN-13: 13 digits; EAN-8: 8 digits; UPC-A: 12 digits; UPC-E: 8
 *    digits (the number system, the six digits of the symbol and the
 *    check digit). An EAN-13 symbol whose first digit is 0 is a UPC-A
 *    symbol: it is reported as UPC-A when UPC-A is enabled and as EAN-13
 *    otherwise.
 *  - Code 128: the data characters (code sets A, B and C, shifts and FNC4
 *    for the characters 128 .. 255). FNC1 in the first position (GS1-128)
 *    adds nothing to the text; a later FNC1 is the character GS (29).
 *    FNC2 and FNC3 add nothing.
 *  - Code 39: the 43 characters of the symbology, without the start and
 *    stop characters; a check character that was asked for is verified
 *    and is part of the text.
 *  - ITF: the digits; a check digit that was asked for is verified and is
 *    part of the text.
 *
 * The spec of the kernel describes the method and every bound in full.
 */

#ifndef AMV_CODE_READER_H
#define AMV_CODE_READER_H

#include "amv.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Symbologies, one bit each: ks_code_reader_run_params.symbologies is a
   sum of them, ks_code_reader_result.symbology is one of them. */
#define KS_CODE_READER_SYMBOLOGY_EAN_13     1
#define KS_CODE_READER_SYMBOLOGY_EAN_8      2
#define KS_CODE_READER_SYMBOLOGY_UPC_A      4
#define KS_CODE_READER_SYMBOLOGY_UPC_E      8
#define KS_CODE_READER_SYMBOLOGY_CODE_128   16
#define KS_CODE_READER_SYMBOLOGY_CODE_39    32
#define KS_CODE_READER_SYMBOLOGY_ITF        64
#define KS_CODE_READER_SYMBOLOGY_ALL_LINEAR 127
#define KS_CODE_READER_SYMBOLOGY_DATA_MATRIX 128
#define KS_CODE_READER_SYMBOLOGY_ALL        255

/* Limits. */
#define KS_CODE_READER_MAX_TEXT_LENGTH  255     /* of a linear barcode
                                                   (longer: not reported)
                                                   and of the text in a
                                                   result */
#define KS_CODE_READER_MAX_MATRIX_TEXT_LENGTH 7089 /* of the whole text of
                                                   a two-dimensional
                                                   symbol */
#define KS_CODE_READER_MAX_DIRECTIONS   180
#define KS_CODE_READER_MAX_LINE_SPACING 1000.0
#define KS_CODE_READER_MAX_LINE_SAMPLES 1048576 /* width + height of the
                                                   area to scan */
#define KS_CODE_READER_MAX_CANDIDATES   4096    /* and so of results */

/* Run parameters; ks_code_reader_run_params_default fills in the
   defaults. */
typedef struct {
    int32_t symbologies;         /* ALL_LINEAR; a sum in 1 .. 255 */
    int32_t num_directions;      /* 12; in 1 .. 180, evenly spaced over
                                    half a turn */
    double  first_direction;     /* 0.0; the angle of direction 0 with the
                                    x axis of pixel space, in radians;
                                    finite and within 1.0e150 */
    double  line_spacing;        /* 4.0; pixels between neighbouring scan
                                    lines, in 1.0 .. 1000.0 */
    int32_t contrast_threshold;  /* 12; the smallest rise or fall that is
                                    an edge, in grey levels, 1 .. 255; for
                                    Data Matrix the smallest difference of
                                    the light and the dark level of a
                                    neighbourhood */
    int32_t min_scan_lines;      /* 2; the fewest scan lines that must
                                    read the same symbol, in 1 .. 1000 */
    int32_t code_39_check_digit; /* 0; 1: a Code 39 symbol must end with
                                    its modulo 43 check character */
    int32_t itf_check_digit;     /* 0; 1: an ITF symbol must end with its
                                    modulo 10 check digit */
    int32_t itf_min_digits;      /* 6; the fewest digits of an ITF symbol,
                                    in 2 .. 254 */
} ks_code_reader_run_params;

/* One symbol. text holds length characters (the first 255 of them when
   length is greater, which only the text of a Data Matrix symbol can be)
   followed by NUL up to its end, so it is a C string whenever the text
   itself holds no NUL (Code 128 and Data Matrix can encode one). For a
   linear barcode the corners are those of the area the reading scan lines
   cover: they bound the scan lines that read the symbol, not the full
   height of its bars, and the centre is the middle of that area (across
   the scan lines it can be about half a line spacing away from the middle
   of the symbol). For a Data Matrix symbol the corners are those of the
   symbol as it is printed, 0: upper left, 1: upper right, 2: lower right,
   3: lower left (the corner of the L), the angle is the direction from
   corner 3 to corner 2, and num_scan_lines is 0. Positions are in the
   space that selected_from_pixel maps pixel space to. */
typedef struct {
    int32_t symbology;      /* one KS_CODE_READER_SYMBOLOGY_* */
    int32_t length;         /* of the whole text: 1 ..
                               KS_CODE_READER_MAX_TEXT_LENGTH, for Data
                               Matrix 1 .. 3125 */
    char    text[KS_CODE_READER_MAX_TEXT_LENGTH + 1];
    double  center_x, center_y;
    double  angle;          /* the direction from the start of the symbol
                               to its end, in (-pi, pi] */
    double  corner_0_x, corner_0_y; /* the start of the symbol on the
                                       first scan line that read it */
    double  corner_1_x, corner_1_y; /* its end on that line */
    double  corner_2_x, corner_2_y; /* its end on the last scan line that
                                       read it */
    double  corner_3_x, corner_3_y; /* its start on that line */
    int32_t num_scan_lines; /* the number of scan lines that read it */
} ks_code_reader_result;

typedef struct ks_code_reader_results ks_code_reader_results; /* opaque */

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
_Static_assert(sizeof(ks_code_reader_run_params) == 48,
               "ks_code_reader_run_params must be 48 bytes");
_Static_assert(offsetof(ks_code_reader_run_params, first_direction) == 8,
               "ks_code_reader_run_params.first_direction offset");
_Static_assert(offsetof(ks_code_reader_run_params, contrast_threshold) == 24,
               "ks_code_reader_run_params.contrast_threshold offset");
_Static_assert(offsetof(ks_code_reader_run_params, itf_min_digits) == 40,
               "ks_code_reader_run_params.itf_min_digits offset");
_Static_assert(sizeof(ks_code_reader_result) == 360,
               "ks_code_reader_result must be 360 bytes");
_Static_assert(offsetof(ks_code_reader_result, text) == 8,
               "ks_code_reader_result.text offset");
_Static_assert(offsetof(ks_code_reader_result, center_x) == 264,
               "ks_code_reader_result.center_x offset");
_Static_assert(offsetof(ks_code_reader_result, num_scan_lines) == 352,
               "ks_code_reader_result.num_scan_lines offset");
#endif

/* The default run parameters. */
void ks_code_reader_run_params_default(ks_code_reader_run_params *params,
                                       ks_status *status);

/* Runs the code reader; a run that finds no symbol succeeds with no
   results. Failures, in this order: KS_FAILURE_IMAGE_NO_PIXELS for a NULL
   image; KS_FAILURE_BAD_PARAMETER for an image that is not valid, run
   parameters that are not valid (the message names the property), a
   transform that is not finite and within 1.0e150, a region that is not
   valid, an area to scan (the bounding box of the pixels of the region in
   the image) whose width plus height exceeds
   KS_CODE_READER_MAX_LINE_SAMPLES; KS_FAILURE_OUT_OF_MEMORY;
   KS_FAILURE_OTHER when more than KS_CODE_READER_MAX_CANDIDATES
   candidates (those of the linear barcodes and the Data Matrix symbols
   together) arise. *results is NULL on failure. */
void ks_code_reader_execute(const ks_image_8_grey *image,
                            const ks_pixel_region *region,
                            const ks_code_reader_run_params *params,
                            const ks_transform_2d_linear *selected_from_pixel,
                            ks_code_reader_results **results,
                            ks_status *status);

/* Frees the results and sets *results to NULL; nothing for NULL. */
void ks_code_reader_results_destroy(ks_code_reader_results **results);

/* The number of symbols (0 for NULL). */
void ks_code_reader_results_count(const ks_code_reader_results *results,
                                  int32_t *count, ks_status *status);

/* The symbol at index, 0-based (KS_FAILURE_INDEX_OUT_OF_RANGE outside
   0 .. count - 1, always for NULL). */
void ks_code_reader_results_item(const ks_code_reader_results *results,
                                 int32_t index, ks_code_reader_result *item,
                                 ks_status *status);

/* A part of the text of the symbol at index: its characters from
   position first on (0-based), at most KS_CODE_READER_MAX_TEXT_LENGTH of
   them, into text (KS_CODE_READER_MAX_TEXT_LENGTH + 1 chars, NUL after
   the characters up to its end); *length is their number. first may be
   0 .. the length of the text; calls with first = 0, 255, 510, ... until
   *length is 0 give the whole text of a symbol whose text is longer than
   a result holds. KS_FAILURE_INDEX_OUT_OF_RANGE for an index outside
   0 .. count - 1 (always for NULL), KS_FAILURE_BAD_PARAMETER for a first
   outside the text; text is all NUL and *length 0 on failure. */
void ks_code_reader_results_text(const ks_code_reader_results *results,
                                 int32_t index, int32_t first,
                                 char text[KS_CODE_READER_MAX_TEXT_LENGTH
                                           + 1],
                                 int32_t *length, ks_status *status);

#ifdef __cplusplus
}
#endif

#endif /* AMV_CODE_READER_H */
