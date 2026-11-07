#!/usr/bin/env bash
# Renders Butane configs from data/hosts.yaml and templates/hosts/host.bu.tftpl.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
check=false
cleanup=()

if [[ "${1:-}" == "--check" ]]; then
  check=true
  output_directory="$(mktemp -d)"
  cleanup+=("${output_directory}")
  shift
else
  output_directory="${1:?usage: render_hosts.sh OUTPUT_DIRECTORY [HOST...] | render_hosts.sh --check}"
  shift
fi

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

mkdir -p "${output_directory}"
for name in "${names[@]}"; do
  printf 'base64encode(templatefile("templates/hosts/host.bu.tftpl", yamldecode(file("data/hosts.yaml")).hosts["%s"]))\n' "${name}" |
    TF_DATA_DIR="${temporary_directory}/.terraform" \
      tofu -chdir="${temporary_directory}" console |
    jq -r . |
    openssl base64 -d -A >"${output_directory}/${name}.bu"
done

if "${check}"; then
  for config in "${output_directory}"/*.bu; do
    butane --files-dir "${repo_dir}" --strict "${config}" >/dev/null
  done
fi
