#!/bin/bash
set -e

# Build assignments for the 'output' section (handles _sensitive)
OUTPUT_ASSIGNMENTS=$(echo "$OUTPUTS_JSON" | jq -r '
  to_entries | .[] |
  .value |= (if . == null then "" else . end) |
  if .key | endswith("_sensitive") then
    "output.\(.key | rtrimstr("_sensitive"))[concealed]=\(.value)"
  else
    "output.\(.key)[text]=\(.value)"
  end
')

# Build assignments for the 'urls' array
URL_ASSIGNMENTS=$(echo "$URLS_JSON" | jq -r '
  to_entries | .[] |
  .value |= (if . == null then "" else . end) |
  "urls[\(.key)].href=\(.value)"
')

# Run ONE command with all assignments
op item edit "$ITEM_NAME" --vault "$ITEM_VAULT" $OUTPUT_ASSIGNMENTS $URL_ASSIGNMENTS
