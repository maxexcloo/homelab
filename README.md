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
Define cluster membership in `data/clusters.yaml` under `nodes`.

## Quick Start

Install [Mise](https://mise.jdx.dev/), jq (`brew install jq` on macOS) and the
1Password desktop app; `curl` and `shasum` must also be available. In 1Password, enable **Settings > Developer > Integrate with
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

Credential-consuming tasks resolve `Homelab/OpenTofu` through the 1Password
desktop app, keeping credentials out of the parent shell. Plans and applies run
locally; every apply requires review of its exact plan and explicit approval.

After validating a push to `main`, CI dispatches `flylab` to refresh external
monitoring at that commit. Set the Actions secret `HOMELAB_FLY_DEPLOY_TOKEN` to
a token with Actions write access to `maxexcloo/flylab`. Keep its recovery copy at
`op://Homelab/GitHub Actions/homelab-fly-deploy-token` and update the secret on rotation.

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

Add one connection entry per TrueNAS host.

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
`mise run check`. CI uses the committed provider lockfile without modifying it.
Provider updates require reinitialisation with `mise run init`.

Commit hooks check changed files; `check` and CI run the full suite, including
Butane validation. These static checks do not verify live provider behaviour or
OpenTofu preconditions; those require a requested plan.

### Workstation Access

After `mise run ssh-config`, add this near the start of `~/.ssh/config`:

```sshconfig
Include config.d/homelab
```

Use SSH aliases such as `ssh kimbap` or `ssh mbk-kimbap`.
`mise run client-configs` merges cluster credentials into existing client configurations,
preserves unrelated contexts, and backs up each destination as `.bak`.

## Repository Map

Start with the input for the thing you want to change, then read its domain HCL.
`locals.tf` decodes shared inputs and derives machine identities; each domain
file contains its own lookups, derived values and direct provider resources.

| Input                 | Purpose                                                 | Main consumers                                 |
| --------------------- | ------------------------------------------------------- | ---------------------------------------------- |
| `hosts/`              | uCore installation and service configuration            | Butane                                         |
| `data/access.yaml`    | Vault names, SSH agent and Tailscale policy             | `onepassword.tf`, `tailscale.tf`, SSH renderer |
| `data/clusters.yaml`  | Cluster membership, desired versions and Talos settings | `talos.tf`, `oci.tf`                           |
| `data/dns/*.yaml`     | Explicit infrastructure DNS records                     | `dns.tf`, `cloudflare.tf`                      |
| `data/domains.yaml`   | Domain roles, credentials and tunnel routes             | `cloudflare.tf`, `dns.tf`                      |
| `data/machines.yaml`  | Machine identity, interfaces and compute                | `oci.tf`, `truenas.tf`, `unifi.tf`             |
| `data/networks.yaml`  | Existing UniFi subnets and managed OCI networking       | `oci.tf`, `unifi.tf`                           |
| `data/providers.yaml` | Provider bookmarks, widgets and Gatus probes            | Homepage, Flylab                               |
| `data/storage.yaml`   | Backup buckets, datasets and NFS exports                | `backblaze.tf`, `truenas.tf`                   |

Homepage and Flylab read machine endpoints from `data/machines.yaml` and
`data/domains.yaml`, and provider links and DNS resolvers from `data/providers.yaml`.
Provider `homepage` entries hold card metadata and native widget settings;
`gatus` entries hold native probe settings. Website probes default to the provider
URL; DNS probes default to the infrastructure domain. In the machine inventory:

- `beszel: true` records an installed host agent.
- `management_port` sets the HTTPS management port; `management` supplies display metadata.
- `monitoring: false` excludes a machine from infrastructure probes.
- `services.<name>` declares HTTP services with `port` and `scheme`.

Set `monitoring: true` under `management` or a service to enable its HTTP probe.
Service `homepage` metadata accepts `description`, `group` (default: Servers),
`icon` and `name`. The `types` mapping supplies machine display groups.

OpenTofu publishes non-secret Cloudflare and Tailscale IDs and preferred hosts
in each cluster vault's `Infrastructure Inventory` note and the `infrastructure`
output. Hosts prefer machine DNS, Tailscale IPv4, UniFi DNS, then LAN/public IP;
HTTPS consumers retain the certificate hostname. Kubelab reads the note through
External Secrets; widget credentials remain app-owned.

## Substrate

- **DNS & Ingress**: Cluster DNS targets, ACME DNS challenge tokens, Cloudflare Tunnels, stable external-service records and the webhook-only HAOS tunnel route; application DNS remains workload-owned in `kubelab`.
- **Mesh & Access**: Server login items with management or SSH URLs, Tailscale grants and host recovery keys, and Kubernetes operator OAuth clients. Tagged devices share a full Tailscale mesh, while admin identities can reach the full tailnet and use approved exit nodes.
- **Networking**: Validate existing UniFi VLANs and manage static DHCP reservations for retained appliances and VMs.
- **Secrets**: 1Password items in `Homelab`, `Cluster: MBK` and `Cluster: SYD`.
- **Storage**: Backblaze B2 appliance backup buckets, TrueNAS NVMe datasets and NFS shares for retained Kubernetes data, plus attached OCI block storage for replaceable `syd` volumes.

List SMTP hosts in `data/domains.yaml` under `resend.hosts`. Each receives a
sending-only key in `Homelab/Resend: <machine FQDN>`. Use SMTP username `resend`
and the stored password. Listed TrueNAS hosts are configured automatically with
sender `<network>-<hostname>@<infrastructure domain>`; configure other hosts manually.
OpenTofu manages the infrastructure domain's Resend DNS records and verification.

The `Flylab` vault holds managed `Resend` and `Tailscale OAuth Client` items,
with sending-only access and `tag:fly` respectively. Supply its `Fly.io` deployment
token separately; keep the service-account recovery copy in
`Homelab/Connect Token: fly`.

Each cluster vault receives B2, Cloudflare WAF and Resend control credentials,
plus an empty Control D item whose password must be populated manually. Items
use unqualified titles and the `Homelab` tag. After Connect bootstrap, External
Secrets delivers them to `kubelab` for application integrations.

Retain the 1Password version-tracking resources: write-only versions must
increase when credentials or recovery material change. The timestamp offset
keeps them above older fingerprints. The manually populated Control D password
stays at version zero.

Updating a machine-login item does not change the corresponding host's password.

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

### Backup Recovery

Keep backup receivers read-only (`readonly=on`) and unmounted (`mountpoint=none`).
Replicate recursively, excluding source mount and sharing properties. Exclude
receiver trees from destination snapshot jobs and onward replication. Verify
matching snapshot GUIDs and an incremental transfer after rebuilding a receiver.
Mount recovery snapshots read-only with `nosuid,nodev,noexec` in a root-owned
`0700` directory, then unmount them when finished.

### Cluster Installation

For an initial TrueNAS installation, download the cluster's Image Factory ISO to
the path declared by `truenas_virtual_machine_cdrom_devices`, then boot the VM.
For OCI, use `mise run prepare-oci-image syd` and export the printed
`TF_VAR_oci_talos_image_path` before planning the first upload. If state has no
cluster outputs yet, pass the QCOW2 URL from [Image Factory](https://factory.talos.dev/)
to `mise run prepare-oci-image` instead. Select the architecture, version and
extensions from `data/clusters.yaml`. Every installation apply needs its own
reviewed plan; there is no automatic bootstrap apply.

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

Single-node upgrades require an outage. If disruption budgets prevent draining,
use `--drain=false` for the approved Talos upgrade; workloads still stop
gracefully during reboot.

Commands for steps 1–3:

```shell
talosctl --context <cluster> --nodes <node-ip> version
talosctl --context <cluster> --nodes <node-ip> etcd snapshot <secure-backup-path>
talosctl --context <cluster> --nodes <node-ip> upgrade --image <installer-image>
kubectl --context <cluster> get nodes -o wide
talosctl --context <cluster> --nodes <node-ip> upgrade-k8s --to <kubernetes-version>
kubectl --context <cluster> get nodes -o wide
```

Changing the Talos installer image does not upgrade the running OS. Applying a
changed Kubernetes version does update component images and can restart running
components; use the upgrade sequence above before reconciling with OpenTofu.
Installation media is bootstrap-only, and existing `clusters` outputs may
still contain the previous installer image. Obtain the desired image from Image
Factory; do not substitute an ordinary apply for the upgrade sequence.

Machine configuration uses Talos 1.14 documents for DNS, Kubernetes networking
and node scheduling. Configuration applies use `no_reboot`; changes requiring a
reboot must be handled separately during an approved maintenance window.

### Dependency Updates

Renovate proposes updates for manual review. Routine tool, hook and action
updates are grouped weekly on Mondays (UTC); major updates, OpenTofu and cluster
upgrades remain separate. Review provider release notes and cluster compatibility.
Regenerate provider checksums for workstation and CI platforms with:

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

Bento uses `ucore-hci:stable`; Hotdog uses `ucore:stable`. Their Butane files
configure uCore's two-stage rebase from Fedora CoreOS to the signed image.
Render installation files with:

```shell
mise run ignition
```

Files are written to `${XDG_CACHE_HOME:-$HOME/.cache}/homelab/ignition/`.
Set `IGNITION_OUTPUT_DIRECTORY` to choose another destination.

Both hosts enable daily Cockpit certificate renewal through `acme.sh`.
Initial issuance and certificate registration require the host's scoped Cloudflare token.

## Licence

AGPL-3.0 - see [LICENSE](LICENSE).
