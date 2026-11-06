"""A small YAML subset parser for subscriptions.yaml.

Supports comments, indentation-based maps, lists, quoted strings, numbers,
booleans, and null. Tabs are rejected. This keeps the collector on the
Python standard library.
"""

from __future__ import annotations

import re
from typing import Any


class YAMLError(ValueError):
    """The subscriptions file is not in the supported YAML subset."""


def parse_yaml(text: str) -> Any:
    lines = _prepare(text)
    if not lines:
        return {}
    value, index = _parse_value(lines, 0, lines[0][0])
    if index != len(lines):
        raise YAMLError(f"unsupported structure near {lines[index][1]!r}")
    return value


def _prepare(text: str) -> list[tuple[int, str]]:
    prepared: list[tuple[int, str]] = []
    for line_number, raw in enumerate(text.splitlines(), start=1):
        if "\t" in raw:
            raise YAMLError(f"line {line_number} uses a tab; indent with spaces")
        stripped = _strip_comment(raw).rstrip()
        if not stripped.strip():
            continue
        indent = len(stripped) - len(stripped.lstrip(" "))
        prepared.append((indent, stripped.strip()))
    return prepared


def _strip_comment(line: str) -> str:
    in_single = False
    in_double = False
    for index, char in enumerate(line):
        if char == "'" and not in_double:
            in_single = not in_single
        elif char == '"' and not in_single:
            in_double = not in_double
        elif char == "#" and not in_single and not in_double:
            return line[:index]
    return line


def _parse_value(lines: list[tuple[int, str]], index: int, indent: int) -> tuple[Any, int]:
    if index >= len(lines):
        return {}, index
    content = lines[index][1]
    if content.startswith("- "):
        return _parse_list(lines, index, indent)
    return _parse_map(lines, index, indent)


def _parse_list(lines: list[tuple[int, str]], index: int, indent: int) -> tuple[list[Any], int]:
    items: list[Any] = []
    while index < len(lines) and lines[index][0] == indent and lines[index][1].startswith("- "):
        item_text = lines[index][1][2:].strip()
        index += 1
        child_indent = indent + 2
        if item_text == "":
            if index < len(lines) and lines[index][0] >= child_indent:
                child, index = _parse_value(lines, index, lines[index][0])
                items.append(child)
            else:
                items.append(None)
            continue
        if _has_key_separator(item_text):
            key, rest = _split_key(item_text)
            mapping: dict[str, Any] = {}
            if rest == "":
                if index < len(lines) and lines[index][0] >= child_indent:
                    child, index = _parse_value(lines, index, lines[index][0])
                    mapping[key] = child
                else:
                    mapping[key] = None
            else:
                mapping[key] = _parse_scalar(rest)
            while (
                index < len(lines)
                and lines[index][0] >= child_indent
                and not lines[index][1].startswith("- ")
            ):
                key, rest = _split_key(lines[index][1])
                nested_indent = lines[index][0]
                index += 1
                if rest == "":
                    if index < len(lines) and lines[index][0] > nested_indent:
                        child, index = _parse_value(lines, index, lines[index][0])
                        mapping[key] = child
                    else:
                        mapping[key] = None
                else:
                    mapping[key] = _parse_scalar(rest)
            items.append(mapping)
            continue
        items.append(_parse_scalar(item_text))
    return items, index


def _parse_map(lines: list[tuple[int, str]], index: int, indent: int) -> tuple[dict[str, Any], int]:
    mapping: dict[str, Any] = {}
    while index < len(lines) and lines[index][0] == indent and not lines[index][1].startswith("- "):
        key, rest = _split_key(lines[index][1])
        index += 1
        if rest == "":
            if index < len(lines) and lines[index][0] > indent:
                child, index = _parse_value(lines, index, lines[index][0])
                mapping[key] = child
            else:
                mapping[key] = None
        else:
            mapping[key] = _parse_scalar(rest)
    return mapping, index


def _has_key_separator(text: str) -> bool:
    if text.startswith(('"', "'")):
        return False
    return ":" in text


def _split_key(text: str) -> tuple[str, str]:
    key, separator, rest = text.partition(":")
    if separator != ":" or not key.strip():
        raise YAMLError(f"expected 'key: value', got {text!r}")
    return key.strip(), rest.strip()


def _parse_scalar(text: str) -> Any:
    if text in {"", "null", "~", "Null", "NULL"}:
        return None
    if len(text) >= 2 and text[0] == text[-1] and text[0] in {'"', "'"}:
        return _unquote(text[1:-1], text[0])
    lowered = text.lower()
    if lowered == "true":
        return True
    if lowered == "false":
        return False
    if re.fullmatch(r"-?\d+", text):
        return int(text)
    if re.fullmatch(r"-?\d+\.\d+", text):
        return float(text)
    return text


def _unquote(text: str, quote: str) -> str:
    if quote == "'":
        return text.replace("''", "'")
    return (
        text.replace(r"\n", "\n")
        .replace(r"\t", "\t")
        .replace(r"\"", '"')
        .replace(r"\\", "\\")
    )
