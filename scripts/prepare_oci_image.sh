#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="${1:-}"
cache_dir="${XDG_CACHE_HOME:-${HOME}/.cache}/homelab"

if [[ "${target}" =~ ^https?:// ]]; then
  image_url="${target}"
else
  if ! image_url="$(tofu -chdir="${repo_dir}" output -json clusters |
    jq --arg cluster "${target}" -er '
      if $cluster == "" then [.[].disk_image_url // empty][0]
      else .[$cluster].disk_image_url end
      | select(. != null and . != "")
    ')"; then
    echo "error: no cluster image URL available; pass an Image Factory URL instead." >&2
    exit 1
  fi
fi

read -r image_hash _ < <(printf '%s' "${image_url}" | shasum -a 256)
image_directory="${cache_dir}/images/${image_hash}"
image_path="${image_directory}/$(basename "${image_url%%[?#]*}")"
mkdir -p "${image_directory}"
curl --fail --location --output "${image_path}.part" --retry 3 "${image_url}"
mv "${image_path}.part" "${image_path}"
printf 'Prepared %s\nExport before planning the upload:\n  export TF_VAR_oci_talos_image_path="%s"\n' "${image_path}" "${image_path}"
