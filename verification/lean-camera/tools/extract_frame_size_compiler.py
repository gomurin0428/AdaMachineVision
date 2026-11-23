#!/usr/bin/env python3
"""Import the bounded Grab_Status frame-size suffix from GNAT's raw tree."""

from __future__ import annotations

import argparse
import hashlib
import re
import shutil
import tempfile
from collections import Counter
from pathlib import Path

import extract_pixel_compiler as compiler_ir


ROOT = compiler_ir.ROOT
SPEC = compiler_ir.SPEC
TYPES = compiler_ir.TYPES
POLICY = compiler_ir.POLICY
OUTPUT = ROOT / "verification/lean-camera/CameraLifecycle/Grab/FrameSizeGenerated.lean"
ExtractionError = compiler_ir.ExtractionError


def ref(nodes: dict[int, dict[str, str]], node_id: int, key: str) -> int:
    try:
        return int(compiler_ir.fields(nodes[node_id])[key])
    except (KeyError, ValueError) as exc:
        raise ExtractionError(f"compiler node @{node_id} has no {key}") from exc


def kind(nodes: dict[int, dict[str, str]], node_id: int) -> str:
    try:
        return nodes[node_id]["kind"]
    except KeyError as exc:
        raise ExtractionError(f"compiler tree references missing node @{node_id}") from exc


def type_name(nodes: dict[int, dict[str, str]], node_id: int) -> str:
    fields = compiler_ir.fields(nodes[node_id])
    name_id = fields.get("name")
    if name_id is None:
        return ""
    return compiler_ir.identifier(nodes, int(name_id)).lower()


def scalar_type(nodes: dict[int, dict[str, str]], node_id: int) -> str:
    name = type_name(nodes, node_id)
    if name.endswith("unsigned_64") or name.endswith("unsigned64"):
        compiler_ir.validate_unsigned_type(nodes, node_id, 64)
        return "unsigned64"
    if kind(nodes, node_id) == "integer_type" \
            and re.search(r"\bprec:\s*32\b", nodes[node_id]["text"]) \
            and re.search(r"\bsign:\s*unsigned\b", nodes[node_id]["text"]):
        node = nodes[node_id]["text"]
        size_id = compiler_ir.fields(nodes[node_id]).get("size")
        lower = compiler_ir.integer_constant(nodes, ref(nodes, node_id, "min"))
        upper = compiler_ir.integer_constant(nodes, ref(nodes, node_id, "max"))
        if (lower, upper) != (0, -1) or size_id is None \
                or compiler_ir.integer_constant(nodes, int(size_id)) != 32:
            raise ExtractionError("compiler unsigned word bounds changed")
        return "size"
    tag = compiler_ir.type_tag(nodes, node_id)
    if tag in {"integer", "natural", "positive", "int32", "int64"}:
        return tag
    raise ExtractionError(f"unsupported resolved scalar type {name!r} at @{node_id}")


def raw_children(nodes: dict[int, dict[str, str]], node_id: int) -> list[int]:
    node = nodes[node_id]
    fields = compiler_ir.fields(node)
    node_kind = node["kind"]
    if node_kind == "statement_list":
        return [int(value) for _, value in re.findall(r"\b(\d+)\s*:\s*@([0-9]+)", node["text"])]
    keys = {
        "bind_expr": ("body",), "cond_expr": ("op 0", "op 1", "op 2"),
        "truth_orif_expr": ("op 0", "op 1"), "truth_andif_expr": ("op 0", "op 1"),
        "compound_expr": ("op 0", "op 1"), "save_expr": ("op 0",),
        "init_expr": ("op 0", "op 1"), "return_expr": ("expr",),
        "eq_expr": ("op 0", "op 1"), "ne_expr": ("op 0", "op 1"),
        "lt_expr": ("op 0", "op 1"), "le_expr": ("op 0", "op 1"),
        "gt_expr": ("op 0", "op 1"), "ge_expr": ("op 0", "op 1"),
        "plus_expr": ("op 0", "op 1"), "minus_expr": ("op 0", "op 1"),
        "mult_expr": ("op 0", "op 1"), "nop_expr": ("op 0",),
        "convert_expr": ("op 0",), "view_convert_expr": ("op 0",),
        "indirect_ref": ("op 0",), "component_ref": ("op 0", "op 1"),
        "var_decl": ("init",), "call_expr": ("fn",), "addr_expr": ("op 0",),
        "tree_list": ("valu", "chan"), "decl_expr": ("op 0",),
    }.get(node_kind, ())
    return [int(fields[key]) for key in keys if key in fields]


def walk_nodes(nodes: dict[int, dict[str, str]], root: int) -> list[int]:
    seen: set[int] = set()
    result: list[int] = []

    def visit(node_id: int) -> None:
        if node_id in seen:
            return
        seen.add(node_id)
        result.append(node_id)
        for child in raw_children(nodes, node_id):
            if child in nodes:
                visit(child)

    visit(root)
    return result


def control_conditions(nodes: dict[int, dict[str, str]], root: int) -> list[int]:
    result: list[int] = []

    def visit(node_id: int) -> None:
        node_kind = kind(nodes, node_id)
        fields = compiler_ir.fields(nodes[node_id])
        if node_kind == "return_expr":
            return
        if node_kind == "cond_expr":
            true_id = ref(nodes, node_id, "op 1")
            if kind(nodes, true_id) == "call_expr":
                name = check_call_name(nodes, true_id)
                if name in {"Range_Check", "Overflow_Check", "Invalid_Data", "Access_Check", "Index_Check"}:
                    return
                raise ExtractionError(f"unknown compiler control call @{true_id}: {name}")
            result.append(node_id)
            visit(true_id)
            visit(ref(nodes, node_id, "op 2"))
            return
        if node_kind == "statement_list":
            for child in raw_children(nodes, node_id):
                visit(child)
            return
        if node_kind in {"bind_expr", "cleanup_point_expr", "try_finally_expr"}:
            for key in ("body", "op 0"):
                if key in fields:
                    visit(int(fields[key]))
            return
        if node_kind == "compound_expr":
            left = ref(nodes, node_id, "op 0")
            if any(kind(nodes, child) == "call_expr" for child in walk_nodes(nodes, left)):
                raise ExtractionError(f"unassociated compiler call in control sequencing @{node_id}")
            visit(ref(nodes, node_id, "op 1"))
            return
        raise ExtractionError(f"unknown compiler control statement @{node_id}: {node_kind}")

    visit(root)
    return result


def return_codes(nodes: dict[int, dict[str, str]], root: int) -> list[int]:
    values: list[int] = []
    for node_id in walk_nodes(nodes, root):
        if kind(nodes, node_id) != "return_expr":
            continue
        constants = [child for child in walk_nodes(nodes, node_id)
                     if kind(nodes, child) == "integer_cst"]
        if len(constants) != 1:
            raise ExtractionError(f"ambiguous enum return expression at @{node_id}")
        values.append(compiler_ir.integer_constant(nodes, constants[0]))
    return values


def enum_members(nodes: dict[int, dict[str, str]], type_id: int) -> dict[str, int]:
    if kind(nodes, type_id) != "enumeral_type":
        raise ExtractionError("Grab_Status compiler result is not an enum")
    entries: dict[str, int] = {}
    node_id = ref(nodes, type_id, "csts")
    seen: set[int] = set()
    while node_id and node_id not in seen:
        seen.add(node_id)
        if kind(nodes, node_id) != "tree_list":
            raise ExtractionError("compiler enum member chain is malformed")
        fields = compiler_ir.fields(nodes[node_id])
        name = compiler_ir.identifier(nodes, int(fields["purp"])).lower()
        value = compiler_ir.integer_constant(nodes, int(fields["valu"]))
        if name in entries or value in entries.values():
            raise ExtractionError("compiler enum names or values are not unique")
        entries[name] = value
        node_id = int(fields.get("chan", "0"))
    if not entries:
        raise ExtractionError("compiler Grab_Status enum has no members")
    return entries


def enum_return_name(code: int, members: dict[str, int]) -> str:
    matches = [name for name, value in members.items() if value == code]
    if len(matches) != 1:
        raise ExtractionError(f"compiler enum return value {code} is ambiguous")
    name = matches[0].rsplit("__", 1)[-1]
    if name == "frame_invalid_dimensions":
        return "invalidDimensions"
    if name == "frame_too_large":
        return "tooLarge"
    if name == "frame_invalid_length":
        return "invalidLength"
    if name == "frame_success":
        return "success"
    return name


def record_scope(nodes: dict[int, dict[str, str]], type_id: int) -> int:
    fields = compiler_ir.fields(nodes[type_id])
    if "unql" in fields:
        type_id = int(fields["unql"])
    return type_id


class FrameTree:
    def __init__(self, nodes: dict[int, dict[str, str]], function_id: int,
                 frame_parameter_id: int, source_name: str):
        self.nodes = nodes
        self.function_id = function_id
        self.frame_parameter_id = frame_parameter_id
        self.source_name = source_name
        self.aliases: set[int] = set()
        self.active: set[int] = set()
        self.consumed_checks: set[int] = set()
        self.checks: list[tuple[int, str, object]] = []

    def path(self, node_id: int) -> list[str]:
        node_kind = kind(self.nodes, node_id)
        if node_kind == "parm_decl":
            if node_id != self.frame_parameter_id:
                raise ExtractionError(f"frame field path uses foreign parameter @{node_id}")
            return []
        if node_kind == "component_ref":
            field_id = ref(self.nodes, node_id, "op 1")
            if kind(self.nodes, field_id) != "field_decl":
                raise ExtractionError(f"compiler component @{node_id} has no field declaration")
            base_id = ref(self.nodes, node_id, "op 0")
            base_type = ref(self.nodes, base_id, "type")
            expected_scope = record_scope(self.nodes, base_type)
            if ref(self.nodes, field_id, "scpe") != expected_scope:
                raise ExtractionError(f"field scope mismatch at compiler component @{node_id}")
            field_name = compiler_ir.identifier(self.nodes, ref(self.nodes, field_id, "name")).lower()
            return self.path(base_id) + [field_name]
        if node_kind == "indirect_ref":
            return self.path(ref(self.nodes, node_id, "op 0"))
        if node_kind in {"nop_expr", "convert_expr", "view_convert_expr", "save_expr"}:
            return self.path(ref(self.nodes, node_id, "op 0"))
        if node_kind == "compound_expr":
            prefix = self.ast(ref(self.nodes, node_id, "op 0"))
            if prefix != ("noEffect",):
                raise ExtractionError(f"field path hides a sequenced effect at @{node_id}")
            return self.path(ref(self.nodes, node_id, "op 1"))
        if node_kind == "var_decl":
            self._alias(node_id)
            return self.path(ref(self.nodes, node_id, "init"))
        if node_kind == "init_expr":
            target_id = ref(self.nodes, node_id, "op 0")
            if kind(self.nodes, target_id) != "var_decl":
                raise ExtractionError(f"field path has an unexpected initializer target @{target_id}")
            self._alias(target_id)
            return self.path(ref(self.nodes, node_id, "op 1"))
        raise ExtractionError(f"unrecognized node in frame field path: @{node_id} {node_kind}")

    def _alias(self, node_id: int) -> None:
        if node_id in self.aliases:
            return
        if ref(self.nodes, node_id, "scpe") != self.function_id:
            raise ExtractionError(f"compiler alias @{node_id} escapes Grab_Status scope")
        source = re.search(r"\bsrcp:\s*([^\s]+)", self.nodes[node_id]["text"])
        if not source or Path(source.group(1).split(":", 1)[0]).name != self.source_name:
            raise ExtractionError(f"compiler alias @{node_id} has unexpected source provenance")
        self.aliases.add(node_id)

    def field(self, node_id: int) -> tuple[str, str]:
        path = self.path(node_id)
        if path == ["bytes", "p_array"]:
            pointer_type = ref(self.nodes, node_id, "type")
            if kind(self.nodes, pointer_type) != "pointer_type":
                raise ExtractionError("byte-array null guard is not a pointer comparison")
            return "bytePointer", "pointer"
        node_type = scalar_type(self.nodes, ref(self.nodes, node_id, "type"))
        if path == ["width"]:
            if compiler_ir.direct_frame_field(
                    self.nodes, node_id, self.function_id, self.frame_parameter_id,
                    {"width"}) != "width" or node_type != "int32":
                raise ExtractionError("Frame.Width is not a direct compiler-resolved Int32 field")
            return "width", node_type
        if path == ["height"]:
            if compiler_ir.direct_frame_field(
                    self.nodes, node_id, self.function_id, self.frame_parameter_id,
                    {"height"}) != "height" or node_type != "int32":
                raise ExtractionError("Frame.Height is not a direct compiler-resolved Int32 field")
            return "height", node_type
        if path == ["byte_count"]:
            if compiler_ir.direct_frame_field(
                    self.nodes, node_id, self.function_id, self.frame_parameter_id,
                    {"byte_count"}) != "byte_count" or node_type != "natural":
                raise ExtractionError("Frame.Byte_Count is not a direct Natural field")
            return "byteCount", node_type
        if path == ["source_size"]:
            if compiler_ir.direct_frame_field(
                    self.nodes, node_id, self.function_id, self.frame_parameter_id,
                    {"source_size"}) != "source_size" or node_type != "unsigned64":
                raise ExtractionError("Frame.Source_Size is not a direct Unsigned_64 field")
            return "sourceSize", node_type
        if path == ["bytes", "p_bounds", "lb0"] and node_type == "positive":
            return "byteFirst", node_type
        if path == ["bytes", "p_bounds", "ub0"] and node_type == "positive":
            return "byteLast", node_type
        raise ExtractionError(f"unrecognized frame field path {'.'.join(path)} at @{node_id}")

    def ast(self, node_id: int):
        if node_id in self.active:
            raise ExtractionError(f"cyclic compiler alias at @{node_id}")
        node_kind = kind(self.nodes, node_id)
        fields = compiler_ir.fields(self.nodes[node_id])
        if node_kind in {"save_expr", "nop_expr", "convert_expr", "view_convert_expr"}:
            if node_kind != "save_expr":
                target = scalar_type(self.nodes, ref(self.nodes, node_id, "type"))
                return ("cast", target, self._nested(node_id, ref(self.nodes, node_id, "op 0")))
            return self._nested(node_id, ref(self.nodes, node_id, "op 0"))
        if node_kind == "compound_expr":
            first = self._nested(node_id, ref(self.nodes, node_id, "op 0"))
            second = self._nested(node_id, ref(self.nodes, node_id, "op 1"))
            return second if first == ("noEffect",) else ("sequence", first, second)
        if node_kind == "statement_list":
            statements = compiler_ir.statement_items(self.nodes, node_id)
            if not statements:
                return ("noEffect",)
            translated = [self._nested(node_id, child_id) for child_id in statements]
            translated = [item for item in translated if item != ("noEffect",)]
            if not translated:
                return ("noEffect",)
            result = translated[0]
            for item in translated[1:]:
                result = ("sequence", result, item)
            return result
        if node_kind == "decl_expr":
            if set(fields) != {"type"} or kind(self.nodes, ref(self.nodes, node_id, "type")) != "void_type":
                raise ExtractionError(f"unexpected declaration expression shape @{node_id}")
            return ("noEffect",)
        if node_kind == "var_decl":
            self._alias(node_id)
            return self._nested(node_id, ref(self.nodes, node_id, "init"))
        if node_kind == "init_expr":
            target_id = ref(self.nodes, node_id, "op 0")
            if kind(self.nodes, target_id) != "var_decl":
                raise ExtractionError(f"unexpected compiler initializer target @{target_id}")
            self._alias(target_id)
            return self._nested(node_id, ref(self.nodes, node_id, "op 1"))
        if node_kind == "integer_cst":
            target = scalar_type(self.nodes, ref(self.nodes, node_id, "type"))
            return ("literal", compiler_ir.integer_constant(self.nodes, node_id), target)
        if node_kind == "component_ref":
            field, target = self.field(node_id)
            return ("field", field, target)
        if node_kind in {"truth_orif_expr", "truth_andif_expr"}:
            left = self._nested(node_id, ref(self.nodes, node_id, "op 0"))
            right = self._nested(node_id, ref(self.nodes, node_id, "op 1"))
            return ("orElse" if node_kind == "truth_orif_expr" else "andThen", left, right)
        if node_kind in {"eq_expr", "ne_expr", "lt_expr", "le_expr", "gt_expr", "ge_expr"}:
            left_id, right_id = ref(self.nodes, node_id, "op 0"), ref(self.nodes, node_id, "op 1")
            if node_kind in {"eq_expr", "ne_expr"}:
                candidates = [(left_id, right_id), (right_id, left_id)]
                for pointer_id, zero_id in candidates:
                    if (kind(self.nodes, zero_id) == "integer_cst"
                            and compiler_ir.integer_constant(self.nodes, zero_id) == 0):
                        try:
                            pointer, pointer_type = self.field(pointer_id)
                        except ExtractionError:
                            continue
                        if pointer == "bytePointer" and pointer_type == "pointer":
                            return ("bytesNull",) if node_kind == "eq_expr" else ("not", ("bytesNull",))
            op = {"eq_expr": "equal", "ne_expr": "notEqual", "lt_expr": "less",
                  "le_expr": "lessEqual", "gt_expr": "greater", "ge_expr": "greaterEqual"}[node_kind]
            return (op, self._nested(node_id, left_id), self._nested(node_id, right_id))
        if node_kind in {"plus_expr", "minus_expr", "mult_expr"}:
            target = scalar_type(self.nodes, ref(self.nodes, node_id, "type"))
            op = {"plus_expr": "add", "minus_expr": "subtract", "mult_expr": "multiply"}[node_kind]
            return (op, target, self._nested(node_id, ref(self.nodes, node_id, "op 0")),
                    self._nested(node_id, ref(self.nodes, node_id, "op 1")))
        if node_kind == "cond_expr":
            true_id, false_id = ref(self.nodes, node_id, "op 1"), ref(self.nodes, node_id, "op 2")
            if kind(self.nodes, true_id) == "call_expr" or kind(self.nodes, false_id) == "call_expr":
                call_id = true_id if kind(self.nodes, true_id) == "call_expr" else false_id
                name = check_call_name(self.nodes, call_id)
                check_kind = {
                    "Range_Check": "rangeCheck", "Overflow_Check": "overflowCheck",
                    "Invalid_Data": "invalidData", "Access_Check": "accessCheck",
                    "Index_Check": "indexCheck",
                }.get(name.removeprefix("__gnat_rcheck_CE_"))
                if check_kind is None:
                    raise ExtractionError(f"unknown compiler check action @{call_id}: {name}")
                compiler_ir.check_branch(self.nodes, node_id, name.removeprefix("__gnat_rcheck_CE_"))
                predicate = self._nested(node_id, ref(self.nodes, node_id, "op 0"))
                if call_id in self.consumed_checks:
                    raise ExtractionError(f"compiler check action @{call_id} is associated more than once")
                self.consumed_checks.add(call_id)
                self.checks.append((call_id, name.removeprefix("__gnat_rcheck_CE_"), predicate))
                if kind(self.nodes, ref(self.nodes, node_id, "type")) == "void_type":
                    return ("check", check_kind, predicate)
                value = self._nested(node_id, false_id)
                if kind(self.nodes, ref(self.nodes, node_id, "type")) == "boolean_type":
                    return ("checkedPredicate", check_kind, predicate, value)
                return ("checked", check_kind, predicate, value)
            target = scalar_type(self.nodes, ref(self.nodes, node_id, "type"))
            return ("ifThenElse", self._nested(node_id, ref(self.nodes, node_id, "op 0")),
                    self._nested(node_id, true_id), self._nested(node_id, false_id), target)
        if node_kind == "truth_not_expr":
            return ("not", self._nested(node_id, ref(self.nodes, node_id, "op 0")))
        if node_kind == "call_expr":
            raise ExtractionError(f"unassociated compiler call action @{node_id}")
        raise ExtractionError(f"unknown compiler expression node @{node_id}: {node_kind}")

    def _nested(self, parent_id: int, child_id: int):
        self.active.add(parent_id)
        try:
            return self.ast(child_id)
        finally:
            self.active.remove(parent_id)


def flatten_or(expr) -> list:
    if isinstance(expr, tuple) and expr and expr[0] == "orElse":
        return flatten_or(expr[1]) + flatten_or(expr[2])
    return [expr]


def erase_check_actions(value):
    if not isinstance(value, tuple) or not value:
        return value
    if value[0] == "check":
        return ("noEffect",)
    if value[0] in {"checked", "checkedPredicate"}:
        return erase_check_actions(value[3])
    if value[0] == "sequence":
        first, second = erase_check_actions(value[1]), erase_check_actions(value[2])
        return second if first == ("noEffect",) else ("sequence", first, second)
    return tuple(erase_check_actions(item) for item in value)


def render_expr(expr) -> str:
    op = expr[0]
    if op == "literal":
        return f".literal ({expr[1]} : Int)"
    if op == "field":
        return "." + expr[1]
    if op == "cast":
        return f".cast .{expr[1]} ({render_expr(expr[2])})"
    if op == "check":
        return f".check .{expr[1]} ({render_predicate(expr[2])})"
    if op == "checked":
        return f".checked .{expr[1]} ({render_predicate(expr[2])}) ({render_expr(expr[3])})"
    if op == "sequence":
        return f".sequence ({render_expr(expr[1])}) ({render_expr(expr[2])})"
    if op in {"multiply", "add", "subtract"}:
        constructor = {"multiply": "multiply", "add": "add", "subtract": "subtract"}[op]
        return f".{constructor} .{expr[1]} ({render_expr(expr[2])}) ({render_expr(expr[3])})"
    if op == "ifThenElse":
        return (f".ifThenElse ({render_expr(expr[1])}) ({render_expr(expr[2])}) "
                f"({render_expr(expr[3])})")
    return render_predicate(expr)


def render_predicate(predicate) -> str:
    op = predicate[0]
    if op == "bytesNull":
        return ".bytesNull"
    if op == "not":
        return f".not ({render_predicate(predicate[1])})"
    if op == "orElse":
        return f".orElse ({render_predicate(predicate[1])}) ({render_predicate(predicate[2])})"
    if op == "andThen":
        return f".andThen ({render_predicate(predicate[1])}) ({render_predicate(predicate[2])})"
    if op == "checkedPredicate":
        return (f".checked .{predicate[1]} ({render_predicate(predicate[2])}) "
                f"({render_predicate(predicate[3])})")
    if op == "sequence":
        return f".sequence ({render_expr(predicate[1])}) ({render_predicate(predicate[2])})"
    constructors = {"equal": "equal", "notEqual": "notEqual", "less": "less",
                    "lessEqual": "lessEqual", "greater": "greater", "greaterEqual": "greaterEqual"}
    if op not in constructors:
        raise ExtractionError(f"cannot emit compiler predicate {op}")
    return (f".{constructors[op]} ({render_expr(predicate[1])}) "
            f"({render_expr(predicate[2])})")


def lean_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def check_call_name(nodes: dict[int, dict[str, str]], node_id: int) -> str:
    name = compiler_ir.check_name(nodes, node_id)
    if not name.startswith("__gnat_rcheck_CE_"):
        raise ExtractionError(f"unknown compiler runtime check call @{node_id}: {name}")
    return name.removeprefix("__gnat_rcheck_CE_")


def check_nodes(tree: FrameTree, condition_ids: list[int]) -> list[tuple[int, str, object]]:
    associated: set[int] = set()
    for condition_id in condition_ids:
        for node_id in walk_nodes(tree.nodes, ref(tree.nodes, condition_id, "op 0")):
            if kind(tree.nodes, node_id) != "call_expr":
                continue
            fn_name = compiler_ir.check_name(tree.nodes, node_id)
            if fn_name.startswith("__gnat_rcheck_CE_"):
                associated.add(node_id)
    if associated != tree.consumed_checks:
        missing = sorted(associated - tree.consumed_checks)
        extra = sorted(tree.consumed_checks - associated)
        raise ExtractionError(f"compiler checks lack exact expression associations; missing={missing} extra={extra}")
    return tree.checks


def expanded_checks(expanded: str, natural_max: int) -> list[tuple[str, str]]:
    lower = expanded.lower()
    function_matches = list(re.finditer(r"function\s+amv__spec__gige_vision__grab_status\b", lower))
    if len(function_matches) < 2:
        raise ExtractionError("GNAT expanded output has no selected Grab_Status body")
    function_start = function_matches[-1].start()
    suffix_start = lower.find("frame_too_large", function_start)
    suffix_end = lower.find("end amv__spec__gige_vision__grab_status", suffix_start)
    if suffix_start < function_start or suffix_end < suffix_start:
        raise ExtractionError("GNAT expanded output has no bounded Grab_Status suffix")
    suffix = expanded[suffix_start:suffix_end]
    checks = []
    for predicate, message in re.findall(
            r"\[\s*constraint_error\s+when\s+(.*?)\s+\"([^\"]+)\"\s*\]",
            suffix, flags=re.S):
        normalized = re.sub(r"\s+", " ", predicate).strip()
        compact = re.sub(r"\s+", "", normalized).lower()
        message = message.lower()
        if "range check failed" in message:
            if not re.fullmatch(r"[a-z0-9_]+\s*<\s*0", normalized, re.I):
                raise ExtractionError(f"unexpected GNAT signed-to-unsigned check: {normalized}")
            checks.append(("range", normalized))
        elif "invalid data" in message:
            if "unsigned!(frame.byte_count)" not in compact:
                raise ExtractionError(f"unexpected GNAT Natural validity check: {normalized}")
            limits = re.findall(r"<=\s*([0-9A-Fa-f_#]+)", normalized)
            if not limits or compiler_ir.ada_integer(limits[-1]) != natural_max:
                raise ExtractionError("GNAT Byte_Count validity check omits the declared Natural maximum")
            checks.append(("invalidData", normalized))
        elif "access check failed" in message:
            if compact != "frame.bytes=null":
                raise ExtractionError(f"unexpected GNAT array access check: {normalized}")
            checks.append(("access", normalized))
        else:
            raise ExtractionError(f"unknown GNAT check message in suffix: {message}")
    expected = ["range", "invalidData", "invalidData", "access", "access"]
    if [name for name, _ in checks] != expected:
        raise ExtractionError(f"GNAT expanded check paths are missing or reordered: {checks}")
    return checks


def generate(raw: str, standard: str, expanded: str, source: Path, types: Path,
             compiler_version: str, compiler_target: str) -> str:
    integer_min, integer_max, natural_min, natural_max = compiler_ir.parse_standard_types(standard)
    if natural_min != 0 or integer_max != natural_max:
        raise ExtractionError("compiler Standard Integer and Natural bounds disagree")
    header, nodes = compiler_ir.parse_function_tree_named(raw, "grab_status", "Grab_Status")
    functions = [node_id for node_id, node in nodes.items() if node["kind"] == "function_decl"
                 and compiler_ir.identifier(nodes, ref(nodes, node_id, "name"))
                 == "amv__spec__gige_vision__grab_status"]
    if len(functions) != 1:
        raise ExtractionError(f"expected one compiler Grab_Status function, found {len(functions)}")
    function_id = functions[0]
    function_fields = compiler_ir.fields(nodes[function_id])
    function_srcp = re.search(r"\bsrcp:\s*([^\s]+)", nodes[function_id]["text"])
    if not function_srcp or Path(function_srcp.group(1).split(":", 1)[0]).name != source.name:
        raise ExtractionError("selected compiler function has unexpected source provenance")
    mangled_name = compiler_ir.identifier(nodes, ref(nodes, function_id, "mngl"))
    if mangled_name != "___ghost_amv__spec__gige_vision__grab_status":
        raise ExtractionError("selected compiler function is not the Ghost Grab_Status body")
    parameters = [node_id for node_id, node in nodes.items() if node["kind"] == "parm_decl"
                  and compiler_ir.fields(node).get("scpe") == str(function_id)]
    parameter_names = {compiler_ir.identifier(nodes, ref(nodes, node_id, "name")).lower(): node_id
                       for node_id in parameters}
    if set(parameter_names) != {"state", "timeout", "frame"} or len(parameter_names) != 3:
        raise ExtractionError("compiler Grab_Status parameter scope changed")
    frame_parameter_id = parameter_names["frame"]
    compiler_ir.frame_record_type(nodes, function_id, frame_parameter_id)
    function_type = ref(nodes, function_id, "type")
    if kind(nodes, function_type) != "function_type":
        raise ExtractionError("Grab_Status compiler declaration has no function type")
    enum_type = ref(nodes, function_type, "retn")
    members = enum_members(nodes, enum_type)
    expected_enum_names = {"frame_invalid_dimensions", "frame_too_large", "frame_invalid_length", "frame_success"}
    if not expected_enum_names <= {name.rsplit("__", 1)[-1] for name in members}:
        raise ExtractionError("compiler Frame_Status enum is missing a suffix result")

    def direct_return(branch_id: int) -> list[str]:
        return_ids = [node_id for node_id in walk_nodes(nodes, branch_id)
                      if kind(nodes, node_id) == "return_expr"]
        for return_id in return_ids:
            result = ref(nodes, return_id, "expr")
            if kind(nodes, result) != "init_expr":
                raise ExtractionError(f"unsupported compiler return expression @{result}")
            target, value = ref(nodes, result, "op 0"), ref(nodes, result, "op 1")
            if kind(nodes, target) != "result_decl" or kind(nodes, value) != "integer_cst":
                raise ExtractionError(f"unexpected compiler status return initialization @{result}")
        codes = return_codes(nodes, branch_id)
        return [enum_return_name(code, members) for code in codes]

    cond_ids = [node_id for node_id, node in nodes.items() if node["kind"] == "cond_expr"]
    lengths = [node_id for node_id in cond_ids
               if direct_return(ref(nodes, node_id, "op 1")) == ["invalidLength"]
               and direct_return(ref(nodes, node_id, "op 2")) == ["success"]]
    if len(lengths) != 1:
        raise ExtractionError(f"expected one Invalid_Length/Success suffix branch, found {len(lengths)}")
    length_id = lengths[0]
    products = [node_id for node_id in cond_ids
                if direct_return(ref(nodes, node_id, "op 1")) == ["tooLarge"]
                and control_conditions(nodes, ref(nodes, node_id, "op 2")) == [length_id]]
    if len(products) != 1:
        raise ExtractionError(f"expected one Too_Large branch preceding length, found {len(products)}")
    product_id = products[0]
    dimensions = [node_id for node_id in cond_ids
                  if direct_return(ref(nodes, node_id, "op 1")) == ["invalidDimensions"]
                  and control_conditions(nodes, ref(nodes, node_id, "op 2")) == [product_id, length_id]]
    if len(dimensions) != 1:
        raise ExtractionError(f"expected one ordered frame-size suffix, found {len(dimensions)}")
    dimension_id = dimensions[0]
    if [dimension_id, product_id, length_id] != [
            node_id for node_id in control_conditions(nodes, ref(nodes, function_id, "body"))
            if node_id in {dimension_id, product_id, length_id}]:
        raise ExtractionError("selected frame-size status paths are not ordered in Grab_Status")

    tree = FrameTree(nodes, function_id, frame_parameter_id, source.name)
    dimension_program = tree.ast(ref(nodes, dimension_id, "op 0"))
    dimension_predicate = erase_check_actions(dimension_program)
    if flatten_or(dimension_predicate) != [
            ("lessEqual", ("field", "width", "int32"), ("literal", 0, "int32")),
            ("lessEqual", ("field", "height", "int32"), ("literal", 0, "int32"))]:
        raise ExtractionError("invalid-dimensions guard differs from direct Int32 Width/Height <= 0")
    limit_program = tree.ast(ref(nodes, product_id, "op 0"))
    limit_predicate = erase_check_actions(limit_program)
    if not (isinstance(limit_predicate, tuple) and limit_predicate[0] == "greater"):
        raise ExtractionError("frame-size limit is not a strict greater-than comparison")
    product_expr = limit_predicate[1]
    if product_expr != ("multiply", "int64", ("cast", "int64", ("field", "width", "int32")),
                        ("cast", "int64", ("field", "height", "int32"))):
        raise ExtractionError("compiler frame product is not widened Int64 Width * Height")
    max_pixels = limit_predicate[2]
    if max_pixels[0] != "literal" or max_pixels[1] != natural_max or max_pixels[2] != "int64":
        raise ExtractionError("frame limit is not the compiler-resolved strict Max_Image_Pixels value")

    length_program = tree.ast(ref(nodes, length_id, "op 0"))
    length_predicate = erase_check_actions(length_program)
    length_parts = flatten_or(length_predicate)
    if len(length_parts) != 5:
        raise ExtractionError("received-size suffix no longer has five ordered short-circuit checks")
    expected_source_product = ("cast", "unsigned64", product_expr)
    expected_byte_product = product_expr
    if length_parts[0] != ("notEqual", ("cast", "unsigned64", ("field", "sourceSize", "unsigned64")),
                            expected_source_product):
        raise ExtractionError("Source_Size comparison/conversion differs from compiler tree")
    if length_parts[1] != ("notEqual", ("cast", "int64", ("field", "byteCount", "natural")),
                            expected_byte_product):
        raise ExtractionError("Byte_Count comparison/conversion differs from compiler tree")
    if length_parts[2] != ("bytesNull",):
        raise ExtractionError("byte-view null guard is missing or reordered")
    if length_parts[3] != ("notEqual", ("field", "byteFirst", "positive"), ("literal", 1, "positive")):
        raise ExtractionError("first-bound comparison is not the direct byte-view lower bound")
    array_length = ("ifThenElse",
                    ("greaterEqual", ("field", "byteLast", "positive"),
                     ("field", "byteFirst", "positive")),
                    ("cast", "int64",
                     ("cast", "integer",
                      ("add", "size",
                       ("subtract", "size", ("cast", "size", ("field", "byteLast", "positive")),
                        ("cast", "size", ("field", "byteFirst", "positive"))),
                       ("literal", 1, "size")))),
                    ("literal", 0, "int64"), "int64")
    if length_parts[4] != ("notEqual", array_length, product_expr):
        raise ExtractionError("byte-array length expression/conversions differ from compiler nodes")
    array_length_expr = length_parts[4][1]

    checks = check_nodes(tree, [dimension_id, product_id, length_id])
    check_counts = Counter(name for _, name, _ in checks)
    if check_counts != Counter({"Range_Check": 1, "Invalid_Data": 2, "Access_Check": 2}):
        raise ExtractionError(f"unknown, extra, or missing compiler checks in frame-size suffix: {check_counts}")
    for _, name, predicate in checks:
        if name == "Range_Check" and predicate != ("less", product_expr, ("literal", 0, "int64")):
            raise ExtractionError("Unsigned_64 product conversion check is not the exact negative range guard")
        if name == "Invalid_Data" and predicate not in {
                ("less", ("field", "byteCount", "natural"), ("literal", 0, "integer")),
                ("less", ("field", "byteCount", "natural"), ("literal", 0, "natural"))}:
            raise ExtractionError("Byte_Count invalid-data check differs from compiler Natural representation")
        if name == "Access_Check" and predicate != ("bytesNull",):
            raise ExtractionError("byte array access check does not guard the null descriptor")
    expanded_check_evidence = expanded_checks(expanded, natural_max)

    policy_text = POLICY.read_text(encoding="utf-8").strip()
    if "Assertion_Policy" not in policy_text or not re.search(r"Ghost\s*=>\s*Check", policy_text):
        raise ExtractionError("verification-only Ghost => Check policy is missing")
    compiler_ir.validate_compiler_output(compiler_version.strip(), compiler_target.strip())

    source_lines: set[int] = set()
    selected_nodes: list[tuple[str, int]] = [
        ("function", function_id), ("invalid_dimensions", dimension_id),
        ("too_large", product_id), ("invalid_length", length_id),
    ]
    selected_nodes.extend(("check_" + name.lower(), node_id) for node_id, name, _ in checks)
    selected_nodes.extend(("alias", node_id) for node_id in sorted(tree.aliases))
    for _, node_id in selected_nodes:
        source_match = re.search(r"\bsrcp:\s*[^:]+:(\d+)", nodes[node_id]["text"])
        if source_match:
            source_lines.add(int(source_match.group(1)))

    type_records = []
    for field_name in ("width", "height", "byte_count", "source_size"):
        field_nodes = [node_id for node_id, node in nodes.items() if node["kind"] == "field_decl"
                       and compiler_ir.identifier(nodes, ref(nodes, node_id, "name")).lower() == field_name]
        if len(field_nodes) != 1:
            raise ExtractionError(f"expected one compiler Frame.{field_name} declaration")
        field_id = field_nodes[0]
        type_id = ref(nodes, field_id, "type")
        tag = scalar_type(nodes, type_id)
        representation_lower, representation_upper = compiler_ir.type_bounds(nodes, type_id)
        if tag == "unsigned64":
            representation_lower, representation_upper = 0, -1
            lower, upper = 0, (1 << 64) - 1
        elif tag == "natural":
            lower, upper = natural_min, natural_max
        elif tag == "positive":
            lower, upper = 1, integer_max
        else:
            lower, upper = representation_lower, representation_upper
        type_records.append((field_name, field_id, type_id, tag, lower, upper,
                             representation_lower, representation_upper))
    product_type = ref(nodes, ref(nodes, ref(nodes, product_id, "op 0"), "op 0"), "type")
    int64_min, int64_max = compiler_ir.type_bounds(nodes, product_type)
    length_nodes = walk_nodes(nodes, ref(nodes, length_id, "op 0"))
    size_type_ids = {ref(nodes, node_id, "type") for node_id in length_nodes
                     if kind(nodes, node_id) in {"plus_expr", "minus_expr"}
                     and scalar_type(nodes, ref(nodes, node_id, "type")) == "size"}
    if len(size_type_ids) != 1:
        raise ExtractionError("expected one compiler size type used for array length")
    size_type_id = next(iter(size_type_ids))
    size_min, size_raw_max = compiler_ir.type_bounds(nodes, size_type_id)
    if (size_min, size_raw_max) != (0, -1):
        raise ExtractionError("compiler array length representation bounds changed")
    size_max = (1 << 32) - 1
    int32_min = next(lower for name, _, _, _, lower, _, _, _ in type_records if name == "width")
    int32_max = next(upper for name, _, _, _, _, upper, _, _ in type_records if name == "width")

    members_by_suffix = {name.rsplit("__", 1)[-1]: value for name, value in members.items()}
    statuses = {name: members_by_suffix["frame_" + suffix.lower()]
                for name, suffix in (("invalidDimensions", "invalid_dimensions"),
                                     ("tooLarge", "too_large"),
                                     ("invalidLength", "invalid_length"), ("success", "success"))}
    control = (
        f".ifThenElse ({render_predicate(dimension_program)}) "
        f"(.returnStatus .invalidDimensions) "
        f"(.ifThenElse ({render_predicate(limit_program)}) (.returnStatus .tooLarge) "
        f"(.ifThenElse ({render_predicate(length_program)}) (.returnStatus .invalidLength) "
        f"(.returnStatus .success)))"
    )
    check_names = {"Range_Check": "range", "Invalid_Data": "invalidData", "Access_Check": "access"}
    check_text = ",\n  ".join(
        f"{{ kind := .{check_names[name]}, nodeId := {node_id}, predicate := {render_predicate(predicate)} }}"
        for node_id, name, predicate in checks
    )
    node_text = ", ".join(f"({lean_string(label)}, {node_id})" for label, node_id in selected_nodes)
    resolved_text = ",\n  ".join(
        f"{{ name := {lean_string(name)}, nodeId := {field_id}, typeNodeId := {type_id}, "
        f"typeName := {lean_string(tag)}, lower := ({lower} : Int), upper := ({upper} : Int), "
        f"representationLower := ({rep_lower} : Int), representationUpper := ({rep_upper} : Int) }}"
        for name, field_id, type_id, tag, lower, upper, rep_lower, rep_upper in type_records
    )
    enum_text = ", ".join(f"({lean_string(name)}, {value})" for name, value in sorted(members.items()))
    flags = ["-c", "-gnat2022", "-gnatW8", "-ffp-contract=off", "-gnatwa", "-gnatVa", "-O0",
             "-gnatec=verification/lean-camera/tools/ghost-check.adc",
             "-gnatG", "-gnatL", "-fdump-tree-original-raw", "-gnatS"]
    flag_text = ", ".join(lean_string(flag) for flag in flags)
    source_text = ", ".join(str(line) for line in sorted(source_lines))
    selected_ids = ", ".join(str(node_id) for _, node_id in selected_nodes)
    expanded_check_text = ",\n  ".join(
        f"({lean_string(name)}, {lean_string(predicate)})" for name, predicate in expanded_check_evidence
    )
    status_codes_text = ", ".join(f"{name} := {value}" for name, value in statuses.items())
    normalized_header = re.sub(r"\s+", " ", header).strip()
    source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    types_hash = hashlib.sha256(types.read_bytes()).hexdigest()
    policy_hash = hashlib.sha256(policy_text.encode()).hexdigest()
    return f'''import CameraLifecycle.Grab.FrameSizeIR

namespace CameraLifecycle.Grab

def compilerFrameSizeProgram : FrameSizeProgram := {{
  dimensions := {render_predicate(dimension_program)},
  product := {render_expr(product_expr)},
  limit := {render_predicate(limit_program)},
  invalidLength := {render_predicate(length_program)},
  arrayLength := {render_expr(array_length_expr)},
  control := {control},
  checks := [
  {check_text}
  ]
}}

def compilerFrameSizeBounds : FrameSizeBounds := {{
  naturalMin := ({natural_min} : Int),
  naturalMax := ({natural_max} : Int),
  positiveMin := (1 : Int),
  positiveMax := ({integer_max} : Int),
  integerMin := ({integer_min} : Int),
  integerMax := ({integer_max} : Int),
  int32Min := ({int32_min} : Int),
  int32Max := ({int32_max} : Int),
  int64Min := ({int64_min} : Int),
  int64Max := ({int64_max} : Int),
  unsigned64Max := ({(1 << 64) - 1} : Int),
  sizeMin := ({size_min} : Int),
  sizeMax := ({size_max} : Int)
}}

def compilerFrameSizeMaxPixels : Int := ({max_pixels[1]} : Int)
def compilerFrameSizeEnumCodes : List (String × Nat) := [{enum_text}]
def compilerFrameSizeStatusCodes : FrameSizeStatusCodes := {{ {status_codes_text} }}
def compilerFrameSizeResolvedTypes : List FrameSizeResolvedType := [
  {resolved_text}
]
def compilerFrameSizeSelectedNodeIds : List (String × Nat) := [{node_text}]
def compilerFrameSizeSourceLines : List Nat := [{source_text}]
def compilerFrameSizeRawNodeIds : List Nat := [{selected_ids}]
def compilerFrameSizeExpandedChecks : List (String × String) := [
  {expanded_check_text}
]
def compilerFrameSizeCompilerVersion : String := {lean_string(compiler_version.strip())}
def compilerFrameSizeCompilerTarget : String := {lean_string(compiler_target.strip())}
def compilerFrameSizeFlags : List String := [{flag_text}]
def compilerFrameSizeSourceName : String := {lean_string(source.name)}
def compilerFrameSizeSourceSha256 : String := {lean_string(source_hash)}
def compilerFrameSizeTypesSha256 : String := {lean_string(types_hash)}
def compilerFrameSizePolicyText : String := {lean_string(policy_text)}
def compilerFrameSizePolicySha256 : String := {lean_string(policy_hash)}
def compilerFrameSizeRawHeader : String := {lean_string(normalized_header)}

end CameraLifecycle.Grab
'''


def extract(source: Path, diagnostics: Path | None, types: Path = TYPES) -> str:
    source = source.resolve()
    types = types.resolve()
    cc, version, target = compiler_ir.compiler()
    with tempfile.TemporaryDirectory(prefix="gnat-frame-size-ir-") as tmp:
        out = Path(tmp)
        include = [f"-I{out}", f"-I{types.parent}", f"-I{ROOT / 'optional/aravis/src'}", f"-I{ROOT / 'src'}"]
        common = ["-c", "-gnat2022", "-gnatW8", "-ffp-contract=off", "-gnatwa", "-gnatVa", "-O0",
                  f"-gnatec={POLICY}", *include]
        compiler_ir.run([cc, *common, "-o", str(out / "amv-gige_vision_types.o"), str(types)], cwd=ROOT)
        standard = compiler_ir.run([cc, *common, "-gnatS", "-o", str(out / "amv-spec-gige_vision.o"),
                                    str(source)], cwd=ROOT)
        expanded_path = out / "expanded.log"
        compiler_ir.run([cc, *common, "-gnatG", "-gnatL", "-fdump-tree-original-raw",
                         "-o", str(out / "amv-spec-gige_vision.o"), str(source)],
                        cwd=ROOT, output=expanded_path)
        raw_path = out / "amv-spec-gige_vision.ads.006t.original"
        if not raw_path.is_file():
            raise ExtractionError("GNAT did not emit the expected Grab_Status raw GCC tree")
        if diagnostics:
            diagnostics.mkdir(parents=True, exist_ok=True)
            shutil.copy2(raw_path, diagnostics / raw_path.name)
            shutil.copy2(expanded_path, diagnostics / "gnatG-gnatL.log")
            (diagnostics / "gnatS-standard.log").write_text(standard, encoding="utf-8")
        return generate(raw_path.read_text(encoding="utf-8"), standard,
                        expanded_path.read_text(encoding="utf-8"), source, types, version, target)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=SPEC)
    parser.add_argument("--types", type=Path, default=TYPES)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--diagnostics-dir", type=Path)
    args = parser.parse_args()
    invocation_source = args.source if args.source.is_absolute() else Path.cwd() / args.source
    generated = extract(invocation_source.resolve(), args.diagnostics_dir, args.types)
    if args.check:
        if not args.output.is_file() or args.output.read_text(encoding="utf-8") != generated:
            raise ExtractionError(f"compiler-generated frame-size Lean is stale: {args.output}")
        print(f"compiler-derived frame-size IR is fresh: {args.output}")
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(generated, encoding="utf-8")
        print(f"generated compiler-derived frame-size IR: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
