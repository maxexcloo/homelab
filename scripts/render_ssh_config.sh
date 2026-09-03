#!/usr/bin/env bash
set -euo pipefail

output_path="${1:-}"
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
access_path="${repo_dir}/data/access.yaml"
domains_path="${repo_dir}/data/domains.yaml"
machines_path="${repo_dir}/data/machines.yaml"

if ! command -v yq >/dev/null 2>&1; then
  echo "error: yq is required but not found in PATH." >&2
  exit 1
fi

identity_agent="$(yq -r '.ssh.identity_agent' "${access_path}")"
infrastructure_domain="$(yq -r '.domains.infrastructure' "${domains_path}")"

render() {
  while IFS=$'\t' read -r hostname network user; do
    fqdn="${hostname}.${network}.${infrastructure_domain}"
    network_hostname="${network}-${hostname}"
    printf 'Host %s %s\n' "${network_hostname}" "${fqdn}"
    printf '  HostName %s\n' "${fqdn}"
    printf '  User %s\n' "${user}"
    printf '  IdentityAgent "%s"\n\n' "${identity_agent}"
  done < <(
    # $network is a yq variable.
    # shellcheck disable=SC2016
    yq -r '
      [
        .machines
        | to_entries[]
        | .key as $network
        | .value
        | to_entries[]
        | select(.value.username != null)
        | {
            "hostname": (.value.hostname // .key),
            "network": $network,
            "username": .value.username
          }
      ]
      | sort_by(.network, .hostname)
      | .[]
      | [.hostname, .network, .username]
      | @tsv
    ' "${machines_path}"
  )
}

if [[ -n "${output_path}" ]]; then
  mkdir -p "$(dirname "${output_path}")"
  render >"${output_path}"
  chmod 600 "${output_path}"
  echo "Installed ${output_path}"
else
  render
fi
