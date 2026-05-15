# AGENTS.md

## Project Overview

Homelab infrastructure managed with OpenTofu. YAML files in `data/` are the source of truth; OpenTofu reads them, computes derived values, and provisions resources across multiple providers.

Each `server` and `service` has two layers:

- **model**: YAML input plus deterministic computed fields. Safe for `for_each`.
- **runtime**: provider-backed addresses, attributes, hosts, URLs, and credential values.

Feature filters use model/input data only, so resource addresses never depend on values those resources produce.

## File Organization

Root HCL files come in three shapes:

- **Domain stages**: `{domain}_{layer}.tf`, for example `servers_input.tf`, `services_model.tf`, `dns_render.tf`.
- **Per-provider files**: one file per provider or utility provider, for example `cloudflare.tf`, `github.tf`, `random.tf`.
- **Per-service templates**: `templates/services/<identity.service>/`. Omit `identity.service` for dashboard/inventory-only services.

## Sorting Convention

Sort within any object — YAML, HCL, or JSON Schema `properties`:

- Single-line assignments alphabetical by key, first
- Multi-line assignments alphabetical by key, after
- Underscore-prefixed names sort before non-prefixed (`_` = ASCII 95 < `a` = 97)

A "multi-line" assignment is one whose value spans multiple lines:

- `identity = v.identity` is single-line and sorts with the other single-line keys
- `CONTENT = base64encode(<spans multiple lines>)` is multi-line and sorts after the single-line block
- Single-line `CONTENT = "value"` sorts alphabetically with the other single-line keys

Applies consistently to:

- `data/` YAML files
- `schemas/*.json` property lists
- HCL resource attribute blocks
- HCL `environment {}` blocks
- HCL `templatefile()` argument objects

Inside staged HCL `locals {}` blocks, sort top-level locals alphabetically by name; the single-line/multi-line ordering applies inside each local's object value.

## HCL Standards

- **Formatting**: `tofu fmt -recursive` (run via `mise run fmt`)
- **`for_each`**: Always prefer over `count`; use a named local for filtered/shaped resource/data `for_each` inputs
- **Block ordering**: In resource/data/module blocks, put `for_each` and module `source` first (alphabetically), blank line, then remaining arguments alphabetically
- **Comprehensions**: Use descriptive names (`server_key`, `service`, `record`, `file_path`). Avoid `k`/`v` except in trivial non-nested expressions. Use `for k, v in map` when both key and value are needed; `for v in values(map)` when only the value is needed; `for k in keys(map)` when only the key is needed. Never `for _, v in map` — discard the key with `values(map)` instead. Never `contains(keys(map), x)` — use `lookup(map, x, null) != null`.
- **Locals — naming and ordering**:
  - `snake_case` for all resources, locals, and variables
  - Within a staged file, names follow the `{domain}_{layer}_{noun}` shape (e.g. `services_render_files_compose`) so producers and consumers sort near each other alphabetically and read in data-flow order
  - **Helpers** (locals used only within their own staged file) are prefixed with `_` so they sort ahead of public locals in the `locals {}` block. Per-provider files (`unifi.tf`, `github.tf`, `b2.tf`, …) don't follow the `{domain}_{layer}_{noun}` shape and don't use the `_` prefix — all locals there sort purely alphabetically.
  - The main output of a stage drops suffixes like `_all`, `_final`, `_merged`, and `_write`: use `dns_render_records`, not `dns_render_records_all`. If that output depends on same-prefix intermediates, keep it at the bottom as a deliberate data-flow exception.
- **Object literals**: Always multi-line, one key per line, even for a single key. Empty `{}` stays inline. Applies inside `merge()`, `jsonencode()`, `templatestring()`, list elements, and resource attributes.
- **Runtime shape**: Runtime values live under `runtime.addresses`, `runtime.attributes`, `runtime.hosts`, `runtime.urls`, and `runtime.credentials`. Use model fields unless the value is provider-backed.
- **Host and URL shape**: Use server `hosts.*` for hostnames without a scheme. Use service `urls.*.host` for hostnames and `urls.*.href` for full URLs. Use `runtime.addresses.*` for provider-discovered IP addresses. Avoid new scalar `fqdn_*`, `url_*`, or ambiguous `*_address` fields.
- **Sensitive data**: `sensitive = true` on all outputs containing credentials; credential values live under `runtime.credentials`
- **Consumer data source**: Downstream resources and output locals should reference `local.servers_model` / `local.services_model`, not `local.servers_input` / `local.services_input_targets`. The model layer normalises credential fields and adds computed attributes. Use input-layer locals only within their own staged file.
- **Defaults**: Set values in `data/defaults.yml` wherever possible; use `try()` / `coalesce()` only when no applicable default exists
- **Merge functions**: Use `merge()` for shallow merges of flat objects; use `provider::deepmerge::mergo()` only when nested keys must combine recursively (server/service YAML overrides, config blob composition, JSON catalog overlays)
- **`try()` vs `lookup()`**: Use `try(map[key], fallback)` for provider-controlled or external maps where key presence or value type isn't guaranteed (e.g. 1Password field lookups). Use `lookup(map, key, default)` for internal maps whose shape is guaranteed by defaults.
- **Multi-condition `if` clauses**: When a comprehension or resource filter has more than one condition, put each on its own line with `&&` or `||` at the end. Sort conditions alphabetically where dependencies allow. A guard `lookup(...) != null` must immediately precede any condition that indexes the same map. Single-condition `if` stays on one line.
- **Validation**: Use `terraform_data` preconditions for referential integrity checks

### Template authoring

- Always use `~` on control-flow directives (`%{~ if …}`, `%{~ for …}`, `%{~ endif ~}`) to suppress blank lines
- Keep root HCL service-agnostic. Service-specific logic belongs in YAML `data`, per-service templates, or `services_render_custom.tf` for cross-service aggregation.
- Use `.tftpl` for files needing template rendering (suffix stripped on deploy); `.raw.tftpl` for binary-encrypted files where SOPS structured encryption is unsuitable (e.g. top-level arrays)
- Guard `templatefile()` with `fileexists()` when the template may not be present

## YAML Standards

- **Formatting**: Prettier (run via `mise run fmt`)
- **Quotes**: Avoid unless YAML would misparse the value or the intended type would change. Use quotes for empty strings, `@`, DNS TXT content, and strings that look like YAML scalars (numbers, booleans, null) but must stay strings.
- **Defaults are split across two files**, both merged into `local.defaults`:
  - `data/config.yml` — global parameters (cloudflare, domains, github, networking, onepassword, organization, resend, server_types, system, tailscale)
  - `data/defaults.yml` — field values merged into every server/service/DNS record
- Per-resource files (`data/servers/*.yml`, `data/services/*.yml`) only include overrides
- **Descriptions**: Short, title case
- **Identifier fields first**: In list-item objects, identifier keys lead in fixed order: `type` (if present) → `name` (if present) → `id` (if present) → remaining fields sorted normally. Applies to DNS records, dashboard cards, widget lists, and all other list-item objects.
- **Service shape**:
  - Root keys apply to every target: `dashboard`, `data`, `features`, `identity`, `imports`, `routing`.
  - `targets.<key>` may override `credentials`, `data`, `features`, `fly`, and `truenas`.
  - Put app-owned config in `data` instead of root HCL when possible.
  - Set `identity.service` only when templates or deploy artifacts exist.
  - Use `targets.<key>: {}` for a single target with no overrides.

## JSON Schema Standards

- `"additionalProperties": false` on closed object types. Pass-through data objects such as `data` and dashboard cards may allow arbitrary JSON-compatible keys.
- `"type": ["string", "null"]` for optional string fields
- Feature flag descriptions state what resources are provisioned and what variables are exposed
- The `if`/`then`/`else` conditional triplet keeps its canonical reading order, exempt from the sorting convention (the `mise run sort-check` linter skips it)

## General

- **Comments**: Only for non-obvious business logic, kept specific to the code at the call site. General explainers (architecture, data flow, usage) belong in `README.md`; conventions belong here in `AGENTS.md`
- **Prefer readable over clever**: Don't introduce abstractions, helpers, or cleverness beyond what the task requires
- **Listing order**: When listing both folders and files (docs file trees, multi-line lint commands, etc.) put folders above files; sort alphabetically within each group
- **Trailing newlines**: Required in all files
