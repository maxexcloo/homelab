#!/usr/bin/env bash
set -euo pipefail

output_path="${1:-}"
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
inventory="$("${repo_dir}/scripts/read_inventory.sh")"
machine_entries="$(jq -r '
  .machines | to_entries | map(select(.value.username != null)) |
  map(.value | .alias = if .type == null then .hostname else "\(.network)-\(.hostname)" end) |
  sort_by(.type == null, .alias) | .[] |
  [.alias, ([.alias, .hostname, .fqdn] | unique | join(",")), .username, .fqdn] | @tsv
' <<<"${inventory}")"

render() {
  while IFS=$'\t' read -r alias names user fqdn; do
    [[ -n "${alias}" ]] || continue
    # Only the alias is a Host pattern, so tools that list Host entries show one target per machine.
    printf 'Host %s\n' "${alias}"
    printf 'Match originalhost %s\n' "${names}"
    printf '  HostName %s\n' "${fqdn}"
    printf '  User %s\n\n' "${user}"
  done <<<"${machine_entries}"
}

if [[ -n "${output_path}" ]]; then
  mkdir -p "$(dirname "${output_path}")"
  temporary_path="$(mktemp "${output_path}.XXXXXX")"
  trap 'rm -f -- "${temporary_path}"' EXIT
  render >"${temporary_path}"
  chmod 600 "${temporary_path}"
  mv -f -- "${temporary_path}" "${output_path}"
  echo "Installed ${output_path}"
else
  render
fi
