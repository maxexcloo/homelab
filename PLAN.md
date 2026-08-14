# Kubernetes Substrate Migration Plan

This document is authoritative for implementation inside the `homelab`
repository: state layout, providers, cluster compute, Talos, and recovery
access. The sibling `kubelab/PLAN.md` is authoritative for cross-repository
migration ordering, workload ownership, and cutover gates. If the plans
conflict at that boundary, correct this scoped plan to match `kubelab/PLAN.md`.

## Repository boundary

This repository owns infrastructure and cluster substrate:

- GCS OpenTofu state foundations;
- TrueNAS, OCI, UniFi, Tailscale, Cloudflare, GitHub, and 1Password substrate
  where explicitly retained;
- Talos Image Factory schematics, machine secrets, configuration, installation,
  bootstrap, health, upgrades, and recovery material; and
- retained appliances such as TrueNAS, Hotdog, HAOS, and Bazzite.

The sibling `kubelab` repository owns Kubernetes API resources reconciled by
Flux, including Crossplane resources for app-scoped external APIs. It must not
contain OpenTofu or Talos lifecycle configuration. Cloudflared and the
Tailscale Kubernetes operator are Kubernetes workloads in `kubelab`; the
cluster tunnel and Tailscale bootstrap identities remain substrate here.

## Naming and DNS

Use short, location-led DNS names with memorable food names for hosts. A
host's canonical infrastructure identity has this form:

```text
<food>.<location>.excloo.net
```

APIs and services use `excloo.dev` and have this form:

```text
<service>.<location>.excloo.dev
```

The location labels are:

| Label | Location            |
| ----- | ------------------- |
| `mbk` | Meadowbank, Sydney  |
| `syd` | Sydney              |
| `fre` | Fremont, California |

Names describe location rather than provider so that moving a host between
providers in the same location does not require a new location identity. Do
not add intermediate `infra` or `k8s` labels, and do not use hyphens in new
host, API, or service labels.

The confirmed and pending host identities are:

| Host                        | Location | Canonical FQDN          | Status    |
| --------------------------- | -------- | ----------------------- | --------- |
| Home Assistant OS appliance | `mbk`    | `hass.mbk.excloo.net`   | Confirmed |
| TrueNAS appliance           | `mbk`    | `kimbap.mbk.excloo.net` | Confirmed |
| Bazzite host                | `mbk`    | `mandu.mbk.excloo.net`  | Confirmed |
| Home Talos node             | `mbk`    | `taco.mbk.excloo.net`   | Confirmed |
| OCI Sydney node             | `syd`    | `hsp.syd.excloo.net`    | Confirmed |
| ZFS.Rent host               | `fre`    | `hotdog.fre.excloo.net` | Confirmed |

`hsp` means halal snack pack and remains a food name. ZFS.Rent's Fremont
location is represented by `fre`. Host names are durable machine identities;
service aliases can change with a machine's role.

The Kubernetes cluster and API identities are:

| Cluster | API FQDN             | Initial node FQDN     |
| ------- | -------------------- | --------------------- |
| `mbk`   | `api.mbk.excloo.dev` | `taco.mbk.excloo.net` |
| `syd`   | `api.syd.excloo.dev` | `hsp.syd.excloo.net`  |

The existing `au` and `au-oci` state-root names and GCS prefixes are separate
infrastructure identities. Renaming them, and the corresponding paths in
`kubelab`, requires a separately reviewed backend and cross-repository change.

Keep this repository lean and direct. Do not recreate the previous YAML
catalogue, JSON schemas, model/runtime pipeline, configuration generators,
deployment templates, or repository scripts. Use ordinary, explicit OpenTofu
roots and upstream providers. Keep each state root small enough to review in
one plan.

## Archive review decisions

The `archive/pre-kubernetes` branch remains useful design evidence. Its
directory structure was not the main source of complexity: conventional root
files and one direct HCL file per provider or infrastructure domain were clear
and maintainable. The complexity came from making one repository-wide service
and server catalogue drive credentials, external APIs, deployment rendering,
dashboards, monitoring, and workflow dispatches.

Retain these patterns from the archive:

- conventional `backend.tf`, `terraform.tf`, `providers.tf`, `variables.tf`,
  `locals.tf`, and `outputs.tf` files when each has real content;
- direct domain files such as `cloudflare.tf`, `oci.tf`, `tailscale.tf`,
  `truenas.tf`, and `unifi.tf`;
- stable logical `for_each` keys, with small locals beside their consumers;
- explicit validation, lifecycle protection, sensitive outputs, and operational
  documentation; and
- pinned tools, Prek, Renovate, and validation-only CI.

Do not restore these patterns:

- the YAML catalogue, JSON schemas, or input/model/runtime/render stages;
- generic credential, object-storage, or 1Password reconciliation modules;
- generated deployment, Homepage, Gatus, or target-repository configuration;
- shell commands and workflow dispatches hidden behind `terraform_data`; or
- inventory-only OpenTofu resources that do not own real infrastructure.

Use this ownership test: `kubelab` owns workloads and their app-scoped
integrations; this repository owns everything required to rebuild, recover, or
reach a cluster while Kubernetes is unavailable.

| Resource family                                                                   | Intended owner                                                                   |
| --------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| Application workloads, routes, policies, storage claims, and in-cluster operators | `kubelab`                                                                        |
| App-scoped B2, Cloudflare, Control D, Pocket ID, and Resend resources             | Crossplane resources in `kubelab`                                                |
| Cluster Cloudflare tunnels and credentials                                        | This repository                                                                  |
| Global Tailscale policy, tag owners, and grants                                   | This repository                                                                  |
| Per-cluster Tailscale OAuth clients and Talos bootstrap identities                | This repository                                                                  |
| Tailscale Kubernetes operator and its Kubernetes resources                        | `kubelab`                                                                        |
| Retained appliance Tailscale clients                                              | Their appliance owner; shared policy remains in this repository                  |
| GCS state, IAM, and shared access foundations                                     | This repository                                                                  |
| OCI network, VM, and Talos lifecycle                                              | This repository                                                                  |
| Talos image, machine, bootstrap, health, upgrade, and recovery lifecycle          | This repository                                                                  |
| TrueNAS VM/storage substrate and UniFi DHCP/network policy                        | This repository, or documented manual ownership when provider safety is unproven |

Crossplane is a deliberate part of the Kubernetes platform and owns app-scoped
external APIs through direct, readable provider resources in `kubelab`. It must
not own GCS state, cluster compute, Talos, cluster access identities, or anything
else required to recreate or reach Kubernetes. Start with direct provider-http
resources and introduce compositions only after repeated real resources show a
stable shared interface.

Transfer existing external resources to Crossplane one at a time. Each transfer
must preserve a stable external identity, use orphan-on-delete by default, record
rollback notes, and produce a reviewed reconciliation result before the old
owner is removed. Do not bulk-transfer application integrations merely to
complete the target architecture.

Keep `homelab-fly` as the bounded owner of Fly Gatus for now. The archive
generated its configuration and dispatched workflows but did not directly own
the Fly runtime. Consolidate it here only when direct OpenTofu ownership solves
a concrete lifecycle or recovery problem.

Retained appliances belong in this repository's operational documentation, but
only provider-managed infrastructure belongs in HCL. Do not recreate the old
server catalogue solely for inventory, dashboards, or monitoring.

## State boundary

The existing GCS bucket is `homelab-opentofu`. Leave the legacy
`states/core` prefix and all existing objects untouched during the migration.
Do not run `tofu init -migrate-state` for the new roots.

The bucket is an externally bootstrapped prerequisite. No root backed by this
bucket may manage the bucket's lifecycle. Before storing sensitive new state,
verify versioning, uniform access, retention, and least-privilege IAM through a
read-only review. The foundations root may manage shared IAM and access
resources, but not the bucket it consumes. Managing the bucket later requires
a separately backed bootstrap root and an independently reviewed migration.

Use fresh prefixes:

| Stack                                                       | GCS prefix                              |
| ----------------------------------------------------------- | --------------------------------------- |
| Access and shared foundations                               | `states/homelab-kubernetes/foundations` |
| Home cluster substrate                                      | `states/homelab-kubernetes/au`          |
| OCI Sydney cluster substrate                                | `states/homelab-kubernetes/au-oci`      |
| TrueNAS resources, only if provider adoption is proven safe | `states/homelab-kubernetes/truenas`     |

State ownership is exclusive:

| State root    | Owned resources                                                                                                                                                                                                                             |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `foundations` | Global Tailscale ACLs/grants and tag owners, shared Cloudflare identity/access foundations, and shared IAM; never the GCS backend bucket                                                                                                    |
| `au`          | Home Talos VM when provider adoption is safe, its UniFi DHCP reservation, cluster Cloudflare tunnel and credential, cluster-scoped Tailscale operator OAuth client and Talos-node bootstrap identity, and the complete home Talos lifecycle |
| `au-oci`      | OCI network, image, VM, cluster Cloudflare tunnel and credential, cluster-scoped Tailscale operator OAuth client and Talos-node bootstrap identity, and the complete OCI Talos lifecycle                                                    |
| `truenas`     | Appliance-wide datasets, shares, snapshots, and the `br4` bridge only after safe provider adoption; otherwise these remain documented manual TrueNAS configuration                                                                          |

The Kubernetes Tailscale operator is not OpenTofu state: Flux owns its
deployment in `kubelab`. OpenTofu owns global policy and tag owners in
`foundations`; each cluster state owns a separate least-privilege operator OAuth
client and delivers its secret through 1Password and External Secrets. Each
Talos node's host-level extension is part of its image, while its bootstrap
identity also belongs to that cluster's state. Existing Tailscale clients on
retained appliances remain with those appliances; do not retire them when
legacy per-service auth keys or the old service deployments are removed.

Every ownership transfer from `states/core` requires its own old-state backup,
address inventory, import or state-move procedure, saved plan, rollback notes,
and explicit approval. The repository cleanup itself transfers no resources.

## Fixed cluster design

| Cluster | Substrate                                     | Role                                             |
| ------- | --------------------------------------------- | ------------------------------------------------ |
| `mbk`   | Single Talos control-plane VM on home TrueNAS | Primary workloads and learning cluster           |
| `syd`   | Single Talos control-plane VM on OCI Sydney   | Independent secondary cluster and upgrade canary |

`mbk` and `syd` are cluster identifiers, not VM or node hostnames. The home VM
and Talos node use the hostname `taco`, with canonical FQDN
`taco.mbk.excloo.net`. The OCI Sydney node uses the hostname `hsp`, with
canonical FQDN `hsp.syd.excloo.net`.

The home network facts were verified read-only:

- TrueNAS is a WTR PRO with 16 CPU cores and about 64 GiB RAM, running
  `26.0.0-BETA.2`.
- Pools `truenas` and `truenas-nvme` are online; use the NVMe pool for the
  160 GiB VM boot zvol.
- `eno1` is `10.0.0.3/22` on the UniFi `Default` network.
- `enp3s0` is `10.4.0.3/22` on the separate `Services` VLAN 4 used by hosts'
  second interfaces.
- No TrueNAS VMs or Linux bridges existed at inventory time.
- TrueNAS reported hardware virtualisation and UEFI support.
- `10.4.0.4` was unused and is the proposed DHCP reservation for the home node.
- The Kubernetes Pod/Service allocation `10.100.0.0/20` did not overlap the
  inspected home, Tailscale, or local container routes.

Create `br4` with `enp3s0` as its only member and move `10.4.0.3/22` from the
physical interface to the bridge using TrueNAS staged network changes. Keep
`eno1` and `10.0.0.3/22` unchanged as the management and recovery path. Do not
use MACVLAN because the VM must communicate with its TrueNAS host for storage.
This live bridge change still requires an exact preview and explicit approval.

### TrueNAS provider adoption decision

The initial bridge and VM remain manual TrueNAS configuration. PjSalty/truenas
`v2.4.1` was assessed on 2026-08-14 but was not added to this root or state:

- upstream validation for the 26.0 line covered `26.0.0-BETA.1`, not the
  installed `26.0.0-BETA.2`, and still reported API drift elsewhere in the
  provider surface;
- each `truenas_network_interface` resource performs its own staged commit and
  check-in, so it cannot express moving `10.4.0.3/22` from `enp3s0` to `br4`
  as one atomic TrueNAS network transaction; and
- upstream apply-idempotency coverage explicitly defers the VM resource because
  of its complex computed fields.

Provider-wide read-only and destroy-protection controls are useful but do not
remove those modelling risks. Reconsider provider ownership only after the
installed TrueNAS release has exact upstream acceptance coverage, the bridge
move can be represented atomically, and a manually created VM imports to a
reviewed no-op plan. Until then, create the bridge and VM through a reviewed
TrueNAS staged-change procedure and keep them out of OpenTofu state.

## Version baseline

Pin exact stable versions. The verified initial values are:

| Component                  | Version                        |
| -------------------------- | ------------------------------ |
| OpenTofu                   | `1.12.5`                       |
| Sidero Labs Talos provider | `0.11.0`                       |
| PjSalty TrueNAS provider   | `v2.4.1` assessed, not adopted |
| Talos Linux                | `v1.13.8`                      |
| Kubernetes                 | `v1.36.3`                      |

Talos `v1.13.8` was verified as the current stable release on 2026-08-14. Use
the stable provider rather than `0.12.0-alpha.5`.

Kubernetes `v1.36.3` is a target, not yet an approved machine-configuration
input. Cilium `v1.19.6` lists compatibility only through Kubernetes 1.34.
Before applying Talos machine configuration, select an upstream-tested
Kubernetes and Cilium pair and update both repositories in one reviewed
decision. A successful installation of an unlisted combination is not
compatibility proof.

The home Image Factory schematic should contain only:

- `siderolabs/tailscale` for host-level Talos API recovery access; and
- `siderolabs/qemu-guest-agent` for the TrueNAS/KVM guest lifecycle.

Cloudflared does not belong in Talos. Static NFS requires no system extension.
Add `siderolabs/iscsi-tools` only in a later, isolated iSCSI trial.

An earlier Tailscale-only schematic resolved to
`4a0d65c669d46663f377e7161e50cfd570c401f26fd9e7bda34a0216b6f1922b`.
Do not reuse it after adding the QEMU guest agent; let the provider create and
record the new content-addressed schematic.

## Target repository shape

Create only directories that immediately contain real files:

```text
.
├── .github/
│   └── workflows/
│       └── validate.yaml
├── .gitignore
├── .mise.toml
├── .pre-commit-config.yaml
├── .terraform.lock.hcl
├── AGENTS.md
├── backend.tf
├── image.tf
├── LICENSE
├── outputs.tf
├── PLAN.md
├── README.md
├── renovate.json
└── terraform.tf
```

Do not create empty `foundations`, `au-oci`, or `truenas` roots as placeholders.
Add a root only with its first reviewed resource.

The repository root is the `au` state root. A later state boundary cannot share
this root configuration; choose its separate directory when its first resource
is ready for review.

## Implementation sequence

1. Finish the clean baseline on `main`.
   - Preserve `LICENSE` and `.mise.local.toml`.
   - Remove empty legacy directories.
   - Add lean repository guidance, ignores, pinned Mise tools, Prek hooks,
     Renovate, and validation-only GitHub Actions.
   - Never put cloud or cluster credentials in GitHub Actions.

2. Add the non-live root `au` image configuration.
   - Configure GCS prefix `states/homelab-kubernetes/au` without state
     migration.
   - Pin `siderolabs/talos` to `0.11.0`.
   - Commit `.terraform.lock.hcl` with `darwin_arm64` and `linux_amd64`
     provider checksums.
   - Declare the two official extensions directly with
     `talos_image_factory_schematic` and derive metal/amd64 ISO and installer
     URLs with `talos_image_factory_urls`.
   - Run `tofu init -backend=false`, `tofu validate`, TFLint, and Trivy.
   - Commit and push the clean baseline before any apply.

3. Resolve the home VM identity and TrueNAS ownership.
   - Use `taco` for the VM and node hostname, with canonical FQDN
     `taco.mbk.excloo.net`.
   - Keep the bridge and initial VM manual under the recorded provider adoption
     decision; do not add `PjSalty/truenas` to this root or state yet.
   - Exact VM target: 12 vCPU, 32 GiB RAM, 160 GiB boot zvol on
     `truenas-nvme`, UEFI, virtio NIC on `br4`, autostart, and a fixed MAC.

4. Review the live home network and VM plan.
   - Preview the TrueNAS staged bridge change and preserve the primary NIC.
   - Create or manually configure the VM only after approval.
   - Boot the provider-resolved Talos ISO in maintenance mode.
   - Discover the actual install disk; never assume `/dev/sda` or `/dev/vda`.
   - Let the first boot use DHCP, then reserve `10.4.0.4` for the VM MAC in
     UniFi and verify the lease before generating endpoint-specific config.

5. Add Talos lifecycle to the root `au` configuration.
   - Use `talos_machine_secrets`, `talos_machine_configuration`,
     `talos_machine_configuration_apply`, `talos_machine_bootstrap`, cluster
     health, and kubeconfig resources from the stable official provider.
   - Use cluster name `mbk` and the separate node hostname `taco`.
   - Stop unless `kubelab/PLAN.md` records an upstream-supported Kubernetes and
     Cilium pair; use that reviewed Kubernetes version in machine configuration.
   - Configure Pod CIDR `10.100.0.0/22`, Service CIDR `10.100.4.0/22`, CNI
     `none`, scheduling on the control plane, Pocket ID OIDC, host DNS, and the
     pinned Image Factory installer.
   - Use write-only or ephemeral provider arguments where `0.11.0` supports
     them. Talos machine secrets otherwise make state credential-sensitive;
     restrict GCS readers accordingly and never expose them in ordinary
     outputs or saved human-readable plans.
   - Store recovery material in 1Password without a custom reconciliation
     script. Review the exact secret flow before apply.
   - Set reset-on-destroy to false and do not make a routine `tofu destroy`
     wipe the node.

6. Apply in reviewed stages.
   - First apply only the content-addressed Image Factory schematic.
   - Apply machine configuration only after the VM IP and install disk are
     verified.
   - Bootstrap etcd exactly once. The provider has had timing issues between
     configuration apply and bootstrap; use explicit dependencies and expect
     a reviewed second apply rather than adding sleep scripts.
   - Retrieve kubeconfig, verify health and reboot recovery, then hand the
     healthy Kubernetes API to `kubelab`.

7. Continue Kubernetes work in `../kubelab`.
   - Install Cilium before Flux because Talos uses `cni.name: none`.
   - Bootstrap Flux from the public `maxexcloo/kubelab` repository at the path
     selected by the separately reviewed cross-repository naming change.
   - Let Flux reconcile Gateway API, Traefik, cert-manager, Tailscale operator,
     cloudflared, External Secrets, Crossplane, static NFS, and the disposable
     OpenSpeedTest workload in dependency order.

8. Stop at the home success gate before `au-oci`.
   - Prove node reboot, Talos and Kubernetes health, Flux recovery, private and
     public HTTP, TLS, secrets, static NFS persistence, and OpenSpeedTest.
   - Do not reset `hsp` until this gate passes and its lack of valued state is
     confirmed again.

## Apply and recovery rules

- Never apply an unsaved or unreviewed OpenTofu plan.
- Never combine a backend change, import, state move, and resource mutation in
  one change.
- Treat state readers as secret readers.
- Use exact resource addresses and stable `for_each` keys; never list indexes.
- Add `prevent_destroy` to retained substrate where the provider supports it.
- Do not use broad `ignore_changes` to conceal drift.
- Keep GitHub Actions validation-only. Run applies locally from a trusted
  workstation.
- Record one coherent outcome per commit. Git history is the work log.
- The archive branch and untouched `states/core` prefix are the rollback path
  while the new roots are being established.
