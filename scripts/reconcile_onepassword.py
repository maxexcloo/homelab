# /// script
# requires-python = ">=3.13"
# dependencies = [
#   "httpx==0.28.1",
#   "onepasswordconnectsdk==2.1.0",
# ]
# ///

import argparse
import base64
import hashlib
import json
import os
import re
import sys
from copy import deepcopy

from httpx import HTTPError
from onepasswordconnectsdk.client import Client

FIELD_NAME_PATTERN = re.compile(r"^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$")
GENERATOR_FIELD_PREFIX = "homelab_generator_"
OWNERSHIP_FIELD_ID = "homelab_ownership"
OWNERSHIP_SECTION_ID = "homelab"
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


def find_items(summaries, item_key, title):
    suffix = f" ({item_key})"
    return [
        summary
        for summary in summaries
        if summary.title == title or summary.title.endswith(suffix)
    ]


def generated_value(seed, generator):
    length = generator["length"]
    generator_type = generator["type"]
    if generator_type == "alphanumeric":
        return seed
    if generator_type == "base64":
        return base64.b64encode(
            hashlib.shake_256(seed.encode()).digest(length)
        ).decode()
    if generator_type == "hex":
        return hashlib.shake_256(seed.encode()).hexdigest(length)
    raise RuntimeError(f"unsupported 1Password generator type: {generator_type}")


def generation_recipe(generator):
    generator_type = generator["type"]
    if generator_type == "alphanumeric":
        return {
            "characterSets": ["LETTERS", "DIGITS"],
            "length": generator["length"],
        }
    if generator_type in {"base64", "hex"}:
        return {
            "characterSets": ["LETTERS", "DIGITS", "SYMBOLS"],
            "length": 64,
        }
    raise RuntimeError(f"unsupported 1Password generator type: {generator_type}")


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


def merge_fields(existing, desired, ownership, previous_ownership):
    existing_fields = existing.setdefault("fields", [])
    existing_by_id = index_by(existing_fields, "id", "1Password item fields")
    desired_by_id = index_by(desired.get("fields", []), "id", "desired item fields")
    current_fields = set(ownership["managed_fields"]) | set(
        ownership["placeholder_fields"]
    )
    preserved = []

    removed = set(previous_ownership.get("managed_fields", [])) - current_fields
    for field_id in (
        set(previous_ownership.get("placeholder_fields", [])) - current_fields
    ):
        if existing_by_id.get(field_id, {}).get("value") in (None, ""):
            removed.add(field_id)
        elif field_id in existing_by_id:
            preserved.append(field_id)
    if removed:
        existing_fields[:] = [
            field for field in existing_fields if field.get("id") not in removed
        ]
        existing_by_id = index_by(existing_fields, "id", "1Password item fields")

    for field_id, desired_field in desired_by_id.items():
        if desired_field.get("label") != field_id or not FIELD_NAME_PATTERN.fullmatch(
            field_id
        ):
            raise RuntimeError(f"field ID and label must match snake_case: {field_id}")

        existing_value = existing_by_id.get(field_id, {}).get("value")
        desired_value = desired_field.get("value")
        if field_id not in existing_by_id:
            existing_fields.append(deepcopy(desired_field))
            continue

        existing_field = existing_by_id[field_id]
        if field_id in ownership["managed_fields"]:
            if desired_value not in (None, ""):
                existing_field["value"] = desired_value
        elif existing_value not in (None, ""):
            if existing_value != desired_value:
                preserved.append(field_id)
        elif desired_value not in (None, ""):
            existing_field["value"] = desired_value

        for key in ("label", "purpose", "section", "type"):
            if key in desired_field:
                existing_field[key] = deepcopy(desired_field[key])

    unknown = sorted(
        set(existing_by_id)
        - set(desired_by_id)
        - SYSTEM_FIELD_IDS
        - {OWNERSHIP_FIELD_ID}
    )
    return preserved, sorted(removed), unknown


def merge_item(existing, item_config):
    desired = deepcopy(item_config.get("payload", item_config))
    ownership = ownership_config(item_config, desired)
    previous_ownership = read_ownership(existing)
    merged = deepcopy(existing)
    preserved, removed_fields, unknown = merge_fields(
        merged,
        desired,
        ownership,
        previous_ownership,
    )
    removed_urls = merge_urls(merged, desired, ownership, previous_ownership)

    merged["category"] = desired["category"]
    merged["title"] = desired["title"]

    existing_tags = merged.setdefault("tags", [])
    existing_tags.extend(
        tag for tag in desired.get("tags", []) if tag not in existing_tags
    )
    write_ownership(merged, ownership)
    return merged, preserved, removed_fields, removed_urls, unknown


def merge_urls(existing, desired, ownership, previous_ownership):
    existing_urls = existing.setdefault("urls", [])
    desired_urls = desired.get("urls", [])
    current_urls = set(ownership["managed_urls"])
    removed = set(previous_ownership.get("managed_urls", [])) - current_urls
    if removed:
        existing_urls[:] = [
            url for url in existing_urls if url.get("label") not in removed
        ]

    existing_by_label = index_by(existing_urls, "label", "1Password item URLs")
    for desired_url in desired_urls:
        desired_url = deepcopy(desired_url)
        primary = desired_url.pop("primary", None)
        label = desired_url["label"]
        if label in existing_by_label:
            existing_by_label[label].update(desired_url)
            if primary:
                existing_by_label[label]["primary"] = True
            else:
                existing_by_label[label].pop("primary", None)
        else:
            if primary:
                desired_url["primary"] = True
            existing_urls.append(desired_url)
    return sorted(removed)


def ownership_config(item_config, desired):
    desired_fields = {field["id"] for field in desired.get("fields", [])}
    desired_urls = {url["label"] for url in desired.get("urls", [])}
    managed_fields = set(item_config.get("managed_fields", []))
    managed_urls = set(item_config.get("managed_urls", []))
    placeholder_fields = set(item_config.get("placeholder_fields", []))
    generated_fields = set(item_config.get("generated_fields", {}))

    if managed_fields & placeholder_fields:
        overlap = ", ".join(sorted(managed_fields & placeholder_fields))
        raise RuntimeError(f"fields cannot be managed and placeholders: {overlap}")
    if not generated_fields <= managed_fields:
        extra = ", ".join(sorted(generated_fields - managed_fields))
        raise RuntimeError(f"generated fields must be managed: {extra}")
    if desired_fields != managed_fields | placeholder_fields:
        missing = ", ".join(
            sorted(desired_fields - managed_fields - placeholder_fields)
        )
        extra = ", ".join(sorted(managed_fields | placeholder_fields - desired_fields))
        raise RuntimeError(
            f"field ownership does not match desired fields (missing: {missing or '-'}; "
            f"extra: {extra or '-'})"
        )
    if desired_urls != managed_urls:
        raise RuntimeError("URL ownership does not match desired URLs")
    return {
        "managed_fields": sorted(managed_fields),
        "managed_urls": sorted(managed_urls),
        "placeholder_fields": sorted(placeholder_fields),
        "version": 1,
    }


def parse_args():
    parser = argparse.ArgumentParser(
        description="Read or reconcile 1Password Connect items."
    )
    parser.add_argument(
        "--inventory",
        action="store_true",
        help="Return selected item IDs and fields for the OpenTofu external provider.",
    )
    parser.add_argument(
        "--write",
        action="store_true",
        help="Create and update items; reconciliation is otherwise read-only.",
    )
    return parser.parse_args()


def populate_generated_fields(client, path, existing, item_config):
    generated = []
    desired = item_config.get("payload", item_config)
    desired_by_id = index_by(desired.get("fields", []), "id", "desired item fields")

    for field_id, generator in sorted(item_config.get("generated_fields", {}).items()):
        if field_id not in desired_by_id:
            raise RuntimeError(f"generated field is not in desired fields: {field_id}")

        existing_by_id = index_by(
            existing.setdefault("fields", []), "id", "1Password item fields"
        )
        if existing_by_id.get(field_id, {}).get("value") not in (None, ""):
            continue

        target = deepcopy(desired_by_id[field_id])
        generator_type = generator["type"]
        generation_required = True
        if generator_type == "alphanumeric":
            target.pop("value", None)
            target["generate"] = True
            target["recipe"] = generation_recipe(generator)
            if field_id in existing_by_id:
                existing_by_id[field_id].update(target)
            else:
                existing["fields"].append(target)
        else:
            temporary_id = f"{GENERATOR_FIELD_PREFIX}{field_id}"
            if temporary_id in existing_by_id:
                temporary = existing_by_id[temporary_id]
                generation_required = temporary.get("value") in (None, "")
                temporary.update(
                    {
                        "generate": True,
                        "label": temporary_id,
                        "recipe": generation_recipe(generator),
                        "type": "CONCEALED",
                    }
                )
            else:
                existing["fields"].append(
                    {
                        "generate": True,
                        "id": temporary_id,
                        "label": temporary_id,
                        "recipe": generation_recipe(generator),
                        "type": "CONCEALED",
                    }
                )

        if generation_required:
            existing = api_request(client, "PUT", path, existing).json()
        existing_by_id = index_by(
            existing.get("fields", []), "id", "generated 1Password item fields"
        )
        source_id = (
            field_id
            if generator_type == "alphanumeric"
            else f"{GENERATOR_FIELD_PREFIX}{field_id}"
        )
        seed = existing_by_id.get(source_id, {}).get("value")
        if not seed:
            existing = api_request(client, "GET", path).json()
            existing_by_id = index_by(
                existing.get("fields", []), "id", "generated 1Password item fields"
            )
            seed = existing_by_id.get(source_id, {}).get("value")
        if not seed:
            raise RuntimeError(f"1Password did not generate field: {field_id}")

        if generator_type != "alphanumeric":
            existing["fields"] = [
                field for field in existing["fields"] if field.get("id") != source_id
            ]
            existing_by_id = index_by(existing["fields"], "id", "1Password item fields")
            target["value"] = generated_value(seed, generator)
            if field_id in existing_by_id:
                existing_by_id[field_id].update(target)
            else:
                existing["fields"].append(target)

        existing = strip_generation_directives(existing)
        existing = api_request(client, "PUT", path, existing).json()
        generated.append(field_id)

    return strip_generation_directives(existing), generated


def read_inventory(client):
    query = read_json_input()
    try:
        field_names = json.loads(query.get("field_names", "{}"))
        titles = json.loads(query["titles"])
        vault_id = query["vault_id"]
    except (KeyError, json.JSONDecodeError, TypeError) as error:
        raise RuntimeError("invalid inventory query") from error

    summaries = client.get_items(vault_id)
    duplicates = []
    existing_fields = {}
    item_ids = {}
    missing = []
    for item_key, title in sorted(titles.items()):
        matches = find_items(summaries, item_key, title)
        if len(matches) > 1:
            duplicates.append(item_key)
            continue
        if not matches:
            missing.append(item_key)
            continue
        item_id = matches[0].id
        item_ids[item_key] = item_id
        selected_names = set(field_names.get(item_key, []))
        if selected_names:
            item = api_request(
                client,
                "GET",
                f"/v1/vaults/{vault_id}/items/{item_id}",
            ).json()
            existing_fields[item_key] = {
                field["id"]: field["value"]
                for field in item.get("fields", [])
                if field.get("id") in selected_names
                and field.get("value") not in (None, "")
            }

    print(
        json.dumps(
            {
                "duplicates": json.dumps(duplicates),
                "existing_fields": json.dumps(existing_fields),
                "item_ids": json.dumps(item_ids),
                "missing": json.dumps(missing),
            },
            separators=(",", ":"),
            sort_keys=True,
        )
    )


def read_json_input(environment_name=None):
    if environment_name and os.environ.get(environment_name):
        try:
            return json.loads(os.environ[environment_name])
        except json.JSONDecodeError as error:
            raise RuntimeError(f"{environment_name} must contain JSON") from error
    try:
        return json.load(sys.stdin)
    except json.JSONDecodeError as error:
        raise RuntimeError("stdin must contain JSON") from error


def read_manifest():
    manifest = read_json_input("ONEPASSWORD_MANIFEST")
    vaults = manifest.get("vaults")
    if not isinstance(vaults, dict) or not vaults:
        raise RuntimeError("manifest.vaults must be a non-empty object")
    return vaults


def read_ownership(item):
    fields = index_by(item.get("fields", []), "id", "1Password item fields")
    field = fields.get(OWNERSHIP_FIELD_ID)
    if field is None or field.get("value") in (None, ""):
        return {
            "managed_fields": [],
            "managed_urls": [],
            "placeholder_fields": [],
            "version": 1,
        }
    try:
        ownership = json.loads(field["value"])
    except (json.JSONDecodeError, TypeError) as error:
        raise RuntimeError("invalid homelab ownership metadata") from error
    if ownership.get("version") != 1:
        raise RuntimeError("unsupported homelab ownership metadata version")
    return ownership


def reconcile_vault(client, vault_key, vault, write):
    if not vault.get("enabled", True):
        print(f"{vault_key}: disabled")
        return

    vault_id = vault.get("vault_id")
    desired_items = vault.get("items")
    if not vault_id or not isinstance(desired_items, dict):
        raise RuntimeError(f"vault {vault_key} must contain vault_id and items")

    summaries = client.get_items(vault_id)
    for item_key in sorted(desired_items):
        item_config = desired_items[item_key]
        desired = deepcopy(item_config.get("payload", item_config))
        title = desired.get("title")
        if not title or not title.endswith(f" ({item_key})"):
            raise RuntimeError(f"invalid stable item title: {vault_key}/{item_key}")
        matches = find_items(summaries, item_key, title)
        if len(matches) > 1:
            raise RuntimeError(f"duplicate 1Password items: {vault_key}/{item_key}")

        if not matches:
            desired["vault"] = {"id": vault_id}
            desired, _, _, _, _ = merge_item(
                {"fields": [], "sections": [], "tags": [], "urls": []},
                item_config,
            )
            desired["vault"] = {"id": vault_id}
            if write:
                created = api_request(
                    client, "POST", f"/v1/vaults/{vault_id}/items", desired
                ).json()
                path = f"/v1/vaults/{vault_id}/items/{created['id']}"
                _, generated = populate_generated_fields(
                    client, path, created, item_config
                )
                if generated:
                    print(
                        f"{vault_key}/{item_key}: generated fields: "
                        f"{', '.join(generated)}"
                    )
            print(f"{vault_key}/{item_key}: {'created' if write else 'create'}")
            continue

        item_id = matches[0].id
        path = f"/v1/vaults/{vault_id}/items/{item_id}"
        existing = api_request(client, "GET", path).json()
        if write:
            existing, generated = populate_generated_fields(
                client, path, existing, item_config
            )
            if generated:
                print(
                    f"{vault_key}/{item_key}: generated fields: {', '.join(generated)}"
                )
        merged, preserved, removed_fields, removed_urls, unknown = merge_item(
            existing, item_config
        )
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
        if removed_fields:
            print(
                f"{vault_key}/{item_key}: managed fields removed: "
                f"{', '.join(removed_fields)}"
            )
        if removed_urls:
            print(
                f"{vault_key}/{item_key}: managed URLs removed: "
                f"{', '.join(removed_urls)}"
            )
        if url_changes:
            print(f"{vault_key}/{item_key}: URL changes: {', '.join(url_changes)}")

        change_summary = ", ".join(changed)
        if merged == existing:
            print(f"{vault_key}/{item_key}: current")
        elif write:
            api_request(client, "PUT", path, merged)
            print(f"{vault_key}/{item_key}: updated ({change_summary})")
        else:
            print(f"{vault_key}/{item_key}: update ({change_summary})")


def strip_generation_directives(item):
    for field in item.get("fields", []):
        field.pop("generate", None)
        field.pop("recipe", None)
    return item


def write_ownership(item, ownership):
    sections = item.setdefault("sections", [])
    section = next(
        (section for section in sections if section.get("id") == OWNERSHIP_SECTION_ID),
        None,
    )
    if section is None:
        sections.append({"id": OWNERSHIP_SECTION_ID, "label": "Homelab"})
    else:
        section["label"] = "Homelab"

    fields = item.setdefault("fields", [])
    fields_by_id = index_by(fields, "id", "1Password item fields")
    value = json.dumps(ownership, separators=(",", ":"), sort_keys=True)
    metadata = {
        "id": OWNERSHIP_FIELD_ID,
        "label": OWNERSHIP_FIELD_ID,
        "section": {"id": OWNERSHIP_SECTION_ID},
        "type": "STRING",
        "value": value,
    }
    if OWNERSHIP_FIELD_ID in fields_by_id:
        fields_by_id[OWNERSHIP_FIELD_ID].update(metadata)
    else:
        fields.append(metadata)


def main():
    args = parse_args()
    try:
        client = connect_client()
        if args.inventory:
            read_inventory(client)
        else:
            for vault_key, vault in sorted(read_manifest().items()):
                reconcile_vault(client, vault_key, vault, args.write)
    except (HTTPError, RuntimeError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
