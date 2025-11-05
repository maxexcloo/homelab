#!/bin/bash
set -e

# This script builds a *complete* JSON template and pipes it to 'op item edit -'
# It uses ID to be robust against name changes.
jq -n \
  --arg notes "$NOTES" \
  --arg password "$PASSWORD" \
  --arg username "$USERNAME" \
  --argjson inputsJson "$INPUTS_JSON" \
  --argjson outputsJson "$OUTPUTS_JSON" \
  --argjson urlsJson "$URLS_JSON" \
  '
    # 1. Build the "urls" array
    (
      $urlsJson | map(select(. != null) | {href: .})
    ) as $urlsTemplate |

    # 2. Build the "fields" array (all sections)
    # --- Conditionally add built-in fields *only if they have a value* ---
    (
      []
      | if $username != "" then . + [{
          "label": "username",
          "value": $username,
          "purpose": "USERNAME",
          "type": "STRING"
        }] else . end
      | if $password != "" then . + [{
          "label": "password",
          "value": $password,
          "purpose": "PASSWORD",
          "type": "CONCEALED"
        }] else . end
      | if $notes != "" then . + [{
          "label": "notesPlain",
          "value": $notes,
          "purpose": "NOTES",
          "type": "STRING"
        }] else . end
    ) +
    
    # --- "add more" (input) section ---
    (
      $inputsJson | to_entries | map(
        .value.value |= (if . == null then "" else . end) | # Handle nulls
        {
          "section": { "label": "add more" },
          "label": .key,
          "value": .value.value,
          "type": .value.type
        }
      )
    ) +

    # --- "output" section ---
    (
      $outputsJson | to_entries | map(
        .value |= (if . == null then "" else . end) |
        if .key | endswith("_sensitive") then
          {
            "section": { "label": "output" },
            "label": (.key | rtrimstr("_sensitive")),
            "value": .value,
            "type": "CONCEALED"
          }
        else
          {
            "section": { "label": "output" },
            "label": .key,
            "value": .value,
            "type": "STRING"
          }
        end
      )
    )
    as $fieldsTemplate |

    # 3. Combine into the final template object
    {
      "urls": $urlsTemplate,
      "fields": $fieldsTemplate
    }
  ' | op item edit "$ID" --vault "$VAULT" -
