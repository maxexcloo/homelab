#!/usr/bin/env bash
# Renders the machines with Butane provisioning in data/machines.yaml.
set -euo pipefail
umask 077

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cleanup=()
mode=render

case "${1:-}" in
  --check)
    mode=check
    output_directory="$(mktemp -d)"
    cleanup+=("${output_directory}")
    shift
    ;;
  --ignition | --sync)
    mode="${1#--}"
    output_directory="${2:?usage: render_hosts.sh [--ignition | --sync] OUTPUT_DIRECTORY [HOST...]}"
    shift 2
    ;;
  *)
    output_directory="${1:?usage: render_hosts.sh [--ignition | --sync] OUTPUT_DIRECTORY [HOST...] | render_hosts.sh --check [HOST...]}"
    shift
    ;;
esac

temporary_directory="$(mktemp -d)"
cleanup+=("${temporary_directory}")
trap 'rm -rf -- "${cleanup[@]}"' EXIT

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

# Only checks and file sync can render without credentials; installable Butane
# and Ignition always get a real password hash.
password_hashes="${temporary_directory}/password-hashes"
mkdir -p "${password_hashes}"

domain="$(yq -r '.domains.infrastructure' "${repo_dir}/data/domains.yaml")"
vault="$(yq -r '.onepassword.vaults.homelab' "${repo_dir}/data/access.yaml")"
openssl_command=openssl
# macOS ships LibreSSL, whose passwd command cannot generate SHA-512 hashes.
if [[ "${mode}" != check && "${mode}" != sync && "$(uname -s)" == Darwin ]]; then
  openssl_command="$(brew --prefix openssl@3)/bin/openssl"
fi

for name in "${names[@]}"; do
  if [[ "${mode}" == check || "${mode}" == sync ]]; then
    # These configs are only validated or read for file paths, never installed.
    printf '%s\n' '!' >"${password_hashes}/${name}"
    continue
  fi
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

# Checks and ignition output work on temporary configs; callers that only want
# the Butane configs get them in their own directory.
bu_directory="${output_directory}"
if [[ "${mode}" == check || "${mode}" == ignition ]]; then
  bu_directory="${temporary_directory}/butane"
fi

mkdir -p "${bu_directory}"
for name in "${names[@]}"; do
  printf 'base64encode(templatefile("%s/templates/hosts/host.bu.tftpl", { machine = jsondecode(file("%s"))["%s"], password_hash = trimspace(file("%s")), ssh_authorized_keys = yamldecode(file("%s/data/access.yaml")).ssh.authorized_keys }))\n' "${repo_dir}" "${machines_file}" "${name}" "${password_hashes}/${name}" "${repo_dir}" |
    TF_DATA_DIR="${temporary_directory}/.terraform" \
      tofu -chdir="${temporary_directory}" console |
    jq -r . |
    openssl base64 -d -A >"${bu_directory}/${name}.bu"
done

case "${mode}" in
  check)
    for config in "${bu_directory}"/*.bu; do
      butane --files-dir "${repo_dir}" --strict "${config}" >/dev/null
    done
    ;;
  ignition)
    mkdir -p "${output_directory}"
    for config in "${bu_directory}"/*.bu; do
      butane --files-dir "${repo_dir}" \
        --output "${output_directory}/$(basename "${config}" .bu).ign" \
        --pretty --strict "${config}"
    done
    ;;
esac
