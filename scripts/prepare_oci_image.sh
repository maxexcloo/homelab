#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="${1:-}"
cache_dir="${XDG_CACHE_HOME:-${HOME}/.cache}/homelab"

if [[ "${target}" =~ ^https?:// ]]; then
  image_url="${target}"
else
  if ! image_url="$(tofu -chdir="${repo_dir}" output -json clusters |
    jq -er --arg cluster "${target}" '
      if $cluster == "" then [.[].disk_image_url // empty][0]
      else .[$cluster].disk_image_url end
      | select(. != null and . != "")
    ')"; then
    echo "error: no cluster image URL available; pass an Image Factory URL instead." >&2
    exit 1
  fi
fi

# Image Factory supplies QCOW2 directly; older state may still contain a raw URL.
case "${image_url%%[?#]*}" in
  https://factory.talos.dev/*.raw.xz) image_url="${image_url/.raw.xz/.qcow2}" ;;
  https://factory.talos.dev/*.raw.gz) image_url="${image_url/.raw.gz/.qcow2}" ;;
esac

archive_name="$(basename "${image_url%%[?#]*}")"
case "${archive_name}" in
  *.qcow2) image_name="${archive_name}" ;;
  *.raw.gz) image_name="${archive_name%.raw.gz}.qcow2" ;;
  *.raw.xz) image_name="${archive_name%.raw.xz}.qcow2" ;;
  *) echo "error: unsupported image archive: ${archive_name}" >&2; exit 1 ;;
esac
image_path="${cache_dir}/${image_name}"
mkdir -p "${cache_dir}"
work_dir="$(mktemp -d "${cache_dir}/prepare.XXXXXX")"
trap 'rm -rf -- "${work_dir}"' EXIT
curl --fail --location --retry 3 --output "${work_dir}/download" "${image_url}"
case "${archive_name}" in
  *.qcow2) mv "${work_dir}/download" "${work_dir}/image.qcow2" ;;
  *)
    case "${archive_name}" in
      *.gz) gzip -dc "${work_dir}/download" >"${work_dir}/image.raw" ;;
      *.xz) xz -dc "${work_dir}/download" >"${work_dir}/image.raw" ;;
    esac
    qemu-img convert -f raw -O qcow2 "${work_dir}/image.raw" "${work_dir}/image.qcow2"
    ;;
esac
mv "${work_dir}/image.qcow2" "${image_path}"
printf 'Prepared %s\nExport before planning the upload:\n  export TF_VAR_oci_talos_image_path="%s"\n' "${image_path}" "${image_path}"
