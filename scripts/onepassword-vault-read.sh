#!/bin/bash
set -e

VAULT_NAME="$1"
CACHE_FILE=".terraform.cache.${VAULT_NAME}.json"
CACHE_MINS=5

# --- CACHE HIT: Just print the file's contents and exit --
if find . -maxdepth 1 -mmin "-$CACHE_MINS" -name "$CACHE_FILE" | grep -q .; then
  cat "$CACHE_FILE"
  exit 0
fi

# --- CACHE MISS: Run the full, slow script ---
if [ -z "$VAULT_NAME" ]; then
  echo "Error: Vault name not provided." >&2
  exit 1
fi

ITEM_TITLES=$(op item list --vault "$VAULT_NAME" --format json | \
              jq -r '.[] | .title' | \
              grep -E '^[a-z0-9]+-[a-z0-9]+(?:-[a-z0-9-]+)?$' || true)

OUTPUT_JSON="{}"

while IFS= read -r ITEM_TITLE; do
  # If the title is empty (from an empty vault), skip the loop.
  if [ -z "$ITEM_TITLE" ]; then
    continue
  fi

  # Get the item's JSON
  ITEM_JSON=$(op item get "$ITEM_TITLE" --format json --vault "$VAULT_NAME")

  # Run our parsing query
  PARSED_ITEM_STRING=$(echo "$ITEM_JSON" | jq -r '
    (
      {id: .id, title: .title}
      + {username: ( .fields[] | select(.purpose == "USERNAME") | .value ) // ""}
      + {password: ( .fields[] | select(.purpose == "PASSWORD") | .value ) // ""}
      + {input: ( .fields | map(select(.section.id == "add more")) | map({(.label): (if .value == "" or .value == "-" then null else .value end)}) | add ) // {} }
      + {urls: [.urls[]?.href] | map(select(. != null))}
      + {tags: .tags // []}
    ) | tojson
  ')

  # We now pass this *string* as the value for our map.
  OUTPUT_JSON=$(echo "$OUTPUT_JSON" | jq --arg key "$ITEM_TITLE" --arg value "$PARSED_ITEM_STRING" '. + {($key): $value}')
done <<< "$ITEM_TITLES"

# --- Write to cache AND print to stdout ---
echo "$OUTPUT_JSON" > "$CACHE_FILE"
echo "$OUTPUT_JSON"
