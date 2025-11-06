#!/bin/bash
set -e

# Get current item as JSON
ITEM_JSON=$(op item get "$ID" --vault "$VAULT" --format json)

# Get existing output section ID, or use "output_section" as default for new sections
OUTPUT_SECTION_ID=$(echo "$ITEM_JSON" | jq -r '(.sections[]? | select(.label == "output") | .id) // "output_section"')

# Update the item with new URLs and output fields
echo "$ITEM_JSON" | jq \
--arg outputSectionId "$OUTPUT_SECTION_ID" \
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
    [.sections[]? | select(.label != "output")] +
    [{"id": $outputSectionId, "label": "output"}]
  ) |
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
