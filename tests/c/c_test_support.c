/* Helpers shared by the C API tests (c_test_support.h). */

#include <stdio.h>
#include <string.h>

#include "c_test_support.h"

int c_test_checks = 0;
int c_test_failures = 0;

void check(int condition, const char *description)
{
    c_test_checks++;
    if (!condition) {
        c_test_failures++;
        printf("FAIL %s\n", description);
    }
}

int is_failure(const ks_status *s, int32_t code, const char *message)
{
    return s->failure == code
        && s->length == (int32_t)strlen(message)
        && strcmp(s->message, message) == 0;
}

ks_space_name space_name(const char *text)
{
    ks_space_name name;
    size_t length = strlen(text);

    memset(&name, 0, sizeof name);
    name.length = (int32_t)length;
    memcpy(name.text, text,
           length < KS_MAX_SPACE_NAME_LENGTH ? length
                                             : KS_MAX_SPACE_NAME_LENGTH);
    return name;
}

int has_name(const ks_space_name *name, const char *text)
{
    size_t length = strlen(text);

    return name->length == (int32_t)length
        && memcmp(name->text, text, length) == 0
        && (length == KS_MAX_SPACE_NAME_LENGTH || name->text[length] == '\0');
}
