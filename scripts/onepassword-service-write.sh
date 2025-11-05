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
    # Build the "fields" array (all sections)
    (
      # --- Built-in Username/Password/Notes ---
      [
        {
          "label": "username",
          "purpose": "USERNAME",
          "type": "STRING",
          "value": $username
        },
        {
          "label": "password",
          "purpose": "PASSWORD",
          "type": "CONCEALED",
          "value": $password
        },
        {
          "label": "notesPlain",
          "purpose": "NOTES",
          "type": "STRING",
          "value": $notes
        }
      ] +
      
      # --- "input" section ("add more") ---
      (
        $inputsJson | to_entries | map(
          .value.value |= (if . == null then "" else . end) |
          {
            "label": .key,
            "section": { "label": "add more" },
            "type": .value.type,
            "value": .value.value
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
                "label": (.key | rtrimstr("_sensitive")),
                "section": { "label": $section_label },
                "type": "CONCEALED",
                "value": .value
              }
            else
              {
                "label": .key,
                "section": { "label": $section_label },
                "type": "STRING",
                "value": .value
              }
            end
          )
        ) | flatten
      )
    )
    as $fieldsTemplate |

    # Build the "urls" array
    (
      $urlsJson | map(select(. != null) | {href: .})
    ) as $urlsTemplate |

    # Combine into the final template object
    {
      "fields": $fieldsTemplate,
      "urls": $urlsTemplate
    }
  ' | op item edit "$ID" --vault "$VAULT" -
