# Homelab

[![License](https://img.shields.io/badge/license-AGPL--3.0-blue.svg)](LICENSE)
[![OpenTofu](https://img.shields.io/badge/OpenTofu-1.10+-blue)](https://opentofu.org/)
[![Status](https://img.shields.io/badge/status-active-success)](https://github.com/maxexcloo/homelab)

Infrastructure as code for homelab management using OpenTofu.

## Quick Start

```bash
# Clone repository
git clone https://github.com/maxexcloo/homelab.git
cd homelab

# Setup
mise run setup  # Creates .mise.local.toml template
mise run init   # Initialize OpenTofu

# Deploy
mise run plan   # Review changes
mise run apply  # Apply changes
```

## Prerequisites

- [mise](https://mise.jdx.dev/) for task management and tool installation
- 1Password Connect server with access to the server and service credential vaults listed in `data/defaults.yml`
- Terraform Cloud account for state backend

Run `mise run setup` to create `.mise.local.toml` from the template, then fill in credentials — see `.mise.local.toml.default` for the full list.

The provider lock file (`.terraform.lock.hcl`) should be committed when provider selections change. The `.terraform/` plugin directory and any plan/state files stay local.

## Architecture

YAML files in `data/` are the source of truth. OpenTofu reads them, computes derived values, and provisions resources across the integrated providers. Some service credentials are rendered directly because no provider resource manages them.

Server and service data is modeled in two layers: desired values from YAML/defaults plus deterministic fields, and runtime values from providers or generated secrets. Consumers use narrower views for 1Password, templates, public inventory, and outputs so dependencies stay visible.

```
data/
├── defaults.yml        # Global defaults and base schemas
├── dns/*.yml           # DNS zones and manual records
├── servers/*.yml       # Server definitions
└── services/*.yml      # Service deployments
    │
    ▼
OpenTofu
    ├── 1Password       Credential storage (one entry per server/service)
    ├── B2              Object storage buckets and keys
    ├── Cloudflare      DNS records, Zero Trust tunnels, ACME tokens
    ├── GitHub          SSH public keys; pushes Fly/Komodo/TrueNAS configs
    ├── Incus           Containers and VMs on managed hosts
    ├── OCI             Oracle Cloud VMs and networking
    ├── Pushover        Pass-through alert notification credentials
    ├── Resend          Email API keys
    └── Tailscale       VPN auth keys, ACLs, and device lookups
```

Rendered service configs (Docker Compose, Fly.toml, TrueNAS app values) are SOPS-encrypted and pushed to the platform-specific GitHub repos listed in `data/defaults.yml`, where deployment runners consume them. TrueNAS catalog updates apply desired values as an overlay on the current app config, so per-app values files only need to include managed keys.

Rendered plaintext can be written locally for debugging by setting `TF_VAR_debug_dir` to a scratch path such as `/tmp/homelab-debug`. Leave it unset for normal runs.

Credentials fall into two groups:

- Mandatory credentials are required for normal operation of this stack: 1Password Connect, Cloudflare, GitHub, Terraform Cloud, and Tailscale.
- Optional credentials are required only when the corresponding data enables those resources: B2, Incus, OCI, Resend, and UniFi.

Feature flags either create provider-backed resources, expose values generated locally by OpenTofu, or control rendered config. `password` is local-only, while `monitoring` and `monitoring_alerts` only control generated Gatus checks and alerts. `b2`, `resend`, and `tailscale` call providers when enabled. Resend uses the generic REST API provider with `TF_VAR_resend_api_key` because this repo does not use a native Resend provider. Pushover has no provider-managed resource here, so `TF_VAR_pushover_application_token` and `TF_VAR_pushover_user_key` are pass-through values rendered into service config when `features.pushover` is enabled.

## Workflow

### Adding Servers

1. Create `data/servers/<key>.yml` following `schemas/server.json`
2. Fill in `platform`, `type`, `features`, `identity`, `networking`
3. Run `mise run plan` to review, `mise run apply` to provision

### Adding Services

1. Create `data/services/<key>.yml` following `schemas/service.json`
2. Fill in `deploy_to`, `features`, `identity`, `networking`
3. For Fly.io deployments, optionally set `platform_config.fly.app_name`; otherwise it defaults to `<org>-<service>` and the Fly hostname is added to computed service URLs
4. Optionally add deploy artifacts under `services/<identity.service>/`; use `.tftpl` for files that need OpenTofu template rendering and `.raw.tftpl` for rendered files that must be encrypted as binary
5. Run `mise run plan` to review, `mise run apply` to provision

## Commands

```bash
mise run apply     # Apply infrastructure changes
mise run check     # Format check, validate, and lint
mise run fmt       # Format HCL and YAML data files
mise run init      # Initialize OpenTofu providers and backend
mise run lint      # Validate YAML data files against JSON schemas
mise run plan      # Review infrastructure changes
mise run refresh   # Check for configuration drift
mise run setup     # Initial project setup
mise run validate  # Validate OpenTofu configuration
```

## Credential Storage

All generated credentials are stored automatically in **1Password** through 1Password Connect:

- **Servers vault** — one login entry per server; generated fields (passwords, API keys, tunnel tokens) are stored as fields, and IPs/FQDNs are stored as item URLs
- **Services vault** — one login entry per service deployment with the same pattern, preserving all computed and custom URLs on the login item

Set `onepassword.vaults.servers` and `onepassword.vaults.services` in `data/defaults.yml` to the target 1Password vault UUIDs, and set `TF_VAR_onepassword_connect_url` plus `TF_VAR_onepassword_connect_token` for the Connect API.

Provided or externally generated secrets can live in `data/secrets.sops.yml`. The file is encrypted with SOPS/age in Git and read during OpenTofu runs. Server keys under `servers.<server>` are exposed as `{key}_sensitive`; service keys are declared in `features.secrets` with `type: external`, then declared keys under `services.<identity.name>` or `services.<service-target>` are exposed as `{key}_sensitive` in templates.

Services can access another service's private fields only by declaring an `imports.services` alias. The normal `services` map remains public inventory, and declared private imports are overlaid by alias as `services.<alias>`.

Rendered sidecar files named `*.raw.tftpl` are templated, encrypted as binary, and deployed without the `.raw` segment. Use this for files where SOPS structured YAML/JSON encryption is unsuitable, such as top-level YAML arrays.

```yaml
servers:
  au-truenas:
    api_token: ...
services:
  truenas:
    homepage_widget_key: ...
```

Set `SOPS_AGE_KEY` in `.mise.local.toml` or use the standard SOPS age key file, then use `mise run secrets-edit`.

## Documentation

- [AGENTS.md](AGENTS.md) - Development guide and standards

## License

AGPL-3.0 - see [LICENSE](LICENSE)
