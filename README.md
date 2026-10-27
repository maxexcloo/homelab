# Homelab

OpenTofu configuration for my homelab: infrastructure, host configuration and the
substrate the Kubernetes clusters run on. Kubernetes resources live in the
separate `kubelab` repository, where Flux reconciles them.

## Setup

Install the [shared Mise configuration](https://github.com/maxexcloo/dotfiles#shared-tools--tasks)
and the 1Password desktop app with its CLI integration, then run:

```shell
mise trust
mise run setup
mise run check
```

Setup creates the `Homelab/OpenTofu` credential item if it's missing; fill in its
fields and run setup again. [fnox.toml](fnox.toml) maps each field into the tasks
that need it, without exporting it to your shell. `truenas_connections` is a JSON
map keyed by machine name, with the `api_key` and `url` of each TrueNAS API.
`control_d_api_key` is copied into each cluster's `Control D` item.

## Usage

| Task                                             | Purpose                                       |
| ------------------------------------------------ | --------------------------------------------- |
| `mise run apply`                                 | Apply reviewed changes                        |
| `mise run check`                                 | Run all repository checks                     |
| `mise run clusters:image <cluster-or-image-url>` | Download a cluster installation image         |
| `mise run clusters:sync`                         | Sync Kubernetes & Talos client configurations |
| `mise run fmt`                                   | Format repository files                       |
| `mise run hosts:ignition`                        | Render host installation files                |
| `mise run hosts:ssh`                             | Install configured SSH aliases                |
| `mise run hosts:sync [host...]`                  | Sync host files & restart changed units       |
| `mise run init`                                  | Initialise providers & the remote backend     |
| `mise run init:offline`                          | Initialise providers without the backend      |
| `mise run plan`                                  | Preview infrastructure changes                |
| `mise run setup`                                 | Set up the workstation                        |

Plans and applies run locally; review each plan before applying it. CI validates
changes and refreshes external monitoring after a merge, but never applies.

Run `mise run init:offline` before `mise run check` on a fresh checkout to validate
without credentials. After a provider update, run `mise run init` and refresh the
lock file's checksums:

```shell
mise exec -- tofu providers lock -platform=darwin_arm64 -platform=linux_amd64
```

Renovate keeps versions current. Talos, Kubernetes and every image deployed
outside Kubernetes are pinned in `data/versions.yaml`; the Talos and Kubernetes
versions move together with the `kubectl` and `talosctl` pins.

## Configuration

- [data/](data/) is the inventory: access, clusters, DNS, domains, machines,
  networks, providers, storage and versions.
- [hosts/](hosts/) holds Butane configurations and the files they install.
- Root HCL files define provider resources by domain; [AGENTS.md](AGENTS.md)
  covers conventions and change safety.

Service entries with `credentials.username` get a generated 1Password login
titled and linked from the service's name and endpoint.

## Hosts

`mise run hosts:ignition` renders installation files from the Butane
configurations; set `IGNITION_OUTPUT_DIRECTORY` to change where they go. Supply
credentials separately during installation.

`mise run hosts:sync` keeps uCore and Bazzite hosts current. It installs each
host's Butane trees and the files OpenTofu generates for it, such as the Talos
worker and Cloudflare Tunnel Quadlets, so apply before syncing generated changes.
Each host asks for its sudo password once. Only units whose files changed
restart, files removed from the repository are removed from the host, and hosts
that are off are skipped until the next sync. Other files take effect when their
service reloads or the host reboots. Users, kernel arguments and enabled units
stay with Butane.

## Cluster Upgrades

Upgrade one cluster at a time, after reading the upstream
[Talos](https://docs.siderolabs.com/talos/) and
[Kubernetes](https://docs.siderolabs.com/kubernetes-guides/) upgrade notes:

1. Take an etcd snapshot and confirm recovery access.
2. Upgrade installed nodes with the matching Image Factory installer. Container
   nodes change image when you apply: TrueNAS apps directly, Podman hosts after
   `mise run hosts:sync`. Their volumes and bind mounts carry over.
3. Upgrade Kubernetes, checking node health after each step.
4. For OCI clusters, run `mise run clusters:image <cluster>` and export the
   printed `TF_VAR_oci_talos_image_path` so rebuilds boot the new version.
5. Review and apply the reconciliation plan.

Single-node clusters have an outage while they upgrade. Configuration applies use
`no_reboot`, and changing the installer doesn't upgrade running nodes.

## TrueNAS

Storage policy and SMB shares sit beside their datasets in `data/storage.yaml`,
keyed by full ZFS path. Only settings that differ from TrueNAS defaults are
recorded.

Apps reach HTTPS through shared Traefik ingress on a wildcard name under the
host. Label an app with `traefik.enable=true` and its backend port with
`traefik.http.services.<service>.loadbalancer.server.port`; the Compose service
name becomes the subdomain. Apps that support TrueNAS certificates natively use
those and their own ports instead.

These stay native because the provider can't represent them:

- The **AI Model Library Mirror** rsync task, which pulls Bento's `ai/models/`
  into kimbap's `/mnt/truenas/ai/` every 15 minutes.
- S3 HTTPS, buckets and access keys. OpenTofu only manages the parent dataset,
  the service and its DNS.

## Workstation Access

After `mise run hosts:ssh`, add this near the start of `~/.ssh/config`:

```sshconfig
Include config.d/homelab
```

`mise run clusters:sync` merges cluster credentials into existing client
configurations, keeps unrelated contexts and backs up each file as `.bak`.

Set `mtls: true` on a tunnel ingress entry to require
[Cloudflare client certificates](https://developers.cloudflare.com/api-shield/security/mtls/)
for its hostname; Kubelab owns enforcement. Activate and verify its WAF rule
before opening the route, and keep one certificate per device in 1Password.

## State Recovery

Restore a previous generation of the state object in the backend from
[backend.tf](backend.tf), then review a refresh-only plan. Don't migrate the
backend to recover.

## Licence

AGPL-3.0 - see [LICENSE](LICENSE).
