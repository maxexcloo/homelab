# Homelab

[![License](https://img.shields.io/badge/license-AGPL--3.0-blue.svg)](LICENSE)
[![OpenTofu](https://img.shields.io/badge/OpenTofu-1.x-blue)](https://opentofu.org/)
[![Status](https://img.shields.io/badge/status-active-success)](https://github.com/maxexcloo/homelab)

Infrastructure as code for homelab management using OpenTofu.

## Quick Start

```bash
git clone https://github.com/maxexcloo/homelab.git
cd homelab

mise run setup
mise run init

mise run plan
mise run apply
```

## Prerequisites

- [mise](https://mise.jdx.dev/) for task management and tool installation
- 1Password Connect server with access to the server and service credential vaults listed in `data/config.yml`
- Terraform Cloud account for state backend

Run `mise run setup` to create `.mise.local.toml` from the template, then fill in credentials for the providers used by the current data files. See `.mise.local.toml.default` for the full list.

The provider lock file (`.terraform.lock.hcl`) should be committed when provider selections change. The `.terraform/` plugin directory and any plan/state files stay local.

## Architecture

YAML files in `data/` are the source of truth. OpenTofu reads them, computes derived values, provisions provider resources, and renders deploy artifacts.

Data flows through four stages:

1. **input**: YAML plus defaults, with service targets expanded
2. **model**: deterministic fields safe for `for_each`
3. **runtime**: provider-backed values and generated credentials
4. **render**: dashboards, labels, compose files, and sidecars

Service endpoints use `service.urls.*.{host,href}`. Server hostnames use `server.hosts.*`.

Rendered service configs are SOPS-encrypted and pushed to the platform-specific GitHub repos listed in `data/config.yml`. `mise run render` can write plaintext render output locally via `debug_dir` for troubleshooting.

## Service Data and Templates

Service YAML can include a root `data` value with any JSON-compatible shape. Templates receive the rendered value as `service.data`. Targets can set `targets.<key>.data`; objects deep-merge with the target value winning, while scalars, arrays, and null replace the service-level value.

Templates receive:

- `defaults` — merged global defaults and config
- `server` — the target server when running on a managed server, otherwise null
- `servers` — all modeled servers
- `service` — the current expanded service, including rendered `data`, `dashboard`, and `routing_labels`
- `services` — all expanded services plus declared `imports.services` aliases overlaid by alias

Feature flags create provider resources or control rendered config. Feature-targeted services use cloud-init on bootstrap servers and available app or Docker templates on managed service platforms. Pushover credentials are read from per-server/service 1Password fields.

## Workflow

### Adding Servers

1. Create `data/servers/<key>.yml` following `schemas/server.json`
2. Fill in `platform`, `type`, `features`, `identity`, and `networking`
3. Run `mise run plan` to review, `mise run apply` to provision

### Adding Services

1. Create `data/services/<key>.yml` following `schemas/service.json`
2. Fill in `features`, `identity`, and `routing`; add `targets:` entries or use `target_feature` for automatic server targets
3. Set `identity.service` only when the service has templates or deploy artifacts; omit it for dashboard/inventory-only services
4. Each target may carry `credentials`, `data`, `features`, `fly`, and `truenas` overlays; target values win over service-level values
5. Set `target_feature` when servers with a matching feature flag should become automatic targets
6. Put provider-neutral app config under `data`; use `targets.<key>.data` for per-target overrides
7. For Fly.io deployments, optionally set `targets.fly.fly.app_name`; otherwise it defaults to `<org>-<identity.name>`
8. Optionally add deploy artifacts under `templates/services/<identity.service>/`; TrueNAS prefers `app.json.tftpl` and falls back to `docker-compose.yaml.tftpl`, while Docker/Komodo targets use `docker-compose.yaml.tftpl`. A service may provide both
9. Run `mise run plan` to review, `mise run apply` to provision

## Commands

```bash
mise run apply       # Apply infrastructure changes
mise run check       # Format check, lint, and validate
mise run fmt         # Format HCL, Python, YAML, schemas, and templates
mise run init        # Initialize OpenTofu providers and backend
mise run lint        # Validate source and default-merged YAML against JSON schemas
mise run plan        # Review infrastructure changes
mise run setup       # Initial project setup
mise run sort-check  # Check YAML and JSON Schema key ordering
mise run validate    # Validate OpenTofu configuration
```

## Credential Storage

Generated credentials are stored in **1Password** through 1Password Connect:

- **Servers vault**: one login entry per server
- **Services vault**: one login entry per service deployment with credentials and URLs

Set `onepassword.vaults.servers.id` and `onepassword.vaults.services.id` in `data/config.yml` to the target vault UUIDs, and set `TF_VAR_onepassword_connect_url` plus `TF_VAR_onepassword_connect_token` for the Connect API.

Manually supplied service credentials are declared under `credentials.fields`. OpenTofu creates empty concealed fields on the matching 1Password item, reads populated values back, and exposes them as `service.runtime.credentials.<name>` in templates. Add `bootstrap_type` and `bootstrap_length` to have OpenTofu generate the initial value instead.

Services can access another service's credentials by declaring an `imports.services` alias. The alias is overlaid onto the `services` map under the declared alias key.

## Documentation

- [AGENTS.md](AGENTS.md) - Development guide and standards

## License

AGPL-3.0 - see [LICENSE](LICENSE)
