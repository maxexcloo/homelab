#!/usr/bin/env bash
set -euo pipefail

output_path="${1:-}"
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
inventory="$("${repo_dir}/scripts/read_inventory.sh")"
identity_agent="$(jq -er '.access.ssh.identity_agent' <<<"${inventory}")"
machine_entries="$(jq -r '
  .machines | to_entries | map(select(.value.username != null)) |
  sort_by(.value.network, .value.hostname) | .[] | .value |
  [.hostname, .network, .username, .fqdn] | @tsv
' <<<"${inventory}")"

render() {
  while IFS=$'\t' read -r hostname network user fqdn; do
    [[ -n "${hostname}" ]] || continue
    network_hostname="${network}-${hostname}"
    # Only the network name is a Host pattern, so tools that list Host entries show one target per machine.
    printf 'Host %s\n' "${network_hostname}"
    printf 'Match originalhost %s,%s,%s\n' "${network_hostname}" "${hostname}" "${fqdn}"
    printf '  HostName %s\n' "${fqdn}"
    printf '  User %s\n' "${user}"
    printf '  IdentityAgent "%s"\n\n' "${identity_agent}"
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
