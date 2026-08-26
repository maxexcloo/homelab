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
OpenTofu subprocess.

### Common Tasks

| Task                         | Description                                                        |
| ---------------------------- | ------------------------------------------------------------------ |
| `mise run apply`             | Apply OpenTofu changes after reviewing the presented plan          |
| `mise run check`             | Run formatting and configuration validation                        |
| `mise run client-configs`    | Sync local `kubeconfig` and `talosconfig` from 1Password           |
| `mise run fmt`               | Format repository files (OpenTofu and Prettier)                    |
| `mise run init`              | Initialise providers locally without connecting the remote backend |
| `mise run opentofu-item`     | Create the OpenTofu 1Password item if missing                      |
| `mise run plan`              | Plan OpenTofu changes                                              |
| `mise run prek`              | Run all Git pre-commit hooks across the repository                 |
| `mise run prepare-oci-image` | Download and convert a Talos OCI image                             |
| `mise run setup`             | Install pinned tools, providers, and Git hooks                     |
| `mise run ssh-config`        | Render and install SSH host aliases to `~/.ssh/config.d/homelab`   |

### Prerequisites

Mise installs 1Password CLI (`op`), Actionlint, `jq`, `kubectl`, OpenTofu, Prek,
Prettier, ShellCheck, Talosctl, and yq. The workstation must also have the
1Password desktop app with CLI integration enabled. The OCI image preparation
task expects `curl`, `gzip`, `qemu-img`, and `xz` from the workstation operating
system.

## Substrate

- **Compute & Virtualisation**: TrueNAS VM (`taco`) on `kimbap` and OCI compute instance (`hsp`) on Ampere A1.
- **DNS & Ingress**: Cluster DNS targets, ACME DNS challenge tokens, and Cloudflare Tunnels; application DNS remains workload-owned in `kubelab`.
- **Mesh & Access**: Tailscale ACL policies, host recovery keys, and Kubernetes operator OAuth clients.
- **Networking**: UniFi VLANs and static DHCP reservations for retained appliances and VMs.
- **Secrets Management**: 1Password native item delivery into scoped vaults (`Homelab`, `Cluster: mbk`, `Cluster: syd`).
- **Storage**: TrueNAS NVMe datasets and NFS shares for retained Kubernetes data, plus attached OCI block storage for replaceable `syd` volumes.

OCI TCP ingress rules declare a `mode` in `data/networks.yaml`. `tailscale` and
`cloudflared` keep the OCI firewall closed and delegate ingress to their private
overlay or tunnel. `public` creates only the explicitly configured OCI NSG rules;
the corresponding application route and DNS record remain owned by `kubelab`.

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

Treat every state reader as a secret reader. State contains generated Talos,
Tailscale, Cloudflare, and other credentials even when plan output is redacted.
Keep state, plans, backups, and recovery material outside Git and restrict them
to the operator performing the recovery.

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

## Licence

AGPL-3.0 - see [LICENSE](LICENSE).
