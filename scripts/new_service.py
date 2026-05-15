#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["pyyaml>=6"]
# ///
"""Create a new service YAML from schema defaults and open it in $EDITOR."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import yaml

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SERVICE_SCHEMA = PROJECT_ROOT / "schemas" / "service.json"
SERVICES_DIR = PROJECT_ROOT / "data" / "services"
DEFAULTS_YAML = PROJECT_ROOT / "data" / "defaults.yml"


def default_for(prop: dict):
    """Return a sensible default for a single schema property."""
    if "default" in prop:
        return prop["default"]

    prop_type = prop.get("type")
    if isinstance(prop_type, list):
        prop_type = [t for t in prop_type if t != "null"][0]

    if prop_type == "boolean":
        return False
    if prop_type == "string":
        return ""
    if prop_type == "integer":
        return 0
    if prop_type == "array":
        return []
    if prop_type == "object" and "properties" in prop:
        return {k: default_for(v) for k, v in prop["properties"].items()}
    if "enum" in prop and prop["enum"]:
        return prop["enum"][0]

    return None


def deep_merge(base: dict, overlay: dict) -> dict:
    """Recursively merge overlay into base."""
    result = dict(base)
    for key, value in overlay.items():
        if isinstance(value, dict) and key in result and isinstance(result[key], dict):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = value
    return result


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit("usage: new_service.py <name> [target] [title]")

    name = sys.argv[1]
    target = sys.argv[2] if len(sys.argv) > 2 else "au-truenas"
    title = sys.argv[3] if len(sys.argv) > 3 else name.replace("-", " ").title()

    schema = json.loads(SERVICE_SCHEMA.read_text())

    # Build base from schema defaults
    service = {k: default_for(v) for k, v in schema["properties"].items()}

    # Overlay defaults.yml service defaults
    if DEFAULTS_YAML.exists():
        defaults = yaml.safe_load(DEFAULTS_YAML.read_text())
        if "services" in defaults:
            service = deep_merge(service, defaults["services"])

    # User overrides
    service["identity"] = {
        "name": name,
        "service": name,
        "title": title,
    }
    service["targets"] = {target: {}}

    # Remove empty structures
    for key in ["credentials", "dashboard", "data", "imports", "routing"]:
        if key in service:
            val = service[key]
            if val == {} or val == []:
                del service[key]
            elif key == "routing" and val == {"labels": {}, "urls": []}:
                del service[key]

    # Order keys
    order = ["features", "identity", "imports", "routing", "targets", "credentials", "dashboard", "data"]
    ordered = {}
    for k in order:
        if k in service:
            ordered[k] = service[k]
    for k in service:
        if k not in ordered:
            ordered[k] = service[k]

    body = yaml.dump(ordered, default_flow_style=False, sort_keys=False, width=1000)
    content = f"# yaml-language-server: $schema=../../schemas/service.json\n{body}"

    out_path = SERVICES_DIR / f"{name}.yml"
    if out_path.exists():
        raise SystemExit(f"{out_path} already exists")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(content)
    print(f"Created {out_path.relative_to(PROJECT_ROOT)}")

    editor = os.environ.get("EDITOR", "vim")
    subprocess.call([editor, str(out_path)])


if __name__ == "__main__":
    main()
