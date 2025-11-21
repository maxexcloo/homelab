#!/bin/bash
set -euo pipefail

# 1. Decode new data from environment variable
DATA="$(printf '%s' "$CONTENT" | base64 -d)"

# 2. Read previous state from stdin (if available)
# The shell_sensitive_script provider passes the existing state JSON here on 'read' or 'update'
PREVIOUS_DATA=""
if [ ! -t 0 ]; then
  PREVIOUS_DATA="$(cat || true)"
fi

# 3. Calculate hash of the data
HASH="$(printf '%s' "$DATA" | sha256sum | awk '{print $1}')"

# 4. Extract hash from previous data
PREVIOUS_HASH="$(printf '%s' "$PREVIOUS_DATA" | jq -r '.hash // ""' 2>/dev/null || true)"

# 5. SOPS encryption changes every time, if the content hasn't changed, return the old encrypted data to prevent diffs
if [ -n "$PREVIOUS_DATA" ] && [ "$PREVIOUS_HASH" = "$HASH" ]; then
  printf '%s' "$PREVIOUS_DATA"
  exit 0
fi

# 6. Encrypt (if content changed)
ENCRYPTED_CONTENT="$(printf '%s' "$DATA" | sops encrypt --age "$AGE_PUBLIC_KEY" --input-type yaml --output-type yaml /dev/stdin)"

# 7. Output JSON
jq -n --arg encrypted_content "$ENCRYPTED_CONTENT" --arg hash "$HASH" '{encrypted_content: $encrypted_content, hash: $hash}'
