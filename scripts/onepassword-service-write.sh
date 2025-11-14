#!/bin/bash
set -e

# Get current item as JSON
ITEM_JSON=$(op item get "$ID" --vault "$VAULT" --format json)

# Get all existing output-* section IDs as a JSON object
OUTPUT_SECTIONS=$(echo "$ITEM_JSON" | jq -r '
  [.sections[]? | select((.label? // "") | startswith("output-")) | {label: .label, id: .id}] |
  map({(.label): .id}) | add // {}
')

# Update the item with new URLs and output fields
echo "$ITEM_JSON" | jq \
--argjson outputSections "$OUTPUT_SECTIONS" \
--argjson outputsJson "$OUTPUTS_JSON" \
--argjson urlsJson "$URLS_JSON" \
'
  .urls = (
    $urlsJson | map({
      href: .href,
      label: .label,
      primary: (.primary // false)
    })
  ) |
  .sections = (
    # Keep all non-output-* sections
    [.sections[]? | select((( .label? // "" ) | startswith("output-")) | not)] +
    # Add output-* sections for each server with non-empty outputs
    [
      $outputsJson | to_entries[] |
      .key as $server_name |
      select(.value | to_entries | map(select(.value != null and .value != "")) | length > 0) |
      (
        $outputSections["output-\($server_name)"] // "output_\($server_name)_section"
      ) as $sectionId |
      {
        "id": $sectionId,
        "label": "output-\($server_name)"
      }
    ]
  ) |
  .fields = (
    # Keep all existing fields that are NOT in output-* sections
    [.fields[]? | select(
      (.section.label? // "") | startswith("output-") | not
    )] +
    # Add new output-* fields from OUTPUTS_JSON (excluding null/empty values)
    [
      $outputsJson | to_entries | map(
        .key as $server_name |
        # Get section ID for this server
        ($outputSections["output-\($server_name)"] // "output_\($server_name)_section") as $sectionId |
        .value | to_entries[] |
        select(.value != null and .value != "") |
        if .key | endswith("_sensitive") then
          {
            "label": (.key | rtrimstr("_sensitive")),
            "section": {"id": $sectionId},
            "type": "CONCEALED",
            "value": .value
          }
        else
          {
            "label": .key,
            "section": {"id": $sectionId},
            "type": "STRING",
            "value": .value
          }
        end
      ) | .[]
    ]
  )
' | op item edit "$ID" --vault "$VAULT" -
