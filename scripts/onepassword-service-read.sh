#!/bin/bash
set -e

op item get "$ITEM_NAME" --vault "$ITEM_VAULT" --format json | \
jq -r '
  {
    output: (
      .fields
      | map(select(.section.id != null and (.section.label | startswith("output-"))))
      | group_by(.section.label)
      | map({
          (.[0].section.label): (
            map({(.label): .value}) | add
          )
        })
      | if length > 0 then add else {} end
      | with_entries( .key |= ltrimstr("output-") )
    ) // {},
    urls: ( [.urls[].href] | map(select(. != null)) ) // []
  }
'
