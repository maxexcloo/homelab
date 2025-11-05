#!/bin/bash
set -e

op item get "$ITEM_NAME" --format json --vault "$ITEM_VAULT" | \
jq -r '
  {
    output: ( .fields | map(select(.section.label == "output")) | map({(.label): .value}) | add ) // {},
    urls: ( .urls | map({(tostring): .href}) | add ) // {}
  }
'
