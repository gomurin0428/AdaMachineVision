import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
PROOF_HELPER = ROOT / "tools/mutant_prove.sh"
PLANNER = ROOT / "tools/mutation_plan.py"
SHARD_HELPER = ROOT / "tools/mutant_shard.sh"
PROOF_GATE = ROOT / "tools/mutation_proof_gate.py"
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
                "ADAMUTANT_MUTANT_ID",
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
        selected_sparks = [sessions / "amv-a.spark", sessions / "amv-b.spark"]
        for spark in selected_sparks:
            spark.write_text("stale", encoding="utf-8")
        unrelated_spark = sessions / "other.spark"
        unrelated_spark.write_text("keep", encoding="utf-8")

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
        self.assertTrue(all(not spark.exists() for spark in selected_sparks))
        self.assertTrue(unrelated_spark.exists())

    def test_mutant_unit_and_timeout_override(self):
        sessions = self.root / "build/obj/gnatprove"
        sessions.mkdir(parents=True)
        selected_spark = sessions / "mutated.spark"
        unrelated_spark = sessions / "unrelated.spark"
        selected_spark.write_text("stale", encoding="utf-8")
        unrelated_spark.write_text("keep", encoding="utf-8")
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
        self.assertFalse(selected_spark.exists())
        self.assertTrue(unrelated_spark.exists())

    def test_no_units_is_a_success_without_running_gnatprove(self):
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.capture.exists())

    def test_gnatprove_failure_propagates(self):
        self.status.write_text("23\n", encoding="utf-8")
        evidence_dir = self.root / "evidence"
        result = self.run_helper(
            ADAMUTANT_MUTANT_FILE="src/body.adb",
            ADAMUTANT_MUTANT_ID="23",
            AMV_PROVE_EVIDENCE_DIR=evidence_dir,
        )
        self.assertEqual(result.returncode, 23)
        self.assertIn("--timeout=120", self.arguments())
        evidence_files = list(evidence_dir.glob("mutant-*.json"))
        self.assertEqual(len(evidence_files), 1)
        evidence = json.loads(evidence_files[0].read_text(encoding="utf-8"))
        self.assertEqual(evidence["gnatproveExitCode"], 23)
        self.assertFalse(evidence["units"][0]["spark_fresh"])


class MutationTargetTests(unittest.TestCase):
    def test_both_mutation_targets_use_the_mandatory_gate(self):
        for target in ("mutation", "mutation-diff"):
            with self.subTest(target=target):
                result = subprocess.run(
                    [
                        "make",
                        "--dry-run",
                        target,
                        "MUTATE=src/amv-kernels-blob.adb",
                        "MUTATION_BASE=origin/main",
                        "MUTATION_BASELINE=/tmp/baseline.json",
                        "MUTATION_EVIDENCE_DIR=/tmp/fresh-evidence",
                        "MUTATION_REPORT_CACHE_PATH=/tmp/last-report.json",
                    ],
                    cwd=ROOT,
                    text=True,
                    capture_output=True,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("tools/mutation_proof_gate.py run", result.stdout)
                self.assertIn("--baseline-report '/tmp/baseline.json'", result.stdout)
                self.assertIn("--evidence-dir '/tmp/fresh-evidence'", result.stdout)
                self.assertIn("--report-cache-path '/tmp/last-report.json'", result.stdout)
                if target == "mutation-diff":
                    self.assertIn("--since origin/main", result.stdout)


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


class MutationProofGateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = pathlib.Path(self.temporary.name)
        self.evidence = self.root / "evidence"
        self.evidence.mkdir()
        self.manifest_time = time.time_ns() - 10_000_000_000
        (self.evidence / "manifest.json").write_text(
            json.dumps({"schemaVersion": 1, "createdAtNs": self.manifest_time}),
            encoding="utf-8",
        )
        self.report = self.root / "mutation-report.json"
        self.write_report(
            [{"id": "1", "status": "Killed", "killedBy": ["proof: assertion"]}]
        )

    def write_report(self, mutants):
        self.report.write_text(
            json.dumps(
                {
                    "schemaVersion": 1,
                    "files": {"src/unit.adb": {"mutants": mutants}},
                }
            ),
            encoding="utf-8",
        )

    def run_gate(self, report=None, evidence=None):
        return subprocess.run(
            [
                sys.executable,
                str(PROOF_GATE),
                "gate",
                "--report",
                str(report or self.report),
                "--evidence-dir",
                str(evidence or self.evidence),
            ],
            text=True,
            capture_output=True,
        )

    def record_spark(self, spark, log="", started_ns=None, mutant_id="1", exit_code=1):
        started_ns = started_ns if started_ns is not None else time.time_ns() - 5_000_000_000
        spark_root = self.root / "build/obj/gnatprove"
        spark_root.mkdir(parents=True, exist_ok=True)
        spark_text = spark if isinstance(spark, str) else json.dumps(spark)
        (spark_root / "unit.spark").write_text(spark_text, encoding="utf-8")
        log_path = self.root / "gnatprove.log"
        log_path.write_text(log, encoding="utf-8")
        return subprocess.run(
            [
                sys.executable,
                str(PROOF_GATE),
                "record",
                "--evidence-dir",
                str(self.evidence),
                "--mutant-id",
                mutant_id,
                "--started-ns",
                str(started_ns),
                "--exit-code",
                str(exit_code),
                "--spark-root",
                str(spark_root),
                "--log",
                str(log_path),
                "--units",
                "unit.adb",
            ],
            text=True,
            capture_output=True,
        )

    def test_limit_unknown_gave_up_and_missing_confirmation_fail_closed(self):
        for status in ("limit", "unknown", "gave_up"):
            with self.subTest(status=status):
                self.evidence = self.root / status
                self.evidence.mkdir()
                self.manifest_time = time.time_ns() - 10_000_000_000
                (self.evidence / "manifest.json").write_text(
                    json.dumps({"schemaVersion": 1, "createdAtNs": self.manifest_time}),
                    encoding="utf-8",
                )
                self.report = self.root / f"report-{status}.json"
                self.write_report(
                    [{"id": "1", "status": "Killed", "killedBy": ["proof: assertion"]}]
                )
                spark = {
                    "proof": [
                        {
                            "severity": "medium",
                            "check_file": "unit.adb",
                            "check_line": 10,
                            "check_col": 5,
                            "message": {"text": "assertion might fail"},
                            "unproved_status": {"status": status},
                        }
                    ]
                }
                result = self.record_spark(spark)
                self.assertEqual(result.returncode, 0, result.stderr)
                gate = self.run_gate()
                self.assertNotEqual(gate.returncode, 0, gate.stdout)

    def test_fresh_high_counterexample_accepts_other_inconclusive_checks(self):
        spark = {
            "proof": [
                {
                    "severity": "high",
                    "check_file": "unit.adb",
                    "check_line": 20,
                    "check_col": 7,
                    "message": {"text": "assertion might fail"},
                    "unproved_status": {"status": "unknown"},
                },
                {
                    "severity": "medium",
                    "check_file": "unit.adb",
                    "check_line": 30,
                    "check_col": 7,
                    "message": {"text": "loop invariant might not be preserved"},
                    "unproved_status": {"status": "limit", "steps": True, "time": True},
                },
            ]
        }
        result = self.record_spark(spark)
        self.assertEqual(result.returncode, 0, result.stderr)
        gate = self.run_gate()
        self.assertEqual(gate.returncode, 0, gate.stdout + gate.stderr)
        self.assertIn('"confirmed": 1', gate.stdout)

    def test_successful_gnatprove_exit_cannot_confirm_a_proof_kill(self):
        spark = {
            "proof": [
                {
                    "severity": "high",
                    "check_file": "unit.adb",
                    "check_line": 20,
                    "check_col": 7,
                    "message": {"text": "assertion might fail"},
                }
            ]
        }
        result = self.record_spark(spark, exit_code=0)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotEqual(self.run_gate().returncode, 0)

    def test_high_diagnostic_requires_a_matching_fresh_unproved_check(self):
        spark = {
            "proof": [
                {
                    "severity": "medium",
                    "check_file": "unit.adb",
                    "check_line": 20,
                    "check_col": 7,
                    "message": {"text": "assertion might fail"},
                    "unproved_status": {"status": "unknown"},
                }
            ]
        }
        matching = self.record_spark(
            spark, "unit.adb:20:7: high: assertion might fail\n"
        )
        self.assertEqual(matching.returncode, 0, matching.stderr)
        self.assertEqual(self.run_gate().returncode, 0)

        self.evidence = self.root / "unmatched"
        self.evidence.mkdir()
        (self.evidence / "manifest.json").write_text(
            json.dumps({"schemaVersion": 1, "createdAtNs": self.manifest_time}),
            encoding="utf-8",
        )
        unmatched = self.record_spark(
            spark, "unit.adb:21:7: high: another check failed\n"
        )
        self.assertEqual(unmatched.returncode, 0, unmatched.stderr)
        self.assertNotEqual(self.run_gate().returncode, 0)

    def test_generic_error_diagnostic_is_not_counterexample_confirmation(self):
        spark = {
            "proof": [
                {
                    "severity": "medium",
                    "check_file": "unit.adb",
                    "check_line": 20,
                    "check_col": 7,
                    "message": {"text": "assertion might fail"},
                    "unproved_status": {"status": "unknown"},
                }
            ]
        }
        result = self.record_spark(spark, "unit.adb:20:7: error: proof failed\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        gate = self.run_gate()
        self.assertNotEqual(gate.returncode, 0)

    def test_final_proved_check_with_timeout_attempt_is_not_inconclusive(self):
        spark = {
            "proof": [
                {
                    "severity": "info",
                    "check_file": "unit.adb",
                    "check_line": 12,
                    "check_col": 5,
                    "message": {"text": "range check proved"},
                    "check_tree": [
                        {
                            "proof_attempts": {
                                "Z3": {"result": "Timeout", "time": 120},
                                "CVC5": {"result": "Valid", "time": 0.1},
                            }
                        }
                    ],
                    "unproved_status": {"status": "unknown"},
                },
                {
                    "severity": "high",
                    "check_file": "unit.adb",
                    "check_line": 20,
                    "check_col": 7,
                    "message": {"text": "assertion might fail"},
                },
            ]
        }
        result = self.record_spark(spark, "unit.adb:20:7: high: assertion might fail\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        gate = self.run_gate()
        self.assertEqual(gate.returncode, 0, gate.stdout + gate.stderr)

    def test_missing_malformed_and_stale_evidence_fail_closed(self):
        missing = self.run_gate()
        self.assertNotEqual(missing.returncode, 0)

        missing_report = self.run_gate(report=self.root / "missing-report.json")
        self.assertNotEqual(missing_report.returncode, 0)

        self.report = self.root / "malformed-report.json"
        self.report.write_text("{", encoding="utf-8")
        malformed_report = self.run_gate()
        self.assertNotEqual(malformed_report.returncode, 0)

        self.report = self.root / "mutation-report.json"
        (self.evidence / "mutant-malformed.json").write_text("{", encoding="utf-8")
        malformed_evidence = self.run_gate()
        self.assertNotEqual(malformed_evidence.returncode, 0)
        (self.evidence / "mutant-malformed.json").unlink()

        spark_root = self.root / "build/obj/gnatprove"
        spark_root.mkdir(parents=True, exist_ok=True)
        malformed = self.record_spark("{", started_ns=time.time_ns() - 1_000_000)
        self.assertEqual(malformed.returncode, 0, malformed.stderr)
        malformed_gate = self.run_gate()
        self.assertNotEqual(malformed_gate.returncode, 0)

        self.evidence = self.root / "stale"
        self.evidence.mkdir()
        (self.evidence / "manifest.json").write_text(
            json.dumps({"schemaVersion": 1, "createdAtNs": self.manifest_time}),
            encoding="utf-8",
        )
        stale = self.record_spark(
            {"proof": [{"severity": "medium", "unproved_status": {"status": "limit"}}]},
            started_ns=time.time_ns() + 10_000_000_000,
        )
        self.assertEqual(stale.returncode, 0, stale.stderr)
        self.assertNotEqual(self.run_gate().returncode, 0)

    def test_baseline_filter_removes_only_proof_killed_entries(self):
        baseline = self.root / "baseline.json"
        original = {
            "schemaVersion": 1,
            "files": {
                "src/unit.adb": {
                    "mutants": [
                        {"id": "p", "status": "Killed", "killedBy": ["proof: assertion"]},
                        {"id": "t", "status": "Killed", "killedBy": ["Test_Unit"]},
                        {"id": "c", "status": "CompileError"},
                        {"id": "r", "status": "RuntimeError"},
                    ]
                }
            },
        }
        baseline.write_text(json.dumps(original), encoding="utf-8")
        original_bytes = baseline.read_bytes()
        filtered = self.root / "filtered.json"
        result = subprocess.run(
            [
                sys.executable,
                str(PROOF_GATE),
                "filter",
                "--input",
                str(baseline),
                "--output",
                str(filtered),
            ],
            text=True,
            capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(baseline.read_bytes(), original_bytes)
        kept = filtered.read_text(encoding="utf-8")
        self.assertNotIn('"id": "p"', kept)
        self.assertIn('"id": "t"', kept)
        self.assertIn('"id": "c"', kept)
        self.assertIn('"id": "r"', kept)

    def test_empty_fresh_report_and_evidence_pass(self):
        self.report = self.root / "empty-report.json"
        self.write_report([])
        gate = self.run_gate()
        self.assertEqual(gate.returncode, 0, gate.stdout + gate.stderr)
        self.assertIn('"proofKilled": 0', gate.stdout)

    def test_gate_failure_prevents_report_cache(self):
        report = self.root / "run-report.json"
        cache = self.root / "cached" / "mutation-report.json"
        evidence = self.root / "run-evidence"
        code = (
            "import json,pathlib,sys; "
            "p=pathlib.Path(sys.argv[1]); p.parent.mkdir(parents=True,exist_ok=True); "
            "p.write_text(json.dumps({'schemaVersion':1,'files':{'src/unit.adb':"
            "{'mutants':[{'id':'1','status':'Killed','killedBy':['proof: assertion']}]}}}))"
        )
        result = subprocess.run(
            [
                sys.executable,
                str(PROOF_GATE),
                "run",
                "--report",
                str(report),
                "--evidence-dir",
                str(evidence),
                "--report-cache-path",
                str(cache),
                "--",
                sys.executable,
                "-c",
                code,
                str(report),
            ],
            text=True,
            capture_output=True,
        )
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertFalse(cache.exists())
        self.assertTrue(report.exists())

    def test_missing_baseline_is_allowed_for_a_cold_cache(self):
        report = self.root / "cold-cache-report.json"
        baseline = self.root / "missing-baseline.json"
        captured_args = self.root / "ada-args.json"
        evidence = self.root / "cold-cache-evidence"
        code = (
            "import json,pathlib,sys; "
            "pathlib.Path(sys.argv[1]).write_text(json.dumps({'schemaVersion':1,'files':{}})); "
            "pathlib.Path(sys.argv[2]).write_text(json.dumps(sys.argv[1:]))"
        )
        result = subprocess.run(
            [
                sys.executable,
                str(PROOF_GATE),
                "run",
                "--report",
                str(report),
                "--baseline-report",
                str(baseline),
                "--evidence-dir",
                str(evidence),
                "--",
                sys.executable,
                "-c",
                code,
                str(report),
                str(captured_args),
            ],
            text=True,
            capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("does not exist; no prior results reused", result.stdout)
        self.assertNotIn("--baseline", json.loads(captured_args.read_text(encoding="utf-8")))

    def test_malformed_existing_baseline_stops_before_adamutant(self):
        baseline = self.root / "malformed-baseline.json"
        baseline.write_text("{", encoding="utf-8")
        report = self.root / "must-not-be-created.json"
        code = "import pathlib,sys; pathlib.Path(sys.argv[1]).write_text('{}')"
        result = subprocess.run(
            [
                sys.executable,
                str(PROOF_GATE),
                "run",
                "--report",
                str(report),
                "--baseline-report",
                str(baseline),
                "--evidence-dir",
                str(self.root / "malformed-baseline-evidence"),
                "--",
                sys.executable,
                "-c",
                code,
                str(report),
            ],
            text=True,
            capture_output=True,
        )
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertFalse(report.exists())


if __name__ == "__main__":
    unittest.main()
