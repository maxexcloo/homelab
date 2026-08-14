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

The committed `.terraform.lock.hcl` records provider checksums for Apple
Silicon development and Linux CI. Review lockfile changes with provider
updates.

TrueNAS plans use the provider's native environment variables for connection
settings and credentials:

```shell
export TRUENAS_URL=https://kimbap.mbk.excloo.net:8443
export TRUENAS_API_KEY='retrieve from the configured secret store'
```

The provider defaults to read-only mode and always enables destroy protection.
Set `truenas_read_only=false` only in the exact saved plan prepared for an
explicitly approved apply. Never put the API key in a checked-in variable file.

## Repository Boundaries

- Root OpenTofu configuration: home network, TrueNAS VM, and Talos cluster
  substrate.
- `kubelab`: Kubernetes and Flux resources after the API is healthy.
- `PLAN.md`: architecture, migration gates, and recovery rules.

The initial configuration creates a content-addressed Talos Image Factory
schematic and manages the ordered `enp3s0` to `br4` TrueNAS network change. The
schematic includes only the official QEMU guest agent and Tailscale system
extensions and derives the metal/amd64 ISO and installer image for Talos Linux
`v1.13.8`. The network resources are live changes and must never be applied
without their exact saved plan, console recovery access, and explicit approval.

## Licence

AGPL-3.0 - see [LICENSE](LICENSE).
