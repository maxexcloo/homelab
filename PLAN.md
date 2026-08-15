# Kubernetes Substrate Migration Plan

This document is authoritative for implementation inside the `homelab`
repository: state layout, providers, cluster compute, Talos, and recovery
access. The sibling `kubelab/PLAN.md` is authoritative for cross-repository
migration ordering, workload ownership, and cutover gates. If the plans
conflict at that boundary, correct this scoped plan to match `kubelab/PLAN.md`.

## Repository boundary

This repository owns infrastructure and cluster substrate:

- one GCS-backed OpenTofu state for retained substrate;
- TrueNAS, OCI, UniFi, Tailscale, Cloudflare, and 1Password substrate
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

The existing `au` root remains the repository's single state identity. Its GCS
prefix is shortened from `states/homelab-kubernetes/au` to `homelab` through a
separately reviewed backend-only migration. The proposed `foundations` and
`au-oci` roots were never applied and were removed before they acquired state.

Keep this repository lean and direct. Do not recreate the previous YAML
catalogue, JSON schemas, model/runtime pipeline, configuration generators,
deployment templates, or repository scripts. Use ordinary, explicit OpenTofu
resources and upstream providers. Keep the single root direct and reviewable.

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

| Legacy area               | Decision                                                                                                                                                                                                                                                                                                                |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| OCI Sydney network and VM | Rebuild the substrate from scratch in root HCL. Use non-overlapping `10.20.0.0/16` addressing and expose the node subnet privately through Tailscale. Do not restore the old `10.0.0.0/16` network, Ubuntu instance, server catalogue, or generated cloud-init. The archived state remains historical evidence only.    |
| UniFi                     | Add only the fixed-MAC DHCP reservation and network policy that OpenTofu actually owns. Do not restore inventory-only client lookups.                                                                                                                                                                                   |
| Cloudflare                | Add cluster tunnels, credentials, and shared recovery access foundations directly. App routes, Access policies, WAF, and rate limits remain Crossplane resources in `kubelab`; do not restore their catalogue-driven generation here.                                                                                   |
| Tailscale                 | Rebuild global grants and tag owners in root HCL, create one reusable pre-authorised key for each retained server, and add separate least-privilege operator OAuth clients for each Kubernetes cluster. Store server keys in 1Password and treat the state as secret-bearing. Do not restore reusable per-service keys. |
| 1Password                 | Store reviewed cluster bootstrap and recovery material without restoring the generic reconciliation modules. Never expose generated credentials through ordinary outputs or human-readable plan artefacts.                                                                                                              |
| GitHub                    | Keep validation-only Actions. The public `kubelab` Git source requires no deploy key, so do not restore a GitHub provider, generated repository variables, workflow dispatches, or destroy-time `local-exec` operations.                                                                                                |
| TrueNAS                   | Manage adopted `enp3s0` and `br4` resources through the unchanged `eno1` management path. Use a staged, rollback-enabled API transaction for network changes because provider v2.4.1 cannot safely perform them. Add the protected `taco` zvol, VM, and devices after the bridge succeeds.                              |
| HAOS, Bazzite, and Hotdog | Treat these as retained appliances. Document their recovery and integration contracts; do not create inventory-only resources for them.                                                                                                                                                                                 |

Keep every temporary OpenTofu state transition (`moved`, `removed`, or import
blocks) together in root `migrations.tf`, never beside ordinary resources.
Delete that file only after a reviewed saved plan confirms every transition
has been recorded in remote state and no block is still required.

The archived OCI configuration is design evidence, not code to copy. It used
an Ubuntu image, generated bootstrap metadata, broad public SSH ingress, and
catalogue-derived identity. The `syd` resources instead use a pinned Talos
image, explicit network rules, the host identity `hsp.syd.excloo.net`, and no
dependency on the archived model pipeline.

On 2026-08-15 the legacy `au-hsp` instance was explicitly confirmed disposable
and deleted outside OpenTofu at the operator's request. Its 160 GB boot volume,
subnet, NSG, route rules, internet gateway, VCN, derived IPs, resolver, private
DNS zones, and view were deleted. Direct verification found no remaining active
compute, block storage, custom image, VCN, or Object Storage resources. The
untouched `states/core` object is now stale historical state and must never be
applied; it owns no live OCI substrate.

Keep stable, non-secret infrastructure facts in a few focused YAML inventories
under `data/` and consume them directly from HCL. `machines.yaml` owns durable
machine identity and access facts; `deployments.yaml` owns provider-managed
placement and sizing; `networks.yaml` owns UniFi and OCI network facts;
`clusters.yaml` owns only Talos/Kubernetes membership, lifecycle, and versions;
`domains.yaml` owns Cloudflare and domain facts; `dns/<zone>.yaml` owns manually
curated long-lived DNS records; and `access.yaml` owns shared 1Password,
SSH-agent, and Tailscale policy. Derive machine FQDNs, cluster API records,
tunnels, reservations, and credentials from those sources. Do not add
per-machine files, schemas, inheritance, generated models, service definitions,
or rendering stages.

Use the same deployment shape across providers where the concepts match:
`compute` owns CPU and `memory_mib`, while `boot` owns `size_mib`. Keep
provider-only values in a provider-named child object and convert MiB only at a
provider boundary that requires another unit. Write-only secret revisions
default to `1` in HCL; add and retain an optional `secret_revision` beside the
specific owning configuration only when a secret must be rewritten.

OpenTofu manages only the explicitly declared DNS foundations and new records.
Existing application and retained-host records marked `Legacy` in Cloudflare
remain intentionally outside OpenTofu until they are retired; do not import or
redeclare them. Never declare the same record here and in `kubelab`; each
ownership transfer requires an address inventory, import or state removal
procedure, reviewed plan, and rollback notes.

Use this ownership test: `kubelab` owns workloads and their app-scoped
integrations; this repository owns everything required to rebuild, recover, or
reach a cluster while Kubernetes is unavailable.

| Resource family                                                                   | Intended owner                                                                   |
| --------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| Application workloads, routes, policies, storage claims, and in-cluster operators | `kubelab`                                                                        |
| App-scoped B2, Cloudflare, Control D, Pocket ID, and Resend resources             | Crossplane resources in `kubelab`                                                |
| Cluster Cloudflare tunnels and credentials                                        | This repository                                                                  |
| Global Tailscale policy, tag owners, and grants                                   | This repository                                                                  |
| Reusable retained-server Tailscale keys                                           | This repository, stored in restricted state and delivered to 1Password           |
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
The root prefix changes from `states/homelab-kubernetes/au` to `homelab` only
through the procedure in `docs/backend-migration.md`. Do not initialise the new
prefix before backing up and inventorying the old state, and do not combine the
backend migration with resource changes.

The bucket is an externally bootstrapped prerequisite. No root backed by this
bucket may manage the bucket's lifecycle. Before storing sensitive new state,
verify versioning, uniform access, retention, and least-privilege IAM through a
read-only review. The root may manage shared IAM and access resources, but not
the bucket it consumes. Managing the bucket later requires
a separately backed bootstrap root and an independently reviewed migration.

The 2026-08-15 read-only review confirmed versioning, uniform bucket-level
access, and enforced public-access prevention. The owner explicitly accepted
the current lack of retention and soft-delete protection and the existing
legacy bucket/object IAM roles for the initial Talos installation. Treat these
as recorded risks rather than installation blockers; review them separately
before broadening state readership or adding another operator.

The single root uses `homelab`. It owns TrueNAS and OCI
compute, UniFi reservations and local DNS, Cloudflare infrastructure/API DNS
and cluster tunnels, global Tailscale policy and identities, native 1Password
delivery, and both Talos lifecycles. It never manages the GCS backend bucket.
This larger shared blast radius is an accepted consequence of keeping all HCL
in one root; saved plans must remain narrowly reviewed.

The Kubernetes Tailscale operator is not OpenTofu state: Flux owns its
deployment in `kubelab`. OpenTofu owns global policy and tag owners in
the root, including a separate least-privilege operator OAuth client for each
cluster, and delivers its secrets through 1Password and External Secrets. Each
Talos node's host-level extension is part of its image. The root owns one
reusable, pre-authorised, tagged key per retained server, including
Talos bootstrap identities, and writes each key to the Servers vault through a
write-only 1Password field. These keys are intentionally present in restricted
OpenTofu state and must be rotated if that state is exposed. Existing Tailscale
clients on retained appliances remain valid; their managed keys are recovery
and reprovisioning material rather than a reason to re-enrol healthy devices.
Do not restore reusable per-service keys.

## Operator access

Use the 1Password SSH agent as the workstation source of SSH private keys.
OpenTofu must not create private SSH keys, store them in state, or write files
under an operator's home directory. Keep non-secret SSH connection facts such
as aliases, hostnames, users, ports, and jump-host relationships in
`data/machines.yaml`. A repository Mise task may render those facts to a
temporary file and explicitly install them as `~/.ssh/config.d/homelab` when an
operator requests it. The generated include must use the 1Password SSH agent,
remain reproducible, and never contain credentials.

Talos nodes do not run SSH. Access `taco` and `hsp` with `talosctl`; include
only retained SSH-capable appliances such as `kimbap`, `mandu`, and `hotdog` in
the generated SSH configuration. Store server usernames and related recovery
metadata in 1Password as well as the non-secret inventory where required for
rendering.

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
4. Add the 64 GiB zvol, headless `taco` VM, and its disk, CD-ROM, and fixed-MAC
   virtio NIC as direct resources in the `au` root, pinned to `v2.4.1`.
5. Keep provider `destroy_protection`, add resource-level `prevent_destroy`
   to the zvol and VM, and review a saved plan before the first apply.
6. If any VM object was created manually, import it first and require a no-op
   plan; never create a duplicate to simplify adoption.

## Version baseline

Pin the latest verified stable versions exactly and let Renovate propose
updates for manual review.
Image and cluster APIs require concrete release identifiers, so record the
latest working values selected during each reviewed upgrade:

| Component                  | Version                                   |
| -------------------------- | ----------------------------------------- |
| OpenTofu                   | `1.12.5`                                  |
| Sidero Labs Talos provider | `0.11.0`                                  |
| PjSalty TrueNAS provider   | `v2.4.1` approved for guarded VM adoption |
| Talos Linux                | `v1.13.8`                                 |
| Kubernetes                 | `v1.36.3`                                 |

Talos `v1.13.8` was verified as the current stable release on 2026-08-14. Use
the stable provider rather than `0.12.0-alpha.5`.

Kubernetes `v1.36.3` and Cilium `v1.20.0` were approved together on 2026-08-15.
Cilium's stable compatibility matrix lists Kubernetes 1.36 as e2e-tested, and
the Cilium release uses Gateway API `v1.6.1`. Prefer the newest stable
upstream-tested combination rather than retaining an older candidate. Record
the resolved versions for reproducible deployment and let Renovate propose the
next compatible update for review.

Every Talos Image Factory schematic contains `siderolabs/tailscale` for
host-level Talos API recovery access. The home schematic additionally contains
`siderolabs/qemu-guest-agent` for the TrueNAS/KVM guest lifecycle. The provider
creates both content-addressed schematics; do not check their generated IDs
into configuration.

The images otherwise differ because Taco runs the `metal/amd64` platform on
TrueNAS while HSP runs the `oracle/arm64` platform on OCI. Platform and
architecture are machine constraints, not behavioural differences.

Cloudflared does not belong in Talos. Static NFS requires no system extension.
Add `siderolabs/iscsi-tools` only in a later, isolated iSCSI trial.

Use names for discoverable provider objects instead of checking in opaque
external IDs. Cloudflare zones and the account, the 1Password vault, and UniFi
networks are looked up by stable names. Keep literal IDs only where the provider
requires an authentication or adoption identity that cannot be discovered
safely. Logical DNS record `id` values are stable OpenTofu keys, not external
provider IDs.

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
│   ├── dns/
│   │   └── <zone>.yaml
│   ├── access.yaml
│   ├── clusters.yaml
│   ├── deployments.yaml
│   ├── domains.yaml
│   ├── machines.yaml
│   ├── networks.yaml
│   └── storage.yaml
├── docs/
│   ├── appliance-recovery.md
│   ├── backend-migration.md
│   ├── onepassword-adoption.md
│   └── truenas-ownership.md
├── cloudflare.tf
├── dns.tf
├── image.tf
├── LICENSE
├── locals.tf
├── migrations.tf
├── onepassword.tf
├── outputs.tf
├── oci.tf
├── PLAN.md
├── providers.tf
├── README.md
├── renovate.json
├── scripts/
│   └── render_ssh_config.sh
├── tailscale.tf
├── talos.tf
├── terraform.tf
├── unifi.tf
├── truenas.tf
└── variables.tf
```

The repository root is the only OpenTofu root. Add a module only when repeated
resources have demonstrated a stable reusable interface.

## Implementation sequence

1. Finish the clean baseline on `main`.
   - Preserve `LICENSE` and `.mise.local.toml`.
   - Remove empty legacy directories.
   - Add lean repository guidance, ignores, compatible Mise tool ranges, Prek hooks,
     Renovate, and validation-only GitHub Actions.
   - Never put cloud or cluster credentials in GitHub Actions.

2. Add the non-live root `au` image configuration.
   - Configure GCS prefix `homelab` only after the separately reviewed
     migration from `states/homelab-kubernetes/au`.
   - Require `siderolabs/talos` `>= 0.11.0, < 0.12.0` and commit the resolved
     provider in the lock file.
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
     `truenas-nvme/virtual-machines`, UEFI, virtio NIC on `br4`, autostart, and
     fixed MAC `02:74:61:63:6f:01`.
   - Keep the Talos VM headless. The installed TrueNAS beta requires a display
     password and explicit distinct SPICE and web ports, while Talos maintenance
     and recovery use its network API. Do not put a display password in OpenTofu
     state solely to provide a console that the normal lifecycle does not use.
   - The substrate apply completed on 2026-08-14 with VM ID `10`, boot disk
     device `34`, network device `35`, and CD-ROM device `36`. The VM remains
     stopped. The uploaded Talos ISO is `479539200` bytes with SHA-256
     `b1a1b8223c9dfe70a8f575ab3ef97eb9071f9de3a7db311898fc7e25b9d65ebe`;
     the final provider-read-only plan reported no changes.
   - The first start attempt on 2026-08-15 failed before QEMU launched. On
     `26.0.0-BETA.2`, the confined `virt-aa-helper` cannot read the supported
     zvol path because it resolves to `/dev/zd0`, which the installed AppArmor
     policy explicitly denies. Taco remained stopped and created no DHCP lease.
     Do not weaken AppArmor or replace the stable zvol path with `/dev/zd0`.
     Until TrueNAS fixes the policy, the approved temporary exception is to use
     TrueNAS's exact generated domain XML with only
     `<seclabel type='none' model='apparmor'/>` added for taco. Start it through
     the private TrueNAS libvirt socket after initialising guest-memory
     accounting. Never disable AppArmor globally or apply this exception to
     another VM. On manual shutdown, release guest-memory accounting; after an
     upstream fix, let a normal TrueNAS start replace the temporary definition.
   - The temporary launch completed on 2026-08-15. Taco is running in Talos
     maintenance mode at reserved address `10.4.0.4`; pinned client and server
     both report `v1.13.8`. Talos was installed on 2026-08-15 to writable virtio
     disk `/dev/vda`, serial `2AxMXe9R`, reported as 69 GB decimal for the
     configured 64 GiB zvol. Authenticated verification found `STATE` on
     `/dev/vda3`, `EPHEMERAL` on `/dev/vda4`, and static hostname `taco`. The
     separately reviewed etcd bootstrap completed on 2026-08-15. Etcd, kubelet,
     the Talos API, and the container runtime are healthy; Kubernetes Node
     readiness is intentionally waiting for Cilium.

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

8. Stop at the home success gate before applying the OCI resources.
   - Prove node reboot, Talos and Kubernetes health, Flux recovery, private and
     public HTTP, TLS, secrets, static NFS persistence, and OpenSpeedTest.
   - The disposable legacy `au-hsp` stack was deleted on 2026-08-15. Create the
     replacement `hsp` stack only after this gate passes.

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
  while the retained resources are being adopted.
