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

Inside staged HCL `locals {}` blocks, declare all `_`-prefixed helper locals first (sorted alphabetically, which must also equal data-flow order), then non-`_` exported locals (also alphabetically = data-flow order). Name or rename locals so alphabetical sort order matches data-flow dependency order. The single-line/multi-line ordering applies inside each local's object value.

## HCL Standards

- **Formatting**: `tofu fmt -recursive` (run via `mise run fmt`)
- **`for_each`**: Always prefer over `count`; use a named local for filtered/shaped resource/data `for_each` inputs
- **Block ordering**: In resource/data/module blocks, put `for_each` and module `source` first (alphabetically), blank line, then remaining arguments alphabetically
- **Comprehensions**: Use descriptive names (`server_key`, `service`, `record`, `file_path`). Avoid `k`/`v` except in trivial non-nested expressions. Use `for k, v in map` when both key and value are needed; `for v in values(map)` when only the value is needed; `for k in keys(map)` when only the key is needed. Never `for _, v in map` — discard the key with `values(map)` instead. Never `contains(keys(map), x)` — use `try(map[x], null) != null`.
- **Helper locals**: Prefer formatting an expression clearly over extracting a helper local used only once. Add a helper only when it represents a meaningful domain concept, avoids real duplication, or makes a complex pipeline materially easier to review.
- **Locals — naming and ordering**:
  - `snake_case` for all resources, locals, and variables
  - Within a staged file, names follow the `{domain}_{layer}_{noun}` shape (e.g. `services_render_write_compose`) so producers and consumers sort near each other alphabetically and read in data-flow order
  - **Helpers** (locals used only within their own staged file) are prefixed with `_`. Per-provider files (`unifi.tf`, `github.tf`, `b2.tf`, …) don't follow the `{domain}_{layer}_{noun}` shape and don't use the `_` prefix — all locals there sort by dependency first, then alphabetically within a dependency layer.
  - The main output of a stage drops suffixes like `_all`, `_final`, `_merged`, and `_write`: use `dns_render_records`, not `dns_render_records_all`. If that output depends on same-prefix intermediates, keep it at the bottom as a deliberate data-flow exception.
- **Object literals**: Always multi-line, one key per line, even for a single key. Empty `{}` stays inline. Applies inside `merge()`, `jsonencode()`, `templatestring()`, list elements, and resource attributes.
- **Runtime shape**: Runtime values live under `runtime.addresses`, `runtime.attributes`, `runtime.hosts`, `runtime.urls`, and `runtime.credentials`. Use model fields unless the value is provider-backed.
- **Host and URL shape**: Use server `hosts.*` for hostnames without a scheme. Use service `urls.*.host` for hostnames and `urls.*.href` for full URLs. Use `runtime.addresses.*` for provider-discovered IP addresses. Avoid new scalar `fqdn_*`, `url_*`, or ambiguous `*_address` fields.
- **Sensitive data**: `sensitive = true` on all outputs containing credentials; credential values live under `runtime.credentials`
- **Consumer data source**: Downstream resources and output locals should reference `local.servers_model` / `local.services_model`, not `local.servers_input` / `local.services_input_targets`. The model layer normalises credential fields and adds computed attributes. Use input-layer locals only within their own staged file.
- **Defaults**: Set values in `data/defaults.yml` wherever possible; use `try()` / `coalesce()` only when no applicable default exists
- **Fallbacks and sentinels**:
  - Prefer normalising optional values once in the input/model layer, then direct field access in render/resource code.
  - Use `coalesce()` only for nullable values with a guaranteed non-null fallback. For string sentinels where `""` means unset, use an explicit `value != "" ? value : fallback` normalization.
  - Use `try(map[key], null)` for relationship boundaries and validations where a key may be absent. Avoid repeating it in consumers; create a shaped local when the same relationship is reused.
  - Use `try()` when the expression itself is the cleanest way to handle dynamic absence or errors: provider/API/decoded data, parsing probes, optional generated object keys, empty ordered candidate lists, and other cases defaults cannot prevent. Do not contort code into `lookup()` or length guards just to avoid `try()`.
  - Use `one()` for true singleton assertions. For ordered “first match, else null” logic, prefer the clearest expression; `try()` around the first-candidate expression is acceptable.
- **Merge functions**: Use `merge()` for shallow merges of flat objects; use `provider::deepmerge::mergo()` only when nested keys must combine recursively (server/service YAML overrides, config blob composition, JSON catalog overlays)
- **`try()` vs `lookup()`**: Prefer direct access after input/model normalization. Use `try(map[key], fallback)` for provider-controlled/external maps, optional generated object keys, relationship membership checks, and default fallback reads. Avoid `lookup()` unless a provider function or schema specifically makes it clearer.
- **Multi-condition predicates**: When a comprehension `if`, resource filter, ternary condition, precondition, or other boolean predicate has more than one condition, wrap it in parentheses and put each condition on its own line with `&&` or `||` at the end. `tofu fmt` renders comprehension filters as `if(`; do not fight the formatter for a space. Order broad discriminators first (`platform`, `type`, target/source), then existence guards immediately before dependent dereferences, then specific field/value checks. Sort sibling conditions alphabetically only when that does not weaken readability or guard ordering. Single-condition predicates stay on one line.
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
