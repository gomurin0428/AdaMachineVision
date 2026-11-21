#!/usr/bin/env python3
import argparse
import hashlib
import json
import pathlib
import sys


PARTS = (
    "logical",
    "arithmetic",
    "conditions",
    "numbers",
    "statements",
    "conjuncts",
    "assertions",
)
SHARD_THRESHOLD = 30


def _body(file):
    name = pathlib.PurePosixPath(file).name
    unit = name[:-4] if name.endswith(".adb") else name
    body_key = hashlib.sha256(file.encode()).hexdigest()[:16]
    return {"file": file, "unit": unit, "body_key": body_key}


def plan(numstat, whole=False):
    changed = []
    seen = set()
    for line in numstat.splitlines():
        if not line:
            continue
        fields = line.split("\t", 2)
        if len(fields) != 3:
            raise ValueError(f"expected git numstat fields, got: {line!r}")
        added, _deleted, file = fields
        if added == "-":
            continue
        try:
            added_lines = int(added)
        except ValueError as error:
            raise ValueError(f"invalid added-line count in {line!r}") from error
        if added_lines <= 0 or file in seen:
            continue
        seen.add(file)
        changed.append((_body(file), added_lines))

    jobs = []
    bodies = []
    for body, added_lines in changed:
        bodies.append(body)
        parts = PARTS if added_lines > SHARD_THRESHOLD else ("all",)
        jobs.extend({**body, "part": part} for part in parts)

    return {
        "jobs": jobs,
        "bodies": bodies,
        "whole": whole,
        "has_mutations": bool(jobs),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--whole", action="store_true")
    args = parser.parse_args()
    try:
        result = plan(sys.stdin.read(), whole=args.whole)
    except ValueError as error:
        print(error, file=sys.stderr)
        return 2
    for name, value in result.items():
        if isinstance(value, bool):
            rendered = str(value).lower()
        else:
            rendered = json.dumps(value, separators=(",", ":"))
        print(f"{name}={rendered}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
