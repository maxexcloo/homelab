#!/usr/bin/env bash
# Renders Butane configs from data/hosts.yaml and templates/hosts/host.bu.tftpl.
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

ln -s "${repo_dir}/data" "${temporary_directory}/data"
ln -s "${repo_dir}/templates" "${temporary_directory}/templates"

TF_DATA_DIR="${temporary_directory}/.terraform" \
  tofu -chdir="${temporary_directory}" init -backend=false -input=false >/dev/null

names=("$@")
if ((${#names[@]} == 0)); then
  while IFS= read -r name; do
    names+=("${name}")
  done < <(yq -r '.hosts | keys[]' "${repo_dir}/data/hosts.yaml")
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
  network="$(yq -r ".machines | to_entries[] | select(.value | has(\"${name}\")) | .key" "${repo_dir}/data/machines.yaml")"
  hostname="$(yq -r ".machines[\"${network}\"][\"${name}\"].hostname // \"${name}\"" "${repo_dir}/data/machines.yaml")"
  type="$(yq -e -r ".machines[\"${network}\"][\"${name}\"].type" "${repo_dir}/data/machines.yaml")"
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
  printf 'base64encode(templatefile("templates/hosts/host.bu.tftpl", merge(yamldecode(file("data/hosts.yaml")).hosts["%s"], { password_hash = trimspace(file("%s")) })))\n' "${name}" "${password_hashes}/${name}" |
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
