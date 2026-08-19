#!/usr/bin/env bash
set -euo pipefail

cache_dir="${XDG_CACHE_HOME:-${HOME}/.cache}/homelab"
target="${1:-}"

if [[ "${target}" =~ ^https?:// ]]; then
  image_url="${target}"
elif [[ -n "${target}" ]]; then
  image_url="$(tofu output -json 2>/dev/null | jq -r --arg cluster "${target}" '.clusters.value[$cluster].disk_image_url // empty')"
else
  image_url="$(tofu output -json 2>/dev/null | jq -r '[.clusters.value[].disk_image_url // empty][0] // empty')"
fi

if [[ -z "${image_url}" ]] || [[ "${image_url}" == "null" ]]; then
  echo "error: no disk_image_url found in cluster outputs." >&2
  echo "Apply the schematic stage first, or pass the disk image URL as an argument." >&2
  exit 1
fi

mkdir -p "${cache_dir}"
archive_name="$(basename "${image_url}")"
image_name="${archive_name%.*}.qcow2"
image_path="${cache_dir}/${image_name}"

if [[ "${archive_name}" == *.qcow2 ]]; then
  echo "Downloading ${archive_name}"
  curl -fL --retry 3 -o "${image_path}" "${image_url}"
else
  if ! command -v qemu-img >/dev/null 2>&1; then
    echo "error: qemu-img is required but was not found in PATH (brew install qemu)." >&2
    exit 1
  fi

  archive_path="${cache_dir}/${archive_name}"
  raw_path="${cache_dir}/${archive_name%.*}"

  echo "Downloading ${archive_name}"
  curl -fL --retry 3 -o "${archive_path}" "${image_url}"

  echo "Decompressing ${archive_name}"
  gzip -dc "${archive_path}" >"${raw_path}"

  echo "Converting to ${image_name}"
  qemu-img convert -f raw -O qcow2 "${raw_path}" "${image_path}"
  rm "${raw_path}" "${archive_path}"
fi

echo
echo "Prepared ${image_path}"
echo "Export the path before planning the upload stage:"
echo "  export TF_VAR_oci_talos_image_path=\"${image_path}\""
