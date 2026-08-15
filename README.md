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
- `mise run init`: initialise providers without connecting the backend.
- `mise run prek`: run the complete local equivalent of CI.
- `mise run ssh-config`: preview the non-secret SSH include.
- `mise run ssh-config-install`: install it under `~/.ssh/config.d/homelab`.

Initialisation during setup uses `-backend=false`. Initialise a real backend
only through the reviewed procedure in
[docs/backend-migration.md](docs/backend-migration.md). Never migrate the legacy
`states/core` state into this root.

The committed `.terraform.lock.hcl` records provider checksums for Apple
Silicon development and Linux CI. Review lockfile changes with provider
updates.

SSH private keys remain in the 1Password SSH agent. The repository stores only
connection facts and renders aliases for SSH-capable hosts; Talos nodes use
`talosctl` and are deliberately omitted. Ensure the main SSH configuration has
an `Include ~/.ssh/config.d/*` line before installing the generated include.

TrueNAS plans use the provider's native environment variables for connection
settings and credentials:

```shell
export TRUENAS_URL=https://kimbap.mbk.excloo.net:8443
export TRUENAS_API_KEY='retrieve from the configured secret store'
```

The provider always enables destroy protection. Set its native
`TRUENAS_READ_ONLY=true` environment variable for read-only checks, and disable
that environment guard only for the exact reviewed saved plan and its
explicitly approved apply. Never put the API key in a checked-in variable file.
Storage adoption boundaries and the existing manually owned replication jobs
are recorded in [docs/truenas-ownership.md](docs/truenas-ownership.md).
Recovery ownership for HAOS, Hotdog, Kimbap, Mandu, and Ramen is recorded in
[docs/appliance-recovery.md](docs/appliance-recovery.md).

## Repository Boundaries

- Root OpenTofu configuration: TrueNAS and OCI compute, UniFi reservations,
  Cloudflare DNS and tunnels, Tailscale policy and credentials, native
  1Password delivery, and both Talos cluster substrates.
- `kubelab`: Kubernetes and Flux resources after the API is healthy.
- `PLAN.md`: architecture, migration gates, and recovery rules.

## DNS

Put manually curated Cloudflare records in `data/dns/<zone>.yaml`. The filename
must match the zone name. Record identity is derived from zone, type, name, and
priority; add a logical `id` only when multiple records would otherwise have
the same identity, such as several apex TXT records. These IDs are OpenTofu
keys, not Cloudflare object IDs.

Machine and cluster API records are derived separately from the infrastructure
inventories. Do not duplicate a derived record in the manual files. Existing
Cloudflare records must be adopted through reviewed import blocks in
`migrations.tf` before any apply.

The initial configuration creates a content-addressed Talos Image Factory
schematic and declares the adopted `enp3s0` and `br4` TrueNAS network end state.
The schematic includes only the official QEMU guest agent and Tailscale system
extensions and derives the metal/amd64 ISO and installer image for Talos Linux
`v1.13.8`. The first bridge adoption requires the staged procedure in
`PLAN.md`; network resources must never be changed without its exact reviewed
procedure, console recovery access, and explicit approval.

## Licence

AGPL-3.0 - see [LICENSE](LICENSE).
