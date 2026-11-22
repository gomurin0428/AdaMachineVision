from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


PROJECT_DIR = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
SOURCE_DIR = REPOSITORY_ROOT / "optional" / "aravis" / "src"
EXTRACTOR = PROJECT_DIR / "tools" / "extract_contracts.py"
SOURCE_FILES = (
    "amv-gige_vision_types.ads",
    "amv-spec-gige_vision.ads",
    "amv-kernels-gige_vision.ads",
)

def copy_sources(destination: Path) -> None:
    destination.mkdir(parents=True)
    for name in SOURCE_FILES:
        shutil.copy2(SOURCE_DIR / name, destination / name)


def mutate_once(path: Path, old: str, new: str) -> None:
    source = path.read_text(encoding="utf-8")
    if source.count(old) != 1:
        raise AssertionError(f"expected exactly one mutation anchor in {path.name}: {old!r}")
    path.write_text(source.replace(old, new, 1), encoding="utf-8")


def run_extractor(source_dir: Path, output: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            str(EXTRACTOR),
            "--source-root",
            str(source_dir),
            "--output",
            str(output),
        ],
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )


def assert_extraction_rejected(
    test: unittest.TestCase,
    source_filename: str,
    old: str,
    new: str,
    expected_message: str | None = None,
) -> None:
    with tempfile.TemporaryDirectory() as directory:
        source_dir = Path(directory) / "src"
        copy_sources(source_dir)
        mutate_once(source_dir / source_filename, old, new)
        result = run_extractor(source_dir, Path(directory) / "Generated.lean")
        test.assertNotEqual(result.returncode, 0, result.stdout)
        if expected_message is not None:
            test.assertIn(expected_message, result.stdout)


class ExtractorTests(unittest.TestCase):
    def test_checked_in_generated_module_matches_current_ada(self) -> None:
        result = subprocess.run(
            [sys.executable, str(EXTRACTOR), "--check"],
            cwd=PROJECT_DIR,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_unsupported_operator_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source_dir = Path(directory) / "src"
            copy_sources(source_dir)
            mutate_once(
                source_dir / "amv-spec-gige_vision.ads",
                "State /= T.Closed or else not Valid_Selector (Device_ID)",
                "State < T.Closed or else not Valid_Selector (Device_ID)",
            )
            result = run_extractor(source_dir, Path(directory) / "Generated.lean")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("expected 'then'", result.stdout)

    def test_unapproved_helper_call_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source_dir = Path(directory) / "src"
            copy_sources(source_dir)
            mutate_once(
                source_dir / "amv-spec-gige_vision.ads",
                "if State /= T.Closed or else not Valid_Selector (Device_ID) then",
                "if State /= T.Closed or else not Unknown_Helper (Device_ID) then",
            )
            result = run_extractor(source_dir, Path(directory) / "Generated.lean")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("unsupported helper call", result.stdout)

    def test_alias_change_fails_closed(self) -> None:
        mutations = (
            (
                "amv-spec-gige_vision.ads",
                "package T renames AMV.GigE_Vision_Types;",
                "package T renames AMV.GigE_Vision_Native;",
                "spec package alias T",
            ),
            (
                "amv-kernels-gige_vision.ads",
                "package T  renames AMV.GigE_Vision_Types;",
                "package T  renames AMV.GigE_Vision_Native;",
                "kernel package alias T",
            ),
            (
                "amv-kernels-gige_vision.ads",
                "package N  renames AMV.GigE_Vision_Native;",
                "package N  renames AMV.GigE_Vision_Types;",
                "kernel package alias N",
            ),
        )
        for filename, old, new, expected in mutations:
            with self.subTest(filename=filename, expected=expected):
                assert_extraction_rejected(self, filename, old, new, expected)

    def test_enum_domain_change_fails_closed(self) -> None:
        mutations = (
            (
                "type Camera_State is (Closed, Open_Stopped, Streaming);",
                "type Camera_State is (Closed, Open_Stopped, Streaming, Paused);",
                "camera_state domain changed",
            ),
            (
                "      Native_Error);",
                "      Native_Error, Native_Pending);",
                "native_result domain changed",
            ),
            (
                "      Camera_Error);",
                "      Camera_Error, Camera_Pending);",
                "camera_status domain changed",
            ),
        )
        for old, new, expected in mutations:
            with self.subTest(expected=expected):
                assert_extraction_rejected(
                    self, "amv-gige_vision_types.ads", old, new, expected
                )

    def test_parameter_mode_change_fails_closed(self) -> None:
        start_profile = (
            "procedure Start\n"
            "     (State   : in out T.Camera_State;\n"
            "      Handle  : N.Camera_Handle;"
        )
        for changed_handle in (
            "Handle  : out N.Camera_Handle;",
            "Handle  : T.Camera_State;",
        ):
            changed = start_profile.replace("Handle  : N.Camera_Handle;", changed_handle)
            assert_extraction_rejected(
                self,
                "amv-kernels-gige_vision.ads",
                start_profile,
                changed,
                "signature or parameter modes changed",
            )

    def test_extra_selected_contract_aspect_fails_closed(self) -> None:
        assert_extraction_rejected(
            self,
            "amv-kernels-gige_vision.ads",
            "                   (State'Old /= T.Open_Stopped));",
            "                   (State'Old /= T.Open_Stopped)), Always_Terminates => True;",
            "unsupported=['always_terminates']",
        )

    def test_unconsumed_selected_clause_tokens_fail_closed(self) -> None:
        assert_extraction_rejected(
            self,
            "amv-spec-gige_vision.ads",
            "Pre => Result /= T.Native_Not_Called;",
            "Pre => Result /= T.Native_Not_Called True;",
            "unsupported/unconsumed token",
        )

    def test_qualified_old_attribute_fails_closed(self) -> None:
        assert_extraction_rejected(
            self,
            "amv-kernels-gige_vision.ads",
            "State'Old /= T.Open_Stopped",
            "Bogus.State'Old /= T.Open_Stopped",
            "qualified Ada attributes are unsupported",
        )

    def test_attribute_on_enum_case_choice_fails_closed(self) -> None:
        assert_extraction_rejected(
            self,
            "amv-spec-gige_vision.ads",
            "when T.Native_Success =>",
            "when T.Native_Success'Old =>",
            "attributes on enum case choices are unsupported",
        )

    def test_camera_result_argument_must_be_exact_result_name(self) -> None:
        original = (
            "elsif State = T.Streaming then\n"
            "         T.Camera_Success\n"
            "      elsif Result = T.Native_Not_Called then\n"
            "         T.Camera_Error\n"
            "      else\n"
            "         Camera_Result (Result));"
        )
        changed = original.replace(
            "Camera_Result (Result)",
            "Camera_Result (if Result = T.Native_Success then Result else Result)",
        )
        assert_extraction_rejected(
            self,
            "amv-spec-gige_vision.ads",
            original,
            changed,
            "must call exactly Camera_Result (Result)",
        )

    def test_camera_result_calls_are_restricted_to_status_helpers(self) -> None:
        assert_extraction_rejected(
            self,
            "amv-spec-gige_vision.ads",
            "if State = T.Closed and then Valid_Selector (Device_ID)\n"
            "        and then Result = T.Native_Success",
            "if State = T.Closed and then Valid_Selector (Device_ID)\n"
            "        and then Camera_Result (Result) = T.Camera_Success\n"
            "        and then Result = T.Native_Success",
            "unsupported Ghost helper call camera_result",
        )

    def test_camera_result_call_must_occur_once_in_status_helper(self) -> None:
        original = (
            "elsif State = T.Streaming then\n"
            "         T.Camera_Success\n"
            "      elsif Result = T.Native_Not_Called then\n"
            "         T.Camera_Error\n"
            "      else\n"
            "         Camera_Result (Result));"
        )
        changed = original.replace(
            "Camera_Result (Result)",
            "if Result = T.Native_Success then Camera_Result (Result) "
            "else Camera_Result (Result)",
        )
        assert_extraction_rejected(
            self,
            "amv-spec-gige_vision.ads",
            original,
            changed,
            "must contain exactly 1 Camera_Result calls, found 2",
        )

    def test_camera_result_call_is_not_allowed_in_its_precondition(self) -> None:
        assert_extraction_rejected(
            self,
            "amv-spec-gige_vision.ads",
            "Pre => Result /= T.Native_Not_Called;",
            "Pre => Result /= T.Native_Not_Called and then "
            "Camera_Result (Result) = T.Camera_Success;",
            "unsupported Ghost helper call camera_result",
        )

    def test_attribute_on_call_fails_closed(self) -> None:
        original = (
            "elsif State = T.Streaming then\n"
            "         T.Camera_Success\n"
            "      elsif Result = T.Native_Not_Called then\n"
            "         T.Camera_Error\n"
            "      else\n"
            "         Camera_Result (Result));"
        )
        changed = original.replace(
            "Camera_Result (Result)", "Camera_Result'Result (Result)"
        )
        assert_extraction_rejected(
            self,
            "amv-spec-gige_vision.ads",
            original,
            changed,
            "attributes on calls are unsupported",
        )

    def test_qualified_camera_result_call_fails_closed(self) -> None:
        original = (
            "elsif State = T.Streaming then\n"
            "         T.Camera_Success\n"
            "      elsif Result = T.Native_Not_Called then\n"
            "         T.Camera_Error\n"
            "      else\n"
            "         Camera_Result (Result));"
        )
        changed = original.replace(
            "Camera_Result (Result)", "Bogus.Camera_Result (Result)"
        )
        assert_extraction_rejected(
            self,
            "amv-spec-gige_vision.ads",
            original,
            changed,
            "unsupported Ghost helper call bogus.camera_result",
        )

    def test_valid_selector_profile_is_checked(self) -> None:
        original = "function Valid_Selector (Device_ID : String) return Boolean"
        mutations = (
            (
                "function Valid_Selector (Device_ID : out String) return Boolean",
                "valid_selector signature or parameter modes changed",
            ),
            (
                "function Valid_Selector (Device_ID : String) return Natural",
                "valid_selector return type changed",
            ),
            (
                "function Valid_Selector (Selector : String) return Boolean",
                "valid_selector signature or parameter modes changed",
            ),
            (
                "function Valid_Selector (Device_ID : Wide_String) return Boolean",
                "valid_selector signature or parameter modes changed",
            ),
        )
        for replacement, expected in mutations:
            with self.subTest(replacement=replacement):
                assert_extraction_rejected(
                    self,
                    "amv-spec-gige_vision.ads",
                    original,
                    replacement,
                    expected,
                )

    def test_valid_selector_pre_post_and_other_aspects_are_rejected(self) -> None:
        anchor = "Device_ID (I) /= ' '));"
        for aspect in ("Pre => True", "Post => True", "Global => null"):
            with self.subTest(aspect=aspect):
                assert_extraction_rejected(
                    self,
                    "amv-spec-gige_vision.ads",
                    anchor,
                    f"Device_ID (I) /= ' ')) with {aspect};",
                    "Valid_Selector aspects are unsupported",
                )

    def test_local_operator_functions_are_rejected_in_all_inputs(self) -> None:
        end_markers = {
            "amv-gige_vision_types.ads": ("end AMV.GigE_Vision_Types;", "Native_Result"),
            "amv-spec-gige_vision.ads": ("end AMV.Spec.GigE_Vision;", "T.Native_Result"),
            "amv-kernels-gige_vision.ads": ("end AMV.Kernels.GigE_Vision;", "T.Native_Result"),
        }
        operators = ("=", "/=", "not", "and", "+")
        for filename, (end_marker, type_name) in end_markers.items():
            for operator in operators:
                with self.subTest(filename=filename, operator=operator):
                    if operator in ("not", "abs"):
                        profile = f"(Value : {type_name}) return {type_name}"
                    else:
                        return_type = "Boolean" if operator in ("=", "/=") else type_name
                        profile = f"(Left, Right : {type_name}) return {return_type}"
                    declaration = f'   function "{operator}" {profile};\n'
                    assert_extraction_rejected(
                        self,
                        filename,
                        end_marker,
                        declaration + end_marker,
                        "local Ada operator function declarations are unsupported",
                    )

    def test_contract_pragmas_are_rejected_in_all_inputs(self) -> None:
        end_markers = {
            "amv-gige_vision_types.ads": "end AMV.GigE_Vision_Types;",
            "amv-spec-gige_vision.ads": "end AMV.Spec.GigE_Vision;",
            "amv-kernels-gige_vision.ads": "end AMV.Kernels.GigE_Vision;",
        }
        for filename, end_marker in end_markers.items():
            for pragma in ("Precondition", "Postcondition"):
                normalized = pragma.lower()
                with self.subTest(filename=filename, pragma=pragma):
                    declaration = f"   pragma {pragma} (True);\n"
                    assert_extraction_rejected(
                        self,
                        filename,
                        end_marker,
                        declaration + end_marker,
                        f"contract pragma {normalized} is unsupported",
                    )


class SourceConnectionTests(unittest.TestCase):
    def assert_ada_change_breaks_lean_agreement(
        self, filename: str, old: str, new: str
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source_dir = root / "src"
            copy_sources(source_dir)
            project_copy = root / "lean-camera"
            shutil.copytree(
                PROJECT_DIR,
                project_copy,
                ignore=shutil.ignore_patterns(".lake", "__pycache__"),
            )
            mutate_once(source_dir / filename, old, new)
            generated = run_extractor(
                source_dir,
                project_copy / "CameraLifecycle" / "Generated.lean",
            )
            self.assertEqual(generated.returncode, 0, generated.stdout)
            build = subprocess.run(
                ["lake", "build", "CameraLifecycle"],
                cwd=project_copy,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=180,
                check=False,
            )
            self.assertNotEqual(
                build.returncode,
                0,
                "Ada source mutation unexpectedly agreed with the independent Lean model",
            )
            self.assertIn("CameraLifecycle/Proofs.lean:", build.stdout, build.stdout)

    def test_wrong_state_mapping_breaks_proof(self) -> None:
        self.assert_ada_change_breaks_lean_agreement(
            "amv-spec-gige_vision.ads",
            "if State = T.Open_Stopped and then Result = T.Native_Success then\n         T.Streaming",
            "if State = T.Closed and then Result = T.Native_Success then\n         T.Streaming",
        )

    def test_wrong_status_mapping_breaks_proof(self) -> None:
        self.assert_ada_change_breaks_lean_agreement(
            "amv-spec-gige_vision.ads",
            "elsif State = T.Streaming then\n         T.Camera_Success\n      elsif Result = T.Native_Not_Called then",
            "elsif State = T.Streaming then\n         T.Camera_Error\n      elsif Result = T.Native_Not_Called then",
        )

    def test_wrong_native_dispatch_breaks_proof(self) -> None:
        self.assert_ada_change_breaks_lean_agreement(
            "amv-kernels-gige_vision.ads",
            "(State'Old /= T.Open_Stopped));",
            "(State'Old = T.Open_Stopped));",
        )

    def test_supported_open_pre_change_breaks_proof(self) -> None:
        original = (
            "procedure Open\n"
            "     (State    : in out T.Camera_State;\n"
            "      Handle   : in out N.Camera_Handle;\n"
            "      Device_ID : String;\n"
            "      Status   : out T.Camera_Status;\n"
            "      Receipt  : out T.Native_Result)\n"
            "   with\n"
            "     Pre => (State = T.Closed) = (Handle = N.Null_Handle),"
        )
        changed = original.replace(
            "Pre => (State = T.Closed) = (Handle = N.Null_Handle),",
            "Pre => True,",
        )
        self.assert_ada_change_breaks_lean_agreement(
            "amv-kernels-gige_vision.ads",
            original,
            changed,
        )

    def test_removed_dispatch_condition_breaks_proof(self) -> None:
        self.assert_ada_change_breaks_lean_agreement(
            "amv-kernels-gige_vision.ads",
            "       and then ((Receipt = T.Native_Not_Called) =\n"
            "                   (State'Old /= T.Open_Stopped))",
            "",
        )

    def test_close_condition_change_breaks_proof(self) -> None:
        self.assert_ada_change_breaks_lean_agreement(
            "amv-kernels-gige_vision.ads",
            "elsif State'Old = T.Streaming",
            "elsif State'Old = T.Open_Stopped",
        )


if __name__ == "__main__":
    unittest.main()
