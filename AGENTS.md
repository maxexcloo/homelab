# AGENTS.md

## Project Overview

Homelab infrastructure managed with OpenTofu (1.10+). YAML files in `data/` are the source of truth; OpenTofu reads them, computes derived values, and provisions resources across Bitwarden, B2, Cloudflare, GitHub, Incus, OCI, Resend, and Tailscale. Some credentials, such as Pushover, are pass-through values rendered into generated configs because no provider resource manages them.

- `data/defaults.yml` — global config and schema defaults for servers/services
- `data/servers/*.yml` — one file per server; deepmerged with server defaults in `servers.tf`
- `data/services/*.yml` — one file per service; deepmerged with service defaults in `services.tf`; expanded per `deploy_to` target (e.g. `gatus-fly`)
- `templates/` — HCL template files for cloud-init configs (`cloud_config/`) and Fly.io configs (`fly/`)
- `services/<identity.name>/` — Docker Compose templates and per-service config files (e.g. `docker-compose.yaml.tftpl`, `app/config/*.yaml.tftpl`)

Key computed locals:

- `local.servers_model_desired` — server YAML plus defaults and deterministic computed fields
- `local.servers_model_runtime` — provider-backed server values and generated secrets
- `local.servers_output_private` — server desired data plus runtime fields for private/runtime consumers
- `local.services_model_desired` — deploy-target-expanded service YAML plus deterministic computed fields
- `local.services_model_runtime` — provider-backed service values and generated secrets
- `local.services_output_private` — service desired data plus runtime fields for private/runtime consumers
- `local.services_render_labels` — per-service Docker labels, with service-owned labels from `platform_config.docker.labels` and routing labels from networking config

## Sorting Convention

Within any object — YAML, HCL, or JSON Schema `properties` — sort single-line assignments alphabetically by key first, then multi-line assignments alphabetically by key.

Underscore-prefixed locals (`_defaults`, `_dns_raw`) sort before non-prefixed ones (ASCII `_` = 95 < `a` = 97).

This applies consistently to `data/` YAML files, `schemas/*.json` property lists, resource attribute blocks, `environment {}` blocks, and `templatefile()` argument objects. Inside staged HCL `locals {}` blocks, sort top-level locals alphabetically by name and sort object attributes inside each local. Only assignments that span multiple lines count as multi-line values; a single-line assignment like `identity = v.identity` sorts alphabetically with every other single-line assignment. When `CONTENT = base64encode(...)` spans multiple lines it is multi-line and goes last; single-line `CONTENT` assignments sort alphabetically with the other single-line attributes.

## HCL Standards

- **Formatting**: `tofu fmt -recursive` (run via `mise run fmt`)
- **`for_each`**: Always prefer over `count`
- **Naming**: `snake_case` for all resources, locals, and variables
- **Sensitive data**: `sensitive = true` on all outputs containing secrets; all generated secret fields end with `_sensitive` (e.g. `password_sensitive`, `tailscale_auth_key_sensitive`)
- **Defaults**: Set values in `data/defaults.yml` wherever possible; use `try()` / `coalesce()` only when a value must be computed from multiple optional sources with no applicable default
- **Validation**: Use `terraform_data` preconditions for referential integrity checks
- **State**: Never manipulate state manually — use `tofu import` for imports

### Feature flags

- `password` is local-only and exposes generated `_sensitive` values.
- Provider-backed feature flags create or read remote resources when enabled, such as `b2`, `resend`, and `tailscale`.
- Some APIs use `TF_VAR_*` values because there is no native provider in use here, such as Resend through the generic REST API provider.
- Pass-through feature flags expose externally supplied credentials because no provider resource manages them here, such as `pushover`.
- Document whether each provider credential is mandatory for this stack or optional based on enabled data. Prefer provider/resource failures or variable validation for missing external credentials unless a referential integrity relationship can be checked locally.

### Locals structure

Complex locals use alphabetical group words so file order matches data-flow order without one local per numbered stage:

```
_servers_input_source             raw deepmerged data
_servers_prepare_ancestors        bounded parent lookup chain
_servers_prepare_parent_context   helper map for inheritance and descriptions
_servers_refine_computed          derived/computed fields, including inherited public networking
servers_model_desired             desired data without generated secrets
servers_model_runtime             generated secrets and provider-backed fields
servers_output_by_feature         filtered subsets keyed by feature flag
servers_output_private            merged private view for runtime consumers
servers_output_public             template-safe inventory view

_services_input_source            raw deepmerged data
_services_input_targets           deploy-target-expanded data
services_model_desired            desired data without generated secrets
services_model_runtime            generated secrets and provider-backed fields
services_output_by_feature        filtered subsets keyed by feature flag
services_output_private           merged private view for runtime consumers
services_output_public            template-safe inventory without labels
services_output_vars              base template context for label/env rendering
services_render_labels            merged routing and service-owned labels
services_render_vars              full template context with environment values
services_rendered_compose            rendered Docker Compose content
services_rendered_file_content_types sidecar file extension type map
services_rendered_file_extensions    sidecar file extension lookup
services_rendered_file_sources       sidecar file source metadata
services_rendered_file_text          sidecar rendered text content
services_rendered_files              deployable sidecar file model

fly_input_services                Fly-targeted service selection
fly_render_files                  rendered Fly repository files
komodo_input_stacks               Docker-capable Komodo stack selection
komodo_render_files               rendered Komodo repository files
truenas_input_servers             TrueNAS target server selection
truenas_input_services            TrueNAS-targeted service selection
truenas_prepare_catalog_services     TrueNAS catalog service selection
truenas_prepare_catalog_templates    TrueNAS catalog app template metadata
truenas_render_files              rendered TrueNAS repository files
```

### `github_repository_file` resources

Always set `overwrite_on_create = true`. SOPS-encrypted files use `shell_sensitive_script` output (`output["encrypted_content"]`). Plain-text files may use inline strings, heredocs, or `join()` expressions directly.

### Template authoring

- Always use `~` on all template directives (`%{ if ~}`, `%{ endif ~}`, `%{ for ~}`, `%{ endfor ~}`) to prevent unwanted blank lines
- Inject Docker labels via `${indent(N, yamlencode(labels))}` at the appropriate depth
- Use `.tftpl` only for files that need OpenTofu template rendering; the rendered deployment path strips the suffix
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
