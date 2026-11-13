#!/usr/bin/env bash
# Syncs every host's generated files from the `hosts` output and its Butane
# trees, or those of the hosts named as arguments.
set -euo pipefail

# Runs as root on the host from the uploaded staging directory.
install_files() {
  local changed=false cloudflared_changed=false path

  cd "$(dirname "${BASH_SOURCE[0]}")/root"
  while IFS= read -r path; do
    path="${path#.}"
    if ! cmp -s ".${path}" "${path}" || [[ "$(stat -c %a ".${path}")" != "$(stat -c %a "${path}")" ]]; then
      echo "Changed ${path}"
      install -D -Z -m "$(stat -c %a ".${path}")" ".${path}" "${path}"
      changed=true
      case "${path}" in
        /etc/cloudflared/config.yml | /etc/cloudflared/credentials.json) cloudflared_changed=true ;;
      esac
    fi
  done < <(find . -type f)

  if [[ "${changed}" == true ]]; then
    systemctl daemon-reload
    if [[ "${cloudflared_changed}" == true && -f /etc/systemd/system/cloudflared.service ]]; then
      systemctl restart cloudflared.service
    fi
  else
    echo "Files up to date"
  fi

  while IFS=$'\t' read -r unit enabled; do
    if [[ "${enabled}" == true ]]; then
      systemctl enable --now "${unit}"
    else
      systemctl disable --now "${unit}"
    fi
  done <../units
}

if [[ "${1:-}" == "--install" ]]; then
  install_files
  exit
fi

hosts_json="$(fnox exec -- tofu output -json hosts)"
inventory_json="$(scripts/read_inventory.sh)"
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
  jq -r --arg name "${name}" '.machines[$name].butane.units[]? | [.name, .enabled] | @tsv' <<<"${inventory_json}" >"${staging}/units"

  while IFS=$'\t' read -r path mode; do
    mkdir -p "$(dirname "${staging}/root${path}")"
    jq -j --arg name "${name}" --arg path "${path}" '.[$name].files[$path].content' <<<"${hosts_json}" >"${staging}/root${path}"
    chmod "${mode}" "${staging}/root${path}"
  done < <(jq -r --arg name "${name}" '.[$name].files | to_entries[] | [.key, .value.mode] | @tsv' <<<"${hosts_json}")

  while IFS=$'\t' read -r source path; do
    mkdir -p "${staging}/root${path}"
    cp -R "${source}/." "${staging}/root${path}/"
  done < <(jq -r --arg name "${name}" '.machines[$name].butane.trees[]? | [.local, .path] | @tsv' <<<"${inventory_json}")

  echo "Syncing ${name}" >&2
  if ! tar --no-mac-metadata --no-xattrs -C "${staging}" -cf - . |
    ssh -o ConnectTimeout=5 "${address}" 'rm -rf .cache/homelab-sync && mkdir -p -m 700 .cache/homelab-sync && tar -xpf - -C .cache/homelab-sync'; then
    skipped+=("${name}")
    continue
  fi
  # Runs through bash, as login shells may be fish.
  ssh -t "${address}" bash -c "'sudo bash .cache/homelab-sync/sync_hosts.sh --install; status=\$?; rm -rf .cache/homelab-sync; exit \$status'"
done

if ((${#skipped[@]} > 0)); then
  echo "Not synced: ${skipped[*]}" >&2
  exit 1
fi
