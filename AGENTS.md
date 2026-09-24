# AGENTS.md

## Project Overview

This repository owns homelab infrastructure and Kubernetes cluster substrate.
The separate `kubelab` repository owns Kubernetes API resources reconciled by
Flux.

## Conventions

- Use Australian English in project-owned prose and identifiers.
- Use `.yaml`, not `.yml`, for project-owned YAML.
- Pin tools and providers to stable release versions. Use readable major tags
  such as `v7` for GitHub Actions, not commit SHAs. Let Renovate propose upgrades
  for manual review.
- Keep credentials, kubeconfigs, plans, state, and recovery material out of Git.
- Keep the complete provider environment in the `OpenTofu` item in the
  `Homelab` vault. Let local setup create its schema when missing, but never
  manage it with OpenTofu. Resolve its tracked `op://` references only through
  credential-consuming Mise tasks authenticated by the 1Password desktop app.
  Keep resolved credentials out of the parent shell. Credential-consuming task
  children inherit them; export the standard Connect variable names only in the
  OpenTofu wrapper.
- Treat anyone who can read OpenTofu state as able to read its secrets.
- Never change live infrastructure without explicit approval and review of the
  OpenTofu plan presented for that apply.

## File Organisation

- `.github/workflows/`: validation only; infrastructure applies are local.
- Root HCL: the homelab cluster substrate.

Use ordinary provider resources directly and keep the root small enough to
review in one plan. Do not recreate the archived catalogue, schema, model,
generator, or deployment pipeline. Add another state root only with its first
reviewed resource and keep it outside the root substrate configuration.

Keep conventional root files for backend, locals, outputs, providers,
requirements, and variables. Put direct provider resources and their exclusive
data sources in the corresponding domain file. Do not combine unrelated
domains merely to deduplicate lookups.

Keep decoded shared inputs and genuinely cross-domain derived values in
`locals.tf`. Put provider-scoped derived locals in the corresponding domain
file, and name them from largest scope to smallest as
`provider_resource_qualifier`.

Keep all maintained documentation in the root `AGENTS.md` and `README.md`.
Do not create a documentation directory or additional Markdown files.

## OpenTofu Safety

- Use stable resource names and `for_each` keys; never identify resources by
  list position.
- Derive resource membership and `for_each` keys only from configuration known
  before apply, never from values produced during apply. Infrastructure DNS may
  use Tailscale device discovery when its results are known during planning.
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
- Do not make routine destroy operations reset Talos nodes or retained
  substrate.
- Read only the secret fields a provider consumer needs, prefer write-only
  arguments where supported, and mark every credential-bearing output
  sensitive.
- Follow the pinned provider's write-only version semantics. The 1Password
  provider requires strictly increasing versions for updates; use automatic
  tracking triggered by non-secret identity or content changes, not manual counters.
- Let the 1Password vault carry scope. Omit tags from items in the `Homelab`
  vault and tag Homelab-created items in cluster vaults only with `Homelab`.
  Use human-readable display names for titles, omit cluster names from titles
  inside cluster vaults, and qualify titles in the `Homelab` vault only when
  needed to distinguish their scope.

## Sorting Convention

Sort unordered mappings recursively: single-line values first, then multi-line
values, alphabetically within each group; underscore-prefixed keys come first.
Non-empty YAML containers are multi-line. Scalar-only JSON arrays are single-line.
Let `tofu fmt` determine HCL layout.

List identifiers lead in `type`, `name`, `id` order; Prek hooks use `id`, then
`name`. Sort Mise tools and lifecycle tasks alphabetically, Renovate rules by
description, and hooks by ID. Workflow keys start with `name`, `on`, `permissions`,
`concurrency`, then global configuration and `jobs`.

Sort unordered prose lists, table rows and tags alphabetically. Preserve meaningful
procedural, dependency, interface, routing and priority order. Keep tags limited to
useful scope, system and purpose labels.

## Style

- Prefer plain, direct HCL over abstractions and generic pipelines.
- Prefer native tool features over custom scripts. Keep scripts only for
  repository-specific glue, and keep Deepmerge for nested Talos configuration.
- Put `for_each` first in every HCL block that uses it, followed by a blank line.
- Keep `depends_on` in its own group, separated from other arguments and blocks
  by blank lines.
- In mixed HCL files, order data sources, then locals, then resources; sort
  each group alphabetically by address.
- Keep comments local and specific.
- Keep check orchestration single-layered so the same validator is not run both
  directly and through a nested task in one path.

## Verification

- Run `mise run check` before handoff.
- Run plans only when requested or immediately before an explicitly approved
  apply.

## Git History

Git history is the work log. Use small, imperative commit subjects and keep one
coherent outcome per commit. Keep backend changes, ownership transfers, and
resource changes separate when their risks differ.
