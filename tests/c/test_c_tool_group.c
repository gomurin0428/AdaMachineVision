/*
 * Tests of the tool group C API (include/amv_tool_group.h): the member
 * list, runs over a few fake members (plain C functions that return a
 * result code), abort on failure, disabled members, the result and
 * message of a run, misuse of the cursor, and the terminal table of a
 * tool block; NULL handles and bad codes included.
 */

#include <math.h>
#include <stdio.h>
#include <string.h>

#include "amv.h"
#include "c_test_support.h"

void test_c_tool_group(void);

static ks_tool_text text(const char *s)
{
    ks_tool_text t;
    size_t length = strlen(s);

    memset(&t, 0, sizeof t);
    t.length = (int32_t)length;
    memcpy(t.text, s,
           length < KS_TOOL_TEXT_MAX_LENGTH ? length : KS_TOOL_TEXT_MAX_LENGTH);
    return t;
}

static int has_text(const ks_tool_text *t, const char *s)
{
    size_t length = strlen(s);

    return t->length == (int32_t)length && memcmp(t->text, s, length) == 0
        && (length == KS_TOOL_TEXT_MAX_LENGTH || t->text[length] == '\0');
}

/* The fake members: key k returns results[k]; the order they ran in is
   recorded in ran[]. */
static const int32_t results[6] = {
    KS_TOOL_RESULT_ACCEPT, KS_TOOL_RESULT_WARNING, KS_TOOL_RESULT_REJECT,
    KS_TOOL_RESULT_ERROR, KS_TOOL_RESULT_ACCEPT, KS_TOOL_RESULT_ACCEPT};
static const char *const names[6] = {"zero", "one", "", "three", "four",
                                     "five"};
static int64_t ran[16];
static int ran_count;

/* Runs every member the group offers; returns the run's status. */
static ks_status run(ks_tool_group **group, int32_t script_result,
                     const char *script_message, int32_t run_tools,
                     int32_t *result, int32_t *first, ks_tool_text *message)
{
    ks_status status, ignored;
    ks_tool_group_cursor cursor;
    ks_tool_text script = text(script_message);
    int32_t index = -2, more = 0;
    int64_t key = -1;

    ran_count = 0;
    ks_tool_group_run_begin(group, script_result, &script, run_tools,
                            &cursor, &status);
    if (status.failure != KS_FAILURE_NONE)
        return status;
    for (;;) {
        ks_tool_group_run_next(*group, &cursor, &index, &more, &ignored);
        if (!more)
            break;
        ks_tool_group_item(*group, index, &key, &ignored);
        if (ran_count < 16)
            ran[ran_count++] = key;
        {
            ks_tool_text name = text(names[key]);
            ks_tool_text member_message =
                text(results[key] == KS_TOOL_RESULT_ACCEPT ? "" : "bad");
            ks_tool_group_run_report(*group, &cursor, index, results[key],
                                     &name, &member_message, &ignored);
        }
    }
    ks_tool_group_run_end(*group, &cursor, result, first, message, &status);
    return status;
}

static void test_members(void)
{
    ks_status status;
    ks_tool_group *group = NULL, *copy = NULL;
    int32_t count = -1, index = -2, flag = -1;
    int64_t key = -1;

    /* NULL is an empty group. */
    ks_tool_group_count(NULL, &count, &status);
    check(status.failure == KS_FAILURE_NONE && count == 0,
          "group: NULL has no member");
    ks_tool_group_item(NULL, 0, &key, &status);
    check(status.failure == KS_FAILURE_INDEX_OUT_OF_RANGE && key == 0,
          "group: item of NULL");
    ks_tool_group_index_of(NULL, 5, &index, &status);
    check(status.failure == KS_FAILURE_NONE
              && index == KS_TOOL_GROUP_NO_INDEX,
          "group: index_of in NULL");
    ks_tool_group_abort_run_on_tool_failure(NULL, &flag, &status);
    check(status.failure == KS_FAILURE_NONE && flag == 0,
          "group: abort flag of NULL is 0");

    /* Add creates the group (own key 0, so key 0 is the group itself). */
    ks_tool_group_add(&group, 0, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Tools.Add: a group cannot contain itself")
              && group == NULL,
          "group: the own key is rejected");
    ks_tool_group_set_own_key(&group, 100, &status);
    check(status.failure == KS_FAILURE_NONE && group != NULL,
          "group: set_own_key creates");
    ks_tool_group_add(&group, 0, &status);
    ks_tool_group_add(&group, 1, &status);
    ks_tool_group_add(&group, 3, &status);
    check(status.failure == KS_FAILURE_NONE, "group: add");
    ks_tool_group_insert(&group, 2, 2, &status);
    check(status.failure == KS_FAILURE_NONE, "group: insert");
    ks_tool_group_add(&group, 1, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Tools.Add: the tool is a member of the group already"),
          "group: a duplicate is rejected");
    ks_tool_group_add(&group, 100, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER,
          "group: the group itself is rejected");
    ks_tool_group_insert(&group, 5, 9, &status);
    check(status.failure == KS_FAILURE_INDEX_OUT_OF_RANGE,
          "group: insert beyond count");
    ks_tool_group_set_own_key(&group, 2, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER,
          "group: the own key may not be a member's");

    ks_tool_group_count(group, &count, &status);
    check(count == 4, "group: count 4");
    ks_tool_group_item(group, 2, &key, &status);
    check(status.failure == KS_FAILURE_NONE && key == 2, "group: item 2");
    ks_tool_group_index_of(group, 3, &index, &status);
    check(index == 3, "group: index_of 3");

    /* Move, remove, remove_at. */
    ks_tool_group_move(group, 0, 3, &status);
    ks_tool_group_item(group, 3, &key, &status);
    check(key == 0, "group: move 0 -> 3");
    ks_tool_group_item(group, 0, &key, &status);
    check(key == 1, "group: move shifts the others down");
    ks_tool_group_move(group, 3, 0, &status);
    ks_tool_group_item(group, 0, &key, &status);
    check(key == 0, "group: move back");
    ks_tool_group_move(group, 0, 4, &status);
    check(status.failure == KS_FAILURE_INDEX_OUT_OF_RANGE,
          "group: move beyond count");
    ks_tool_group_remove(group, 9, &index, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER
              && index == KS_TOOL_GROUP_NO_INDEX,
          "group: remove of a non-member");

    /* Flags. */
    ks_tool_group_set_disabled(group, 1, 1, &status);
    ks_tool_group_disabled(group, 1, &flag, &status);
    check(status.failure == KS_FAILURE_NONE && flag == 1,
          "group: disabled flag");
    ks_tool_group_set_disabled(group, 1, 2, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER, "group: bad flag");
    ks_tool_group_set_disabled(group, 1, 0, &status);

    /* Names: stored per member, they move with it. */
    {
        ks_tool_text name, long_name, t;
        int64_t first_key = -1;

        ks_tool_group_item(group, 0, &first_key, &status);
        t = text("first");
        ks_tool_group_set_name(group, 0, &t, &status);
        check(status.failure == KS_FAILURE_NONE, "group: set_name");
        t = text("third");
        ks_tool_group_set_name(group, 2, &t, &status);
        ks_tool_group_index_of_name(group, &t, &index, &status);
        check(status.failure == KS_FAILURE_NONE && index == 2,
              "group: index_of_name");
        t = text("Third");
        ks_tool_group_index_of_name(group, &t, &index, &status);
        check(index == KS_TOOL_GROUP_NO_INDEX,
              "group: names are case-sensitive");
        t = text("");
        ks_tool_group_index_of_name(group, &t, &index, &status);
        check(index == KS_TOOL_GROUP_NO_INDEX,
              "group: the empty name never matches");
        t = text("first");
        ks_tool_group_item_by_name(group, &t, &key, &status);
        check(status.failure == KS_FAILURE_NONE && key == first_key,
              "group: item_by_name");
        t = text("none");
        ks_tool_group_item_by_name(group, &t, &key, &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "Tools: no tool named \"none\"")
                  && key == 0,
              "group: item_by_name of an unknown name");
        ks_tool_group_name(group, 0, &name, &status);
        check(status.failure == KS_FAILURE_NONE && has_text(&name, "first"),
              "group: name");
        ks_tool_group_name(group, 9, &name, &status);
        check(status.failure == KS_FAILURE_INDEX_OUT_OF_RANGE
                  && name.length == 0,
              "group: name beyond count");
        memset(&long_name, 'n', sizeof long_name);
        long_name.length = 257;
        ks_tool_group_set_name(group, 1, &long_name, &status);
        check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                         "a tool name must be at most 256 characters"),
              "group: a name of 257 characters");
        t = text("x");
        ks_tool_group_set_name(group, 9, &t, &status);
        check(status.failure == KS_FAILURE_INDEX_OUT_OF_RANGE,
              "group: set_name beyond count");
        ks_tool_group_move(group, 0, 3, &status);
        t = text("first");
        ks_tool_group_index_of_name(group, &t, &index, &status);
        check(index == 3, "group: a name moves with its member");
        ks_tool_group_move(group, 3, 0, &status);
    }
    ks_tool_group_set_abort_run_on_tool_failure(&group, 7, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER,
          "group: bad abort flag");

    /* A duplicate is independent. */
    ks_tool_group_duplicate(group, &copy, &status);
    check(status.failure == KS_FAILURE_NONE && copy != NULL,
          "group: duplicate");
    ks_tool_group_remove_at(copy, 0, &status);
    ks_tool_group_count(copy, &count, &status);
    check(count == 3, "group: the copy changed");
    ks_tool_group_count(group, &count, &status);
    check(count == 4, "group: the original did not");
    ks_tool_group_own_key(copy, &key, &status);
    check(key == 100, "group: the copy has the own key");
    ks_tool_group_destroy(&copy);
    check(copy == NULL, "group: destroy");

    ks_tool_group_clear(group, &status);
    ks_tool_group_count(group, &count, &status);
    check(count == 0, "group: clear");
    ks_tool_group_destroy(&group);
    ks_tool_group_destroy(&group);
    check(group == NULL, "group: destroy twice");
}

static void test_runs(void)
{
    ks_status status;
    ks_tool_group *group = NULL;
    ks_tool_group_cursor cursor, other;
    ks_tool_text message, empty = text("");
    int32_t result = 99, first = 99, index, more;
    int64_t key;

    ks_tool_group_create(-1, &group, &status);
    for (key = 0; key < 6; key++)
        ks_tool_group_add(&group, key, &status);

    /* Every member runs, in order; the worst result and the first that
       did not accept. */
    status = run(&group, KS_TOOL_RESULT_ACCEPT, "", 1, &result, &first,
                 &message);
    check(status.failure == KS_FAILURE_NONE && ran_count == 6
              && ran[0] == 0 && ran[5] == 5,
          "run: every member in order");
    check(result == KS_TOOL_RESULT_ERROR && first == 1,
          "run: worst result and first failure");
    check(has_text(&message, "one: bad"), "run: the message");

    /* Abort on failure stops after the Error (member 3). */
    ks_tool_group_set_abort_run_on_tool_failure(&group, 1, &status);
    status = run(&group, KS_TOOL_RESULT_ACCEPT, "", 1, &result, &first,
                 &message);
    check(status.failure == KS_FAILURE_NONE && ran_count == 4
              && ran[3] == 3,
          "run: abort after the error");
    ks_tool_group_set_abort_run_on_tool_failure(&group, 0, &status);

    /* Disabled members are skipped; a member without a name. */
    ks_tool_group_set_disabled(group, 1, 1, &status);
    ks_tool_group_set_disabled(group, 3, 1, &status);
    status = run(&group, KS_TOOL_RESULT_ACCEPT, "", 1, &result, &first,
                 &message);
    check(status.failure == KS_FAILURE_NONE && ran_count == 4
              && ran[0] == 0 && ran[1] == 2 && ran[2] == 4 && ran[3] == 5,
          "run: disabled members are skipped");
    check(result == KS_TOOL_RESULT_REJECT && first == 2
              && has_text(&message, "tool 2: bad"),
          "run: a member without a name");

    /* The script's result and message, and run_tools 0. */
    status = run(&group, KS_TOOL_RESULT_WARNING, "script note", 0, &result,
                 &first, &message);
    check(status.failure == KS_FAILURE_NONE && ran_count == 0
              && result == KS_TOOL_RESULT_WARNING
              && first == KS_TOOL_GROUP_NO_INDEX
              && has_text(&message, "script note"),
          "run: the script alone");
    status = run(&group, KS_TOOL_RESULT_WARNING, "script note", 1, &result,
                 &first, &message);
    check(result == KS_TOOL_RESULT_REJECT
              && has_text(&message, "script note; tool 2: bad"),
          "run: the script and the members");

    /* Misuse. */
    ks_tool_group_run_begin(&group, 5, &empty, 1, &cursor, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Run: the script's result must be a "
                     "CogToolResultConstants code (-1 .. 2)"),
          "run: bad script result");
    ks_tool_group_run_begin(&group, 0, &empty, 2, &cursor, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER, "run: bad run_tools");
    ks_tool_group_run_begin(&group, 0, &empty, 1, &cursor, &status);
    check(status.failure == KS_FAILURE_NONE, "run: begin");
    ks_tool_group_run_begin(&group, 0, &empty, 1, &other, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Run: the group is running already (a group cannot "
                     "contain itself, directly or through other groups)"),
          "run: a group runs once at a time");
    ks_tool_group_run_next(group, &cursor, &index, &more, &status);
    check(status.failure == KS_FAILURE_NONE && more == 1 && index == 0,
          "run: next");
    ks_tool_group_run_next(group, &cursor, &index, &more, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER && more == 0
              && cursor.fault == KS_TOOL_GROUP_FAULT_MISUSE,
          "run: next before the report");
    ks_tool_group_run_end(group, &cursor, &result, &first, &message,
                          &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Run: a call of this run failed")
              && result == KS_TOOL_RESULT_ERROR && message.length == 0,
          "run: end reports the failure");
    ks_tool_group_run_end(group, &cursor, &result, &first, &message,
                          &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER,
          "run: the cursor of an ended run");

    /* A change during the run. */
    ks_tool_group_run_begin(&group, 0, &empty, 1, &cursor, &status);
    ks_tool_group_run_next(group, &cursor, &index, &more, &status);
    ks_tool_group_set_disabled(group, 5, 1, &status);
    {
        ks_tool_text name = text("zero");
        ks_tool_group_run_report(group, &cursor, 0, KS_TOOL_RESULT_ACCEPT,
                                 &name, &empty, &status);
    }
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Run: the group changed while it ran")
              && cursor.fault == KS_TOOL_GROUP_FAULT_CHANGED,
          "run: a change makes the cursor stale");
    ks_tool_group_run_end(group, &cursor, &result, &first, &message,
                          &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER,
          "run: end after a change");
    ks_tool_group_run_begin(&group, 0, &empty, 1, &cursor, &status);
    check(status.failure == KS_FAILURE_NONE,
          "run: the group can run again after run_end");

    /* A report of another member, a bad result code. */
    ks_tool_group_run_next(group, &cursor, &index, &more, &status);
    {
        ks_tool_text name = text("x");
        ks_tool_group_run_report(group, &cursor, index + 1,
                                 KS_TOOL_RESULT_ACCEPT, &name, &empty,
                                 &status);
        check(status.failure == KS_FAILURE_BAD_PARAMETER,
              "run: report of a member not offered");
    }
    ks_tool_group_run_end(group, &cursor, &result, &first, &message,
                          &status);
    ks_tool_group_run_next(NULL, &cursor, &index, &more, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER && more == 0,
          "run: next on NULL");

    /* An empty group created by run_begin. */
    {
        ks_tool_group *none = NULL;
        status = run(&none, KS_TOOL_RESULT_ACCEPT, "", 1, &result, &first,
                     &message);
        check(status.failure == KS_FAILURE_NONE && none != NULL
                  && result == KS_TOOL_RESULT_ACCEPT
                  && first == KS_TOOL_GROUP_NO_INDEX && message.length == 0,
              "run: an empty group accepts");
        ks_tool_group_destroy(&none);
    }
    ks_tool_group_destroy(&group);
}

static void test_terminals(void)
{
    ks_status status;
    ks_tool_block_terminals *t = NULL, *copy = NULL;
    ks_tool_text name, value;
    int32_t count = -1, index = -2, type = -1, flag = -1;
    int64_t integer = 0;
    double real = 0.0;

    ks_tool_block_terminals_count(NULL, &count, &status);
    check(status.failure == KS_FAILURE_NONE && count == 0,
          "terminals: NULL is empty");

    name = text("Gain");
    ks_tool_block_terminals_add_real(&t, &name, 2.5, &status);
    check(status.failure == KS_FAILURE_NONE && t != NULL,
          "terminals: add_real creates");
    name = text("Count");
    ks_tool_block_terminals_add_integer(&t, &name, -7, &status);
    name = text("Pass");
    ks_tool_block_terminals_add_boolean(&t, &name, 1, &status);
    name = text("Code");
    value = text("abc");
    ks_tool_block_terminals_add_string(&t, &name, &value, &status);
    name = text("Image");
    ks_tool_block_terminals_add(&t, &name, KS_TOOL_BLOCK_TYPE_IMAGE_8_GREY,
                                &status);
    name = text("Pose");
    ks_tool_block_terminals_insert(&t, 0, &name, KS_TOOL_BLOCK_TYPE_TRANSFORM,
                                   &status);
    ks_tool_block_terminals_count(t, &count, &status);
    check(count == 6, "terminals: count 6");

    name = text("Gain");
    ks_tool_block_terminals_get_real(t, &name, &real, &status);
    check(status.failure == KS_FAILURE_NONE && real == 2.5,
          "terminals: get_real");
    ks_tool_block_terminals_set_real(t, &name, -1.25, &status);
    ks_tool_block_terminals_get_real(t, &name, &real, &status);
    check(real == -1.25, "terminals: set_real");
    ks_tool_block_terminals_set_real(t, &name, NAN, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Value must be finite"),
          "terminals: NaN is rejected");
    ks_tool_block_terminals_get_integer(t, &name, &integer, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Terminal \"Gain\" is of type Real, not Integer")
              && integer == 0,
          "terminals: type mismatch");
    name = text("Count");
    ks_tool_block_terminals_get_integer(t, &name, &integer, &status);
    check(integer == -7, "terminals: get_integer");
    name = text("count");
    ks_tool_block_terminals_get_integer(t, &name, &integer, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "No terminal is named \"count\""),
          "terminals: names are case-sensitive");
    name = text("Code");
    ks_tool_block_terminals_get_string(t, &name, &value, &status);
    check(has_text(&value, "abc"), "terminals: get_string");
    name = text("Pass");
    ks_tool_block_terminals_get_boolean(t, &name, &flag, &status);
    check(flag == 1, "terminals: get_boolean");

    /* Objects. */
    name = text("Image");
    ks_tool_block_terminals_has_value(t, &name, &flag, &status);
    check(status.failure == KS_FAILURE_NONE && flag == 0,
          "terminals: an object without value");
    ks_tool_block_terminals_get_object(t, &name,
                                       KS_TOOL_BLOCK_TYPE_IMAGE_8_GREY,
                                       &index, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Terminal \"Image\" has no value")
              && index == KS_TOOL_GROUP_NO_INDEX,
          "terminals: get_object without a value");
    ks_tool_block_terminals_set_object(t, &name,
                                       KS_TOOL_BLOCK_TYPE_IMAGE_16_GREY,
                                       &index, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER,
          "terminals: set_object of another type");
    ks_tool_block_terminals_set_object(t, &name,
                                       KS_TOOL_BLOCK_TYPE_IMAGE_8_GREY,
                                       &index, &status);
    check(status.failure == KS_FAILURE_NONE && index == 5,
          "terminals: set_object");
    ks_tool_block_terminals_get_object(t, &name,
                                       KS_TOOL_BLOCK_TYPE_IMAGE_8_GREY,
                                       &index, &status);
    check(status.failure == KS_FAILURE_NONE && index == 5,
          "terminals: get_object");
    ks_tool_block_terminals_value_type(t, &name, &type, &status);
    check(type == KS_TOOL_BLOCK_TYPE_IMAGE_8_GREY,
          "terminals: value_type");

    /* Names: duplicates, lengths, order. */
    name = text("Gain");
    ks_tool_block_terminals_add(&t, &name, KS_TOOL_BLOCK_TYPE_REAL, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "A terminal named \"Gain\" exists already"),
          "terminals: duplicate name");
    name = text("");
    ks_tool_block_terminals_add(&t, &name, KS_TOOL_BLOCK_TYPE_REAL, &status);
    check(is_failure(&status, KS_FAILURE_BAD_PARAMETER,
                     "Name must have 1 to 256 characters"),
          "terminals: empty name");
    name = text("X");
    ks_tool_block_terminals_add(&t, &name, 8, &status);
    check(status.failure == KS_FAILURE_BAD_PARAMETER,
          "terminals: bad type code");
    ks_tool_block_terminals_name(t, 0, &name, &status);
    check(has_text(&name, "Pose"), "terminals: name 0");
    ks_tool_block_terminals_move(t, 0, 5, &status);
    ks_tool_block_terminals_name(t, 5, &name, &status);
    check(has_text(&name, "Pose"), "terminals: move");
    name = text("Image");
    ks_tool_block_terminals_index_of(t, &name, &index, &status);
    check(index == 4, "terminals: index after move");
    name = text("Count");
    ks_tool_block_terminals_remove(t, &name, &index, &status);
    check(status.failure == KS_FAILURE_NONE && index == 1,
          "terminals: remove");
    ks_tool_block_terminals_index_of(t, &name, &index, &status);
    check(index == KS_TOOL_GROUP_NO_INDEX, "terminals: removed");
    ks_tool_block_terminals_remove_at(t, 9, &status);
    check(status.failure == KS_FAILURE_INDEX_OUT_OF_RANGE,
          "terminals: remove_at beyond count");

    /* A duplicate is independent. */
    ks_tool_block_terminals_duplicate(t, &copy, &status);
    name = text("Gain");
    ks_tool_block_terminals_set_real(copy, &name, 9.0, &status);
    ks_tool_block_terminals_get_real(t, &name, &real, &status);
    check(real == -1.25, "terminals: the copy is independent");
    ks_tool_block_terminals_destroy(&copy);

    ks_tool_block_terminals_clear(t, &status);
    ks_tool_block_terminals_count(t, &count, &status);
    check(count == 0, "terminals: clear");
    ks_tool_block_terminals_destroy(&t);
    check(t == NULL, "terminals: destroy");
}

void test_c_tool_group(void)
{
    test_members();
    test_runs();
    test_terminals();
}
