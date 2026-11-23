from __future__ import annotations

import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(PROJECT_DIR / "tools"))
import extract_pixel_compiler as compiler_extractor


SPEC = REPOSITORY_ROOT / "optional/aravis/src/amv-spec-gige_vision.ads"
EXTRACTOR = PROJECT_DIR / "tools/extract_pixel_compiler.py"
GENERATED = PROJECT_DIR / "CameraLifecycle/Grab/CompilerGenerated.lean"


def run_extractor(
    source: Path, output: Path, diagnostics: Path | None = None
) -> subprocess.CompletedProcess[str]:
    command = [sys.executable, str(EXTRACTOR), "--source", str(source), "--output", str(output)]
    if diagnostics is not None:
        command.extend(["--diagnostics-dir", str(diagnostics)])
    return subprocess.run(
        command,
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
        check=False,
    )


def run_lean(project: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["lake", "build", "CameraLifecycle"],
        cwd=project,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=180,
        check=False,
    )


def copy_lean_project(root: Path) -> Path:
    project = root / "lean-camera"
    shutil.copytree(
        PROJECT_DIR,
        project,
        ignore=shutil.ignore_patterns(".lake", "__pycache__"),
    )
    return project


def make_source_copy(directory: Path) -> Path:
    source = directory / SPEC.name
    shutil.copy2(SPEC, source)
    return source


def replace_all(path: Path, old: str, new: str, count: int, *, exact: bool = False) -> None:
    text = path.read_text(encoding="utf-8")
    if exact:
        actual = text.count(old)
        changed = text.replace(old, new)
    else:
        pieces = []
        for piece in re.split(r"(\s+)", old):
            if not piece:
                continue
            if piece.isspace():
                pieces.append(r"\s*")
            else:
                pieces.append(re.escape(piece))
        pattern = re.compile("".join(pieces))
        changed, actual = pattern.subn(lambda _: new, text)
    if actual != count:
        raise AssertionError(f"expected {count} occurrences of {old!r}, got {actual}")
    path.write_text(changed, encoding="utf-8")


class PixelCompilerExtractorTests(unittest.TestCase):
    def test_compiler_version_and_target_are_pinned(self) -> None:
        with self.assertRaisesRegex(compiler_extractor.ExtractionError, "unsupported compiler/target"):
            compiler_extractor.validate_compiler_output("gcc (other) 16.1.0", "x86_64-pc-linux-gnu")
        with self.assertRaisesRegex(compiler_extractor.ExtractionError, "unsupported compiler/target"):
            compiler_extractor.validate_compiler_output(
                compiler_extractor.EXPECTED_VERSION, "aarch64-linux-gnu"
            )

    def test_unknown_raw_tree_node_fails_closed(self) -> None:
        nodes = {1: {"kind": "vector_convert_expr", "text": ""}}
        with self.assertRaisesRegex(compiler_extractor.ExtractionError, "unsupported compiler expression node"):
            compiler_extractor.parse_expr(nodes, 1, 2147483647)

    def test_frame_scalar_fields_require_direct_scoped_parameter_path(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            diagnostics = root / "compiler-diagnostics"
            result = run_extractor(SPEC, root / "CompilerGenerated.lean", diagnostics)
            self.assertEqual(result.returncode, 0, result.stdout)
            raw_dumps = list(diagnostics.glob("*.006t.original"))
            self.assertEqual(len(raw_dumps), 1)
            _, nodes = compiler_extractor.parse_function_tree(raw_dumps[0].read_text(encoding="utf-8"))
            function_ids = [
                node_id for node_id, node in nodes.items()
                if node["kind"] == "function_decl"
                and compiler_extractor.identifier(nodes, int(compiler_extractor.fields(node)["name"]))
                == "amv__spec__gige_vision__pixel_at"
            ]
            self.assertEqual(len(function_ids), 1)
            function_id = function_ids[0]
            parameters = {
                compiler_extractor.identifier(nodes, compiler_extractor.ref(nodes, node_id, "name")).lower(): node_id
                for node_id, node in nodes.items()
                if node["kind"] == "parm_decl"
                and compiler_extractor.fields(node).get("scpe") == str(function_id)
            }
            frame_parameter_id = parameters["frame"]
            width_components = [
                node_id for node_id, node in nodes.items()
                if node["kind"] == "component_ref"
                and compiler_extractor.identifier(
                    nodes, compiler_extractor.ref(nodes, node_id, "op 1")
                ).lower() == "width"
                and nodes[compiler_extractor.ref(nodes, node_id, "op 0")]["kind"] == "indirect_ref"
                and compiler_extractor.ref(
                    nodes, compiler_extractor.ref(nodes, node_id, "op 0"), "op 0"
                ) == frame_parameter_id
            ]
            self.assertTrue(width_components)
            component_id = width_components[0]
            _, _, _, natural_max = compiler_extractor.parse_standard_types(
                (diagnostics / "gnatS-standard.log").read_text(encoding="utf-8")
            )
            expression, _, _ = compiler_extractor.parse_expr(
                nodes, component_id, natural_max, function_id=function_id,
                frame_parameter_id=frame_parameter_id,
            )
            self.assertEqual(expression, ".width")

            wrong_scope_nodes = {node_id: dict(node) for node_id, node in nodes.items()}
            wrong_scope_nodes[frame_parameter_id]["text"], count = re.subn(
                r"\bscpe:\s*@\d+", f"scpe: @{function_id + 1}",
                wrong_scope_nodes[frame_parameter_id]["text"], count=1,
            )
            self.assertEqual(count, 1)
            with self.assertRaisesRegex(compiler_extractor.ExtractionError, "identity or scope"):
                compiler_extractor.parse_expr(
                    wrong_scope_nodes, component_id, natural_max, function_id=function_id,
                    frame_parameter_id=frame_parameter_id,
                )

            wrong_identity_nodes = {node_id: dict(node) for node_id, node in nodes.items()}
            decoy_parameter_id = max(wrong_identity_nodes) + 1
            wrong_identity_nodes[decoy_parameter_id] = dict(nodes[frame_parameter_id])
            with self.assertRaisesRegex(compiler_extractor.ExtractionError, "direct field"):
                compiler_extractor.parse_expr(
                    wrong_identity_nodes, component_id, natural_max, function_id=function_id,
                    frame_parameter_id=decoy_parameter_id,
                )

            nested_path_nodes = {node_id: dict(node) for node_id, node in nodes.items()}
            nested_component_id = max(nested_path_nodes) + 1
            component = nodes[component_id]
            nested_path_nodes[nested_component_id] = {
                "kind": "component_ref",
                "text": (
                    f"type: @{compiler_extractor.frame_record_type(nodes, function_id, frame_parameter_id)} "
                    f"op 0: @{compiler_extractor.ref(nodes, component_id, 'op 0')} "
                    f"op 1: @{compiler_extractor.ref(nodes, component_id, 'op 1')}"
                ),
            }
            nested_path_nodes[component_id]["text"], count = re.subn(
                r"\bop 0:\s*@\d+", f"op 0: @{nested_component_id}",
                component["text"], count=1,
            )
            self.assertEqual(count, 1)
            with self.assertRaisesRegex(compiler_extractor.ExtractionError, "expected indirect_ref"):
                compiler_extractor.parse_expr(
                    nested_path_nodes, component_id, natural_max, function_id=function_id,
                    frame_parameter_id=frame_parameter_id,
                )

    def test_standard_dump_validates_both_integer_exponents(self) -> None:
        standard = (
            "type Integer is range -(2 **31) .. +(2 **31 - 1);\n"
            "subtype Natural is Integer range 0 .. Integer'Last;\n"
            "subtype Positive is Integer range 1 .. Integer'Last;\n"
        )
        self.assertEqual(compiler_extractor.parse_standard_types(standard),
                         (-(1 << 31), (1 << 31) - 1, 0, (1 << 31) - 1))
        with self.assertRaisesRegex(compiler_extractor.ExtractionError, "did not expose"):
            compiler_extractor.parse_standard_types(standard.replace("+(2 **31 - 1)", "+(2 **30 - 1)"))

    def test_shadowed_int64_name_with_different_bounds_is_rejected(self) -> None:
        nodes = {
            1: {"kind": "integer_type", "text": "name: @2 size: @3 algn: 64 prec: 64 sign: signed min : @4 max : @5"},
            2: {"kind": "identifier_node", "text": "strg: amv__kernels__Tint64B lngt: 26"},
            3: {"kind": "integer_cst", "text": "type: @1 int: 64"},
            4: {"kind": "integer_cst", "text": "type: @1 int: -9223372036854775808"},
            5: {"kind": "integer_cst", "text": "type: @1 int: 9223372036854775806"},
        }
        with self.assertRaisesRegex(compiler_extractor.ExtractionError, "unexpected sign/precision/range"):
            compiler_extractor.type_tag(nodes, 1)

    def test_checked_in_artifact_is_fresh_from_actual_compiler_output(self) -> None:
        result = subprocess.run(
            [sys.executable, str(EXTRACTOR), "--check"],
            cwd=PROJECT_DIR,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=120,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("compiler-derived Pixel_At IR is fresh", result.stdout)

    def test_relative_source_path_resolves_from_project_working_directory(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "CompilerGenerated.lean"
            result = run_extractor(
                Path("../../optional/aravis/src/amv-spec-gige_vision.ads"), output
            )
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertTrue(output.is_file())

    def assert_semantic_mutation_disagrees_with_lean(self, mutate) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = make_source_copy(root)
            mutate(source)
            project = copy_lean_project(root)
            output = project / "CameraLifecycle/Grab/CompilerGenerated.lean"
            result = run_extractor(source, output)
            self.assertEqual(result.returncode, 0, result.stdout)
            generated = output.read_text(encoding="utf-8")
            baseline = GENERATED.read_text(encoding="utf-8")
            self.assertNotEqual(generated, baseline, "mutation only changed freshness metadata")
            self.assertNotEqual(
                re.findall(r"compilerRowExpr[01].*", generated),
                re.findall(r"compilerRowExpr[01].*", baseline),
                "compiler expression did not reflect the source mutation",
            )
            proof = run_lean(project)
            self.assertNotEqual(proof.returncode, 0, proof.stdout)
            self.assertIn("CompilerProofs.lean", proof.stdout)

    def assert_mutation_rejected_or_breaks_lean(self, mutate, changed_pattern: str) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = make_source_copy(root)
            mutate(source)
            project = copy_lean_project(root)
            output = project / "CameraLifecycle/Grab/CompilerGenerated.lean"
            diagnostics = root / "compiler-diagnostics"
            result = run_extractor(source, output, diagnostics)
            raw_dumps = list(diagnostics.glob("*.006t.original"))
            self.assertEqual(len(raw_dumps), 1, result.stdout)
            if result.returncode != 0:
                self.assertIn("compiler extraction failed", result.stdout)
                self.assertNotIn("command failed", result.stdout)
                return
            generated = output.read_text(encoding="utf-8")
            baseline = GENERATED.read_text(encoding="utf-8")
            self.assertNotEqual(
                [match.group(0) for match in re.finditer(changed_pattern, generated, re.M)],
                [match.group(0) for match in re.finditer(changed_pattern, baseline, re.M)],
                "actual compiler mutation only changed freshness/provenance metadata",
            )
            proof = run_lean(project)
            self.assertNotEqual(proof.returncode, 0, proof.stdout)
            self.assertIn("CompilerProofs.lean", proof.stdout)

    def test_width_to_height_regenerates_ir_and_breaks_lean_proof(self) -> None:
        def replace_width(source: Path) -> None:
            text = source.read_text(encoding="utf-8")
            pattern = re.compile(
                r"(T\.Int64\s*\(\s*Y\s*\)\s*\*\s*T\.Int64\s*\(\s*)Frame\.Width"
                r"(\s*\)\s*\+\s*T\.Int64\s*\(\s*X\s*\))"
            )
            changed, count = pattern.subn(r"\1Frame.Height\2", text)
            if count != 2:
                raise AssertionError(f"expected two selected compiler row expressions, got {count}")
            source.write_text(changed, encoding="utf-8")

        self.assert_semantic_mutation_disagrees_with_lean(
            replace_width
        )

    def test_x_y_swap_regenerates_ir_and_breaks_lean_proof(self) -> None:
        def swap(source: Path) -> None:
            text = source.read_text(encoding="utf-8")
            pattern = re.compile(
                r"T\.Int64\s*\(\s*Y\s*\)(\s*\*\s*T\.Int64\s*\(\s*Frame\.Width\s*\)"
                r"\s*\+\s*T\.Int64\s*\(\s*)X(\s*\))"
            )
            changed, count = pattern.subn(r"T.Int64 (X)\1Y\2", text)
            if count != 2:
                raise AssertionError(f"expected two compiler-source row expressions, got {count}")
            source.write_text(changed, encoding="utf-8")

        self.assert_semantic_mutation_disagrees_with_lean(swap)

    def test_removing_widening_uses_legal_int32_arithmetic_then_regenerates(self) -> None:
        def narrow(source: Path) -> None:
            text = source.read_text(encoding="utf-8")
            pattern = re.compile(
                r"T\.Int64\s*\(\s*Y\s*\)\s*\*\s*T\.Int64\s*\(\s*Frame\.Width\s*\)"
                r"\s*\+\s*T\.Int64\s*\(\s*X\s*\)"
            )
            replacement = "T.Int64 (T.Int32 (Y) * T.Int32 (Frame.Width) + T.Int32 (X))"
            changed, count = pattern.subn(replacement, text)
            if count != 2:
                raise AssertionError(f"expected two widened compiler-source expressions, got {count}")
            source.write_text(changed, encoding="utf-8")

        self.assert_mutation_rejected_or_breaks_lean(narrow, r"^def compiler(RowExpr[01]|CheckRoutines|RawCheckCalls)")

    def test_arithmetic_mutation_fails_closed_from_compiler_tree(self) -> None:
        self.assert_mutation_rejected_or_breaks_lean(
            lambda source: replace_all(source, "+ T.Int64 (X)", "- T.Int64 (X)", 2),
            r"^def compiler(RowExpr[01]|CheckRoutines|RawCheckCalls)",
        )

    def test_formatted_source_mutation_still_disagrees_with_lean(self) -> None:
        def mutate(source: Path) -> None:
            text = source.read_text(encoding="utf-8")
            pattern = re.compile(
                r"(T\.Int64\s*\(\s*Y\s*\)\s*\*)\s*T\.Int64\s*\(\s*Frame\.Width\s*\)"
            )
            formatted, count = pattern.subn(
                lambda match: f"{match.group(1)}\n         T.Int64  (Frame.Width)", text
            )
            if count != 2:
                raise AssertionError(f"expected two compiler-source width conversions, got {count}")
            source.write_text(formatted, encoding="utf-8")
            replace_all(
                source,
                "T.Int64 (Y) * T.Int64 (Frame.Width)",
                "T.Int64 (Y) * T.Int64 (Frame.Height)",
                2,
            )

        self.assert_semantic_mutation_disagrees_with_lean(mutate)

    def test_return_index_plus_two_is_not_silently_accepted(self) -> None:
        self.assert_mutation_rejected_or_breaks_lean(
            lambda source: replace_all(source, "T.Int64 (X)) + 1", "T.Int64 (X)) + 2", 1),
            r"^def compiler(IndexValueExpr|ArrayFailurePredicate|RowExpr[01])",
        )

    def test_fixed_return_index_is_not_silently_accepted(self) -> None:
        def fixed_index(source: Path) -> None:
            text = source.read_text(encoding="utf-8")
            pattern = re.compile(
                r"Frame\.Bytes\.all\s*\(\s*Positive\s*\(\s*Natural\s*\(.*?\)\s*\+\s*1\s*\)\s*\)\s*\)",
                re.S,
            )
            changed, count = pattern.subn("Frame.Bytes.all (Positive (1)))", text, count=1)
            if count != 1:
                raise AssertionError(f"expected one final returned byte index, got {count}")
            source.write_text(changed, encoding="utf-8")

        self.assert_mutation_rejected_or_breaks_lean(
            fixed_index, r"^def compiler(IndexValueExpr|ArrayFailurePredicate|RowExpr[01])"
        )

    def test_inserted_fallback_return_is_rejected_after_compilation(self) -> None:
        self.assert_mutation_rejected_or_breaks_lean(
            lambda source: replace_all(
                source, "      else\n         Frame.Bytes.all",
                "      elsif X = 17 then\n         0\n      else\n         Frame.Bytes.all", 1, exact=True,
            ),
            r"^def compiler(SelectedNodeIds|CheckRoutines|RowExpr[01])",
        )

    def test_reordered_natural_and_increment_checks_are_rejected(self) -> None:
        old = (
            "Natural\n                 (T.Int64 (Y) * T.Int64 (Frame.Width)\n"
            "                  + T.Int64 (X)) + 1"
        )
        new = (
            "Natural\n                 (T.Int64 (Y) * T.Int64 (Frame.Width)\n"
            "                  + T.Int64 (X) + 1)"
        )
        self.assert_mutation_rejected_or_breaks_lean(
            lambda source: replace_all(source, old, new, 1),
            r"^def compiler(SelectedNodeIds|CheckPredicates|IndexValueExpr|RowExpr[01])",
        )

    def test_negated_row_guard_is_rejected_after_compilation(self) -> None:
        self.assert_mutation_rejected_or_breaks_lean(
            lambda source: replace_all(
                source, ">= T.Int64 (Frame.Byte_Count)", "<= T.Int64 (Frame.Byte_Count)", 1
            ),
            r"^def compiler(SelectedNodeIds|CheckPredicates|RowExpr[01])",
        )

    def test_unrelated_row_expression_is_not_selected_as_return_evidence(self) -> None:
        old = "        or else Frame.Bytes = null\n      then\n         0\n      elsif"
        new = (
            "        or else T.Int64 (Y) * T.Int64 (Frame.Width) + T.Int64 (X) = -1\n"
            "        or else Frame.Bytes = null\n      then\n         0\n      elsif"
        )
        self.assert_mutation_rejected_or_breaks_lean(
            lambda source: replace_all(source, old, new, 1),
            r"^def compiler(SelectedNodeIds|RowNodeIds|RowExpr[01])",
        )

    def test_line_movement_preserves_compiler_expression_meaning(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = make_source_copy(root)
            source.write_text("\n" + source.read_text(encoding="utf-8"), encoding="utf-8")
            output = root / "CompilerGenerated.lean"
            result = run_extractor(source, output)
            self.assertEqual(result.returncode, 0, result.stdout)
            generated = output.read_text(encoding="utf-8")
            baseline = GENERATED.read_text(encoding="utf-8")
            self.assertNotEqual(generated, baseline)
            self.assertRegex(generated, r'def compilerPixelAtSource : String := "amv-spec-gige_vision\.ads:\d+"')
            self.assertNotEqual(
                re.findall(r"^def compilerPixelAtSource.*$", generated, re.M),
                re.findall(r"^def compilerPixelAtSource.*$", baseline, re.M),
            )
            self.assertEqual(
                re.findall(r"^def compilerRowExpr[01].*$", generated, re.M),
                re.findall(r"^def compilerRowExpr[01].*$", baseline, re.M),
            )

    def test_model_has_universal_boundary_and_null_range_regressions(self) -> None:
        proof_source = (PROJECT_DIR / "CameraLifecycle/Grab/CompilerProofs.lean").read_text(encoding="utf-8")
        for theorem in (
            "compiler_index_negative_row_is_range",
            "compiler_index_zero_row_reads_lower_bound",
            "compiler_index_natural_last_overflows_increment",
            "compiler_index_natural_max_minus_one_succeeds",
            "compiler_index_too_large_row_is_range",
            "compiler_index_upper_bound_succeeds",
            "compiler_index_outside_upper_bound_fails",
            "compiler_index_null_range_fails",
            "compiler_widened_row_max_coordinates_width_edges",
            "compiler_widened_row_zero_coordinates_width_edges",
            "compiler_pixel_read_branch_avoids_index_failures",
        ):
            self.assertIn(f"theorem {theorem}", proof_source)


if __name__ == "__main__":
    unittest.main()
