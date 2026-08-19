#!/usr/bin/env bash
set -euo pipefail

clusters_path="data/clusters.yaml"
kubeconfig_dest="${HOME}/.kube/config"
talosconfig_dest="${HOME}/.talos/config"

for tool in op jq kubectl talosctl yq; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "error: ${tool} is required but not found in PATH." >&2
    exit 1
  fi
done

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

mkdir -p "${HOME}/.kube" "${HOME}/.talos"

if [[ -f "${kubeconfig_dest}" ]]; then
  cp "${kubeconfig_dest}" "${kubeconfig_dest}.bak"
fi

if [[ -f "${talosconfig_dest}" ]]; then
  cp "${talosconfig_dest}" "${talosconfig_dest}.bak"
fi

get_note() {
  local vault="$1"
  local item="$2"
  local dest="$3"

  local content
  if content="$(op item get --vault "${vault}" "${item}" --format json 2>/dev/null | jq -re '.fields[] | select(.id == "notesPlain") | .value // empty')"; then
    if [[ -n "${content}" ]]; then
      printf '%s\n' "${content}" >"${dest}"
      return 0
    fi
  fi
  return 1
}

kubeconfig_paths=()
first_talos=true

echo "Fetching credentials from 1Password..."

while IFS= read -r cluster; do
  vault="Cluster: ${cluster}"
  kube_file="${tmpdir}/${cluster}.kubeconfig"
  talos_file="${tmpdir}/${cluster}.talosconfig"

  echo "  - Fetching ${cluster} from vault '${vault}'..."

  if get_note "${vault}" kubeconfig "${kube_file}"; then
    kubeconfig_paths+=("${kube_file}")
  else
    echo "    (warning: no kubeconfig found for cluster ${cluster})" >&2
  fi

  if get_note "${vault}" talosconfig "${talos_file}"; then
    if [[ "${first_talos}" == true ]]; then
      cp "${talos_file}" "${talosconfig_dest}"
      first_talos=false
    else
      talosctl --talosconfig "${talosconfig_dest}" config merge "${talos_file}"
    fi
  else
    echo "    (warning: no talosconfig found for cluster ${cluster})" >&2
  fi
done < <(yq -r '.clusters | to_entries | .[] | select(.value.talos_enabled == true) | .key' "${clusters_path}")

if [[ ${#kubeconfig_paths[@]} -gt 0 ]]; then
  KUBECONFIG="$(IFS=:; echo "${kubeconfig_paths[*]}")" kubectl config view --flatten >"${kubeconfig_dest}"
  chmod 600 "${kubeconfig_dest}"

  for ctx in $(kubectl config get-contexts -o name); do
    for cluster in $(yq -r '.clusters | keys | .[]' "${clusters_path}"); do
      if [[ "${ctx}" == *"${cluster}"* ]] && [[ "${ctx}" != "${cluster}" ]]; then
        kubectl config rename-context "${ctx}" "${cluster}" >/dev/null 2>&1 || true
      fi
    done
  done
  echo "Updated ${kubeconfig_dest}"
fi

if [[ "${first_talos}" == false ]]; then
  chmod 600 "${talosconfig_dest}"
  echo "Updated ${talosconfig_dest}"
fi

echo
echo "Available kubectl contexts:"
kubectl config get-contexts -o name
echo
echo "Available talosctl contexts:"
talosctl config contexts
