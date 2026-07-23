#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["pyyaml>=6"]
# ///
"""Lint HCL local assignments and YAML/JSON keys per AGENTS.md.

Within each mapping: single-line keys come first (alphabetical), then
multi-line keys (alphabetical).

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
