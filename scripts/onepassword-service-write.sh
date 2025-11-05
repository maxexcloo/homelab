#!/bin/bash
set -e

# Build assignments for the PER-SERVER output sections
OUTPUT_ASSIGNMENTS=$(echo "$OUTPUTS_JSON" | jq -r '
  to_entries | .[] |
  .key as $server_name | "output-\($server_name)" as $section_name |
  .value | to_entries | .[] |
  .value |= (if . == null then "" else . end) |
  if .key | endswith("_sensitive") then
    "\($section_name).\(.key | rtrimstr("_sensitive"))[concealed]=\(.value)"
  else
    "\($section_name).\(.key)[text]=\(.value)"
  end
')

# Build assignments for the 'urls' array
URL_ASSIGNMENTS=$(echo "$URLS_JSON" | jq -r '
  to_entries | .[] |
  .value |= (if . == null then "" else . end) |
  "urls.\(.key)\\.href=\(.value)"
')

# Run ONE command with all assignments
op item edit "$ITEM_NAME" --vault "$ITEM_VAULT" $OUTPUT_ASSIGNMENTS $URL_ASSIGNMENTS
