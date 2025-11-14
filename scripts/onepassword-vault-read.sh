#!/bin/bash
set -eo pipefail

# Get raw JSON from 1Password
OP_OUTPUT=$(op item list --vault "$1" --format json)
ITEMS=$(echo "$OP_OUTPUT" | \
        jq -r '.[] | .title' | \
        grep -E '^[a-z0-9]+-[a-z0-9]+(?:-[a-z0-9-]+)?$' || true)

# Prepare output map
OUTPUT_JSON="{}"

# Loop over vault items
while IFS= read -r ITEM; do
  # If the title is empty (from an empty vault), skip the loop.
  if [ -z "$ITEM" ]; then
    continue
  fi

  # Get the item's JSON
  ITEM_JSON=$(op item get "$ITEM" --format json --vault "$1")

  # Run our parsing query
  ITEM_STRING=$(echo "$ITEM_JSON" | jq -r '
    (
      {id: .id, title: .title}
      + {username: ( .fields[] | select(.purpose == "USERNAME") | .value ) // ""}
      + {password: ( .fields[] | select(.purpose == "PASSWORD") | .value ) // ""}
      + {urls: [.urls[]?.href] | map(select(. != null))}
      + {input: (
          .fields
          | map(select(.section.id == "add more"))
          | map({
              (.label): (if .value == "" or .value == "-" then null else .value end)
            })
          | add
        ) // {} }
      + {tags: .tags // []}
    ) | tojson
  ')

  # We now pass this *string* as the value for our map.
  OUTPUT_JSON=$(echo "$OUTPUT_JSON" | jq --arg key "$ITEM" --arg value "$ITEM_STRING" '. + {($key): $value}')
done <<< "$ITEMS"

# Print output map to stdout
echo "$OUTPUT_JSON"
