/* Tests of the AMV Flow C API (optional/flow/include/amv_flow.h), the way
 * the editor uses it: a flow built by calls, raw pixels in, JSON and BGRA
 * out; the flow file that test_flow writes (run from the repository root
 * after make test-flow); and the failures. Exit status 1 on any failure. */

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "amv_flow.h"

static int checks = 0;
static int failures = 0;

static void check(int condition, const char *what) {
    checks++;
    if (!condition) {
        failures++;
        printf("FAIL: %s\n", what);
    }
}

static void check_ok(const amvf_status *st, const char *what) {
    checks++;
    if (st->failure != AMVF_OK) {
        failures++;
        printf("FAIL: %s: failure %d: %s\n", what, (int)st->failure,
               st->message);
    }
}

/* Text from one of the JSON functions: asks for the size, then fetches. */
typedef void (*text_fn)(amvf_flow *, char *, int64_t, int64_t *,
                        amvf_status *);

static char *fetch(text_fn fn, amvf_flow *flow, const char *what) {
    amvf_status st;
    int64_t needed = 0;
    fn(flow, NULL, 0, &needed, &st);
    check_ok(&st, what);
    char *text = malloc((size_t)needed);
    fn(flow, text, needed, &needed, &st);
    check_ok(&st, what);
    return text;
}

static char *graphics(amvf_flow *flow, int64_t node) {
    amvf_status st;
    int64_t needed = 0;
    amvf_node_graphics_json(flow, node, NULL, 0, &needed, &st);
    char *text = malloc((size_t)needed);
    amvf_node_graphics_json(flow, node, text, needed, &needed, &st);
    check_ok(&st, "graphics");
    return text;
}

static void kinds_json(amvf_flow *unused, char *b, int64_t c, int64_t *n,
                       amvf_status *st) {
    (void)unused;
    amvf_kinds_json(b, c, n, st);
}

int main(void) {
    amvf_status st;

    check(amvf_abi_version() == AMVF_ABI_VERSION, "ABI version");

    char *kinds = fetch(kinds_json, NULL, "kinds");
    check(strstr(kinds, "\"kind\": \"ShapeMatch\"") != NULL
              && strstr(kinds, "\"choices\"") != NULL,
          "kinds JSON lists ShapeMatch and choices");
    free(kinds);

    /* A flow built by calls: blobs, an integer check, raw pixels in. */
    amvf_flow *flow = amvf_flow_create(&st);
    check_ok(&st, "create");
    amvf_flow_add_input(flow, "Image", "Image_8_Grey", &st);
    check_ok(&st, "add input");
    amvf_flow_add_output(flow, "Count", "Integer", &st);
    check_ok(&st, "add output");
    int64_t blob = amvf_flow_add_node(flow, "Blob", 40.0, 60.0, &st);
    check_ok(&st, "add Blob");
    int64_t judge = amvf_flow_add_node(flow, "RangeCheck", 240.0, 60.0, &st);
    check_ok(&st, "add RangeCheck");
    check(blob == 1 && judge == 2, "node ids 1 and 2");
    amvf_flow_set_param_json(flow, blob, "MinArea", "50", &st);
    check_ok(&st, "set MinArea");
    amvf_flow_set_param_json(flow, blob, "Polarity", "\"Light\"", &st);
    check_ok(&st, "set Polarity");
    amvf_flow_set_param_json(flow, judge, "Low", "3", &st);
    amvf_flow_set_param_json(flow, judge, "High", "3", &st);
    check_ok(&st, "set High");
    amvf_flow_link(flow, "input.Image", "1.Image", &st);
    check_ok(&st, "link the image");
    amvf_flow_link(flow, "1.Count", "2.Value", &st);
    check_ok(&st, "link the count");
    amvf_flow_link(flow, "1.Count", "output.Count", &st);
    check_ok(&st, "link the output");
    amvf_flow_set_node_name(flow, blob, "Spots", &st);
    check_ok(&st, "name a node");

    enum { W = 200, H = 150, S = 208 };
    static uint8_t pixels[S * H];
    static const double discs[3][3] = {
        {40, 40, 10}, {100, 90, 15}, {160, 70, 20}};
    for (int y = 0; y < H; y++)
        for (int x = 0; x < S; x++) {
            uint8_t v = 30;
            for (int d = 0; d < 3; d++) {
                double dx = x - discs[d][0], dy = y - discs[d][1];
                if (x < W && dx * dx + dy * dy <= discs[d][2] * discs[d][2])
                    v = 220;
            }
            pixels[y * S + x] = v;
        }
    amvf_flow_set_input_image_8(flow, "Image", W, H, S, pixels, &st);
    check_ok(&st, "set the image");
    amvf_flow_run(flow, &st);
    check_ok(&st, "run");

    char *results = fetch(amvf_flow_results_json, flow, "results");
    check(strstr(results, "\"result\": \"accept\"") != NULL,
          "results: accepted");
    check(strstr(results, "\"Count\": 3") != NULL, "results: three blobs");
    free(results);

    amvf_flow_run(flow, &st);
    check_ok(&st, "run again");
    results = fetch(amvf_flow_results_json, flow, "results");
    check(strstr(results, "\"runs\": 2, \"accept\": 2") != NULL,
          "results: two runs counted");
    free(results);
    {
        /* A recipe round trip: the Blob's threshold changed, then put back. */
        int64_t need = 0;
        amvf_flow_recipe_json(flow, "A", NULL, 0, &need, &st);
        check_ok(&st, "recipe size");
        char *recipe = malloc((size_t)need);
        amvf_flow_recipe_json(flow, "A", recipe, need, &need, &st);
        check_ok(&st, "recipe");
        check(strstr(recipe, "\"recipe\": \"A\"") != NULL, "recipe: named");
        amvf_flow_apply_recipe(flow, "{\"format\": 1, \"params\": {\"1.Threshold\": 77}}", &st);
        check_ok(&st, "apply a recipe");
        amvf_flow_apply_recipe(flow, "{\"format\": 1, \"params\": {\"8.Low\": 1}}", &st);
        check(st.failure == AMVF_FAILURE_FLOW, "apply a recipe for another flow fails");
        amvf_flow_apply_recipe(flow, recipe, &st);
        check_ok(&st, "apply the saved recipe");
        free(recipe);
        /* A recipe makes a new flow: run it again for results. */
        amvf_flow_run(flow, &st);
        check_ok(&st, "run after the recipe (the image input kept)");
    }
    amvf_flow_reset_counts(flow, &st);
    check_ok(&st, "reset the counts");
    results = fetch(amvf_flow_results_json, flow, "results");
    check(strstr(results, "\"runs\": 0") != NULL, "results: counts reset");
    free(results);

    char *json = fetch(amvf_flow_to_json, flow, "to JSON");
    check(strstr(json, "\"name\": \"Spots\"") != NULL
              && strstr(json, "\"x\": 40.0") != NULL,
          "flow JSON keeps the name and the position");
    free(json);

    char *g = graphics(flow, blob);
    check(strstr(g, "\"width\": 200") != NULL
              && strstr(g, "\"role\": \"found\"") != NULL,
          "graphics: the image size and a found point");
    free(g);

    int32_t w = 0, h = 0;
    amvf_node_image_bgra(flow, blob, NULL, 0, &w, &h, &st);
    check_ok(&st, "image size");
    check(w == W && h == H, "image size 200 x 150");
    uint8_t *bgra = malloc((size_t)w * (size_t)h * 4);
    amvf_node_image_bgra(flow, blob, bgra, (int64_t)w * h * 4, &w, &h, &st);
    check_ok(&st, "image pixels");
    size_t at = ((size_t)70 * W + 160) * 4;
    check(bgra[at] == 220 && bgra[at + 1] == 220 && bgra[at + 2] == 220
              && bgra[at + 3] == 255,
          "image pixels: BGRA of a disc");
    check(bgra[0] == 30, "image pixels: background");
    free(bgra);

    /* Failures */
    int64_t needed = 0;
    char small[4];
    amvf_flow_results_json(flow, small, sizeof small, &needed, &st);
    check(st.failure == AMVF_FAILURE_BAD_ARGUMENT && needed > 4,
          "a small buffer is a bad argument, with the size needed");
    amvf_flow_link(flow, "1.Area", "1.Image", &st);
    check(st.failure == AMVF_FAILURE_FLOW
              && strstr(st.message, "cannot link") != NULL,
          "a link of different types fails with a message");
    amvf_flow_set_param_json(flow, blob, "Threshold", "300", &st);
    check(st.failure == AMVF_FAILURE_FLOW
              && strstr(st.message, "must be in") != NULL,
          "a parameter out of range fails");
    amvf_flow_set_param_json(flow, blob, "Threshold", "[", &st);
    check(st.failure == AMVF_FAILURE_FLOW, "malformed value JSON fails");
    amvf_flow_run(NULL, &st);
    check(st.failure == AMVF_FAILURE_BAD_ARGUMENT, "a NULL flow fails");
    amvf_flow_link(flow, NULL, "1.Image", &st);
    check(st.failure == AMVF_FAILURE_BAD_ARGUMENT, "a NULL string fails");
    amvf_flow_add_node(flow, "Telescope", 0, 0, &st);
    check(st.failure == AMVF_FAILURE_FLOW, "an unknown kind fails");
    amvf_flow_set_input_image_8(flow, "Image", 0, 10, 0, pixels, &st);
    check(st.failure == AMVF_FAILURE_BAD_ARGUMENT, "an empty image fails");
    amvf_flow_destroy(flow);
    amvf_flow_destroy(NULL);

    /* The flow file of test_flow, on its model image. */
    flow = amvf_flow_create(&st);
    amvf_flow_load(flow, "build/flow-test/align.amvflow", &st);
    check_ok(&st, "load align.amvflow (run make test-flow first)");
    if (st.failure == AMVF_OK) {
        amvf_flow_set_input_image_file(flow, "Image",
                                       "build/flow-test/align_model.bmp", &st);
        check_ok(&st, "set the image from a file");
        amvf_flow_run(flow, &st);
        check_ok(&st, "run align");
        results = fetch(amvf_flow_results_json, flow, "align results");
        check(strstr(results, "\"result\": \"accept\"") != NULL
                  && strstr(results, "\"Slot\": 14.0") != NULL,
              "align: accepted, slot 14");
        free(results);
        g = graphics(flow, 3);
        check(strstr(g, "\"role\": \"region\"") != NULL,
              "align: the caliper's region is drawn");
        free(g);
    }
    amvf_flow_load(flow, "build/flow-test/no_such.amvflow", &st);
    check(st.failure == AMVF_FAILURE_FLOW, "a missing file fails");
    amvf_flow_destroy(flow);

    if (failures == 0) {
        printf("PASS: AMV Flow C API, %d checks\n", checks);
        return 0;
    }
    printf("FAIL: %d of %d checks\n", failures, checks);
    return 1;
}
