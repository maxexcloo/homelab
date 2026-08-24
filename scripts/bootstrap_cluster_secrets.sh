#!/usr/bin/env bash
set -euo pipefail
umask 077

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <cluster>" >&2
  exit 1
fi

cluster="$1"
repository_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

for tool in jq kubectl op yq; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "error: ${tool} is required but not found in PATH." >&2
    exit 1
  fi
done

credentials_file="$(mktemp)"
trap 'rm -f "${credentials_file}"' EXIT
bootstrap_vault="$(yq -er '.onepassword.vaults.homelab' "${repository_dir}/data/access.yaml")"

echo "Injecting 1Password Connect bootstrap secret for cluster '${cluster}'..."

env -u OP_CONNECT_HOST -u OP_CONNECT_TOKEN \
  op document get --vault "${bootstrap_vault}" "Connect Credentials: ${cluster}" --out-file "${credentials_file}" --force >/dev/null
jq -e 'type == "object"' "${credentials_file}" >/dev/null

kubectl --context "${cluster}" create namespace external-secrets --dry-run=client -o yaml | kubectl --context "${cluster}" apply -f -

env -u OP_CONNECT_HOST -u OP_CONNECT_TOKEN \
  op item get --vault "${bootstrap_vault}" "Connect Token: ${cluster}" --format json |
  jq -er 'first(.fields[] | select(.id == "credential")) | .value // empty' |
  kubectl --context "${cluster}" -n external-secrets create secret generic onepassword-connect \
    --from-file=1password-credentials.json="${credentials_file}" \
    --from-file=token=/dev/stdin \
    --dry-run=client -o yaml |
  kubectl --context "${cluster}" apply -f -

echo "Successfully injected onepassword-connect secret into cluster '${cluster}'."
