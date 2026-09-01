#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_directory="$(dirname -- "${script_directory}")"
output_directory="${1:-${XDG_CACHE_HOME:-${HOME}/.cache}/homelab/ignition}"

shopt -s nullglob
configs=("${repository_directory}"/hosts/*/*.bu)

if ((${#configs[@]} == 0)); then
  printf 'No Butane configurations found.\n' >&2
  exit 1
fi

temporary_directory="$(mktemp -d)"
trap 'rm -rf -- "${temporary_directory}"' EXIT

mkdir -p -- "${output_directory}"

for config in "${configs[@]}"; do
  host="$(basename -- "${config}" .bu)"
  output="${output_directory}/${host}.ign"

  butane \
    --files-dir "${repository_directory}/hosts" \
    --output "${temporary_directory}/${host}.ign" \
    --pretty \
    --strict \
    "${config}"
  install -m 0644 "${temporary_directory}/${host}.ign" "${output}"
  printf 'Rendered %s\n' "${output}"
done
