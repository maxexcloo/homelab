#!/bin/bash
set -e

# Helpers
function op_get() {
  curl -f -s -H "Authorization: Bearer $CONNECT_TOKEN" -H "Content-Type: application/json" "$CONNECT_HOST$1"
}

function op_put() {
  curl -f -s -X PUT -H "Authorization: Bearer $CONNECT_TOKEN" -H "Content-Type: application/json" -d @- "$CONNECT_HOST$1"
}

# 1. Resolve vault ID
VAULT_ID=$(op_get "/v1/vaults" | jq -r --arg vault "$VAULT" '.[] | select(.id == $vault or .name == $vault) | .id')

# 2. Validate vault
if [ -z "$VAULT_ID" ]; then
  echo "Error: Vault '$VAULT' not found." >&2
  exit 1
fi

# 3. Get current item
ITEM_JSON=$(op_get "/v1/vaults/$VAULT_ID/items/$ID")

# 4. Update Item
echo "$ITEM_JSON" | jq \
--argjson outputs "$OUTPUTS_JSON" \
--argjson urls "$URLS_JSON" \
'
  # Map existing output sections (Label -> ID)
  ([.sections[]? | select(.label | startswith("output-"))] | map({(.label): .id}) | add // {}) as $existing_map |

  # Calculate target sections (Reuse ID if exists, else deterministic)
  ($outputs | keys | map(
    . as $s | ("output-\($s)") as $l | { id: ($existing_map[$l] // "\($l)_section"), label: $l }
  )) as $targets |

  # Lookup for field assignment (Label -> ID)
  ($targets | map({(.label): .id}) | add) as $final_map |

  # Update item
  .fields = (
    # Keep fields not in any output-* section
    [.fields[]? | select(
      (.section.id // "") as $sid | ($existing_map | to_entries | map(select(.value == $sid)) | length == 0)
    )] +
    # Add new output fields
    [
      $outputs | to_entries[] | . as $server |
      $server.value | to_entries[] | select(.value != null and .value != "") | {
        label: (.key | sub("_sensitive$"; "")),
        section: { id: $final_map["output-\($server.key)"] },
        type: (if .key | endswith("_sensitive") then "CONCEALED" else "STRING" end),
        value: .value
      }
    ]
  ) |
  .sections = (
    ([.sections[]? | select((.label // "") | startswith("output-") | not)] +
    [$targets[] | select(
      (.label | ltrimstr("output-")) as $s | ($outputs[$s] | to_entries | map(select(.value != null and .value != "")) | length > 0)
    )]) | sort_by(.label)
  ) |
  .urls = ($urls | map({
    href: .href,
    label: .label,
    primary: (.primary // false)
  }))
' | op_put "/v1/vaults/$VAULT_ID/items/$ID"
