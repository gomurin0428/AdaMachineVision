/* AMV Flow C API (docs/FLOW_EDITOR_DESIGN.md 7): the flow engine of
 * optional/flow as a shared library (amvflow), for the JavaFX editor and
 * other languages.
 *
 *  - Every function but amvf_abi_version and amvf_flow_destroy reports its
 *    outcome in the amvf_status it is given (never NULL): failure 0 is
 *    success; otherwise message holds why (UTF-8, at most
 *    AMVF_MAX_MESSAGE_LENGTH bytes, NUL-terminated).
 *  - Strings passed in are NUL-terminated UTF-8.
 *  - Text and images come back in the caller's buffer: with capacity 0 a
 *    call only stores the size it needs (bytes, with the NUL for text) in
 *    *needed (or the image's width and height); with a buffer at least
 *    that large it writes. A smaller non-zero capacity is a failure.
 *  - A flow handle is used by one thread at a time.
 *  - JSON shapes are those of AMV.Flow.Reports and of the flow files.
 */
#ifndef AMV_FLOW_H
#define AMV_FLOW_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define AMVF_ABI_VERSION 1
#define AMVF_MAX_MESSAGE_LENGTH 1023

#define AMVF_OK                    0
#define AMVF_FAILURE_FLOW          1 /* not a valid flow, file or edit */
#define AMVF_FAILURE_BAD_ARGUMENT  2 /* NULL handle, small buffer, ... */
#define AMVF_FAILURE_AMV           3 /* an AMV tool or image failure */
#define AMVF_FAILURE_OUT_OF_MEMORY 4
#define AMVF_FAILURE_INTERNAL      5

typedef struct {
    int32_t failure;                            /* AMVF_OK or AMVF_FAILURE_* */
    int32_t length;                             /* of message */
    char    message[AMVF_MAX_MESSAGE_LENGTH + 1];
} amvf_status;

typedef struct amvf_flow amvf_flow;

int32_t amvf_abi_version(void);

/* The node kinds, their ports and parameters (JSON). */
void amvf_kinds_json(char *buffer, int64_t capacity, int64_t *needed,
                     amvf_status *status);

/* Flows */
amvf_flow *amvf_flow_create(amvf_status *status);
void amvf_flow_destroy(amvf_flow *flow); /* NULL is ignored */
void amvf_flow_load(amvf_flow *flow, const char *path, amvf_status *status);
void amvf_flow_save(amvf_flow *flow, const char *path, amvf_status *status);
void amvf_flow_to_json(amvf_flow *flow, char *buffer, int64_t capacity,
                       int64_t *needed, amvf_status *status);
void amvf_flow_from_json(amvf_flow *flow, const char *json,
                         const char *base_directory, amvf_status *status);
void amvf_flow_set_base_directory(amvf_flow *flow, const char *directory,
                                  amvf_status *status);

/* Editing; every edit is checked by the engine. */
int64_t amvf_flow_add_node(amvf_flow *flow, const char *kind, double x,
                           double y, amvf_status *status);
void amvf_flow_remove_node(amvf_flow *flow, int64_t node,
                           amvf_status *status);
void amvf_flow_set_node_position(amvf_flow *flow, int64_t node, double x,
                                 double y, amvf_status *status);
void amvf_flow_set_node_name(amvf_flow *flow, int64_t node, const char *name,
                             amvf_status *status);
void amvf_flow_link(amvf_flow *flow, const char *from, const char *to,
                    amvf_status *status);
void amvf_flow_unlink(amvf_flow *flow, const char *to, amvf_status *status);
void amvf_flow_set_param_json(amvf_flow *flow, int64_t node, const char *name,
                              const char *value_json, amvf_status *status);
void amvf_flow_add_input(amvf_flow *flow, const char *name,
                         const char *type_name, amvf_status *status);
void amvf_flow_add_output(amvf_flow *flow, const char *name,
                          const char *type_name, amvf_status *status);
void amvf_flow_problems_json(amvf_flow *flow, char *buffer, int64_t capacity,
                             int64_t *needed, amvf_status *status);

/* Inputs and running */
void amvf_flow_set_input_image_8(amvf_flow *flow, const char *input,
                                 int32_t width, int32_t height,
                                 int32_t stride, const uint8_t *pixels,
                                 amvf_status *status);
void amvf_flow_set_input_image_file(amvf_flow *flow, const char *input,
                                    const char *path, amvf_status *status);
void amvf_flow_run(amvf_flow *flow, amvf_status *status);

/* Results of the last run */
void amvf_flow_results_json(amvf_flow *flow, char *buffer, int64_t capacity,
                            int64_t *needed, amvf_status *status);
void amvf_node_graphics_json(amvf_flow *flow, int64_t node, char *buffer,
                             int64_t capacity, int64_t *needed,
                             amvf_status *status);
/* The node's input image of the last run as 8-bit B, G, R, A (A = 255),
 * width * height * 4 bytes, rows top to bottom. Without an image:
 * width = height = 0. */
void amvf_node_image_bgra(amvf_flow *flow, int64_t node, uint8_t *buffer,
                          int64_t capacity, int32_t *width, int32_t *height,
                          amvf_status *status);

#ifdef __cplusplus
}
#endif

#endif /* AMV_FLOW_H */
