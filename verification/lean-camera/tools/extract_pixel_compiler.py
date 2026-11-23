#!/usr/bin/env python3
"""Extract the Pixel_At scalar expression from GNAT 16.1 raw trees."""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
SPEC = ROOT / "optional/aravis/src/amv-spec-gige_vision.ads"
TYPES = ROOT / "optional/aravis/src/amv-gige_vision_types.ads"
POLICY = Path(__file__).with_name("ghost-check.adc")
OUTPUT = ROOT / "verification/lean-camera/CameraLifecycle/Grab/CompilerGenerated.lean"
EXPECTED_VERSION = "gcc (GNAT-FSF-builds) 16.1.0"
EXPECTED_TARGET = "x86_64-pc-linux-gnu"


class ExtractionError(RuntimeError):
    pass


def run(command: list[str], *, cwd: Path, output: Path | None = None) -> str:
    result = subprocess.run(command, cwd=cwd, text=True, capture_output=True)
    text = result.stdout + result.stderr
    if result.returncode:
        raise ExtractionError(f"command failed ({result.returncode}): {' '.join(command)}\n{text}")
    if output is not None:
        output.write_text(text)
    return text


def compiler() -> tuple[str, str, str]:
    cc = os.environ.get("GNAT_CC", shutil.which("gcc") or "")
    if not cc:
        raise ExtractionError("GNAT_CC/gcc not found")
    version = run([cc, "--version"], cwd=ROOT).splitlines()[0]
    target = run([cc, "-dumpmachine"], cwd=ROOT).strip()
    validate_compiler_output(version, target)
    return cc, version, target


def validate_compiler_output(version: str, target: str) -> None:
    if version != EXPECTED_VERSION or target != EXPECTED_TARGET:
        raise ExtractionError(f"unsupported compiler/target: {version}; {target}")


def parse_standard_types(text: str) -> tuple[int, int, int, int]:
    integer = re.search(
        r"type Integer is range -\(2 \*\*(\d+)\) \.\. \+\(2 \*\*(\d+) - 1\);", text
    )
    natural = re.search(r"subtype Natural\s+is Integer range 0 \.\. Integer'Last;", text)
    positive = re.search(r"subtype Positive\s+is Integer range 1 \.\. Integer'Last;", text)
    if not integer or integer.group(1) != integer.group(2) or not natural or not positive:
        raise ExtractionError("GNAT -gnatS output did not expose Integer, Natural, and Positive ranges")
    bits = int(integer.group(1))
    return -(1 << bits), (1 << bits) - 1, 0, (1 << bits) - 1


def parse_function_tree(text: str) -> tuple[str, dict[int, dict[str, str]]]:
    lines = text.splitlines()
    starts = [i for i, line in enumerate(lines) if "amv.spec.gige_vision.pixel_at (" in line]
    if len(starts) != 1:
        raise ExtractionError(f"expected one compiler Pixel_At tree, found {len(starts)}")
    start = starts[0]
    end = next((i for i in range(start + 1, len(lines))
                if lines[i] and not lines[i][0].isspace() and not lines[i].startswith("@")), len(lines))
    block = lines[start:end]
    nodes: dict[int, dict[str, str]] = {}
    current: int | None = None
    for line in block:
        match = re.match(r"^@(\d+)\s+(\w+)\s*(.*)$", line)
        if match:
            current = int(match.group(1))
            nodes[current] = {"kind": match.group(2), "text": match.group(3)}
        elif current is not None:
            nodes[current]["text"] += " " + line.strip()
    if not nodes:
        raise ExtractionError("selected Pixel_At tree has no GCC nodes")
    return block[0], nodes


def fields(node: dict[str, str]) -> dict[str, str]:
    result: dict[str, str] = {}
    text = node["text"]
    for name, value in re.findall(r"([A-Za-z][A-Za-z0-9]*(?:\s+\d+)?)\s*:\s*@([0-9]+)", text):
        result[name.strip()] = value
    return result


def integer_constant(nodes: dict[int, dict[str, str]], node_id: int) -> int:
    node = nodes[node_id]
    if node["kind"] != "integer_cst":
        raise ExtractionError(f"expected compiler integer constant at @{node_id}")
    match = re.search(r"\bint:\s*(-?\d+)", node["text"])
    if not match:
        raise ExtractionError(f"unrecognized integer constant at @{node_id}")
    return int(match.group(1))


def identifier(nodes: dict[int, dict[str, str]], node_id: int | None) -> str:
    if node_id is None:
        raise ExtractionError("missing compiler identifier")
    node = nodes[node_id]
    if node["kind"] in {"type_decl", "field_decl", "parm_decl", "var_decl", "function_decl"}:
        name_ref = fields(node).get("name")
        if name_ref:
            return identifier(nodes, int(name_ref))
    if node["kind"] != "identifier_node":
        raise ExtractionError(f"expected compiler identifier, got @{node_id} ({node['kind']})")
    match = re.search(r"\bstrg:\s*([^\s]+)", node["text"])
    if not match:
        raise ExtractionError(f"identifier @{node_id} has no name")
    return match.group(1)


def type_name(nodes: dict[int, dict[str, str]], type_id: int) -> str:
    node = nodes[type_id]
    if node["kind"] not in {"integer_type", "enumeral_type", "boolean_type"}:
        raise ExtractionError(f"unsupported operand type node {node['kind']} at @{type_id}")
    ref = fields(node).get("name")
    return identifier(nodes, int(ref)) if ref else node["kind"]


def type_tag(nodes: dict[int, dict[str, str]], type_id: int) -> str:
    name = type_name(nodes, type_id).lower()
    tags = {
        "amv__kernels__tint64b": ("int64", 64),
        "amv__gige_vision_types__int64": ("int64", 64),
        "amv__gige_vision_types__int32": ("int32", 32),
        "integer": ("integer", 32),
        "natural": ("natural", 32),
        "positive": ("positive", 32),
    }
    if name not in tags:
        raise ExtractionError(f"unrecognized selected scalar type {name} at @{type_id}")
    tag, precision = tags[name]
    node = nodes[type_id]
    prec = re.search(r"\bprec:\s*(\d+)", node["text"])
    sign = re.search(r"\bsign:\s*(signed|unsigned)", node["text"])
    size = fields(node).get("size")
    bounds = type_bounds(nodes, type_id)
    if (node["kind"] != "integer_type" or not prec or int(prec.group(1)) != precision
            or not sign or sign.group(1) != "signed" or size is None
            or integer_constant(nodes, int(size)) != precision
            or bounds != (-(1 << (precision - 1)), (1 << (precision - 1)) - 1)):
        raise ExtractionError(f"compiler scalar type {name} at @{type_id} has unexpected sign/precision/range")
    return tag


def validate_unsigned_type(nodes: dict[int, dict[str, str]], type_id: int, precision: int) -> None:
    node = nodes[type_id]
    details = node["text"]
    if (node["kind"] != "integer_type" or not re.search(rf"\bprec:\s*{precision}\b", details)
            or not re.search(r"\bsign:\s*unsigned\b", details)
            or integer_constant(nodes, int(fields(node)["size"])) != precision
            or type_bounds(nodes, type_id) != (0, -1)):
        raise ExtractionError(f"unexpected compiler unsigned index type at @{type_id}")


def type_bounds(nodes: dict[int, dict[str, str]], type_id: int) -> tuple[int, int]:
    node = nodes[type_id]
    refs = fields(node)
    if node["kind"] != "integer_type" or "min" not in refs or "max" not in refs:
        raise ExtractionError(f"missing integer bounds at type node @{type_id}")
    return integer_constant(nodes, int(refs["min"])), integer_constant(nodes, int(refs["max"]))


def root_parameter(nodes: dict[int, dict[str, str]], node_id: int,
                   active: frozenset[int] = frozenset()) -> str:
    if node_id in active:
        raise ExtractionError(f"cyclic compiler parameter reference at @{node_id}")
    node = nodes[node_id]
    if node["kind"] == "parm_decl":
        return identifier(nodes, int(fields(node)["name"])).lower()
    if node["kind"] in {"indirect_ref", "nop_expr", "save_expr", "component_ref"}:
        operand = fields(node).get("op 0")
        if operand is None:
            raise ExtractionError(f"{node['kind']} has no base operand at @{node_id}")
        return root_parameter(nodes, int(operand), active | {node_id})
    raise ExtractionError(f"unsupported compiler frame base node {node['kind']} at @{node_id}")


def frame_record_type(nodes: dict[int, dict[str, str]], function_id: int,
                      frame_parameter_id: int) -> int:
    parameter = nodes[frame_parameter_id]
    if parameter["kind"] != "parm_decl" \
            or identifier(nodes, ref(nodes, frame_parameter_id, "name")).lower() != "frame" \
            or fields(parameter).get("scpe") != str(function_id):
        raise ExtractionError(
            f"compiler frame parameter @{frame_parameter_id} has unexpected identity or scope"
        )
    parameter_type = ref(nodes, frame_parameter_id, "type")
    expect_kind(nodes, parameter_type, "reference_type")
    record_type = ref(nodes, parameter_type, "refd")
    expect_kind(nodes, record_type, "record_type")
    return record_type


def direct_frame_field(nodes: dict[int, dict[str, str]], component_id: int,
                       function_id: int, frame_parameter_id: int,
                       allowed_fields: set[str]) -> str:
    record_type = frame_record_type(nodes, function_id, frame_parameter_id)
    expect_kind(nodes, component_id, "component_ref")
    field_id = ref(nodes, component_id, "op 1")
    expect_kind(nodes, field_id, "field_decl")
    field = identifier(nodes, field_id).lower()
    if field not in allowed_fields:
        raise ExtractionError(f"unexpected selected frame field {field} at @{component_id}")
    if fields(nodes[field_id]).get("scpe") != str(record_type):
        raise ExtractionError(f"selected {field} field does not belong to the frame parameter type")
    base_id = ref(nodes, component_id, "op 0")
    expect_kind(nodes, base_id, "indirect_ref")
    if ref(nodes, base_id, "op 0") != frame_parameter_id \
            or ref(nodes, base_id, "type") != record_type:
        raise ExtractionError(
            f"selected {field} field is not a direct field of the actual Pixel_At frame parameter"
        )
    if ref(nodes, component_id, "type") != ref(nodes, field_id, "type"):
        raise ExtractionError(f"compiler field type differs from selected expression @{component_id}")
    return field


def parse_expr(nodes: dict[int, dict[str, str]], node_id: int, natural_max: int,
               active: frozenset[int] = frozenset(), *, function_id: int | None = None,
               frame_parameter_id: int | None = None) -> tuple[str, frozenset[str], str]:
    if node_id in active:
        raise ExtractionError(f"cyclic compiler expression at @{node_id}")
    node = nodes[node_id]
    refs = fields(node)
    kind = node["kind"]
    active = active | {node_id}
    if kind in {"nop_expr", "save_expr", "indirect_ref"}:
        child = refs.get("op 0")
        if child is None:
            raise ExtractionError(f"{kind} has no operand at @{node_id}")
        expr, support, child_type = parse_expr(
            nodes, int(child), natural_max, active, function_id=function_id,
            frame_parameter_id=frame_parameter_id,
        )
        target_type_id = refs.get("type")
        if target_type_id is None:
            raise ExtractionError(f"{kind} has no resolved type at @{node_id}")
        target = type_tag(nodes, int(target_type_id))
        if kind == "nop_expr" and target != child_type:
            return f".cast .{target} ({expr})", support, target
        if kind != "nop_expr" and target != child_type:
            raise ExtractionError(f"unexpected {kind} type change at @{node_id}")
        return expr, support, child_type
    if kind == "var_decl":
        name = identifier(nodes, int(refs["name"]))
        init = refs.get("init")
        if not init:
            raise ExtractionError(f"unsupported compiler variable {name}")
        expr, support, source_type = parse_expr(
            nodes, int(init), natural_max, active, function_id=function_id,
            frame_parameter_id=frame_parameter_id,
        )
        target = type_tag(nodes, int(refs["type"]))
        if source_type != target:
            raise ExtractionError(f"compiler variable {name} type differs from its initializer")
        return expr, support, target
    if kind == "parm_decl":
        name = identifier(nodes, int(refs["name"])).lower()
        if name not in {"x", "y"} or type_tag(nodes, int(refs["type"])) != "natural":
            raise ExtractionError(f"unexpected Pixel_At scalar parameter {name}")
        return f".{name}", frozenset({name}), "natural"
    if kind == "component_ref":
        if function_id is None or frame_parameter_id is None:
            raise ExtractionError("selected frame field has no scoped Pixel_At parameter context")
        field = direct_frame_field(
            nodes, node_id, function_id, frame_parameter_id, {"width", "height", "byte_count"}
        )
        target = type_tag(nodes, int(refs["type"]))
        return f".{field}", frozenset({field}), target
    if kind == "integer_cst":
        value = integer_constant(nodes, node_id)
        target = type_tag(nodes, int(refs["type"]))
        return f".literal {value}", frozenset(), target
    if kind in {"plus_expr", "mult_expr"}:
        left, ls, left_type = parse_expr(
            nodes, int(refs["op 0"]), natural_max, active, function_id=function_id,
            frame_parameter_id=frame_parameter_id,
        )
        right, rs, right_type = parse_expr(
            nodes, int(refs["op 1"]), natural_max, active, function_id=function_id,
            frame_parameter_id=frame_parameter_id,
        )
        target = type_tag(nodes, int(refs["type"]))
        if left_type != target or right_type != target:
            raise ExtractionError(f"compiler arithmetic operand type mismatch at @{node_id}")
        op = "add" if kind == "plus_expr" else "mul"
        return f".{op} .{target} ({left}) ({right})", ls | rs, target
    raise ExtractionError(f"unsupported compiler expression node {kind} at @{node_id}")


def ref(nodes: dict[int, dict[str, str]], node_id: int, key: str) -> int:
    value = fields(nodes[node_id]).get(key)
    if value is None or int(value) not in nodes:
        raise ExtractionError(f"missing {key} in compiler node @{node_id}")
    return int(value)


def selected_expression_node_ids(nodes: dict[int, dict[str, str]], root: int) -> list[int]:
    output: list[int] = []
    visited: set[int] = set()

    def visit(node_id: int) -> None:
        if node_id in visited:
            return
        node = nodes[node_id]
        kind = node["kind"]
        allowed = {"plus_expr", "mult_expr", "nop_expr", "component_ref", "indirect_ref",
                   "parm_decl", "field_decl", "integer_cst"}
        if kind not in allowed:
            raise ExtractionError(f"unsupported selected-expression provenance node {kind} at @{node_id}")
        visited.add(node_id)
        output.append(node_id)
        refs = fields(node)
        if "type" in refs:
            output.append(int(refs["type"]))
        if kind in {"parm_decl", "field_decl"} and "name" in refs:
            output.append(int(refs["name"]))
        for key in ("op 0", "op 1"):
            if key in refs and kind not in {"parm_decl", "field_decl", "integer_cst"}:
                visit(int(refs[key]))

    visit(root)
    return output


def expect_kind(nodes: dict[int, dict[str, str]], node_id: int, kind: str) -> None:
    if nodes[node_id]["kind"] != kind:
        raise ExtractionError(f"expected {kind} at compiler node @{node_id}, got {nodes[node_id]['kind']}")


def statement_items(nodes: dict[int, dict[str, str]], node_id: int) -> list[int]:
    expect_kind(nodes, node_id, "statement_list")
    entries = [(int(position), int(value)) for position, value in
               re.findall(r"(\d+)\s*:\s*@([0-9]+)", nodes[node_id]["text"])]
    if [position for position, _ in entries] != list(range(len(entries))):
        raise ExtractionError(f"unsupported compiler statement sequence at @{node_id}")
    return [value for _, value in entries]


def check_name(nodes: dict[int, dict[str, str]], call_id: int) -> str:
    expect_kind(nodes, call_id, "call_expr")
    fn = ref(nodes, call_id, "fn")
    target = ref(nodes, fn, "op 0") if nodes[fn]["kind"] == "addr_expr" else fn
    expect_kind(nodes, target, "function_decl")
    return identifier(nodes, target)


def selected_return_path(nodes: dict[int, dict[str, str]], function_id: int
                         ) -> tuple[int, int, list[tuple[int, int, int]], list[int]]:
    returns: list[int] = []
    conditions: list[tuple[int, int, int]] = []
    paths: dict[int, list[tuple[int, int, int]]] = {}

    def visit(node_id: int, path: list[tuple[int, int, int]], active: frozenset[int]) -> None:
        if node_id in active:
            raise ExtractionError(f"cyclic compiler statement path at @{node_id}")
        active = active | {node_id}
        kind = nodes[node_id]["kind"]
        if kind == "return_expr":
            returns.append(node_id)
            paths[node_id] = path
        elif kind == "bind_expr":
            visit(ref(nodes, node_id, "body"), path, active)
        elif kind == "statement_list":
            for child in statement_items(nodes, node_id):
                visit(child, path, active)
        elif kind == "cond_expr":
            for branch in (1, 2):
                child = ref(nodes, node_id, f"op {branch}")
                if nodes[child]["kind"] == "call_expr":
                    conditions.append((node_id, branch, child))
                else:
                    visit(child, path + [(node_id, branch, child)], active)
        elif kind == "call_expr":
            raise ExtractionError(f"unhandled unconditional compiler call @{node_id}")
        elif kind != "decl_expr":
            raise ExtractionError(f"unhandled compiler statement path {kind} at @{node_id}")

    visit(ref(nodes, function_id, "body"), [], frozenset())
    all_returns = {i for i, node in nodes.items() if node["kind"] == "return_expr"}
    if len(returns) != 4 or len(set(returns)) != 4 or all_returns != set(returns):
        raise ExtractionError(f"unhandled Pixel_At return paths: {returns}")
    byte_returns = []
    for return_id in returns:
        expr_id = ref(nodes, return_id, "expr")
        expect_kind(nodes, expr_id, "init_expr")
        target = ref(nodes, expr_id, "op 0")
        expect_kind(nodes, target, "result_decl")
        value = ref(nodes, expr_id, "op 1")
        if nodes[value]["kind"] == "array_ref":
            byte_returns.append((return_id, value))
        elif integer_constant(nodes, value) != 0:
            raise ExtractionError(f"unhandled nonzero fallback return @{return_id}")
    if len(byte_returns) != 1:
        raise ExtractionError(f"expected one selected byte-array return, got {byte_returns}")
    byte_return, array_id = byte_returns[0]
    all_arrays = {i for i, node in nodes.items() if node["kind"] == "array_ref"}
    if all_arrays != {array_id}:
        raise ExtractionError(f"unhandled Pixel_At array return paths: {sorted(all_arrays)}")
    guard_conditions = []
    for cond_id, branch, _ in paths[byte_return]:
        if branch != 2:
            raise ExtractionError(f"selected byte return is not on a false/else guard path @{cond_id}")
        opposite = ref(nodes, cond_id, f"op {3 - branch}")
        if nodes[opposite]["kind"] == "call_expr":
            raise ExtractionError(f"selected byte return bypasses an error path @{cond_id}")
        if any(return_id != byte_return and return_id in paths
               and (cond_id, 3 - branch, opposite) in paths[return_id] for return_id in returns):
            guard_conditions.append(cond_id)
    if len(guard_conditions) != 3:
        raise ExtractionError(f"unhandled fallback guard paths: {guard_conditions}")
    return byte_return, array_id, conditions, guard_conditions


def check_branch(nodes: dict[int, dict[str, str]], cond_id: int, name: str) -> int:
    expect_kind(nodes, cond_id, "cond_expr")
    true_branch = ref(nodes, cond_id, "op 1")
    false_branch = ref(nodes, cond_id, "op 2")
    if check_name(nodes, true_branch) != f"__gnat_rcheck_CE_{name}":
        raise ExtractionError(f"compiler {name} check has wrong branch/orientation at @{cond_id}")
    if statement_items(nodes, false_branch):
        raise ExtractionError(f"compiler {name} check does not continue on false at @{cond_id}")
    return true_branch


def verify_bound(nodes: dict[int, dict[str, str]], node_id: int, field: str) -> None:
    expect_kind(nodes, node_id, "var_decl")
    if type_tag(nodes, ref(nodes, node_id, "type")) != "integer":
        raise ExtractionError(f"array bound @{node_id} is not an Integer")
    base = ref(nodes, node_id, "init")
    for wrapper in ("nop_expr", "save_expr"):
        expect_kind(nodes, base, wrapper)
        type_tag(nodes, ref(nodes, base, "type"))
        base = ref(nodes, base, "op 0")
    expect_kind(nodes, base, "component_ref")
    if identifier(nodes, ref(nodes, base, "op 1")) != field \
            or root_parameter(nodes, ref(nodes, base, "op 0")) != "frame":
        raise ExtractionError(f"array bound @{node_id} does not reference {field}")
    type_tag(nodes, ref(nodes, base, "type"))


def verify_comparison(nodes: dict[int, dict[str, str]], node_id: int, kind: str,
                      left: int, right: int) -> None:
    expect_kind(nodes, node_id, kind)
    if ref(nodes, node_id, "op 0") != left or ref(nodes, node_id, "op 1") != right:
        raise ExtractionError(f"compiler check operands/orientation changed at @{node_id}")


def verify_range(nodes: dict[int, dict[str, str]], cond_id: int, row_id: int,
                 natural_min: int, natural_max: int) -> int:
    check = check_branch(nodes, cond_id, "Range_Check")
    predicate = ref(nodes, cond_id, "op 0")
    expect_kind(nodes, predicate, "truth_orif_expr")
    for comparison, kind, bound in ((ref(nodes, predicate, "op 0"), "lt_expr", natural_min),
                                    (ref(nodes, predicate, "op 1"), "gt_expr", natural_max)):
        expect_kind(nodes, comparison, kind)
        if ref(nodes, comparison, "op 0") != row_id \
                or integer_constant(nodes, ref(nodes, comparison, "op 1")) != bound:
            raise ExtractionError(f"compiler Natural check predicate changed at @{cond_id}")
        if type_tag(nodes, ref(nodes, ref(nodes, comparison, "op 1"), "type")) != "int64":
            raise ExtractionError("compiler Natural check bound is not Int64")
    return check


def parse_predicate(nodes: dict[int, dict[str, str]], node_id: int, natural_max: int,
                    function_id: int, frame_parameter_id: int) -> str:
    node = nodes[node_id]
    refs = fields(node)
    if node["kind"] == "eq_expr":
        left, _, _ = parse_expr(
            nodes, int(refs["op 0"]), natural_max, function_id=function_id,
            frame_parameter_id=frame_parameter_id,
        )
        right, _, _ = parse_expr(
            nodes, int(refs["op 1"]), natural_max, function_id=function_id,
            frame_parameter_id=frame_parameter_id,
        )
        return f".equal ({left}) ({right})"
    raise ExtractionError(f"unsupported compiler check predicate node {node['kind']} at @{node_id}")


def check_calls(nodes: dict[int, dict[str, str]]) -> list[tuple[int, str]]:
    functions: dict[int, str] = {}
    for node_id, node in nodes.items():
        if node["kind"] == "function_decl":
            name_ref = fields(node).get("name")
            if name_ref:
                functions[node_id] = identifier(nodes, int(name_ref))
    found: list[tuple[int, str]] = []
    for node_id, node in nodes.items():
        if node["kind"] != "call_expr":
            continue
        fn = fields(node).get("fn")
        if fn is None:
            raise ExtractionError("call expression without resolved function")
        target = nodes[int(fn)]
        if target["kind"] == "addr_expr":
            target_ref = fields(target).get("op 0")
            target_id = int(target_ref) if target_ref else -1
        else:
            target_id = int(fn)
        name = functions.get(target_id)
        if name and name.startswith("__gnat_rcheck_CE_"):
            found.append((node_id, name.removeprefix("__gnat_rcheck_CE_")))
    allowed = {"Range_Check", "Overflow_Check", "Index_Check", "Access_Check", "Invalid_Data"}
    unknown = {name for _, name in found} - allowed
    if unknown:
        raise ExtractionError(f"unknown GNAT runtime check calls: {sorted(unknown)}")
    if not {"Range_Check", "Overflow_Check", "Index_Check"} <= {name for _, name in found}:
        raise ExtractionError(f"required compiler check calls missing: {found}")
    return found


def lean_int(value: int) -> str:
    return f"({value} : Int)"


def ada_integer(text: str) -> int:
    value = text.strip().replace("_", "")
    based = re.fullmatch(r"(\d+)#([0-9A-Fa-f]+)#", value)
    if based:
        return int(based.group(2), int(based.group(1)))
    if re.fullmatch(r"-?\d+", value):
        return int(value)
    raise ExtractionError(f"unrecognized GNAT integer literal {text!r}")


def generate(raw: str, standard: str, expanded: str,
             source_name: str = "amv-spec-gige_vision.ads",
             compiler_version: str = EXPECTED_VERSION,
             compiler_target: str = EXPECTED_TARGET) -> str:
    integer_min, integer_max, natural_min, natural_max = parse_standard_types(standard)
    if natural_min != 0 or integer_max != natural_max:
        raise ExtractionError("compiler Standard Integer and Natural bounds disagree")
    header, nodes = parse_function_tree(raw)
    function_ids = [node_id for node_id, node in nodes.items() if node["kind"] == "function_decl"
                    and identifier(nodes, int(fields(node)["name"])) == "amv__spec__gige_vision__pixel_at"]
    if len(function_ids) != 1:
        raise ExtractionError(f"expected one compiler Pixel_At function, found {len(function_ids)}")
    function_id = function_ids[0]
    srcp = re.search(r"srcp:\s*([^\s]+)", nodes[function_id]["text"])
    if not srcp or Path(srcp.group(1).split(":", 1)[0]).name != source_name:
        raise ExtractionError("selected compiler function has unexpected source-file provenance")
    normalized_header = re.sub(r"\s+", " ", header)
    if not re.search(r"\bnatural x, natural y\b", normalized_header):
        raise ExtractionError("compiler-resolved Pixel_At parameters are not Natural x/y")
    parameters = [node_id for node_id, node in nodes.items() if node["kind"] == "parm_decl"
                  and fields(node).get("scpe") == str(function_id)]
    parameter_names = {identifier(nodes, ref(nodes, node_id, "name")).lower(): node_id for node_id in parameters}
    if set(parameter_names) != {"frame", "x", "y"} or len(parameter_names) != 3:
        raise ExtractionError("compiler Pixel_At parameter declarations changed")
    frame_parameter_id = parameter_names["frame"]
    frame_record_type(nodes, function_id, frame_parameter_id)
    for name in ("x", "y"):
        node_id = parameter_names[name]
        if type_tag(nodes, ref(nodes, node_id, "type")) != "natural":
            raise ExtractionError(f"Pixel_At scalar parameter @{node_id} is not Natural")

    byte_return, array_id, conditions, guard_conditions = selected_return_path(nodes, function_id)
    array_base = ref(nodes, array_id, "op 0")
    expect_kind(nodes, array_base, "indirect_ref")
    array_type = ref(nodes, array_base, "type")
    expect_kind(nodes, array_type, "array_type")
    array_name = identifier(nodes, ref(nodes, array_type, "name")).lower()
    if not array_name.startswith("amv__gige_vision_types__byte_array"):
        raise ExtractionError(f"selected return has unexpected array type {array_name}")
    validate_unsigned_type(nodes, ref(nodes, array_id, "type"), 8)
    if ref(nodes, array_type, "elts") != ref(nodes, array_id, "type"):
        raise ExtractionError("selected array element type differs from returned Pixel type")
    domain_type = ref(nodes, array_type, "domn")
    domain_details = nodes[domain_type]["text"]
    if (nodes[domain_type]["kind"] != "integer_type"
            or not re.search(r"\bprec:\s*64\b", domain_details)
            or not re.search(r"\bsign:\s*signed\b", domain_details)
            or integer_constant(nodes, int(fields(nodes[domain_type])["size"])) != 64):
        raise ExtractionError("compiler byte-array index representation has unexpected signedness/range")
    domain_min_id, domain_max_id = ref(nodes, domain_type, "min"), ref(nodes, domain_type, "max")
    for bound_expr in (domain_min_id, domain_max_id):
        validate_unsigned_type(nodes, ref(nodes, bound_expr, "type"), 64)
    base_component = ref(nodes, array_base, "op 0")
    expect_kind(nodes, base_component, "component_ref")
    pointer_type = ref(nodes, base_component, "type")
    if nodes[pointer_type]["kind"] != "pointer_type" \
            or identifier(nodes, ref(nodes, base_component, "op 1")).lower() != "p_array":
        raise ExtractionError("selected array reference is not the compiler Bytes access component")
    bytes_component = ref(nodes, base_component, "op 0")
    expect_kind(nodes, bytes_component, "component_ref")
    if identifier(nodes, ref(nodes, bytes_component, "op 1")).lower() != "bytes" \
            or root_parameter(nodes, ref(nodes, bytes_component, "op 0")) != "frame":
        raise ExtractionError("selected returned array is not rooted at Pixel_At Frame.Bytes")

    raw_index = ref(nodes, array_id, "op 1")
    expect_kind(nodes, raw_index, "nop_expr")
    raw_index_type = ref(nodes, raw_index, "type")
    validate_unsigned_type(nodes, raw_index_type, 64)
    raw_index_precision = int(re.search(r"\bprec:\s*(\d+)", nodes[raw_index_type]["text"]).group(1))
    array_index_max = (1 << raw_index_precision) - 1
    raw_index_value = ref(nodes, raw_index, "op 0")
    expect_kind(nodes, raw_index_value, "plus_expr")
    if type_tag(nodes, ref(nodes, raw_index_value, "type")) != "integer":
        raise ExtractionError("returned byte index is not computed in Integer")
    raw_index_row = ref(nodes, raw_index_value, "op 0")
    expect_kind(nodes, raw_index_row, "nop_expr")
    if type_tag(nodes, ref(nodes, raw_index_row, "type")) != "integer":
        raise ExtractionError("returned row index is not converted to Integer")
    row_temp_id = ref(nodes, raw_index_row, "op 0")
    expect_kind(nodes, row_temp_id, "var_decl")
    row_temp = identifier(nodes, ref(nodes, row_temp_id, "name"))
    row_node = ref(nodes, row_temp_id, "init")
    expect_kind(nodes, row_node, "plus_expr")
    row_expr, row_support, row_type = parse_expr(
        nodes, row_node, natural_max, function_id=function_id,
        frame_parameter_id=frame_parameter_id,
    )
    if row_type != "int64" or row_support not in {
            frozenset({"x", "y", "width"}), frozenset({"x", "y", "height"})} \
            or type_tag(nodes, ref(nodes, row_temp_id, "type")) != "int64":
        raise ExtractionError("selected returned row has unexpected operands or type")
    increment = integer_constant(nodes, ref(nodes, raw_index_value, "op 1"))
    if increment < 0 or type_tag(nodes, ref(nodes, ref(nodes, raw_index_value, "op 1"), "type")) != "integer":
        raise ExtractionError("selected returned byte index has an invalid increment")

    # Tie the checked row to the final guard immediately preceding this byte return.
    guard_cond = guard_conditions[-1]
    guard = ref(nodes, guard_cond, "op 0")
    expect_kind(nodes, guard, "ge_expr")
    guard_row_id, bound_id = ref(nodes, guard, "op 0"), ref(nodes, guard, "op 1")
    if nodes[bound_id]["kind"] == "nop_expr":
        if type_tag(nodes, ref(nodes, bound_id, "type")) != "int64":
            raise ExtractionError("Frame.Byte_Count guard conversion is not Int64")
        bound_id = ref(nodes, bound_id, "op 0")
    expect_kind(nodes, bound_id, "component_ref")
    if direct_frame_field(nodes, bound_id, function_id, frame_parameter_id,
                          {"byte_count"}) != "byte_count" \
            or type_tag(nodes, ref(nodes, bound_id, "type")) != "natural":
        raise ExtractionError("selected row guard is not compared with Frame.Byte_Count")
    guard_expr, guard_support, guard_type = parse_expr(
        nodes, guard_row_id, natural_max, function_id=function_id,
        frame_parameter_id=frame_parameter_id,
    )
    if (guard_expr, guard_support, guard_type) != (row_expr, row_support, row_type):
        raise ExtractionError("row guarded before fallback differs from returned byte index row")

    lists_with_return = [node_id for node_id, node in nodes.items()
                         if node["kind"] == "statement_list"
                         and byte_return in statement_items(nodes, node_id)]
    if len(lists_with_return) != 1:
        raise ExtractionError("ambiguous compiler statement list for selected byte return")
    selected_statements = statement_items(nodes, lists_with_return[0])
    ordered_checks = []
    for statement in selected_statements:
        if nodes[statement]["kind"] != "cond_expr":
            continue
        true_branch = ref(nodes, statement, "op 1")
        if nodes[true_branch]["kind"] == "call_expr":
            ordered_checks.append((statement, check_name(nodes, true_branch)))
    range_checks = [cond for cond, name in ordered_checks if name == "__gnat_rcheck_CE_Range_Check"]
    index_checks = [cond for cond, name in ordered_checks if name == "__gnat_rcheck_CE_Index_Check"]
    if len(range_checks) != 1 or len(index_checks) != 1:
        raise ExtractionError(f"selected return lacks unique Natural and array checks: {ordered_checks}")
    range_cond, index_cond = range_checks[0], index_checks[0]
    if selected_statements.index(range_cond) >= selected_statements.index(index_cond) \
            or selected_statements.index(index_cond) >= selected_statements.index(byte_return):
        raise ExtractionError("selected compiler check order is not Natural, array index, return")
    range_call = check_branch(nodes, range_cond, "Range_Check")
    index_call = check_branch(nodes, index_cond, "Index_Check")
    verify_range(nodes, range_cond, row_temp_id, natural_min, natural_max)

    index_predicate_node = ref(nodes, index_cond, "op 0")
    expect_kind(nodes, index_predicate_node, "truth_orif_expr")
    lower_check = ref(nodes, index_predicate_node, "op 0")
    upper_check = ref(nodes, index_predicate_node, "op 1")
    expect_kind(nodes, lower_check, "lt_expr")
    expect_kind(nodes, upper_check, "gt_expr")
    checked_value = ref(nodes, lower_check, "op 0")
    if checked_value != ref(nodes, upper_check, "op 0"):
        raise ExtractionError("array lower/upper checks do not share the checked index")
    expect_kind(nodes, checked_value, "save_expr")
    overflow_cond = ref(nodes, checked_value, "op 0")
    expect_kind(nodes, overflow_cond, "cond_expr")
    overflow_test = ref(nodes, overflow_cond, "op 0")
    expect_kind(nodes, overflow_test, "eq_expr")
    overflow_row = ref(nodes, overflow_test, "op 0")
    if nodes[overflow_row]["kind"] != "nop_expr" \
            or type_tag(nodes, ref(nodes, overflow_row, "type")) != "integer" \
            or ref(nodes, overflow_row, "op 0") != row_temp_id:
        raise ExtractionError("nested overflow test does not reference the selected row temporary")
    overflow_limit = ref(nodes, overflow_test, "op 1")
    if integer_constant(nodes, overflow_limit) != natural_max \
            or type_tag(nodes, ref(nodes, overflow_limit, "type")) != "integer":
        raise ExtractionError("nested overflow true branch has an unexpected limit")
    all_checks = check_calls(nodes)
    overflow_calls = [node_id for node_id, name in all_checks if name == "Overflow_Check"]
    if len(overflow_calls) != 1:
        raise ExtractionError(f"expected one nested increment overflow check, got {overflow_calls}")
    overflow_call = overflow_calls[0]
    overflow_true = ref(nodes, overflow_cond, "op 1")
    expect_kind(nodes, overflow_true, "compound_expr")
    if ref(nodes, overflow_true, "op 0") != overflow_call \
            or integer_constant(nodes, ref(nodes, overflow_true, "op 1")) != 0:
        raise ExtractionError("increment overflow check is not on the comparison's true branch")
    overflow_false = ref(nodes, overflow_cond, "op 2")
    expect_kind(nodes, overflow_false, "plus_expr")
    false_row, false_increment = ref(nodes, overflow_false, "op 0"), ref(nodes, overflow_false, "op 1")
    if nodes[false_row]["kind"] != "nop_expr" or ref(nodes, false_row, "op 0") != row_temp_id \
            or integer_constant(nodes, false_increment) != increment \
            or false_increment != ref(nodes, raw_index_value, "op 1"):
        raise ExtractionError("overflow false branch differs from the returned byte index expression")

    lower_bound, upper_bound = ref(nodes, lower_check, "op 1"), ref(nodes, upper_check, "op 1")
    verify_bound(nodes, lower_bound, "LB0")
    verify_bound(nodes, upper_bound, "UB0")
    verify_comparison(nodes, lower_check, "lt_expr", checked_value, lower_bound)
    verify_comparison(nodes, upper_check, "gt_expr", checked_value, upper_bound)

    # Every emitted runtime-check call must be accounted for, including pre-return guards.
    check_counts = {name: sum(kind == name for _, kind in all_checks) for name in {kind for _, kind in all_checks}}
    expected_counts = {"Access_Check": 3, "Invalid_Data": 14, "Range_Check": 3,
                       "Index_Check": 1, "Overflow_Check": 1}
    if check_counts != expected_counts:
        raise ExtractionError(f"unhandled compiler check paths: {check_counts}")
    condition_calls = {call for _, _, call in conditions}
    all_call_ids = {call for call, _ in all_checks}
    if not condition_calls <= all_call_ids or overflow_call not in all_call_ids:
        raise ExtractionError("compiler conditional contains an unrecognized runtime check")
    guard_range_calls = [call for call, kind in all_checks if kind == "Range_Check" and call != range_call]
    if len(guard_range_calls) != 2:
        raise ExtractionError("unexpected compiler range checks outside the selected Natural conversion")
    for cond_id, branch, call_id in conditions:
        name = check_name(nodes, call_id).removeprefix("__gnat_rcheck_CE_")
        check_branch(nodes, cond_id, name)
        if name == "Range_Check" and call_id != range_call:
            predicate = ref(nodes, cond_id, "op 0")
            expect_kind(nodes, predicate, "lt_expr")
            converted = ref(nodes, predicate, "op 0")
            expect_kind(nodes, converted, "var_decl")
            init = ref(nodes, converted, "init")
            expect_kind(nodes, init, "component_ref")
            direct_frame_field(nodes, init, function_id, frame_parameter_id, {"width", "height"})
            if integer_constant(nodes, ref(nodes, predicate, "op 1")) != 0:
                raise ExtractionError(f"unhandled guarded conversion check at @{cond_id}")

    predicate_blocks = re.findall(r"\[constraint_error when([^\]]*)\]", expanded, re.S)
    pseudo_checks = []
    for block in predicate_blocks:
        if row_temp not in block:
            continue
        message = re.search(r'"(range check failed|index check failed)"', block)
        if message:
            pseudo_checks.append((message.group(1), re.sub(r"\s+", " ", block[:message.start()]).strip()))
    if [kind for kind, _ in pseudo_checks] != ["range check failed", "index check failed"]:
        raise ExtractionError(f"GNAT pseudo-source checks for selected return are missing or reordered: {pseudo_checks}")
    range_match = re.fullmatch(r"not \((\w+) in (.+?) \.\. (.+)\)", pseudo_checks[0][1])
    if not range_match or range_match.group(1) != row_temp \
            or (ada_integer(range_match.group(2)), ada_integer(range_match.group(3))) != (natural_min, natural_max):
        raise ExtractionError(f"unsupported GNAT Natural predicate: {pseudo_checks[0][1]}")
    index_match = re.fullmatch(
        r"not \(integer\(positive\(natural\((\w+)\) \{\+\} (\d+)\)\) in (\w+) \.\. (\w+)\)",
        pseudo_checks[1][1],
    )
    if not index_match or index_match.group(1) != row_temp or int(index_match.group(2)) != increment \
            or index_match.group(3) != identifier(nodes, ref(nodes, lower_bound, "name")) \
            or index_match.group(4) != identifier(nodes, ref(nodes, upper_bound, "name")):
        raise ExtractionError("pseudo-source index predicate differs from compiler check and return nodes")
    return_source = re.search(
        rf"\breturn\s+frame\.bytes\.all\s*\(\s*positive\(natural\(\s*{re.escape(row_temp)}\s*\)\s*\+\s*(\d+)\s*\)\s*\)\s*;",
        expanded, re.I,
    )
    if not return_source or int(return_source.group(1)) != increment:
        raise ExtractionError("GNAT pseudo-source return index differs from actual compiler array_ref")

    guard_expr, _, _ = parse_expr(
        nodes, guard_row_id, natural_max, function_id=function_id,
        frame_parameter_id=frame_parameter_id,
    )
    accepted_row_operands = {
        frozenset({"x", "y", "width"}), frozenset({"x", "y", "height"})
    }
    row_candidates: set[int] = set()
    for node_id, node in nodes.items():
        if node["kind"] != "plus_expr":
            continue
        try:
            _, support, result_type = parse_expr(
                nodes, node_id, natural_max, function_id=function_id,
                frame_parameter_id=frame_parameter_id,
            )
        except ExtractionError:
            continue
        if result_type == "int64" and support in accepted_row_operands:
            row_candidates.add(node_id)
    if row_candidates != {guard_row_id, row_node}:
        raise ExtractionError(
            f"unconnected or missing compiler row expressions: {sorted(row_candidates)}"
        )
    width_fields = [node_id for node_id, node in nodes.items() if node["kind"] == "field_decl"
                    and identifier(nodes, ref(nodes, node_id, "name")).lower() == "width"]
    if len(width_fields) != 1:
        raise ExtractionError(f"expected one compiler Frame.Width field, found {len(width_fields)}")
    width_type_id = ref(nodes, width_fields[0], "type")
    if type_tag(nodes, width_type_id) != "int32":
        raise ExtractionError("Frame.Width is not compiler-resolved signed Int32")
    width_min, width_max = type_bounds(nodes, width_type_id)
    width_type_name = type_name(nodes, width_type_id)
    int64_min, int64_max = type_bounds(nodes, ref(nodes, row_node, "type"))

    policy_text = POLICY.read_text(encoding="utf-8").strip()
    if "Assertion_Policy" not in policy_text or not re.search(r"Ghost\s*=>\s*Check", policy_text):
        raise ExtractionError("verification-only Ghost => Check policy is missing")
    compiler_version, compiler_target = compiler_version.strip(), compiler_target.strip()
    validate_compiler_output(compiler_version, compiler_target)
    row_expr0, row_expr1 = guard_expr, row_expr
    index_value_expr = (
        f".cast .integer (.cast .positive (.add .integer "
        f"(.cast .natural (compilerRowExpr1)) (.literal {increment})))"
    )
    natural_predicate = (
        f".not (.inRange (compilerRowExpr1) (.literal {natural_min}) (.literal {natural_max}))"
    )
    overflow_predicate = parse_predicate(
        nodes, overflow_test, natural_max, function_id, frame_parameter_id
    )
    array_predicate = f".not (.inRange ({index_value_expr}) .arrayFirst .arrayLast)"
    raw_checks = ", ".join(f'({node_id}, "{name}")' for node_id, name in all_checks)
    check_names = ", ".join(f'"{name}"' for _, name in all_checks)
    predicate_text = ",\n  ".join(
        f'"{kind}: {text.replace(chr(34), chr(92)+chr(34))}"' for kind, text in pseudo_checks
    )
    selected_nodes = [
        ("function_decl", function_id), ("outer_guard", guard_conditions[0]),
        ("layout_guard", guard_conditions[1]), ("row_guard", guard_row_id),
        ("row_temporary", row_temp_id), ("return_row", row_node),
        ("natural_check_condition", range_cond), ("natural_check_call", range_call),
        ("array_check_condition", index_cond), ("array_check_call", index_call),
        ("array_lower_test", lower_check), ("array_upper_test", upper_check),
        ("overflow_condition", overflow_cond), ("overflow_test", overflow_test),
        ("overflow_true_branch_call", overflow_call), ("array_return", byte_return),
        ("array_ref", array_id), ("returned_index_cast", raw_index),
        ("returned_index_type", raw_index_type),
        ("returned_index_add", raw_index_value), ("byte_array_domain", domain_type),
        ("byte_array_domain_min", domain_min_id), ("byte_array_domain_max", domain_max_id),
        ("array_lower_bound", lower_bound), ("array_upper_bound", upper_bound),
        ("return_row_conversion", raw_index_row),
        ("return_index_increment", ref(nodes, raw_index_value, "op 1")),
        ("return_array_type", array_type), ("return_pixel_type", ref(nodes, array_id, "type")),
    ]
    for label, root_node in (("guard_row_tree", guard_row_id), ("return_row_tree", row_node)):
        selected_nodes.extend(
            (f"{label}_{index}", node_id)
            for index, node_id in enumerate(selected_expression_node_ids(nodes, root_node))
        )
    selected_nodes_lean = ", ".join(f'("{name}", {node_id})' for name, node_id in selected_nodes)
    expanded_lines = re.findall(r"^--\s*(\d+):", expanded, re.M)
    return f'''import CameraLifecycle.Grab.CompilerIR

namespace CameraLifecycle.Grab

def compilerNaturalMin : Nat := {natural_min}
def compilerNaturalMax : Nat := {natural_max}
def compilerPositiveMin : Nat := 1
def compilerPositiveMax : Nat := {integer_max}
def compilerIntegerMin : Int := {lean_int(integer_min)}
def compilerIntegerMax : Int := {lean_int(integer_max)}
def compilerWidthMin : Int := {lean_int(width_min)}
def compilerWidthMax : Int := {lean_int(width_max)}
def compilerWidthTypeName : String := "{width_type_name}"
def compilerInt64Min : Int := {lean_int(int64_min)}
def compilerInt64Max : Int := {lean_int(int64_max)}
def compilerArrayIndexMin : Int := 0
def compilerArrayIndexMax : Int := {array_index_max}
def compilerArrayIndexPrecision : Nat := {raw_index_precision}
def compilerVersion : String := "{compiler_version}"
def compilerTarget : String := "{compiler_target}"
def compilerExecutable : String := "gcc"
def compilerBuildFlags : List String := ["-c", "-gnat2022", "-gnatW8", "-ffp-contract=off", "-gnatwa", "-gnatVa", "-O0", "-gnatec=verification/lean-camera/tools/ghost-check.adc", "-I<scratch-output>", "-Ioptional/aravis/src", "-Isrc"]
def compilerTreeFlags : List String := ["-gnatG", "-gnatL", "-fdump-tree-original-raw"]
def compilerStandardFlags : List String := ["-gnatS"]
def compilerPolicy : String := "{policy_text.replace(chr(34), chr(92)+chr(34)).replace(chr(10), ' ')}"
def compilerPolicyPath : String := "verification/lean-camera/tools/ghost-check.adc"
def compilerPolicySha256 : String := "{hashlib.sha256(POLICY.read_bytes()).hexdigest()}"
def compilerBounds : ScalarBounds := {{
  naturalMin := {lean_int(natural_min)},
  naturalMax := {lean_int(natural_max)},
  positiveMin := (1 : Int),
  positiveMax := {lean_int(integer_max)},
  integerMin := {lean_int(integer_min)},
  integerMax := {lean_int(integer_max)},
  int32Min := {lean_int(width_min)},
  int32Max := {lean_int(width_max)},
  int64Min := {lean_int(int64_min)},
  int64Max := {lean_int(int64_max)}
}}
def compilerPixelAtSource : String := "{srcp.group(1)}"
def compilerPixelAtHeader : String := "{header.strip().replace(chr(34), chr(92)+chr(34))}"
def compilerSelectedNodeIds : List (String × Nat) := [{selected_nodes_lean}]
def compilerRowNodeIds : List Nat := [{guard_row_id}, {row_node}]
def compilerRowExpr0 : ScalarExpr := {row_expr0}
def compilerRowExpr1 : ScalarExpr := {row_expr1}
def compilerNaturalFailurePredicate : ScalarPredicate := {natural_predicate}
def compilerOverflowFailurePredicate : ScalarPredicate := {overflow_predicate}
def compilerArrayFailurePredicate : ScalarPredicate := {array_predicate}
def compilerIndexValueExpr : ScalarExpr := {index_value_expr}
def compilerRawCheckCalls : List (Nat × String) := [{raw_checks}]
def compilerCheckRoutines : List String := [{check_names}]
def compilerCheckPredicates : List String := [
  {predicate_text}
]
def compilerExpandedSourceLines : List Nat := [{', '.join(expanded_lines)}]

end CameraLifecycle.Grab
'''


def extract(source: Path, diagnostics: Path | None) -> str:
    cc, compiler_version, compiler_target = compiler()
    with tempfile.TemporaryDirectory(prefix="gnat-pixel-ir-") as tmp:
        out = Path(tmp)
        include = [f"-I{out}", f"-I{ROOT / 'optional/aravis/src'}", f"-I{ROOT / 'src'}"]
        common = ["-c", "-gnat2022", "-gnatW8", "-ffp-contract=off", "-gnatwa", "-gnatVa", "-O0",
                  f"-gnatec={POLICY}", *include]
        run([cc, *common, "-o", str(out / "amv-gige_vision_types.o"), str(TYPES)], cwd=ROOT)
        standard_log = run([cc, *common, "-gnatS", "-o", str(out / "amv-spec-gige_vision.o"), str(source)], cwd=ROOT)
        expanded_path = out / "expanded.log"
        run([cc, *common, "-gnatG", "-gnatL", "-fdump-tree-original-raw",
             "-o", str(out / "amv-spec-gige_vision.o"), str(source)], cwd=ROOT, output=expanded_path)
        raw_path = out / "amv-spec-gige_vision.ads.006t.original"
        if not raw_path.is_file():
            raise ExtractionError("GNAT did not emit the expected raw GCC tree")
        if diagnostics:
            diagnostics.mkdir(parents=True, exist_ok=True)
            shutil.copy2(raw_path, diagnostics / raw_path.name)
            shutil.copy2(expanded_path, diagnostics / "gnatG-gnatL.log")
            (diagnostics / "gnatS-standard.log").write_text(standard_log)
        return generate(raw_path.read_text(), standard_log, expanded_path.read_text(),
                        source.name, compiler_version, compiler_target)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=SPEC)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--diagnostics-dir", type=Path)
    args = parser.parse_args()
    generated = extract(args.source, args.diagnostics_dir)
    if args.check:
        if not args.output.is_file() or args.output.read_text() != generated:
            raise ExtractionError(f"compiler-generated Lean is stale: {args.output}")
        print(f"compiler-derived Pixel_At IR is fresh: {args.output}")
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(generated)
        print(f"generated compiler-derived Pixel_At IR: {args.output}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ExtractionError as error:
        raise SystemExit(f"compiler extraction failed: {error}")
