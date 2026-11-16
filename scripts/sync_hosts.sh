#!/usr/bin/env bash
# Syncs every host's generated files from the `hosts` output and its Butane
# trees, or those of the hosts named as arguments.
set -euo pipefail

# Runs as root on the host from the uploaded staging directory.
install_files() {
  local changed=false cloudflared_changed=false proxy_restart=false syncthing_changed=false dsh_changed=false browserless_changed=false path
  local username="" uid=""

  cd "$(dirname "${BASH_SOURCE[0]}")"
  if [[ -s user ]]; then
    IFS=$'\t' read -r username uid <user
    jq empty root/etc/homelab/proxy/traefik/traefik.json
  fi

  cd root
  while IFS= read -r path; do
    path="${path#.}"
    if ! cmp -s ".${path}" "${path}" || [[ "$(stat -c %a ".${path}")" != "$(stat -c %a "${path}")" ]]; then
      echo "Changed ${path}"
      install -D -Z -m "$(stat -c %a ".${path}")" ".${path}" "${path}"
      changed=true
      case "${path}" in
        /etc/cloudflared/config.yml | /etc/cloudflared/credentials.json) cloudflared_changed=true ;;
        /etc/homelab/proxy/browserless.json | /etc/homelab/proxy/prepare_browserless.py | /etc/containers/systemd/users/*/browserless.container) browserless_changed=true ;;
        /etc/homelab/proxy/dsh-tls.sh) dsh_changed=true ;;
        /etc/homelab/proxy/* | /etc/containers/systemd/users/*/traefik.container) proxy_restart=true ;;
        /etc/systemd/system/syncthing@*.service.d/authentication.conf) syncthing_changed=true ;;
        /etc/systemd/user/dsh.service) dsh_changed=true ;;
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

  if [[ -n "${username}" ]]; then
    chcon -R -t container_file_t /etc/homelab/proxy/traefik
    as_user systemctl --user daemon-reload
    if [[ "${syncthing_changed}" == true ]]; then
      systemctl restart "syncthing@${username}.service"
    fi
    if [[ -f etc/systemd/user/dsh.service ]]; then
      if [[ "${dsh_changed}" == true ]] && as_user systemctl --user is-active --quiet dsh.service; then
        as_user systemctl --user restart dsh.service
      fi
      as_user systemctl --user enable --now dsh.service
    fi
    if [[ -f "etc/containers/systemd/users/${uid}/browserless.container" ]]; then
      if [[ "${browserless_changed}" == true ]] && as_user systemctl --user is-active --quiet browserless.service; then
        as_user systemctl --user restart browserless.service
      else
        as_user systemctl --user start browserless.service
      fi
    fi
    if [[ "${proxy_restart}" == true ]] && as_user systemctl --user is-active --quiet traefik.service; then
      as_user systemctl --user restart traefik.service
    else
      as_user systemctl --user start traefik.service
    fi
  fi

  while IFS=$'\t' read -r unit enabled; do
    if [[ "${enabled}" == true ]]; then
      systemctl enable --now "${unit}"
    else
      systemctl disable --now "${unit}"
    fi
  done <../units
}

as_user() {
  runuser -u "${username}" -- env HOME="/var/home/${username}" XDG_RUNTIME_DIR="/run/user/${uid}" \
    PATH="/var/home/${username}/.local/share/mise/shims:/usr/local/bin:/usr/bin" "$@"
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
  jq -r --arg name "${name}" '.machines[$name] | select(any(.services[]; has("upstream"))) | [.username, .uid] | @tsv' <<<"${inventory_json}" >"${staging}/user"

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
  if ! COPYFILE_DISABLE=1 tar --no-xattrs -C "${staging}" -cf - . |
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
