import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
PROOF_HELPER = ROOT / "tools/mutant_prove.sh"
PLANNER = ROOT / "tools/mutation_plan.py"
SHARD_HELPER = ROOT / "tools/mutant_shard.sh"
SHARDS = (
    "logical",
    "arithmetic",
    "conditions",
    "numbers",
    "statements",
    "conjuncts",
    "assertions",
)
PINNED_ADAMUTANT_REF = "2c874914d9f4428c24ca0ba94f9d705549186723"
PINNED_DEFAULT_MUTATORS = {
    "ArithmeticOperator",
    "EqualityOperator",
    "LogicalOperator",
    "UnaryOperator",
    "BooleanLiteral",
    "MembershipOperator",
    "ConditionalExpression",
    "StatementDeletion",
    "NumericLiteral",
    "StringLiteral",
    "AttributeSwap",
    "ConjunctDeletion",
    "AssertionDeletion",
}


class MutationPlannerTests(unittest.TestCase):
    def plan(self, numstat="", whole=False):
        command = [sys.executable, str(PLANNER)]
        if whole:
            command.append("--whole")
        result = subprocess.run(
            command, input=numstat, text=True, capture_output=True, check=True
        )
        output = {}
        for line in result.stdout.splitlines():
            name, value = line.split("=", 1)
            output[name] = value if name in {"whole", "has_mutations"} else json.loads(value)
        return output

    def test_no_changes_and_deletions_only(self):
        self.assertEqual(self.plan()["jobs"], [])
        result = self.plan("0\t14\tsrc/removed.adb\n")
        self.assertEqual(result["jobs"], [])
        self.assertEqual(result["bodies"], [])
        self.assertEqual(result["has_mutations"], "false")

    def test_30_added_lines_and_small_change_use_all(self):
        for count in (3, 30):
            with self.subTest(added_lines=count):
                result = self.plan(f"{count}\t0\tsrc/body.adb\n")
                self.assertEqual([job["part"] for job in result["jobs"]], ["all"])

    def test_31_added_lines_uses_all_seven_parts_once(self):
        result = self.plan("31\t0\tsrc/body.adb\n")
        self.assertEqual([job["part"] for job in result["jobs"]], list(SHARDS))
        self.assertEqual(len(result["bodies"]), 1)
        self.assertEqual(
            {job["body_key"] for job in result["jobs"]},
            {result["bodies"][0]["body_key"]},
        )

    def test_whole_file_mode_uses_full_file_line_count(self):
        result = self.plan("31\t0\tsrc/manual.adb\n", whole=True)
        self.assertEqual(result["whole"], "true")
        self.assertEqual([job["part"] for job in result["jobs"]], list(SHARDS))


class MutationProofHelperTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = pathlib.Path(self.temporary.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.capture = self.root / "gnatprove-args.txt"
        self.status = self.root / "gnatprove-status.txt"
        self.status.write_text("0\n", encoding="utf-8")
        stub = self.bin / "gnatprove"
        stub.write_text(
            "#!/bin/sh\n"
            "printf '%s\\n' \"$@\" > \"$GNATPROVE_CAPTURE\"\n"
            "exit \"$(sed -n '1p' \"$GNATPROVE_STATUS_FILE\")\"\n",
            encoding="utf-8",
        )
        stub.chmod(0o755)

    def environment(self, **values):
        env = os.environ.copy()
        for key in tuple(env):
            if key.startswith("AMV_PROVE_") or key in {
                "ADAMUTANT_MUTANT_FILE",
                "ADAMUTANT_PROVE_CACHE",
            }:
                env.pop(key)
        env["PATH"] = f"{self.bin}{os.pathsep}{env['PATH']}"
        env["GNATPROVE_CAPTURE"] = str(self.capture)
        env["GNATPROVE_STATUS_FILE"] = str(self.status)
        env.update({key: str(value) for key, value in values.items()})
        return env

    def run_helper(self, **values):
        return subprocess.run(
            ["sh", str(PROOF_HELPER)],
            cwd=self.root,
            env=self.environment(**values),
            text=True,
            capture_output=True,
        )

    def arguments(self):
        return self.capture.read_text(encoding="utf-8").splitlines()

    def test_baseline_flags_units_cache_and_session_cleanup(self):
        sessions = self.root / "build/obj/gnatprove"
        sessions.mkdir(parents=True)
        for name in ("why3session.xml", "why3session.xml.1", "why3shapes", "why3shapes.1"):
            (sessions / name).write_text("stale", encoding="utf-8")
        output = sessions / "gnatprove.out"
        output.write_text("keep", encoding="utf-8")
        spark = sessions / ".spark"
        spark.write_text("keep", encoding="utf-8")

        result = self.run_helper(
            AMV_PROVE_UNITS="amv-a.adb amv-b.adb",
            AMV_PROVE_JOBS=4,
            AMV_PROVE_CACHE="/fresh-cache",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        args = self.arguments()
        for flag in (
            "-P",
            "amv.gpr",
            "-j4",
            "--steps=200000",
            "--timeout=120",
            "--checks-as-errors=on",
            "--report=fail",
            "--counterexamples=on",
            "--memcached-server=file:/fresh-cache",
        ):
            self.assertIn(flag, args)
        unit_flags = [args[index + 1] for index, arg in enumerate(args) if arg == "-u"]
        self.assertEqual(unit_flags, ["amv-a.adb", "amv-b.adb"])
        self.assertFalse(list(sessions.glob("why3session.xml*")))
        self.assertFalse(list(sessions.glob("why3shapes*")))
        self.assertTrue(output.exists())
        self.assertTrue(spark.exists())

    def test_mutant_unit_and_timeout_override(self):
        result = self.run_helper(
            ADAMUTANT_MUTANT_FILE="src/nested/mutated.adb",
            AMV_PROVE_UNITS="ignored.adb",
            AMV_PROVE_TIMEOUT=37,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        args = self.arguments()
        self.assertIn("--timeout=37", args)
        unit_flags = [args[index + 1] for index, arg in enumerate(args) if arg == "-u"]
        self.assertEqual(unit_flags, ["mutated.adb"])
        self.assertFalse(any(arg.startswith("--memcached-server=") for arg in args))

    def test_no_units_is_a_success_without_running_gnatprove(self):
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.capture.exists())

    def test_gnatprove_failure_propagates(self):
        self.status.write_text("23\n", encoding="utf-8")
        result = self.run_helper(AMV_PROVE_UNITS="body.adb")
        self.assertEqual(result.returncode, 23)
        self.assertIn("--timeout=120", self.arguments())


class MutatorShardCoverageTests(unittest.TestCase):
    def test_seven_shards_equal_the_pinned_default_mutator_set(self):
        workflow = (ROOT / ".github/workflows/mutation.yml").read_text(encoding="utf-8")
        self.assertRegex(
            workflow,
            rf"(?m)^\s+ADAMUTANT_REF: {PINNED_ADAMUTANT_REF}$",
        )

        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            (root / "adamutant.toml").write_text("[thresholds]\n", encoding="utf-8")
            grouped = []
            for shard in SHARDS:
                subprocess.run(
                    ["sh", str(SHARD_HELPER), shard],
                    cwd=root,
                    check=True,
                    text=True,
                    capture_output=True,
                )
                config = (root / f"adamutant-{shard}.toml").read_text(encoding="utf-8")
                match = re.search(r"(?m)^mutators = \[(.*)\]$", config)
                self.assertIsNotNone(match, shard)
                grouped.extend(re.findall(r'"([^"]+)"', match.group(1)))

            subprocess.run(
                ["sh", str(SHARD_HELPER), "all"],
                cwd=root,
                check=True,
                text=True,
                capture_output=True,
            )
            all_config = (root / "adamutant-all.toml").read_text(encoding="utf-8")
            self.assertNotRegex(all_config, r"(?m)^mutators = ")

        self.assertEqual(len(grouped), len(set(grouped)))
        self.assertEqual(set(grouped), PINNED_DEFAULT_MUTATORS)


if __name__ == "__main__":
    unittest.main()
