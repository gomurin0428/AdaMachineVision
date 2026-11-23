from __future__ import annotations

import re
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(PROJECT_DIR / "tools"))
import extract_frame_size_compiler as frame_size


SPEC = REPOSITORY_ROOT / "optional/aravis/src/amv-spec-gige_vision.ads"
TYPES = REPOSITORY_ROOT / "optional/aravis/src/amv-gige_vision_types.ads"


def copy_input(directory: Path) -> Path:
    source = directory / SPEC.name
    shutil.copy2(SPEC, source)
    return source


def substitute_once(path: Path, pattern: str, replacement: str) -> None:
    source = path.read_text(encoding="utf-8")
    changed, count = re.subn(pattern, replacement, source, count=1, flags=re.MULTILINE | re.DOTALL)
    if count != 1:
        raise AssertionError(f"expected one source mutation match, got {count}: {pattern}")
    path.write_text(changed, encoding="utf-8")


class FrameSizeCompilerExtractorTests(unittest.TestCase):
    def assertMutationRejected(self, pattern: str, replacement: str, expected: str | None = None) -> None:
        with tempfile.TemporaryDirectory(prefix="frame-size-mutation-") as temp:
            source = copy_input(Path(temp))
            substitute_once(source, pattern, replacement)
            with self.assertRaises(frame_size.ExtractionError) as raised:
                frame_size.extract(source, None)
            message = str(raised.exception)
            self.assertNotIn("command failed", message.lower(), message)
            if expected:
                self.assertIn(expected, message)

    def assertReturnBranchAccessCheckRejected(self, status: str) -> None:
        with tempfile.TemporaryDirectory(prefix="frame-size-status-branch-") as temp:
            directory = Path(temp)
            baseline_diagnostics = directory / "baseline"
            frame_size.extract(SPEC, baseline_diagnostics)
            source = copy_input(directory)
            substitute_once(
                source,
                rf"T\.{status}",
                f"(declare Probe : constant Positive := Frame.Bytes.all'First; begin T.{status})",
            )
            diagnostics = directory / "branch-probe"
            with self.assertRaises(frame_size.ExtractionError) as raised:
                frame_size.extract(source, diagnostics)
            self.assertNotIn("command failed", str(raised.exception).lower())

            def access_checks(path: Path) -> int:
                raw = (path / "amv-spec-gige_vision.ads.006t.original").read_text(encoding="utf-8")
                _, nodes = frame_size.compiler_ir.parse_function_tree_named(raw, "grab_status", "Grab_Status")
                function_ids = [node_id for node_id, node in nodes.items()
                                if node["kind"] == "function_decl"
                                and frame_size.compiler_ir.identifier(
                                    nodes, frame_size.ref(nodes, node_id, "name"))
                                == "amv__spec__gige_vision__grab_status"]
                self.assertEqual(len(function_ids), 1)
                body = frame_size.ref(nodes, function_ids[0], "body")
                return sum(
                    node["kind"] == "call_expr"
                    and frame_size.compiler_ir.check_name(nodes, node_id)
                    == "__gnat_rcheck_CE_Access_Check"
                    for node_id in frame_size.walk_nodes(nodes, body)
                    for node in (nodes[node_id],)
                )

            self.assertGreater(access_checks(diagnostics), access_checks(baseline_diagnostics))

    def test_access_check_in_invalid_dimensions_return_branch_rejected(self) -> None:
        self.assertReturnBranchAccessCheckRejected("Frame_Invalid_Dimensions")

    def test_access_check_in_too_large_return_branch_rejected(self) -> None:
        self.assertReturnBranchAccessCheckRejected("Frame_Too_Large")

    def test_compiler_ir_freshness(self) -> None:
        generated = frame_size.OUTPUT.read_text(encoding="utf-8")
        self.assertEqual(frame_size.extract(SPEC, None), generated)

    def test_spacing_and_line_movement_preserve_semantic_program(self) -> None:
        baseline = frame_size.extract(SPEC, None)
        with tempfile.TemporaryDirectory(prefix="frame-size-format-") as temp:
            source = copy_input(Path(temp))
            substitute_once(
                source,
                r"T\.Int64\s*\(\s*Frame\.Width\s*\)\s*\*\s*T\.Int64\s*\(\s*Frame\.Height\s*\)",
                "T.Int64 (Frame.Width) *\n       T.Int64 (Frame.Height)",
            )
            source.write_text("\n" + source.read_text(encoding="utf-8"), encoding="utf-8")
            formatted = frame_size.extract(source, None)
        start = "def compilerFrameSizeProgram"
        end = "def compilerFrameSizeBounds"
        self.assertEqual(baseline[baseline.index(start):baseline.index(end)],
                         formatted[formatted.index(start):formatted.index(end)])
        self.assertNotEqual(
            re.search(r"def compilerFrameSizeSourceSha256 : String := \"([^\"]+)", baseline).group(1),
            re.search(r"def compilerFrameSizeSourceSha256 : String := \"([^\"]+)", formatted).group(1),
        )

    def test_strict_limit_mutation_rejected(self) -> None:
        self.assertMutationRejected(
            r"(T\.Int64\s*\(\s*Frame\.Width\s*\)\s*\*\s*T\.Int64\s*\(\s*Frame\.Height\s*\))\s*>\s*T\.Max_Image_Pixels",
            r"\1 >= T.Max_Image_Pixels", "Max_Image_Pixels value",
        )

    def test_product_operand_mutation_rejected(self) -> None:
        self.assertMutationRejected(
            r"T\.Int64\s*\(\s*Frame\.Width\s*\)\s*\*\s*T\.Int64\s*\(\s*Frame\.Height\s*\)",
            "T.Int64 (Frame.Width) * T.Int64 (Frame.Width)", "product is not widened",
        )

    def test_width_half_arithmetic_mutation_rejected(self) -> None:
        self.assertMutationRejected(
            r"T\.Int64\s*\(\s*Frame\.Width\s*\)\s*\*\s*T\.Int64\s*\(\s*Frame\.Height\s*\)",
            "T.Int64 (Frame.Width / 2) * T.Int64 (Frame.Height)",
        )

    def test_forced_int32_narrowing_has_compiler_range_check_and_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="frame-size-narrowing-") as temp:
            directory = Path(temp)
            baseline_diagnostics = directory / "baseline"
            frame_size.extract(SPEC, baseline_diagnostics)
            source = copy_input(directory)
            substitute_once(
                source,
                r"T\.Int64\s*\(\s*Frame\.Width\s*\)\s*\*\s*T\.Int64\s*\(\s*Frame\.Height\s*\)",
                "T.Int64 (T.Int32 (T.Int64 (Frame.Width) * T.Int64 (Frame.Height)))",
            )
            diagnostics = directory / "narrowed"
            with self.assertRaises(frame_size.ExtractionError):
                frame_size.extract(source, diagnostics)
            def range_checks(path: Path) -> int:
                raw = (path / "amv-spec-gige_vision.ads.006t.original").read_text(encoding="utf-8")
                _, nodes = frame_size.compiler_ir.parse_function_tree_named(raw, "grab_status", "Grab_Status")
                return sum(node["kind"] == "call_expr"
                           and frame_size.compiler_ir.check_name(nodes, node_id).endswith("_Range_Check")
                           for node_id, node in nodes.items())
            self.assertGreater(range_checks(diagnostics), range_checks(baseline_diagnostics))

    def test_unused_probe_access_check_before_limit_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="frame-size-probe-") as temp:
            directory = Path(temp)
            baseline_diagnostics = directory / "baseline"
            frame_size.extract(SPEC, baseline_diagnostics)
            source = copy_input(directory)
            substitute_once(
                source,
                r"elsif\s+T\.Int64\s*\(\s*Frame\.Width\s*\)\s*\*\s*T\.Int64\s*\(\s*Frame\.Height\s*\)\s*>\s*T\.Max_Image_Pixels\s+then",
                "elsif (declare Probe : constant Positive := Frame.Bytes.all'First; "
                "begin T.Int64 (Frame.Width) * T.Int64 (Frame.Height) > T.Max_Image_Pixels) then",
            )
            diagnostics = directory / "probe"
            with self.assertRaises(frame_size.ExtractionError):
                frame_size.extract(source, diagnostics)
            def access_checks(path: Path) -> int:
                raw = (path / "amv-spec-gige_vision.ads.006t.original").read_text(encoding="utf-8")
                _, nodes = frame_size.compiler_ir.parse_function_tree_named(raw, "grab_status", "Grab_Status")
                return sum(node["kind"] == "call_expr"
                           and frame_size.compiler_ir.check_name(nodes, node_id).endswith("_Access_Check")
                           for node_id, node in nodes.items())
            self.assertGreater(access_checks(diagnostics), access_checks(baseline_diagnostics))

    def test_noop_extra_product_expression_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="frame-size-extra-product-") as temp:
            directory = Path(temp)
            baseline_diagnostics = directory / "baseline"
            frame_size.extract(SPEC, baseline_diagnostics)
            source = copy_input(directory)
            substitute_once(
                source,
                r"elsif\s+T\.Int64\s*\(\s*Frame\.Width\s*\)\s*\*\s*T\.Int64\s*\(\s*Frame\.Height\s*\)\s*>\s*T\.Max_Image_Pixels\s+then",
                "elsif T.Int64 (Frame.Width) * T.Int64 (Frame.Width) >= 0 and then "
                "T.Int64 (Frame.Width) * T.Int64 (Frame.Height) > T.Max_Image_Pixels then",
            )
            diagnostics = directory / "extra-product"
            with self.assertRaises(frame_size.ExtractionError) as raised:
                frame_size.extract(source, diagnostics)
            self.assertNotIn("command failed", str(raised.exception).lower())

            def node_count(path: Path, node_kind: str) -> int:
                raw = (path / "amv-spec-gige_vision.ads.006t.original").read_text(encoding="utf-8")
                _, nodes = frame_size.compiler_ir.parse_function_tree_named(raw, "grab_status", "Grab_Status")
                return sum(node["kind"] == node_kind for node in nodes.values())

            self.assertEqual(node_count(diagnostics, "mult_expr"), node_count(baseline_diagnostics, "mult_expr"))
            self.assertGreater(node_count(diagnostics, "truth_andif_expr"),
                               node_count(baseline_diagnostics, "truth_andif_expr"))

    def test_eager_null_access_check_mutation_rejected(self) -> None:
        self.assertMutationRejected(
            r"Frame\.Bytes\s*=\s*null\s+or\s+else\s+Frame\.Bytes\.all'First\s*/=\s*1",
            "(Frame.Bytes = null or Frame.Bytes.all'First /= 1)",
        )

    def test_raw_check_branch_orientation_mutation_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="frame-size-raw-check-") as temp:
            diagnostics = Path(temp) / "diagnostics"
            frame_size.extract(SPEC, diagnostics)
            raw_path = diagnostics / "amv-spec-gige_vision.ads.006t.original"
            raw = raw_path.read_text(encoding="utf-8")
            _, nodes = frame_size.compiler_ir.parse_function_tree_named(raw, "grab_status", "Grab_Status")
            selected = next(
                (node_id, frame_size.compiler_ir.ref(nodes, node_id, "op 1"),
                 frame_size.compiler_ir.ref(nodes, node_id, "op 2"))
                for node_id, node in nodes.items()
                if node["kind"] == "cond_expr"
                and nodes[frame_size.compiler_ir.ref(nodes, node_id, "op 1")]["kind"] == "call_expr"
                and frame_size.compiler_ir.check_name(
                    nodes, frame_size.compiler_ir.ref(nodes, node_id, "op 1")
                ).startswith("__gnat_rcheck_CE_")
            )
            cond_id, check_id, other_id = selected
            match = re.search(rf"(?ms)^@{cond_id}\s+cond_expr\b.*?(?=^@\d+\s|\Z)", raw)
            self.assertIsNotNone(match)
            block = match.group(0)
            block, count = re.subn(
                rf"(op 1:\s*)@{check_id}(\s+op 2:\s*)@{other_id}\b",
                rf"\1@{other_id}\2@{check_id}", block, count=1,
            )
            self.assertEqual(count, 1)
            mutated = raw[:match.start()] + block + raw[match.end():]
            standard = (diagnostics / "gnatS-standard.log").read_text(encoding="utf-8")
            expanded = (diagnostics / "gnatG-gnatL.log").read_text(encoding="utf-8")
            _, version, target = frame_size.compiler_ir.compiler()
            with self.assertRaises(frame_size.ExtractionError):
                frame_size.generate(mutated, standard, expanded, SPEC, TYPES, version, target)

    def test_raw_unknown_check_call_mutation_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="frame-size-raw-call-") as temp:
            diagnostics = Path(temp) / "diagnostics"
            frame_size.extract(SPEC, diagnostics)
            raw = (diagnostics / "amv-spec-gige_vision.ads.006t.original").read_text(encoding="utf-8")
            mutated = raw.replace("__gnat_rcheck_CE_Access_Check", "__gnat_rcheck_CE_Unknown_Check")
            self.assertNotEqual(raw, mutated)
            standard = (diagnostics / "gnatS-standard.log").read_text(encoding="utf-8")
            expanded = (diagnostics / "gnatG-gnatL.log").read_text(encoding="utf-8")
            _, version, target = frame_size.compiler_ir.compiler()
            with self.assertRaises(frame_size.ExtractionError):
                frame_size.generate(mutated, standard, expanded, SPEC, TYPES, version, target)

    def test_count_conversion_mutation_rejected(self) -> None:
        self.assertMutationRejected(
            r"T\.Int64\s*\(\s*Frame\.Byte_Count\s*\)",
            "T.Int64 (Frame.Byte_Count + 1)",
        )

    def test_source_size_equality_mutation_rejected(self) -> None:
        self.assertMutationRejected(r"Frame\.Source_Size\s*/=", "Frame.Source_Size =",
                                    "Source_Size comparison")

    def test_byte_count_predicate_mutation_rejected(self) -> None:
        self.assertMutationRejected(
            r"(T\.Int64\s*\(\s*Frame\.Byte_Count\s*\))\s*/=",
            r"\1 =", "Byte_Count comparison",
        )

    def test_array_length_predicate_mutation_rejected(self) -> None:
        self.assertMutationRejected(
            r"(T\.Int64\s*\(\s*Frame\.Bytes\.all'Length\s*\))\s*/=",
            r"\1 =", "array length expression",
        )

    def test_first_bound_mutation_rejected(self) -> None:
        self.assertMutationRejected(
            r"Frame\.Bytes\.all'First\s*/=\s*1",
            "Frame.Bytes.all'First /= 2",
            "first-bound comparison",
        )

    def test_null_access_guard_reorder_rejected(self) -> None:
        self.assertMutationRejected(
            r"Frame\.Bytes\s*=\s*null\s+or else\s+Frame\.Bytes\.all'First\s*/=\s*1",
            "Frame.Bytes.all'First /= 1 or else Frame.Bytes = null",
            "null guard is missing or reordered",
        )

    def test_null_access_guard_removal_rejected(self) -> None:
        self.assertMutationRejected(r"or else\s+Frame\.Bytes\s*=\s*null", "")

    def test_null_access_guard_negation_rejected(self) -> None:
        self.assertMutationRejected(r"Frame\.Bytes\s*=\s*null", "Frame.Bytes /= null",
                                    "null guard is missing or reordered")

    def test_status_return_mutation_rejected(self) -> None:
        self.assertMutationRejected(r"T\.Frame_Too_Large", "T.Frame_Invalid_Length",
                                    "Too_Large branch")

    def test_unknown_limit_node_rejected(self) -> None:
        self.assertMutationRejected(r"T\.Max_Image_Pixels", "T.Max_Image_Pixels + 1",
                                    "Max_Image_Pixels value")

    def test_changed_type_bounds_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="frame-size-type-mutation-") as temp:
            directory = Path(temp)
            source = copy_input(directory)
            types = directory / TYPES.name
            shutil.copy2(TYPES, types)
            text = types.read_text(encoding="utf-8")
            old = "subtype Int32 is AMV.Kernels.Int32;"
            if text.count(old) != 1:
                self.fail("expected one Int32 subtype declaration")
            types.write_text(text.replace(old, "subtype Int32 is AMV.Kernels.Int32 range -100 .. 100;"), encoding="utf-8")
            with self.assertRaises(frame_size.ExtractionError) as raised:
                frame_size.extract(source, None, types)
            message = str(raised.exception)
            self.assertNotIn("command failed", message.lower(), message)
            self.assertIn("compiler checks in frame-size suffix", message)


if __name__ == "__main__":
    unittest.main()
