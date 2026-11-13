/*
 * The blob inspection example (examples/blob_inspection.adb) through the
 * C API: find the washers in a synthetic image, measure them and check
 * that each has exactly one hole of the right size.
 *
 *     c_blob_inspection
 *
 * The library is written in Ada, so the program calls adainit() before
 * the first ks_ function and adafinal() after the last one. Every call
 * reports through a ks_status; a failure carries a message that names
 * the property at fault.
 */

#include <stdio.h>
#include <stdlib.h>

#include "amv.h"

extern void adainit(void);
extern void adafinal(void);

/* Stops the program when a call failed. */
static void check(const ks_status *status, const char *what)
{
    if (status->failure != KS_FAILURE_NONE) {
        fprintf(stderr, "%s failed: %s\n", what, status->message);
        adafinal();
        exit(EXIT_FAILURE);
    }
}

/* Paints a light disc of radius outer centred on (cx, cy) with a hole of
   radius hole (none when hole is 0). Each pixel is sampled 4 x 4 times
   over its square (pixel (x, y) covers [x - 0.5, x + 0.5] x
   [y - 0.5, y + 0.5]), so that the edges are anti-aliased. */
static void disc(ks_image_8_grey *image, double cx, double cy, double outer,
                 double hole)
{
    const uint8_t value = 210;
    ks_status status;
    int32_t x, y;
    int i, j, hits;
    uint8_t old;

    for (y = (int32_t)(cy - outer - 1); y <= (int32_t)(cy + outer + 1); y++) {
        for (x = (int32_t)(cx - outer - 1); x <= (int32_t)(cx + outer + 1);
             x++) {
            hits = 0;
            for (j = 0; j < 4; j++) {
                for (i = 0; i < 4; i++) {
                    double u = x - 0.5 + (i + 0.5) / 4.0 - cx;
                    double v = y - 0.5 + (j + 0.5) / 4.0 - cy;
                    double r2 = u * u + v * v;
                    if (r2 <= outer * outer
                        && (hole == 0.0 || r2 > hole * hole))
                        hits++;
                }
            }
            if (hits > 0) {
                ks_image_8_grey_get_pixel(image, x, y, &old, &status);
                check(&status, "ks_image_8_grey_get_pixel");
                ks_image_8_grey_set_pixel(
                    image, x, y,
                    (uint8_t)(old + (value - old) * hits / 16.0 + 0.5),
                    &status);
                check(&status, "ks_image_8_grey_set_pixel");
            }
        }
    }
}

int main(void)
{
    const ks_transform_2d_linear identity = {1.0, 0.0, 0.0, 1.0, 0.0, 0.0};
    ks_status status;
    ks_image_8_grey *image = NULL;
    ks_pixel_region *region = NULL;
    ks_blob_run_params params;
    ks_blob_measure area_filter = {0};
    ks_blob_results *results = NULL;
    ks_blob_result washer, feature;
    int32_t washers = 0, features = 0, i, j;
    int good = 0, bad = 0, holes;
    double hole_area;

    adainit();

    /* The image: six washers (outer radius 22, hole radius 8; one hole too
       small, one missing) and a speck of dust. */
    ks_image_8_grey_create(320, 200, 30, &image, &status);
    check(&status, "ks_image_8_grey_create");
    disc(image, 60.0, 55.0, 22.0, 8.0);
    disc(image, 160.0, 55.0, 22.0, 8.0);
    disc(image, 260.0, 55.0, 22.0, 8.0);
    disc(image, 60.0, 145.0, 22.0, 8.0);
    disc(image, 160.0, 145.0, 22.0, 4.5);
    disc(image, 260.0, 145.0, 22.0, 0.0);
    disc(image, 112.0, 100.0, 2.0, 0.0);

    /* The run parameters: VisionPro's defaults, then light blobs, an area
       filter of 500 to 5000 square pixels (washers, not dust and not
       holes) and no sorting (row by row order). */
    ks_blob_run_params_default(&params, &status);
    check(&status, "ks_blob_run_params_default");
    params.segmentation_params.polarity = KS_BLOB_POLARITY_LIGHT_BLOBS;
    area_filter.measure = KS_BLOB_MEASURE_AREA;
    area_filter.mode = KS_BLOB_MEASURE_MODE_FILTER;
    area_filter.filter_mode = KS_BLOB_FILTER_INCLUDE_BLOBS_IN_RANGE;
    area_filter.filter_range_low = 500.0;
    area_filter.filter_range_high = 5000.0;
    ks_blob_measure_collection_add(&params.run_time_measures, &area_filter,
                                   &status);
    check(&status, "ks_blob_measure_collection_add");
    params.sort_enabled = 0;

    /* The run: the whole image, measured in pixel space (the identity is
       the transform from pixel space to the selected space). */
    ks_pixel_region_whole_image(320, 200, &region, &status);
    check(&status, "ks_pixel_region_whole_image");
    ks_blob_execute(image, region, &params, &identity, &results, &status);
    check(&status, "ks_blob_execute");

    ks_blob_results_count(results, 1, &washers, &status);
    check(&status, "ks_blob_results_count");
    ks_blob_results_count(results, 0, &features, &status);
    check(&status, "ks_blob_results_count");
    printf("found %d washers among %d features (washers, holes, dust)\n",
           (int)washers, (int)features);

    for (i = 0; i < washers; i++) {
        ks_blob_results_item(results, 1, i, &washer, &status);
        check(&status, "ks_blob_results_item");

        /* The holes are the washer's children with the hole label. */
        holes = 0;
        hole_area = 0.0;
        for (j = 0; j < features; j++) {
            ks_blob_results_item(results, 0, j, &feature, &status);
            check(&status, "ks_blob_results_item");
            if (feature.parent_id == washer.id
                && feature.label == KS_BLOB_LABEL_HOLE) {
                holes++;
                hole_area = feature.area;
            }
        }

        printf("washer at (%.1f, %.1f): area %.1f, ", washer.center_of_mass_x,
               washer.center_of_mass_y, washer.area);
        if (holes == 1 && hole_area >= 150.0 && hole_area <= 250.0) {
            good++;
            printf("hole area %.1f: OK\n", hole_area);
        } else if (holes == 1) {
            bad++;
            printf("hole area %.1f: NG (hole size)\n", hole_area);
        } else if (holes == 0) {
            bad++;
            printf("no hole: NG\n");
        } else {
            bad++;
            printf("several holes: NG\n");
        }
    }
    printf("OK: %d, NG: %d\n", good, bad);

    /* Every handle the library returned is freed by its destroy function. */
    ks_blob_results_destroy(&results, &status);
    ks_pixel_region_destroy(&region, &status);
    ks_image_8_grey_destroy(&image, &status);

    adafinal();
    return EXIT_SUCCESS;
}
