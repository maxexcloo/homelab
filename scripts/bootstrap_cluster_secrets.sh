#!/usr/bin/env bash
set -euo pipefail
umask 077

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <cluster>" >&2
  exit 1
fi

cluster="$1"

for tool in op jq kubectl; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "error: ${tool} is required but not found in PATH." >&2
    exit 1
  fi
done

echo "Injecting 1Password SDK bootstrap secret for cluster '${cluster}'..."

token="$(
  op item get --vault "Homelab" "Service Account Auth Token: ${cluster}-eso" --format json |
    jq -er 'first(.fields[] | select(.id == "credential" or .label == "credential" or .type == "CONCEALED")) | .value // empty'
)"

kubectl --context "${cluster}" create namespace external-secrets --dry-run=client -o yaml | kubectl --context "${cluster}" apply -f -

printf '%s' "${token}" |
  kubectl --context "${cluster}" -n external-secrets create secret generic onepassword-sdk \
    --from-file=token=/dev/stdin \
    --dry-run=client -o yaml |
  kubectl --context "${cluster}" apply -f -
unset token

echo "Successfully injected onepassword-sdk secret into cluster '${cluster}'."
