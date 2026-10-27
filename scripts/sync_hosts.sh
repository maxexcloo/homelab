#!/usr/bin/env bash
# Syncs every host, or the hosts named as arguments. Each host gets its Butane
# trees and its generated files from the `hosts` output, then installs them as
# root by running this script with --install after one sudo prompt.
set -euo pipefail

# Runs on the host from the uploaded staging directory. Installs changed files,
# removes files an earlier sync installed that are no longer staged, and
# restarts the units those changes affect.
install_files() {
  local manifest=/var/lib/homelab-sync/files
  local quadlets=/etc/containers/systemd
  local affected=() changed network path restart=() running=() service unit

  cd "$(dirname "${BASH_SOURCE[0]}")/root"
  find . -type f | sed 's/^\.//' | sort >../files
  mkdir -p "$(dirname "${manifest}")"
  touch "${manifest}"

  changed="$(
    while read -r path; do
      if ! cmp -s ".${path}" "${path}" || [[ "$(stat -c %a ".${path}")" != "$(stat -c %a "${path}")" ]]; then
        echo "${path}"
      fi
    done <../files
    comm -23 "${manifest}" ../files
  )"
  if [[ -z "${changed}" ]]; then
    echo "Up to date"
    return
  fi

  # A container restarts when its unit or any file it names changes.
  for unit in $(printf '%s\n' "${quadlets}"/*.container ".${quadlets}"/*.container | sed 's/^\.//' | sort -u); do
    for path in ${changed}; do
      if [[ "${path}" == "${unit}" ]] || grep -qsF -e "${path}" -e "=$(basename "${path}")" ".${unit}" "${unit}"; then
        service="$(basename "${unit}" .container).service"
        affected+=("${service}")
        [[ ! -f "${unit}" ]] || running+=("${service}")
        break
      fi
    done
  done

  for path in ${changed}; do
    echo "Changed ${path}"
    case "${path}" in
      /etc/systemd/system/*.service | /etc/systemd/system/*.timer)
        [[ -f ".${path}" ]] || systemctl disable --now "$(basename "${path}")" || true
        ;;
    esac
  done

  # Podman keeps an existing network, so changed networks are recreated once
  # their containers stop.
  ((${#running[@]} == 0)) || systemctl stop "${running[@]}"
  for path in ${changed}; do
    if [[ "${path}" == "${quadlets}"/*.network && -f "${path}" ]]; then
      network="$(sed -n 's/^NetworkName=//p' "${path}")"
      ! podman network exists "${network}" || podman network rm "${network}"
    fi
  done

  for path in ${changed}; do
    if [[ -f ".${path}" ]]; then
      install -D -Z -m "$(stat -c %a ".${path}")" ".${path}" "${path}"
    else
      rm -f "${path}"
    fi
  done
  cp ../files "${manifest}"
  systemctl daemon-reload

  for path in ${changed}; do
    [[ -f "${path}" ]] || continue
    case "${path}" in
      "${quadlets}"/*.network) systemctl restart "$(basename "${path}" .network)-network.service" ;;
      /etc/systemd/system/*.service | /etc/systemd/system/*.timer) systemctl try-restart "$(basename "${path}")" ;;
    esac
  done
  # One transaction lets systemd order each container after the units it needs.
  for service in "${affected[@]}"; do
    [[ ! -f "${quadlets}/${service%.service}.container" ]] || restart+=("${service}")
  done
  ((${#restart[@]} == 0)) || systemctl restart "${restart[@]}"
}

if [[ "${1:-}" == "--install" ]]; then
  install_files
  exit
fi

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hosts_json="$(fnox exec -- tofu output -json hosts)"
staging_root="$(mktemp -d)"
trap 'rm -rf -- "${staging_root}"' EXIT

if (($# == 0)); then
  names="$(jq -r 'keys[]' <<<"${hosts_json}")"
  # Host names contain no whitespace.
  # shellcheck disable=SC2086
  set -- ${names}
fi

skipped=()
for name in "$@"; do
  address="$(jq -er --arg name "${name}" '.[$name].address' <<<"${hosts_json}")"
  staging="${staging_root}/${name}"
  mkdir -p "${staging}/root"
  cp "${BASH_SOURCE[0]}" "${staging}/sync_hosts.sh"

  butane_config="${repo_dir}/hosts/${name}/${name}.bu"
  if [[ -f "${butane_config}" ]]; then
    while IFS=$'\t' read -r tree path; do
      mkdir -p "${staging}/root${path}"
      cp -Rp "${repo_dir}/hosts/${tree}/." "${staging}/root${path}/"
    done < <(yq -r '.storage.trees[] | [.local, .path] | @tsv' "${butane_config}")
  fi

  while IFS=$'\t' read -r path mode; do
    mkdir -p "$(dirname "${staging}/root${path}")"
    jq -j --arg name "${name}" --arg path "${path}" '.[$name].files[$path].content' <<<"${hosts_json}" >"${staging}/root${path}"
    chmod "${mode}" "${staging}/root${path}"
  done < <(jq -r --arg name "${name}" '.[$name].files | to_entries[] | [.key, .value.mode] | @tsv' <<<"${hosts_json}")

  echo "Syncing ${name}" >&2
  if ! tar --no-mac-metadata --no-xattrs -C "${staging}" -cf - . |
    ssh -o ConnectTimeout=5 "${address}" 'rm -rf .cache/homelab-sync && mkdir -p -m 700 .cache/homelab-sync && tar -xpf - -C .cache/homelab-sync'; then
    skipped+=("${name}")
    continue
  fi
  ssh -t "${address}" 'sudo bash .cache/homelab-sync/sync_hosts.sh --install; status=$?; rm -rf .cache/homelab-sync; exit "${status}"'
done

if ((${#skipped[@]} > 0)); then
  echo "Not synced: ${skipped[*]}" >&2
  exit 1
fi
