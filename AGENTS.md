# AGENTS.md

## Project Overview

This repository manages homelab infrastructure with OpenTofu. YAML in `data/`
is the source of truth. OpenTofu validates it, builds deterministic models,
provisions resources, and renders encrypted deployment artifacts.

Servers and services have two layers:

- `model` contains input and deterministic computed values. Use it for resource
  identity, `for_each`, filters, and validation.
- `runtime` adds provider-backed values under `addresses`, `attributes`,
  `credentials`, `hosts`, and `urls`.

Never derive resource keys or collection membership from runtime or rendered
values. Those values may be unknown until apply.

## File Organization

- Use `{domain}_{stage}.tf` for staged pipelines, such as `services_model.tf`.
- Use one root file per provider or utility provider, such as `cloudflare.tf`.
- Keep backend, locals, outputs, providers, Terraform requirements, and
  variables in their conventional root files.
- Put service templates under `templates/services/<identity.service>/`.
- Omit `identity.service` for inventory-only services with no artifacts.

Keep root HCL service-agnostic. Put service-specific behaviour in YAML, its
template directory, or `services_render_custom.tf` when it aggregates services.

## Sorting Convention

Sort object assignments in this order:

1. Single-line values, alphabetically by key.
2. Multi-line values, alphabetically by key.

Underscore-prefixed names sort before other names. Apply this to HCL objects and
argument blocks, YAML mappings, JSON Schema `properties`, environment blocks,
and template argument objects. A non-empty object is multi-line. A scalar-only
JSON array sorts as a single-line value even when formatting wraps it; an array
containing an object or array is multi-line. Apply the same rule inside each
local's object value.

List-item identifiers come first in `type`, `name`, `id` order. Prek hook items
use `id`, then `name`. Sort the remaining fields normally.

## HCL Standards

- Format with `mise run fmt`.
- In mixed files, order data sources, locals, provisioning blocks, then outputs.
  Keep an `import` next to its resource. Order provisioning blocks by dependency.
- Always prefer `for_each` over `count`. Use stable logical keys and shape its
  input in a named local. Membership filters may use model/input data and
  `fileexists()`, never runtime or rendered values.
- Put `for_each` and module `source` first in a block, add a blank line, then
  sort the remaining arguments.
- Use descriptive comprehension names. Use `values()`, `keys()`, or both
  variables as needed; do not write `for _, value in map`. Test map membership
  with `can(map[key])` so a present null value is not treated as absent.
- Name resources, locals, and variables in `snake_case`. Prefix file-private
  locals with `_`; exported locals omit it. Staged locals use
  `{domain}_{stage}_{noun}` where practical. Sort locals alphabetically by full
  name; choose names that make the resulting order easy to follow.
- Keep the main stage output concise. Drop temporary suffixes such as `_all`,
  `_final`, `_merged`, and `_write`.
- Add a helper local only when it names a useful concept, removes duplication,
  or makes a complex expression easier to review.
- Normalize optional values once in the input or model stage, then use direct
  access in consumers. Prefer defaults when every object needs the same value.
- Use `coalesce()` only for nullable values with a guaranteed non-null fallback.
  Normalize empty-string sentinels with an explicit conditional.
- Use `can(map[key])` for relationship membership and `try(map[key], null)` to
  retrieve a nullable related value. Shape reused relationships once.
- Use `try()` for provider/API data, parsing probes, optional generated keys,
  external maps, and ordered candidates that may be empty. Avoid `lookup()`
  unless it is clearer than `try()`.
- Use `one()` for a true singleton, not for first-match selection.
- Use `merge()` for flat objects and `provider::deepmerge::mergo()` only when
  nested values must combine.
- Write domain, configuration, argument, and list-element objects over multiple
  lines with one key per line, including objects inside `merge()`, `jsonencode()`,
  and `templatestring()`. Empty objects and clear temporary one-key objects may
  stay inline.
- Expand predicates with more than two conditions, mixed operators, or guarded
  dereferences. Put one condition per line with the operator at the end. Order
  broad discriminators first and guards immediately before dependent access.
  Two short symmetric conditions may stay on one line. Accept `tofu fmt`'s
  `if(` formatting in comprehensions. Sort sibling conditions only when it does
  not weaken guard order or readability.
- Use `terraform_data` preconditions for referential validation.
- Mark every credential-bearing output sensitive. Keep credentials under
  `runtime.credentials` and expose only the fields consumers need.

Use input locals while constructing and validating models. Use model locals for
stable resource keys, filters, and deterministic consumers. Use runtime locals
only after the address set is fixed and a provider-backed value is required.

Use server `hosts.*` and service `urls.*.{host,href}` instead of new scalar
`fqdn_*`, `url_*`, or ambiguous `*_address` fields. Provider-discovered IPs
belong under `runtime.addresses`.

## JSON Schema Standards

- Define closed objects with `additionalProperties: false`. Allow open
  JSON-compatible objects only for deliberate pass-through data.
- Use `["string", "null"]` for nullable strings.
- Describe what each feature provisions and which runtime values it exposes.
- Keep JSON Schema `if`, `then`, `else` in that reading order.

## YAML Standards

- Put global configuration in `data/config.yml` and merged defaults in
  `data/defaults.yml`. Per-resource YAML should contain overrides only.
- Keep short descriptions in title case.
- Avoid quotes unless YAML would change the value or structure. Quote empty
  strings, DNS TXT content, values starting with `@`, and scalar-looking strings
  that must remain strings. Email addresses do not need quotes.
- In `truenas.env`, leave booleans and numbers typed; templates convert them to
  strings. Quote values with a leading `:` or starting with `{`, `[`, `#`, `%`,
  `@`, `` ` ``, `&`, `*`, `!`, `|`, or `>`.
- Root service keys are `credentials`, `dashboard`, `data`, `features`,
  `identity`, `imports`, `routing`, and `target_feature`. Target entries may
  override `credentials`, `data`, `features`, `fly`, and `truenas`.
- Put app-owned configuration in `data`. Set `identity.service` only when the
  service has templates or deployment artifacts.
- Omit `targets` when `target_feature` supplies every target. Use
  `targets.<key>: {}` for one target with no overrides.

## Templates & Deployments

- Start template control directives with `%{~`. Add trailing trim markers only
  when the following newline should also disappear.
- Use `.tftpl` for rendered text and `.raw.tftpl` for binary-encrypted content.
- Guard optional templates with `fileexists()`.
- Treat deployment repositories as generated output. Change their workflows and
  files through this repository, never in the generated repository.

## TrueNAS Services

Read and follow `docs/truenas-services.md` before changing a TrueNAS catalog
service or its templates.

## General

- Prefer plain, direct code over abstraction.
- Keep comments local and specific. Put architecture and usage explanations in
  docs instead of code comments.
- Sort Python imports with Ruff. Sort top-level constants, classes, and helper
  functions within their groups; keep `main()` and the execution guard last.
- When a list mixes directories and files, list directories first and sort each
  group alphabetically.
- End every file with a newline.

## Verification

- Run `mise run check` once before handoff.
- Run `mise run prek` when hooks or workflows changed, or when a complete suite
  is requested.
- Run `mise run plan` only when requested or immediately before an explicitly
  approved apply.
- Never run `mise run apply` without explicit user approval.
