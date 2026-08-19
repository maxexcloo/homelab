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

### Common Tasks

| Task                         | Description                                                          |
| ---------------------------- | -------------------------------------------------------------------- |
| `mise run bootstrap-secrets` | Inject the 1Password SDK bootstrap secret into a cluster             |
| `mise run check`             | Run validation suite (OpenTofu, formatters, linters, security scans) |
| `mise run client-configs`    | Sync local `kubeconfig` and `talosconfig` from 1Password             |
| `mise run fmt`               | Format repository files (OpenTofu and Prettier)                      |
| `mise run init`              | Initialise providers locally without connecting the remote backend   |
| `mise run plan`              | Plan OpenTofu changes                                                |
| `mise run prek`              | Run all Git pre-commit hooks across the repository                   |
| `mise run ssh-config`        | Render and install SSH host aliases to `~/.ssh/config.d/homelab`     |

## Substrate

- **Compute & Virtualisation**: TrueNAS VM (`taco`) on `kimbap` and OCI compute instance (`hsp`) on Ampere A1.
- **Storage**: TrueNAS NVMe datasets, NFS shares, and automated snapshot tasks for Kubernetes persistent storage.
- **Networking**: UniFi VLANs and static DHCP reservations for retained appliances and VMs.
- **DNS & Ingress**: Cloudflare DNS records across owned zones, ACME DNS challenge tokens, and Cloudflare Tunnels.
- **Mesh & Access**: Tailscale ACL policies, host recovery keys, and Kubernetes operator OAuth clients.
- **Secrets Management**: 1Password native item delivery into scoped vaults (`Homelab`, `Cluster: mbk`, `Cluster: syd`).

## Operations & Safety

- **Local Execution**: CI validates syntax and security; all plans and applies run locally from trusted workstations.
- **Safe State**: State is stored in Google Cloud Storage with object versioning.
- **Destruction Guards**: Storage datasets and recovery items enforce `prevent_destroy` to safeguard live substrate.

## Licence

AGPL-3.0 - see [LICENSE](LICENSE).
