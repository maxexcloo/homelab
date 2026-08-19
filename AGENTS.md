# AGENTS.md

## Project Overview

This repository owns homelab infrastructure and Kubernetes cluster substrate.
The separate `kubelab` repository owns Kubernetes API resources reconciled by
Flux.

## Conventions

- Treat this repository as authoritative for substrate details and
  `kubelab` as authoritative for Kubernetes resources and platform
  integrations.
- Use Australian English in project-owned prose and identifiers.
- Use `.yaml`, not `.yml`, for project-owned YAML.
- Pin tools and providers to exact stable versions. Let Renovate propose
  upgrades for manual review.
- Keep credentials, kubeconfigs, plans, state, and recovery material out of Git.
- Treat anyone who can read OpenTofu state as able to read its secrets.
- Never change live infrastructure without an explicit approval and a reviewed,
  saved OpenTofu plan.

## File Organisation

- `.github/workflows/`: validation only; infrastructure applies are local.
- Root HCL: the `au` cluster substrate.

Use ordinary provider resources directly and keep the root small enough to
review in one plan. Do not recreate the archived catalogue, schema, model,
generator, or deployment pipeline. Add another state root only with its first
reviewed resource and keep it outside the root `au` configuration.

Keep conventional root files for backend, locals, outputs, providers,
requirements, and variables. Put direct provider resources and their exclusive
data sources in the corresponding domain file. Do not combine unrelated
domains merely to deduplicate lookups.

Keep root Markdown limited to `AGENTS.md` and `README.md`. Put later
operational documentation under `docs/`.

## OpenTofu Safety

- Use stable resource names and `for_each` keys; never identify resources by
  list position.
- Derive resource membership and `for_each` keys only from configuration known
  before apply, never from provider-generated or rendered values.
- Normalise optional input once, use descriptive comprehension names, and add a
  helper local only when it names a useful concept or removes real duplication.
- Use `one()` only for a true singleton. Use `can(map[key])` for relationship
  membership and `try(map[key], null)` for optional related values.
- Keep one GCS prefix per state root and never manage a backend from the root
  that consumes it.
- Commit `.terraform.lock.hcl` for every root and include checksums for every
  platform used to validate or plan it.
- Keep every temporary `moved`, `removed`, and `import` block in
  `migrations.tf`, separate from ordinary resources.
- Never migrate, import, move, or remove state as part of an unrelated resource
  change.
- Never migrate a backend except through its separately reviewed procedure.
- Never run `tofu apply` without reviewing the exact saved plan first.
- Do not make routine destroy operations reset Talos nodes or retained
  substrate.
- Read only the secret fields a provider consumer needs, prefer write-only
  arguments where supported, and mark every credential-bearing output
  sensitive.

## Sorting Convention

Sort object assignments in this order:

1. Single-line values, alphabetically by key.
2. Multi-line values, alphabetically by key.

Underscore-prefixed names sort before other names. Apply this recursively to
HCL objects and argument blocks, YAML mappings, environment blocks, and
template argument objects. A non-empty object is multi-line. A scalar-only
array is a single-line value even when formatting wraps it; an array containing
an object or array is multi-line. Apply the same rule inside each local's object
value. Separate every multi-line assignment from adjacent assignments with a
blank line, except where the formatter removes the separator. Keep assignments
contiguous inside YAML list-item mappings.

List-item identifiers come first in `type`, `name`, `id` order. Prek hook items
use `id`, then `name`; sort remaining fields normally.

Sort Mise tools alphabetically and tasks alphabetically within each lifecycle
section. Sort Renovate package rules by description and Prek hooks by `id`.
GitHub workflows use top-level `name`, `on`, `permissions`, `concurrency`, then
global configuration and `jobs`. Preserve dependency order within workflow
steps.

Sort unordered peer headings, lists, and table rows alphabetically. Preserve
procedural, dependency, routing, interface, priority, chronological, and other
meaningful order.

## Style

- Prefer plain, direct HCL over abstractions and generic pipelines.
- In mixed HCL files, order data sources, then locals, then resources; sort
  each group alphabetically by address.
- Keep comments local and specific; put operational explanations in
  `docs/`.
- Keep check orchestration single-layered so the same validator is not run both
  directly and through a nested task in one path.

## Verification

- Run `mise run check` before handoff.
- Run `mise run prek` after changing hooks or workflows.
- Run plans only when requested or immediately before an explicitly approved
  apply.

## Git History

Git history is the work log. Use small, imperative commit subjects and keep one
coherent outcome per commit. Keep backend changes, ownership transfers, and
resource changes separate when their risks differ.
