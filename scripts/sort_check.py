#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["pyyaml>=6"]
# ///
"""Lint HCL assignments and YAML/JSON keys per AGENTS.md.

Within each mapping: single-line keys come first (alphabetical), then
multi-line keys (alphabetical).

HCL assignment groups must follow the same single-line/multi-line order, and
every multi-line assignment must be separated from adjacent assignments by a
blank line. Top-level locals retain their required full-name ordering.
Dynamically keyed object entries are exempt because `tofu fmt` removes their
separators.

List-item mappings place identifier keys before sorted fields. Data and schema
items use type/name/id; Prek hooks use id/name.

What counts as "multi-line" depends on the file format:

  YAML  - non-empty mappings and sequences are always block style here, so
          any non-empty container is multi-line; empty `{}` / `[]` is single.

  JSON  - Prettier inlines short scalar arrays like `"required": ["a", "b"]`
          and `"enum": [...]`, so a list is only multi-line when it contains
          a nested object or list. Mappings stay multi-line whenever non-empty.
"""

import json
import re
import sys
from pathlib import Path

import yaml

HCL_GLOBS = ["*.tf", "modules/**/*.tf"]
IDENTIFIER_KEYS = ["type", "name", "id"]
JSON_GLOBS = ["schemas/*.json"]
# JSON Schema's `if`/`then`/`else` triplet has a canonical reading order that
# matches programming-language conditionals; alphabetising would put `else`
# before the condition. Skip ordering for objects whose keys are a subset of
# this triplet.
JSON_SCHEMA_CONDITIONAL = {"if", "then", "else"}
PREK_IDENTIFIER_KEYS = ["id", "name"]
PROJECT_ROOT = Path(__file__).resolve().parent.parent
YAML_GLOBS = ["data/**/*.yml", ".pre-commit-config.yaml"]


def collect(globs):
    paths = []
    for pattern in globs:
        paths.extend(PROJECT_ROOT.glob(pattern))
    return sorted(set(paths))


def expected_order(data, kind, identifier_keys=()):
    keys = list(data.keys())
    identifiers = [key for key in identifier_keys if key in keys]
    sortable_keys = [key for key in keys if key not in identifiers]
    singles = sorted(k for k in sortable_keys if not is_multi(data[k], kind))
    multis = sorted(k for k in sortable_keys if is_multi(data[k], kind))
    return identifiers + singles + multis


def hcl_assignment_errors(path):
    errors = []
    lines = path.read_text().splitlines()
    locals_ranges = []
    locals_start = None
    records = {}

    for index, line in enumerate(lines):
        if line == "locals {":
            locals_start = index
        elif locals_start is not None and line == "}":
            locals_ranges.append(range(locals_start, index + 1))
            locals_start = None

        match = re.match(
            r'^(?P<indent>\s+)(?P<key>"[^"]+"|[A-Za-z_][A-Za-z0-9_-]*)\s*=\s*(?P<value>.*)$',
            line,
        )
        if not match:
            continue

        end = hcl_expression_end(lines, index, match.group("value"))
        records[index] = {
            "dynamic_key": match.group("key").startswith('"${'),
            "end": end,
            "indent": len(match.group("indent")),
            "key": match.group("key").strip('"'),
            "multi": end > index,
        }

    last_by_indent = {}
    for index, line in enumerate(lines):
        indent = len(line) - len(line.lstrip())
        stripped = line.strip()

        if stripped.startswith("}"):
            last_by_indent = {
                key: value for key, value in last_by_indent.items() if key <= indent
            }

        if index not in records:
            if stripped.endswith("{") and "=" not in stripped:
                last_by_indent.pop(indent + 2, None)
            continue

        current = records[index]
        previous = last_by_indent.get(current["indent"])
        if previous is not None:
            has_separator = any(
                not separator.strip()
                for separator in lines[previous["end"] + 1 : index]
            )
            in_top_level_locals = current["indent"] == 2 and any(
                index in locals_range for locals_range in locals_ranges
            )
            if previous["multi"] and not current["multi"] and not in_top_level_locals:
                errors.append(
                    f"{path}:{index + 1}: single-line assignment "
                    f"{current['key']!r} follows a multi-line assignment"
                )
            if (
                (previous["multi"] or current["multi"])
                and not (previous["dynamic_key"] or current["dynamic_key"])
                and not has_separator
            ):
                errors.append(
                    f"{path}:{index + 1}: missing blank line adjacent to "
                    "a multi-line assignment"
                )

        last_by_indent[current["indent"]] = current

    return errors


def hcl_expression_end(lines, start, first_value):
    if first_value.startswith('"') and first_value.endswith('"'):
        return start

    heredoc = re.search(r"<<-?([A-Za-z_][A-Za-z0-9_]*)", first_value)
    if heredoc:
        marker = heredoc.group(1)
        for index in range(start + 1, len(lines)):
            if lines[index].strip() == marker:
                return index
        return len(lines) - 1

    balance = {"(": 0, "[": 0, "{": 0}
    pairs = {")": "(", "]": "[", "}": "{"}
    for index in range(start, len(lines)):
        text = first_value if index == start else lines[index]
        for character in hcl_sanitized(text):
            if character in balance:
                balance[character] += 1
            elif character in pairs:
                balance[pairs[character]] -= 1
        if all(value == 0 for value in balance.values()):
            return index
    return len(lines) - 1


def hcl_local_errors(path):
    errors = []
    local_names = []
    locals_line = None

    for line_number, line in enumerate(path.read_text().splitlines(), start=1):
        if line == "locals {":
            local_names = []
            locals_line = line_number
            continue

        if locals_line is None:
            continue

        if line == "}":
            expected = sorted(local_names)
            if local_names != expected:
                errors.append(
                    f"{path}:{locals_line}: locals out of order\n"
                    f"    actual:   {local_names}\n"
                    f"    expected: {expected}"
                )
            local_names = []
            locals_line = None
            continue

        match = re.match(r"^  (_?[a-z][a-z0-9_]*)\s*=", line)
        if match:
            local_names.append(match.group(1))

    return errors


def hcl_sanitized(line):
    result = []
    escaped = False
    quoted = False
    index = 0

    while index < len(line):
        character = line[index]
        if quoted:
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == '"':
                quoted = False
            index += 1
            continue

        if character == '"':
            quoted = True
        elif character == "#":
            break
        elif character == "/" and index + 1 < len(line) and line[index + 1] == "/":
            break
        else:
            result.append(character)
        index += 1

    return "".join(result)


def is_json_schema_conditional(keys):
    return "if" in keys and set(keys).issubset(JSON_SCHEMA_CONDITIONAL)


def is_multi(value, kind):
    if isinstance(value, dict):
        return len(value) > 0
    if isinstance(value, list):
        if not value:
            return False
        if kind == "yaml":
            return True
        return any(isinstance(item, (dict, list)) for item in value)
    return False


def list_identifier_keys(path, location):
    if path.name == ".pre-commit-config.yaml" and location[-1:] == ["hooks"]:
        return PREK_IDENTIFIER_KEYS
    return IDENTIFIER_KEYS


def walk(path, data, location, errors, kind, identifier_keys=()):
    if isinstance(data, dict):
        keys = list(data.keys())
        if len(keys) >= 2 and not (kind == "json" and is_json_schema_conditional(keys)):
            expected = expected_order(data, kind, identifier_keys)
            if keys != expected:
                loc = "/" + "/".join(location) if location else "(root)"
                errors.append(
                    f"{path}: at {loc}: keys out of order\n"
                    f"    actual:   {keys}\n"
                    f"    expected: {expected}"
                )
        for key, value in data.items():
            walk(path, value, location + [str(key)], errors, kind)
    elif isinstance(data, list):
        for index, item in enumerate(data):
            walk(
                path,
                item,
                location + [f"[{index}]"],
                errors,
                kind,
                list_identifier_keys(path, location) if isinstance(item, dict) else (),
            )


def main():
    errors = []
    hcl_paths = collect(HCL_GLOBS)
    json_paths = collect(JSON_GLOBS)
    yaml_paths = collect(YAML_GLOBS)

    for path in hcl_paths:
        errors.extend(hcl_assignment_errors(path))
        errors.extend(hcl_local_errors(path))

    for path in yaml_paths:
        try:
            data = yaml.safe_load(path.read_text())
        except yaml.YAMLError as exc:
            errors.append(f"{path}: parse error: {exc}")
            continue
        if data is not None:
            walk(path, data, [], errors, "yaml")

    for path in json_paths:
        try:
            data = json.loads(path.read_text())
        except json.JSONDecodeError as exc:
            errors.append(f"{path}: parse error: {exc}")
            continue
        walk(path, data, [], errors, "json")

    if errors:
        for entry in errors:
            print(entry, file=sys.stderr)
        print(f"\nsort-check: {len(errors)} issue(s)", file=sys.stderr)
        sys.exit(1)

    print(
        f"sort-check: {len(hcl_paths)} HCL + {len(json_paths)} JSON + "
        f"{len(yaml_paths)} YAML - clean"
    )


if __name__ == "__main__":
    main()
