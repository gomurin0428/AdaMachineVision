#!/usr/bin/env python3
"""Reject unproved Lean escape hatches and audit proof dependencies."""

from pathlib import Path
from collections import Counter
import re
import subprocess
import sys


PROJECT_DIR = Path(__file__).resolve().parents[1]
LEAN_ROOTS = (PROJECT_DIR / "CameraLifecycle",)
EXPECTED_PROOFS = (
    "camera_result_agrees",
    "camera_result_pre_agrees",
    "open_status_agrees",
    "open_state_agrees",
    "start_status_agrees",
    "start_state_agrees",
    "stop_status_agrees",
    "stop_state_agrees",
    "is_open_agrees",
    "is_streaming_agrees",
    "open_relation_agrees",
    "start_relation_agrees",
    "stop_relation_agrees",
    "close_relation_agrees",
    "is_open_relation_agrees",
    "is_streaming_relation_agrees",
    "open_status_camera_result_calls_respect_pre",
    "start_status_camera_result_calls_respect_pre",
    "stop_status_camera_result_calls_respect_pre",
    "Grab.valid_observation_agrees",
    "Grab.positive_int_to_nat",
    "Grab.int_ofNat_lt_toNat",
    "Grab.int_ofNat_le_toNat",
    "Grab.int_ofNat_lt_decide_ge_false",
    "Grab.nat_sub_zero_of_le",
    "Grab.int_ofNat_le_ofNat",
    "Grab.bool_eq_false_of_not_true",
    "Grab.bool_and_eq_true_components",
    "Grab.bool_or_eq_false_components",
    "Grab.int_beq_true_eq",
    "Grab.nat_bne_false_eq",
    "Grab.nat_bne_eq_false_of_eq",
    "Grab.int_bne_false_eq",
    "Grab.grab_status_success_guards",
    "Grab.grab_status_success_bytes",
    "Grab.one_sub_succ_zero",
    "Grab.int_ofNat_succ_sub_one",
    "Grab.byte_last_from_length",
    "Grab.valid_image_range_bounds",
    "Grab.valid_image_agrees",
    "Grab.grab_status_agrees",
    "Grab.pixel_at_agrees",
    "Grab.grab_pre_agrees",
    "Grab.grab_post_agrees",
    "Grab.build_frame_post_agrees",
    "Grab.grab_relation_agrees",
    "Grab.build_frame_relation_agrees",
    "Grab.empty_observation_validity_matches_nullness",
    "Grab.pixel_at_null_bytes_returns_zero",
    "Grab.pixel_at_reads_byte_content",
    "Grab.successful_pixel_reads_byte",
    "Grab.grab_success_pixel_reads_row_major_byte",
    "Grab.build_frame_success_pixel_reads_row_major_byte",
    "Grab.grab_failure_returns_null",
    "Grab.build_frame_failure_returns_null",
)
FORBIDDEN = re.compile(r"\b(?:sorry|admit|native_decide|axiom)\b", re.IGNORECASE)
AUDIT_LINE = re.compile(
    r"'([^']+)' (does not depend on any axioms|depends on axioms:.*)$",
    re.MULTILINE,
)


def validate_audit_output(output: str) -> tuple[bool, str]:
    results = AUDIT_LINE.findall(output)
    expected = [f"CameraLifecycle.{name}" for name in EXPECTED_PROOFS]
    actual = [name for name, _ in results]
    if Counter(actual) != Counter(expected):
        return False, "axiom audit theorem names do not match the expected list exactly once"
    if any(result != "does not depend on any axioms" for _, result in results):
        return False, "proof theorem depends on axioms"
    return True, f"axiom audit: {len(expected)} theorems have no axioms"


def main() -> int:
    lean_files = sorted(path for root in LEAN_ROOTS for path in root.rglob("*.lean"))
    for path in lean_files:
        source = path.read_text(encoding="utf-8")
        if FORBIDDEN.search(source):
            print(f"forbidden proof escape hatch in {path}", file=sys.stderr)
            return 1

    result = subprocess.run(
        ["lake", "env", "lean", "CameraLifecycle/ProofAudit.lean"],
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    print(result.stdout, end="")
    if result.returncode != 0:
        return result.returncode
    valid, message = validate_audit_output(result.stdout)
    if not valid:
        print(message, file=sys.stderr)
        return 1
    print(message)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
