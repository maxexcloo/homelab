# /// script
# requires-python = ">=3.13"
# dependencies = [
#   "httpx==0.28.1",
#   "onepasswordconnectsdk==2.1.0",
# ]
# ///

import argparse
import json
import os
import re
import sys
from copy import deepcopy

from httpx import HTTPError
from onepasswordconnectsdk.client import Client

FIELD_NAME_PATTERN = re.compile(r"^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$")
SYSTEM_FIELD_IDS = frozenset({"notesPlain", "password", "username"})


def api_request(client, method, path, body=None):
    response = client.build_request(method, path, body)
    if response.is_error:
        raise RuntimeError(f"1Password Connect returned HTTP {response.status_code}")
    return response


def connect_client():
    host = os.environ.get("OP_CONNECT_HOST") or os.environ.get(
        "TF_VAR_onepassword_connect_url"
    )
    token = os.environ.get("OP_CONNECT_TOKEN") or os.environ.get(
        "TF_VAR_onepassword_connect_token"
    )
    if not host or not token:
        raise RuntimeError(
            "OP_CONNECT_HOST and OP_CONNECT_TOKEN are required "
            "(the matching TF_VAR_ variables are also accepted)"
        )
    return Client(host, token)


def describe_url_changes(existing, merged):
    existing_urls = index_by(existing.get("urls", []), "label", "1Password item URLs")
    merged_urls = index_by(merged.get("urls", []), "label", "reconciled item URLs")
    changes = []
    for label, merged_url in merged_urls.items():
        if label not in existing_urls:
            changes.append(f"{label}[added]")
            continue
        fields = sorted(
            key
            for key in set(existing_urls[label]) | set(merged_url)
            if existing_urls[label].get(key) != merged_url.get(key)
        )
        if fields:
            changes.append(f"{label}[{','.join(fields)}]")
    return changes


def index_by(items, key, context):
    indexed = {}
    for item in items:
        value = item.get(key)
        if not value:
            raise RuntimeError(f"{context} has an entry without {key}")
        if value in indexed:
            raise RuntimeError(f"{context} has duplicate {key}: {value}")
        indexed[value] = item
    return indexed


def merge_fields(existing, desired):
    existing_fields = existing.setdefault("fields", [])
    existing_by_id = index_by(existing_fields, "id", "1Password item fields")
    desired_by_id = index_by(desired.get("fields", []), "id", "desired item fields")
    preserved = []

    for field_id, desired_field in desired_by_id.items():
        if desired_field.get("label") != field_id or not FIELD_NAME_PATTERN.fullmatch(
            field_id
        ):
            raise RuntimeError(f"field ID and label must match snake_case: {field_id}")

        if field_id not in existing_by_id:
            existing_fields.append(deepcopy(desired_field))
            continue

        existing_field = existing_by_id[field_id]
        existing_value = existing_field.get("value")
        desired_value = desired_field.get("value")
        if existing_value not in (None, ""):
            if desired_value not in (None, "") and existing_value != desired_value:
                preserved.append(field_id)
        elif desired_value not in (None, ""):
            existing_field["value"] = desired_value

        for key in ("label", "purpose", "section", "type"):
            if key in desired_field:
                existing_field[key] = deepcopy(desired_field[key])

    unknown = sorted(set(existing_by_id) - set(desired_by_id) - SYSTEM_FIELD_IDS)
    return preserved, unknown


def merge_item(existing, desired):
    merged = deepcopy(existing)
    preserved, unknown = merge_fields(merged, desired)

    if not merged.get("category"):
        merged["category"] = desired.get("category")

    existing_tags = merged.setdefault("tags", [])
    existing_tags.extend(
        tag for tag in desired.get("tags", []) if tag not in existing_tags
    )

    desired_urls = desired.get("urls", [])
    if desired_urls:
        existing_urls = merged.setdefault("urls", [])
        existing_urls_by_label = index_by(existing_urls, "label", "1Password item URLs")
        desired_urls_by_label = index_by(desired_urls, "label", "desired URLs")
        for label, desired_url in desired_urls_by_label.items():
            desired_url = deepcopy(desired_url)
            if desired_url.get("primary") is False:
                desired_url.pop("primary")
            if label in existing_urls_by_label:
                existing_urls_by_label[label].update(desired_url)
            else:
                existing_urls.append(desired_url)

    return merged, preserved, unknown


def parse_args():
    parser = argparse.ArgumentParser(
        description="Reconcile 1Password Connect items from JSON on stdin."
    )
    parser.add_argument(
        "--write",
        action="store_true",
        help="Create and update items; the default is a read-only dry run.",
    )
    return parser.parse_args()


def read_manifest():
    try:
        manifest = json.load(sys.stdin)
    except json.JSONDecodeError as error:
        raise RuntimeError(
            "stdin must contain the reconciliation manifest JSON"
        ) from error

    vaults = manifest.get("vaults")
    if not isinstance(vaults, dict) or not vaults:
        raise RuntimeError("manifest.vaults must be a non-empty object")
    return vaults


def reconcile_vault(client, vault_key, vault, write):
    if not vault.get("enabled", True):
        print(f"{vault_key}: disabled")
        return

    vault_id = vault.get("vault_id")
    desired_items = vault.get("items")
    if not vault_id or not isinstance(desired_items, dict):
        raise RuntimeError(f"vault {vault_key} must contain vault_id and items")

    summaries = client.get_items(vault_id)
    summaries_by_title = {}
    for summary in summaries:
        summaries_by_title.setdefault(summary.title, []).append(summary)

    for item_key in sorted(desired_items):
        desired = deepcopy(desired_items[item_key])
        title = desired.get("title")
        if not title or not title.endswith(f" ({item_key})"):
            raise RuntimeError(f"invalid stable item title: {vault_key}/{item_key}")
        matches = summaries_by_title.get(title, [])
        if len(matches) > 1:
            raise RuntimeError(f"duplicate 1Password items: {vault_key}/{item_key}")

        if not matches:
            desired["vault"] = {"id": vault_id}
            if write:
                api_request(client, "POST", f"/v1/vaults/{vault_id}/items", desired)
            print(f"{vault_key}/{item_key}: {'created' if write else 'create'}")
            continue

        item_id = matches[0].id
        path = f"/v1/vaults/{vault_id}/items/{item_id}"
        existing = api_request(client, "GET", path).json()
        merged, preserved, unknown = merge_item(existing, desired)
        changed = sorted(
            key
            for key in set(existing) | set(merged)
            if existing.get(key) != merged.get(key)
        )
        url_changes = describe_url_changes(existing, merged)

        if unknown:
            print(
                f"{vault_key}/{item_key}: unknown fields preserved: {', '.join(unknown)}"
            )
        if preserved:
            print(
                f"{vault_key}/{item_key}: non-empty values preserved: "
                f"{', '.join(preserved)}"
            )
        if url_changes:
            print(f"{vault_key}/{item_key}: URL changes: {', '.join(url_changes)}")

        if merged == existing:
            print(f"{vault_key}/{item_key}: current")
        elif write:
            api_request(client, "PUT", path, merged)
            print(f"{vault_key}/{item_key}: updated ({', '.join(changed)})")
        else:
            print(f"{vault_key}/{item_key}: update ({', '.join(changed)})")


def main():
    args = parse_args()
    try:
        client = connect_client()
        for vault_key, vault in sorted(read_manifest().items()):
            reconcile_vault(client, vault_key, vault, args.write)
    except (HTTPError, RuntimeError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
