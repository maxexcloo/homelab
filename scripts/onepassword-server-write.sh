#!/bin/bash
set -e

# Get current item structure
CURRENT_ITEM=$(op item get "$ID" --vault "$VAULT" --format json)

# Only update URLs and output section, preserve everything else
echo "$CURRENT_ITEM" | jq \
  --argjson outputsJson "$OUTPUTS_JSON" \
  --argjson urlsJson "$URLS_JSON" \
  '
  # Update URLs
  .urls = ($urlsJson | map(select(. != null) | {href: .})) |

  # Keep all existing fields except output section
  .fields = [
    # Keep all non-output fields as-is
    (.fields[] | select(.section.id != "output" and .section.label != "output")),

    # Add new output fields
    ($outputsJson | to_entries[] |
      if .key | endswith("_sensitive") then
        {
          label: (.key | rtrimstr("_sensitive")),
          section: {id: "output"},
          type: "CONCEALED",
          value: (.value // "")
        }
      else
        {
          label: .key,
          section: {id: "output"},
          type: "STRING",
          value: (.value // "")
        }
      end
    )
  ]
  ' | op item edit "$ID" --vault "$VAULT" -
