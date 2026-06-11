#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["pyyaml>=6"]
# ///
"""Create a new service YAML and open it in $EDITOR."""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

import yaml

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SERVICES_DIR = PROJECT_ROOT / "data" / "services"


def sort_mapping(data: dict) -> dict:
    single_line = sorted(
        key
        for key, value in data.items()
        if not isinstance(value, (dict, list)) or not value
    )
    multi_line = sorted(
        key for key, value in data.items() if isinstance(value, (dict, list)) and value
    )
    return {key: data[key] for key in single_line + multi_line}


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit("usage: new_service.py <name> [target] [title]")

    name = sys.argv[1]
    target = sys.argv[2] if len(sys.argv) > 2 else "au-truenas"
    title = sys.argv[3] if len(sys.argv) > 3 else name.replace("-", " ").title()

    service = {
        "identity": {
            "name": name,
            "service": name,
            "title": title,
        },
        "targets": {target: {}},
    }

    body = yaml.dump(
        sort_mapping(service),
        default_flow_style=False,
        sort_keys=False,
        width=1000,
    )
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
