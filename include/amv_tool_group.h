/*
 * AdaMachineVision (AMV) C API: the tool group and the terminals of a tool
 * block (AMV.Kernels.Tool_Group, the counterpart of CogToolGroup and of
 * the CogToolBlockTerminalCollection of a CogToolBlock). Included by
 * amv.h; the conventions of amv.h apply (ks_status, adainit).
 *
 * A group does not run tools itself: it holds every decision of a run
 * (which member runs next, when the run stops, its result and message)
 * and the caller runs the members.
 *
 * Groups. A ks_tool_group * is an owned handle (NULL is an empty group:
 * own key 0, AbortRunOnToolFailure 0). Its members are 64-bit keys chosen
 * by the caller (the Ada API uses the tools' addresses), each with a
 * disabled flag (VisionPro's DisabledTools: a disabled member stays in
 * the group and is skipped by a run). A key is a member at most once and
 * never equals the group's own key (KS_FAILURE_BAD_PARAMETER for a
 * duplicate, for the own key and beyond KS_TOOL_GROUP_MAX_MEMBERS). The
 * functions taking ks_tool_group ** create the group when *group is NULL.
 * Indices are 0-based (KS_FAILURE_INDEX_OUT_OF_RANGE outside).
 *
 * Runs. A run goes through a cursor that the caller owns and passes back
 * unchanged:
 *
 *   ks_tool_group_run_begin(&group, script_result, &script_message,
 *                           run_tools, &cursor, &status);
 *   for (;;) {
 *       ks_tool_group_run_next(group, &cursor, &index, &more, &status);
 *       if (!more) break;
 *       ... run member index, then ...
 *       ks_tool_group_run_report(group, &cursor, index, result, &name,
 *                                &message, &status);
 *   }
 *   ks_tool_group_run_end(group, &cursor, &result, &first_failure,
 *                         &message, &status);
 *
 * script_result and script_message start the run's result and message
 * (KS_TOOL_RESULT_ACCEPT and an empty text without a script); run_tools 0
 * runs no member (a script's GroupRun returned false). run_next offers
 * the enabled members in order, each once; with AbortRunOnToolFailure set
 * it offers none after a member reported KS_TOOL_RESULT_ERROR (only Error
 * stops a run). run_end returns the worst result (Error > Reject > Warning
 * > Accept), the first member that did not accept (KS_TOOL_GROUP_NO_INDEX
 * for none) and the message: the script's message, then "<name>: <the
 * member's message>" for that member ("tool <index>" without a name, its
 * result without a message), joined by "; ", cut at
 * KS_TOOL_TEXT_MAX_LENGTH characters. A run of a group that is running
 * already, a cursor of another run, a call out of order and any change of
 * the group during the run give KS_FAILURE_BAD_PARAMETER; after a failed
 * run_next or run_report, more is 0 and run_end reports the failure.
 * run_end always ends the run its cursor belongs to.
 *
 * Terminals. A ks_tool_block_terminals * is an owned handle (NULL is the
 * empty collection) of up to KS_TOOL_BLOCK_MAX_TERMINALS named terminals:
 * names of 1 to KS_TOOL_BLOCK_MAX_NAME_LENGTH characters, unique
 * (case-sensitive), a type (KS_TOOL_BLOCK_TYPE_*) and a value. The kernel
 * stores the values of the scalar types (any finite double, int64_t, 0 or
 * 1, a string of at most KS_TOOL_TEXT_MAX_LENGTH bytes); for the object
 * types it only records whether the terminal has a value, and the caller
 * keeps the objects by terminal index (set_object and get_object return
 * it after checking the name and type). Get and set check the type: an
 * unknown name or another type gives KS_FAILURE_BAD_PARAMETER and changes
 * nothing.
 *
 * Texts. Names, messages and string values are ks_tool_text: length
 * characters in text (not NUL-terminated at KS_TOOL_TEXT_MAX_LENGTH).
 * A longer length keeps the first KS_TOOL_TEXT_MAX_LENGTH characters: a
 * message is cut there, a name or a string value is rejected. A negative
 * length is malformed. Texts returned have NUL characters after their
 * length.
 *
 * The meaning of every field and operation is documented in
 * src/amv-kernels-tool_group.ads, src/amv-tool_group.ads and
 * src/amv-tool_block.ads.
 *
 * AMV is not affiliated with or endorsed by Cognex Corporation; "Cognex"
 * and "VisionPro" are trademarks of Cognex Corporation.
 */

#ifndef AMV_TOOL_GROUP_H
#define AMV_TOOL_GROUP_H

#include "amv.h"

#ifdef __cplusplus
extern "C" {
#endif

#define KS_TOOL_GROUP_MAX_MEMBERS     256
#define KS_TOOL_BLOCK_MAX_TERMINALS   128
#define KS_TOOL_BLOCK_MAX_NAME_LENGTH 256
#define KS_TOOL_TEXT_MAX_LENGTH       1024
#define KS_TOOL_GROUP_NO_INDEX        (-1)

/* CogToolResultConstants (VisionPro's values). */
#define KS_TOOL_RESULT_ERROR   (-1)
#define KS_TOOL_RESULT_ACCEPT  0
#define KS_TOOL_RESULT_WARNING 1
#define KS_TOOL_RESULT_REJECT  2

/* Terminal value types (AMV codes). */
#define KS_TOOL_BLOCK_TYPE_REAL          0 /* double */
#define KS_TOOL_BLOCK_TYPE_INTEGER       1 /* int64_t */
#define KS_TOOL_BLOCK_TYPE_BOOLEAN       2 /* int32_t 0 or 1 */
#define KS_TOOL_BLOCK_TYPE_STRING        3 /* ks_tool_text */
#define KS_TOOL_BLOCK_TYPE_IMAGE_8_GREY  4 /* objects: kept by the caller */
#define KS_TOOL_BLOCK_TYPE_IMAGE_16_GREY 5
#define KS_TOOL_BLOCK_TYPE_TRANSFORM     6
#define KS_TOOL_BLOCK_TYPE_SHAPE         7

/* Why a call of a run failed (ks_tool_group_cursor.fault). */
#define KS_TOOL_GROUP_FAULT_NONE    0
#define KS_TOOL_GROUP_FAULT_CHANGED 1 /* the group changed during the run */
#define KS_TOOL_GROUP_FAULT_MISUSE  2 /* out of order, bad arguments */

typedef struct {
    int32_t length;
    char    text[KS_TOOL_TEXT_MAX_LENGTH];
} ks_tool_text;

typedef struct {
    int64_t      own_key;       /* of the group at run_begin */
    uint64_t     change_count;  /* of the group at run_begin */
    uint64_t     run;           /* serial of the run, 0 once ended */
    int32_t      next;          /* first member not yet considered */
    int32_t      pending;       /* offered, not yet reported; -1 */
    int32_t      worst;         /* worst result so far */
    int32_t      first_failure; /* first member not accepting; -1 */
    int32_t      stopped;       /* 1: no member is offered any more */
    int32_t      fault;         /* KS_TOOL_GROUP_FAULT_* */
    ks_tool_text message;       /* the run's message so far */
} ks_tool_group_cursor;

typedef struct ks_tool_group ks_tool_group;                     /* opaque */
typedef struct ks_tool_block_terminals ks_tool_block_terminals; /* opaque */

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
_Static_assert(sizeof(ks_tool_text) == 1028,
               "ks_tool_text must be 1028 bytes");
_Static_assert(sizeof(ks_tool_group_cursor) == 1080,
               "ks_tool_group_cursor must be 1080 bytes");
_Static_assert(offsetof(ks_tool_group_cursor, next) == 24,
               "ks_tool_group_cursor.next offset");
_Static_assert(offsetof(ks_tool_group_cursor, message) == 48,
               "ks_tool_group_cursor.message offset");
#endif

/* ------------------------------------------------------------------ */
/* Groups                                                              */
/* ------------------------------------------------------------------ */

/* A new empty group whose own key is own_key. */
void ks_tool_group_create(int64_t own_key, ks_tool_group **group,
                          ks_status *status);
/* Frees *group (nothing for NULL) and sets it to NULL; the member tools
   are not touched. */
void ks_tool_group_destroy(ks_tool_group **group);
/* A copy with the same members, flags and settings and no run in
   progress (NULL for NULL). */
void ks_tool_group_duplicate(const ks_tool_group *group,
                             ks_tool_group **copy, ks_status *status);
/* The own key (0 for NULL); set_own_key fails for a member's key and,
   with another key, while the group runs. */
void ks_tool_group_own_key(const ks_tool_group *group, int64_t *key,
                           ks_status *status);
void ks_tool_group_set_own_key(ks_tool_group **group, int64_t key,
                               ks_status *status);
/* Tools.Count, Tools.Item (index) and Tools.IndexOf (-1 for a key that
   is not a member). */
void ks_tool_group_count(const ks_tool_group *group, int32_t *count,
                         ks_status *status);
void ks_tool_group_item(const ks_tool_group *group, int32_t index,
                        int64_t *key, ks_status *status);
void ks_tool_group_index_of(const ks_tool_group *group, int64_t key,
                            int32_t *index, ks_status *status);
/* Tools.Add, Tools.Insert (index 0 .. count): the member is enabled. */
void ks_tool_group_add(ks_tool_group **group, int64_t key,
                       ks_status *status);
void ks_tool_group_insert(ks_tool_group **group, int32_t index,
                          int64_t key, ks_status *status);
/* Tools.RemoveAt, Tools.Remove (the index the member had; BAD_PARAMETER
   for a key that is not a member), Tools.Move (the member at from_index
   ends at to_index) and Tools.Clear. */
void ks_tool_group_remove_at(ks_tool_group *group, int32_t index,
                             ks_status *status);
void ks_tool_group_remove(ks_tool_group *group, int64_t key,
                          int32_t *index, ks_status *status);
void ks_tool_group_move(ks_tool_group *group, int32_t from_index,
                        int32_t to_index, ks_status *status);
void ks_tool_group_clear(ks_tool_group *group, ks_status *status);
/* Whether member index is in DisabledTools (0 or 1). */
void ks_tool_group_disabled(const ks_tool_group *group, int32_t index,
                            int32_t *disabled, ks_status *status);
void ks_tool_group_set_disabled(ks_tool_group *group, int32_t index,
                                int32_t disabled, ks_status *status);
/* Member names (for Tools.Item / IndexOf / Contains / Remove (String)):
   each member stores a name (empty until set; at most 256 characters),
   which moves with it. The Ada API sets every member's name from its
   tool's Name before each lookup; a C caller sets them itself. */
void ks_tool_group_set_name(ks_tool_group *group, int32_t index,
                            const ks_tool_text *name, ks_status *status);
void ks_tool_group_name(const ks_tool_group *group, int32_t index,
                        ks_tool_text *name, ks_status *status);
/* The index of the first member named name (case-sensitive),
   KS_TOOL_GROUP_NO_INDEX when there is none (the empty name never
   matches). */
void ks_tool_group_index_of_name(const ks_tool_group *group,
                                 const ks_tool_text *name, int32_t *index,
                                 ks_status *status);
/* The key of the first member named name; KS_FAILURE_BAD_PARAMETER
   ("Tools: no tool named \"x\"") when there is none. */
void ks_tool_group_item_by_name(const ks_tool_group *group,
                                const ks_tool_text *name, int64_t *key,
                                ks_status *status);
/* AbortRunOnToolFailure (0 or 1; 0 by default). */
void ks_tool_group_abort_run_on_tool_failure(const ks_tool_group *group,
                                             int32_t *value,
                                             ks_status *status);
void ks_tool_group_set_abort_run_on_tool_failure(ks_tool_group **group,
                                                 int32_t value,
                                                 ks_status *status);

/* ------------------------------------------------------------------ */
/* Runs                                                                */
/* ------------------------------------------------------------------ */

void ks_tool_group_run_begin(ks_tool_group **group, int32_t script_result,
                             const ks_tool_text *script_message,
                             int32_t run_tools, ks_tool_group_cursor *cursor,
                             ks_status *status);
void ks_tool_group_run_next(const ks_tool_group *group,
                            ks_tool_group_cursor *cursor, int32_t *index,
                            int32_t *more, ks_status *status);
void ks_tool_group_run_report(const ks_tool_group *group,
                              ks_tool_group_cursor *cursor, int32_t index,
                              int32_t result, const ks_tool_text *name,
                              const ks_tool_text *message,
                              ks_status *status);
void ks_tool_group_run_end(ks_tool_group *group,
                           ks_tool_group_cursor *cursor, int32_t *result,
                           int32_t *first_failure, ks_tool_text *message,
                           ks_status *status);

/* CogToolGroup.RunTool, the decisions (a script runs one tool):
   run_tool_begin sets *run to 0 when key is a member of the group in
   DisabledTools (the tool does not run), 1 otherwise (also for a tool
   that is not a member). After the tool ran with sub_result,
   run_tool_end makes *result the worse of *result and sub_result
   (Error > Reject > Warning > Accept), sets *replace to 1 when
   sub_result is strictly worse (take the tool's message too) and
   *abort_run to 1 when sub_result is KS_TOOL_RESULT_ERROR and the group
   has AbortRunOnToolFailure (RunTool then fails). Bad parameter for a
   result code outside -1 .. 2. */
void ks_tool_group_run_tool_begin(const ks_tool_group *group, int64_t key,
                                  int32_t *run, ks_status *status);
void ks_tool_group_run_tool_end(const ks_tool_group *group,
                                int32_t sub_result, int32_t *result,
                                int32_t *replace, int32_t *abort_run,
                                ks_status *status);

/* ------------------------------------------------------------------ */
/* Terminals (CogToolBlockTerminalCollection)                          */
/* ------------------------------------------------------------------ */

void ks_tool_block_terminals_create(ks_tool_block_terminals **terminals,
                                    ks_status *status);
void ks_tool_block_terminals_destroy(ks_tool_block_terminals **terminals);
/* A copy with the same terminals and values (NULL for NULL). */
void ks_tool_block_terminals_duplicate(
    const ks_tool_block_terminals *terminals,
    ks_tool_block_terminals **copy, ks_status *status);
void ks_tool_block_terminals_count(const ks_tool_block_terminals *terminals,
                                   int32_t *count, ks_status *status);
void ks_tool_block_terminals_clear(ks_tool_block_terminals *terminals,
                                   ks_status *status);
/* Add a terminal: of value_type with the default value (0.0, 0, 0, "",
   no value for an object type), with an initial scalar value, or of an
   object type with a value (the caller stores it at index count - 1).
   Insert adds one of value_type with the default value at index
   (0 .. count). These create the collection when *terminals is NULL. */
void ks_tool_block_terminals_add(ks_tool_block_terminals **terminals,
                                 const ks_tool_text *name,
                                 int32_t value_type, ks_status *status);
void ks_tool_block_terminals_add_real(ks_tool_block_terminals **terminals,
                                      const ks_tool_text *name, double value,
                                      ks_status *status);
void ks_tool_block_terminals_add_integer(
    ks_tool_block_terminals **terminals, const ks_tool_text *name,
    int64_t value, ks_status *status);
void ks_tool_block_terminals_add_boolean(
    ks_tool_block_terminals **terminals, const ks_tool_text *name,
    int32_t value, ks_status *status);
void ks_tool_block_terminals_add_string(
    ks_tool_block_terminals **terminals, const ks_tool_text *name,
    const ks_tool_text *value, ks_status *status);
void ks_tool_block_terminals_add_object(
    ks_tool_block_terminals **terminals, const ks_tool_text *name,
    int32_t value_type, ks_status *status);
void ks_tool_block_terminals_insert(ks_tool_block_terminals **terminals,
                                    int32_t index, const ks_tool_text *name,
                                    int32_t value_type, ks_status *status);
/* RemoveAt, Remove (name; the index it had) and Move. */
void ks_tool_block_terminals_remove_at(ks_tool_block_terminals *terminals,
                                       int32_t index, ks_status *status);
void ks_tool_block_terminals_remove(ks_tool_block_terminals *terminals,
                                    const ks_tool_text *name, int32_t *index,
                                    ks_status *status);
void ks_tool_block_terminals_move(ks_tool_block_terminals *terminals,
                                  int32_t from_index, int32_t to_index,
                                  ks_status *status);
/* IndexOf (name): -1 when no terminal is so named. Item [index].Name,
   Item [name].ValueType, and whether the terminal has a value. */
void ks_tool_block_terminals_index_of(
    const ks_tool_block_terminals *terminals, const ks_tool_text *name,
    int32_t *index, ks_status *status);
void ks_tool_block_terminals_name(const ks_tool_block_terminals *terminals,
                                  int32_t index, ks_tool_text *name,
                                  ks_status *status);
void ks_tool_block_terminals_value_type(
    const ks_tool_block_terminals *terminals, const ks_tool_text *name,
    int32_t *value_type, ks_status *status);
void ks_tool_block_terminals_has_value(
    const ks_tool_block_terminals *terminals, const ks_tool_text *name,
    int32_t *has_value, ks_status *status);
/* Item [name].Value of the scalar types. */
void ks_tool_block_terminals_set_real(ks_tool_block_terminals *terminals,
                                      const ks_tool_text *name, double value,
                                      ks_status *status);
void ks_tool_block_terminals_get_real(
    const ks_tool_block_terminals *terminals, const ks_tool_text *name,
    double *value, ks_status *status);
void ks_tool_block_terminals_set_integer(ks_tool_block_terminals *terminals,
                                         const ks_tool_text *name,
                                         int64_t value, ks_status *status);
void ks_tool_block_terminals_get_integer(
    const ks_tool_block_terminals *terminals, const ks_tool_text *name,
    int64_t *value, ks_status *status);
void ks_tool_block_terminals_set_boolean(ks_tool_block_terminals *terminals,
                                         const ks_tool_text *name,
                                         int32_t value, ks_status *status);
void ks_tool_block_terminals_get_boolean(
    const ks_tool_block_terminals *terminals, const ks_tool_text *name,
    int32_t *value, ks_status *status);
void ks_tool_block_terminals_set_string(ks_tool_block_terminals *terminals,
                                        const ks_tool_text *name,
                                        const ks_tool_text *value,
                                        ks_status *status);
void ks_tool_block_terminals_get_string(
    const ks_tool_block_terminals *terminals, const ks_tool_text *name,
    ks_tool_text *value, ks_status *status);
/* Object values: set_object checks that the terminal exists with the
   object type value_type and marks it as having a value, get_object
   checks that it has one; both return the index where the caller keeps
   the object. */
void ks_tool_block_terminals_set_object(ks_tool_block_terminals *terminals,
                                        const ks_tool_text *name,
                                        int32_t value_type, int32_t *index,
                                        ks_status *status);
void ks_tool_block_terminals_get_object(
    const ks_tool_block_terminals *terminals, const ks_tool_text *name,
    int32_t value_type, int32_t *index, ks_status *status);

#ifdef __cplusplus
}
#endif

#endif /* AMV_TOOL_GROUP_H */
