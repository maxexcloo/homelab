#!/usr/bin/env bash
set -euo pipefail

machines_path="${1:-data/machines.yaml}"
access_path="${2:-data/access.yaml}"
domains_path="${3:-data/domains.yaml}"
identity_agent="$(yq -r '.ssh.identity_agent' "${access_path}")"
infrastructure_domain="$(yq -r '.domains.infrastructure' "${domains_path}")"

while IFS=$'\t' read -r alias location address user port; do
  fqdn="${alias}.${location}.${infrastructure_domain}"
  printf 'Host %s %s\n' "${alias}" "${fqdn}"
  printf '  HostName %s\n' "${address}"
  printf '  User %s\n' "${user}"
  printf '  Port %s\n' "${port}"
  printf '  IdentityAgent "%s"\n\n' "${identity_agent}"
done < <(
  yq -r '
    .machines
    | to_entries
    | .[]
    | select(.value.ssh != null)
    | [.key, .value.location, (.value.address // .value.public_ipv4), .value.ssh.user, .value.ssh.port]
    | @tsv
  ' "${machines_path}"
)
