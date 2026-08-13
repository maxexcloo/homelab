import base64
import importlib.util
import json
from pathlib import Path

import pytest

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SCRIPT_PATH = PROJECT_ROOT / "scripts/reconcile_onepassword.py"


def load_reconciler():
    spec = importlib.util.spec_from_file_location("reconcile_onepassword", SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


RECONCILER = load_reconciler()


class FakeClient:
    def __init__(self, items, summaries):
        self.calls = []
        self.items = items
        self.summaries = summaries

    def build_request(self, method, path, body):
        self.calls.append((method, path, body))
        return FakeResponse(self.items.get(path))

    def get_items(self, _vault_id):
        return self.summaries


class FakeResponse:
    def __init__(self, payload):
        self.is_error = False
        self.payload = payload
        self.status_code = 200
        self.text = ""

    def json(self):
        return self.payload


class FakeSummary:
    def __init__(self, item_id, title):
        self.id = item_id
        self.title = title


def field(field_id, value):
    return {
        "id": field_id,
        "label": field_id,
        "type": "CONCEALED",
        "value": value,
    }


def item_config(
    fields=(), managed_fields=(), managed_urls=(), placeholders=(), urls=()
):
    return {
        "generated_fields": {},
        "managed_fields": list(managed_fields),
        "managed_urls": list(managed_urls),
        "placeholder_fields": list(placeholders),
        "payload": {
            "category": "LOGIN",
            "fields": list(fields),
            "title": "Example (example)",
            "urls": list(urls),
        },
    }


def ownership_field(**overrides):
    ownership = {
        "managed_fields": [],
        "managed_urls": [],
        "placeholder_fields": [],
        "version": 1,
    }
    ownership.update(overrides)
    return {
        "id": RECONCILER.OWNERSHIP_FIELD_ID,
        "label": RECONCILER.OWNERSHIP_FIELD_ID,
        "value": json.dumps(ownership),
    }


def test_generated_values_have_documented_lengths():
    seed = "1Password-generated-seed"

    encoded = RECONCILER.generated_value(seed, {"length": 12, "type": "base64"})
    hexadecimal = RECONCILER.generated_value(seed, {"length": 12, "type": "hex"})

    assert len(base64.b64decode(encoded)) == 12
    assert len(hexadecimal) == 24
    assert (
        RECONCILER.generated_value(seed, {"length": len(seed), "type": "alphanumeric"})
        == seed
    )


def test_merge_item_removes_previously_managed_fields():
    existing = {
        "fields": [
            field("obsolete", "managed-value"),
            ownership_field(managed_fields=["obsolete"]),
        ],
        "sections": [],
        "tags": [],
        "urls": [],
    }

    merged, preserved, removed_fields, removed_urls, unknown = RECONCILER.merge_item(
        existing, item_config()
    )

    assert "obsolete" not in {entry["id"] for entry in merged["fields"]}
    assert preserved == []
    assert removed_fields == ["obsolete"]
    assert removed_urls == []
    assert unknown == []


def test_merge_item_preserves_populated_retired_placeholders():
    existing = {
        "fields": [
            field("manual_token", "operator-value"),
            ownership_field(placeholder_fields=["manual_token"]),
        ],
        "sections": [],
        "tags": [],
        "urls": [],
    }

    merged, preserved, removed_fields, _removed_urls, unknown = RECONCILER.merge_item(
        existing, item_config()
    )

    fields = {entry["id"]: entry for entry in merged["fields"]}
    assert fields["manual_token"]["value"] == "operator-value"
    assert preserved == ["manual_token"]
    assert removed_fields == []
    assert unknown == ["manual_token"]


def test_merge_item_removes_empty_retired_placeholders():
    existing = {
        "fields": [
            field("manual_token", ""),
            ownership_field(placeholder_fields=["manual_token"]),
        ],
        "sections": [],
        "tags": [],
        "urls": [],
    }

    merged, _preserved, removed_fields, _removed_urls, _unknown = RECONCILER.merge_item(
        existing, item_config()
    )

    assert "manual_token" not in {entry["id"] for entry in merged["fields"]}
    assert removed_fields == ["manual_token"]


def test_merge_item_removes_only_owned_urls():
    existing = {
        "fields": [ownership_field(managed_urls=["old"])],
        "sections": [],
        "tags": [],
        "urls": [
            {"href": "https://old.example.com", "label": "old"},
            {"href": "https://manual.example.com", "label": "manual"},
        ],
    }

    merged, _preserved, _removed_fields, removed_urls, _unknown = RECONCILER.merge_item(
        existing, item_config()
    )

    assert merged["urls"] == [{"href": "https://manual.example.com", "label": "manual"}]
    assert removed_urls == ["old"]


def test_ownership_rejects_duplicate_url_labels():
    url = {"href": "https://example.com", "label": "default"}
    config = item_config(managed_urls=["default"], urls=[url, url])

    with pytest.raises(RuntimeError, match="duplicate label: default"):
        RECONCILER.ownership_config(config, config["payload"])


def test_ownership_rejects_overlapping_field_modes():
    config = item_config(
        fields=[field("token", "")],
        managed_fields=["token"],
        placeholders=["token"],
    )

    with pytest.raises(RuntimeError, match="cannot be managed and placeholders"):
        RECONCILER.ownership_config(config, config["payload"])


def test_prune_removes_only_absent_owned_items():
    vault_id = "vault"
    orphan_path = f"/v1/vaults/{vault_id}/items/orphan-id"
    manual_path = f"/v1/vaults/{vault_id}/items/manual-id"
    client = FakeClient(
        items={
            manual_path: {"fields": []},
            orphan_path: {"fields": [ownership_field()]},
        },
        summaries=[
            FakeSummary("current-id", "Current (current)"),
            FakeSummary("manual-id", "Manual"),
            FakeSummary("orphan-id", "Orphan (orphan)"),
        ],
    )
    vault = {
        "items": {
            "current": {
                "title": "Current (current)",
            }
        },
        "vault_id": vault_id,
    }

    RECONCILER.prune_vault(client, "services", vault, write=True)

    delete_paths = [path for method, path, _body in client.calls if method == "DELETE"]
    assert delete_paths == [orphan_path]
