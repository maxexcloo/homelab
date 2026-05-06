#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["pyyaml>=6"]
# ///
"""Create a small service YAML file and starter template."""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

import yaml

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SERVICE_SCHEMA = PROJECT_ROOT / "schemas" / "service.json"
SERVICES_DIR = PROJECT_ROOT / "data" / "services"
TEMPLATES_DIR = PROJECT_ROOT / "templates" / "services"


class HomelabDumper(yaml.SafeDumper):
    def increase_indent(self, flow: bool = False, indentless: bool = False):
        return super().increase_indent(flow, False)


def load_schema() -> dict[str, Any]:
    return json.loads(SERVICE_SCHEMA.read_text())


def pattern_for(schema: dict[str, Any], *path: str) -> str | None:
    node: dict[str, Any] = schema
    for key in path:
        node = node["properties"][key]
    return node.get("pattern")


def title_from_name(name: str) -> str:
    return " ".join(part.capitalize() for part in name.split("-"))


def prompt(value: str | None, label: str, default: str | None = None) -> str:
    if value is not None:
        return value
    if not sys.stdin.isatty():
        if default is not None:
            return default
        raise SystemExit(f"{label} is required in non-interactive mode")

    suffix = f" [{default}]" if default not in (None, "") else ""
    entered = input(f"{label}{suffix}: ").strip()
    if entered == "" and default is not None:
        return default
    return entered


def prompt_bool(value: bool, label: str, default: bool = False) -> bool:
    if value:
        return True
    if not sys.stdin.isatty():
        return default

    suffix = "Y/n" if default else "y/N"
    entered = input(f"{label} [{suffix}]: ").strip().lower()
    if entered == "":
        return default
    return entered in {"y", "yes", "true", "1"}


def prompt_choice(
    value: str | None, label: str, choices: list[str], default: str
) -> str:
    if value is not None:
        return value
    if not sys.stdin.isatty():
        return default

    while True:
        entered = input(f"{label} ({'/'.join(choices)}) [{default}]: ").strip()
        choice = entered or default
        if choice in choices:
            return choice
        print(f"Choose one of: {', '.join(choices)}", file=sys.stderr)


def prompt_optional(value: str | None, label: str) -> str | None:
    if value is not None:
        return value
    if not sys.stdin.isatty():
        return None

    entered = input(f"{label} [none]: ").strip()
    return entered or None


def prompt_optional_int(value: int | None, label: str) -> int | None:
    if value is not None:
        return value
    if not sys.stdin.isatty():
        return None

    while True:
        entered = input(f"{label} [none]: ").strip()
        if entered == "":
            return None
        try:
            number = int(entered)
        except ValueError:
            print("Enter a number, or leave blank.", file=sys.stderr)
            continue
        if 1 <= number <= 65535:
            return number
        print("Port must be between 1 and 65535.", file=sys.stderr)


def validate_pattern(value: str, pattern: str | None, label: str) -> None:
    if pattern is not None and not re.fullmatch(pattern, value):
        raise SystemExit(f"{label} must match {pattern}: {value}")


def render_service(service: dict[str, Any]) -> str:
    body = yaml.dump(
        service,
        Dumper=HomelabDumper,
        default_flow_style=False,
        sort_keys=False,
        width=1000,
    )
    return f"# yaml-language-server: $schema=../../schemas/service.json\n{body}"


def compose_template() -> str:
    return """services:
  ${service.identity.name}:
    image: REPLACE_ME
    restart: unless-stopped
"""


def truenas_catalog_template() -> str:
    return """{
  "values": {}
}
"""


def fly_dockerfile() -> str:
    return "FROM alpine:3.20\n"


def validate_service_yaml(content: str) -> None:
    validator = shutil.which("check-jsonschema")
    if validator is None:
        raise SystemExit(
            "check-jsonschema not found; run through mise or install the project tools"
        )

    with tempfile.NamedTemporaryFile("w", suffix=".yml", delete=True) as tmp:
        tmp.write(content)
        tmp.flush()
        result = subprocess.run(
            [validator, "--schemafile", str(SERVICE_SCHEMA), tmp.name],
            cwd=PROJECT_ROOT,
            capture_output=True,
            text=True,
        )

    if result.returncode != 0:
        if result.stdout:
            print(result.stdout, file=sys.stderr, end="")
        if result.stderr:
            print(result.stderr, file=sys.stderr, end="")
        raise SystemExit(result.returncode)


def write_file(path: Path, content: str, force: bool, dry_run: bool) -> None:
    if dry_run:
        print(f"--- {path.relative_to(PROJECT_ROOT)}")
        print(content, end="" if content.endswith("\n") else "\n")
        return
    if path.exists() and not force:
        raise SystemExit(
            f"{path.relative_to(PROJECT_ROOT)} exists; pass --force to overwrite"
        )

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
    print(f"Created {path.relative_to(PROJECT_ROOT)}")


def write_files(files: dict[Path, str], force: bool, dry_run: bool) -> None:
    existing = [path.relative_to(PROJECT_ROOT) for path in files if path.exists()]
    if existing and not force and not dry_run:
        raise SystemExit(
            "Refusing to overwrite existing files; pass --force to replace them:\n"
            + "\n".join(f"  {path}" for path in existing)
        )
    for path, content in files.items():
        write_file(path, content, force, dry_run)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("name", nargs="?")
    parser.add_argument("--description")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--expose", choices=["cloudflare", "external", "internal", "tailscale"]
    )
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--kind", choices=["compose", "fly", "none", "truenas-catalog"])
    parser.add_argument("--password", action="store_true")
    parser.add_argument("--port", type=int)
    parser.add_argument("--scheme", choices=["http", "https"])
    parser.add_argument("--service")
    parser.add_argument("--target")
    parser.add_argument("--title")
    parser.add_argument("--username")
    args = parser.parse_args()

    schema = load_schema()
    name_pattern = pattern_for(schema, "identity", "name")
    service_pattern = pattern_for(schema, "identity", "service")
    target_pattern = schema["properties"]["targets"]["propertyNames"]["pattern"]

    name = prompt(args.name, "Service name")
    service_key = prompt(args.service, "Template service key", name)
    target = prompt(args.target, "Target", "au-truenas")
    title = prompt(args.title, "Title", title_from_name(name))
    description = prompt_optional(args.description, "Description")
    kind = prompt_choice(
        args.kind,
        "Starter template",
        ["compose", "fly", "none", "truenas-catalog"],
        "fly" if target == "fly" else "compose",
    )
    port = prompt_optional_int(args.port, "Web port")
    password = prompt_bool(args.password, "Generate password")
    username = prompt_optional(args.username, "Username") if password else args.username

    if target == "fly" and kind != "fly":
        raise SystemExit("Target fly requires --kind fly")
    if kind == "fly" and port is None:
        raise SystemExit("Fly services require --port")

    validate_pattern(name, name_pattern, "Service name")
    validate_pattern(service_key, service_pattern, "Template service key")
    validate_pattern(target, target_pattern, "Target")

    identity = {
        "name": name,
        "service": service_key,
        "title": title,
    }
    if description is not None:
        identity = {
            "description": description,
            **identity,
        }
    if username is not None:
        identity["username"] = username

    service: dict[str, Any] = {}
    if password:
        service["features"] = {
            "password": True,
        }

    service["identity"] = identity
    if port is not None:
        service["routing"] = {
            "expose": prompt_choice(
                args.expose,
                "Exposure",
                ["cloudflare", "external", "internal", "tailscale"],
                "internal",
            ),
            "port": port,
            "scheme": prompt_choice(
                args.scheme, "Backend scheme", ["http", "https"], "http"
            ),
        }

    service["targets"] = {
        target: {},
    }

    content = render_service(service)
    validate_service_yaml(content)

    files = {
        SERVICES_DIR / f"{name}.yml": content,
    }
    if kind == "compose":
        files[TEMPLATES_DIR / service_key / "docker-compose.yaml.tftpl"] = (
            compose_template()
        )
    elif kind == "truenas-catalog":
        files[TEMPLATES_DIR / service_key / "app.json.tftpl"] = (
            truenas_catalog_template()
        )
    elif kind == "fly":
        files[TEMPLATES_DIR / service_key / "Dockerfile"] = fly_dockerfile()

    write_files(files, args.force, args.dry_run)


if __name__ == "__main__":
    main()
