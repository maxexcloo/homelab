#!/usr/bin/env bash
set -euo pipefail
umask 077

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
clusters_path="${repo_dir}/data/clusters.yaml"
kubeconfig_dest="${HOME}/.kube/config"
talosconfig_dest="${HOME}/.talos/config"

for tool in jq kubectl op talosctl yq; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "error: ${tool} is required but not found in PATH." >&2
    exit 1
  fi
done

tmpdir="$(mktemp -d)"
trap 'rm -rf -- "${tmpdir}"' EXIT

mkdir -p "${HOME}/.kube" "${HOME}/.talos"
chmod 700 "${HOME}/.kube" "${HOME}/.talos"

install_config() {
  local source="$1"
  local destination="$2"

  if [[ -f "${destination}" ]]; then
    install -m 600 "${destination}" "${destination}.bak"
  fi
  install -m 600 "${source}" "${destination}"
}

get_note() {
  op item get --vault "$1" "$2" --format json 2>/dev/null |
    jq -er 'first(.fields[] | select(.id == "notesPlain")) | .value | select(length > 0)' >"$3"
}

clusters=()
kubeconfig_paths=()
talosconfig_path=""

while IFS= read -r cluster; do
  clusters+=("${cluster}")
done < <(yq -r '.clusters | to_entries | sort_by(.key) | .[] | select(.value.talos_enabled == true) | .key' "${clusters_path}")

echo "Fetching credentials from 1Password..."

for cluster in "${clusters[@]}"; do
  vault="Cluster: ${cluster}"
  kube_file="${tmpdir}/${cluster}.kubeconfig"
  talos_file="${tmpdir}/${cluster}.talosconfig"

  echo "  - Fetching ${cluster} from vault '${vault}'..."

  if get_note "${vault}" "Kubernetes Client Configuration" "${kube_file}"; then
    context="$(kubectl --kubeconfig "${kube_file}" config current-context)"
    if [[ "${context}" != "${cluster}" ]]; then
      kubectl --kubeconfig "${kube_file}" config rename-context "${context}" "${cluster}" >/dev/null
    fi
    kubeconfig_paths+=("${kube_file}")
  else
    echo "    (warning: no kubeconfig found for cluster ${cluster})" >&2
  fi

  if get_note "${vault}" "Talos Client Configuration" "${talos_file}"; then
    if [[ -z "${talosconfig_path}" ]]; then
      talosconfig_path="${tmpdir}/talosconfig"
      if [[ -f "${talosconfig_dest}" ]]; then
        cp "${talosconfig_dest}" "${talosconfig_path}"
        TALOSCONFIG_SOURCE="${talos_file}" yq -i '.contexts *= load(strenv(TALOSCONFIG_SOURCE)).contexts' "${talosconfig_path}"
      else
        cp "${talos_file}" "${talosconfig_path}"
      fi
    else
      TALOSCONFIG_SOURCE="${talos_file}" yq -i '.contexts *= load(strenv(TALOSCONFIG_SOURCE)).contexts' "${talosconfig_path}"
    fi
  else
    echo "    (warning: no talosconfig found for cluster ${cluster})" >&2
  fi
done

if [[ ${#kubeconfig_paths[@]} -gt 0 ]]; then
  kubeconfig_path="${tmpdir}/kubeconfig"
  kubeconfig_merge_paths=("${kubeconfig_paths[@]}")
  if [[ -f "${kubeconfig_dest}" ]]; then
    kubeconfig_merge_paths+=("${kubeconfig_dest}")
  fi
  KUBECONFIG="$(IFS=:; printf '%s' "${kubeconfig_merge_paths[*]}")" kubectl config view --flatten >"${kubeconfig_path}"
  install_config "${kubeconfig_path}" "${kubeconfig_dest}"
  echo "Updated ${kubeconfig_dest}"
fi

if [[ -n "${talosconfig_path}" ]]; then
  install_config "${talosconfig_path}" "${talosconfig_dest}"
  echo "Updated ${talosconfig_dest}"
fi

if [[ -f "${kubeconfig_dest}" ]]; then
  echo
  echo "Available kubectl contexts:"
  kubectl --kubeconfig "${kubeconfig_dest}" config get-contexts -o name
fi

if [[ -f "${talosconfig_dest}" ]]; then
  echo
  echo "Available talosctl contexts:"
  talosctl --talosconfig "${talosconfig_dest}" config contexts
fi
