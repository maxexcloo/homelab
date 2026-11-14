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

inventory_file="${temporary_directory}/inventory.json"
"${repo_dir}/scripts/read_inventory.sh" |
  jq '.machines |= with_entries(select(.value.butane != null))' >"${inventory_file}"

names=("$@")
if ((${#names[@]} == 0)); then
  mapfile -t names < <(jq -r '.machines | keys[]' "${inventory_file}")
fi

# Checks render without credentials; installable Ignition always gets a real
# password hash and the host's generated files.
hosts_file="${temporary_directory}/hosts.json"
if [[ "${output_directory}" == --check ]]; then
  printf '{}\n' >"${hosts_file}"
else
  (cd "${repo_dir}" && fnox exec -- tofu output -json hosts) >"${hosts_file}"
  vault="$(jq -er '.access.onepassword.vaults.homelab' "${inventory_file}")"
  openssl_command=openssl
  # macOS ships LibreSSL, whose passwd command cannot generate SHA-512 hashes.
  if [[ "$(uname -s)" == Darwin ]]; then
    openssl_command="$(brew --prefix openssl@3)/bin/openssl"
  fi
  mkdir -p "${output_directory}"
fi

for name in "${names[@]}"; do
  password_hash="${temporary_directory}/${name}.password-hash"
  if [[ "${output_directory}" == --check ]]; then
    printf '%s\n' '!' >"${password_hash}"
  else
    title="$(jq -er --arg name "${name}" '.machines[$name].login_title' "${inventory_file}")"
    if ! op item get "${title}" --vault "${vault}" --fields password --reveal |
      "${openssl_command}" passwd -6 -stdin >"${password_hash}"; then
      printf 'Host %s: could not render its password; ensure %s exists and 1Password is unlocked\n' "${name}" "${title}" >&2
      exit 1
    fi
  fi

  variables="${temporary_directory}/${name}.json"
  jq --arg name "${name}" --rawfile password_hash "${password_hash}" --slurpfile hosts "${hosts_file}" \
    '{ files: ($hosts[0][$name].files // {}), machine: .machines[$name], password_hash: ($password_hash | rtrimstr("\n")), ssh_authorized_keys: .access.ssh.authorized_keys }' \
    "${inventory_file}" >"${variables}"
  config="${temporary_directory}/${name}.bu"
  # Base64 carries the rendered YAML through the console's HCL string output intact.
  printf 'base64encode(templatefile("%s/templates/hosts/host.bu.tftpl", jsondecode(file("%s"))))\n' "${repo_dir}" "${variables}" |
    TF_DATA_DIR="${temporary_directory}/.terraform" tofu -chdir="${temporary_directory}" console |
    jq -r . |
    openssl base64 -d -A >"${config}"
  if [[ "${output_directory}" == --check ]]; then
    butane --files-dir "${repo_dir}" --strict "${config}" >/dev/null
  else
    butane --files-dir "${repo_dir}" --output "${output_directory}/${name}.ign" --pretty --strict "${config}"
  fi
done
