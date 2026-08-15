# TrueNAS Ownership

OpenTofu owns the Kubernetes dataset and NFS share declared under the `kimbap`
target in `data/storage.yaml`. The target must resolve to the TrueNAS compute
host for this root. The share is restricted to the Meadowbank Services subnet.
It also adopts the two existing `truenas-nvme` snapshot schedules through the
temporary import blocks in `migrations.tf`.

The following existing jobs remain manually owned in TrueNAS:

- daily and monthly recursive snapshots of `truenas`;
- local replication from `truenas-nvme` to `truenas/truenas-nvme`;
- SSH replication of `truenas` to `hotdog/au-truenas/truenas`; and
- SSH replication of `truenas-nvme` to
  `hotdog/au-truenas/truenas-nvme`; and
- both existing pool scrub schedules.

The pinned provider cannot represent the HDD snapshot tasks' `.system`
exclusion or the replication jobs' links to periodic snapshot tasks. Its scrub
resource also requires a plan-known numeric pool ID and cannot consume its own
name-based pool lookup. Managing those resources would risk clearing live
settings or hard-code appliance database IDs, so their manual ownership is
deliberate rather than an adoption backlog.

Before the first storage apply, review a saved plan that imports task IDs 3 and
5 as the NVMe snapshot schedules. The new dataset and NFS share must appear as
creates; no existing task may appear as a replacement or deletion.

TrueNAS currently owns its `cloudflare` ACME authenticator, `truenas`
certificate, SMTP configuration, and UPS configuration manually. Their native
provider resources are either alpha or would place additional credential
material in OpenTofu state without improving recovery. Keep their non-secret
recovery facts in 1Password and do not create duplicates through OpenTofu.

The 2026-08-15 read-only inventory confirmed that SMTP is enabled and the UPS
service is enabled and running. No separate TrueNAS alert service or reporting
exporter exists. Keep appliance mail and UPS tests in the TrueNAS operating
procedure; add an exporter only when a concrete in-cluster monitoring consumer
is ready, with Flux owning that consumer.
