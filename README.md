# Homelab

OpenTofu manages the infrastructure needed to rebuild and reach the homelab's
Talos Kubernetes clusters. The separate `kubelab` repository owns Kubernetes
resources and application integrations, reconciled by Flux.

## Clusters

| Cluster | Node   | Host               | Storage                         |
| ------- | ------ | ------------------ | ------------------------------- |
| `mbk`   | `taco` | TrueNAS (`kimbap`) | NVMe-backed VM disk and NFS     |
| `syd`   | `hsp`  | OCI Ampere A1      | Boot and attached block volumes |

Both clusters have a single control-plane node. Allow for outages during upgrades.

## Quick Start

Install [Mise](https://mise.jdx.dev/) and the 1Password desktop app; `curl` and `shasum` must
also be available. In 1Password, enable **Settings > Developer > Integrate with
1Password CLI** and Touch ID under **Settings > Security**.

Existing provider accounts, the GCS backend, 1Password Connect, declared vaults,
TrueNAS pools and UniFi networks are prerequisites. Then run:

```shell
mise trust
mise run setup
mise run check
```

Setup installs the pinned tools, initialises providers and installs Git hooks.
It creates the `Homelab/OpenTofu` item schema if missing; populate every field
and rerun setup if it does. Existing items are left untouched.

Credential-consuming tasks resolve that item's complete provider environment
through desktop authorisation. Resolved values are inherited by the task and its
children, including the image preparation script. Connect credentials use
underscore-prefixed names until the OpenTofu wrapper exports `OP_CONNECT_HOST`
and `OP_CONNECT_TOKEN`; they are not resolved in the parent shell.
CI validates configuration; plans and applies run locally and require review of
the exact plan and explicit approval.

TrueNAS connections are stored as JSON in the concealed `truenas_connections`
field of `Homelab/OpenTofu`, keyed by the machine names in `data/machines.yaml`:

```json
{
  "kimbap": {
    "api_key": "<API key>",
    "url": "https://<TrueNAS API endpoint>"
  }
}
```

For an existing OpenTofu item, add this field manually using the existing
`truenas_api_key` and `truenas_url` values for `kimbap`, then remove the old fields.
Setup leaves existing items untouched. Add one connection entry per TrueNAS host;
provider aliases remain keyed by machine name.

### Common Tasks

| Task                             | Purpose                                              |
| -------------------------------- | ---------------------------------------------------- |
| `mise run apply`                 | Review the presented plan and apply approved changes |
| `mise run check`                 | Run all repository checks                            |
| `mise run client-configs`        | Sync Kubernetes and Talos client configurations      |
| `mise run fmt`                   | Format repository files                              |
| `mise run ignition`              | Render uCore installation files                      |
| `mise run init`                  | Initialise providers and the remote backend          |
| `mise run plan`                  | Preview infrastructure changes                       |
| `mise run prepare-oci-image syd` | Download the Talos OCI image                         |
| `mise run setup`                 | Set up the workstation                               |
| `mise run ssh-config`            | Install SSH aliases                                  |

For credential-free validation on a fresh checkout, run `mise run init-ci` before
`mise run check`. Provider updates require reinitialisation with `mise run init`.

Commit hooks check relevant changed files. Full checks and CI run the same hook
suite, including validation of embedded Butane inputs. These are offline checks;
OpenTofu preconditions and live provider compatibility still need a requested
plan. Passing `check` does not establish that an apply is safe.

### Workstation Access

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

## Substrate

- **DNS & Ingress**: Cluster DNS targets, ACME DNS challenge tokens, Cloudflare Tunnels, stable external-service records and the webhook-only HAOS tunnel route; application DNS remains workload-owned in `kubelab`.
- **Mesh & Access**: Server login items with management or SSH URLs, Tailscale grants and host recovery keys, and Kubernetes operator OAuth clients. Tagged devices share a full Tailscale mesh, while admin identities can reach the full tailnet and use approved exit nodes.
- **Networking**: Validate existing UniFi VLANs and manage static DHCP reservations for retained appliances and VMs.
- **Secrets**: 1Password items in `Homelab`, `Cluster: mbk` and `Cluster: syd`.
- **Storage**: Backblaze B2 appliance backup buckets, TrueNAS NVMe datasets and NFS shares for retained Kubernetes data, plus attached OCI block storage for replaceable `syd` volumes.

Each cluster vault receives B2, Cloudflare WAF and Resend control credentials,
plus an empty Control D item whose password must be populated manually. Items
use unqualified titles and the `Homelab` tag. After Connect bootstrap, External
Secrets delivers them to `kubelab` for application integrations.

Managed 1Password password and note versions use timestamps captured when their
non-secret identity or configuration fingerprint changes. The pinned provider
requires an increasing write-only version; a content hash alone cannot guarantee
that. The version offset keeps timestamps above the previously used fingerprints.
Separate tracking resources preserve dependency ordering, including writing Talos
recovery material before configuring nodes. Retain this tracking across rotations.
The manually populated Control D password stays at version zero.

The first apply after adopting timestamp tracking republishes the affected values
and generates new machine-login passwords. Review these item updates in the plan;
updating a login item does not change the corresponding host's password.

B2 credentials cannot directly access object data or delete buckets, but their
`writeKeys` capability can mint broader keys and is effectively full-account
access. Resend credentials also have full access to create application keys.

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

## Operations

Storage datasets and recovery items use `prevent_destroy`. Keep credentials,
state, plans and recovery material outside Git.

### Backend State & Recovery

State lives in the externally managed GCS bucket `homelab-opentofu`, prefix
`homelab`, default workspace. This root must not manage its backend.

The last read-only backend review on 15 August 2026 confirmed object versioning,
uniform bucket-level access, and public-access prevention. It also confirmed
that retention and soft-delete protection were not enabled and that legacy
bucket and object IAM roles remained. Review those accepted risks before
broadening state access.

The archived `states/core` prefix is stale historical evidence. Never migrate
it into `homelab`, apply the archived branch against it, or delete its objects as
part of a routine substrate change.

Treat every state reader as a secret reader: redacted plan output does not
remove credentials from state. Restrict recovery material to its operator.

1. Stop plans and applies. Record the operator, OpenTofu version, workspace and
   affected GCS generation; save the current `tofu state list`.
2. Securely copy the current and selected historical generations outside Git.
3. Restore the selected generation at the same location, then compare the
   resource list with the saved list.
4. Review a refresh-only plan and obtain explicit approval before corrective apply.

Never use `tofu init -migrate-state` for recovery. Before `tofu force-unlock`,
verify the lock holder, process, and timestamp and prove that no apply is still
running.

### Cluster Installation

For an initial TrueNAS installation, download the cluster's Image Factory ISO to
the path declared by `truenas_virtual_machine_cdrom_devices`, then boot the VM.
For OCI, use `mise run prepare-oci-image syd` and export the printed
`TF_VAR_oci_talos_image_path` before planning the first upload. If state has no
cluster outputs yet, pass the QCOW2 URL from [Image Factory](https://factory.talos.dev/)
to `mise run prepare-oci-image` instead. Select the architecture, version and
extensions from `data/clusters.yaml`. Every installation apply needs its own
reviewed plan; there is no automatic bootstrap apply.

Prepared images are cached under a SHA-256 hash of their URL, keeping different
versions and schematics separate even when their filenames match.

Image Factory supplies QCOW2 directly. Other raw image URLs require `qemu-img`
and the appropriate `gzip` or `xz` decompressor for local conversion.

### Cluster Upgrades

For an existing cluster, review the [Talos upgrade instructions](https://docs.siderolabs.com/talos/v1.14/configure-your-talos-cluster/lifecycle-management/upgrading-talos)
and [Kubernetes upgrade instructions](https://docs.siderolabs.com/kubernetes-guides/advanced-guides/upgrading-kubernetes/)
before setting the desired versions in `data/clusters.yaml`. Upgrade one cluster
at a time:

1. Obtain approval for the upgrade and outage. Verify access to the 1Password
   recovery item and take an etcd snapshot outside Git.
2. Upgrade Talos with the Image Factory installer matching the cluster's schematic
   and desired version. Verify node health before continuing.
3. Upgrade Kubernetes and verify node health again.
4. Review and approve the OpenTofu reconciliation plan before applying it.

Commands for steps 1–3:

```shell
talosctl --context <cluster> --nodes <node-ip> version
talosctl --context <cluster> --nodes <node-ip> etcd snapshot <secure-backup-path>
talosctl --context <cluster> --nodes <node-ip> upgrade --image <installer-image>
kubectl --context <cluster> get nodes -o wide
talosctl --context <cluster> --nodes <node-ip> upgrade-k8s --to <kubernetes-version>
kubectl --context <cluster> get nodes -o wide
```

Changing desired versions or the installer image does not upgrade a running
node. Installation media is bootstrap-only, and existing `clusters` outputs may
still contain the previous installer image. Obtain the desired image from Image
Factory; do not substitute an ordinary apply for the upgrade sequence.

Machine configuration uses Talos 1.14 documents for DNS, Kubernetes networking
and node scheduling. Configuration applies use `no_reboot`; changes requiring a
reboot must be handled separately during an approved maintenance window.

### Dependency Updates

Renovate proposes tool, provider, hook, action and Quadlet image updates for
manual review. Routine development tool, hook and action updates are grouped
weekly on Mondays (UTC); major updates, OpenTofu and cluster upgrades remain
separate. Two narrow rules cover the custom cluster-version YAML fields and
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

Each Butane file under `hosts/` embeds shared `common/etc/` configuration and
its host's `etc/` overlay. Deliver credentials from 1Password at deployment time;
keep generated identities, certificates, application state and system caches
out of Git.

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

Cockpit certificate renewal runs as a shared one-shot `acme.sh` Quadlet. Initial
issuance and certificate-path registration remain a one-time deployment step
because they require the host's scoped Cloudflare token.

## Licence

AGPL-3.0 - see [LICENSE](LICENSE).
