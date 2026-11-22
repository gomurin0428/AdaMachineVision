#!/usr/bin/env python3
"""Translate the supported camera lifecycle Ada expression subset to Lean."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import re
import sys
from typing import Iterable, Sequence


class ExtractionError(Exception):
    pass


@dataclass(frozen=True)
class Name:
    parts: tuple[str, ...]
    attribute: str | None = None


@dataclass(frozen=True)
class BoolLiteral:
    value: bool


@dataclass(frozen=True)
class Call:
    name: tuple[str, ...]
    arguments: tuple[Expr, ...]


@dataclass(frozen=True)
class Binary:
    operator: str
    left: Expr
    right: Expr


@dataclass(frozen=True)
class Negation:
    value: Expr


@dataclass(frozen=True)
class IfExpression:
    branches: tuple[tuple[Expr, Expr], ...]
    otherwise: Expr | None


@dataclass(frozen=True)
class CaseExpression:
    selector: Expr
    branches: tuple[tuple[tuple[Name, ...], Expr], ...]


Expr = Name | BoolLiteral | Call | Binary | Negation | IfExpression | CaseExpression


TOKEN_RE = re.compile(
    r"(?P<space>\s+)"
    r"|(?P<comment>--[^\n]*)"
    r'|(?P<string>"(?:[^"]|"")*")'
    r"|(?P<char>'(?:''|[^'])')"
    r"|(?P<attribute>'[A-Za-z][A-Za-z0-9_]*)"
    r"|(?P<identifier>[A-Za-z][A-Za-z0-9_]*)"
    r"|(?P<number>(?:[0-9]+#[0-9A-Fa-f_]+#|[0-9][0-9_]*))"
    r"|(?P<operator>/=|=>|:=|<=|>=|\*\*|\.\.|[()\[\]{},;:.+\-*/=<>&|'])",
    re.DOTALL,
)


def tokenize(text: str, label: str) -> list[str]:
    result: list[str] = []
    position = 0
    while position < len(text):
        match = TOKEN_RE.match(text, position)
        if match is None:
            raise ExtractionError(f"{label}: unsupported character at offset {position}")
        position = match.end()
        kind = match.lastgroup
        if kind in ("space", "comment"):
            continue
        token = match.group()
        if kind in ("identifier", "attribute"):
            token = token.lower()
        result.append(token)
    return result


def reject_operator_overloads(tokens: Sequence[str], label: str) -> None:
    for index, token in enumerate(tokens[:-1]):
        designator = tokens[index + 1]
        if token == "function" and designator.startswith('"') and designator.endswith('"'):
            raise ExtractionError(f"{label}: local Ada operator function declarations are unsupported")


CONTRACT_PRAGMAS = frozenset(
    {
        "precondition",
        "postcondition",
        "contract_cases",
        "refined_post",
        "type_invariant",
        "default_initial_condition",
        "initial_condition",
    }
)
ALLOWED_PRAGMAS = frozenset({"validity_checks"})


def reject_unparsed_pragmas(tokens: Sequence[str], label: str) -> None:
    for index, token in enumerate(tokens):
        if token != "pragma":
            continue
        name = tokens[index + 1] if index + 1 < len(tokens) else "<missing>"
        if name in CONTRACT_PRAGMAS:
            raise ExtractionError(f"{label}: contract pragma {name} is unsupported")
        if name not in ALLOWED_PRAGMAS:
            raise ExtractionError(f"{label}: unparsed pragma {name} is unsupported")


def split_top(tokens: Sequence[str], delimiter: str) -> list[list[str]]:
    parts: list[list[str]] = []
    start = 0
    stack: list[str] = []
    closing = {")": "(", "]": "[", "}": "{"}
    opening = {"(": ")", "[": "]", "{": "}"}
    for index, token in enumerate(tokens):
        if token in opening:
            stack.append(token)
        elif token in closing:
            if not stack or stack.pop() != closing[token]:
                raise ExtractionError("unbalanced delimiters")
        elif token == delimiter and not stack:
            parts.append(list(tokens[start:index]))
            start = index + 1
    if stack:
        raise ExtractionError("unbalanced delimiters")
    parts.append(list(tokens[start:]))
    return parts


def matching(tokens: Sequence[str], start: int, left: str = "(", right: str = ")") -> int:
    if start >= len(tokens) or tokens[start] != left:
        raise ExtractionError(f"expected {left!r}")
    depth = 0
    for index in range(start, len(tokens)):
        if tokens[index] == left:
            depth += 1
        elif tokens[index] == right:
            depth -= 1
            if depth == 0:
                return index
    raise ExtractionError(f"unclosed {left!r}")


def sequences(tokens: Sequence[str], needle: Sequence[str]) -> list[int]:
    return [
        index
        for index in range(len(tokens) - len(needle) + 1)
        if list(tokens[index : index + len(needle)]) == list(needle)
    ]


def require_sequence(tokens: Sequence[str], needle: Sequence[str], label: str) -> None:
    hits = sequences(tokens, needle)
    if len(hits) != 1:
        raise ExtractionError(f"{label}: expected exactly one declaration, found {len(hits)}")


def find_statement_end(tokens: Sequence[str], start: int) -> int:
    stack: list[str] = []
    closing = {")": "(", "]": "[", "}": "{"}
    opening = {"(": ")", "[": "]", "{": "}"}
    for index in range(start, len(tokens)):
        token = tokens[index]
        if token in opening:
            stack.append(token)
        elif token in closing:
            if not stack or stack.pop() != closing[token]:
                raise ExtractionError("unbalanced delimiters in declaration")
        elif token == ";" and not stack:
            return index
    raise ExtractionError("unterminated declaration")


@dataclass(frozen=True)
class Parameter:
    name: str
    mode: str
    type_name: tuple[str, ...]


def parse_parameters(tokens: Sequence[str], start: int) -> tuple[tuple[Parameter, ...], int]:
    end = matching(tokens, start)
    contents = tokens[start + 1 : end]
    parameters: list[Parameter] = []
    if contents:
        for group in split_top(contents, ";"):
            if not group:
                raise ExtractionError("empty formal parameter group")
            colon = group.index(":") if ":" in group else -1
            if colon <= 0 or colon == len(group) - 1:
                raise ExtractionError("unsupported formal parameter syntax")
            names = split_top(group[:colon], ",")
            if len(names) != 1 or len(names[0]) != 1:
                raise ExtractionError("only single-name formal groups are supported")
            name = names[0][0]
            if not re.fullmatch(r"[a-z][a-z0-9_]*", name):
                raise ExtractionError("unsupported formal parameter name")
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
                raise ExtractionError(f"missing type for {name}")
            parameters.append(Parameter(name, mode, tuple(type_tokens)))
    return tuple(parameters), end + 1


def parse_aspects(tokens: Sequence[str], label: str) -> dict[str, list[str]]:
    aspects: dict[str, list[str]] = {}
    for aspect in split_top(tokens, ","):
        if not aspect:
            raise ExtractionError(f"{label}: empty aspect")
        if len(aspect) < 3 or aspect[1] != "=>":
            raise ExtractionError(f"{label}: unsupported aspect syntax")
        name = aspect[0]
        if name in aspects:
            raise ExtractionError(f"{label}: duplicate {name} aspect")
        aspects[name] = aspect[2:]
    return aspects


class ExpressionParser:
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
            raise ExtractionError(f"{self.label}: expected {expected!r}, found {token!r}")
        self.position += 1
        return token

    def parse(self) -> Expr:
        expression = self.parse_or()
        if self.peek() is not None:
            raise ExtractionError(
                f"{self.label}: unsupported/unconsumed token {self.peek()!r}"
            )
        return expression

    def parse_or(self) -> Expr:
        expression = self.parse_and()
        while self.peek() == "or" and self.peek(1) == "else":
            self.take("or")
            self.take("else")
            expression = Binary("or", expression, self.parse_and())
        return expression

    def parse_and(self) -> Expr:
        expression = self.parse_compare()
        while self.peek() == "and" and self.peek(1) == "then":
            self.take("and")
            self.take("then")
            expression = Binary("and", expression, self.parse_compare())
        return expression

    def parse_compare(self) -> Expr:
        expression = self.parse_unary()
        if self.peek() in ("=", "/="):
            operator = self.take()
            expression = Binary(operator, expression, self.parse_unary())
        return expression

    def parse_unary(self) -> Expr:
        if self.peek() == "not":
            self.take("not")
            return Negation(self.parse_unary())
        return self.parse_primary()

    def parse_name(self) -> Name:
        first = self.take()
        if not re.fullmatch(r"[a-z][a-z0-9_]*", first):
            raise ExtractionError(f"{self.label}: expected identifier, found {first!r}")
        parts = [first]
        while self.peek() == ".":
            self.take(".")
            part = self.take()
            if not re.fullmatch(r"[a-z][a-z0-9_]*", part):
                raise ExtractionError(f"{self.label}: malformed qualified name")
            parts.append(part)
        attribute = None
        if self.peek() is not None and self.peek().startswith("'"):
            attribute = self.take()[1:]
        return Name(tuple(parts), attribute)

    def parse_primary(self) -> Expr:
        token = self.peek()
        if token == "if":
            return self.parse_if()
        if token == "case":
            return self.parse_case()
        if token == "(":
            self.take("(")
            expression = self.parse_or()
            self.take(")")
            return expression
        if token is None:
            raise ExtractionError(f"{self.label}: expected expression")
        if token in ("true", "false"):
            self.take()
            return BoolLiteral(token == "true")
        if re.fullmatch(r"[a-z][a-z0-9_]*", token):
            name = self.parse_name()
            if self.peek() != "(":
                return name
            if name.attribute is not None:
                raise ExtractionError(f"{self.label}: attributes on calls are unsupported")
            self.take("(")
            arguments: list[Expr] = []
            if self.peek() != ")":
                while True:
                    arguments.append(self.parse_or())
                    if self.peek() != ",":
                        break
                    self.take(",")
            self.take(")")
            return Call(name.parts, tuple(arguments))
        raise ExtractionError(f"{self.label}: unsupported expression token {token!r}")

    def parse_if(self) -> IfExpression:
        self.take("if")
        branches: list[tuple[Expr, Expr]] = []
        condition = self.parse_or()
        self.take("then")
        body = self.parse_or()
        branches.append((condition, body))
        while self.peek() == "elsif":
            self.take("elsif")
            condition = self.parse_or()
            self.take("then")
            body = self.parse_or()
            branches.append((condition, body))
        otherwise = None
        if self.peek() == "else":
            self.take("else")
            otherwise = self.parse_or()
        return IfExpression(tuple(branches), otherwise)

    def parse_case(self) -> CaseExpression:
        self.take("case")
        selector = self.parse_or()
        self.take("is")
        branches: list[tuple[tuple[Name, ...], Expr]] = []
        while self.peek() == "when":
            self.take("when")
            choices = [self.parse_case_choice()]
            while self.peek() == "|":
                self.take("|")
                choices.append(self.parse_case_choice())
            self.take("=>")
            value = self.parse_or()
            branches.append((tuple(choices), value))
            if self.peek() != ",":
                break
            self.take(",")
        if not branches:
            raise ExtractionError(f"{self.label}: empty case expression")
        return CaseExpression(selector, tuple(branches))

    def parse_case_choice(self) -> Name:
        choice = self.parse_name()
        if choice.attribute is not None:
            raise ExtractionError(f"{self.label}: attributes on enum case choices are unsupported")
        return choice


def parse_expression(tokens: Sequence[str], label: str) -> Expr:
    return ExpressionParser(tokens, label).parse()


@dataclass(frozen=True)
class Function:
    name: str
    parameters: tuple[Parameter, ...]
    return_type: tuple[str, ...]
    body: Expr
    aspects: dict[str, list[str]]


@dataclass(frozen=True)
class Operation:
    name: str
    parameters: tuple[Parameter, ...]
    return_type: tuple[str, ...] | None
    aspects: dict[str, list[str]]


EXPECTED_ENUMS = {
    "camera_state": (
        "closed",
        "open_stopped",
        "streaming",
    ),
    "native_result": (
        "native_not_called",
        "native_success",
        "native_timeout",
        "native_bad_parameter",
        "native_unsupported",
        "native_out_of_memory",
        "native_error",
    ),
    "camera_status": (
        "camera_success",
        "camera_bad_parameter",
        "camera_unsupported",
        "camera_out_of_memory",
        "camera_error",
    ),
}

ENUM_TYPES = {
    "camera_state": "CameraState",
    "native_result": "NativeResult",
    "camera_status": "CameraStatus",
}

ENUM_CONSTRUCTORS = {
    "closed": "closed",
    "open_stopped": "openStopped",
    "streaming": "streaming",
    "native_not_called": "notCalled",
    "native_success": "success",
    "native_timeout": "timeout",
    "native_bad_parameter": "badParameter",
    "native_unsupported": "unsupported",
    "native_out_of_memory": "outOfMemory",
    "native_error": "error",
    "camera_success": "success",
    "camera_bad_parameter": "badParameter",
    "camera_unsupported": "unsupported",
    "camera_out_of_memory": "outOfMemory",
    "camera_error": "error",
}

GHOST_NAMES = (
    "camera_result",
    "open_status",
    "open_state",
    "start_status",
    "start_state",
    "stop_status",
    "stop_state",
    "is_open",
    "is_streaming",
)

FUNCTION_TYPES = {
    "camera_result": (("native_result",), "camera_status"),
    "open_status": (("camera_state", "bool", "native_result"), "camera_status"),
    "open_state": (("camera_state", "bool", "native_result"), "camera_state"),
    "start_status": (("camera_state", "native_result"), "camera_status"),
    "start_state": (("camera_state", "native_result"), "camera_state"),
    "stop_status": (("camera_state", "native_result"), "camera_status"),
    "stop_state": (("camera_state", "native_result"), "camera_state"),
    "is_open": (("camera_state",), "bool"),
    "is_streaming": (("camera_state",), "bool"),
    "valid_selector": (("bool",), "bool"),
}

KERNEL_ALLOWED_CALLS = frozenset(
    {
        "open_status",
        "open_state",
        "start_status",
        "start_state",
        "stop_status",
        "stop_state",
        "valid_selector",
        "is_open",
        "is_streaming",
    }
)

FUNCTION_LEAN_NAMES = {
    "camera_result": "cameraResult",
    "open_status": "openStatus",
    "open_state": "openState",
    "start_status": "startStatus",
    "start_state": "startState",
    "stop_status": "stopStatus",
    "stop_state": "stopState",
    "is_open": "isOpen",
    "is_streaming": "isStreaming",
}

FUNCTION_PROFILES = {
    "camera_result": (
        (Parameter("result", "in", ("t", ".", "native_result")),),
        ("t", ".", "camera_status"),
    ),
    "open_status": (
        (
            Parameter("state", "in", ("t", ".", "camera_state")),
            Parameter("device_id", "in", ("string",)),
            Parameter("result", "in", ("t", ".", "native_result")),
        ),
        ("t", ".", "camera_status"),
    ),
    "open_state": (
        (
            Parameter("state", "in", ("t", ".", "camera_state")),
            Parameter("device_id", "in", ("string",)),
            Parameter("result", "in", ("t", ".", "native_result")),
        ),
        ("t", ".", "camera_state"),
    ),
    "start_status": (
        (
            Parameter("state", "in", ("t", ".", "camera_state")),
            Parameter("result", "in", ("t", ".", "native_result")),
        ),
        ("t", ".", "camera_status"),
    ),
    "start_state": (
        (
            Parameter("state", "in", ("t", ".", "camera_state")),
            Parameter("result", "in", ("t", ".", "native_result")),
        ),
        ("t", ".", "camera_state"),
    ),
    "stop_status": (
        (
            Parameter("state", "in", ("t", ".", "camera_state")),
            Parameter("result", "in", ("t", ".", "native_result")),
        ),
        ("t", ".", "camera_status"),
    ),
    "stop_state": (
        (
            Parameter("state", "in", ("t", ".", "camera_state")),
            Parameter("result", "in", ("t", ".", "native_result")),
        ),
        ("t", ".", "camera_state"),
    ),
    "is_open": (
        (Parameter("state", "in", ("t", ".", "camera_state")),),
        ("boolean",),
    ),
    "is_streaming": (
        (Parameter("state", "in", ("t", ".", "camera_state")),),
        ("boolean",),
    ),
}

VALID_SELECTOR_PROFILE = (
    (Parameter("device_id", "in", ("string",)),),
    ("boolean",),
)

GHOST_ALLOWED_CALLS = {
    "camera_result": frozenset(),
    "open_status": frozenset({("camera_result",), ("valid_selector",)}),
    "open_state": frozenset({("valid_selector",)}),
    "start_status": frozenset({("camera_result",)}),
    "start_state": frozenset(),
    "stop_status": frozenset({("camera_result",)}),
    "stop_state": frozenset(),
    "is_open": frozenset(),
    "is_streaming": frozenset(),
}

OPERATION_PROFILES = {
    "open": (
        (
            Parameter("state", "in out", ("t", ".", "camera_state")),
            Parameter("handle", "in out", ("n", ".", "camera_handle")),
            Parameter("device_id", "in", ("string",)),
            Parameter("status", "out", ("t", ".", "camera_status")),
            Parameter("receipt", "out", ("t", ".", "native_result")),
        ),
        None,
        {"pre", "post"},
    ),
    "start": (
        (
            Parameter("state", "in out", ("t", ".", "camera_state")),
            Parameter("handle", "in", ("n", ".", "camera_handle")),
            Parameter("status", "out", ("t", ".", "camera_status")),
            Parameter("receipt", "out", ("t", ".", "native_result")),
        ),
        None,
        {"pre", "post"},
    ),
    "stop": (
        (
            Parameter("state", "in out", ("t", ".", "camera_state")),
            Parameter("handle", "in", ("n", ".", "camera_handle")),
            Parameter("status", "out", ("t", ".", "camera_status")),
            Parameter("receipt", "out", ("t", ".", "native_result")),
        ),
        None,
        {"pre", "post"},
    ),
    "close": (
        (
            Parameter("state", "in out", ("t", ".", "camera_state")),
            Parameter("handle", "in out", ("n", ".", "camera_handle")),
            Parameter("stop_receipt", "out", ("t", ".", "native_result")),
        ),
        None,
        {"pre", "post"},
    ),
    "is_open": (
        (Parameter("state", "in", ("t", ".", "camera_state")),),
        ("boolean",),
        {"post"},
    ),
    "is_streaming": (
        (Parameter("state", "in", ("t", ".", "camera_state")),),
        ("boolean",),
        {"post"},
    ),
}

LEAN_TYPES = {
    "bool": "Bool",
    "boolean": "Bool",
    "camera_state": "CameraState",
    "native_result": "NativeResult",
    "camera_status": "CameraStatus",
    "nat": "Nat",
}


def parse_enum(tokens: Sequence[str], enum_name: str) -> tuple[str, ...]:
    hits = sequences(tokens, ["type", enum_name, "is", "("])
    if len(hits) != 1:
        raise ExtractionError(
            f"types: expected one {enum_name} enum declaration, found {len(hits)}"
        )
    opening = hits[0] + 3
    closing = matching(tokens, opening)
    members: list[str] = []
    for member in split_top(tokens[opening + 1 : closing], ","):
        if len(member) != 1 or not re.fullmatch(r"[a-z][a-z0-9_]*", member[0]):
            raise ExtractionError(f"types: unsupported {enum_name} literal")
        members.append(member[0])
    if closing + 1 >= len(tokens) or tokens[closing + 1] != ";":
        raise ExtractionError(f"types: malformed {enum_name} declaration")
    return tuple(members)


def validate_enum_types(tokens: Sequence[str]) -> dict[str, tuple[str, ...]]:
    parsed = {name: parse_enum(tokens, name) for name in EXPECTED_ENUMS}
    for name, expected in EXPECTED_ENUMS.items():
        if parsed[name] != expected:
            raise ExtractionError(
                f"types: {name} domain changed: expected {expected}, found {parsed[name]}"
            )
    return parsed


def validate_aliases(spec_tokens: Sequence[str], kernel_tokens: Sequence[str]) -> None:
    type_alias = ["package", "t", "renames", "amv", ".", "gige_vision_types", ";"]
    require_sequence(spec_tokens, type_alias, "spec package alias T")
    require_sequence(kernel_tokens, type_alias, "kernel package alias T")
    native_alias = ["package", "n", "renames", "amv", ".", "gige_vision_native", ";"]
    require_sequence(kernel_tokens, native_alias, "kernel package alias N")


def parse_ghost_function(tokens: Sequence[str], name: str) -> Function:
    hits = sequences(tokens, ["function", name])
    if len(hits) != 1:
        raise ExtractionError(f"spec: expected one function {name}, found {len(hits)}")
    start = hits[0] + 2
    parameters, after_parameters = parse_parameters(tokens, start)
    if after_parameters >= len(tokens) or tokens[after_parameters] != "return":
        raise ExtractionError(f"spec: {name}: missing return type")
    is_positions = [
        index
        for index in range(after_parameters + 1, len(tokens))
        if tokens[index] == "is"
    ]
    if not is_positions:
        raise ExtractionError(f"spec: {name}: missing expression body")
    is_index = is_positions[0]
    return_type = tuple(tokens[after_parameters + 1 : is_index])
    body_start = is_index + 1
    if body_start >= len(tokens) or tokens[body_start] != "(":
        raise ExtractionError(f"spec: {name}: unsupported expression function body")
    body_end = matching(tokens, body_start)
    body = parse_expression(tokens[body_start + 1 : body_end], f"spec {name} body")
    cursor = body_end + 1
    aspects: dict[str, list[str]] = {}
    if cursor < len(tokens) and tokens[cursor] == "with":
        statement_end = find_statement_end(tokens, cursor + 1)
        aspects = parse_aspects(tokens[cursor + 1 : statement_end], f"spec {name}")
    elif cursor >= len(tokens) or tokens[cursor] != ";":
        raise ExtractionError(f"spec: {name}: unsupported trailing syntax")
    return Function(name, parameters, return_type, body, aspects)


def validate_selector_declaration(tokens: Sequence[str]) -> None:
    hits = sequences(tokens, ["function", "valid_selector"])
    if len(hits) != 1:
        raise ExtractionError(
            f"spec: expected one function valid_selector, found {len(hits)}"
        )
    parameters, after_parameters = parse_parameters(tokens, hits[0] + 2)
    if after_parameters >= len(tokens) or tokens[after_parameters] != "return":
        raise ExtractionError("spec: Valid_Selector is missing its return type")
    is_positions = [
        index for index in range(after_parameters + 1, len(tokens)) if tokens[index] == "is"
    ]
    if not is_positions:
        raise ExtractionError("spec: Valid_Selector is missing its expression body")
    is_index = is_positions[0]
    return_type = tuple(tokens[after_parameters + 1 : is_index])
    body_start = is_index + 1
    if body_start >= len(tokens) or tokens[body_start] != "(":
        raise ExtractionError("spec: Valid_Selector must have a parenthesized expression body")
    body_end = matching(tokens, body_start)
    cursor = body_end + 1
    if cursor < len(tokens) and tokens[cursor] == "with":
        raise ExtractionError("spec: Valid_Selector aspects are unsupported")
    if cursor >= len(tokens) or tokens[cursor] != ";":
        raise ExtractionError("spec: unsupported syntax after Valid_Selector body")
    require_profile(
        "valid_selector",
        parameters,
        return_type,
        VALID_SELECTOR_PROFILE[0],
        VALID_SELECTOR_PROFILE[1],
        "spec",
    )


def parse_operation(tokens: Sequence[str], name: str) -> Operation:
    kind = "function" if name in ("is_open", "is_streaming") else "procedure"
    hits = sequences(tokens, [kind, name])
    if len(hits) != 1:
        raise ExtractionError(f"kernel spec: expected one {kind} {name}, found {len(hits)}")
    start = hits[0] + 2
    parameters, after_parameters = parse_parameters(tokens, start)
    return_type: tuple[str, ...] | None = None
    cursor = after_parameters
    if kind == "function":
        if cursor >= len(tokens) or tokens[cursor] != "return":
            raise ExtractionError(f"kernel spec: {name}: missing return type")
        with_positions = [
            index for index in range(cursor + 1, len(tokens)) if tokens[index] == "with"
        ]
        if not with_positions:
            raise ExtractionError(f"kernel spec: {name}: missing contract aspects")
        with_index = with_positions[0]
        return_type = tuple(tokens[cursor + 1 : with_index])
        cursor = with_index
    elif cursor >= len(tokens) or tokens[cursor] != "with":
        raise ExtractionError(f"kernel spec: {name}: missing contract aspects")
    statement_end = find_statement_end(tokens, cursor + 1)
    aspects = parse_aspects(tokens[cursor + 1 : statement_end], f"kernel {name}")
    return Operation(name, parameters, return_type, aspects)


def require_profile(
    name: str,
    parameters: Sequence[Parameter],
    return_type: tuple[str, ...] | None,
    expected_parameters: Sequence[Parameter],
    expected_return: tuple[str, ...] | None,
    label: str,
) -> None:
    if tuple(parameters) != tuple(expected_parameters):
        raise ExtractionError(f"{label}: {name} signature or parameter modes changed")
    if return_type != expected_return:
        raise ExtractionError(f"{label}: {name} return type changed")


def required_aspects(
    name: str,
    aspects: dict[str, list[str]],
    expected: set[str],
    label: str,
    allow_global: bool = False,
) -> dict[str, Expr]:
    allowed = set(expected)
    if allow_global:
        allowed.update({"global", "depends"})
    unexpected = set(aspects) - allowed
    missing = expected - set(aspects)
    if unexpected or missing:
        raise ExtractionError(
            f"{label}: {name} aspects changed; missing={sorted(missing)}, "
            f"unsupported={sorted(unexpected)}"
        )
    parsed: dict[str, Expr] = {}
    for aspect in expected:
        parsed[aspect] = parse_expression(aspects[aspect], f"{label} {name} {aspect}")
    return parsed


def enum_literal_type(name: Name) -> str | None:
    if name.attribute is None and len(name.parts) == 2 and name.parts[0] == "t":
        literal = name.parts[1]
        for enum_name, literals in EXPECTED_ENUMS.items():
            if literal in literals:
                return enum_name
    return None


def leaf_name(name: Name | Call) -> str:
    return name.parts[-1]


def validate_call_paths(
    expression: Expr,
    origin: str,
    allowed_ghost_calls: frozenset[tuple[str, ...]] | None = None,
) -> None:
    if isinstance(expression, Call):
        if origin == "ghost":
            if allowed_ghost_calls is None:
                raise ExtractionError("internal error: Ghost call allowlist is required")
            if expression.name not in allowed_ghost_calls:
                raise ExtractionError(f"unsupported Ghost helper call {'.'.join(expression.name)}")
        else:
            if expression.name[:3] != ("amv", "spec", "gige_vision"):
                raise ExtractionError(f"unapproved contract call {'.'.join(expression.name)}")
            if expression.name[3:] not in tuple((name,) for name in KERNEL_ALLOWED_CALLS):
                raise ExtractionError(f"unapproved contract call {'.'.join(expression.name)}")
        for argument in expression.arguments:
            validate_call_paths(argument, origin, allowed_ghost_calls)
    elif isinstance(expression, Binary):
        validate_call_paths(expression.left, origin, allowed_ghost_calls)
        validate_call_paths(expression.right, origin, allowed_ghost_calls)
    elif isinstance(expression, Negation):
        validate_call_paths(expression.value, origin, allowed_ghost_calls)
    elif isinstance(expression, IfExpression):
        for condition, value in expression.branches:
            validate_call_paths(condition, origin, allowed_ghost_calls)
            validate_call_paths(value, origin, allowed_ghost_calls)
        if expression.otherwise is not None:
            validate_call_paths(expression.otherwise, origin, allowed_ghost_calls)
    elif isinstance(expression, CaseExpression):
        validate_call_paths(expression.selector, origin, allowed_ghost_calls)
        for _, value in expression.branches:
            validate_call_paths(value, origin, allowed_ghost_calls)


def validate_device_id_usage(expression: Expr) -> None:
    if isinstance(expression, Name):
        if expression.parts == ("device_id",):
            raise ExtractionError("Device_ID must be passed only to an approved selector helper")
    elif isinstance(expression, Call):
        name = expression.name[-1]
        for index, argument in enumerate(expression.arguments):
            allowed = (name == "valid_selector" and index == 0) or (
                name in ("open_status", "open_state") and index == 1
            )
            if allowed:
                if not isinstance(argument, Name) or argument.parts != ("device_id",):
                    validate_device_id_usage(argument)
            else:
                validate_device_id_usage(argument)
    elif isinstance(expression, Binary):
        validate_device_id_usage(expression.left)
        validate_device_id_usage(expression.right)
    elif isinstance(expression, Negation):
        validate_device_id_usage(expression.value)
    elif isinstance(expression, IfExpression):
        for condition, value in expression.branches:
            validate_device_id_usage(condition)
            validate_device_id_usage(value)
        if expression.otherwise is not None:
            validate_device_id_usage(expression.otherwise)
    elif isinstance(expression, CaseExpression):
        validate_device_id_usage(expression.selector)
        for _, value in expression.branches:
            validate_device_id_usage(value)


def infer_type(expression: Expr, environment: dict[str, str], origin: str) -> str:
    if isinstance(expression, BoolLiteral):
        return "bool"
    if isinstance(expression, Name):
        if expression.attribute is not None:
            if len(expression.parts) != 1:
                raise ExtractionError("qualified Ada attributes are unsupported")
            key = f"{expression.parts[0]}'{expression.attribute}"
            if key not in environment:
                raise ExtractionError(f"unsupported attribute {key}")
            return environment[key]
        if expression.parts == ("n", "null_handle"):
            return "nat"
        if expression.parts[0] == "t":
            enum_type = enum_literal_type(expression)
            if enum_type is None:
                raise ExtractionError(f"unknown enum literal {'.'.join(expression.parts)}")
            return enum_type
        if len(expression.parts) == 1 and expression.parts[0] in environment:
            return environment[expression.parts[0]]
        raise ExtractionError(f"unknown identifier {'.'.join(expression.parts)}")
    if isinstance(expression, Call):
        name = expression.name[-1]
        if name not in FUNCTION_TYPES:
            raise ExtractionError(f"unsupported helper call {'.'.join(expression.name)}")
        if len(expression.arguments) != len(FUNCTION_TYPES[name][0]):
            raise ExtractionError(f"{name}: wrong number of arguments")
        for argument, expected in zip(expression.arguments, FUNCTION_TYPES[name][0]):
            actual = infer_type(argument, environment, origin)
            if actual != expected:
                raise ExtractionError(f"{name}: argument type mismatch ({actual} != {expected})")
        return FUNCTION_TYPES[name][1]
    if isinstance(expression, Negation):
        if infer_type(expression.value, environment, origin) != "bool":
            raise ExtractionError("not operand is not Boolean")
        return "bool"
    if isinstance(expression, Binary):
        left = infer_type(expression.left, environment, origin)
        right = infer_type(expression.right, environment, origin)
        if expression.operator in ("and", "or"):
            if left != "bool" or right != "bool":
                raise ExtractionError("Boolean operator applied to non-Boolean expression")
        elif expression.operator in ("=", "/="):
            if left != right:
                raise ExtractionError(f"equality type mismatch ({left} != {right})")
        else:
            raise ExtractionError(f"unsupported operator {expression.operator}")
        return "bool"
    if isinstance(expression, IfExpression):
        branch_types: list[str] = []
        for condition, value in expression.branches:
            if infer_type(condition, environment, origin) != "bool":
                raise ExtractionError("if condition is not Boolean")
            branch_types.append(infer_type(value, environment, origin))
        if expression.otherwise is None:
            if any(value_type != "bool" for value_type in branch_types):
                raise ExtractionError("implicit True else is allowed only for Boolean if expressions")
            branch_types.append("bool")
        else:
            branch_types.append(infer_type(expression.otherwise, environment, origin))
        if len(set(branch_types)) != 1:
            raise ExtractionError("if branches have different result types")
        return branch_types[0]
    if isinstance(expression, CaseExpression):
        selector_type = infer_type(expression.selector, environment, origin)
        if selector_type not in EXPECTED_ENUMS:
            raise ExtractionError("case selector is outside the selected enum domains")
        covered: list[str] = []
        branch_types: list[str] = []
        for choices, value in expression.branches:
            for choice in choices:
                choice_type = enum_literal_type(choice)
                if choice_type != selector_type:
                    raise ExtractionError("case choice has the wrong enum type")
                covered.append(choice.parts[-1])
            branch_types.append(infer_type(value, environment, origin))
        if len(covered) != len(set(covered)):
            raise ExtractionError("case expression has duplicate choices")
        if set(covered) != set(EXPECTED_ENUMS[selector_type]):
            raise ExtractionError("case expression does not cover its full enum domain")
        if len(set(branch_types)) != 1:
            raise ExtractionError("case alternatives have different result types")
        return branch_types[0]
    raise ExtractionError("unsupported AST node")


def lean_constructor(name: Name) -> str:
    enum_type = enum_literal_type(name)
    if enum_type is None:
        raise ExtractionError(f"cannot translate enum literal {'.'.join(name.parts)}")
    constructor = ENUM_CONSTRUCTORS[name.parts[-1]]
    return f".{constructor}"


def translate(
    expression: Expr,
    variables: dict[str, str],
    environment: dict[str, str],
    origin: str,
    function_names: dict[str, str] | None = None,
) -> str:
    function_names = function_names or FUNCTION_LEAN_NAMES
    if isinstance(expression, BoolLiteral):
        return "true" if expression.value else "false"
    if isinstance(expression, Name):
        if expression.attribute is not None:
            if len(expression.parts) != 1:
                raise ExtractionError("cannot translate a qualified Ada attribute")
            key = f"{expression.parts[0]}'{expression.attribute}"
            if key not in variables:
                raise ExtractionError(f"cannot translate attribute {key}")
            return variables[key]
        if expression.parts == ("n", "null_handle"):
            return "0"
        if expression.parts[0] == "t":
            return lean_constructor(expression)
        if len(expression.parts) == 1 and expression.parts[0] in variables:
            return variables[expression.parts[0]]
        raise ExtractionError(f"cannot translate identifier {'.'.join(expression.parts)}")
    if isinstance(expression, Call):
        name = expression.name[-1]
        arguments = [
            translate(argument, variables, environment, origin, function_names)
            for argument in expression.arguments
        ]
        if name == "valid_selector":
            if arguments != ["selectorValid"]:
                raise ExtractionError("Valid_Selector must receive the abstract selectorValid input")
            return "selectorValid"
        if name not in function_names:
            raise ExtractionError(f"cannot translate helper call {name}")
        return function_names[name] + " " + " ".join(f"({argument})" for argument in arguments)
    if isinstance(expression, Negation):
        return f"(!({translate(expression.value, variables, environment, origin, function_names)}))"
    if isinstance(expression, Binary):
        operators = {"and": "&&", "or": "||", "=": "==", "/=": "!="}
        operator = operators.get(expression.operator)
        if operator is None:
            raise ExtractionError(f"cannot translate operator {expression.operator}")
        left = translate(expression.left, variables, environment, origin, function_names)
        right = translate(expression.right, variables, environment, origin, function_names)
        return f"(({left}) {operator} ({right}))"
    if isinstance(expression, IfExpression):
        otherwise = (
            translate(expression.otherwise, variables, environment, origin, function_names)
            if expression.otherwise is not None
            else "true"
        )
        for condition, value in reversed(expression.branches):
            otherwise = (
                f"(if {translate(condition, variables, environment, origin, function_names)} then "
                f"{translate(value, variables, environment, origin, function_names)} else {otherwise})"
            )
        return otherwise
    if isinstance(expression, CaseExpression):
        selector_type = infer_type(
            expression.selector,
            environment,
            origin,
        )
        branches_by_choice: dict[str, Expr] = {}
        for choices, value in expression.branches:
            for choice in choices:
                branches_by_choice[choice.parts[-1]] = value
        arms = []
        for choice in EXPECTED_ENUMS[selector_type]:
            constructor = ENUM_CONSTRUCTORS[choice]
            value = translate(
                branches_by_choice[choice],
                variables,
                environment,
                origin,
                function_names,
            )
            arms.append(f"  | .{constructor} => {value}")
        selector = translate(expression.selector, variables, environment, origin, function_names)
        return "match " + selector + " with\n" + "\n".join(arms)
    raise ExtractionError("cannot translate unsupported AST node")


def bool_true() -> Expr:
    return BoolLiteral(True)


def conjunction(left: Expr, right: Expr) -> Expr:
    if isinstance(left, BoolLiteral) and left.value:
        return right
    return Binary("and", left, right)


def disjunction(left: Expr, right: Expr) -> Expr:
    if isinstance(left, BoolLiteral) and not left.value:
        return right
    return Binary("or", left, right)


def negate(expression: Expr) -> Expr:
    return Negation(expression)


def collect_camera_result_call_guards(expression: Expr) -> list[tuple[Call, Expr]]:
    guards: list[tuple[Call, Expr]] = []

    def visit(node: Expr, context: Expr) -> None:
        if isinstance(node, Call):
            if node.name[-1] == "camera_result":
                guards.append((node, context))
            for argument in node.arguments:
                visit(argument, context)
        elif isinstance(node, Binary):
            if node.operator == "and":
                visit(node.left, context)
                visit(node.right, conjunction(context, node.left))
            elif node.operator == "or":
                visit(node.left, context)
                visit(node.right, conjunction(context, negate(node.left)))
            else:
                visit(node.left, context)
                visit(node.right, context)
        elif isinstance(node, Negation):
            visit(node.value, context)
        elif isinstance(node, IfExpression):
            prior: Expr = BoolLiteral(False)
            for condition, value in node.branches:
                visit(condition, context)
                branch_context = conjunction(
                    context,
                    conjunction(negate(prior), condition),
                )
                visit(value, branch_context)
                prior = disjunction(prior, condition)
            if node.otherwise is not None:
                visit(node.otherwise, conjunction(context, negate(prior)))
        elif isinstance(node, CaseExpression):
            visit(node.selector, context)
            for choices, value in node.branches:
                branch_guard: Expr = BoolLiteral(False)
                for choice in choices:
                    branch_guard = disjunction(
                        branch_guard,
                        Binary("=", node.selector, choice),
                    )
                visit(value, conjunction(context, branch_guard))

    visit(expression, bool_true())
    return guards


def expression_environment(function_name: str, clause: str | None = None) -> dict[str, str]:
    if function_name in GHOST_NAMES and clause is None:
        if function_name == "camera_result":
            return {"result": "native_result"}
        if function_name in ("open_status", "open_state"):
            return {"state": "camera_state", "device_id": "bool", "result": "native_result"}
        if function_name in ("start_status", "start_state", "stop_status", "stop_state"):
            return {"state": "camera_state", "result": "native_result"}
        return {"state": "camera_state"}
    if function_name in ("open", "start", "stop", "close"):
        if clause == "pre":
            return {"state": "camera_state", "handle": "nat"}
        if function_name == "open":
            return {
                "state": "camera_state",
                "state'old": "camera_state",
                "handle": "nat",
                "handle'old": "nat",
                "device_id": "bool",
                "status": "camera_status",
                "receipt": "native_result",
            }
        if function_name == "start" or function_name == "stop":
            return {
                "state": "camera_state",
                "state'old": "camera_state",
                "handle": "nat",
                "status": "camera_status",
                "receipt": "native_result",
            }
        return {
            "state": "camera_state",
            "state'old": "camera_state",
            "handle": "nat",
            "handle'old": "nat",
            "stop_receipt": "native_result",
        }
    if function_name in ("is_open", "is_streaming") and clause == "post":
        return {"state": "camera_state", f"{function_name}'result": "bool"}
    raise ExtractionError(f"no expression environment for {function_name}")


def variable_names(function_name: str, clause: str | None = None) -> dict[str, str]:
    if function_name in GHOST_NAMES and clause is None:
        result = {"state": "state", "device_id": "selectorValid", "result": "result"}
        return result
    if clause == "pre":
        handle_name = "handle" if function_name in ("start", "stop") else "oldHandle"
        return {"state": "oldState", "handle": handle_name}
    if function_name == "open":
        return {
            "state": "newState",
            "state'old": "oldState",
            "handle": "newHandle",
            "handle'old": "oldHandle",
            "device_id": "selectorValid",
            "status": "status",
            "receipt": "receipt",
        }
    if function_name in ("start", "stop"):
        return {
            "state": "newState",
            "state'old": "oldState",
            "handle": "handle",
            "status": "status",
            "receipt": "receipt",
        }
    if function_name == "close":
        return {
            "state": "newState",
            "state'old": "oldState",
            "handle": "newHandle",
            "handle'old": "oldHandle",
            "stop_receipt": "receipt",
        }
    if function_name in ("is_open", "is_streaming") and clause == "post":
        return {
            "state": "state",
            f"{function_name}'result": "result",
        }
    raise ExtractionError(f"no translation environment for {function_name}")


OPERATION_LEAN_ARGUMENTS = {
    "open": (
        ("oldState", "CameraState"),
        ("oldHandle", "Nat"),
        ("selectorValid", "Bool"),
        ("newState", "CameraState"),
        ("newHandle", "Nat"),
        ("status", "CameraStatus"),
        ("receipt", "NativeResult"),
    ),
    "start": (
        ("oldState", "CameraState"),
        ("handle", "Nat"),
        ("newState", "CameraState"),
        ("status", "CameraStatus"),
        ("receipt", "NativeResult"),
    ),
    "stop": (
        ("oldState", "CameraState"),
        ("handle", "Nat"),
        ("newState", "CameraState"),
        ("status", "CameraStatus"),
        ("receipt", "NativeResult"),
    ),
    "close": (
        ("oldState", "CameraState"),
        ("oldHandle", "Nat"),
        ("newState", "CameraState"),
        ("newHandle", "Nat"),
        ("receipt", "NativeResult"),
    ),
    "is_open": (("state", "CameraState"), ("result", "Bool")),
    "is_streaming": (("state", "CameraState"), ("result", "Bool")),
}

OPERATION_LEAN_NAMES = {
    "open": "open",
    "start": "start",
    "stop": "stop",
    "close": "close",
    "is_open": "isOpen",
    "is_streaming": "isStreaming",
}

PRE_ARGUMENTS = {
    "open": (("oldState", "CameraState"), ("oldHandle", "Nat")),
    "start": (("oldState", "CameraState"), ("handle", "Nat")),
    "stop": (("oldState", "CameraState"), ("handle", "Nat")),
    "close": (("oldState", "CameraState"), ("oldHandle", "Nat")),
}

POST_ARGUMENTS = {
    "open": OPERATION_LEAN_ARGUMENTS["open"],
    "start": (
        ("oldState", "CameraState"),
        ("newState", "CameraState"),
        ("status", "CameraStatus"),
        ("receipt", "NativeResult"),
    ),
    "stop": (
        ("oldState", "CameraState"),
        ("newState", "CameraState"),
        ("status", "CameraStatus"),
        ("receipt", "NativeResult"),
    ),
    "close": (
        ("oldState", "CameraState"),
        ("_oldHandle", "Nat"),
        ("newState", "CameraState"),
        ("newHandle", "Nat"),
        ("receipt", "NativeResult"),
    ),
    "is_open": OPERATION_LEAN_ARGUMENTS["is_open"],
    "is_streaming": OPERATION_LEAN_ARGUMENTS["is_streaming"],
}


def emit_definition(
    name: str,
    arguments: Sequence[tuple[str, str]],
    result_type: str,
    expression: str,
) -> str:
    parameters = " ".join(f"({argument} : {type_name})" for argument, type_name in arguments)
    return f"def {name} {parameters} : {result_type} :=\n  {expression}\n"


def validate_function(function: Function) -> None:
    expected_parameters, expected_return = FUNCTION_PROFILES[function.name]
    require_profile(
        function.name,
        function.parameters,
        function.return_type,
        expected_parameters,
        expected_return,
        "spec",
    )
    expected_aspects = {"pre"} if function.name == "camera_result" else set()
    parsed_aspects = required_aspects(
        function.name,
        function.aspects,
        expected_aspects,
        "spec",
    )
    environment = expression_environment(function.name)
    if infer_type(function.body, environment, "ghost") != FUNCTION_TYPES[function.name][1]:
        raise ExtractionError(f"spec: {function.name} body result type changed")
    validate_call_paths(function.body, "ghost", GHOST_ALLOWED_CALLS[function.name])
    validate_device_id_usage(function.body)
    camera_calls = collect_camera_result_call_guards(function.body)
    expected_camera_calls = 1 if function.name in {
        "open_status",
        "start_status",
        "stop_status",
    } else 0
    if len(camera_calls) != expected_camera_calls:
        raise ExtractionError(
            f"spec: {function.name} must contain exactly {expected_camera_calls} "
            f"Camera_Result calls, found {len(camera_calls)}"
        )
    for call, _ in camera_calls:
        if (
            call.name != ("camera_result",)
            or call.arguments != (Name(("result",)),)
        ):
            raise ExtractionError(
                f"spec: {function.name} must call exactly Camera_Result (Result)"
            )
    if function.name == "camera_result":
        validate_call_paths(parsed_aspects["pre"], "ghost", frozenset())
        if infer_type(parsed_aspects["pre"], environment, "ghost") != "bool":
            raise ExtractionError("spec: Camera_Result Pre is not Boolean")


def validate_operation(operation: Operation) -> dict[str, Expr]:
    expected_parameters, expected_return, expected_aspects = OPERATION_PROFILES[operation.name]
    require_profile(
        operation.name,
        operation.parameters,
        operation.return_type,
        expected_parameters,
        expected_return,
        "kernel spec",
    )
    parsed = required_aspects(
        operation.name,
        operation.aspects,
        expected_aspects,
        "kernel spec",
        allow_global=True,
    )
    if "pre" in parsed:
        environment = expression_environment(operation.name, "pre")
        if infer_type(parsed["pre"], environment, "kernel") != "bool":
            raise ExtractionError(f"kernel spec: {operation.name} Pre is not Boolean")
        validate_call_paths(parsed["pre"], "kernel")
        validate_device_id_usage(parsed["pre"])
    if "post" in parsed:
        environment = expression_environment(operation.name, "post")
        if infer_type(parsed["post"], environment, "kernel") != "bool":
            raise ExtractionError(f"kernel spec: {operation.name} Post is not Boolean")
        validate_call_paths(parsed["post"], "kernel")
        validate_device_id_usage(parsed["post"])
    return parsed


def generate(spec_source: str, kernel_source: str, types_source: str) -> str:
    spec_tokens = tokenize(spec_source, "spec")
    kernel_tokens = tokenize(kernel_source, "kernel spec")
    type_tokens = tokenize(types_source, "types")
    reject_operator_overloads(spec_tokens, "spec")
    reject_operator_overloads(kernel_tokens, "kernel spec")
    reject_operator_overloads(type_tokens, "types")
    reject_unparsed_pragmas(spec_tokens, "spec")
    reject_unparsed_pragmas(kernel_tokens, "kernel spec")
    reject_unparsed_pragmas(type_tokens, "types")
    validate_aliases(spec_tokens, kernel_tokens)
    validate_enum_types(type_tokens)
    validate_selector_declaration(spec_tokens)

    functions = {
        name: parse_ghost_function(spec_tokens, name)
        for name in GHOST_NAMES
    }
    for function in functions.values():
        validate_function(function)

    operations = {
        name: parse_operation(kernel_tokens, name)
        for name in OPERATION_PROFILES
    }
    aspects = {
        name: validate_operation(operation)
        for name, operation in operations.items()
    }

    lines = [
        "import CameraLifecycle.Model",
        "",
        "namespace CameraLifecycle.Generated",
        "",
        "open CameraLifecycle.Model",
        "",
    ]

    ghost_arguments = {
        "camera_result": (("result", "NativeResult"),),
        "open_status": (("state", "CameraState"), ("selectorValid", "Bool"), ("result", "NativeResult")),
        "open_state": (("state", "CameraState"), ("selectorValid", "Bool"), ("result", "NativeResult")),
        "start_status": (("state", "CameraState"), ("result", "NativeResult")),
        "start_state": (("state", "CameraState"), ("result", "NativeResult")),
        "stop_status": (("state", "CameraState"), ("result", "NativeResult")),
        "stop_state": (("state", "CameraState"), ("result", "NativeResult")),
        "is_open": (("state", "CameraState"),),
        "is_streaming": (("state", "CameraState"),),
    }
    for name in GHOST_NAMES:
        function = functions[name]
        env = expression_environment(name)
        variables = variable_names(name)
        result_type = LEAN_TYPES[FUNCTION_TYPES[name][1]]
        body = translate(function.body, variables, env, "ghost")
        lines.append(
            emit_definition(FUNCTION_LEAN_NAMES[name], ghost_arguments[name], result_type, body)
        )
        if name == "camera_result":
            pre = parse_expression(function.aspects["pre"], "Camera_Result Pre")
            pre_body = translate(pre, variables, env, "ghost")
            lines.append(emit_definition("cameraResultPre", ghost_arguments[name], "Bool", pre_body))
        lines.append("")

    guard_specs = {
        "open_status": (("state", "CameraState"), ("selectorValid", "Bool"), ("result", "NativeResult")),
        "start_status": (("state", "CameraState"), ("result", "NativeResult")),
        "stop_status": (("state", "CameraState"), ("result", "NativeResult")),
    }
    for name in guard_specs:
        guards = collect_camera_result_call_guards(functions[name].body)
        if len(guards) != 1:
            raise ExtractionError(
                f"spec: {name} must contain exactly one Camera_Result call, found {len(guards)}"
            )
        call, guard = guards[0]
        if call.name != ("camera_result",) or call.arguments != (Name(("result",)),):
            raise ExtractionError(f"spec: {name} must call exactly Camera_Result (Result)")
        env = expression_environment(name)
        if infer_type(guard, env, "ghost") != "bool":
            raise ExtractionError(f"spec: {name} Camera_Result call guard is not Boolean")
        variables = variable_names(name)
        guard_name = FUNCTION_LEAN_NAMES[name] + "CameraResultCallGuard"
        lines.append(
            emit_definition(
                guard_name,
                guard_specs[name],
                "Bool",
                translate(guard, variables, env, "ghost"),
            )
        )
        lines.append("")

    for name in OPERATION_PROFILES:
        lean_name = OPERATION_LEAN_NAMES[name]
        operation_aspects = aspects[name]
        if "pre" in operation_aspects:
            env = expression_environment(name, "pre")
            pre_expression = operation_aspects["pre"]
            pre_body = translate(
                pre_expression,
                variable_names(name, "pre"),
                env,
                "kernel",
            )
            lines.append(
                emit_definition(
                    lean_name + "Pre",
                    PRE_ARGUMENTS[name],
                    "Bool",
                    pre_body,
                )
            )
            lines.append("")
        post_expression = operation_aspects["post"]
        env = expression_environment(name, "post")
        post_body = translate(
            post_expression,
            variable_names(name, "post"),
            env,
            "kernel",
        )
        lines.append(
            emit_definition(
                lean_name + "Post",
                POST_ARGUMENTS[name],
                "Bool",
                post_body,
            )
        )
        lines.append("")
        if name in PRE_ARGUMENTS:
            all_arguments = OPERATION_LEAN_ARGUMENTS[name]
            pre_call_arguments = " ".join(
                f"({argument})" for argument, _ in PRE_ARGUMENTS[name]
            )
            post_call_arguments = " ".join(
                f"({'oldHandle' if argument == '_oldHandle' else argument})"
                for argument, _ in POST_ARGUMENTS[name]
            )
            relation = (
                f"{lean_name}Pre {pre_call_arguments} = true ∧ "
                f"{lean_name}Post {post_call_arguments} = true"
            )
        else:
            all_arguments = OPERATION_LEAN_ARGUMENTS[name]
            post_call_arguments = " ".join(
                f"({argument})" for argument, _ in POST_ARGUMENTS[name]
            )
            relation = f"{lean_name}Post {post_call_arguments} = true"
        lines.append(
            emit_definition(lean_name + "Relation", all_arguments, "Prop", relation)
        )
        lines.append("")

    lines.extend(["end CameraLifecycle.Generated", ""])
    return "\n".join(lines)


def main() -> int:
    project_dir = Path(__file__).resolve().parents[1]
    repository_root = Path(__file__).resolve().parents[3]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source-root",
        type=Path,
        default=repository_root / "optional" / "aravis" / "src",
        help="directory containing the selected Ada specification files",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=project_dir / "CameraLifecycle" / "Generated.lean",
        help="generated Lean comparison module",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail if the checked-in generated module differs from Ada sources",
    )
    arguments = parser.parse_args()
    try:
        source_root = arguments.source_root
        generated = generate(
            (source_root / "amv-spec-gige_vision.ads").read_text(encoding="utf-8"),
            (source_root / "amv-kernels-gige_vision.ads").read_text(encoding="utf-8"),
            (source_root / "amv-gige_vision_types.ads").read_text(encoding="utf-8"),
        )
        output = arguments.output
        if arguments.check:
            if not output.exists():
                raise ExtractionError(f"generated file is missing: {output}")
            current = output.read_text(encoding="utf-8")
            if current != generated:
                raise ExtractionError(
                    f"generated file is stale: run {Path(__file__).name} to refresh {output}"
                )
            print(f"generated source matches Ada contracts: {output}")
        else:
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(generated, encoding="utf-8")
            print(f"generated Lean comparison module: {output}")
    except (ExtractionError, OSError, ValueError) as error:
        print(f"contract extraction failed: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
