# AGENTS.md

## Project Overview

This repository owns homelab infrastructure and Kubernetes cluster substrate.
The separate `kubelab` repository owns Kubernetes API resources reconciled by
Flux.

## Conventions

- Read `PLAN.md` before changing architecture, ownership, deletion behaviour,
  networking, storage, secrets, state, or migration order.
- Treat `PLAN.md` as authoritative for this repository's substrate details and
  `kubelab/PLAN.md` as authoritative for cross-repository ordering and workload
  ownership.
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

Keep root Markdown limited to `AGENTS.md`, `PLAN.md`, and `README.md`. Put later
operational documentation under `docs/`.

## OpenTofu Safety

- Use stable resource names and `for_each` keys; never identify resources by
  list position.
- Keep one GCS prefix per state root and never manage a backend from the root
  that consumes it.
- Commit `.terraform.lock.hcl` for every root and include checksums for every
  platform used to validate or plan it.
- Never migrate, import, move, or remove state as part of an unrelated resource
  change.
- Never use `tofu init -migrate-state` for the new Kubernetes substrate roots.
- Never run `tofu apply` without reviewing the exact saved plan first.
- Do not make routine destroy operations reset Talos nodes or retained
  substrate.

## Verification

- Run `mise run check` before handoff.
- Run `mise run prek` after changing hooks or workflows.
- Run plans only when requested or immediately before an explicitly approved
  apply.

## Git History

Git history is the work log. Use small, imperative commit subjects and keep one
coherent outcome per commit. Keep backend changes, ownership transfers, and
resource changes separate when their risks differ.
