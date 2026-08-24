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

```shell
mise trust
mise run setup
mise run check
```

Copy `.mise.local.toml.default` to `.mise.local.toml` and replace its placeholders
before planning or applying infrastructure changes.

### Common Tasks

| Task                         | Description                                                        |
| ---------------------------- | ------------------------------------------------------------------ |
| `mise run apply`             | Apply OpenTofu changes after reviewing the presented plan          |
| `mise run bootstrap-secrets` | Inject the 1Password Connect bootstrap secret into a cluster       |
| `mise run check`             | Run formatting and configuration validation                        |
| `mise run client-configs`    | Sync local `kubeconfig` and `talosconfig` from 1Password           |
| `mise run fmt`               | Format repository files (OpenTofu and Prettier)                    |
| `mise run init`              | Initialise providers locally without connecting the remote backend |
| `mise run plan`              | Plan OpenTofu changes                                              |
| `mise run prek`              | Run all Git pre-commit hooks across the repository                 |
| `mise run prepare-oci-image` | Download and convert a Talos OCI image                             |
| `mise run setup`             | Install pinned tools, providers, and Git hooks                     |
| `mise run ssh-config`        | Render and install SSH host aliases to `~/.ssh/config.d/homelab`   |

### Prerequisites

Mise installs 1Password CLI (`op`), Actionlint, `jq`, `kubectl`, OpenTofu, Prek,
Prettier, ShellCheck, Talosctl, and yq. The OCI image preparation task also
expects `curl`, `gzip`, `qemu-img`, and `xz` from the workstation operating
system.

## Substrate

- **Compute & Virtualisation**: TrueNAS VM (`taco`) on `kimbap` and OCI compute instance (`hsp`) on Ampere A1.
- **Storage**: TrueNAS NVMe datasets, NFS shares, and automated snapshot tasks for Kubernetes persistent storage.
- **Networking**: UniFi VLANs and static DHCP reservations for retained appliances and VMs.
- **DNS & Ingress**: Cluster DNS targets, ACME DNS challenge tokens, and Cloudflare Tunnels; application DNS remains workload-owned in `kubelab`.
- **Mesh & Access**: Tailscale ACL policies, host recovery keys, and Kubernetes operator OAuth clients.
- **Secrets Management**: 1Password native item delivery into scoped vaults (`Homelab`, `Cluster: mbk`, `Cluster: syd`).

OCI TCP ingress rules declare a `mode` in `data/networks.yaml`. `tailscale` and
`cloudflared` keep the OCI firewall closed and delegate ingress to their private
overlay or tunnel. `public` creates only the explicitly configured OCI NSG rules;
the corresponding application route and DNS record remain owned by `kubelab`.

## Operations & Safety

- **Local Execution**: CI validates formatting and configuration; all plans and applies run locally from trusted workstations.
- **Safe State**: State is stored in versioned Google Cloud Storage; see
  [backend state and recovery](docs/backend-state.md) for its boundaries and
  recovery procedure.
- **Destruction Guards**: Storage datasets and recovery items enforce `prevent_destroy` to safeguard live substrate.

## Licence

AGPL-3.0 - see [LICENSE](LICENSE).
