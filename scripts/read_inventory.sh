#!/usr/bin/env bash
# Evaluate the shared HCL inventory without providers, state or credentials.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temporary_directory="$(mktemp -d)"
trap 'rm -rf -- "${temporary_directory}"' EXIT
ln -s "${repo_dir}/data" "${temporary_directory}/data"
ln -s "${repo_dir}/locals.tf" "${temporary_directory}/locals.tf"

TF_DATA_DIR="${temporary_directory}/.terraform" \
  tofu -chdir="${temporary_directory}" console <<'HCL' | jq -r .
jsonencode({ access = local.access, inventory = local.inventory, machines = { for name, machine in local.machines : name => merge(machine, { hostname = local.machine_hostnames[name], fqdn = local.machine_fqdns[name], login_title = try(local.machine_login_titles[name], null) }) } })
HCL
