# Bento Talos Conversion

This is a proposed conversion procedure. Preparing or reviewing its pull requests
does not authorise installation, an apply, a reboot, a drain, a disk write or a
change to kimbap. Keep both PRs unmerged until their prerequisites are satisfied
and the conversion is separately approved. Kubelab reconciles `main` automatically.

## Target & Ownership

Keep bento as the `syd` cluster's dedicated GPU worker, with the same hostname,
GPU taint, AMD DRA claims, ComfyUI images and application paths. Install native
Talos on mandu's released Kingston OM8PGP42048N-A0 2 TB. Retain bento's Crucial
P3 Plus CT1000P3PSSD8 1 TB as the original bootable rollback disk.

Homelab owns the amd64/metal Image Factory profile, Talos machine configuration,
Tailscale access, hardware settings and disk layout. Kubelab owns application
manifests, monitoring and the read-only model publisher. The existing arm64/Oracle
image and other cluster nodes are unchanged.

The new disk has a 200 GiB maximum EPHEMERAL partition for runtime images and
logs, a growing XFS `datasets` user partition for application data, and the
existing local-path directory volume. The data partition selects `system_disk`,
so attaching the old disk does not make it a provisioning target. Applications
continue to use `/var/mnt/datasets/ai`.
The data volume preserves executable mounts for the workers' cache directories;
Talos's default secure user-volume mount would otherwise add `noexec`.

## Prerequisites & Review Gates

1. Finish and verify kimbap's ZFS restore. Its native apps and Talos control plane
   are intentionally stopped; do not attempt recovery as part of this task.
2. Consolidate mandu onto the spare Lexar NM790 4 TB and verify its replacement
   workflows before releasing its Kingston disk. All disk operations stay
   sequential. No purchases, MacBook changes, host renaming or hotdog encryption.
3. Verify kimbap's model library after the restore. The native **AI Model Library
   Mirror** is documented as copying `ai/models/` to `/mnt/truenas/ai/`; do not
   infer its completeness or treat it as a backup of other directories.
4. Decide what to retain from bento's `ai/radiance/data` (about 19 GiB), ComfyUI
   cache/configuration/input/output/user directories (about 1.1 GiB), and other
   home-directory data. Models occupy about 691 GiB. Keep the original disk even
   when starting fresh. These sizes are observations, not acceptance checks.
5. Resolve display parity before approving conversion. The running TRCC daemon
   has no verified published OCI image; package its pinned release in its owning
   application repository and qualify USB access, sensors and persistent state.
   Preserve intended front-panel monitoring as well: the old btop service was
   failed at inspection. Talos's dashboard is a possible replacement only if
   explicitly accepted. These PRs do not supply a TRCC image or claim parity.
6. Reconcile the independent Mercury work into the Homelab PR before merge.
   Preserve its staged and unstaged changes. Retain the uCore installation recipe
   and old-disk credentials until acceptance; native Talos is excluded from host
   sync and SSH alias generation.

## Prepare The Conversion

Once the prerequisites pass and the maintenance is approved:

1. Record the running worker replica counts and any pending jobs. Repository
   defaults stop GPU workers on release upgrades; record the actual runtime
   state rather than assuming those defaults are the desired restart state.
2. Verify access to **Talos Recovery: syd** and the existing client configuration
   without printing their secret fields. Verify local console/recovery access;
   a NanoKVMPro USB device was observed, but remote recovery was not exercised.
3. Generate the amd64/metal boot media with the extensions from bento's image
   profile in `data/clusters.yaml`, at the pinned Talos version. Use the same
   schematic for boot media and installer. Do not use the cluster's Oracle image.
4. Review the current disk identity against the configured Kingston model
   selector. If the reported model differs, correct the selector and review it
   before proceeding. Confirm that exactly the intended replacement matches.
5. Request and review an OpenTofu plan at this point. The apply must retain
   cluster secrets, preserve the existing OCI image, avoid resets, and move only
   bento's machine-configuration address from `container` to `node`. Do not
   execute unrelated imports or storage changes present in the root. Keep any
   unrelated state procedure separate. These PR preparations run no plan.

The `moved` block preserves bento's OpenTofu resource identity; it does not migrate
its container runtime, install Talos or transfer node data. Both configuration
resources retain `on_destroy.reset = false`.

## Install & Restore

1. In the approved window, stop accepting new GPU jobs, stop the workers, pause
   the native model mirror and drain bento. Shut down uCore cleanly so its XFS
   filesystem does not need journal recovery. Disconnect the Crucial disk.
2. Replace it with the released Kingston and boot the prepared Talos media.
   Confirm wired network access, disk identity and both R9700s before approving
   configuration delivery. Stop if the expected hardware is absent.
3. Retire the stopped container worker's Kubernetes Node object and stale GPU
   claims only after reviewing their consumers. The replacement must register
   without the old `node.excloo.dev/container` label. Do not run two nodes named
   bento or copy the old Talos Podman volumes into the native installation.
4. Deliver the reviewed configuration through the direct LAN endpoint. Bootstrap
   uses the machine address from inventory before the new Tailscale identity
   exists. The first apply discovers devices before the new identity registers,
   so its DNS and client inventory can still refer to the old host. Keep LAN
   access, confirm the new tailnet identity, then request and review a second
   reconciliation plan. Apply that reviewed reconciliation and sync client
   configurations before relying on the FQDN or remote access. Do not bootstrap
   a new control plane or rotate cluster secrets.
5. Verify the `datasets` volume and the intended system/data partition sizes.
   Keep workers stopped until their data and model directories are ready.
6. Attach the original Crucial disk over USB. Discover it by hardware identity
   and filesystem UUID, not `/dev/sdX` or a broad non-system-disk selector. Its
   inspected XFS UUID is `497dbef7-b564-4805-9cea-d5f8c8967f08`; reverify it.
   Use a temporary `ExistingVolumeConfig` named `bento-original`, with
   `discovery.volumeSelector.match` selecting that UUID and `mount.readOnly: true`.
   Never reformat it or repair its journal as incidental migration work.
7. Expose `/var/mnt/bento-original` read-only to a temporary, bento-pinned copy
   pod and the destination volume read-write. The source AI directory is
   **`ostree/deploy/fedora-coreos/var/home/core/ai` relative to the XFS root**,
   verified with `findmnt`; it is not the old live `/var` bind mount. Copy only
   the agreed data, preserving ownership, modes and symbolic links.
8. Restore models from verified kimbap storage or the retained USB disk. Compare
   the selected source and destination before starting applications. Do not
   move SQLite/user configuration to NFS or copy containerd's image cache.
9. Remove the temporary copy pod and existing-volume configuration after the
   copy passes verification, then disconnect and retain the original disk.

## Restore Mirroring & Verify Behaviour

Kubelab's `ai-models` publisher exports only the models directory read-only.
It listens on the node's Tailscale address at port 10873, using the `models`
rsync module. It has no public ingress or LAN listener. Homelab restricts the
node IP to Tailscale addresses; verify that dependency after registration.

After kimbap is healthy and the change is approved, change its existing native
mirror from SSH pull to rsync-module pull. Use bento's configured infrastructure
hostname, module `models` and port 10873; preserve `/mnt/truenas/ai/`, the
15-minute schedule and the existing exclusion/deletion policy. Verify a dry run
before enabling the schedule. The TrueNAS task remains native and is not changed
by either PR. Initial restore and ongoing mirror traffic have opposite directions.

Acceptance requires all of the following:

- Both R9700s expose KFD/render devices through the native Talos kernel and AMD
  DRA; the integrated display GPU remains excluded by the existing DeviceClass.
- One-GPU image and video workflows, then the two-GPU video workflow, produce
  expected outputs through Studio. Verify exclusive allocation, shared inputs,
  model downloads and persistence. Release conflicting claims between cases.
- The two 210 W caps hold after driver initialisation and an approved reboot.
- Existing application routes, Tailscale connectivity, cluster DNS and Cilium
  cross-node traffic work, without adding public exposure.
- Beszel and VictoriaLogs report the native node; Beszel measures its wired
  interfaces. Preserve TRCC/front-panel behaviour agreed at the review gate.
- Reboot, GPU claim preparation, data mounts and application restart work. Test
  this with the control plane healthy; do not assume surviving processes during
  a control-plane outage demonstrate recoverability.
- A model downloaded through Studio reaches the existing kimbap mirror. Check
  the intended source/destination and policy before any deletion-enabled run.

After acceptance, separately review retiring the old uCore recipe and its retained
login, mail and ACME credentials. Remove completed migration blocks only after
verifying the managed state. Keep the original disk until all agreed replacement
workflows pass.

## Rollback

Stop new workloads and preserve any writes made after cutover. Shut down Talos,
disconnect the Kingston, and reinstall the untouched Crucial as the boot disk.
Stop the new tailnet identity from serving traffic before the original worker
returns. Never run both identities as bento simultaneously.

Reconcile worker registration, DNS, model-mirror transport and repository state
with the restored uCore arrangement through a reviewed rollback. Reverse the
OpenTofu address move through its own reviewed migration rather than resetting
either disk. Restore the recorded worker counts only after data and GPU checks.
Swapping disks restores the old OS and its data at shutdown time; it does not
preserve writes made on the Kingston after cutover.

## Compatibility Evidence

- [Talos v1.14.5](https://github.com/siderolabs/talos/releases/tag/v1.14.5) uses
  Linux 6.18.58; the working container shared Fedora's 7.2.7 kernel. Native boot,
  NIC and GPU behaviour remain qualification requirements.
- [Official extensions](https://github.com/siderolabs/extensions/blob/main/README.md)
  include AMDGPU modules/firmware, AMD microcode, Realtek firmware and Tailscale.
- [AMD DRA](https://github.com/ROCm/k8s-gpu-dra-driver/blob/main/docs/installation.md)
  requires host `amdgpu` support. Retain Kubelab's `/run/cdi` setting.
- [Talos volumes](https://docs.siderolabs.com/talos/v1.14/reference/configuration/block/uservolumeconfig)
  and [existing volumes](https://docs.siderolabs.com/talos/v1.14/reference/configuration/block/existingvolumeconfig)
  provide the new local data partition and explicit read-only USB source.
- [TRCC](https://github.com/Lexonight1/thermalright-trcc-linux)
  provides native packages/Python installation; a deployable image and behaviour
  on Talos have not been established by this investigation.
