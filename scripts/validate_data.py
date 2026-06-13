#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["jsonschema>=4", "pyyaml>=6"]
# ///
"""Validate source YAML and the default-merged objects consumed by OpenTofu."""

import json
import sys
from copy import deepcopy
from pathlib import Path

import yaml
from jsonschema import Draft7Validator

PROJECT_ROOT = Path(__file__).resolve().parent.parent


class UniqueKeyLoader(yaml.SafeLoader):
    pass


def construct_unique_mapping(loader, node, deep=False):
    keys = set()
    for key_node, _value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in keys:
            raise yaml.constructor.ConstructorError(
                "while constructing a mapping",
                node.start_mark,
                f"found duplicate key {key!r}",
                key_node.start_mark,
            )
        keys.add(key)

    return yaml.SafeLoader.construct_mapping(loader, node, deep=deep)


UniqueKeyLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG,
    construct_unique_mapping,
)


def deep_merge(base, overlay):
    merged = deepcopy(base)
    for key, value in overlay.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = deep_merge(merged[key], value)
        else:
            merged[key] = deepcopy(value)
    return merged


def error_path(error):
    return ".".join(str(part) for part in error.absolute_path) or "(root)"


def load_json(path):
    def unique_object(pairs):
        data = {}
        for key, value in pairs:
            if key in data:
                raise ValueError(f"{path}: found duplicate key {key!r}")
            data[key] = value
        return data

    return json.loads(path.read_text(), object_pairs_hook=unique_object)


def load_yaml(path):
    return yaml.load(path.read_text(), Loader=UniqueKeyLoader)


def validate(instance, schema, label, errors):
    validator = Draft7Validator(schema)
    for error in sorted(
        validator.iter_errors(instance), key=lambda item: list(item.path)
    ):
        errors.append(f"{label}: {error_path(error)}: {error.message}")


def main():
    errors = []
    defaults = load_yaml(PROJECT_ROOT / "data/defaults.yml")

    schemas = {
        name: load_json(PROJECT_ROOT / f"schemas/{name}.json")
        for name in ("config", "defaults", "dns", "server", "service")
    }

    validate(
        load_yaml(PROJECT_ROOT / "data/config.yml"),
        schemas["config"],
        "data/config.yml",
        errors,
    )
    validate(defaults, schemas["defaults"], "data/defaults.yml", errors)

    for path in sorted((PROJECT_ROOT / "data/servers").glob("*.yml")):
        server = deep_merge(defaults["servers"], load_yaml(path))
        validate(server, schemas["server"], path.relative_to(PROJECT_ROOT), errors)

    for path in sorted((PROJECT_ROOT / "data/services").glob("*.yml")):
        service = deep_merge(defaults["services"], load_yaml(path))
        validate(service, schemas["service"], path.relative_to(PROJECT_ROOT), errors)

    for path in sorted((PROJECT_ROOT / "data/dns").glob("*.yml")):
        zone = load_yaml(path)
        zone["records"] = [
            deep_merge(defaults["dns"], record) for record in zone.get("records", [])
        ]
        validate(zone, schemas["dns"], path.relative_to(PROJECT_ROOT), errors)

    for target_name in ("fly", "truenas"):
        validate(
            defaults["targets"][target_name],
            schemas["service"]["definitions"][f"{target_name}_target"],
            f"data/defaults.yml: targets.{target_name}",
            errors,
        )

    if errors:
        print("\n".join(errors), file=sys.stderr)
        raise SystemExit(1)

    print("data validation: config, defaults, DNS, servers, and services - clean")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, yaml.YAMLError) as error:
        print(f"data validation: {error}", file=sys.stderr)
        raise SystemExit(1) from None
