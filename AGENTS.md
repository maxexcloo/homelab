# AGENTS.md

## Project Overview

Homelab infrastructure managed with OpenTofu. YAML files in `data/` are the source of truth; OpenTofu reads them, computes derived values, and provisions resources across multiple providers.

Each `server` and `service` has two layers:

- **model**: YAML input plus deterministic computed fields. Safe for `for_each`.
- **runtime**: provider-backed addresses, attributes, hosts, URLs, and credential values.

Feature filters use model/input data only, so resource addresses never depend on values those resources produce.

## File Organization

Root HCL files use three patterns:

- **Domain stages**: `{domain}_{layer}.tf`, for example `servers_input.tf`, `services_model.tf`, `dns_render.tf`.
- **Per-provider files**: one file per provider or utility provider, for example `cloudflare.tf`, `github.tf`, `random.tf`.
- **Conventional OpenTofu files**: `backend.tf`, `locals.tf`, `outputs.tf`, `providers.tf`, `terraform.tf`, and `variables.tf`.

Per-service templates live under `templates/services/<identity.service>/`. Omit
`identity.service` for dashboard/inventory-only services.

## Sorting Convention

Sort within any object — YAML, HCL, or JSON Schema `properties`:

- Single-line assignments alphabetical by key, first
- Multi-line assignments alphabetical by key, after
- Underscore-prefixed names sort before non-prefixed (`_` = ASCII 95 < `a` = 97)

A "multi-line" assignment is one whose value spans multiple lines:

- `identity = v.identity` is single-line and sorts with the other single-line keys
- `CONTENT = base64encode(<spans multiple lines>)` is multi-line and sorts after the single-line block
- Single-line `CONTENT = "value"` sorts alphabetically with the other single-line keys
- In JSON, scalar-only arrays such as `required` and `enum` sort as single-line values even when Prettier wraps them; arrays containing objects or arrays sort as multi-line values

Applies consistently to:

- `data/` YAML files
- `schemas/*.json` property lists
- HCL resource attribute blocks
- HCL `environment {}` blocks
- HCL `templatefile()` argument objects

The single-line/multi-line ordering also applies inside each local's object value.

## HCL Standards

- **Formatting**: `tofu fmt -recursive` (run via `mise run fmt`)
- **Top-level ordering**: In mixed HCL files, put data sources before locals, then provisioning blocks, then outputs. Order provisioning blocks by dependency and keep an `import` immediately after its resource. Conventional files such as `providers.tf` and `variables.tf` contain their expected block type.
- **`for_each`**: Always prefer over `count`; use a named local for filtered/shaped resource/data `for_each` inputs. **Filters that determine map membership (keys) must use only model/input data and file existence checks (`fileexists`)**, never render outputs like `services_render_write_compose` or `services_render_write_sidecars`. Render outputs wrap bootstrapped credential values from `random_id` which are unknown at plan time; when used in a `for_each` filter they make the entire map's keys indeterministic.
- **Block ordering**: In resource/data/module blocks, put `for_each` and module `source` first (alphabetically), blank line, then sort remaining arguments using the single-line/multi-line convention
- **Comprehensions**: Use descriptive names (`server_key`, `service`, `record`, `file_path`). Avoid `k`/`v` except in trivial non-nested expressions. Use `for k, v in map` when both key and value are needed; `for v in values(map)` when only the value is needed; `for k in keys(map)` when only the key is needed. Never `for _, v in map` — discard the key with `values(map)` instead. Use `can(map[key])` when testing membership so present nullable values are not mistaken for absent keys.
- **Helper locals**: Prefer formatting an expression clearly over extracting a helper local used only once. Add a helper only when it represents a meaningful domain concept, avoids real duplication, or makes a complex pipeline materially easier to review.
- **Locals — naming and ordering**:
  - `snake_case` for all resources, locals, and variables
  - Within a staged file, names follow the `{domain}_{layer}_{noun}` shape (e.g. `services_render_write_compose`) so producers and consumers sort near each other alphabetically and read in data-flow order
  - Prefix every file-private local with `_`, including locals in per-provider files. Exported locals omit the prefix.
  - Sort locals alphabetically by their full names. Prefer names that make alphabetical order read naturally as data flow, but alphabetical order and consistency take precedence; HCL resolves dependencies declaratively.
  - The main output of a stage drops suffixes like `_all`, `_final`, `_merged`, and `_write`: use `dns_render_records`, not `dns_render_records_all`.
- **Object literals**: Domain, configuration, argument, and list-element objects are multi-line with one key per line. Empty `{}` stays inline. A temporary one-key object inside an expression may stay inline when that is clearer than expanding it. Applies inside `merge()`, `jsonencode()`, `templatestring()`, list elements, and resource attributes.
- **Runtime shape**: Runtime values live under `runtime.addresses`, `runtime.attributes`, `runtime.hosts`, `runtime.urls`, and `runtime.credentials`. Use model fields unless the value is provider-backed.
- **Host and URL shape**: Use server `hosts.*` for hostnames without a scheme. Use service `urls.*.host` for hostnames and `urls.*.href` for full URLs. Use `runtime.addresses.*` for provider-discovered IP addresses. Avoid new scalar `fqdn_*`, `url_*`, or ambiguous `*_address` fields.
- **Sensitive data**: `sensitive = true` on all outputs containing credentials; credential values live under `runtime.credentials`
- **Consumer data source**: Use input locals in input/model stages, referential validation, and early cross-domain normalization required to construct a model. Resource keys, filters, and deterministic downstream consumers use `local.servers_model` / `local.services_model`. Consumers that need provider-backed values use `local.servers` / `local.services` only after their address set is fixed.
- **Defaults**: Put global parameters in `data/config.yml` and fields merged into every server, service, or DNS record in `data/defaults.yml`. Use `try()` / `coalesce()` only when neither default layer can represent the fallback.
- **Fallbacks and sentinels**:
  - Prefer normalising optional values once in the input/model layer, then direct field access in render/resource code.
  - Use `coalesce()` only for nullable values with a guaranteed non-null fallback. For string sentinels where `""` means unset, use an explicit `value != "" ? value : fallback` normalization.
  - Use `can(map[key])` when relationship membership matters. Use `try(map[key], null)` when retrieving a nullable value across a relationship boundary. Avoid repeating either form in consumers; create a shaped local when the same relationship is reused.
  - Use `try(map[key], fallback)` for provider-controlled/external maps, optional generated object keys, and default fallback reads. Avoid `lookup()` unless a provider function or schema makes it clearer. Do not contort code into length guards just to avoid `try()`.
  - Use `try()` when the expression itself is the cleanest way to handle dynamic absence or errors: provider/API/decoded data, parsing probes, empty ordered candidate lists, and other cases defaults cannot prevent.
  - Use `one()` for true singleton assertions. For ordered “first match, else null” logic, prefer the clearest expression; `try()` around the first-candidate expression is acceptable.
- **Merge functions**: Use `merge()` for shallow merges of flat objects; use `provider::deepmerge::mergo()` only when nested keys must combine recursively (server/service YAML overrides, config blob composition, JSON catalog overlays)
- **Multi-condition predicates**: Expand a predicate when it has more than two conditions, mixes `&&` and `||`, or must guard a dependent dereference. Wrap expanded predicates in parentheses and put each condition on its own line with `&&` or `||` at the end. Two short, symmetric conditions using the same operator may stay on one line. `tofu fmt` renders comprehension filters as `if(`; do not fight the formatter for a space. Order broad discriminators first (`platform`, `type`, target/source), then existence guards immediately before dependent dereferences, then specific field/value checks. Sort sibling conditions alphabetically only when that does not weaken readability or guard ordering. Single-condition predicates stay on one line.
- **Validation**: Use `terraform_data` preconditions for referential integrity checks

### Template authoring

- Always use a leading `~` on control-flow directives (`%{~ if …}`, `%{~ for …}`, `%{~ endif }`) to suppress whitespace before the directive. Add a trailing `~` only when removing the following newline is intentional; careless right trimming can join structured YAML lines.
- Keep root HCL service-agnostic. Service-specific logic belongs in YAML `data`, per-service templates, or `services_render_custom.tf` for cross-service aggregation.
- Treat the GitHub deployment repositories as generated outputs. Never edit them directly; manage workflows under `templates/workflows/`, service artifacts in this repository, and repository-owned files through OpenTofu.
- Use `.tftpl` for files needing template rendering (suffix stripped on deploy); `.raw.tftpl` for binary-encrypted files where SOPS structured encryption is unsuitable (e.g. top-level arrays)
- Guard `templatefile()` with `fileexists()` when the template may not be present

## YAML Standards

- **Formatting**: Prettier (run via `mise run fmt`)
- **Quotes**: Avoid unless YAML would misparse the value or the intended type would change. Use quotes for empty strings, DNS TXT content, values starting with `@`, and strings that look like YAML scalars (numbers, booleans, null) but must stay strings. Email addresses containing `@` do not need quotes. **`truenas.env` values**: do not quote booleans or numbers — the base template's `tostring()` normalizes them to environment variable strings regardless of YAML type. Only quote values that YAML would structurally misparse (leading `:` in scalars, values starting with `{`, `[`, `#`, `%`, `@`, `` ` ``, `&`, `*`, `!`, `|`, `>`).
- **Defaults are split across two files**, both merged into `local.defaults`:
  - `data/config.yml` — global parameters shared across resource types
  - `data/defaults.yml` — field values merged into every server/service/DNS record
- Per-resource files (`data/servers/*.yml`, `data/services/*.yml`) only include overrides
- **Descriptions**: Short, title case
- **Identifier fields first**: In list-item objects, place every present identifier key before all non-identifier keys. When multiple identifier keys are present, order them `type` → `name` → `id`, then sort the remaining keys using the standard single-line/multi-line convention. Applies to DNS records, dashboard cards, widget lists, and all other list-item objects unless a more specific order is documented.
- **Prek hooks**: Hook objects use `id` → `name` (when overridden) as their identifier order, then sort the remaining keys using the standard single-line/multi-line convention.
- **Service shape**:
  - Root keys apply to every target: `credentials`, `dashboard`, `data`, `features`, `identity`, `imports`, `routing`, `target_feature`.
  - `targets.<key>` may override `credentials`, `data`, `features`, `fly`, and `truenas`.
  - Put app-owned config in `data` instead of root HCL when possible.
  - Set `identity.service` only when templates or deploy artifacts exist.
  - Omit `targets` when `target_feature` supplies every target.
  - Use `targets.<key>: {}` for a single target with no overrides.

## TrueNAS Services

Before editing a service that deploys through a TrueNAS community catalog app,
read and follow `docs/truenas-services.md`. That provider-specific guide is
mandatory for the service YAML and its templates.

## JSON Schema Standards

- `"additionalProperties": false` on closed object types. Pass-through data objects such as `data` and dashboard cards may allow arbitrary JSON-compatible keys.
- `"type": ["string", "null"]` for optional string fields
- Feature flag descriptions state what resources are provisioned and what variables are exposed
- The `if`/`then`/`else` conditional triplet keeps its canonical reading order, exempt from the sorting convention (the `mise run sort-check` linter skips it)

## General

- **Comments**: Only for non-obvious business logic, kept specific to the code at the call site. General explainers (architecture, data flow, usage) belong in `README.md`; conventions belong here in `AGENTS.md`
- **Prefer readable over clever**: Don't introduce abstractions, helpers, or cleverness beyond what the task requires
- **Python ordering**: Sort imports with Ruff. Sort top-level constants, classes, and helper functions alphabetically within their groups; keep `main()` and the execution guard last.
- **Listing order**: When listing both folders and files (docs file trees, multi-line lint commands, etc.) put folders above files; sort alphabetically within each group
- **Trailing newlines**: Required in all files
- **Verification**: `mise run check` is the canonical source validation. Run `mise run prek` for the complete repository hook suite before handoff, and review `mise run plan` before applying HCL or data changes.
