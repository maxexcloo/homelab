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

- the multi-file server and service catalogue, JSON schemas, inheritance,
  defaults, or input/model/runtime/render stages;
- generic credential, object-storage, or 1Password reconciliation modules;
- generated deployment, Homepage, Gatus, or target-repository configuration;
- shell commands and workflow dispatches hidden behind `terraform_data`; or
- inventory-only OpenTofu resources that do not own real infrastructure.

Reintroduce retained legacy infrastructure only through direct resources under
the current state and ownership boundaries:

| Legacy area               | Decision                                                                                                                                                                                                                                                                                                                                                              |
| ------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| OCI Sydney network and VM | Rewrite the useful VCN, subnet, internet gateway, NSG, boot volume, and instance resources directly in the future `au-oci` state root after the home success gate. Preserve stable external identities through an address inventory, old-state backup, import procedure, saved plan, and rollback notes. Do not restore the server catalogue or generated cloud-init. |
| UniFi                     | Add only the fixed-MAC DHCP reservation and network policy that OpenTofu actually owns. Do not restore inventory-only client lookups.                                                                                                                                                                                                                                 |
| Cloudflare                | Add cluster tunnels, credentials, and shared recovery access foundations directly. App routes, Access policies, WAF, and rate limits remain Crossplane resources in `kubelab`; do not restore their catalogue-driven generation here.                                                                                                                                 |
| Tailscale                 | Rebuild global grants and tag owners in `foundations`, then add separate least-privilege operator OAuth and Talos bootstrap identities to each cluster root. Do not restore reusable per-server or per-service auth keys.                                                                                                                                             |
| 1Password                 | Store reviewed cluster bootstrap and recovery material without restoring the generic reconciliation modules. Never expose generated credentials through ordinary outputs or human-readable plan artefacts.                                                                                                                                                            |
| GitHub                    | Retain validation and Flux bootstrap ownership only where required. Do not restore generated repository variables, workflow dispatches, or destroy-time `local-exec` operations.                                                                                                                                                                                      |
| TrueNAS                   | Manage adopted `enp3s0` and `br4` resources through the unchanged `eno1` management path. Use a staged, rollback-enabled API transaction for network changes because provider v2.4.1 cannot safely perform them. Add the protected `taco` zvol, VM, and devices after the bridge succeeds.                                                                            |
| HAOS, Bazzite, and Hotdog | Treat these as retained appliances. Document their recovery and integration contracts; do not create inventory-only resources for them.                                                                                                                                                                                                                               |

The archived OCI configuration is design evidence, not code to copy. It used
an Ubuntu image, generated bootstrap metadata, broad public SSH ingress, and
catalogue-derived identity. The future `syd` root instead uses a pinned Talos
image, explicit network rules, the host identity `hsp.syd.excloo.net`, and no
dependency on the archived model pipeline.

Keep stable, non-secret infrastructure facts in one flat
`data/infrastructure.yaml` file and consume them directly from HCL. This file
may contain location codes, canonical host identities, and network values used
by real resources. Do not add per-host files, schemas, inheritance, feature
flags, generated models, service definitions, or rendering stages.

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
  64 GiB VM boot zvol.
- `eno1` is `10.0.0.3/22` on the UniFi `Default` network.
- `enp3s0` is `10.4.0.3/22` on the separate `Services` VLAN 4 used by hosts'
  second interfaces.
- No TrueNAS VMs or Linux bridges existed at inventory time.
- TrueNAS reported hardware virtualisation and UEFI support.
- `10.4.0.4` was unused and is the proposed DHCP reservation for the home node.
- The Kubernetes Pod/Service allocation `10.100.0.0/20` did not overlap the
  inspected home, Tailscale, or local container routes.

Create `br4` with `enp3s0` as its only member and move `10.4.0.3/22` from the
physical interface to the bridge as one staged TrueNAS network transaction.
After the transaction is committed and checked in, import both interfaces into
their `truenas_network_interface` resources and require a no-op plan. Connect
through `eno1` and keep `10.0.0.3/22` unchanged as the
management and recovery path. Do not use MACVLAN because the VM must
communicate with its TrueNAS host for storage. This live bridge change still
requires an exact reviewed procedure, console recovery access, and explicit
approval.

### TrueNAS provider adoption decision

PjSalty/truenas `v2.4.1` was reassessed on 2026-08-14 for the home bridge and VM
substrate. A live apply proved that its physical-interface request cannot clear
the last address: the request model marks `aliases` with `omitempty`, so
`aliases = []` is omitted and OpenTofu rejects the unchanged address as an
inconsistent provider result. The provider also commits each interface
resource separately, whereas this migration should stage both interface
changes before one commit and check-in. Do not retry the two-resource creation
plan. Use one separately reviewed TrueNAS API transaction and import the
resulting interfaces, or wait for a pinned provider release that fixes the
empty-alias update and supports safe staging. The unchanged `eno1` management
path at `10.0.0.3/22` remains the recovery path.

Provider import also leaves its operation-only `rollback` attribute unset,
while the schema plans a default of `true`. Updating only that metadata sends
unrelated empty virtual-interface fields and fails TrueNAS validation. For the
initial import, normalise only that state attribute to `true` from a verified
state backup rather than asking the provider to perform a live update. Continue
detecting drift in all live bridge attributes, and set rollback explicitly in
every staged API procedure.

The initial bridge adoption completed on 2026-08-14 as one staged API
transaction with a 120-second rollback window. The committed state was verified
through `eno1` before check-in: `br4` owns `10.4.0.3/22`, and its sole member
`enp3s0` has no address. Both interfaces are in the `au` state, the imported
bridge rollback metadata was normalised from a verified state backup, and the
final provider-read-only plan reported no changes.

The VM evidence is stronger than the earlier assessment: v2.4.1 has live
create, update, import, disappearance, and post-apply empty-plan coverage for
`truenas_vm`, plus live coverage for `truenas_vm_device` and `truenas_zvol`.
The provider's 26.0 validation covered `26.0.0-BETA.1`, not the installed
`26.0.0-BETA.2`; its four reported failures were in service and SMB APIs rather
than these virtualization resources.

Adopt the provider through this sequence:

1. Run a provider connection and inventory smoke test with the native
   `TRUENAS_READ_ONLY=true` environment guard through `eno1`.
2. Review a one-transaction API procedure that stages the `enp3s0` address
   removal and `br4` creation before commit and check-in, with console recovery
   ready.
3. Apply that exact procedure only after explicit approval, import both
   interfaces into their declared resources, and require a no-op plan before
   continuing.
4. Add the 64 GiB zvol, `taco` VM, and its disk, CD-ROM, display, and fixed-MAC
   virtio NIC as direct resources in the `au` root, pinned to `v2.4.1`.
5. Keep provider `destroy_protection`, add resource-level `prevent_destroy`
   to the zvol and VM, and review a saved plan before the first apply.
6. If any VM object was created manually, import it first and require a no-op
   plan; never create a duplicate to simplify adoption.

## Version baseline

Pin exact stable versions. The verified initial values are:

| Component                  | Version                                   |
| -------------------------- | ----------------------------------------- |
| OpenTofu                   | `1.12.5`                                  |
| Sidero Labs Talos provider | `0.11.0`                                  |
| PjSalty TrueNAS provider   | `v2.4.1` approved for guarded VM adoption |
| Talos Linux                | `v1.13.8`                                 |
| Kubernetes                 | `v1.36.3`                                 |

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
record the new content-addressed schematic. The applied home schematic with
both required extensions resolved to
`7d4c31cbd96db9f90c874990697c523482b2bae27fb4631d5583dcd9c281b1ff`.

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
├── data/
│   └── infrastructure.yaml
├── image.tf
├── LICENSE
├── locals.tf
├── outputs.tf
├── PLAN.md
├── providers.tf
├── README.md
├── renovate.json
├── terraform.tf
└── truenas.tf
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
   - Manage `enp3s0` and `br4` through the pinned TrueNAS provider, then add the
     guarded zvol and VM resources after the bridge succeeds.
   - Exact VM target: 12 vCPU, 32 GiB RAM, 64 GiB boot zvol on
     `truenas-nvme`, UEFI, virtio NIC on `br4`, autostart, and a fixed MAC.

4. Review the live home network and VM plan.
   - Preview the ordered TrueNAS bridge changes through the unchanged primary
     NIC and keep console recovery ready.
   - After the bridge is checked in, review the protected OpenTofu zvol, VM,
     and device plan; create or import them only after approval.
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
