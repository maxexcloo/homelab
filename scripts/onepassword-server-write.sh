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
  # Define target section (Find existing "output" or define new)
  ((.sections[]? | select(.label == "output")) // {id: "output_section", label: "output"}) as $target_section |
  $target_section.id as $target_id |

  # Update item
  .fields = (
    # Keep fields not in the output section
    [.fields[]? | select(.section.id != $target_id)] +
    # Add new output fields
    [
      $outputs | to_entries[] | select(.value != null and .value != "") | {
        label: (.key | sub("_sensitive$"; "")),
        section: { id: $target_id },
        type: (if .key | endswith("_sensitive") then "CONCEALED" else "STRING" end),
        value: .value
      }
    ]
  ) |
  .sections = (
    ([.sections[]? | select(.label != "output")] + [$target_section]) | sort_by(.label)
  ) |
  .urls = ($urls | map({
    href: .href,
    label: .label,
    primary: (.primary // false)
  }))
' | op_put "/v1/vaults/$VAULT_ID/items/$ID"
