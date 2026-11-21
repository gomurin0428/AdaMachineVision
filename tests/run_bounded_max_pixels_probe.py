#!/usr/bin/env python3
"""Run the Max_Pixels boundary probe under a verified Linux address-space cap."""

import os
import sys


ADDRESS_SPACE_LIMIT = 256 * 1024 * 1024
LIMIT_MARKER = "AMV_BOUNDED_PROBE_RLIMIT_AS"


def fail(reason):
    print(f"bounded Max_Pixels probe: {reason}", file=sys.stderr)
    return 2


def main():
    command = sys.argv[1:]
    if not command:
        return fail("missing probe executable")
    if not sys.platform.startswith("linux"):
        return fail("RLIMIT_AS is supported only on Linux")

    try:
        import resource
    except ImportError:
        return fail("Python resource module is unavailable")
    if not hasattr(resource, "RLIMIT_AS"):
        return fail("RLIMIT_AS is unavailable")

    try:
        resource.setrlimit(
            resource.RLIMIT_AS, (ADDRESS_SPACE_LIMIT, ADDRESS_SPACE_LIMIT)
        )
        actual = resource.getrlimit(resource.RLIMIT_AS)
    except (OSError, OverflowError, ValueError) as error:
        return fail(f"could not set and verify RLIMIT_AS: {error}")
    if actual != (ADDRESS_SPACE_LIMIT, ADDRESS_SPACE_LIMIT):
        return fail(f"RLIMIT_AS is {actual}, expected both limits at 256 MiB")

    environment = os.environ.copy()
    environment[LIMIT_MARKER] = str(ADDRESS_SPACE_LIMIT)
    try:
        os.execvpe(command[0], command, environment)
    except OSError as error:
        return fail(f"could not execute probe: {error}")


if __name__ == "__main__":
    sys.exit(main())
