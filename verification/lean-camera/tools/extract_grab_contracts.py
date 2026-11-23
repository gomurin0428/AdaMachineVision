#!/usr/bin/env python3
"""Translate the restricted Ada Grab contract subset into Lean."""

from __future__ import annotations

import argparse
from dataclasses import dataclass, field
from pathlib import Path
import re
import sys
from typing import Sequence

from extract_contracts import (
    ExtractionError,
    Parameter,
    find_statement_end,
    matching,
    parse_aspects,
    reject_operator_overloads,
    split_top,
    tokenize,
)


@dataclass(frozen=True)
class Expr:
    kind: str
    value: object = None
    children: tuple[Expr, ...] = ()


class Parser:
    def __init__(self, tokens: Sequence[str], label: str):
        self.tokens = list(tokens)
        self.position = 0
        self.label = label

    def peek(self, offset: int = 0) -> str | None:
        index = self.position + offset
        return self.tokens[index] if index < len(self.tokens) else None

    def take(self, expected: str | None = None) -> str:
        token = self.peek()
        if token is None:
            raise ExtractionError(f"{self.label}: unexpected end of expression")
        if expected is not None and token != expected:
            raise ExtractionError(
                f"{self.label}: expected {expected!r}, found {token!r} at token {self.position}"
            )
        self.position += 1
        return token

    def parse(self) -> Expr:
        result = self.expression()
        if self.peek() is not None:
            raise ExtractionError(f"{self.label}: unsupported/unconsumed token {self.peek()!r}")
        return result

    def expression(self, minimum: int = 0) -> Expr:
        left = self.prefix()
        while True:
            token = self.peek()
            if token == "or" and self.peek(1) == "else":
                precedence, operator, width = 1, "or_else", 2
            elif token == "or":
                precedence, operator, width = 1, "or", 1
            elif token == "and" and self.peek(1) == "then":
                precedence, operator, width = 2, "and_then", 2
            elif token == "and":
                precedence, operator, width = 2, "and", 1
            elif token == "not" and self.peek(1) == "in":
                precedence, operator, width = 3, "notin", 2
            elif token in ("=", "/=", "<", "<=", ">", ">=", "in"):
                precedence, operator, width = 3, token, 1
            elif token in ("+", "-"):
                precedence, operator, width = 4, token, 1
            elif token == "*":
                precedence, operator, width = 5, token, 1
            else:
                break
            if precedence < minimum:
                break
            for _ in range(width):
                self.take()
            if operator in ("in", "notin"):
                choices = [self.expression(precedence + 1)]
                while self.peek() == "|":
                    self.take("|")
                    choices.append(self.expression(precedence + 1))
                left = Expr("membership", operator == "notin", (left, *choices))
            else:
                right = self.expression(precedence + 1)
                left = Expr("binary", operator, (left, right))
        return left

    def prefix(self) -> Expr:
        token = self.peek()
        if token == "if":
            return self.if_expression()
        if token == "for":
            self.take("for")
            self.take("all")
            variable = self.take()
            if not re.fullmatch(r"[a-z][a-z0-9_]*", variable):
                raise ExtractionError(f"{self.label}: unsupported quantified variable")
            self.take("in")
            collection = self.expression()
            self.take("=>")
            body = self.expression()
            return Expr("forall", variable, (collection, body))
        if token == "not":
            self.take("not")
            return Expr("unary", "not", (self.expression(6),))
        if token in ("+", "-"):
            self.take()
            return Expr("unary", token, (self.expression(6),))
        if token == "(":
            self.take("(")
            value = self.expression()
            self.take(")")
            return value
        if token in ("true", "false", "null") or self.is_number(token):
            self.take()
            if token == "true" or token == "false":
                return Expr("bool", token == "true")
            if token == "null":
                return Expr("null")
            return Expr("number", self.number_value(token))
        if token is None or not re.fullmatch(r"[a-z][a-z0-9_]*", token):
            raise ExtractionError(f"{self.label}: unsupported expression token {token!r}")
        parts = [self.take()]
        while self.peek() == ".":
            self.take(".")
            part = self.take()
            if not re.fullmatch(r"[a-z][a-z0-9_]*", part):
                raise ExtractionError(f"{self.label}: malformed selected component")
            parts.append(part)
        attribute = None
        attribute_argument = None
        if self.peek() is not None and self.peek().startswith("'"):
            attribute = self.take()[1:]
            if attribute not in {"all", "first", "last", "length", "range"}:
                raise ExtractionError(f"{self.label}: unsupported attribute '{attribute}")
            if attribute in {"first", "last", "range"} and self.peek() == "(":
                self.take("(")
                argument = self.take()
                if not self.is_number(argument):
                    raise ExtractionError(f"{self.label}: unsupported attribute argument")
                attribute_argument = self.number_value(argument)
                self.take(")")
        name = Expr("name", (tuple(parts), attribute, attribute_argument))
        if self.peek() != "(":
            return name
        self.take("(")
        arguments: list[Expr] = []
        if self.peek() != ")":
            while True:
                arguments.append(self.expression())
                if self.peek() != ",":
                    break
                self.take(",")
        self.take(")")
        path = tuple(parts)
        if attribute is not None:
            raise ExtractionError(f"{self.label}: call on an attributed name is unsupported")
        if path[-1] == "all" or path == ("image", "pixels"):
            return Expr("index", None, (name, *arguments))
        return Expr("call", path, tuple(arguments))

    def if_expression(self) -> Expr:
        self.take("if")
        branches: list[Expr] = []
        condition = self.expression()
        self.take("then")
        branches.extend((condition, self.expression()))
        while self.peek() == "elsif":
            self.take("elsif")
            condition = self.expression()
            self.take("then")
            branches.extend((condition, self.expression()))
        otherwise = None
        if self.peek() == "else":
            self.take("else")
            otherwise = self.expression()
        if otherwise is None:
            otherwise = Expr("bool", True)
        return Expr("if", True, (*branches, otherwise))

    @staticmethod
    def is_number(token: str | None) -> bool:
        return token is not None and bool(
            re.fullmatch(r"(?:[0-9]+#[0-9a-f_]+#|[0-9][0-9_]*)", token)
        )

    @staticmethod
    def number_value(token: str) -> int:
        clean = token.replace("_", "")
        if "#" in clean:
            base, digits, _ = clean.split("#")
            return int(digits, int(base))
        return int(clean)


def expr(tokens: Sequence[str], label: str) -> Expr:
    return Parser(tokens, label).parse()


def selected(tokens: Sequence[str], pattern: Sequence[str], label: str) -> list[int]:
    hits = [i for i in range(len(tokens) - len(pattern) + 1)
            if list(tokens[i : i + len(pattern)]) == list(pattern)]
    if not hits:
        raise ExtractionError(f"{label}: declaration not found")
    return hits


def parse_grab_parameters(tokens: Sequence[str], start: int) -> tuple[tuple[Parameter, ...], int]:
    end = matching(tokens, start)
    result: list[Parameter] = []
    for group in split_top(tokens[start + 1 : end], ";"):
        if not group:
            continue
        if ":" not in group:
            raise ExtractionError("unsupported acquisition formal parameter")
        colon = group.index(":")
        names = split_top(group[:colon], ",")
        tail = group[colon + 1 :]
        if tail[:2] == ["in", "out"]:
            mode, type_tokens = "in out", tail[2:]
        elif tail[:1] == ["out"]:
            mode, type_tokens = "out", tail[1:]
        elif tail[:1] == ["in"]:
            mode, type_tokens = "in", tail[1:]
        else:
            mode, type_tokens = "in", tail
        if not type_tokens:
            raise ExtractionError("missing acquisition formal parameter type")
        for name_group in names:
            if len(name_group) != 1 or not re.fullmatch(r"[a-z][a-z0-9_]*", name_group[0]):
                raise ExtractionError("unsupported acquisition formal parameter name")
            result.append(Parameter(name_group[0], mode, tuple(type_tokens)))
    return tuple(result), end + 1


def declaration_expression(
    tokens: Sequence[str], name: str, label: str, expected_profile: tuple[tuple[Parameter, ...], tuple[str, ...]]
) -> Expr:
    hits = selected(tokens, ("function", name), f"{label} {name}")
    if len(hits) != 1:
        raise ExtractionError(f"{label}: expected one {name} declaration")
    matches: list[Expr] = []
    for hit in hits:
        parameters, cursor = parse_grab_parameters(tokens, hit + 2)
        if cursor >= len(tokens) or tokens[cursor] != "return":
            continue
        returns = []
        index = cursor + 1
        while index < len(tokens) and tokens[index] != "is":
            returns.append(tokens[index])
            index += 1
        if tuple(parameters) != expected_profile[0] or tuple(returns) != expected_profile[1]:
            continue
        if index + 1 >= len(tokens) or tokens[index + 1] != "(":
            raise ExtractionError(f"{label} {name}: unsupported expression body")
        body_start = index + 1
        body_end = matching(tokens, body_start)
        cursor = body_end + 1
        if cursor < len(tokens) and tokens[cursor] == "with":
            raise ExtractionError(f"{label} {name}: unparsed helper aspects are unsupported")
        if cursor >= len(tokens) or tokens[cursor] != ";":
            raise ExtractionError(f"{label} {name}: trailing helper syntax is unsupported")
        matches.append(expr(tokens[body_start + 1 : body_end], f"{label} {name}"))
    if len(matches) != 1:
        raise ExtractionError(f"{label}: expected exactly one {name} with the selected profile")
    return matches[0]


def operation(tokens: Sequence[str], name: str) -> tuple[dict[str, Expr], tuple[Parameter, ...]]:
    hits = selected(tokens, ("procedure", name), f"kernel {name}")
    if len(hits) != 1:
        raise ExtractionError(f"kernel: expected one procedure {name}")
    parameters, cursor = parse_grab_parameters(tokens, hits[0] + 2)
    if cursor >= len(tokens) or tokens[cursor] != "with":
        raise ExtractionError(f"kernel {name}: missing contract aspects")
    end = find_statement_end(tokens, cursor + 1)
    aspects = parse_aspects(tokens[cursor + 1 : end], f"kernel {name}")
    wanted = {"global", "depends", "post"} | ({"pre"} if name == "grab" else set())
    if set(aspects) != wanted:
        raise ExtractionError(f"kernel {name}: unsupported or missing contract aspect")
    return {key: expr(aspects[key], f"kernel {name} {key}") for key in wanted - {"global", "depends"}}, tuple(parameters)


def expect_sequence(tokens: Sequence[str], expected: Sequence[str], label: str) -> None:
    if len(selected(tokens, expected, label)) != 1:
        raise ExtractionError(f"{label}: expected exactly one declaration")


FRAME_STATUS = (
    "frame_success", "frame_bad_parameter", "frame_timeout", "frame_unsupported_payload",
    "frame_unsupported_format", "frame_invalid_dimensions", "frame_too_large",
    "frame_invalid_length", "frame_out_of_memory", "frame_error",
)
CAMERA_STATE = ("closed", "open_stopped", "streaming")
NATIVE_RESULT = (
    "native_not_called", "native_success", "native_timeout", "native_bad_parameter",
    "native_unsupported", "native_out_of_memory", "native_error",
)


def validate_enum(tokens: Sequence[str], name: str, expected: Sequence[str]) -> None:
    hits = selected(tokens, ("type", name, "is", "("), f"types {name}")
    if len(hits) != 1:
        raise ExtractionError(f"types: expected one {name} enum")
    start = hits[0] + 3
    end = matching(tokens, start)
    members = []
    for item in split_top(tokens[start + 1 : end], ","):
        if len(item) != 1:
            raise ExtractionError(f"types {name}: unsupported enum literal")
        members.append(item[0])
    if tuple(members) != tuple(expected) or tokens[end + 1] != ";":
        raise ExtractionError(f"types: {name} domain changed")


def validate_observation_record(tokens: Sequence[str]) -> None:
    hits = selected(tokens, ("type", "frame_observation", "is", "record"), "Frame_Observation")
    if len(hits) != 1:
        raise ExtractionError("types: expected one Frame_Observation record")
    start = hits[0] + 4
    end = selected(tokens[start:], ("end", "record", ";"), "Frame_Observation end")[0] + start
    fields: list[tuple[str, tuple[str, ...], tuple[str, ...]]] = []
    for group in split_top(tokens[start:end], ";"):
        if not group:
            continue
        if ":" not in group:
            raise ExtractionError("types: malformed Frame_Observation field")
        colon = group.index(":")
        names = group[:colon]
        tail = group[colon + 1 :]
        if ":=" in tail:
            split = tail.index(":=")
            type_tokens = tail[:split]
            default = tuple(tail[split + 1 :])
        else:
            type_tokens = tail
            default = ()
        if len(names) != 1 or not type_tokens:
            raise ExtractionError("types: unsupported Frame_Observation field profile")
        fields.append((names[0], tuple(type_tokens), default))
    expected = (
        ("acquisition_status", ("native_result",), ("native_error",)),
        ("byte_count", ("natural",), ("0",)),
        ("bytes", ("byte_array_access",), ("null",)),
        ("buffer_status", ("int32",), ("-", "1")),
        ("payload_type", ("unsigned_32",), ("0",)),
        ("pixel_format", ("unsigned_32",), ("0",)),
        ("width", ("int32",), ("0",)),
        ("height", ("int32",), ("0",)),
        ("source_size", ("unsigned_64",), ("0",)),
    )
    if tuple(fields) != expected:
        raise ExtractionError("types: Frame_Observation field profile changed")


def validate_pragma_set(tokens: Sequence[str], label: str,
                        expected: tuple[tuple[str, ...], ...]) -> None:
    found: list[tuple[str, ...]] = []
    index = 0
    while index < len(tokens):
        if tokens[index] != "pragma":
            index += 1
            continue
        try:
            end = tokens.index(";", index)
        except ValueError as error:
            raise ExtractionError(f"{label}: unterminated pragma") from error
        found.append(tuple(tokens[index : end + 1]))
        index = end + 1
    if sorted(found) != sorted(expected):
        raise ExtractionError(f"{label}: pragma declarations changed or are unsupported")


def reject_shadowed_standard_conversions(tokens: Sequence[str], label: str) -> None:
    standard_names = {"integer", "natural", "positive"}
    declaration_words = {"function", "procedure", "type", "subtype", "package", "task", "entry"}
    for index, token in enumerate(tokens):
        if token not in standard_names:
            continue
        previous = tokens[index - 1] if index else None
        following = tokens[index + 1] if index + 1 < len(tokens) else None
        if previous in declaration_words or following == ":":
            raise ExtractionError(f"{label}: local declaration shadows Standard conversion {token}")


def validate_sources(type_text: str, spec_text: str, kernel_text: str,
                     image_text: str, base_kernel_text: str) -> dict[str, list[str]]:
    sources = [
        tokenize(type_text, "types"), tokenize(spec_text, "spec"),
        tokenize(kernel_text, "kernel"), tokenize(image_text, "images"),
        tokenize(base_kernel_text, "base kernels"),
    ]
    types, spec, kernel, images, base = sources
    labels = ("types", "spec", "kernel", "images", "base kernels")
    for tokens, label in zip(sources, labels):
        reject_operator_overloads(tokens, label)
        reject_shadowed_standard_conversions(tokens, label)
    validity_pragma = ("pragma", "validity_checks", "(", '"F"', ")", ";")
    for tokens, label in ((types, "types"), (spec, "spec"), (kernel, "kernel"),
                          (base, "base kernels")):
        validate_pragma_set(tokens, label, (validity_pragma,))
    validate_pragma_set(images, "images", (
        validity_pragma,
        ("pragma", "assertion_level", "(", "tested", ")", ";"),
        ("pragma", "unevaluated_use_of_old", "(", "allow", ")", ";"),
    ))
    validate_pragma_set(base, "base kernels", (
        ("pragma", "validity_checks", "(", '"F"', ")", ";"),
    ))
    validate_enum(types, "camera_state", CAMERA_STATE)
    validate_enum(types, "native_result", NATIVE_RESULT)
    validate_enum(types, "frame_status", FRAME_STATUS)
    validate_observation_record(types)
    for tokens, pattern, label in (
        (types, ("package", "amv", ".", "gige_vision_types", "with", "spark_mode", "is"), "types package"),
        (spec, ("package", "amv", ".", "spec", ".", "gige_vision", "with", "spark_mode", ",", "ghost", "is"), "spec package"),
        (kernel, ("package", "amv", ".", "kernels", ".", "gige_vision", "with", "spark_mode", "is"), "kernel package"),
        (images, ("package", "amv", ".", "kernels", ".", "images", "with", "spark_mode", ",", "preelaborate", "is"), "image package"),
        (base, ("package", "amv", ".", "kernels", "with", "spark_mode", ",", "pure", "is"), "base kernel package"),
    ):
        expect_sequence(tokens, pattern, label)
    for pattern, label in (
        (("subtype", "int32", "is", "amv", ".", "kernels", ".", "int32", ";"), "Int32 alias"),
        (("subtype", "int64", "is", "amv", ".", "kernels", ".", "int64", ";"), "Int64 alias"),
        (("subtype", "unsigned_32", "is", "interfaces", ".", "unsigned_32", ";"), "Unsigned_32 alias"),
        (("subtype", "unsigned_64", "is", "interfaces", ".", "unsigned_64", ";"), "Unsigned_64 alias"),
        (("subtype", "pixel", "is", "interfaces", ".", "unsigned_8", ";"), "Pixel alias"),
        (("type", "byte_array", "is", "array", "(", "positive", "range", "<", ">", ")", "of", "pixel", ";"), "Byte_Array domain"),
        (("type", "byte_array_access", "is", "access", "all", "byte_array", ";"), "Byte_Array_Access"),
        (("max_image_pixels", ":", "constant", ":=", "2", "**", "31", "-", "1", ";"), "Max_Image_Pixels"),
        (("arv_buffer_status_success", ":", "constant", "int32", ":=", "0", ";"), "buffer success constant"),
        (("arv_buffer_status_timeout", ":", "constant", "int32", ":=", "2", ";"), "buffer timeout constant"),
        (("arv_payload_image", ":", "constant", "unsigned_32", ":=", "16#0001#", ";"), "image payload constant"),
        (("arv_pixel_format_mono_8", ":", "constant", "unsigned_32", ":=", "16#0108_0001#", ";"), "Mono8 constant"),
    ):
        expect_sequence(types, pattern, label)
    validate_integer_type(base, "int32", "-", "2", "**", "31", "..", "2", "**", "31", "-", "1")
    validate_integer_type(base, "int64", "-", "2", "**", "63", "..", "2", "**", "63", "-", "1")
    for pattern, label in (
        (("subtype", "grey_8", "is", "interfaces", ".", "unsigned_8", ";"), "Grey_8 alias"),
        (("type", "grey_8_matrix", "is", "array", "(", "natural", "range", "<", ">", ",", "natural", "range", "<", ">", ")", "of", "grey_8", ";"), "Grey_8_Matrix domain"),
        (("type", "grey_8_pixels", "is", "access", "grey_8_matrix", ";"), "Grey_8_Pixels"),
        (("type", "ks_image_8_grey_data", "is", "limited", "record", "width", ":", "int32", ":=", "0", ";", "height", ":", "int32", ":=", "0", ";", "pixels", ":", "grey_8_pixels", ";", "end", "record", ";"), "8-bit image record"),
        (("type", "ks_image_8_grey", "is", "access", "ks_image_8_grey_data", "with", "convention", "=>", "c", ";"), "8-bit image access type"),
        (("max_pixels", ":", "constant", ":=", "2", "**", "31", "-", "1", ";"), "Max_Pixels"),
    ):
        expect_sequence(images, pattern, label)
    expect_sequence(kernel, ("package", "t", "renames", "amv", ".", "gige_vision_types", ";"), "kernel T alias")
    expect_sequence(kernel, ("package", "ki", "renames", "amv", ".", "kernels", ".", "images", ";"), "kernel KI alias")
    expect_sequence(kernel, ("package", "n", "renames", "amv", ".", "gige_vision_native", ";"), "kernel N alias")
    expect_sequence(spec, ("package", "t", "renames", "amv", ".", "gige_vision_types", ";"), "spec T alias")
    expect_sequence(kernel, ("with", "amv", ".", "spec", ".", "gige_vision", ";"), "kernel spec dependency")
    expect_sequence(spec, ("with", "amv", ".", "gige_vision_types", ";"), "spec types dependency")
    return {"types": types, "spec": spec, "kernel": kernel, "images": images}


def validate_integer_type(tokens: Sequence[str], name: str, *bounds: str) -> None:
    expected = ("type", name, "is", "range", *bounds, "with", "size", "=>", "32" if name == "int32" else "64", ";")
    expect_sequence(tokens, expected, f"{name} source range")


def formal(name: str, mode: str, type_name: tuple[str, ...]) -> Parameter:
    return Parameter(name, mode, type_name)


@dataclass(frozen=True)
class TypedValue:
    type_name: str
    lower: int | None = None
    upper: int | None = None


@dataclass(frozen=True)
class RangeFacts:
    bounds: dict[tuple[object, ...], tuple[int, int]] = field(default_factory=dict)
    nonnull: frozenset[tuple[str, ...]] = frozenset()
    is_null: frozenset[tuple[str, ...]] = frozenset()


INTEGER_MIN, INTEGER_MAX = -(2**31), 2**31 - 1
NUMERIC_BOUNDS = {
    "integer": (INTEGER_MIN, INTEGER_MAX),
    "natural": (0, INTEGER_MAX),
    "positive": (1, INTEGER_MAX),
    "int32": (-(2**31), 2**31 - 1),
    "int64": (-(2**63), 2**63 - 1),
    "unsigned32": (0, 2**32 - 1),
    "unsigned64": (0, 2**64 - 1),
    "pixel": (0, 255),
}
NUMERIC_BASE = {
    "integer": "integer", "natural": "integer", "positive": "integer",
    "int32": "int32", "int64": "int64", "unsigned32": "unsigned32",
    "unsigned64": "unsigned64", "pixel": "pixel",
}
CONVERSIONS = {
    "int32": "int32", "t.int32": "int32",
    "int64": "int64", "t.int64": "int64",
    "integer": "integer", "natural": "natural", "positive": "positive",
    "unsigned_32": "unsigned32", "t.unsigned_32": "unsigned32",
    "unsigned_64": "unsigned64", "t.unsigned_64": "unsigned64",
}
FRAME_FIELDS = {
    "acquisition_status": "native_result", "byte_count": "natural",
    "bytes": "byte_array_access", "buffer_status": "int32",
    "payload_type": "unsigned32", "pixel_format": "unsigned32",
    "width": "int32", "height": "int32", "source_size": "unsigned64",
}
IMAGE_FIELDS = {"width": "int32", "height": "int32", "pixels": "grey8_matrix_access"}
ENUM_MEMBERS = {
    **{f"t.{name}": "frame_status" for name in (
        "frame_success", "frame_bad_parameter", "frame_timeout", "frame_unsupported_payload",
        "frame_unsupported_format", "frame_invalid_dimensions", "frame_too_large",
        "frame_invalid_length", "frame_out_of_memory", "frame_error",
    )},
    **{f"t.{name}": "native_result" for name in (
        "native_not_called", "native_success", "native_timeout", "native_bad_parameter",
        "native_unsupported", "native_out_of_memory", "native_error",
    )},
    **{f"t.{name}": "camera_state" for name in ("closed", "open_stopped", "streaming")},
}
CONSTANT_VALUES = {
    "t.arv_buffer_status_success": ("int32", 0),
    "t.arv_buffer_status_timeout": ("int32", 2),
    "t.arv_payload_image": ("unsigned32", 1),
    "t.arv_pixel_format_mono_8": ("unsigned32", 17301505),
    "t.max_image_pixels": ("literal", 2**31 - 1),
}


def expression_key(node: Expr) -> tuple[object, ...]:
    if node.kind == "unary" and node.value == "+":
        return expression_key(node.children[0])
    return (node.kind, node.value, *(expression_key(child) for child in node.children))


def interval_from_type(type_name: str) -> tuple[int, int] | None:
    return NUMERIC_BOUNDS.get(type_name)


def with_facts(node: Expr, value: TypedValue, facts: RangeFacts) -> TypedValue:
    bounds = facts.bounds.get(expression_key(node))
    if bounds is None:
        return value
    lower, upper = bounds
    if value.lower is not None:
        lower = max(lower, value.lower)
    if value.upper is not None:
        upper = min(upper, value.upper)
    return TypedValue(value.type_name, lower, upper)


def numeric(type_name: str) -> bool:
    return type_name == "literal" or type_name in NUMERIC_BASE


def fits(value: TypedValue, target: str) -> bool:
    bounds = interval_from_type(target)
    return (
        bounds is not None and value.lower is not None and value.upper is not None
        and bounds[0] <= value.lower <= value.upper <= bounds[1]
    )


def require_fits(value: TypedValue, target: str, where: str) -> None:
    if not fits(value, target):
        raise ExtractionError(
            f"{where}: cannot prove {value.type_name} range "
            f"[{value.lower}, {value.upper}] fits {target}"
        )


def compatible(value: TypedValue, expected: str) -> bool:
    if value.type_name == expected:
        return True
    if value.type_name == "null":
        return expected in {"byte_array_access", "image_handle", "image_data_access", "grey8_matrix_access"}
    if expected == "image_access8":
        return value.type_name in {"image_handle", "image_data_access"}
    if numeric(value.type_name) and numeric(expected):
        if value.type_name == "literal":
            return fits(value, expected)
        return NUMERIC_BASE[value.type_name] == NUMERIC_BASE[expected] and fits(value, expected)
    return False


def require_type(value: TypedValue, expected: str, where: str) -> None:
    if not compatible(value, expected):
        raise ExtractionError(f"{where}: expected {expected}, found {value.type_name}")


def compatible_operands(left: TypedValue, right: TypedValue, where: str) -> None:
    if left.type_name == "null" or right.type_name == "null":
        other = right if left.type_name == "null" else left
        if other.type_name not in {"byte_array_access", "image_handle", "image_data_access", "grey8_matrix_access"}:
            raise ExtractionError(f"{where}: null compared with {other.type_name}")
        return
    if numeric(left.type_name) and numeric(right.type_name):
        if left.type_name == "literal" and right.type_name == "literal":
            require_fits(left, "integer", where)
            require_fits(right, "integer", where)
            return
        if left.type_name == "literal":
            require_fits(left, NUMERIC_BASE[right.type_name], where)
        elif right.type_name == "literal":
            require_fits(right, NUMERIC_BASE[left.type_name], where)
        elif NUMERIC_BASE[left.type_name] != NUMERIC_BASE[right.type_name]:
            raise ExtractionError(f"{where}: incompatible numeric types {left.type_name}/{right.type_name}")
        return
    if left.type_name != right.type_name:
        raise ExtractionError(f"{where}: incompatible types {left.type_name}/{right.type_name}")


def resolve_name(
    node: Expr, env: dict[str, str], facts: RangeFacts, safety: bool,
) -> TypedValue:
    path, attribute, argument = node.value
    joined = ".".join(path)
    root_type = env.get(path[0]) if path else None
    if attribute is not None:
        if path == ("frame", "bytes", "all") and root_type == "frame_observation":
            if safety and ("frame", "bytes") not in facts.nonnull:
                raise ExtractionError("Frame.Bytes attribute access is not guarded by Bytes /= null")
            if attribute == "length" and argument is None:
                return with_facts(node, TypedValue("natural", 0, INTEGER_MAX), facts)
            if attribute == "first" and argument is None:
                return with_facts(node, TypedValue("integer", INTEGER_MIN, INTEGER_MAX), facts)
            raise ExtractionError(f"unsupported byte-array attribute/dimension {joined}'{attribute}({argument})")
        if path == ("image", "pixels") and root_type in {"image_handle", "image_data_access"}:
            if safety and ("image",) not in facts.nonnull:
                raise ExtractionError("Image.Pixels access is not guarded by Image /= null")
            if safety and ("image", "pixels") not in facts.nonnull:
                raise ExtractionError("Image.Pixels range access is not guarded by Pixels /= null")
            if attribute == "range" and argument in {1, 2}:
                return TypedValue("range")
            if attribute in {"first", "last"} and argument in {1, 2}:
                return with_facts(node, TypedValue("integer", INTEGER_MIN, INTEGER_MAX), facts)
            raise ExtractionError(f"unsupported matrix attribute/dimension {joined}'{attribute}({argument})")
        raise ExtractionError(f"unsupported attribute source {joined}'{attribute}")

    if joined in env:
        return with_facts(node, TypedValue(env[joined], *(
            interval_from_type(env[joined]) or (None, None)
        )), facts)
    if joined in ENUM_MEMBERS:
        return TypedValue(ENUM_MEMBERS[joined])
    if joined in CONSTANT_VALUES:
        type_name, value = CONSTANT_VALUES[joined]
        return TypedValue(type_name, value, value)
    if joined == "n.null_handle":
        return TypedValue("camera_handle")
    if not root_type:
        raise ExtractionError(f"unknown source identifier {joined}")
    if root_type == "frame_observation":
        if path == (path[0], "bytes"):
            return TypedValue("byte_array_access")
        if path == (path[0], "bytes", "all"):
            if safety and (path[0], "bytes") not in facts.nonnull:
                raise ExtractionError(f"{path[0].title()}.Bytes dereference is not guarded by Bytes /= null")
            return TypedValue("byte_array")
        if len(path) == 2 and path[1] in FRAME_FIELDS:
            return with_facts(node, TypedValue(FRAME_FIELDS[path[1]], *(
                interval_from_type(FRAME_FIELDS[path[1]]) or (None, None)
            )), facts)
    if root_type in {"image_handle", "image_data_access"}:
        if safety and (path[0],) not in facts.nonnull:
            raise ExtractionError("Image field access is not guarded by Image /= null")
        if len(path) == 2 and path[1] in IMAGE_FIELDS:
            field_type = IMAGE_FIELDS[path[1]]
            return with_facts(node, TypedValue(field_type, *(
                interval_from_type(field_type) or (None, None)
            )), facts)
    if root_type == "byte_array_access" and path == (path[0], "all"):
        if safety and (path[0],) not in facts.nonnull:
            raise ExtractionError("array dereference is not guarded by a non-null test")
        return TypedValue("byte_array")
    raise ExtractionError(f"unknown or invalid source field {joined} ({root_type})")


def substitute_name(node: Expr, name: str, replacement: Expr) -> Expr:
    if node.kind == "name":
        path, attribute, argument = node.value
        if path and path[0] == name:
            if replacement.kind != "name":
                return node
            new_path = (*replacement.value[0], *path[1:])
            return Expr("name", (new_path, attribute, argument))
    if node.kind == "forall" and str(node.value) == name:
        return node
    return Expr(node.kind, node.value, tuple(substitute_name(child, name, replacement) for child in node.children))


def refine_facts(
    facts: RangeFacts, node: Expr, truth: bool, env: dict[str, str],
    summaries: dict[str, Expr],
) -> RangeFacts:
    if node.kind == "unary" and node.value == "not":
        return refine_facts(facts, node.children[0], not truth, env, summaries)
    if node.kind == "binary" and node.value in {"and", "and_then", "or", "or_else"}:
        left, right = node.children
        if node.value in {"and", "and_then"} and truth:
            return refine_facts(refine_facts(facts, left, True, env, summaries), right, True, env, summaries)
        if node.value in {"or", "or_else"} and not truth:
            return refine_facts(refine_facts(facts, left, False, env, summaries), right, False, env, summaries)
        return facts
    if node.kind == "call" and truth:
        name = ".".join(node.value)
        summary = summaries.get(name)
        if summary is not None and len(node.children) == 1:
            parameter = "image" if name == "ki.valid_image" else "frame"
            expanded = substitute_name(summary, parameter, node.children[0])
            return refine_facts(facts, expanded, True, env, summaries)
        return facts
    if node.kind != "binary" or node.value not in {"=", "/=", "<", "<=", ">", ">="}:
        return facts

    left, right = node.children
    op = node.value if truth else {"=": "/=", "/=": "=", "<": ">=", "<=": ">", ">": "<=", ">=": "<"}[node.value]
    if left.kind == "null" or right.kind == "null":
        target = right if left.kind == "null" else left
        if target.kind == "name" and target.value[1] is None:
            path = target.value[0]
            equality = op == "="
            nonnull = facts.nonnull - {path} if equality else facts.nonnull | {path}
            is_null = facts.is_null | {path} if equality else facts.is_null - {path}
            return RangeFacts(dict(facts.bounds), frozenset(nonnull), frozenset(is_null))
        return facts
    if op not in {"=", "<", "<=", ">", ">="}:
        return facts

    left_value = infer_type(left, env, facts=facts, summaries=summaries, safety=False)
    right_value = infer_type(right, env, facts=facts, summaries=summaries, safety=False)
    bounds = dict(facts.bounds)

    def constrain(target: Expr, current: TypedValue, relation: str, reference: TypedValue) -> None:
        if current.lower is None or current.upper is None or reference.lower is None or reference.upper is None:
            return
        lower, upper = bounds.get(expression_key(target), (current.lower, current.upper))
        if relation == "<":
            upper = min(upper, reference.upper - 1)
        elif relation == "<=":
            upper = min(upper, reference.upper)
        elif relation == ">":
            lower = max(lower, reference.lower + 1)
        elif relation == ">=":
            lower = max(lower, reference.lower)
        elif relation == "=":
            lower, upper = max(lower, reference.lower), min(upper, reference.upper)
        bounds[expression_key(target)] = (lower, upper)

    constrain(left, left_value, op, right_value)
    reverse = {"<": ">", "<=": ">=", ">": "<", ">=": "<=", "=": "="}[op]
    constrain(right, right_value, reverse, left_value)
    return RangeFacts(bounds, facts.nonnull, facts.is_null)


def infer_type(
    node: Expr, env: dict[str, str], facts: RangeFacts | None = None,
    summaries: dict[str, Expr] | None = None, safety: bool = True,
) -> TypedValue:
    facts = facts or RangeFacts()
    summaries = summaries or {}
    kind = node.kind
    if kind == "number":
        value = int(node.value)
        return TypedValue("literal", value, value)
    if kind == "bool":
        return TypedValue("bool")
    if kind == "null":
        return TypedValue("null")
    if kind == "name":
        return resolve_name(node, env, facts, safety)
    if kind == "unary":
        child = infer_type(node.children[0], env, facts, summaries, safety)
        if node.value == "not":
            require_type(child, "bool", "not operand")
            return TypedValue("bool")
        if not numeric(child.type_name):
            raise ExtractionError(f"unary {node.value}: expected a numeric operand, found {child.type_name}")
        if child.type_name in {"unsigned32", "unsigned64", "pixel"}:
            raise ExtractionError(f"unary {node.value}: modular numeric forms are unsupported")
        result_type = "literal" if child.type_name == "literal" else (
            "integer" if child.type_name in {"natural", "positive"} else child.type_name
        )
        if node.value == "+":
            result = TypedValue(result_type, child.lower, child.upper)
        else:
            lower = -child.upper if child.upper is not None else None
            upper = -child.lower if child.lower is not None else None
            result = TypedValue(result_type, lower, upper)
        if safety:
            require_fits(result, "integer" if result_type == "literal" else result_type,
                         f"unary {node.value}")
        return with_facts(node, result, facts)
    if kind == "binary":
        op = node.value
        left_node, right_node = node.children
        left = infer_type(left_node, env, facts, summaries, safety)
        if op in {"and", "and_then", "or", "or_else"}:
            require_type(left, "bool", f"{op} left operand")
            right_facts = facts
            if op == "and_then":
                right_facts = refine_facts(facts, left_node, True, env, summaries)
            elif op == "or_else":
                right_facts = refine_facts(facts, left_node, False, env, summaries)
            right = infer_type(right_node, env, right_facts, summaries, safety)
            require_type(right, "bool", f"{op} right operand")
            return TypedValue("bool")
        right = infer_type(right_node, env, facts, summaries, safety)
        if op in {"=", "/=", "<", "<=", ">", ">="}:
            if op in {"<", "<=", ">", ">="} and not (numeric(left.type_name) and numeric(right.type_name)):
                raise ExtractionError(f"{op}: ordering requires numeric operands")
            compatible_operands(left, right, f"operator {op}")
            return TypedValue("bool")
        if op not in {"+", "-", "*"}:
            raise ExtractionError(f"unsupported binary operator {op}")
        if not (numeric(left.type_name) and numeric(right.type_name)):
            raise ExtractionError(f"operator {op}: expected numeric operands")
        if left.type_name in {"unsigned32", "unsigned64", "pixel"} or right.type_name in {"unsigned32", "unsigned64", "pixel"}:
            raise ExtractionError(f"operator {op}: modular arithmetic is unsupported")
        if left.type_name == "literal" and right.type_name == "literal":
            result_type = "integer"
        else:
            concrete = right.type_name if left.type_name == "literal" else left.type_name
            other = left.type_name if left.type_name == "literal" else right.type_name
            if other != "literal" and NUMERIC_BASE[concrete] != NUMERIC_BASE[other]:
                raise ExtractionError(f"operator {op}: incompatible numeric types {left.type_name}/{right.type_name}")
            result_type = NUMERIC_BASE[concrete]
        if left.lower is None or left.upper is None or right.lower is None or right.upper is None:
            lower = upper = None
        elif op == "+":
            lower, upper = left.lower + right.lower, left.upper + right.upper
        elif op == "-":
            lower, upper = left.lower - right.upper, left.upper - right.lower
        else:
            products = (left.lower * right.lower, left.lower * right.upper,
                        left.upper * right.lower, left.upper * right.upper)
            lower, upper = min(products), max(products)
        result = TypedValue(result_type, lower, upper)
        if safety:
            require_fits(result, result_type, f"operator {op}")
        return with_facts(node, result, facts)
    if kind == "membership":
        left = infer_type(node.children[0], env, facts, summaries, safety)
        for choice in node.children[1:]:
            compatible_operands(left, infer_type(choice, env, facts, summaries, safety), "membership")
        return TypedValue("bool")
    if kind == "if":
        pairs = list(zip(node.children[0:-1:2], node.children[1:-1:2]))
        remaining = facts
        branches: list[TypedValue] = []
        for condition, value in pairs:
            condition_type = infer_type(condition, env, remaining, summaries, safety)
            require_type(condition_type, "bool", "conditional branch condition")
            branch_facts = refine_facts(remaining, condition, True, env, summaries)
            branches.append(infer_type(value, env, branch_facts, summaries, safety))
            remaining = refine_facts(remaining, condition, False, env, summaries)
        branches.append(infer_type(node.children[-1], env, remaining, summaries, safety))
        result_type = branches[0].type_name
        for branch in branches[1:]:
            if result_type == "literal":
                result_type = branch.type_name
            elif branch.type_name == "literal" or branch.type_name == result_type:
                continue
            elif numeric(result_type) and numeric(branch.type_name) and (
                NUMERIC_BASE[result_type] == NUMERIC_BASE[branch.type_name]
            ):
                result_type = NUMERIC_BASE[result_type]
            else:
                raise ExtractionError(f"conditional branches have incompatible types {result_type}/{branch.type_name}")
        if result_type == "literal":
            result_type = "integer"
        lower_values = [branch.lower for branch in branches if branch.lower is not None]
        upper_values = [branch.upper for branch in branches if branch.upper is not None]
        result = TypedValue(result_type,
                            min(lower_values) if len(lower_values) == len(branches) else None,
                            max(upper_values) if len(upper_values) == len(branches) else None)
        for branch in branches:
            require_type(branch, result_type, "conditional result")
        return with_facts(node, result, facts)
    if kind == "forall":
        variable = str(node.value)
        if variable in env:
            raise ExtractionError(f"quantified variable {variable} shadows an existing binding")
        collection, body = node.children
        collection_type = infer_type(collection, env, facts, summaries, safety)
        if collection_type.type_name != "range":
            raise ExtractionError("only Image.Pixels'Range quantified loops are supported")
        updated = dict(env)
        updated[variable] = "natural"
        body_type = infer_type(body, updated, facts, summaries, safety)
        require_type(body_type, "bool", "quantified body")
        return TypedValue("bool")
    if kind == "index":
        base = node.children[0]
        if base.kind != "name":
            raise ExtractionError("unsupported indexed array prefix")
        array_type = infer_type(base, env, facts, summaries, safety).type_name
        arguments = node.children[1:]
        if array_type == "byte_array" and len(arguments) == 1:
            require_type(infer_type(arguments[0], env, facts, summaries, safety), "positive", "Byte_Array index")
            return TypedValue("pixel", 0, 255)
        if array_type == "grey8_matrix_access" and len(arguments) == 2:
            if safety and ("image", "pixels") not in facts.nonnull:
                raise ExtractionError("Image.Pixels indexing is not guarded by Pixels /= null")
            for argument in arguments:
                require_type(infer_type(argument, env, facts, summaries, safety), "natural", "Grey_8_Matrix index")
            return TypedValue("pixel", 0, 255)
        raise ExtractionError(f"unsupported indexed array/type {array_type}/{len(arguments)}")
    if kind == "call":
        name = ".".join(node.value)
        target = CONVERSIONS.get(name)
        if target is not None:
            if len(node.children) != 1:
                raise ExtractionError(f"{name}: conversion profile changed")
            argument = infer_type(node.children[0], env, facts, summaries, safety)
            if argument.type_name not in NUMERIC_BASE and argument.type_name != "literal":
                raise ExtractionError(f"{name}: unsupported conversion source {argument.type_name}")
            if argument.type_name == "pixel":
                raise ExtractionError(f"{name}: Pixel conversions are unsupported")
            converted = TypedValue(target, argument.lower, argument.upper)
            if safety:
                require_fits(argument, target, name)
            return with_facts(node, converted, facts)
        profiles = {
            "amv.spec.gige_vision.grab_status": (("camera_state", "natural", "frame_observation"), "frame_status"),
            "amv.spec.gige_vision.pixel_at": (("frame_observation", "natural", "natural"), "pixel"),
            "t.valid_observation": (("frame_observation",), "bool"),
            "ki.valid_image": (("image_access8",), "bool"),
        }
        if name not in profiles:
            raise ExtractionError(f"unsupported call {name}")
        arguments, result_type = profiles[name]
        if len(node.children) != len(arguments):
            raise ExtractionError(f"{name}: expected {len(arguments)} arguments, found {len(node.children)}")
        for index, (argument, expected) in enumerate(zip(node.children, arguments), start=1):
            require_type(infer_type(argument, env, facts, summaries, safety), expected,
                         f"{name} argument {index}")
        return TypedValue(result_type, *(interval_from_type(result_type) or (None, None)))
    raise ExtractionError(f"unsupported expression type for {kind}")


STATUS_NAMES = {
    "frame_success": "success", "frame_bad_parameter": "badParameter",
    "frame_timeout": "timeout", "frame_unsupported_payload": "unsupportedPayload",
    "frame_unsupported_format": "unsupportedFormat", "frame_invalid_dimensions": "invalidDimensions",
    "frame_too_large": "tooLarge", "frame_invalid_length": "invalidLength",
    "frame_out_of_memory": "outOfMemory", "frame_error": "error",
}
NATIVE_NAMES = {
    "native_not_called": "notCalled", "native_success": "success",
    "native_timeout": "timeout", "native_bad_parameter": "badParameter",
    "native_unsupported": "unsupported", "native_out_of_memory": "outOfMemory",
    "native_error": "error",
}
STATE_NAMES = {"closed": "closed", "open_stopped": "openStopped", "streaming": "streaming"}


def emit_name(node: Expr, env: dict[str, str]) -> str:
    path, attribute, argument = node.value
    joined = ".".join(path)
    if attribute:
        if joined == "frame.bytes.all":
            if attribute == "first":
                return "byteFirst frame"
            if attribute == "length":
                return "byteLength frame"
        if joined == "image.pixels" and attribute in {"first", "last"}:
            axes = {
                ("first", 1): "imageFirstRow image", ("last", 1): "imageLastRow image",
                ("first", 2): "imageFirstColumn image", ("last", 2): "imageLastColumn image",
            }
            if (attribute, argument) in axes:
                return axes[(attribute, argument)]
        raise ExtractionError(f"unsupported attribute source {joined}'{attribute}")
    if joined in env:
        return env[joined]
    if joined.startswith("t."):
        literal = joined[2:]
        if literal in STATUS_NAMES:
            return "." + STATUS_NAMES[literal]
        if literal in NATIVE_NAMES:
            return "." + NATIVE_NAMES[literal]
        if literal in STATE_NAMES:
            return "." + STATE_NAMES[literal]
        constants = {
            "arv_buffer_status_success": "0", "arv_buffer_status_timeout": "2",
            "arv_payload_image": "1", "arv_pixel_format_mono_8": "17301505",
            "max_image_pixels": "2147483647",
        }
        if literal in constants:
            return constants[literal]
    if joined == "n.null_handle":
        return "0"
    fields = {
        "frame.acquisition_status": "frame.acquisitionStatus",
        "frame.byte_count": "frame.byteCount",
        "frame.bytes": "frame.bytes",
        "frame.buffer_status": "frame.bufferStatus",
        "frame.payload_type": "frame.payloadType",
        "frame.pixel_format": "frame.pixelFormat",
        "frame.width": "frame.width", "frame.height": "frame.height",
        "frame.source_size": "frame.sourceSize",
        "observation.acquisition_status": "observation.acquisitionStatus",
        "observation.byte_count": "observation.byteCount",
        "observation.bytes": "observation.bytes",
        "observation.buffer_status": "observation.bufferStatus",
        "observation.payload_type": "observation.payloadType",
        "observation.pixel_format": "observation.pixelFormat",
        "observation.width": "observation.width", "observation.height": "observation.height",
        "observation.source_size": "observation.sourceSize",
        "image.width": "(image.map ImageData.width).getD 0",
        "image.height": "(image.map ImageData.height).getD 0",
    }
    if joined in fields:
        return fields[joined]
    raise ExtractionError(f"unsupported source name {joined}")


def lean_numeric_representation(node: Expr, type_env: dict[str, str]) -> str | None:
    if node.kind == "number":
        return None
    if node.kind == "name":
        type_name = infer_type(node, type_env, safety=False).type_name
    elif node.kind == "unary":
        if node.value == "not":
            return None
        source = infer_type(node.children[0], type_env, safety=False).type_name
        if node.value == "-" or source in {"natural", "positive"}:
            return "int"
        return lean_numeric_representation(node.children[0], type_env)
    elif node.kind == "call":
        name = ".".join(node.value)
        if name in CONVERSIONS:
            return "int" if CONVERSIONS[name] in {"integer", "int32", "int64"} else "nat"
        type_name = infer_type(node, type_env, safety=False).type_name
    elif node.kind == "index":
        return "uint8"
    elif node.kind == "binary" and node.value in {"+", "-", "*"}:
        type_name = infer_type(node, type_env, safety=False).type_name
        if type_name in {"int32", "int64"}:
            return "int"
        if type_name == "integer":
            left, right = node.children
            values = (infer_type(left, type_env, safety=False), infer_type(right, type_env, safety=False))
            nonnegative = all(
                value.type_name in {"natural", "positive", "unsigned32", "unsigned64"}
                or (value.type_name == "literal" and value.lower is not None and value.lower >= 0)
                for value in values
            )
            return "nat" if node.value in {"+", "*"} and nonnegative else "int"
        return None
    elif node.kind == "if":
        type_name = infer_type(node, type_env, safety=False).type_name
    else:
        return None
    return {
        "natural": "nat", "positive": "nat", "unsigned32": "nat", "unsigned64": "nat",
        "pixel": "uint8", "integer": "int", "int32": "int", "int64": "int",
    }.get(type_name)


def emit_as(node: Expr, env: dict[str, str], type_env: dict[str, str], target: str,
            proposition: bool = False) -> str:
    value = emit(node, env, proposition, type_env)
    representation = lean_numeric_representation(node, type_env)
    if target == "int" and representation == "nat":
        return f"(Int.ofNat ({value}))"
    if target == "nat" and representation == "int":
        return f"(Int.toNat ({value}))"
    return value


def emit(
    node: Expr, env: dict[str, str], proposition: bool = False,
    type_env: dict[str, str] | None = None,
) -> str:
    type_env = type_env or {}
    kind = node.kind
    if kind == "number":
        return str(node.value)
    if kind == "bool":
        if proposition:
            return "True" if node.value else "False"
        return "true" if node.value else "false"
    if kind == "null":
        return "none"
    if kind == "name":
        path, attribute, argument = node.value
        if attribute == "range":
            raise ExtractionError("range attribute is only supported as a quantified domain")
        if path == ("image", "pixels") and attribute is None:
            return "(image.bind ImageData.pixels)"
        if proposition and infer_type(node, type_env, safety=False).type_name == "bool":
            return f"({emit_name(node, env)} = true)"
        return emit_name(node, env)
    if kind == "unary":
        value = emit(node.children[0], env, proposition, type_env)
        if node.value == "not":
            return f"(¬ {value})" if proposition else f"(!({value}))"
        if node.value == "+":
            source_type = infer_type(node.children[0], type_env, safety=False).type_name
            return f"(Int.ofNat ({value}))" if source_type in {"natural", "positive"} else value
        source_type = infer_type(node.children[0], type_env, safety=False).type_name
        if source_type in {"natural", "positive"}:
            return f"(- (Int.ofNat ({value})))"
        return f"(-({value}))"
    if kind == "binary":
        op = node.value
        left, right = node.children
        a, b = emit(left, env, proposition, type_env), emit(right, env, proposition, type_env)
        if op in {"and", "and_then", "or", "or_else"}:
            conjunction = op in {"and", "and_then"}
            symbol = ("∧" if conjunction else "∨") if proposition else ("&&" if conjunction else "||")
            return f"({a} {symbol} {b})"
        if op == "=" and proposition and infer_type(left, type_env, safety=False).type_name == "bool" and infer_type(right, type_env, safety=False).type_name == "bool":
            return f"({emit(left, env, True, type_env)} ↔ {emit(right, env, True, type_env)})"
        if op == "/=" and proposition and infer_type(left, type_env, safety=False).type_name == "bool" and infer_type(right, type_env, safety=False).type_name == "bool":
            return f"¬ ({emit(left, env, True, type_env)} ↔ {emit(right, env, True, type_env)})"
        if op in {"=", "/=", "<", "<=", ">", ">="}:
            left_type = infer_type(left, type_env, safety=False)
            right_type = infer_type(right, type_env, safety=False)
            if numeric(left_type.type_name) and numeric(right_type.type_name):
                base = NUMERIC_BASE.get(left_type.type_name, "integer")
                if base == "integer":
                    nat_values = all(
                        value.type_name in {"natural", "positive", "unsigned32", "unsigned64"}
                        or (value.type_name == "literal" and value.lower is not None and value.lower >= 0)
                        for value in (left_type, right_type)
                    )
                    representation = "nat" if nat_values else "int"
                elif base in {"int32", "int64"}:
                    representation = "int"
                elif base == "pixel":
                    representation = "uint8"
                else:
                    representation = "nat"
                a = emit_as(left, env, type_env, representation, proposition)
                b = emit_as(right, env, type_env, representation, proposition)
        if not proposition and op in {"=", "/="} and (
            left.kind == "null" or right.kind == "null"
        ):
            option = right if left.kind == "null" else left
            predicate = "isNone" if op == "=" else "isSome"
            return f"({emit(option, env, False, type_env)}.{predicate})"
        if op in {"=", "/=", "<", "<=", ">", ">="}:
            if proposition:
                symbols = {"=": "=", "/=": "≠", "<": "<", "<=": "≤", ">": ">", ">=": "≥"}
                return f"({a} {symbols[op]} {b})"
            if op == "=":
                return f"({a} == {b})"
            if op == "/=":
                return f"({a} != {b})"
            symbols = {"<": "<", "<=": "≤", ">": ">", ">=": "≥"}
            return f"(decide ({a} {symbols[op]} {b}))"
        if op in {"+", "-", "*"}:
            representation = lean_numeric_representation(node, type_env)
            if representation in {"int", "nat"}:
                a = emit_as(left, env, type_env, representation)
                b = emit_as(right, env, type_env, representation)
        return f"({a} {op} {b})"
    if kind == "membership":
        left = emit(node.children[0], env, proposition, type_env)
        pieces = []
        for choice in node.children[1:]:
            right = emit(choice, env, proposition, type_env)
            pieces.append(f"({left} {'=' if proposition else '=='} {right})")
        result = (" ∨ " if proposition else " || ").join(pieces)
        return f"({('¬ ' if proposition else '!')}({result}))" if node.value else f"({result})"
    if kind == "if":
        pairs = list(zip(node.children[0:-1:2], node.children[1:-1:2] if node.value else node.children[1::2]))
        otherwise = node.children[-1] if node.value else None
        representation = lean_numeric_representation(node, type_env)
        if representation in {"int", "nat"}:
            result = emit_as(otherwise, env, type_env, representation, proposition) if otherwise else "false"
        else:
            result = emit(otherwise, env, proposition, type_env) if otherwise else "false"
        for condition, value in reversed(pairs):
            if representation in {"int", "nat"}:
                branch = emit_as(value, env, type_env, representation, proposition)
            else:
                branch = emit(value, env, proposition, type_env)
            result = f"(if {emit(condition, env, False, type_env)} then {branch} else {result})"
        return result
    if kind == "forall":
        variable = str(node.value)
        collection, body = node.children
        if collection.kind != "name" or collection.value[1] != "range" or collection.value[0] != ("image", "pixels"):
            raise ExtractionError("only Image.Pixels'Range quantified loops are supported")
        axis = collection.value[2]
        if axis not in (1, 2):
            raise ExtractionError("unsupported matrix range dimension")
        updated = dict(env)
        lean_variable = f"q_{variable}"
        updated[variable] = lean_variable
        updated_types = dict(type_env)
        updated_types[variable] = "natural"
        return f"(∀ ({lean_variable} : Nat), imageRangeContains image {axis} {lean_variable} = true → {emit(body, updated, True, updated_types)})"
    if kind == "index":
        base = node.children[0]
        arguments = node.children[1:]
        if base.kind != "name":
            raise ExtractionError("unsupported indexed array prefix")
        path = base.value[0]
        if path == ("frame", "bytes", "all") and len(arguments) == 1:
            return f"byteAt frame {emit(arguments[0], env, False, type_env)}"
        if path == ("image", "pixels") and len(arguments) == 2:
            return f"imagePixel image {emit(arguments[0], env, False, type_env)} {emit(arguments[1], env, False, type_env)}"
        raise ExtractionError(f"unsupported indexed array {'.'.join(path)}")
    if kind == "call":
        name = ".".join(node.value)
        if name in CONVERSIONS:
            if len(node.children) != 1:
                raise ExtractionError(f"{name}: conversion profile changed")
            arg = node.children[0]
            value = emit(arg, env, False, type_env)
            source_representation = lean_numeric_representation(arg, type_env)
            target_type = CONVERSIONS[name]
            if target_type in {"integer", "int32", "int64"}:
                if source_representation == "nat":
                    return f"(Int.ofNat ({value}))"
                return value
            if source_representation == "int":
                return f"(Int.toNat ({value}))"
            return value
        if name == "amv.spec.gige_vision.grab_status" and len(node.children) == 3:
            return f"grabStatusAda {emit(node.children[0], env, False, type_env)} {emit(node.children[1], env, False, type_env)} {emit(node.children[2], env, False, type_env)}"
        if name == "amv.spec.gige_vision.pixel_at" and len(node.children) == 3:
            return f"pixelAtAda {emit(node.children[0], env, False, type_env)} {emit(node.children[1], env, False, type_env)} {emit(node.children[2], env, False, type_env)}"
        if name == "t.valid_observation" and len(node.children) == 1:
            result = f"validObservationAda {emit(node.children[0], env, False, type_env)}"
            return f"({result} = true)" if proposition else result
        if name == "ki.valid_image" and len(node.children) == 1:
            result = f"validImageAda {emit(node.children[0], env, False, type_env)}"
            return f"({result} = true)" if proposition else result
        raise ExtractionError(f"unsupported call {name}")
    raise ExtractionError(f"unsupported expression node {kind}")


def emit_prop(node: Expr, env: dict[str, str], type_env: dict[str, str]) -> str:
    if node.kind in {"binary", "membership", "unary", "forall"}:
        return emit(node, env, True, type_env)
    if node.kind == "if":
        return emit(node, env, True, type_env)
    if node.kind == "bool":
        return "True" if node.value else "False"
    if node.kind == "call":
        return f"({emit(node, env, False, type_env)} = true)"
    if node.kind == "name" and infer_type(node, type_env, safety=False).type_name == "bool":
        return f"({emit(node, env, False, type_env)} = true)"
    raise ExtractionError(f"unsupported bare Boolean contract expression: {node.kind}")


def function_environment(*names: tuple[str, str]) -> dict[str, str]:
    return {source: lean for source, lean in names}


def generate(source_root: Path, kernel_root: Path) -> str:
    type_text = (source_root / "amv-gige_vision_types.ads").read_text(encoding="utf-8")
    spec_text = (source_root / "amv-spec-gige_vision.ads").read_text(encoding="utf-8")
    kernel_text = (source_root / "amv-kernels-gige_vision.ads").read_text(encoding="utf-8")
    image_text = (kernel_root / "amv-kernels-images.ads").read_text(encoding="utf-8")
    base_kernel_text = (kernel_root / "amv-kernels.ads").read_text(encoding="utf-8")
    tokens = validate_sources(type_text, spec_text, kernel_text, image_text, base_kernel_text)
    type_tokens, spec_tokens, kernel_tokens, image_tokens = (
        tokens["types"], tokens["spec"], tokens["kernel"], tokens["images"]
    )
    valid_obs = declaration_expression(
        type_tokens, "valid_observation", "types",
        ((formal("frame", "in", ("frame_observation",)),), ("boolean",)),
    )
    # Signatures are checked from the complete Ada profile, including modes.
    grab_status = function_body(spec_tokens, "grab_status", (
        formal("state", "in", ("t", ".", "camera_state")),
        formal("timeout", "in", ("natural",)),
        formal("frame", "in", ("t", ".", "frame_observation")),
    ), ("t", ".", "frame_status"), "spec")
    pixel_at = function_body(spec_tokens, "pixel_at", (
        formal("frame", "in", ("t", ".", "frame_observation")),
        formal("x", "in", ("natural",)), formal("y", "in", ("natural",)),
    ), ("t", ".", "pixel"), "spec")
    valid_image = function_body(image_tokens, "valid_image", (
        formal("image", "in", ("access", "constant", "ks_image_8_grey_data")),
    ), ("boolean",), "images")
    # Also validate the selected lifecycle and operation declarations exactly.
    grab_aspects, grab_parameters = operation(kernel_tokens, "grab")
    build_aspects, build_parameters = operation(kernel_tokens, "build_frame")
    expected_grab = (
        formal("state", "in", ("t", ".", "camera_state")),
        formal("handle", "in", ("n", ".", "camera_handle")),
        formal("timeout", "in", ("natural",)),
        formal("image", "out", ("ki", ".", "ks_image_8_grey")),
        formal("status", "out", ("t", ".", "frame_status")),
        formal("observation", "out", ("t", ".", "frame_observation")),
    )
    expected_build = (
        formal("state", "in", ("t", ".", "camera_state")),
        formal("timeout", "in", ("natural",)),
        formal("observation", "in", ("t", ".", "frame_observation")),
        formal("image", "out", ("ki", ".", "ks_image_8_grey")),
        formal("status", "out", ("t", ".", "frame_status")),
    )
    if grab_parameters != expected_grab or build_parameters != expected_build:
        raise ExtractionError("kernel: Grab or Build_Frame signature/modes changed")
    env_grab = function_environment(("state", "state"), ("handle", "handle"), ("timeout", "timeout"),
                                    ("image", "image"), ("status", "status"), ("observation", "observation"))
    env_build = function_environment(("state", "state"), ("timeout", "timeout"),
                                     ("observation", "observation"), ("image", "image"), ("status", "status"))
    env_frame = function_environment(
        ("frame.acquisition_status", "frame.acquisitionStatus"),
        ("frame.byte_count", "frame.byteCount"),
        ("frame.bytes", "frame.bytes"),
        ("frame.buffer_status", "frame.bufferStatus"),
        ("frame.payload_type", "frame.payloadType"),
        ("frame.pixel_format", "frame.pixelFormat"),
        ("frame.width", "frame.width"), ("frame.height", "frame.height"),
        ("frame.source_size", "frame.sourceSize"),
    )
    fn_env = function_environment(
        ("state", "state"), ("timeout", "timeout"),
        ("frame.acquisition_status", "frame.acquisitionStatus"),
        ("frame.byte_count", "frame.byteCount"), ("frame.bytes", "frame.bytes"),
        ("frame.buffer_status", "frame.bufferStatus"), ("frame.payload_type", "frame.payloadType"),
        ("frame.pixel_format", "frame.pixelFormat"), ("frame.width", "frame.width"),
        ("frame.height", "frame.height"), ("frame.source_size", "frame.sourceSize"),
        ("x", "x"), ("y", "y"),
    )
    type_env_grab = {
        "state": "camera_state", "handle": "camera_handle", "timeout": "natural",
        "image": "image_handle", "status": "frame_status", "observation": "frame_observation",
    }
    type_env_build = {
        "state": "camera_state", "timeout": "natural", "observation": "frame_observation",
        "image": "image_handle", "status": "frame_status",
    }
    type_env_frame = {"frame": "frame_observation"}
    type_env_status = {"state": "camera_state", "timeout": "natural", "frame": "frame_observation"}
    type_env_pixel = {"frame": "frame_observation", "x": "natural", "y": "natural"}
    type_env_image = {"image": "image_data_access"}
    grab_pre = grab_aspects["pre"]
    grab_post = grab_aspects["post"]
    build_post = build_aspects["post"]
    summaries = {"t.valid_observation": valid_obs, "ki.valid_image": valid_image}
    for label, expression, type_env, expected in (
        ("Grab_Status", grab_status, type_env_status, "frame_status"),
        ("Pixel_At", pixel_at, type_env_pixel, "pixel"),
        ("Valid_Observation", valid_obs, type_env_frame, "bool"),
        ("Valid_Image", valid_image, type_env_image, "bool"),
        ("Grab Pre", grab_pre, type_env_grab, "bool"),
        ("Grab Post", grab_post, type_env_grab, "bool"),
        ("Build_Frame Post", build_post, type_env_build, "bool"),
    ):
        require_type(infer_type(expression, type_env, summaries=summaries), expected, label)
    grab_status_body = emit(grab_status, fn_env, type_env=type_env_status)
    pixel_at_body = emit(pixel_at, fn_env, type_env=type_env_pixel)
    valid_obs_body = emit(valid_obs, env_frame, type_env=type_env_frame)
    valid_image_body = emit(valid_image, function_environment(("image", "image")), type_env=type_env_image)
    pre_body = emit(grab_pre, env_grab, type_env=type_env_grab)
    grab_post_body = emit_prop(grab_post, env_grab, type_env_grab)
    build_post_body = emit_prop(build_post, env_build, type_env_build)
    return f'''import CameraLifecycle.Grab.Domain

namespace CameraLifecycle.Grab.Generated

open CameraLifecycle.Model
open CameraLifecycle.Grab

def grabStatusAda (state : CameraState) (timeout : Nat) (frame : Observation) : FrameStatus :=
  {grab_status_body}

def pixelAtAda (frame : Observation) (x y : Nat) : UInt8 :=
  letI : OfNat UInt8 0 := ⟨byteZero⟩
  {pixel_at_body}

def validObservationAda (frame : Observation) : Bool :=
  {valid_obs_body}

def validImageAda (image : Image) : Bool :=
  {valid_image_body}

def grabPreAda (state : CameraState) (handle : Nat) : Bool :=
  {pre_body}

def grabPostAda (state : CameraState) (timeout : Nat) (image : Image)
    (status : FrameStatus) (observation : Observation) : Prop :=
  {grab_post_body}

def buildFramePostAda (state : CameraState) (timeout : Nat) (observation : Observation)
    (image : Image) (status : FrameStatus) : Prop :=
  {build_post_body}

def grabRelationAda (state : CameraState) (handle timeout : Nat) (image : Image)
    (status : FrameStatus) (observation : Observation) : Prop :=
  observationDomain observation ∧ timeout ≤ naturalMax ∧ imageDomain image ∧
  grabPreAda state handle = true ∧
  grabPostAda state timeout image status observation

def buildFrameRelationAda (state : CameraState) (timeout : Nat) (observation : Observation)
    (image : Image) (status : FrameStatus) : Prop :=
  observationDomain observation ∧ timeout ≤ naturalMax ∧ imageDomain image ∧
  buildFramePostAda state timeout observation image status

end CameraLifecycle.Grab.Generated
'''


def function_body(tokens: Sequence[str], name: str, expected_parameters: tuple[Parameter, ...],
                 expected_return: tuple[str, ...], label: str) -> Expr:
    hits = selected(tokens, ("function", name), f"{label} {name}")
    if name == "valid_image" and len(hits) != 2:
        raise ExtractionError("images: expected exactly the two Valid_Image overloads")
    if name != "valid_image" and len(hits) != 1:
        raise ExtractionError(f"{label}: expected one {name} declaration")
    bodies = []
    profiles = []
    for hit in hits:
        parameters, cursor = parse_grab_parameters(tokens, hit + 2)
        if cursor >= len(tokens) or tokens[cursor] != "return":
            continue
        return_tokens = []
        index = cursor + 1
        while index < len(tokens) and tokens[index] != "is":
            return_tokens.append(tokens[index])
            index += 1
        profiles.append((parameters, tuple(return_tokens)))
        if tuple(parameters) != expected_parameters or tuple(return_tokens) != expected_return:
            continue
        if index + 1 >= len(tokens) or tokens[index + 1] != "(":
            raise ExtractionError(f"{label} {name}: unsupported expression body")
        start = index + 1
        end = matching(tokens, start)
        if end + 1 >= len(tokens) or tokens[end + 1] != ";":
            raise ExtractionError(f"{label} {name}: aspects/trailing syntax unsupported")
        bodies.append(expr(tokens[start + 1 : end], f"{label} {name}"))
    if name == "valid_image":
        expected_overloads = {
            ((formal("image", "in", ("access", "constant", "ks_image_8_grey_data")),), ("boolean",)),
            ((formal("image", "in", ("access", "constant", "ks_image_16_grey_data")),), ("boolean",)),
        }
        if len(profiles) != len(expected_overloads) or set(profiles) != expected_overloads:
            raise ExtractionError("images: Valid_Image overload profiles changed")
    if len(bodies) != 1:
        raise ExtractionError(f"{label}: expected one {name} with the selected profile")
    return bodies[0]


def main() -> int:
    repository_root = Path(__file__).resolve().parents[3]
    project_dir = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, default=repository_root / "optional" / "aravis" / "src")
    parser.add_argument("--kernel-root", type=Path, default=repository_root / "src")
    parser.add_argument("--output", type=Path, default=project_dir / "CameraLifecycle" / "Grab" / "Generated.lean")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        generated = generate(args.source_root, args.kernel_root)
        if args.check:
            if not args.output.exists() or args.output.read_text(encoding="utf-8") != generated:
                raise ExtractionError(f"generated Grab source is stale: run {Path(__file__).name}")
            print(f"generated Grab source matches Ada contracts: {args.output}")
        else:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(generated, encoding="utf-8")
            print(f"generated Grab source: {args.output}")
    except (ExtractionError, OSError) as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
