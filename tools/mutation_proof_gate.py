#!/usr/bin/env python3
"""Record fresh GNATprove evidence and gate AdaMutant proof-killed results."""

import argparse
import copy
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import time


SCHEMA_VERSION = 1
PROOF_KILLED = "proof-killed"
HIGH_DIAGNOSTIC = re.compile(r"^\s*(?:(?P<file>[^:\s]+\.ad[bs]):(?P<line>\d+):(?P<col>\d+):\s*)?high:\s*(?P<message>.*)$")
LOCATION = re.compile(r"^\s*-->\s*(?P<file>[^:\s]+\.ad[bs]):(?P<line>\d+):(?P<col>\d+)")


def _write_json(path, value):
    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name + f".tmp-{os.getpid()}")
    temp.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(temp, path)


def _load_json(path):
    try:
        with pathlib.Path(path).open(encoding="utf-8") as stream:
            return json.load(stream)
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ValueError(f"cannot read valid JSON from {path}: {error}") from error


def _parse_high_diagnostics(text):
    lines = text.splitlines()
    diagnostics = []
    for index, line in enumerate(lines):
        match = HIGH_DIAGNOSTIC.match(line)
        if not match:
            continue
        item = {
            "raw": line.strip(),
            "message": match.group("message").strip(),
            "file": match.group("file"),
            "line": int(match.group("line")) if match.group("line") else None,
            "column": int(match.group("col")) if match.group("col") else None,
        }
        if item["file"] is None:
            for following in lines[index + 1 : index + 4]:
                location = LOCATION.match(following)
                if location:
                    item["file"] = location.group("file")
                    item["line"] = int(location.group("line"))
                    item["column"] = int(location.group("col"))
                    break
        diagnostics.append(item)
    return diagnostics


def _same_location(left, right):
    if not left.get("file") or not right.get("file") or left.get("line") is None or right.get("line") is None:
        return False
    if pathlib.Path(left["file"]).name != pathlib.Path(right["file"]).name:
        return False
    if int(left["line"]) != int(right["line"]):
        return False
    left_col, right_col = left.get("column", left.get("col")), right.get("column", right.get("col"))
    return left_col is None or right_col is None or int(left_col) == int(right_col)


def _matches_diagnostic(check, diagnostic):
    message = check.get("message", "")
    return (
        _same_location(check, diagnostic)
        and (
            not diagnostic["message"]
            or not message
            or diagnostic["message"] in message
            or message in diagnostic["message"]
        )
    )


def _proof_record(unit, spark_root, started_ns, diagnostics):
    spark_path = pathlib.Path(spark_root) / (pathlib.Path(unit).stem + ".spark")
    record = {
        "unit": unit,
        "spark_path": str(spark_path),
        "spark_fresh": False,
        "checks": [],
        "confirmed_high_checks": [],
        "issues": [],
    }
    try:
        stat = spark_path.stat()
    except OSError:
        record["issues"].append("missing fresh .spark file")
        return record
    record["spark_mtime_ns"] = stat.st_mtime_ns
    if stat.st_mtime_ns < started_ns:
        record["issues"].append(".spark file predates this GNATprove invocation")
        return record
    record["spark_fresh"] = True
    try:
        data = _load_json(spark_path)
    except ValueError as error:
        record["issues"].append(f"malformed .spark file: {error}")
        return record
    if not isinstance(data, dict):
        record["issues"].append(".spark root is not an object")
        return record
    checks = data.get("proof")
    if not isinstance(checks, list):
        record["issues"].append(".spark proof field is missing or malformed")
        return record

    for check in checks:
        if not isinstance(check, dict) or not isinstance(check.get("severity"), str):
            record["issues"].append("malformed final-check entry in .spark")
            continue
        message = check.get("message")
        message_text = message.get("text", "") if isinstance(message, dict) else ""
        item = {
            "severity": check["severity"],
            "file": check.get("check_file", check.get("file")),
            "line": check.get("check_line", check.get("line")),
            "column": check.get("check_col", check.get("col")),
            "message": message_text,
            "unproved_status": check.get("unproved_status"),
        }
        record["checks"].append(item)
        matching_diagnostics = [
            diagnostic for diagnostic in diagnostics if _matches_diagnostic(item, diagnostic)
        ]
        if check["severity"] == "high":
            record["confirmed_high_checks"].append(
                {"check": item, "diagnostics": matching_diagnostics}
            )
        elif check["severity"] != "info" and matching_diagnostics:
            record["confirmed_high_checks"].append(
                {"check": item, "diagnostics": matching_diagnostics}
            )
        elif check["severity"] != "info":
            record["issues"].append(
                "final check is not proved and has no matching high-severity counterexample"
            )
    return record


def record(args):
    evidence_dir = pathlib.Path(args.evidence_dir)
    evidence_dir.mkdir(parents=True, exist_ok=True)
    diagnostics = _parse_high_diagnostics(pathlib.Path(args.log).read_text(encoding="utf-8", errors="replace"))
    units = args.units.split()
    evidence = {
        "schemaVersion": SCHEMA_VERSION,
        "mutantId": str(args.mutant_id),
        "startedAtNs": args.started_ns,
        "finishedAtNs": time.time_ns(),
        "gnatproveExitCode": args.exit_code,
        "highDiagnostics": diagnostics,
        "units": [
            _proof_record(unit, args.spark_root, args.started_ns, diagnostics)
            for unit in units
        ],
    }
    suffix = hashlib.sha256(str(args.mutant_id).encode("utf-8")).hexdigest()[:20]
    path = evidence_dir / f"mutant-{suffix}-{args.started_ns}.json"
    _write_json(path, evidence)
    print(f"recorded GNATprove evidence for mutant {args.mutant_id}: {path}")
    return 0


def _mutants(report):
    files = report.get("files")
    if not isinstance(files, dict):
        raise ValueError("raw AdaMutant report has no files object")
    for file_name, file_data in files.items():
        if not isinstance(file_data, dict) or not isinstance(file_data.get("mutants"), list):
            raise ValueError(f"malformed mutant list for {file_name}")
        for mutant in file_data["mutants"]:
            if not isinstance(mutant, dict) or "id" not in mutant or not isinstance(mutant.get("status"), str):
                raise ValueError(f"malformed mutant entry for {file_name}")
            yield mutant


def _killed_by(mutant):
    killed_by = mutant.get("killedBy")
    if not isinstance(killed_by, list) or not all(isinstance(item, str) for item in killed_by):
        return None
    if any(item == "proof" or item.startswith("proof:") for item in killed_by):
        return PROOF_KILLED
    if killed_by:
        return "other"
    return None


def filter_baseline(input_path, output_path):
    source = pathlib.Path(input_path).resolve()
    destination = pathlib.Path(output_path).resolve()
    if source == destination:
        raise ValueError("filtered baseline must not overwrite the original report")
    report = _load_json(source)
    if not isinstance(report, dict):
        raise ValueError("baseline report root must be an object")
    list(_mutants(report))
    filtered = copy.deepcopy(report)
    removed = 0
    for file_data in filtered["files"].values():
        kept = []
        for mutant in file_data["mutants"]:
            if mutant.get("status") == "Killed" and _killed_by(mutant) == PROOF_KILLED:
                removed += 1
            else:
                kept.append(mutant)
        file_data["mutants"] = kept
    _write_json(destination, filtered)
    print(f"filtered {removed} proof-killed baseline entries; original left unchanged")
    return 0


def _validate_report(report_path, evidence_dir, minimum_mtime_ns):
    failures = []
    evidence_dir = pathlib.Path(evidence_dir)
    manifest_path = evidence_dir / "manifest.json"
    try:
        manifest = _load_json(manifest_path)
        if not isinstance(manifest, dict):
            raise ValueError("malformed evidence manifest")
        if manifest.get("schemaVersion") != SCHEMA_VERSION or type(manifest.get("createdAtNs")) is not int:
            raise ValueError("malformed evidence manifest")
    except ValueError as error:
        return False, [str(error)], {"proofKilled": 0, "confirmed": 0, "blocked": 0}

    report_path = pathlib.Path(report_path)
    try:
        stat = report_path.stat()
        if stat.st_mtime_ns < max(minimum_mtime_ns, manifest["createdAtNs"]):
            raise ValueError("raw AdaMutant report is stale")
        report = _load_json(report_path)
        if not isinstance(report, dict):
            raise ValueError("raw AdaMutant report root must be an object")
        mutants = list(_mutants(report))
    except (OSError, ValueError) as error:
        return False, [str(error)], {"proofKilled": 0, "confirmed": 0, "blocked": 0}

    by_id = {}
    for path in evidence_dir.glob("mutant-*.json"):
        try:
            entry = _load_json(path)
            if not isinstance(entry, dict):
                continue
            mutant_id = str(entry.get("mutantId"))
            by_id.setdefault(mutant_id, []).append((path, entry))
        except ValueError:
            continue

    proof_killed = []
    for mutant in mutants:
        status = mutant["status"]
        killing_method = _killed_by(mutant)
        if status == "Killed" and killing_method is None:
            failures.append(f"mutant {mutant['id']}: missing or malformed killedBy in raw report")
        elif status == "Killed" and killing_method == PROOF_KILLED:
            proof_killed.append(mutant)

    confirmed = 0
    blocked = 0
    for mutant in proof_killed:
        mutant_id = str(mutant["id"])
        records = by_id.get(mutant_id, [])
        if len(records) != 1:
            failures.append(f"mutant {mutant_id}: expected one fresh evidence record, found {len(records)}")
            blocked += 1
            continue
        path, evidence = records[0]
        try:
            started = evidence["startedAtNs"]
            if evidence.get("schemaVersion") != SCHEMA_VERSION or evidence.get("mutantId") != mutant_id:
                raise ValueError("malformed or mismatched mutant evidence")
            if type(started) is not int or started < manifest["createdAtNs"]:
                raise ValueError("mutant evidence predates this run")
            finished = evidence.get("finishedAtNs")
            exit_code = evidence.get("gnatproveExitCode")
            if (
                path.stat().st_mtime_ns < started
                or type(finished) is not int
                or finished < started
                or type(exit_code) is not int
            ):
                raise ValueError("mutant evidence is stale or has no GNATprove exit code")
            if exit_code == 0:
                raise ValueError("proof-killed result has a successful GNATprove exit")
            units = evidence.get("units")
            if not isinstance(units, list) or not units:
                raise ValueError("mutant evidence has no selected-unit checks")
            diagnostics = evidence.get("highDiagnostics")
            if not isinstance(diagnostics, list):
                raise ValueError("mutant evidence has malformed high-severity diagnostics")
            for diagnostic in diagnostics:
                if (
                    not isinstance(diagnostic, dict)
                    or not isinstance(diagnostic.get("raw"), str)
                    or not HIGH_DIAGNOSTIC.match(diagnostic["raw"])
                    or not isinstance(diagnostic.get("message"), str)
                    or (diagnostic.get("file") is not None and not isinstance(diagnostic.get("file"), str))
                    or (diagnostic.get("line") is not None and type(diagnostic.get("line")) is not int)
                    or (diagnostic.get("column") is not None and type(diagnostic.get("column")) is not int)
                ):
                    raise ValueError("mutant evidence has malformed high-severity diagnostics")
            high = False
            for unit in units:
                if (
                    not isinstance(unit, dict)
                    or unit.get("spark_fresh") is not True
                    or type(unit.get("spark_mtime_ns")) is not int
                    or unit["spark_mtime_ns"] < started
                    or not isinstance(unit.get("checks"), list)
                    or not isinstance(unit.get("confirmed_high_checks"), list)
                    or not isinstance(unit.get("issues"), list)
                    or not all(isinstance(issue, str) for issue in unit["issues"])
                ):
                    raise ValueError("mutant evidence has missing or malformed fresh .spark data")
                for check in unit["checks"]:
                    if not isinstance(check, dict) or not isinstance(check.get("severity"), str):
                        raise ValueError("mutant evidence has malformed final-check statuses")
                    if check["severity"] == "high" or (
                        check["severity"] != "info"
                        and any(_matches_diagnostic(check, diagnostic) for diagnostic in diagnostics)
                    ):
                        high = True
            if high:
                confirmed += 1
                print(f"mutant {mutant_id}: confirmed high-severity counterexample; raw Killed result retained")
            else:
                issues = [issue for unit in units for issue in unit["issues"]]
                if not issues and not any(unit["checks"] for unit in units):
                    issues.append("no final proof checks")
                detail = "; ".join(issues) if issues else "no confirmed high-severity counterexample"
                failures.append(f"mutant {mutant_id}: proof-killed result is inconclusive ({detail})")
                blocked += 1
        except (KeyError, OSError, TypeError, ValueError) as error:
            failures.append(f"mutant {mutant_id}: malformed or stale evidence ({error})")
            blocked += 1

    result = {"proofKilled": len(proof_killed), "confirmed": confirmed, "blocked": blocked}
    return not failures, failures, result


def gate(args):
    passed, failures, result = _validate_report(args.report, args.evidence_dir, args.minimum_mtime_ns)
    output = {"schemaVersion": SCHEMA_VERSION, "passed": passed, **result, "failures": failures}
    if args.result:
        _write_json(args.result, output)
    print(json.dumps(output, sort_keys=True))
    return 0 if passed else 1


def _create_evidence_dir(requested):
    if requested:
        path = pathlib.Path(requested)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.mkdir()
    else:
        base = pathlib.Path("build/mutation-evidence")
        base.mkdir(parents=True, exist_ok=True)
        path = pathlib.Path(tempfile.mkdtemp(prefix="run-", dir=base))
    path = path.resolve()
    manifest = {"schemaVersion": SCHEMA_VERSION, "createdAtNs": time.time_ns()}
    _write_json(path / "manifest.json", manifest)
    return path, manifest


def run(args):
    command = args.argv
    if command and command[0] == "--":
        command = command[1:]
    if not command:
        print("mutation gate: missing AdaMutant command", file=sys.stderr)
        return 2
    try:
        evidence_dir, manifest = _create_evidence_dir(args.evidence_dir)
        if args.baseline_report:
            baseline = pathlib.Path(args.baseline_report)
            if baseline.exists():
                filtered = evidence_dir / "baseline.filtered.json"
                filter_baseline(baseline, filtered)
                if "--baseline" in command:
                    raise ValueError("AdaMutant command already contains --baseline")
                command.extend(["--baseline", str(filtered)])
            else:
                print(f"baseline report {baseline} does not exist; no prior results reused")
    except (OSError, ValueError) as error:
        print(f"mutation gate setup failed: {error}", file=sys.stderr)
        return 2

    environment = os.environ.copy()
    environment["AMV_PROVE_EVIDENCE_DIR"] = str(evidence_dir)
    print(f"mutation proof evidence: {evidence_dir}")
    try:
        completed = subprocess.run(command, env=environment, check=False)
        run_status = completed.returncode
    except OSError as error:
        print(f"AdaMutant could not be started: {error}", file=sys.stderr)
        run_status = 127
    passed, failures, result = _validate_report(args.report, evidence_dir, manifest["createdAtNs"])
    gate_result = {"schemaVersion": SCHEMA_VERSION, "passed": passed, **result, "failures": failures}
    _write_json(evidence_dir / "gate-result.json", gate_result)
    print(json.dumps(gate_result, sort_keys=True))
    if passed and run_status == 0 and args.report_cache_path:
        report = pathlib.Path(args.report)
        destination = pathlib.Path(args.report_cache_path)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(report, destination)
        print(f"cached gated AdaMutant report: {destination}")
    if run_status:
        return run_status
    return 0 if passed else 1


def main():
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="mode", required=True)

    record_parser = subparsers.add_parser("record")
    record_parser.add_argument("--evidence-dir", required=True)
    record_parser.add_argument("--mutant-id", required=True)
    record_parser.add_argument("--started-ns", type=int, required=True)
    record_parser.add_argument("--exit-code", type=int, required=True)
    record_parser.add_argument("--spark-root", required=True)
    record_parser.add_argument("--log", required=True)
    record_parser.add_argument("--units", required=True)
    record_parser.set_defaults(handler=record)

    filter_parser = subparsers.add_parser("filter")
    filter_parser.add_argument("--input", required=True)
    filter_parser.add_argument("--output", required=True)
    filter_parser.set_defaults(handler=lambda args: filter_baseline(args.input, args.output))

    gate_parser = subparsers.add_parser("gate")
    gate_parser.add_argument("--report", required=True)
    gate_parser.add_argument("--evidence-dir", required=True)
    gate_parser.add_argument("--minimum-mtime-ns", type=int, default=0)
    gate_parser.add_argument("--result")
    gate_parser.set_defaults(handler=gate)

    run_parser = subparsers.add_parser("run")
    run_parser.add_argument("--report", required=True)
    run_parser.add_argument("--baseline-report")
    run_parser.add_argument("--evidence-dir")
    run_parser.add_argument("--report-cache-path")
    run_parser.add_argument("argv", nargs=argparse.REMAINDER)
    run_parser.set_defaults(handler=run)

    args = parser.parse_args()
    return args.handler(args)


if __name__ == "__main__":
    sys.exit(main())
