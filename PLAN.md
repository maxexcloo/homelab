# OpenTofu Substrate Plan

This document is authoritative only for OpenTofu-managed infrastructure in the
`homelab` repository. The sibling `kubelab/PLAN.md` owns Kubernetes resources,
platform controllers, workloads, application integrations, migration order,
and the home success gate. When that external gate controls an OpenTofu action,
this plan records only the dependency and does not duplicate its checks.

## Scope

The root OpenTofu configuration owns:

- one GCS-backed state for the retained substrate;
- TrueNAS compute, storage, and adopted network interfaces;
- OCI network, image, storage, and compute resources;
- UniFi reservations and managed client metadata;
- Cloudflare infrastructure DNS, cluster tunnels, and recovery credentials;
- global Tailscale policy, retained-server keys, and cluster bootstrap
  identities;
- native 1Password delivery of infrastructure and recovery material;
- Talos Image Factory schematics, machine secrets, configuration, bootstrap,
  health, kubeconfig, and safe lifecycle operations; and
- infrastructure records for retained appliances such as TrueNAS, HAOS,
  Bazzite, and Hotdog.

This repository does not own Kubernetes API resources. Do not add Flux, Helm,
Gateway API, CNI, ingress, certificate, External Secrets, Crossplane, workload,
route, policy, claim, or application configuration here. Those resources and
their operational sequencing belong in `kubelab`.

The only cross-repository inputs retained here are:

- the Kubernetes version passed to Talos machine configuration; and
- the external home success gate that must pass before enabling `syd`.

`kubelab/PLAN.md` selects and validates those inputs. OpenTofu consumes them
without redefining their platform rationale.

## Naming and DNS

Use short, location-led infrastructure names with memorable food hostnames:

```text
<food>.<location>.excloo.net
```

Infrastructure-managed API records use:

```text
api.<location>.excloo.dev
```

The location labels are:

| Label | Location            |
| ----- | ------------------- |
| `mbk` | Meadowbank, Sydney  |
| `syd` | Sydney              |
| `fre` | Fremont, California |

Names describe location rather than provider. Do not add intermediate `infra`
or `k8s` labels, and do not use hyphens in new host or API labels.

| Machine  | Canonical FQDN          | Infrastructure role |
| -------- | ----------------------- | ------------------- |
| `hass`   | `hass.mbk.excloo.net`   | HAOS appliance      |
| `kimbap` | `kimbap.mbk.excloo.net` | TrueNAS appliance   |
| `mandu`  | `mandu.mbk.excloo.net`  | Bazzite host        |
| `taco`   | `taco.mbk.excloo.net`   | Home Talos node     |
| `hsp`    | `hsp.syd.excloo.net`    | OCI Talos node      |
| `hotdog` | `hotdog.fre.excloo.net` | ZFS.Rent host       |

The infrastructure-managed cluster API records are:

| Cluster | API FQDN             | Initial node |
| ------- | -------------------- | ------------ |
| `mbk`   | `api.mbk.excloo.dev` | `taco`       |
| `syd`   | `api.syd.excloo.dev` | `hsp`        |

Existing application records marked `Legacy` in Cloudflare remain outside
OpenTofu until their separate owner retires them. Never declare the same DNS
record in this repository and `kubelab`.

## Root and state boundary

The repository root is the only OpenTofu root. It uses:

- bucket `homelab-opentofu`;
- prefix `homelab`; and
- workspace `default`.

The bucket is an externally bootstrapped prerequisite. This root must never
manage the bucket that stores its active state. The legacy `states/core`
objects remain untouched historical evidence and must never be applied.

The 2026-08-15 read-only backend review confirmed versioning, uniform
bucket-level access, and enforced public-access prevention. The owner accepted
the current lack of retention and soft-delete protection and the existing
legacy bucket/object IAM roles for the initial build. Review those risks before
broadening state readership.

Treat anyone who can read OpenTofu state as able to read its secrets. Tailscale
keys, OAuth credentials, tunnel credentials, Talos machine secrets, and other
generated values are intentionally state-sensitive even where providers expose
write-only arguments.

Keep temporary `moved`, `removed`, and import blocks isolated from ordinary
resource definitions. Remove them only after a reviewed saved plan confirms
every transition is recorded in remote state.

## Configuration model

Keep the root direct and reviewable. Use ordinary provider resources and small
locals beside their consumers. Do not recreate the archived catalogue, JSON
schemas, inheritance, generators, deployment rendering, workflow dispatches,
or generic reconciliation modules.

Stable non-secret facts live in focused YAML inventories:

| File                    | Ownership                                                               |
| ----------------------- | ----------------------------------------------------------------------- |
| `data/machines.yaml`    | Durable machine identity and access facts                               |
| `data/deployments.yaml` | Provider placement and sizing                                           |
| `data/networks.yaml`    | UniFi and OCI network facts                                             |
| `data/clusters.yaml`    | Talos membership, versions, lifecycle, and machine configuration inputs |
| `data/domains.yaml`     | Cloudflare account and domain facts                                     |
| `data/dns/*.yaml`       | Manually curated infrastructure DNS records                             |
| `data/access.yaml`      | 1Password, SSH-agent, and Tailscale policy facts                        |
| `data/storage.yaml`     | Storage resources with an explicit target                               |

Do not add per-machine files, schemas, generated models, or application
definitions. Derive FQDNs, API records, tunnels, reservations, and credentials
from these inputs.

Use the same deployment shape across providers where concepts match:

- `compute.cores` for CPU;
- `compute.memory_mib` for memory; and
- `boot.size_mib` for boot storage.

Convert MiB only at provider boundaries that require another unit. Write-only
secret revisions default to `1` in HCL; add an optional revision only beside
the resource whose secret must be rewritten.

Every cluster declares `talos_enabled` explicitly. It gates Talos schematics,
secrets, configuration, recovery resources, and compute that requires Talos
metadata. A disabled cluster may retain infrastructure identities and access
foundations, but cannot enter the Talos lifecycle graph.

## Provider ownership

| Provider/domain | OpenTofu ownership                                                                                  |
| --------------- | --------------------------------------------------------------------------------------------------- |
| GCS             | Consume the external backend and manage only separately reviewed shared access resources            |
| TrueNAS         | Adopted `enp3s0` and `br4`, protected zvols, VMs, devices, datasets, snapshot tasks, and NFS shares |
| OCI             | Sydney VCN, subnet, routing, security, image bucket/object, custom image, and `hsp` instance        |
| UniFi           | Fixed-MAC reservations and explicitly adopted client metadata                                       |
| Cloudflare      | Infrastructure DNS, ACME tokens, cluster tunnels, and tunnel credentials                            |
| Tailscale       | Global ACL/grants, tag owners, reusable retained-server keys, and cluster OAuth identities          |
| 1Password       | Reviewed infrastructure access, bootstrap, and recovery items                                       |
| Talos           | Schematics, secrets, machine configuration, safe apply, bootstrap, health, and kubeconfig           |

Retained appliances are documented here only when OpenTofu owns a real
provider object or recovery contract. Do not create inventory-only resources.

## Archive decisions

The `archive/pre-kubernetes` branch remains design evidence. Retain:

- conventional root files such as `backend.tf`, `providers.tf`, `locals.tf`,
  `variables.tf`, and `outputs.tf` when they contain real configuration;
- one direct HCL file per provider or infrastructure domain;
- stable logical `for_each` keys;
- validation, lifecycle protection, sensitive outputs, and operational docs;
  and
- pinned tools, Prek, Renovate, and validation-only CI.

Do not restore:

- the repository-wide server/service catalogue and schema pipeline;
- generated application, dashboard, monitoring, or target-repository files;
- generic credential or object-storage modules;
- shell commands hidden behind `terraform_data`; or
- inventory-only resources.

The archived OCI code used Ubuntu, broad SSH ingress, generated cloud-init, and
catalogue-derived identity. Rebuild Sydney from direct current resources with
Talos, explicit network policy, non-overlapping `10.20.0.0/16` addressing, and
the durable `hsp.syd.excloo.net` identity.

On 2026-08-15 the disposable legacy `au-hsp` instance and its 160 GB boot
volume, subnet, NSG, route rules, internet gateway, VCN, derived IPs, resolver,
private DNS zones, and view were deleted outside OpenTofu at the owner's
request. Read-only verification found no remaining active compute, block
storage, custom image, VCN, or Object Storage resources. The old `states/core`
state is stale history only.

## Home TrueNAS substrate

Verified facts:

- TrueNAS is a WTR PRO with 16 CPU cores and about 64 GiB RAM, running
  `26.0.0-BETA.2` at inventory time;
- pools `truenas` and `truenas-nvme` are online;
- `eno1` is the unchanged `10.0.0.3/22` management path;
- `br4` owns `10.4.0.3/22` on the UniFi `Services` network;
- `enp3s0` is the sole `br4` member and has no address; and
- Taco uses reserved address `10.4.0.4` and MAC `02:74:61:63:6f:01`.

The bridge migration completed on 2026-08-14 as one staged TrueNAS API
transaction with a 120-second rollback window. Provider v2.4.1 cannot safely
perform that migration: empty `aliases` is omitted and each interface would be
committed separately. Both interfaces were imported after the manual staged
transaction. Do not retry the original two-resource bridge creation plan.

Provider import left the operation-only `rollback` value unset while the
schema planned `true`. That state metadata was normalised from a verified
backup because asking the provider to update it sent invalid unrelated fields.
Continue detecting drift in all live interface attributes.

The protected Taco VM substrate is:

- VM ID `10`;
- 12 vCPU and 32 GiB RAM;
- 64 GiB zvol `truenas-nvme/virtual-machines/taco`;
- UEFI, headless operation, and autostart;
- virtio boot device `34`, network device `35`, and CD-ROM device `36`; and
- fixed virtio NIC on `br4`.

The installed TrueNAS beta generated an AppArmor policy that denied the zvol
after it resolved to `/dev/zd0`. The approved temporary exception is Taco's
exact generated libvirt XML with only:

```xml
<seclabel type='none' model='apparmor'/>
```

Start it through the private TrueNAS libvirt socket after initialising guest
memory accounting. Never disable AppArmor globally, substitute `/dev/zd0` for
the provider-managed zvol path, or apply the exception to another VM. Remove
the exception after an upstream TrueNAS fix permits a normal start.

OpenTofu also owns the targeted NFS storage substrate on Kimbap:

- dataset `truenas-nvme/kubernetes` with LZ4, 128 KiB records, and atime off;
- NFS share restricted to `10.4.0.0/22`, using SYS and root/wheel maproot; and
- declared snapshot tasks from `data/storage.yaml`.

This plan owns only those TrueNAS resources. Consumption of the export belongs
in `kubelab`.

## Talos lifecycle

OpenTofu manages Talos as infrastructure through the official provider. The
fixed node identities are:

| Cluster | Node   | Substrate                 |
| ------- | ------ | ------------------------- |
| `mbk`   | `taco` | TrueNAS metal/amd64 VM    |
| `syd`   | `hsp`  | OCI oracle/arm64 instance |

Talos machine configuration consumes the cluster endpoint, Pod/Service CIDRs,
the externally approved Kubernetes version, machine type, install disk,
hostname, time sources, and system extensions. It schedules on the single
control-plane node and leaves CNI ownership to `kubelab` by setting
`cni.name: none`.

Every schematic contains `siderolabs/tailscale`. Taco additionally contains
`siderolabs/qemu-guest-agent`. Do not check content-addressed schematic IDs into
configuration.

Machine configuration uses write-only provider arguments, stores recovery
material in 1Password before apply, sets reset-on-destroy to false, and uses
`staged_if_needing_reboot`. Bootstrap is a one-time resource. Scope lifecycle
dependencies to the matching node or cluster.

The Meadowbank lifecycle completed on 2026-08-15:

- Talos `v1.13.8` installed to `/dev/vda`;
- `STATE` and `EPHEMERAL` partitions verified;
- hostname `taco` verified;
- etcd bootstrapped once;
- provider health check passed at `10.4.0.4`;
- administrator kubeconfig stored in 1Password; and
- a post-apply targeted plan reported no changes.

The local workstation kubeconfig is an operator concern and is not managed by
OpenTofu.

## Sydney rollout gate

`syd` remains declared with `talos_enabled: false`. Do not create its OCI
instance or Talos lifecycle until `kubelab/PLAN.md` records that the home
success gate has passed.

Infrastructure that may be reviewed before the gate must still be applied in
narrow stages. Do not let a Meadowbank recovery plan pull pending Sydney
schematics, secrets, compute, or recovery items into its graph.

Before OCI work resumes, fix local DNS for
`objectstorage.ap-sydney-1.oraclecloud.com`. The current filtered response
prevents the OCI provider from reaching Object Storage. Do not use the previous
temporary localhost CONNECT proxy for an apply.

After the external gate passes:

1. enable `syd` in `data/clusters.yaml` as its own reviewed change;
2. review the OCI network and security plan;
3. upload the pinned local Talos OCI image and create the custom image;
4. create the protected 64 GiB `hsp` instance from declared data;
5. apply Talos configuration and bootstrap in separately reviewed stages; and
6. store and verify Sydney recovery material before handoff to `kubelab`.

## Version baseline

Pin exact stable versions and let Renovate propose upgrades for manual review.

| Component                       | Version   |
| ------------------------------- | --------- |
| OpenTofu                        | `1.12.5`  |
| 1Password provider              | `3.3.1`   |
| Cloudflare provider             | `5.23.0`  |
| OCI provider                    | `8.27.0`  |
| TrueNAS provider                | `2.4.1`   |
| Talos provider                  | `0.11.0`  |
| Tailscale provider              | `0.29.2`  |
| UniFi provider                  | `0.55.0`  |
| Talos Linux                     | `v1.13.8` |
| Kubernetes machine-config input | `v1.36.3` |

The Kubernetes value is retained only because it is passed through OpenTofu to
Talos. Compatibility selection and platform upgrade ordering belong in
`kubelab/PLAN.md`.

Commit `.terraform.lock.hcl` with checksums for `darwin_arm64` and
`linux_amd64`. Use the stable Talos provider rather than the available alpha
series.

## Repository shape

All root HCL remains in the repository root. Add a module only after repeated
real resources demonstrate a stable reusable interface.

```text
.
├── .github/workflows/validate.yaml
├── .terraform.lock.hcl
├── AGENTS.md
├── PLAN.md
├── README.md
├── backend.tf
├── cloudflare.tf
├── data/
│   ├── access.yaml
│   ├── clusters.yaml
│   ├── deployments.yaml
│   ├── dns/
│   ├── domains.yaml
│   ├── machines.yaml
│   ├── networks.yaml
│   └── storage.yaml
├── dns.tf
├── image.tf
├── locals.tf
├── oci.tf
├── onepassword.tf
├── outputs.tf
├── providers.tf
├── tailscale.tf
├── talos.tf
├── terraform.tf
├── truenas.tf
├── unifi.tf
└── variables.tf
```

## Operator access

Use the 1Password SSH agent as the workstation source of SSH private keys.
OpenTofu must not create private SSH keys, store them in state, or write files
under an operator's home directory.

Keep non-secret SSH aliases, hostnames, users, ports, and jump relationships in
`data/machines.yaml`. A Mise task may render them to a temporary file and
install `~/.ssh/config.d/homelab` only on explicit request. Talos nodes do not
run SSH; access them with `talosctl`.

Every ownership transfer from `states/core` requires its own state backup,
address inventory, import or move procedure, saved plan, rollback notes, and
explicit approval.

## Apply order and current status

The implementation order is:

1. establish the pinned root, backend, lock file, validation, and inventories;
2. adopt or create access, DNS, network, storage, and retained-machine
   foundations in narrow reviewed stages;
3. adopt the TrueNAS bridge and protected Taco VM substrate;
4. apply the Meadowbank Talos lifecycle and recovery resources;
5. hand the healthy API and recovery material to `kubelab`;
6. wait for the external home success gate; and
7. enable and apply Sydney OCI and Talos resources in narrow stages.

Steps 1–5 are complete for Meadowbank. Step 6 is owned and evaluated in
`kubelab`. Step 7 has not started; pending Sydney resources are intentionally
absent from state.

The root is not expected to have a full no-op plan while the declared but
gated Sydney infrastructure remains pending. Use narrow saved plans and verify
the intended boundary explicitly.

## OpenTofu safety rules

- Never apply an unsaved or unreviewed OpenTofu plan.
- Apply exactly the reviewed saved plan after explicit approval.
- Never combine a backend change, import, state move, and resource mutation.
- Never use `tofu init -migrate-state` for routine initialisation.
- Treat state readers as secret readers.
- Use stable resource names and semantic `for_each` keys; never list indexes.
- Add `prevent_destroy` to retained substrate where supported.
- Do not use broad `ignore_changes` to conceal drift.
- Do not make routine destroy operations reset Talos nodes or delete retained
  data.
- Keep GitHub Actions validation-only; local trusted workstations perform
  applies.
- Keep plans, state, credentials, kubeconfigs, and recovery material out of
  Git.
- Run `mise run check` before handoff.
- Record one coherent outcome per commit.
- Preserve the archive branch and untouched `states/core` objects as historical
  rollback evidence until every ownership transfer and rollback window closes.
