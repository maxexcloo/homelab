#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_directory="${1:?usage: render_cluster_settings.sh OUTPUT_DIRECTORY}"
clusters="$(jq -r '.clusters | keys[]' "${repo_dir}/inventory.json")"
if [[ -z "${clusters}" ]]; then
  exit 0
fi

while IFS= read -r cluster; do
  settings="$(jq --arg cluster "${cluster}" '{
    apiVersion: "kustomize.config.k8s.io/v1alpha1",
    kind: "Component",
    patches: [{
      patch: ({
        apiVersion: "kustomize.toolkit.fluxcd.io/v1",
        kind: "Kustomization",
        metadata: {name: "_"},
        spec: {postBuild: {substitute: {
          control_d_profile: .control_d_profile,
          pod_subnet: .clusters[$cluster].pod_subnet,
          tailscale_ingress_target: .clusters[$cluster].tailscale_ingress_target
        }}}
      } | tojson),
      target: {group: "kustomize.toolkit.fluxcd.io", kind: "Kustomization", name: "(apps|automation|platform)"}
    }]
  }' "${repo_dir}/inventory.json" | yq -P '(.patches[].patch |= (from_json | (... style="") | to_yaml)) | .patches[].patch style="literal"')"
  mkdir -p "${output_directory}/${cluster}/settings"
  printf '%s\n' "${settings}" >"${output_directory}/${cluster}/settings/kustomization.yaml"
done <<<"${clusters}"
