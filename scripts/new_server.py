#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["pyyaml>=6"]
# ///
"""Create a new server YAML from schema defaults and open it in $EDITOR."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import yaml

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SERVER_SCHEMA = PROJECT_ROOT / "schemas" / "server.json"
SERVERS_DIR = PROJECT_ROOT / "data" / "servers"
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
        raise SystemExit("usage: new_server.py <name> [region] [platform] [type] [parent]")

    name = sys.argv[1]
    region = sys.argv[2] if len(sys.argv) > 2 else "au"
    platform = sys.argv[3] if len(sys.argv) > 3 else "unmanaged"
    server_type = sys.argv[4] if len(sys.argv) > 4 else "server"
    parent = sys.argv[5] if len(sys.argv) > 5 else None

    schema = json.loads(SERVER_SCHEMA.read_text())

    # Build base from schema defaults
    server = {k: default_for(v) for k, v in schema["properties"].items()}

    # Overlay defaults.yml server defaults
    if DEFAULTS_YAML.exists():
        defaults = yaml.safe_load(DEFAULTS_YAML.read_text())
        if "servers" in defaults:
            server = deep_merge(server, defaults["servers"])

    # User overrides
    server["identity"] = {
        "name": name,
        "region": region,
        "title": name.replace("-", " ").title(),
    }
    server["platform"] = platform
    server["type"] = server_type
    if parent:
        server["parent"] = parent
    else:
        server.pop("parent", None)

    # Remove empty networking fields
    if "networking" in server:
        networking = {k: v for k, v in server["networking"].items() if v}
        if networking:
            server["networking"] = networking
        else:
            server.pop("networking", None)

    # Build key
    key = name if name == region else f"{region}-{name}"
    if parent:
        key = f"{parent}-{name}"

    # Order keys for readability
    order = ["platform", "type", "parent", "features", "identity", "networking", "platform_config", "credentials", "dashboard", "data"]
    ordered = {}
    for k in order:
        if k in server:
            ordered[k] = server[k]
    for k in server:
        if k not in ordered:
            ordered[k] = server[k]

    body = yaml.dump(ordered, default_flow_style=False, sort_keys=False, width=1000)
    content = f"# yaml-language-server: $schema=../../schemas/server.json\n{body}"

    out_path = SERVERS_DIR / f"{key}.yml"
    if out_path.exists():
        raise SystemExit(f"{out_path} already exists")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(content)
    print(f"Created {out_path.relative_to(PROJECT_ROOT)}")

    editor = os.environ.get("EDITOR", "vim")
    subprocess.call([editor, str(out_path)])


if __name__ == "__main__":
    main()
