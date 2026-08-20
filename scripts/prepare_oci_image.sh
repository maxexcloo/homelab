#!/usr/bin/env bash
set -euo pipefail

cache_dir="${XDG_CACHE_HOME:-${HOME}/.cache}/homelab"
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="${1:-}"

require_tools() {
  local tool
  for tool in "$@"; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
      echo "error: ${tool} is required but not found in PATH." >&2
      exit 1
    fi
  done
}

resolve_image_url() {
  local cluster="${1:-}"

  if [[ -n "${cluster}" ]]; then
    tofu -chdir="${repo_dir}" output -json clusters 2>/dev/null |
      jq -r --arg cluster "${cluster}" '.[$cluster].disk_image_url // empty'
  else
    tofu -chdir="${repo_dir}" output -json clusters 2>/dev/null |
      jq -r '[.[].disk_image_url // empty][0] // empty'
  fi
}

require_tools curl

if [[ "${target}" =~ ^https?:// ]]; then
  image_url="${target}"
else
  require_tools jq tofu
  if ! image_url="$(resolve_image_url "${target}")"; then
    echo "error: unable to read cluster outputs." >&2
    exit 1
  fi
fi

if [[ -z "${image_url}" ]] || [[ "${image_url}" == "null" ]]; then
  echo "error: no disk_image_url found in cluster outputs." >&2
  echo "Apply the schematic stage first, or pass the disk image URL as an argument." >&2
  exit 1
fi

mkdir -p "${cache_dir}"
work_dir="$(mktemp -d "${cache_dir}/prepare.XXXXXX")"
trap 'rm -rf -- "${work_dir}"' EXIT

archive_name="$(basename "${image_url%%[?#]*}")"
archive_path="${work_dir}/${archive_name}"

case "${archive_name}" in
  *.qcow2)
    image_name="${archive_name}"
    ;;
  *.raw.gz)
    decompressor=(gzip -dc)
    image_name="${archive_name%.raw.gz}.qcow2"
    require_tools gzip qemu-img
    ;;
  *.raw.xz)
    decompressor=(xz -dc)
    image_name="${archive_name%.raw.xz}.qcow2"
    require_tools qemu-img xz
    ;;
  *)
    echo "error: unsupported image archive: ${archive_name}" >&2
    exit 1
    ;;
esac

image_path="${cache_dir}/${image_name}"

echo "Downloading ${archive_name}"
curl -fL --retry 3 -o "${archive_path}" "${image_url}"

if [[ "${archive_name}" == *.qcow2 ]]; then
  mv "${archive_path}" "${image_path}"
else
  raw_path="${work_dir}/${archive_name%.*}"

  echo "Decompressing ${archive_name}"
  "${decompressor[@]}" "${archive_path}" >"${raw_path}"

  echo "Converting to ${image_name}"
  qemu-img convert -f raw -O qcow2 "${raw_path}" "${work_dir}/${image_name}"
  mv "${work_dir}/${image_name}" "${image_path}"
fi

echo
echo "Prepared ${image_path}"
echo "Export the path before planning the upload stage:"
echo "  export TF_VAR_oci_talos_image_path=\"${image_path}\""
