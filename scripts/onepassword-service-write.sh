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
    # --- Built-in Username/Password/Notes ---
    [
      {
        "label": "username",
        "value": $username,
        "purpose": "USERNAME",
        "type": "STRING"
      },
      {
        "label": "password",
        "value": $password,
        "purpose": "PASSWORD",
        "type": "CONCEALED"
      },
      {
        "label": "notesPlain",
        "value": $notes,
        "purpose": "NOTES",
        "type": "STRING"
      }
    ] +
    
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

    # --- "output-SERVERNAME" sections ---
    (
      $outputsJson | to_entries | map(
        .key as $server_name | "output-\($server_name)" as $section_label |
        .value | to_entries | map(
          .value |= (if . == null then "" else . end) |
          if .key | endswith("_sensitive") then
            {
              "section": { "label": $section_label },
              "label": (.key | rtrimstr("_sensitive")),
              "value": .value,
              "type": "CONCEALED"
            }
          else
            {
              "section": { "label": $section_label },
              "label": .key,
              "value": .value,
              "type": "STRING"
            }
          end
        )
      ) | flatten
    )
    as $fieldsTemplate |

    # 3. Combine into the final template object
    {
      "urls": $urlsTemplate,
      "fields": $fieldsTemplate
    }
  ' | op item edit "$ID" --vault "$VAULT" -
