# AGENTS.md

## Project Overview

Homelab infrastructure managed with OpenTofu (1.10+). YAML files in `data/` are the source of truth; OpenTofu reads them, computes derived values, and provisions resources across multiple providers.

Data flows through two model layers — **desired** (YAML + defaults + deterministic computed fields) and **runtime** (provider-backed values + generated secrets). Consumers select narrower views (public, private, feature-filtered) so dependency chains stay visible.

Files follow a `{domain}_{layer}.tf` naming pattern grouped by data-flow stage: input → model → outputs → validation → render.

## Sorting Convention

Within any object — YAML, HCL, or JSON Schema `properties` — sort single-line assignments alphabetically by key first, then multi-line assignments alphabetically by key.

Underscore-prefixed locals sort before non-prefixed ones (ASCII `_` = 95 < `a` = 97).

This applies consistently to `data/` YAML files, `schemas/*.json` property lists, resource attribute blocks, `environment {}` blocks, and `templatefile()` argument objects. Inside staged HCL `locals {}` blocks, sort top-level locals alphabetically by name and sort object attributes inside each local. Only assignments that span multiple lines count as multi-line values; a single-line assignment like `identity = v.identity` sorts alphabetically with every other single-line assignment. When `CONTENT = base64encode(...)` spans multiple lines it is multi-line and goes last; single-line `CONTENT` assignments sort alphabetically with the other single-line attributes.

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

## General

- **Comments**: Only for non-obvious business logic
- **KISS**: Prefer readable over clever
- **Trailing newlines**: Required in all files
