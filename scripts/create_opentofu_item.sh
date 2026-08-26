#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mise_path="${repo_dir}/.mise.toml"

for tool in curl jq yq; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "error: ${tool} is required but not found in PATH." >&2
    exit 1
  fi
done

if [[ -z "${OP_CONNECT_HOST:-}" || "${OP_CONNECT_HOST}" == "REPLACE_ME" ]]; then
  echo "error: set OP_CONNECT_HOST in .mise.local.toml." >&2
  exit 1
fi

if [[ -z "${OP_CONNECT_TOKEN:-}" || "${OP_CONNECT_TOKEN}" == "REPLACE_ME" ]]; then
  echo "error: set OP_CONNECT_TOKEN in .mise.local.toml." >&2
  exit 1
fi

connect_host="${OP_CONNECT_HOST%/}"
required_fields_json="$(
  yq -p=toml -o=json '
    [.env[]
      | select(test("^op://Homelab/OpenTofu/"))
      | sub("^op://Homelab/OpenTofu/"; "")]
    | unique
    | sort
  ' "${mise_path}"
)"

if [[ "$(jq 'length' <<<"${required_fields_json}")" -eq 0 ]]; then
  echo "error: no Homelab/OpenTofu references found in .mise.toml." >&2
  exit 1
fi

read -r vault_count vault_id < <(
  curl -fsS \
    -H "Authorization: Bearer ${OP_CONNECT_TOKEN}" \
    "${connect_host}/v1/vaults" |
    jq -r '[.[] | select(.name == "Homelab")] | "\(length) \(.[0].id // "")"'
)

if [[ "${vault_count}" -ne 1 ]]; then
  echo "error: expected exactly one accessible Homelab vault; found ${vault_count}." >&2
  exit 1
fi

read -r item_count item_id < <(
  curl -fsS \
    -H "Authorization: Bearer ${OP_CONNECT_TOKEN}" \
    "${connect_host}/v1/vaults/${vault_id}/items" |
    jq -r '[.[] | select(.title == "OpenTofu")] | "\(length) \(.[0].id // "")"'
)

if [[ "${item_count}" -gt 1 ]]; then
  echo "error: found multiple OpenTofu items in the Homelab vault." >&2
  exit 1
fi

if [[ "${item_count}" -eq 1 ]]; then
  actual_fields_json="$(
    curl -fsS \
      -H "Authorization: Bearer ${OP_CONNECT_TOKEN}" \
      "${connect_host}/v1/vaults/${vault_id}/items/${item_id}" |
      jq '[.fields[] | select(.id != "notesPlain") | .label] | unique | sort'
  )"
  missing_fields="$(
    jq -nr \
      --argjson actual "${actual_fields_json}" \
      --argjson required "${required_fields_json}" \
      '$required - $actual | .[]'
  )"

  if [[ -n "${missing_fields}" ]]; then
    echo "error: the Homelab/OpenTofu item is missing these fields:" >&2
    while IFS= read -r field; do
      echo "  - ${field}" >&2
    done <<<"${missing_fields}"
    exit 1
  fi

  echo "The Homelab/OpenTofu item already exists."
  exit 0
fi

fields_json="$(
  jq -cn --argjson labels "${required_fields_json}" '
    $labels
    | map({id: ascii_downcase, label: ., type: "CONCEALED", value: ""})
  '
)"

jq -cn \
  --arg vault_id "${vault_id}" \
  --argjson fields "${fields_json}" '
    {
      category: "API_CREDENTIAL",
      title: "OpenTofu",
      fields: ([{
        id: "notesPlain",
        label: "notesPlain",
        purpose: "NOTES",
        type: "STRING",
        value: "Provider environment for the homelab OpenTofu root."
      }] + $fields),
      vault: {id: $vault_id}
    }
  ' |
  curl -fsS \
    -X POST \
    -H "Authorization: Bearer ${OP_CONNECT_TOKEN}" \
    -H "Content-Type: application/json" \
    --data-binary @- \
    "${connect_host}/v1/vaults/${vault_id}/items" \
    -o /dev/null

echo "Created Homelab/OpenTofu. Populate every concealed field before planning or applying."
