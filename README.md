# Homelab

This repository manages homelab infrastructure and Talos cluster substrate
with OpenTofu. Kubernetes API resources and Flux reconciliation live in the
separate `kubelab` repository.

The migration begins with `mbk`, a single Talos control-plane VM on TrueNAS.
The independent OCI Sydney cluster, `syd`, follows only after the home
cluster passes the recovery and workload success gate in [PLAN.md](PLAN.md).

CI validates configuration and never receives infrastructure or cluster
credentials. Plans and applies run locally from a trusted workstation after
review and explicit approval.

## First Setup

```shell
mise trust
mise run setup
mise run check
```

The main commands are:

- `mise run check`: check formatting, OpenTofu, workflows, and security.
- `mise run fmt`: format project files.
- `mise run prek`: run the complete local equivalent of CI.

Initialisation during setup uses `-backend=false`. Initialise a real backend
only as part of a reviewed local planning or apply procedure. Never migrate the
legacy `states/core` state into a new stack.

The committed `.terraform.lock.hcl` records signed provider checksums for
Apple Silicon development and Linux CI. Review lockfile changes with provider
updates.

## Repository Boundaries

- Root OpenTofu configuration: home Talos cluster substrate, starting with
  Image Factory.
- `kubelab`: Kubernetes and Flux resources after the API is healthy.
- `PLAN.md`: architecture, migration gates, and recovery rules.

The first resource creates a content-addressed Talos Image Factory schematic
for a TrueNAS KVM guest. It includes only the official QEMU guest agent and
Tailscale system extensions and derives the metal/amd64 ISO and installer image
for Talos Linux `v1.13.8`. It does not create a VM, install Talos, configure a
machine, or bootstrap Kubernetes.

## Licence

AGPL-3.0 - see [LICENSE](LICENSE).
