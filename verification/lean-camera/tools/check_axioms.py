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
    "Grab.compiler_int64_bounds_of_nat",
    "Grab.compiler_int64_bounds_of_neg_succ",
    "Grab.compiler_int64_bounds_of_sub_nat_nat",
    "Grab.compiler_neg_succ_width_bound",
    "Grab.compiler_positive_row_expr",
    "Grab.compiler_negative_product_expr",
    "Grab.compiler_sub_nat_nat_zero",
    "Grab.compiler_int_ofNat_zero_add",
    "Grab.compiler_negative_row_expr",
    "Grab.compiler_bounds_of_equal",
    "Grab.compiler_row_ranges",
    "Grab.checkedValue_ok",
    "Grab.evalScalar_cast_ok",
    "Grab.evalScalar_add_ok",
    "Grab.evalScalar_mul_ok",
    "Grab.compiler_int64_contains_natural",
    "Grab.compiler_int64_contains_width",
    "Grab.compiler_widened_row_eval",
    "Grab.compiler_evalPredicate_inRange_ok",
    "Grab.compiler_evalPredicate_not_ok",
    "Grab.compiler_evalPredicate_equal_ok",
    "Grab.compiler_decide_true",
    "Grab.compiler_decide_false",
    "Grab.compiler_int_ofNat_le_decide_true",
    "Grab.compiler_int_ofNat_le_decide_false",
    "Grab.compiler_ofNat_lt",
    "Grab.compiler_int_ofNat_lt_decide_true",
    "Grab.compiler_int_ofNat_lt_decide_false",
    "Grab.compiler_ofNat_succ_lt",
    "Grab.compiler_neg_succ_add_one",
    "Grab.compiler_zero_sub_negOfNat",
    "Grab.compiler_neg_succ_lt_zero",
    "Grab.compiler_ofNat_not_lt_negSucc",
    "Grab.compiler_generated_finish_predicates_match",
    "Grab.compiler_nat_failure_eval",
    "Grab.compiler_overflow_failure_eval",
    "Grab.compiler_index_value_eval",
    "Grab.compiler_index_backend_cast_safe",
    "Grab.compiler_array_failure_eval",
    "Grab.compiler_nat_failure_negative",
    "Grab.compiler_nat_failure_above_max",
    "Grab.compiler_nat_failure_within_max",
    "Grab.compiler_integer_cast_fits_natural",
    "Grab.compiler_overflow_failure_at_max",
    "Grab.compiler_overflow_failure_below_max",
    "Grab.compiler_finish_negative",
    "Grab.compiler_finish_above_max",
    "Grab.compiler_finish_at_max",
    "Grab.compiler_finish_model_below_max",
    "Grab.compiler_finish_below_max",
    "Grab.compiler_finish_predicates_equiv",
    "Grab.compiler_row0_matches_mathematics",
    "Grab.compiler_row1_matches_mathematics",
    "Grab.compiler_ir_index_matches_mathematics",
    "Grab.compiler_index_negative_row_is_range",
    "Grab.compiler_index_zero_row_reads_lower_bound",
    "Grab.compiler_index_natural_last_overflows_increment",
    "Grab.compiler_index_too_large_row_is_range",
    "Grab.compiler_index_upper_bound_succeeds",
    "Grab.compiler_index_outside_upper_bound_fails",
    "Grab.compiler_index_null_range_fails",
    "Grab.compiler_positive_conversion_has_no_independent_failure",
    "Grab.compiler_row_copies_agree",
    "Grab.compiler_index_natural_max_minus_one_succeeds",
    "Grab.compiler_widened_row_max_coordinates_width_edges",
    "Grab.compiler_widened_row_zero_coordinates_width_edges",
    "Grab.compiler_model_early_guard_returns_zero",
    "Grab.compiler_model_invalid_coordinates_return_zero",
    "Grab.compiler_model_row_outside_byte_count_returns_zero",
    "Grab.compiler_pixel_read_branch_avoids_index_failures",
    "Grab.compiler_frame_size_bounds_resolved",
    "Grab.compiler_frame_size_enum_mapping",
    "Grab.compiler_frame_size_program_order",
    "Grab.checkedFrameSizeValue_ok",
    "Grab.int32_product_fits_int64",
    "Grab.compiler_frame_product_all_int32",
    "Grab.unsigned64_cast_failure_exact",
    "Grab.compiler_byte_count_to_int64_safe",
    "Grab.compiler_frame_product_unsigned64_cast",
    "Grab.compiler_source_size_unsigned64_identity",
    "Grab.compiler_int32_max_squared_fits_int64",
    "Grab.compiler_int32_minimum_squared_fits_int64",
    "Grab.compiler_frame_size_size_cast_ok",
    "Grab.compiler_frame_size_subtract_ok",
    "Grab.compiler_frame_size_add_ok",
    "Grab.compiler_frame_array_length_present",
    "Grab.compiler_frame_array_length_null_access_fails",
    "Grab.compiler_frame_size_dimensions_eval",
    "Grab.compiler_frame_size_limit_eval",
    "Grab.compiler_frame_size_check_false_ok",
    "Grab.compiler_frame_size_sequence_predicate_ok",
    "Grab.compiler_frame_size_or_else_ok",
    "Grab.compiler_frame_size_or_else_true_left",
    "Grab.compiler_frame_size_invalid_length_eval",
    "Grab.compiler_frame_size_suffix_agrees",
    "Grab.compiler_frame_size_suffix_failure_free",
    "Grab.compiler_frame_size_bridge_to_grab_status_prefix",
    "Grab.compiler_frame_size_success_at_strict_maximum",
    "Grab.compiler_frame_size_strict_maximum_plus_one_is_too_large",
    "Grab.compiler_frame_size_int32_minimum_is_invalid_dimensions",
    "Grab.compiler_frame_size_zero_dimension_is_invalid_dimensions",
    "Grab.compiler_frame_size_unsigned64_max_source_size_is_invalid_length",
    "Grab.compiler_frame_size_short_byte_view_is_invalid_length",
    "Grab.compiler_frame_size_long_byte_view_is_invalid_length",
    "Grab.compiler_frame_size_zero_byte_view_is_invalid_length",
    "Grab.compiler_frame_size_absent_byte_view_is_invalid_length",
    "Grab.compiler_frame_size_non_one_first_bound_is_invalid_length",
    "Grab.compiler_frame_size_reversed_byte_bounds_are_invalid_length",
    "Grab.compiler_frame_size_inconsistent_source_count_is_invalid_length",
    "Grab.compiler_frame_size_inconsistent_byte_count_is_invalid_length",
    "Grab.compiler_frame_size_exact_size_success",
    "Grab.frame_size_success_at_strict_maximum",
    "Grab.frame_size_strict_maximum_plus_one_is_too_large",
    "Grab.frame_size_int32_minimum_is_invalid_dimensions",
    "Grab.frame_size_zero_dimension_is_invalid_dimensions",
    "Grab.frame_size_unsigned64_max_source_size_is_invalid_length",
    "Grab.frame_size_short_byte_view_is_invalid_length",
    "Grab.frame_size_long_byte_view_is_invalid_length",
    "Grab.frame_size_zero_byte_view_is_invalid_length",
    "Grab.frame_size_absent_byte_view_is_invalid_length",
    "Grab.frame_size_non_one_first_bound_is_invalid_length",
    "Grab.frame_size_reversed_byte_bounds_are_invalid_length",
    "Grab.frame_size_inconsistent_source_count_is_invalid_length",
    "Grab.frame_size_inconsistent_byte_count_is_invalid_length",
    "Grab.frame_size_exact_size_success",
    "Grab.frame_size_bridge_to_grab_status_prefix",
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
