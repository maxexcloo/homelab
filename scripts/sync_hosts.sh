#!/usr/bin/env bash
# Syncs every host's generated files from the `hosts` output and its Butane
# trees, or those of the hosts named as arguments.
set -euo pipefail

# Runs as root on the host from the uploaded staging directory.
install_files() {
  local changed=false path unit
  local username="" uid=""
  local -a user_units=()
  local -A system_changed=() user_changed=()

  cd "$(dirname "${BASH_SOURCE[0]}")"
  if [[ -s user ]]; then
    IFS=$'\t' read -r username uid <user
  fi

  cd root
  while IFS= read -r path; do
    path="${path#.}"
    if ! cmp -s ".${path}" "${path}" || [[ "$(stat -c %a ".${path}")" != "$(stat -c %a "${path}")" ]]; then
      echo "Changed ${path}"
      install -D -Z -m "$(stat -c %a ".${path}")" ".${path}" "${path}"
      changed=true
      case "${path}" in
        /etc/cloudflared/config.yml | /etc/cloudflared/credentials.json)
          if [[ -f /etc/systemd/system/cloudflared.service ]]; then
            system_changed[cloudflared.service]=1
          fi
          ;;
        /etc/systemd/user/*.service) user_changed["${path##*/}"]=1 ;;
        /etc/containers/systemd/users/"${uid}"/*.container) user_changed["$(basename "${path}" .container).service"]=1 ;;
        /etc/homelab/proxy/agent-browser.json) user_changed[browserless.service]=1 ;;
        /etc/homelab/proxy/dsh-tls.sh) user_changed[dsh.service]=1 ;;
        /etc/homelab/proxy/fnox.toml)
          user_changed[traefik.service]=1
          if [[ -f "etc/systemd/system/syncthing@${username}.service.d/authentication.conf" ]]; then
            system_changed["syncthing@${username}.service"]=1
          fi
          ;;
        /etc/homelab/proxy/syncthing-auth.sh | /etc/systemd/system/syncthing@*.service.d/authentication.conf)
          system_changed["syncthing@${username}.service"]=1
          ;;
        /etc/homelab/proxy/*) user_changed[traefik.service]=1 ;;
      esac
    fi
  done < <(find . -type f)

  if [[ "${changed}" == true ]]; then
    systemctl daemon-reload
    if ((${#system_changed[@]})); then
      systemctl restart "${!system_changed[@]}"
    fi
  else
    echo "Files up to date"
  fi

  if [[ -n "${username}" ]]; then
    chcon -R -t container_file_t /etc/homelab/proxy/traefik
    as_user systemctl --user daemon-reload
    if [[ -d etc/systemd/user ]]; then
      while IFS= read -r path; do
        unit="${path##*/}"
        as_user systemctl --user enable "${unit}"
        user_units+=("${unit}")
      done < <(find etc/systemd/user -maxdepth 1 -name '*.service')
    fi
    while IFS= read -r path; do
      user_units+=("$(basename "${path}" .container).service")
    done < <(find "etc/containers/systemd/users/${uid}" -maxdepth 1 -name '*.container')
    if ((${#user_changed[@]})); then
      as_user systemctl --user try-restart "${!user_changed[@]}"
    fi
    if ((${#user_units[@]})); then
      as_user systemctl --user start "${user_units[@]}"
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
