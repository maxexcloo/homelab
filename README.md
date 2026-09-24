# Homelab

Homelab infrastructure and Talos Kubernetes cluster substrate managed with OpenTofu.
In-cluster Kubernetes resources and platform workloads live in the separate `kubelab`
repository reconciled by Flux.

## Clusters

- **`mbk`**: Single-node Talos Kubernetes substrate running as a virtual machine on
  TrueNAS (`kimbap`) with NVMe-backed NFS storage.
- **`syd`**: Independent cloud Talos Kubernetes node running on Oracle Cloud
  Infrastructure (OCI) Ampere A1.

## Quick Start

Tooling is pinned and managed through [Mise](https://mise.jdx.dev/):

In the 1Password desktop app, enable **Settings > Developer > Integrate with
1Password CLI** and enable Touch ID under **Settings > Security**. Then run:

```shell
mise trust
mise run setup
mise run check
```

Setup creates the `OpenTofu` item schema in the `Homelab` vault when it is
missing and leaves an existing item untouched. If it creates the item, populate
every field and rerun setup before planning or applying. Credential-consuming
tasks request desktop authorisation and resolve the complete provider
environment from that item. The Connect credentials are exposed only to the
OpenTofu subprocess. Existing provider accounts, the GCS backend, 1Password
Connect, the declared vaults, TrueNAS pools and UniFi networks are prerequisites.
OpenTofu creates the scoped service credentials and empty
Control D items stored in those vaults; populate the Control D passwords in the
cluster vaults when ready.

### Common Tasks

| Task                         | Description                                                      |
| ---------------------------- | ---------------------------------------------------------------- |
| `mise run apply`             | Apply OpenTofu changes after reviewing the presented plan        |
| `mise run check`             | Run formatting and configuration validation                      |
| `mise run client-configs`    | Sync local `kubeconfig` and `talosconfig` from 1Password         |
| `mise run fmt`               | Format repository files (OpenTofu and Prettier)                  |
| `mise run ignition`          | Render installation Ignition files for every uCore host          |
| `mise run init`              | Initialise providers and the remote backend                      |
| `mise run opentofu-item`     | Create the OpenTofu 1Password item if missing                    |
| `mise run plan`              | Plan OpenTofu changes                                            |
| `mise run prek`              | Run all Git pre-commit hooks across the repository               |
| `mise run prepare-oci-image` | Download a Talos OCI QCOW2 image                                 |
| `mise run setup`             | Install pinned tools, providers, and Git hooks                   |
| `mise run ssh-config`        | Render and install SSH host aliases to `~/.ssh/config.d/homelab` |

### Prerequisites

Mise installs 1Password CLI (`op`), Actionlint, Butane, `jq`, `kubectl`, OpenTofu,
Prek, Prettier, ShellCheck, Talosctl, and yq. The workstation must also have the
1Password desktop app with CLI integration enabled and the operating system's
`curl`. Image Factory generates QCOW2 images directly. Explicit raw image URLs
from other sources still support local conversion with `qemu-img` and `gzip` or
`xz` when those tools are installed.

For credential-free validation on a fresh checkout, run `mise run init-ci` before
`mise run check`. Provider updates require reinitialisation with `mise run init`.

After `mise run ssh-config`, add this near the start of `~/.ssh/config`:

```sshconfig
Include config.d/homelab
```

Connect with an alias such as `ssh mbk-bento`. `mise run client-configs` merges
cluster credentials into the existing Kubernetes and Talos configurations,
preserves unrelated contexts, and backs up each destination as `.bak`.

## Repository Map

Start with the input for the thing you want to change, then read its domain HCL.
`locals.tf` decodes shared inputs and derives machine identities; each domain
file contains its own lookups, derived values and direct provider resources.

| Input                | Purpose                                                 | Main consumers                                 |
| -------------------- | ------------------------------------------------------- | ---------------------------------------------- |
| `data/access.yaml`   | Vault names, SSH agent and Tailscale policy             | `onepassword.tf`, `tailscale.tf`, SSH renderer |
| `data/clusters.yaml` | Cluster membership, desired versions and Talos settings | `talos.tf`, `oci.tf`                           |
| `data/dns/*.yaml`    | Explicit infrastructure DNS records                     | `dns.tf`, `cloudflare.tf`                      |
| `data/domains.yaml`  | Domain roles, credentials and tunnel routes             | `cloudflare.tf`, `dns.tf`                      |
| `data/machines.yaml` | Machine identity, interfaces and compute                | `oci.tf`, `truenas.tf`, `unifi.tf`             |
| `data/networks.yaml` | Existing UniFi subnets and managed OCI networking       | `oci.tf`, `unifi.tf`                           |
| `data/storage.yaml`  | Backup buckets, datasets and NFS exports                | `backblaze.tf`, `truenas.tf`                   |
| `hosts/`             | uCore installation and service configuration            | Butane                                         |

The scripts contain only repository-specific glue: creating the provider item,
fetching and merging client configurations, rendering SSH aliases, and choosing
an image download from cluster outputs. Native tools perform secret reads,
Kubernetes merging, Ignition rendering and image generation. The Talos context
merge uses yq because `talosctl config merge` renames conflicting contexts instead
of refreshing them.

## Substrate

- **Compute & Virtualisation**: TrueNAS VM (`taco`) on `kimbap` and OCI compute instance (`hsp`) on Ampere A1.
- **DNS & Ingress**: Cluster DNS targets, ACME DNS challenge tokens, Cloudflare Tunnels, stable external-service records and the webhook-only HAOS tunnel route; application DNS remains workload-owned in `kubelab`.
- **Mesh & Access**: Server login items with management or SSH URLs, Tailscale ACL policies and host recovery keys, and Kubernetes operator OAuth clients. Tagged devices share a full Tailscale mesh, while admin identities can reach the full tailnet and use approved exit nodes.
- **Networking**: Validate existing UniFi VLANs and manage static DHCP reservations for retained appliances and VMs.
- **Secrets Management**: 1Password native item delivery into scoped vaults (`Homelab`, `Cluster: mbk`, `Cluster: syd`).
- **Storage**: Backblaze B2 appliance backup buckets, TrueNAS NVMe datasets and NFS shares for retained Kubernetes data, plus attached OCI block storage for replaceable `syd` volumes.

The root creates B2, Cloudflare WAF, and Resend control credentials for each
configured cluster and an empty Control D login item in each cluster vault. The
operator populates the Control D password manually. The root stores every
credential as an unqualified, `Homelab`-tagged item in the corresponding cluster
vault, so External Secrets can materialise them after the one-time 1Password
Connect bootstrap. B2 cluster credentials can manage buckets and application
keys but cannot access object data or delete buckets directly. Backblaze
nevertheless treats `writeKeys` as full-account-equivalent because it can mint
broader application keys. Resend credentials have full access because `kubelab`
uses them to create application-scoped credentials. Those application resources
and credentials remain owned by `kubelab` in the same cluster vault.

OCI TCP ingress rules declare a `mode` in `data/networks.yaml`. `tailscale` and
`cloudflared` keep the OCI firewall closed and delegate ingress to their private
overlay or tunnel. `public` creates only the explicitly configured OCI NSG rules;
the corresponding application route and DNS record remain owned by `kubelab`.
Subnets attach an empty managed security list so the default VCN security list
cannot add permissions outside the node NSGs.
The NSGs also allow ICMP packet-too-big messages needed for path MTU discovery.

A machine's Tailscale device name is derived as `<network>-<hostname>`.
Infrastructure DNS records are created when a matching live device supplies
the corresponding address.

## Operations & Safety

- **Destruction Guards**: Storage datasets and recovery items enforce `prevent_destroy` to safeguard live substrate.
- **Local Execution**: CI validates formatting and configuration; all plans and applies run locally from trusted workstations.
- **Safe State**: State is stored in versioned Google Cloud Storage outside the root that consumes it.
- **Secret Loading**: Credential-consuming Mise tasks authenticate through the 1Password desktop app and resolve tracked references only for their subprocess.

### Backend State & Recovery

The root uses the externally bootstrapped `homelab-opentofu` Google Cloud
Storage bucket, prefix `homelab`, and default workspace. The root must never
manage the bucket that stores its active state.

The last read-only backend review on 15 August 2026 confirmed object versioning,
uniform bucket-level access, and public-access prevention. It also confirmed
that retention and soft-delete protection were not enabled and that legacy
bucket and object IAM roles remained. Review those accepted risks before
broadening state access.

The archived `states/core` prefix is stale historical evidence. Never migrate
it into `homelab`, apply the archived branch against it, or delete its objects as
part of a routine substrate change.

Treat every state reader as a secret reader. State contains generated Backblaze
B2, Cloudflare, Resend, Talos, Tailscale, and other credentials even when plan
output is redacted. Keep state, plans, backups, and recovery material outside
Git and restrict them to the operator performing the recovery.

To recover state:

1. Freeze plans and applies for this root.
2. Record the affected GCS object generation, OpenTofu version, workspace, and
   operator.
3. Copy the current and selected historical object generations to secure
   storage outside the repository.
4. Restore the selected generation in GCS without changing the backend prefix.
5. Compare `tofu state list` before and after restoration.
6. Run a refresh-only plan, review every change, and obtain explicit approval
   before any corrective apply.

Never use `tofu init -migrate-state` for recovery. Before `tofu force-unlock`,
verify the lock holder, process, and timestamp and prove that no apply is still
running.

### Cluster Installation & Upgrades

For an initial TrueNAS installation, download the cluster's Image Factory ISO to
the path declared by `truenas_virtual_machine_cdrom_devices`, then boot the VM.
For OCI, use `mise run prepare-oci-image syd` and export the printed
`TF_VAR_oci_talos_image_path` before planning the first upload. If state has no
cluster outputs yet, pass the QCOW2 URL from [Image Factory](https://factory.talos.dev/)
to `mise run prepare-oci-image` instead. Select the architecture, version and
extensions from `data/clusters.yaml`. Every installation apply needs its own
reviewed plan; there is no automatic bootstrap apply.

Versions in `data/clusters.yaml` are desired configuration, not evidence of the
running versions. Changing `machine.install.image` does not upgrade an installed
Talos node. Retained OCI images and TrueNAS installation media are bootstrap-only.

For an existing cluster, review the [Talos upgrade instructions](https://docs.siderolabs.com/talos/v1.14/configure-your-talos-cluster/lifecycle-management/upgrading-talos)
and [Kubernetes upgrade instructions](https://docs.siderolabs.com/kubernetes-guides/advanced-guides/upgrading-kubernetes/)
before changing versions. Upgrade Talos first, then Kubernetes, one cluster at a
time. Both clusters have one control plane, so allow for an outage and keep an
etcd snapshot and the 1Password recovery item available outside Git.

Use the cluster context, node address and desired Image Factory installer image:

```shell
talosctl --context <cluster> --nodes <node-ip> version
talosctl --context <cluster> --nodes <node-ip> etcd snapshot <secure-backup-path>
talosctl --context <cluster> --nodes <node-ip> upgrade --image <installer-image>
talosctl --context <cluster> --nodes <node-ip> upgrade-k8s --to <kubernetes-version>
kubectl --context <cluster> get nodes -o wide
```

The image must match the cluster's schematic and desired Talos version. Obtain
it from Image Factory; an existing `clusters` output may still describe the
previous version until configuration is reconciled. Confirm node health after
each upgrade, then review and apply the OpenTofu reconciliation plan. Do not use
a routine configuration apply to bypass Kubernetes' sequenced upgrade procedure.

### Dependency Updates

Renovate proposes tool, provider, hook, action and Quadlet image updates for
manual review. Two narrow rules cover the custom cluster-version YAML fields and
group those changes with their CLIs. Review major provider release notes and
cluster compatibility before applying updates. Regenerate provider checksums for
both workstation and CI platforms with:

```shell
mise exec -- tofu providers lock -platform=darwin_arm64 -platform=linux_amd64
```

Host container versions are pinned and deployed deliberately. uCore's `stable`
references remain its supported OS update channel; they are not immutable release
pins. No live host or cluster upgrades run from CI.

### Host Installation

Non-secret uCore host configuration lives under `hosts/`. Each Butane file
embeds `common/etc/` and its host's `etc/` overlay. Generated Cloudflare tokens,
certificates, and other credentials are deliberately excluded and delivered
from 1Password at deployment time.

The `bento` and `hotdog` Butane files use uCore's two-stage automatic rebase:
Fedora CoreOS first rebases to the unverified OCI reference, then rebases to
the signed reference after reboot. Bento targets `ucore-hci:stable`; Hotdog
targets `ucore:stable`. Render complete installation Ignition files with:

```shell
mise run ignition
```

Butane writes one file per host to
`${XDG_CACHE_HOME:-$HOME/.cache}/homelab/ignition/`. Set
`IGNITION_OUTPUT_DIRECTORY` to choose another destination. To render a single
host, use Butane directly:

```shell
mise exec -- butane --files-dir hosts --pretty --strict hosts/bento/bento.bu --output /tmp/bento.ign
```

The `hosts/common/etc/` tree contains shared server overrides. Each
`hosts/HOST/etc/` tree contains only role- or hardware-specific differences.
Generated identity, certificate, token, application state, SELinux, and ZFS
cache files are not source configuration and must not be copied into Git.
Cockpit certificate renewal runs as a shared one-shot `acme.sh` Quadlet. Initial
issuance and certificate-path registration remain a one-time deployment step
because they require the host's scoped Cloudflare token.

## Licence

AGPL-3.0 - see [LICENSE](LICENSE).
