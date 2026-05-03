#!/bin/bash
set -euo pipefail

DATA="$(printf '%s' "$CONTENT" | base64 -d)"

PREVIOUS_DATA=""
if [ ! -t 0 ]; then
  PREVIOUS_DATA="$(cat || true)"
fi

HASH="$(printf '%s' "$DATA" | sha256sum | awk '{print $1}')"
PREVIOUS_HASH="$(printf '%s' "$PREVIOUS_DATA" | jq -r '.hash // ""' 2>/dev/null || true)"

if [ -n "${DEBUG_PATH:-}" ]; then
  mkdir -p "$(dirname "${DEBUG_PATH}")"
  printf '%s' "$DATA" > "${DEBUG_PATH}"
fi

if [ -n "$PREVIOUS_DATA" ] && [ "$PREVIOUS_HASH" = "$HASH" ]; then
  printf '%s' "$PREVIOUS_DATA"
  exit 0
fi

INPUT_TYPE="$CONTENT_TYPE"
OUTPUT_TYPE="$CONTENT_TYPE"
if [ "$CONTENT_TYPE" = "binary" ]; then
  # Binary input is wrapped in JSON so the shell provider can return a normal
  # object while preserving the encrypted payload exactly.
  OUTPUT_TYPE="json"
fi

SOPS_ARGS=(encrypt --age "$AGE_PUBLIC_KEY" --input-type "$INPUT_TYPE" --output-type "$OUTPUT_TYPE")
if [ -n "${FILENAME:-}" ]; then
  SOPS_ARGS+=(--filename-override "$FILENAME")
fi

ENCRYPTED_CONTENT="$(printf '%s' "$DATA" | sops "${SOPS_ARGS[@]}" /dev/stdin)"

jq -n --arg encrypted_content "$ENCRYPTED_CONTENT" --arg hash "$HASH" '{encrypted_content: $encrypted_content, hash: $hash}'
