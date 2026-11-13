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
fields and run setup again. `truenas_connections` is a JSON map keyed by machine
name, with the `api_key` and `url` of each TrueNAS API.

## Usage

| Task                                        | Purpose                                       |
| ------------------------------------------- | --------------------------------------------- |
| `mise run apply`                            | Apply reviewed changes                        |
| `mise run check`                            | Run all repository checks                     |
| `mise run fmt`                              | Format repository files                       |
| `mise run hosts:ignition [host...]`         | Render host installation files                |
| `mise run init`                             | Initialise providers & the remote backend     |
| `mise run init:offline`                     | Initialise providers without the backend      |
| `mise run oci:image <cluster-or-image-url>` | Download a cluster installation image         |
| `mise run plan`                             | Preview infrastructure changes                |
| `mise run setup`                            | Set up the workstation                        |
| `mise run sync:clusters`                    | Sync Kubernetes & Talos client configurations |
| `mise run sync:hosts [host...]`             | Sync generated host files & trees             |
| `mise run sync:ssh`                         | Install configured SSH aliases                |

Plans and applies run locally; review each plan before applying it.

Run `mise run init:offline` before `mise run check` on a fresh checkout to validate
without credentials. After a provider update, run `mise run init` and refresh the
lock file's checksums:

```shell
mise exec -- tofu providers lock -platform=darwin_arm64 -platform=linux_amd64
```

## Hosts

Run `mise run hosts:ignition mercury` to render Mercury's installation file into
`${XDG_CACHE_HOME:-$HOME/.cache}/homelab/ignition/`. Rendering needs an unlocked
1Password CLI, OpenSSL (`brew install openssl@3` on macOS) and the
`Workstation: mercury.mbk.excloo.net` login from a reviewed apply. Password
changes in 1Password do not update an installed host.

On Cloudflare Tunnel hosts, run this once after syncing their configuration:

```shell
sudo /usr/bin/cloudflared service install --no-update-service
```

## Cluster Upgrades

Upgrade one cluster at a time, after reading the upstream
[Talos](https://docs.siderolabs.com/talos/) and
[Kubernetes](https://docs.siderolabs.com/kubernetes-guides/) upgrade notes:

1. Take an etcd snapshot and confirm recovery access.
2. Upgrade installed nodes with the matching Image Factory installer. TrueNAS
   container nodes change image when you apply; their volumes and bind mounts
   carry over.
3. Upgrade Kubernetes, checking node health after each step.
4. For OCI clusters, run `mise run oci:image <cluster>` and export the
   printed `TF_VAR_oci_talos_image_path` so rebuilds boot the new version.
5. Review and apply the reconciliation plan.

Single-node clusters have an outage while they upgrade. Configuration applies use
`no_reboot`, and changing the installer doesn't upgrade running nodes.

## NanoKVM

NanoKVM renews its Let's Encrypt certificate with Lego from
`/etc/cron.d/nanokvm-acme`, using the DNS token from `Cloudflare ACME DNS:
<hostname>` copied to `/etc/lego/cloudflare-token`. Keep Lego's `1.1.1.1:53`
resolver override, as the appliance's resolver doesn't return delegated TXT
answers. The hook at `/usr/local/libexec/nanokvm-certificate` installs the full
chain and an RSA key, then signals `NanoKVM-Server` to exit so its supervisor
restarts it.

## TrueNAS

These stay native because the pinned provider can't represent them:

- Saturn's `truenas-nvme` pool topology and `autotrim=on`.
- Saturn's replication tasks to Pluto.
- S3 HTTPS, buckets and access keys.
- Saturn's Beszel app device access: a read-only `/dev:/dev` bind, the
  `/dev/zfs` mapping and device cgroup rules `b 8:* rw`, `b 259:* rw` and
  `c 242:* rw`. Avoid per-disk mappings, which stop the app starting when a
  drive is removed. The NVMe character major is kernel-assigned; recheck it
  with `ls -l /dev/nvme0` after kernel changes.

## Workstation Access

After `mise run sync:ssh`, add this near the start of `~/.ssh/config`:

```sshconfig
Include config.d/homelab
```

Before opening a tunnel route with `mtls: true`, activate and verify its
Cloudflare WAF rule in Kubelab.

## State Recovery

Restore a previous generation of the state object in the backend from
[backend.tf](backend.tf), then review a refresh-only plan. Don't migrate the
backend to recover.

## Licence

AGPL-3.0 - see [LICENSE](LICENSE).
