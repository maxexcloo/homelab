#!/bin/bash
set -eo pipefail

# Helpers
function op_get() {
  curl -f -s -H "Authorization: Bearer $CONNECT_TOKEN" -H "Content-Type: application/json" "$CONNECT_HOST$1"
}

# 1. Set variables
eval "$(jq -r '@sh "CONNECT_HOST=\(.connect_host) CONNECT_TOKEN=\(.connect_token) VAULT=\(.vault)"')"
OUTPUT_JSON="{}"

# 2. Resolve vault ID
VAULT_ID=$(op_get "/v1/vaults" | jq -r --arg v "$VAULT" '.[] | select(.name == $v or .id == $v) | .id')

# 3. Validate vault
if [ -z "$VAULT_ID" ]; then
  echo "Error: Vault '$VAULT' not found." >&2
  exit 1
fi

# 4. List all items in the vault & filter based on regex
ITEM_IDS=$(op_get "/v1/vaults/$VAULT_ID/items" | jq -r '.[] | select(.title | test("^[a-z0-9]+-[a-z0-9]+(?:-[a-z0-9-]+)?$")) | .id')

# 5. Loop and fetch full details for each item
for ID in $ITEM_IDS; do
  # Get full item details
  ITEM_JSON=$(op_get "/v1/vaults/$VAULT_ID/items/$ID")
  ITEM_TITLE=$(echo "$ITEM_JSON" | jq -r '.title')

  # Run the parsing query
  ITEM_PARSED=$(echo "$ITEM_JSON" | jq -r '
    (
      {id: .id, title: .title}
      + {username: (.fields[]? | select(.purpose == "USERNAME") | .value // "")}
      + {password: (.fields[]? | select(.purpose == "PASSWORD") | .value // "")}
      + {urls: [.urls[]?.href] | map(select(. != null))}
      + {input: ([.fields[]? | select(.section.id == "add more") | {(.label): (if .value == "" or .value == "-" then null else .value end)}] | add // {})}
      + {tags: .tags // []}
    ) | tojson
  ')

  # Append item to output map
  OUTPUT_JSON=$(echo "$OUTPUT_JSON" | jq --arg key "$ITEM_TITLE" --arg value "$ITEM_PARSED" '. + {($key): $value}')
done

# 6. Print output map to stdout
echo "$OUTPUT_JSON"
