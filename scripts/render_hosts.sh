#!/usr/bin/env bash
# Renders Ignition for the machines with Butane provisioning in data/machines.yaml,
# or validates their Butane with --check.
set -euo pipefail
umask 077

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_directory="${1:?usage: render_hosts.sh OUTPUT_DIRECTORY [HOST...] | render_hosts.sh --check [HOST...]}"
shift

temporary_directory="$(mktemp -d)"
trap 'rm -rf -- "${temporary_directory}"' EXIT

# Keep each machine's network and derived hostname beside its provisioning.
machines_file="${temporary_directory}/machines.json"
# $network is a yq variable.
# shellcheck disable=SC2016
yq -o=json '[.machines | to_entries[] | .key as $network |
  .value | to_entries[] | select(.value.butane != null) |
  {"key": .key, "value": (.value + {
    "hostname": (.value.hostname // .key), "network": $network
  })}] | from_entries' "${repo_dir}/data/machines.yaml" >"${machines_file}"

names=("$@")
if ((${#names[@]} == 0)); then
  while IFS= read -r name; do
    names+=("${name}")
  done < <(jq -r 'keys[]' "${machines_file}")
fi

# Checks render without credentials; installable Ignition always gets a real
# password hash and the host's generated files.
hosts_file="${temporary_directory}/hosts.json"
password_hashes="${temporary_directory}/password-hashes"
mkdir -p "${password_hashes}"

if [[ "${output_directory}" == --check ]]; then
  printf '{}\n' >"${hosts_file}"
  for name in "${names[@]}"; do
    printf '%s\n' '!' >"${password_hashes}/${name}"
  done
else
  (cd "${repo_dir}" && fnox exec -- tofu output -json hosts) >"${hosts_file}"
  domain="$(yq -r '.domains.infrastructure' "${repo_dir}/data/domains.yaml")"
  vault="$(yq -r '.onepassword.vaults.homelab' "${repo_dir}/data/access.yaml")"
  openssl_command=openssl
  # macOS ships LibreSSL, whose passwd command cannot generate SHA-512 hashes.
  if [[ "$(uname -s)" == Darwin ]]; then
    openssl_command="$(brew --prefix openssl@3)/bin/openssl"
  fi
  for name in "${names[@]}"; do
    machine_access="$(jq -er --arg name "${name}" '.[$name] | [.network, .hostname, .type] | @tsv' "${machines_file}")"
    IFS=$'\t' read -r network hostname type <<<"${machine_access}"
    type_title="$(printf '%s' "${type}" | awk '{ print toupper(substr($0, 1, 1)) substr($0, 2) }')"
    title="${type_title}: ${hostname}.${network}.${domain}"
    if ! op item get "${title}" --vault "${vault}" --fields password --reveal |
      "${openssl_command}" passwd -6 -stdin >"${password_hashes}/${name}"; then
      printf 'Host %s: could not render its password; ensure %s exists and 1Password is unlocked\n' "${name}" "${title}" >&2
      exit 1
    fi
  done
  mkdir -p "${output_directory}"
fi

for name in "${names[@]}"; do
  config="${temporary_directory}/${name}.bu"
  printf 'base64encode(templatefile("%s/templates/hosts/host.bu.tftpl", { files = try(jsondecode(file("%s"))["%s"].files, {}), machine = jsondecode(file("%s"))["%s"], password_hash = trimspace(file("%s")), ssh_authorized_keys = yamldecode(file("%s/data/access.yaml")).ssh.authorized_keys }))\n' "${repo_dir}" "${hosts_file}" "${name}" "${machines_file}" "${name}" "${password_hashes}/${name}" "${repo_dir}" |
    TF_DATA_DIR="${temporary_directory}/.terraform" \
      tofu -chdir="${temporary_directory}" console |
    jq -r . |
    openssl base64 -d -A >"${config}"
  if [[ "${output_directory}" == --check ]]; then
    butane --files-dir "${repo_dir}" --strict "${config}" >/dev/null
  else
    butane --files-dir "${repo_dir}" --output "${output_directory}/${name}.ign" --pretty --strict "${config}"
  fi
done
