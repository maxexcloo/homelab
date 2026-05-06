#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["pyyaml>=6"]
# ///
"""Create a small server YAML file."""

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
SERVER_SCHEMA = PROJECT_ROOT / "schemas" / "server.json"
SERVERS_DIR = PROJECT_ROOT / "data" / "servers"

FEATURE_FLAGS = [
    "b2",
    "cloud_init",
    "cloudflare_acme_token",
    "cloudflare_zero_trust_tunnel",
    "docker",
    "password",
    "resend",
    "tailscale",
]


class HomelabDumper(yaml.SafeDumper):
    def increase_indent(self, flow: bool = False, indentless: bool = False):
        return super().increase_indent(flow, False)


def load_schema() -> dict[str, Any]:
    return json.loads(SERVER_SCHEMA.read_text())


def schema_node(schema: dict[str, Any], *path: str) -> dict[str, Any]:
    node = schema
    for key in path:
        node = node["properties"][key]
    return node


def enum_for(schema: dict[str, Any], *path: str) -> list[str]:
    return schema_node(schema, *path)["enum"]


def pattern_for(schema: dict[str, Any], *path: str) -> str | None:
    return schema_node(schema, *path).get("pattern")


def title_from_name(name: str) -> str:
    return " ".join(
        part.upper() if len(part) <= 3 else part.capitalize()
        for part in name.split("-")
    )


def default_key(name: str, region: str, parent: str | None) -> str:
    if name == region:
        return region
    if parent is not None:
        return f"{parent}-{name}"
    return f"{region}-{name}"


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
    return entered in {"1", "true", "y", "yes"}


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


def render_server(server: dict[str, Any]) -> str:
    body = yaml.dump(
        server,
        Dumper=HomelabDumper,
        default_flow_style=False,
        sort_keys=False,
        width=1000,
    )
    return f"# yaml-language-server: $schema=../../schemas/server.json\n{body}"


def validate_server_yaml(content: str) -> None:
    validator = shutil.which("check-jsonschema")
    if validator is None:
        raise SystemExit(
            "check-jsonschema not found; run through mise or install the project tools"
        )

    with tempfile.NamedTemporaryFile("w", suffix=".yml", delete=True) as tmp:
        tmp.write(content)
        tmp.flush()
        result = subprocess.run(
            [validator, "--schemafile", str(SERVER_SCHEMA), tmp.name],
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


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("name", nargs="?")
    parser.add_argument("--b2", action="store_true")
    parser.add_argument("--cloud-init", action="store_true")
    parser.add_argument("--cloudflare-acme-token", action="store_true")
    parser.add_argument("--cloudflare-tunnel", action="store_true")
    parser.add_argument("--description")
    parser.add_argument("--docker", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--management-address")
    parser.add_argument("--management-port", type=int)
    parser.add_argument("--parent")
    parser.add_argument("--password", action="store_true")
    parser.add_argument("--platform")
    parser.add_argument("--public-address")
    parser.add_argument("--public-ipv4")
    parser.add_argument("--public-ipv6")
    parser.add_argument("--region")
    parser.add_argument("--resend", action="store_true")
    parser.add_argument("--tailscale", action="store_true")
    parser.add_argument("--title")
    parser.add_argument("--type")
    parser.add_argument("--username")
    args = parser.parse_args()

    schema = load_schema()
    name_pattern = pattern_for(schema, "identity", "name")
    parent_pattern = pattern_for(schema, "parent")
    region_pattern = pattern_for(schema, "identity", "region")

    name = prompt(args.name, "Server name")
    region = prompt(args.region, "Region", "au")
    title = prompt(args.title, "Title", title_from_name(name))
    platform = prompt_choice(
        args.platform, "Platform", enum_for(schema, "platform"), "unmanaged"
    )
    server_type = prompt_choice(args.type, "Type", enum_for(schema, "type"), "server")
    parent = prompt_optional(args.parent, "Parent")
    description = prompt_optional(args.description, "Description")

    validate_pattern(name, name_pattern, "Server name")
    validate_pattern(region, region_pattern, "Region")
    if parent is not None:
        validate_pattern(parent, parent_pattern, "Parent")

    feature_values = {
        "b2": prompt_bool(args.b2, "Provision B2 credentials"),
        "cloud_init": prompt_bool(args.cloud_init, "Generate cloud-init"),
        "cloudflare_acme_token": prompt_bool(
            args.cloudflare_acme_token, "Provision Cloudflare ACME token"
        ),
        "cloudflare_zero_trust_tunnel": prompt_bool(
            args.cloudflare_tunnel, "Provision Cloudflare tunnel"
        ),
        "docker": prompt_bool(args.docker, "Docker host"),
        "password": prompt_bool(args.password, "Generate password"),
        "resend": prompt_bool(args.resend, "Provision Resend API key"),
        "tailscale": prompt_bool(args.tailscale, "Generate Tailscale auth key"),
    }

    username = (
        prompt_optional(args.username, "Username")
        if feature_values["password"]
        else args.username
    )
    management_address = prompt_optional(args.management_address, "Management address")
    management_port = prompt_optional_int(args.management_port, "Management port")
    public_address = prompt_optional(args.public_address, "Public CNAME")
    public_ipv4 = prompt_optional(args.public_ipv4, "Public IPv4")
    public_ipv6 = prompt_optional(args.public_ipv6, "Public IPv6")

    identity = {
        "name": name,
        "region": region,
        "title": title,
    }
    if description is not None:
        identity = {
            "description": description,
            **identity,
        }
    if username is not None:
        identity["username"] = username

    networking = {
        key: value
        for key, value in {
            "management_address": management_address,
            "management_port": management_port,
            "public_address": public_address,
            "public_ipv4": public_ipv4,
            "public_ipv6": public_ipv6,
        }.items()
        if value is not None
    }

    server: dict[str, Any] = {
        "platform": platform,
        "type": server_type,
    }
    if parent is not None:
        server = {
            "parent": parent,
            **server,
        }

    enabled_features = {
        feature: True for feature, enabled in feature_values.items() if enabled
    }
    if enabled_features:
        server["features"] = enabled_features
    server["identity"] = identity
    if networking:
        server["networking"] = networking

    content = render_server(server)
    validate_server_yaml(content)

    key = default_key(name, region, parent)
    validate_pattern(key, parent_pattern, "Server key")
    write_file(SERVERS_DIR / f"{key}.yml", content, args.force, args.dry_run)


if __name__ == "__main__":
    main()
