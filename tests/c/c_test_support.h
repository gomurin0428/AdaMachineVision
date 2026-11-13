/*
 * Helpers shared by the C API tests: the check counters and the
 * comparisons of statuses and space names. test_c_api.c holds main; each
 * tool's tests live in test_c_<tool>.c as a function test_c_<tool>(void)
 * that main calls (docs/handoff/TOOLS_PLAN.md, "Tools as SPARK kernels").
 */

#ifndef C_TEST_SUPPORT_H
#define C_TEST_SUPPORT_H

#include <stdint.h>

#include "amv.h"

/* The number of checks made and of those that failed. */
extern int c_test_checks;
extern int c_test_failures;

/* Counts a check; prints "FAIL <description>" when condition is 0. */
void check(int condition, const char *description);

/* 1 when the status holds the failure code and exactly the message. */
int is_failure(const ks_status *s, int32_t code, const char *message);

/* A ks_space_name holding text (at most KS_MAX_SPACE_NAME_LENGTH
   characters are copied; the length tells longer names apart). */
ks_space_name space_name(const char *text);

/* 1 when the name holds exactly text. */
int has_name(const ks_space_name *name, const char *text);

#endif /* C_TEST_SUPPORT_H */
