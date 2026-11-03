#!/usr/bin/env bash
set -euo pipefail

output_path="${1:-}"
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
access_path="${repo_dir}/data/access.yaml"
domains_path="${repo_dir}/data/domains.yaml"
machines_path="${repo_dir}/data/machines.yaml"

identity_agent="$(yq -er '.ssh.identity_agent' "${access_path}")"
infrastructure_domain="$(yq -er '.domains.infrastructure' "${domains_path}")"

# $network is a yq variable.
# shellcheck disable=SC2016
machine_entries="$(yq -r '
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
' "${machines_path}")"

render() {
  while IFS=$'\t' read -r hostname network user; do
    [[ -n "${hostname}" ]] || continue
    fqdn="${hostname}.${network}.${infrastructure_domain}"
    network_hostname="${network}-${hostname}"
    printf 'Host %s %s %s\n' "${hostname}" "${network_hostname}" "${fqdn}"
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
