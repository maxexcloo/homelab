#!/usr/bin/env bash
set -euo pipefail

output_path="${1:-}"
machines_path="data/machines.yaml"
access_path="data/access.yaml"
domains_path="data/domains.yaml"
identity_agent="$(yq -r '.ssh.identity_agent' "${access_path}")"
infrastructure_domain="$(yq -r '.domains.infrastructure' "${domains_path}")"

render() {
  while IFS=$'\t' read -r alias network address user port; do
    fqdn="${alias}.${network}.${infrastructure_domain}"
    printf 'Host %s %s\n' "${alias}" "${fqdn}"
    printf '  HostName %s\n' "${address}"
    printf '  User %s\n' "${user}"
    printf '  Port %s\n' "${port}"
    printf '  IdentityAgent "%s"\n\n' "${identity_agent}"
  done < <(
    yq -r '
      .machines
      | to_entries
      | sort_by(.key)
      | .[]
      | select(.value.ssh != null)
      | [.key, .value.network, (.value.address // .value.public_ipv4), .value.ssh.user, .value.ssh.port]
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
