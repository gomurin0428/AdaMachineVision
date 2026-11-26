from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


PROJECT_DIR = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
ADA_SOURCE_DIR = REPOSITORY_ROOT / "optional" / "aravis" / "src"
KERNEL_SOURCE_DIR = REPOSITORY_ROOT / "src"
EXTRACTOR = PROJECT_DIR / "tools" / "extract_grab_contracts.py"
ADA_FILES = (
    "amv-gige_vision_types.ads",
    "amv-spec-gige_vision.ads",
    "amv-kernels-gige_vision.ads",
)
KERNEL_FILES = ("amv-kernels-images.ads", "amv-kernels.ads")


def copy_inputs(root: Path) -> tuple[Path, Path]:
    ada_dir = root / "ada-src"
    kernel_dir = root / "kernel-src"
    ada_dir.mkdir()
    kernel_dir.mkdir()
    for name in ADA_FILES:
        shutil.copy2(ADA_SOURCE_DIR / name, ada_dir / name)
    for name in KERNEL_FILES:
        shutil.copy2(KERNEL_SOURCE_DIR / name, kernel_dir / name)
    return ada_dir, kernel_dir


def copy_project(root: Path) -> Path:
    project = root / "lean-camera"
    shutil.copytree(
        PROJECT_DIR,
        project,
        ignore=shutil.ignore_patterns(".lake", "__pycache__"),
    )
    return project


def mutate_once(path: Path, old: str, new: str) -> None:
    source = path.read_text(encoding="utf-8")
    if source.count(old) != 1:
        raise AssertionError(
            f"expected exactly one mutation anchor in {path.name}: {old!r}; "
            f"found {source.count(old)}"
        )
    path.write_text(source.replace(old, new, 1), encoding="utf-8")


def mutate_all(path: Path, old: str, new: str, expected_count: int) -> None:
    source = path.read_text(encoding="utf-8")
    if source.count(old) != expected_count:
        raise AssertionError(
            f"expected {expected_count} mutation anchors in {path.name}: {old!r}; "
            f"found {source.count(old)}"
        )
    path.write_text(source.replace(old, new), encoding="utf-8")


def run_extractor(
    ada_dir: Path,
    kernel_dir: Path,
    output: Path,
    check: bool = False,
) -> subprocess.CompletedProcess[str]:
    command = [
        sys.executable,
        str(EXTRACTOR),
        "--source-root",
        str(ada_dir),
        "--kernel-root",
        str(kernel_dir),
        "--output",
        str(output),
    ]
    if check:
        command.append("--check")
    return subprocess.run(
        command,
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
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


class GrabExtractorTests(unittest.TestCase):
    def test_checked_in_generated_module_matches_all_ada_inputs(self) -> None:
        result = subprocess.run(
            [sys.executable, str(EXTRACTOR), "--check"],
            cwd=PROJECT_DIR,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=60,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_changed_source_makes_check_reject_stale_generated_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            ada_dir, kernel_dir = copy_inputs(root)
            mutate_once(
                ada_dir / "amv-spec-gige_vision.ads",
                "elsif Frame.Pixel_Format /= T.Arv_Pixel_Format_Mono_8 then\n"
                "         T.Frame_Unsupported_Format",
                "elsif Frame.Pixel_Format /= T.Arv_Pixel_Format_Mono_8 then\n"
                "         T.Frame_Unsupported_Payload",
            )
            result = run_extractor(
                ada_dir,
                kernel_dir,
                PROJECT_DIR / "CameraLifecycle" / "Grab" / "Generated.lean",
                check=True,
            )
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertIn("generated Grab source is stale", result.stdout)

    def test_supported_equivalent_expression_regenerates_and_builds(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            ada_dir, kernel_dir = copy_inputs(root)
            project = copy_project(root)
            mutate_once(
                ada_dir / "amv-gige_vision_types.ads",
                "((if Frame.Byte_Count = 0 then Frame.Bytes = null",
                "((if (Frame.Byte_Count = 0) then Frame.Bytes = null",
            )
            output = project / "CameraLifecycle" / "Grab" / "Generated.lean"
            result = run_extractor(ada_dir, kernel_dir, output)
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertEqual(
                output.read_text(encoding="utf-8"),
                (PROJECT_DIR / "CameraLifecycle" / "Grab" / "Generated.lean").read_text(
                    encoding="utf-8"
                ),
            )
            build = run_lean(project)
            self.assertEqual(build.returncode, 0, build.stdout)

    def test_unary_plus_equivalent_source_rewrite_regenerates_and_builds(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            ada_dir, kernel_dir = copy_inputs(root)
            project = copy_project(root)
            mutate_once(
                kernel_dir / "amv-kernels-images.ads",
                "function Valid_Image\n"
                "     (Image : access constant Ks_Image_8_Grey_Data) return Boolean\n"
                "   is\n"
                "     (Image /= null\n"
                "      and then Image.Pixels /= null\n"
                "      and then Image.Width >= 1",
                "function Valid_Image\n"
                "     (Image : access constant Ks_Image_8_Grey_Data) return Boolean\n"
                "   is\n"
                "     (Image /= null\n"
                "      and then Image.Pixels /= null\n"
                "      and then +Image.Width >= 1",
            )
            output = project / "CameraLifecycle" / "Grab" / "Generated.lean"
            result = run_extractor(ada_dir, kernel_dir, output)
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertIn("image.map ImageData.width).getD 0 ≥ 1", output.read_text(encoding="utf-8"))
            build = run_lean(project)
            self.assertEqual(build.returncode, 0, build.stdout)

    def test_unsafe_numeric_and_contextual_type_mutations_fail_extraction(self) -> None:
        mutations = (
            (
                "amv-spec-gige_vision.ads",
                "T.Unsigned_64 (T.Int64 (Frame.Width) * T.Int64 (Frame.Height))",
                "T.Unsigned_64 (-1)",
                "negative modular conversion",
                1,
            ),
            (
                "amv-spec-gige_vision.ads",
                "Natural\n                 (T.Int64 (Y) * T.Int64 (Frame.Width)\n"
                "                  + T.Int64 (X)) + 1",
                "Natural (-1) + 1",
                "unchecked negative Natural conversion",
                1,
            ),
            (
                "amv-spec-gige_vision.ads",
                "elsif T.Int64 (Frame.Width) * T.Int64 (Frame.Height)\n"
                "        > T.Max_Image_Pixels",
                "elsif Frame.Width * Frame.Height\n        > T.Max_Image_Pixels",
                "unwidened Int32 product",
                1,
            ),
            (
                "amv-spec-gige_vision.ads",
                "T.Int64 (Y) * T.Int64 (Frame.Width)\n"
                "        + T.Int64 (X) >= T.Int64 (Frame.Byte_Count)",
                "T.Int64 (Y) * T.Int64 (Frame.Width)\n"
                "        + T.Int64 (X) + 9223372036854775807 >= T.Int64 (Frame.Byte_Count)",
                "overflowing signed intermediate",
                1,
            ),
            (
                "amv-kernels-gige_vision.ads",
                "AMV.Spec.GigE_Vision.Pixel_At\n"
                "                       (Observation, Natural (X), Natural (Y))",
                "AMV.Spec.GigE_Vision.Pixel_At\n"
                "                       (Observation, Natural (X), T.Frame_Success)",
                "wrong helper argument type",
                2,
            ),
            (
                "amv-spec-gige_vision.ads",
                "elsif Frame.Width <= 0 or else Frame.Height <= 0 then\n"
                "         T.Frame_Invalid_Dimensions",
                "elsif Frame.Width then\n         T.Frame_Invalid_Dimensions",
                "non-Boolean condition",
                1,
            ),
            (
                "amv-spec-gige_vision.ads",
                "or else Frame.Bytes.all'First /= 1\n"
                "        or else T.Int64 (Frame.Bytes.all'Length)",
                "or else Frame.Bytes.all'First (2) /= 1\n"
                "        or else T.Int64 (Frame.Bytes.all'Length)",
                "invalid byte-array attribute axis",
                1,
            ),
            (
                "amv-kernels-images.ads",
                "Image /= null\n      and then Image.Pixels /= null",
                "Image /= null\n      and Image.Pixels /= null",
                "eager and does not guard pointer access",
                2,
            ),
            (
                "amv-spec-gige_vision.ads",
                "or else Frame.Bytes = null\n      then\n         0\n"
                "      elsif Frame.Bytes.all'First",
                "or else Frame.Bytes = null\n      then\n         T.Frame_Success\n"
                "      elsif Frame.Bytes.all'First",
                "incompatible conditional result type",
                1,
            ),
            (
                "amv-kernels-gige_vision.ads",
                "for all Y in Image.Pixels'Range (1)\n"
                "               => (for all X in Image.Pixels'Range (2)\n"
                "                   => Image.Pixels (Y, X) =\n"
                "                     AMV.Spec.GigE_Vision.Pixel_At\n"
                "                       (Observation, Natural (X), Natural (Y)))",
                "for all Status in Image.Pixels'Range (1)\n"
                "               => (for all X in Image.Pixels'Range (2)\n"
                "                   => Image.Pixels (Status, X) =\n"
                "                     AMV.Spec.GigE_Vision.Pixel_At\n"
                "                       (Observation, Natural (X), Natural (Status)))",
                "quantifier shadowing",
                2,
            ),
            (
                "amv-spec-gige_vision.ads",
                "end AMV.Spec.GigE_Vision;",
                "function Natural (Value : Integer) return Integer is (Value);\n"
                "end AMV.Spec.GigE_Vision;",
                "shadowed standard conversion",
                1,
            ),
        )
        for filename, old, new, label, expected_count in mutations:
            with self.subTest(mutation=label):
                with tempfile.TemporaryDirectory() as directory:
                    root = Path(directory)
                    ada_dir, kernel_dir = copy_inputs(root)
                    source = ada_dir / filename if filename in ADA_FILES else kernel_dir / filename
                    if expected_count == 1:
                        mutate_once(source, old, new)
                    else:
                        mutate_all(source, old, new, expected_count)
                    result = run_extractor(ada_dir, kernel_dir, root / "Generated.lean")
                    self.assertNotEqual(result.returncode, 0, result.stdout)

    def test_semantic_ada_mutations_break_grab_proofs(self) -> None:
        mutations = (
            (
                "amv-spec-gige_vision.ads",
                "if State /= T.Streaming or else Timeout = 0 then",
                "if State /= T.Streaming or else Timeout = 0 or else "
                "Frame.Acquisition_Status = T.Native_Timeout then",
                "status precedence",
            ),
            (
                "amv-spec-gige_vision.ads",
                "elsif Frame.Pixel_Format /= T.Arv_Pixel_Format_Mono_8 then\n"
                "         T.Frame_Unsupported_Format",
                "elsif Frame.Pixel_Format /= T.Arv_Pixel_Format_Mono_8 then\n"
                "         T.Frame_Unsupported_Payload",
                "status mapping",
            ),
            (
                "amv-spec-gige_vision.ads",
                "if State /= T.Streaming or else Timeout = 0 then",
                "if State /= T.Streaming or else Timeout < 0 then",
                "timeout condition",
            ),
            (
                "amv-spec-gige_vision.ads",
                "> T.Max_Image_Pixels",
                ">= T.Max_Image_Pixels",
                "dimension limit",
            ),
            (
                "amv-spec-gige_vision.ads",
                "T.Int64 (Frame.Bytes.all'Length) /=",
                "T.Int64 (Frame.Bytes.all'Length) =",
                "byte length condition",
            ),
            (
                "amv-spec-gige_vision.ads",
                "T.Int64 (Y) * T.Int64 (Frame.Width)\n"
                "                  + T.Int64 (X)) + 1",
                "T.Int64 (Y) * T.Int64 (Frame.Height)\n"
                "                  + T.Int64 (X)) + 1",
                "row-major stride",
            ),
            (
                "amv-spec-gige_vision.ads",
                "T.Int64 (Y) * T.Int64 (Frame.Width)\n"
                "                  + T.Int64 (X)) + 1",
                "T.Int64 (X) * T.Int64 (Frame.Width)\n"
                "                  + T.Int64 (Y)) + 1",
                "X/Y swap",
            ),
            (
                "amv-kernels-gige_vision.ads",
                "Image.Pixels (Y, X) =\n"
                "                     AMV.Spec.GigE_Vision.Pixel_At\n"
                "                       (Observation, Natural (X), Natural (Y))",
                "True",
                "weakened pixel quantifier body",
            ),
            (
                "amv-kernels-gige_vision.ads",
                "else Image = null",
                "else Image /= null",
                "failure null postcondition",
            ),
            (
                "amv-kernels-gige_vision.ads",
                "and then Status = T.Frame_Out_Of_Memory",
                "and then False",
                "removed OOM alternative",
            ),
            (
                "amv-kernels-gige_vision.ads",
                "and then Status = T.Frame_Out_Of_Memory))",
                "and then Status = T.Frame_Out_Of_Memory)\n"
                "          or else Status = T.Frame_Error)",
                "added status alternative",
            ),
            (
                "amv-kernels-gige_vision.ads",
                "Observation.Payload_Type = 0",
                "Observation.Pixel_Format = 0",
                "canonical observation field",
            ),
            (
                "amv-kernels-gige_vision.ads",
                "      Observation  : out T.Frame_Observation)\n"
                "   with\n"
                "     Pre => (State = T.Closed) = (Handle = N.Null_Handle),",
                "      Observation  : out T.Frame_Observation)\n"
                "   with\n"
                "     Pre => True,",
                "Grab precondition",
            ),
        )
        for filename, old, new, label in mutations:
            with self.subTest(mutation=label):
                with tempfile.TemporaryDirectory() as directory:
                    root = Path(directory)
                    ada_dir, kernel_dir = copy_inputs(root)
                    project = copy_project(root)
                    source = ada_dir / filename if filename in ADA_FILES else None
                    if source is None:
                        source = kernel_dir / filename
                    if label in {"weakened pixel quantifier body", "failure null postcondition",
                                 "removed OOM alternative", "added status alternative"}:
                        count = 2
                        mutate_all(source, old, new, count)
                    else:
                        mutate_once(source, old, new)
                    if label == "row-major stride":
                        mutate_once(
                            source,
                            "T.Int64 (Y) * T.Int64 (Frame.Width)\n"
                            "        + T.Int64 (X) >= T.Int64 (Frame.Byte_Count)",
                            "T.Int64 (Y) * T.Int64 (Frame.Height)\n"
                            "        + T.Int64 (X) >= T.Int64 (Frame.Byte_Count)",
                        )
                    elif label == "X/Y swap":
                        mutate_once(
                            source,
                            "T.Int64 (Y) * T.Int64 (Frame.Width)\n"
                            "        + T.Int64 (X) >= T.Int64 (Frame.Byte_Count)",
                            "T.Int64 (X) * T.Int64 (Frame.Width)\n"
                            "        + T.Int64 (Y) >= T.Int64 (Frame.Byte_Count)",
                        )
                    output = project / "CameraLifecycle" / "Grab" / "Generated.lean"
                    generated = run_extractor(ada_dir, kernel_dir, output)
                    self.assertEqual(generated.returncode, 0, generated.stdout)
                    self.assertNotEqual(
                        output.read_text(encoding="utf-8"),
                        (PROJECT_DIR / "CameraLifecycle" / "Grab" / "Generated.lean").read_text(
                            encoding="utf-8"
                        ),
                    )
                    build = run_lean(project)
                    self.assertNotEqual(build.returncode, 0, build.stdout)
                    self.assertIn("CameraLifecycle/Grab/Proofs.lean", build.stdout)

    def test_schema_profile_bounds_unknown_helper_and_contract_drift_fail_closed(self) -> None:
        mutations = (
            (
                "amv-gige_vision_types.ads",
                "type Camera_State is (Closed, Open_Stopped, Streaming);",
                "type Camera_State is (Closed, Open_Stopped, Streaming, Paused);",
                "Camera_State schema",
            ),
            (
                "amv-gige_vision_types.ads",
                "      Native_Error);",
                "      Native_Error, Native_Pending);",
                "Native_Result schema",
            ),
            (
                "amv-gige_vision_types.ads",
                "      Frame_Error);",
                "      Frame_Error, Frame_Pending);",
                "Frame_Status schema",
            ),
            (
                "amv-spec-gige_vision.ads",
                "X, Y  : Natural) return T.Pixel",
                "X : out Natural; Y : Natural) return T.Pixel",
                "Pixel_At profile",
            ),
            (
                "amv-gige_vision_types.ads",
                "type Byte_Array is array (Positive range <>) of Pixel;",
                "type Byte_Array is array (Natural range <>) of Pixel;",
                "Byte_Array bounds",
            ),
            (
                "amv-kernels-images.ads",
                "array (Natural range <>, Natural range <>) of Grey_8;",
                "array (Positive range <>, Natural range <>) of Grey_8;",
                "matrix bounds",
            ),
            (
                "amv-kernels-images.ads",
                "function Valid_Image\n"
                "     (Image : access constant Ks_Image_16_Grey_Data)",
                "function Valid_Image\n"
                "     (Image : access constant Ks_Image_8_Grey_Data)",
                "Valid_Image overload profiles",
            ),
            (
                "amv-kernels-images.ads",
                "(Image : access constant Ks_Image_8_Grey_Data) return Boolean\n   is",
                "(Image : access constant Ks_Image_8_Grey_Data) return Boolean\n"
                "     with Pre => True\n   is",
                "Valid_Image aspect drift",
            ),
            (
                "amv-kernels-gige_vision.ads",
                "package KI renames AMV.Kernels.Images;",
                "package KI renames AMV.Kernels;",
                "KI alias",
            ),
            (
                "amv-kernels-gige_vision.ads",
                "package N  renames AMV.GigE_Vision_Native;",
                "package N  renames AMV.GigE_Vision_Types;",
                "N alias",
            ),
            (
                "amv-kernels-gige_vision.ads",
                "package T  renames AMV.GigE_Vision_Types;",
                "package T  renames AMV.GigE_Vision_Native;",
                "T alias",
            ),
            (
                "amv-kernels-gige_vision.ads",
                "with AMV.Spec.GigE_Vision;",
                "with AMV.GigE_Vision_Types;",
                "kernel spec dependency",
            ),
            (
                "amv-kernels-gige_vision.ads",
                "      Image        : out KI.Ks_Image_8_Grey;\n"
                "      Status       : out T.Frame_Status;",
                "      Image        : in out KI.Ks_Image_8_Grey;\n"
                "      Status       : out T.Frame_Status;",
                "Grab Image mode",
            ),
            (
                "amv-kernels-gige_vision.ads",
                "      Observation : T.Frame_Observation;\n"
                "      Image       : out KI.Ks_Image_8_Grey;",
                "      Observation : out T.Frame_Observation;\n"
                "      Image       : out KI.Ks_Image_8_Grey;",
                "Build_Frame Observation mode",
            ),
            (
                "amv-spec-gige_vision.ads",
                "T.Int64 (Frame.Bytes.all'Length) /=",
                "T.Unknown (Frame.Bytes.all'Length) /=",
                "unknown helper call",
            ),
            (
                "amv-spec-gige_vision.ads",
                "or else Frame.Bytes.all'First /= 1",
                "or else Frame.Bytes.all'Size /= 1",
                "unsupported array attribute",
            ),
            (
                "amv-kernels-gige_vision.ads",
                "Global  => null,\n     Depends => ((Image, Status) =>",
                "Global  => null,\n     Pre => True,\n     Depends => ((Image, Status) =>",
                "extra Build_Frame Pre aspect",
            ),
        )
        for filename, old, new, label in mutations:
            with self.subTest(mutation=label):
                with tempfile.TemporaryDirectory() as directory:
                    root = Path(directory)
                    ada_dir, kernel_dir = copy_inputs(root)
                    source = ada_dir / filename if filename in ADA_FILES else kernel_dir / filename
                    mutate_once(source, old, new)
                    result = run_extractor(
                        ada_dir,
                        kernel_dir,
                        root / "Generated.lean",
                    )
                    self.assertNotEqual(result.returncode, 0, result.stdout)

    def test_selected_type_sources_reject_operator_overloads_and_contract_pragmas(self) -> None:
        for filename, old, declaration, label in (
            (
                "amv-kernels-images.ads",
                "end AMV.Kernels.Images;",
                'function "=" (Left, Right : Int32) return Boolean;\n',
                "operator overload",
            ),
            (
                "amv-kernels-images.ads",
                "end AMV.Kernels.Images;",
                "pragma Postcondition (True);\n",
                "contract pragma",
            ),
            (
                "amv-gige_vision_types.ads",
                "end AMV.GigE_Vision_Types;",
                "pragma Precondition (True);\n",
                "contract pragma in types",
            ),
        ):
            with self.subTest(rejection=label):
                with tempfile.TemporaryDirectory() as directory:
                    root = Path(directory)
                    ada_dir, kernel_dir = copy_inputs(root)
                    source = ada_dir / filename if filename in ADA_FILES else kernel_dir / filename
                    mutate_once(source, old, declaration + old)
                    result = run_extractor(ada_dir, kernel_dir, root / "Generated.lean")
                    self.assertNotEqual(result.returncode, 0, result.stdout)


if __name__ == "__main__":
    unittest.main()
