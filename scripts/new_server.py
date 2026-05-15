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


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit(
            "usage: new_server.py <name> [region] [platform] [type] [parent]"
        )

    name = sys.argv[1]
    region = sys.argv[2] if len(sys.argv) > 2 else "au"
    platform = sys.argv[3] if len(sys.argv) > 3 else "unmanaged"
    server_type = sys.argv[4] if len(sys.argv) > 4 else "server"
    parent = sys.argv[5] if len(sys.argv) > 5 else None

    schema = json.loads(SERVER_SCHEMA.read_text())

    server: dict = {
        "identity": {
            "name": name,
            "region": region,
            "title": name.replace("-", " ").title(),
        },
        "platform": platform,
        "type": server_type,
    }
    if parent:
        server["parent"] = parent

    # Build key
    key = name if name == region else f"{region}-{name}"
    if parent:
        key = f"{parent}-{name}"

    # Order keys as they appear in the schema
    ordered = {}
    for k in schema["properties"]:
        if k in server:
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
