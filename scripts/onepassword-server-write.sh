#!/bin/bash
set -e

# Get current item structure
CURRENT_ITEM=$(op item get "$ID" --vault "$VAULT" --format json)

# Only update URLs and output section, preserve everything else
echo "$CURRENT_ITEM" | jq \
  --argjson outputsJson "$OUTPUTS_JSON" \
  --argjson urlsJson "$URLS_JSON" \
  '
    # 1. Update URLs
    .urls = ($urlsJson | map(select(. != null) | {href: .})) |
    # 2. Re-build the .fields array by concatenating two lists
    .fields = (
      # List 1: All fields that are NOT "output"
      [
        .fields[] | select(.section.label? // "" != "output")
      ]
      +
      # List 2: All the new "output" fields
      [
        $outputsJson | to_entries[] |
          if .key | endswith("_sensitive") then
            {
              "label": (.key | rtrimstr("_sensitive")),
              "section": { "label": "output" },
              "type": "CONCEALED",
              "value": (.value // "")
            }
          else
            {
              "label": .key,
              "section": { "label": "output" },
              "type": "STRING",
              "value": (.value // "")
            }
          end
      ]
    )
  ' | op item edit "$ID" --vault "$VAULT" -
