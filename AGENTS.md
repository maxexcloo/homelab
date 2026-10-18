# AGENTS.md

## Project Overview

This repository owns homelab infrastructure and Kubernetes cluster substrate.
The separate `kubelab` repository owns Kubernetes API resources reconciled by
Flux.

Keep host provisioning focused on OS, hardware and access. Application runtime
configuration and service units belong to their owning application repository.

## Conventions

- Follow the global version policy. Keep provider compatibility constraints in
  `requirements.tf` and hold `kubectl` and `talosctl` at the configured cluster
  versions. Use local Updatecli previews for manual review.
- Keep the complete provider environment in the credential item referenced by
  `.mise.toml`; local setup may create its schema, but OpenTofu never manages it.
  Resolve its `op://` references only inside credential-consuming Mise tasks, and
  export the standard Connect variable names only in the OpenTofu wrapper.
- Treat anyone who can read OpenTofu state as able to read its secrets.

## File Organisation

- `.github/workflows/`: validation and external-monitoring dispatch only;
  infrastructure applies are local.
- Root HCL: the homelab cluster substrate, small enough to review in one plan.
  Add another state root only with its first reviewed resource.

Keep conventional root files for backend, locals, outputs, providers,
requirements, and variables. Put provider resources and their exclusive data
sources in the corresponding domain file.

Each local lives with its primary owner: decoded shared inputs in `locals.tf`,
derived values in the domain file that owns them. Name locals from largest
scope to smallest as `provider_resource_qualifier`.

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
  that consumes it. Never migrate a backend except through its separately
  reviewed procedure.
- Commit `.terraform.lock.hcl` for every root and include checksums for every
  platform used to validate or plan it.
- Renaming a resource or changing its `for_each` key requires a `moved` block.
- Keep every temporary `moved`, `removed`, and `import` block in
  `migrations.tf`, separate from ordinary resources.
  Remove completed blocks after verifying the sole managed state reflects
  their intended result; remove the file when empty.
- Never migrate, import, move, or remove state as part of an unrelated resource
  change.
- Adopt existing TrueNAS resources without changing their live settings. Preserve
  dataset ACLs, case sensitivity, quotas, share identities and backup schedules.
  Keep system datasets, app-managed children, replication receivers and credentials
  under native ownership. Leave replication tasks native while the pinned provider
  cannot represent their exclusions, snapshot bindings and receiver protections.
- Do not make routine destroy operations reset Talos nodes or retained
  substrate.
- Read only the secret fields a provider consumer needs, prefer write-only
  arguments where supported, and mark every credential-bearing output
  sensitive.
- Follow the pinned provider's write-only version semantics. The 1Password
  provider requires strictly increasing versions for updates; use automatic
  tracking triggered by non-secret identity or content changes, not manual counters.
- Let the 1Password vault carry scope. Omit tags from items in the infrastructure
  vault and use only the configured ownership tag for items managed in cluster
  vaults. Use human-readable display names for titles, omit cluster names from
  titles inside cluster vaults, and qualify titles in the infrastructure vault
  only when needed to distinguish their scope.

## Style

- Use lowercase identifiers for shared data keys and `name` for human-readable
  labels. Keep resource identity separate from presentation.
- Use full ZFS paths for TrueNAS dataset keys. Configure only deviations from
  defaults and leave factory-default resources native.
- Keep consumer settings beside their owner in shared data. Avoid app-name
  wrappers such as `homepage` and `gatus`; nest only distinct endpoints or fields
  required by a native schema. Define shared provider settings once rather than
  adding per-consumer overrides without a concrete need.
- Keep tags limited to useful scope, system and purpose labels.
- Put `for_each` first in every HCL block that uses it, followed by a blank line.
- Keep `depends_on` in its own group, separated from other arguments and blocks
  by blank lines, before any `lifecycle` block.
- In mixed HCL files, order data sources, then locals, then resources; sort
  each group alphabetically by address.

## Verification

- Run plans only when requested or immediately before an explicitly approved
  apply.

## Git History

Keep backend changes, ownership transfers, and resource changes in separate
commits when their risks differ.
