#!/bin/bash
set -e

# Get current item as JSON
CURRENT_ITEM=$(op item get "$ID" --vault "$VAULT" --format json)

# Get existing output section ID, or use "output_section" as default for new sections
OUTPUT_SECTION_ID=$(echo "$CURRENT_ITEM" | jq -r '(.sections[]? | select(.label == "output") | .id) // "output_section"')

# Update the item with new URLs and output fields
echo "$CURRENT_ITEM" | jq \
--arg outputSectionId "$OUTPUT_SECTION_ID" \
--argjson outputsJson "$OUTPUTS_JSON" \
--argjson urlsJson "$URLS_JSON" \
'
  # Update URLs
  .urls = ($urlsJson | map(select(. != null) | {href: .})) |
  # Rebuild sections array: keep all non-output sections, then add the output section
  .sections = (
    [.sections[]? | select(.label != "output")] + 
    [{"id": $outputSectionId, "label": "output"}]
  ) |
  # Rebuild fields array
  .fields = (
    # Keep all existing fields that are NOT in the output section
    [.fields[]? | select(
      .section.label? != "output" and
      .section.id? != $outputSectionId
    )] +
    # Add new output fields from OUTPUTS_JSON (excluding null/empty values)
    [
      $outputsJson | to_entries[] | 
      select(.value != null and .value != "") |
      if .key | endswith("_sensitive") then
        {
          "label": (.key | rtrimstr("_sensitive")),
          "section": {"id": $outputSectionId},
          "type": "CONCEALED",
          "value": .value
        }
      else
        {
          "label": .key,
          "section": {"id": $outputSectionId},
          "type": "STRING",
          "value": .value
        }
      end
    ]
  )
' | op item edit "$ID" --vault "$VAULT" -
