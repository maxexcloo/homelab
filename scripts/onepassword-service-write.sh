#!/bin/bash
set -e

# Get current item structure
CURRENT_ITEM=$(op item get "$ID" --vault "$VAULT" --format json)

# Only update URLs and output sections, preserve everything else
echo "$CURRENT_ITEM" | jq \
  --argjson outputsJson "$OUTPUTS_JSON" \
  --argjson urlsJson "$URLS_JSON" \
  '
  # Update URLs
  .urls = ($urlsJson | map(select(. != null) | {href: .})) |
  
  # Keep all existing fields except output sections
  .fields = [
    # Keep all fields that aren't output sections
    (.fields[] | select(.section.label // "" | startswith("output-") | not)),
    
    # Add new output sections (one per server)
    ($outputsJson | to_entries | map(
      .key as $server_name | 
      .value | to_entries[] |
      if .key | endswith("_sensitive") then
        {
          label: (.key | rtrimstr("_sensitive")),
          section: {id: "output-\($server_name)"},
          type: "CONCEALED",
          value: (.value // "")
        }
      else
        {
          label: .key,
          section: {id: "output-\($server_name)"},
          type: "STRING",
          value: (.value // "")
        }
      end
    )[])
  ]
  ' | op item edit "$ID" --vault "$VAULT" -
