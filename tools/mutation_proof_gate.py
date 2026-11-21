#!/usr/bin/env python3
"""Record fresh GNATprove evidence and gate proof-dependent AdaMutant results."""

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


SCHEMA_VERSION = 2
PROOF_KILLED = "proof-killed"
FINAL_CHECK_SEVERITIES = {"high", "info", "low", "medium"}
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


def _has_location(item):
    file_name = item.get("file")
    line = item.get("line")
    column = item.get("column", item.get("col"))
    return (
        isinstance(file_name, str)
        and bool(file_name.strip())
        and type(line) is int
        and line > 0
        and type(column) is int
        and column > 0
    )


def _same_location(left, right):
    if not _has_location(left) or not _has_location(right):
        return False
    if pathlib.Path(left["file"]).name != pathlib.Path(right["file"]).name:
        return False
    return left["line"] == right["line"] and left.get("column", left.get("col")) == right.get("column", right.get("col"))


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
        "final_checks_well_formed": False,
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

    record["final_checks_well_formed"] = True
    for check in checks:
        if (
            not isinstance(check, dict)
            or not isinstance(check.get("severity"), str)
            or check["severity"] not in FINAL_CHECK_SEVERITIES
        ):
            record["issues"].append("malformed final-check entry in .spark")
            record["final_checks_well_formed"] = False
            continue
        message = check.get("message")
        if message is None:
            message_text = ""
        elif isinstance(message, dict) and isinstance(message.get("text", ""), str):
            message_text = message.get("text", "")
        elif isinstance(message, str):
            message_text = message
        else:
            message_text = ""
            record["issues"].append("malformed final-check message in .spark")
            record["final_checks_well_formed"] = False
        file_name = check.get("check_file") or check.get("file")
        line = check.get("check_line", check.get("line"))
        column = check.get("check_col", check.get("col"))
        location_valid = _has_location(
            {"file": file_name, "line": line, "column": column}
        )
        if not location_valid:
            record["issues"].append("final check is missing valid location metadata")
            record["final_checks_well_formed"] = False
        unproved_status = check.get("unproved_status")
        if unproved_status is not None and not isinstance(unproved_status, dict):
            record["issues"].append("malformed final-check unproved_status in .spark")
            record["final_checks_well_formed"] = False
        item = {
            "severity": check["severity"],
            "file": file_name,
            "line": line,
            "column": column,
            "location_valid": location_valid,
            "message": message_text,
            "unproved_status": unproved_status,
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
            yield file_name, mutant


def _killed_by(mutant):
    killed_by = mutant.get("killedBy")
    if not isinstance(killed_by, list) or not all(isinstance(item, str) for item in killed_by):
        return None
    if any(item == "proof" or item.startswith("proof:") for item in killed_by):
        return PROOF_KILLED
    if killed_by:
        return "other"
    return None


def _proof_dependent(mutant):
    status = mutant.get("status")
    if status == "Killed":
        return _killed_by(mutant) == PROOF_KILLED
    if status == "Survived":
        return True
    if status == "NoCoverage":
        if _killed_by(mutant) == PROOF_KILLED:
            return True
        reason = mutant.get("statusReason")
        return (
            not isinstance(reason, str)
            or reason.strip().casefold() != "no test executes this code"
        )
    return False


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
            if _proof_dependent(mutant):
                removed += 1
            else:
                kept.append(mutant)
        file_data["mutants"] = kept
    _write_json(destination, filtered)
    print(f"filtered {removed} proof-dependent baseline entries; original left unchanged")
    return 0


def _empty_result():
    return {
        "proofKilled": 0,
        "proofDependent": 0,
        "confirmed": 0,
        "validated": 0,
        "blocked": 0,
        "judgements": [],
    }


def _selected_unit(file_name):
    return file_name.replace("\\", "/").rsplit("/", 1)[-1]


def _validate_evidence(path, evidence, mutant_id, file_name, created_at_ns):
    expected_unit = _selected_unit(file_name)
    started = evidence.get("startedAtNs")
    if evidence.get("schemaVersion") != SCHEMA_VERSION or evidence.get("mutantId") != mutant_id:
        raise ValueError("malformed or mismatched mutant evidence")
    if type(started) is not int or started < created_at_ns:
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

    units = evidence.get("units")
    if not isinstance(units, list) or not units:
        raise ValueError("mutant evidence has no selected-unit checks")
    if any(not isinstance(unit, dict) or not isinstance(unit.get("unit"), str) for unit in units):
        raise ValueError("mutant evidence has malformed selected-unit metadata")
    selected = [unit for unit in units if unit["unit"] == expected_unit]
    if len(selected) != 1:
        raise ValueError(f"expected one fresh proof record for selected unit {expected_unit}, found {len(selected)}")
    unit = selected[0]
    spark_path = unit.get("spark_path")
    if (
        unit.get("spark_fresh") is not True
        or type(unit.get("spark_mtime_ns")) is not int
        or unit["spark_mtime_ns"] < started
        or not isinstance(spark_path, str)
        or pathlib.Path(spark_path).name != pathlib.Path(expected_unit).stem + ".spark"
    ):
        raise ValueError("mutant evidence has missing, malformed, or stale selected-unit .spark data")
    issues = unit.get("issues")
    if not isinstance(issues, list) or not all(isinstance(issue, str) for issue in issues):
        raise ValueError("mutant evidence has malformed selected-unit issues")
    if unit.get("final_checks_well_formed") is not True:
        detail = "; ".join(issues) if issues else "malformed final-check entry or location metadata"
        raise ValueError(detail)
    if (
        not isinstance(unit.get("checks"), list)
        or not isinstance(unit.get("confirmed_high_checks"), list)
    ):
        raise ValueError("mutant evidence has malformed selected-unit final checks")
    checks = unit["checks"]
    if not checks:
        raise ValueError("selected unit has no final proof checks")
    for check in checks:
        if (
            not isinstance(check, dict)
            or not isinstance(check.get("severity"), str)
            or check["severity"] not in FINAL_CHECK_SEVERITIES
            or check.get("location_valid") is not True
            or not _has_location(check)
            or not isinstance(check.get("message"), str)
            or (
                check.get("unproved_status") is not None
                and not isinstance(check["unproved_status"], dict)
            )
        ):
            raise ValueError("malformed final-check entry or missing location metadata")

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
    return exit_code, unit, diagnostics


def _validate_report(report_path, evidence_dir, minimum_mtime_ns):
    failures = []
    result = _empty_result()
    evidence_dir = pathlib.Path(evidence_dir)
    manifest_path = evidence_dir / "manifest.json"
    try:
        manifest = _load_json(manifest_path)
        if not isinstance(manifest, dict):
            raise ValueError("malformed evidence manifest")
        if manifest.get("schemaVersion") != SCHEMA_VERSION or type(manifest.get("createdAtNs")) is not int:
            raise ValueError("malformed evidence manifest")
    except ValueError as error:
        return False, [str(error)], result

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
        return False, [str(error)], result

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

    required = []
    judgements = result["judgements"]
    for file_name, mutant in mutants:
        status = mutant["status"]
        killing_method = _killed_by(mutant)
        if status == "Killed" and killing_method is None:
            reason = "missing or malformed killedBy in raw report"
            failures.append(f"mutant {mutant['id']} ({file_name}): {reason}")
            judgements.append(
                {"id": str(mutant["id"]), "file": file_name, "status": "Inconclusive", "reason": reason}
            )
            result["blocked"] += 1
            continue
        if not _proof_dependent(mutant):
            continue
        result["proofDependent"] += 1
        if status == "Killed" and killing_method == PROOF_KILLED:
            result["proofKilled"] += 1
        required.append((file_name, mutant))

    for file_name, mutant in required:
        mutant_id = str(mutant["id"])
        records = by_id.get(mutant_id, [])
        reason = None
        if not records:
            reason = "missing fresh selected-unit GNATprove evidence"
        else:
            try:
                matching = []
                malformed_units = False
                expected_unit = _selected_unit(file_name)
                for path, evidence in records:
                    units = evidence.get("units")
                    if not isinstance(units, list):
                        malformed_units = True
                        continue
                    if any(not isinstance(unit, dict) or not isinstance(unit.get("unit"), str) for unit in units):
                        malformed_units = True
                        continue
                    if any(unit["unit"] == expected_unit for unit in units):
                        matching.append((path, evidence))
                if malformed_units:
                    raise ValueError("mutant evidence has malformed selected-unit metadata")
                if len(matching) != 1:
                    raise ValueError(
                        f"expected one fresh evidence record for selected unit {expected_unit}, found {len(matching)}"
                    )
                path, evidence = matching[0]
                exit_code, unit, diagnostics = _validate_evidence(
                    path, evidence, mutant_id, file_name, manifest["createdAtNs"]
                )
                status = mutant["status"]
                if status == "Killed":
                    if exit_code == 0:
                        raise ValueError("proof-killed result has a successful GNATprove exit")
                    high = any(
                        check["severity"] == "high"
                        or (
                            check["severity"] != "info"
                            and any(_matches_diagnostic(check, diagnostic) for diagnostic in diagnostics)
                        )
                        for check in unit["checks"]
                    )
                    if not high:
                        issues = unit["issues"]
                        detail = "; ".join(issues) if issues else "no confirmed high-severity counterexample"
                        raise ValueError(f"proof-killed result is inconclusive ({detail})")
                    result["confirmed"] += 1
                    print(f"mutant {mutant_id}: confirmed high-severity counterexample; raw Killed result retained")
                else:
                    if exit_code != 0:
                        raise ValueError(f"GNATprove exited with status {exit_code}")
                    unproved = [check for check in unit["checks"] if check["severity"] != "info"]
                    if unproved:
                        check = unproved[0]
                        raise ValueError(
                            "selected-unit final check is not proved "
                            f"({check['severity']} at {check['file']}:{check['line']}:{check['column']})"
                        )
                    if unit["issues"]:
                        raise ValueError("selected-unit proof evidence has issues: " + "; ".join(unit["issues"]))
                    result["validated"] += 1
            except (KeyError, OSError, TypeError, ValueError) as error:
                reason = str(error)

        if reason is not None:
            failures.append(f"mutant {mutant_id} ({file_name}): {reason}")
            judgements.append(
                {"id": mutant_id, "file": file_name, "status": "Inconclusive", "reason": reason}
            )
            result["blocked"] += 1

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
