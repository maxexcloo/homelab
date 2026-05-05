# AGENTS.md

## Project Overview

Homelab infrastructure managed with OpenTofu (1.10+). YAML files in `data/` are the source of truth; OpenTofu reads them, computes derived values, and provisions resources across multiple providers.

Data flows through two model layers — **desired** (YAML + defaults + deterministic computed fields) and **runtime** (provider-backed values + generated secrets). Consumers select narrower views (public, private, feature-filtered) so dependency chains stay visible.

## File Organization

Root HCL files come in three shapes:

- **Domain stages** — `{domain}_{layer}.tf` (`servers_input.tf`, `services_model.tf`, `dns_model.tf`, …) hold the input → model → outputs → validation → render pipeline for a domain that flows through every layer.
- **Per-provider files** — one file per provider (`unifi.tf`, `github.tf`, `b2.tf`, `bcrypt.tf`, `random.tf`, `age.tf`, …) for resources and data sources that don't fit a staged domain. Includes utility providers (random/bcrypt/age) used as cross-cutting building blocks.
- **Per-service templates** — under `services/<identity.service>/`. Use `docker-compose.yaml.tftpl` for custom Docker stacks and `app.json.tftpl` for TrueNAS catalog overlays. Any other files are deployed as sidecars (`.tftpl` rendered, `.raw.tftpl` rendered then binary-encrypted because SOPS structured encryption is unsuitable, e.g. top-level YAML arrays).

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
- **Comprehensions**: Use descriptive key/value names (`server_key`, `service`, `record`, `file_path`). Avoid `k`/`v` except in trivial, non-nested expressions
- **Naming**: `snake_case` for all resources, locals, and variables
- **Sensitive data**: `sensitive = true` on all outputs containing secrets; generated secret fields end with `_sensitive`
- **Defaults**: Set values in `data/defaults.yml` wherever possible; use `try()` / `coalesce()` only when no applicable default exists
- **Validation**: Use `terraform_data` preconditions for referential integrity checks

### Template authoring

- Always use `~` on all template directives to prevent unwanted blank lines
- Keep root HCL service-agnostic. Service-specific behavior belongs in YAML data or per-service templates
- Use `.tftpl` for files needing template rendering (suffix stripped on deploy); `.raw.tftpl` for binary-encrypted files where SOPS structured encryption is unsuitable (e.g. top-level arrays)
- Guard `templatefile()` with `fileexists()` when the template may not be present

## YAML Standards

- **Formatting**: Prettier (run via `mise run fmt`)
- **Quotes**: Avoid unless YAML would misparse the value or the intended type would change. Use quotes for empty strings, `@`, DNS TXT content with literal quotes, and JSON-like string values
- **Defaults**: `data/defaults.yml` defines the full schema; per-resource files only include overrides
- **Descriptions**: Short, title case

## JSON Schema Standards

- `"additionalProperties": false` on all object types
- `"type": ["string", "null"]` for optional string fields
- Feature flag descriptions state what resources are provisioned and what variables are exposed
- The `if`/`then`/`else` conditional triplet keeps its canonical reading order, exempt from the sorting convention (the `mise run sort-check` linter skips it)

## General

- **Comments**: Only for non-obvious business logic, kept specific to the code at the call site. General explainers (architecture, data flow, usage) belong in `README.md`; conventions belong here in `AGENTS.md`
- **KISS**: Prefer readable over clever
- **Trailing newlines**: Required in all files
