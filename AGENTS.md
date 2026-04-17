# AGENTS.md

## Project Overview

Homelab infrastructure managed with OpenTofu (1.10+). YAML files in `data/` are the source of truth; OpenTofu reads them, computes derived values, and provisions resources across Bitwarden, B2, Cloudflare, GitHub, Incus, OCI, Resend, and Tailscale.

- `data/defaults.yml` — global config and schema defaults for servers/services
- `data/servers/*.yml` — one file per server; deepmerged with server defaults in `servers.tf`
- `data/services/*.yml` — one file per service; deepmerged with service defaults in `services.tf`; expanded per `deploy_to` target (e.g. `gatus-fly`)
- `templates/` — HCL template files for cloud-init configs (`cloud_config/`), Docker Compose and stack configs (`docker/<service>/`), and Fly.io configs (`fly/`)

Key computed locals:
- `local.servers` — fully-merged server map with computed fields (FQDNs, feature flags, etc.)
- `local.services` — fully-merged, deploy-target-expanded service map
- `local.services_labels` — per-service Homepage/Traefik Docker labels, computed in `services.tf` and passed as the `labels` variable to all `templatefile()` calls

## Sorting Convention

Within any object — YAML, HCL, or JSON Schema `properties` — apply this order:

1. **Single-line scalar values** (strings, booleans, integers, enums) — alphabetically
2. **Multi-line values** (objects and arrays) — alphabetically

Underscore-prefixed locals (`_defaults`, `_dns_raw`) sort before non-prefixed ones (ASCII `_` = 95 < `a` = 97).

This applies consistently to `data/` YAML files, `schemas/*.json` property lists, HCL `locals {}` blocks, resource attribute blocks, `environment {}` blocks, and `templatefile()` argument objects. When `CONTENT = base64encode(...)` spans multiple lines it is multi-line and goes last; single-line `CONTENT` assignments sort alphabetically with the other scalars.

## HCL Standards

- **Formatting**: `tofu fmt -recursive` (run via `mise run fmt`)
- **`for_each`**: Always prefer over `count`
- **Naming**: `snake_case` for all resources, locals, and variables
- **Sensitive data**: `sensitive = true` on all outputs containing secrets; all generated secret fields end with `_sensitive` (e.g. `password_sensitive`, `tailscale_auth_key_sensitive`)
- **Defaults**: Set values in `data/defaults.yml` wherever possible; use `try()` / `coalesce()` only when a value must be computed from multiple optional sources with no applicable default
- **Validation**: Use `terraform_data` preconditions for referential integrity checks
- **State**: Never manipulate state manually — use `tofu import` for imports

### Locals structure

Complex locals are built in stages, underscore-prefixed for intermediate steps:

```
_servers           raw deepmerged data
_servers_computed  derived/computed fields added
servers            final map with feature-conditional resource references merged in
servers_by_feature filtered subsets keyed by feature flag
servers_filtered   null/empty/false values stripped (for output)
```

### `github_repository_file` resources

Always set `overwrite_on_create = true`. SOPS-encrypted files use `shell_sensitive_script` output (`output["encrypted_content"]`). Plain-text files may use inline strings, heredocs, or `join()` expressions directly.

### Template authoring

- Always use `~` on all template directives (`%{ if ~}`, `%{ endif ~}`, `%{ for ~}`, `%{ endfor ~}`) to prevent unwanted blank lines
- Inject Docker labels via `${indent(N, yamlencode(labels))}` at the appropriate depth
- Guard `templatefile()` with `fileexists()` when the template may not be present

## YAML Standards

- **Formatting**: Prettier (run via `mise run fmt`)
- **Defaults**: `data/defaults.yml` defines the full schema; per-resource files only include overrides
- **Descriptions**: Short, title case

## JSON Schema Standards

- `"additionalProperties": false` on all object types
- `"type": ["string", "null"]` for optional string fields
- Feature flag descriptions state what resources are provisioned and what variables are exposed

## General

- **Comments**: Only for non-obvious business logic
- **KISS**: Prefer readable over clever
- **Trailing newlines**: Required in all files
