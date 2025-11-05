#!/bin/bash
set -e

# Get current item structure
CURRENT_ITEM=$(op item get "$ID" --vault "$VAULT" --format json)

# Get all existing output-* section IDs
OUTPUT_SECTIONS=$(echo "$CURRENT_ITEM" | jq -r '
  [.sections[]? | select(.label | startswith("output-")) | {label: .label, id: .id}] |
  map({(.label): .id}) | add // {}
')

# Only update URLs and output sections, preserve everything else
echo "$CURRENT_ITEM" | jq \
--argjson outputSections "$OUTPUT_SECTIONS" \
--argjson outputsJson "$OUTPUTS_JSON" \
--argjson urlsJson "$URLS_JSON" \
'
    # 1. Update URLs
    .urls = ($urlsJson | map(select(. != null) | {href: .})) |
    # 2. Handle sections - rebuild to avoid duplicates
    .sections = (
      # Keep all non-output sections
      [.sections[]? | select(.label | startswith("output-") | not)] +
      # Add output-* sections for servers with non-empty outputs
      [
        $outputsJson | to_entries[] |
        .key as $server_name |
        select(.value | to_entries | map(select(.value != null and .value != "")) | length > 0) |
        if $outputSections["output-\($server_name)"] then
          {
            "id": $outputSections["output-\($server_name)"],
            "label": "output-\($server_name)"
          }
        else
          {"label": "output-\($server_name)"}
        end
      ]
    ) |
    # 3. Re-build the .fields array
    .fields = (
      # List 1: All fields that are NOT "output-*"
      [
        .fields[]? | select(.section.label? // "" | startswith("output-") | not)
      ]
      +
      # List 2: All the new "output-*" fields (excluding null/empty values)
      [
        $outputsJson | to_entries | map(
          .key as $server_name |
          .value | to_entries[] |
          select(.value != null and .value != "") |
          if .key | endswith("_sensitive") then
            {
              "label": (.key | rtrimstr("_sensitive")),
              "section": (
                if $outputSections["output-\($server_name)"] then
                  {
                    "id": $outputSections["output-\($server_name)"],
                    "label": "output-\($server_name)"
                  }
                else
                  {"label": "output-\($server_name)"}
                end
              ),
              "type": "CONCEALED",
              "value": .value
            }
          else
            {
              "label": .key,
              "section": (
                if $outputSections["output-\($server_name)"] then
                  {
                    "id": $outputSections["output-\($server_name)"],
                    "label": "output-\($server_name)"
                  }
                else
                  {"label": "output-\($server_name)"}
                end
              ),
              "type": "STRING",
              "value": .value
            }
          end
        ) | .[]
      ]
    )
  ' | op item edit "$ID" --vault "$VAULT" -
