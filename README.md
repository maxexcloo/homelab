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
`control_d_api_key` manages Control D rules and is copied into each cluster's
`Control D` item.

## Usage

| Task                                             | Purpose                                       |
| ------------------------------------------------ | --------------------------------------------- |
| `mise run apply`                                 | Apply reviewed changes                        |
| `mise run check`                                 | Run all repository checks                     |
| `mise run clusters:image <cluster-or-image-url>` | Download a cluster installation image         |
| `mise run clusters:sync`                         | Sync Kubernetes & Talos client configurations |
| `mise run fmt`                                   | Format repository files                       |
| `mise run hosts:ignition [host...]`              | Render host installation files                |
| `mise run hosts:ssh`                             | Install configured SSH aliases                |
| `mise run hosts:sync [host...]`                  | Sync generated host files                     |
| `mise run init`                                  | Initialise providers & the remote backend     |
| `mise run init:offline`                          | Initialise providers without the backend      |
| `mise run plan`                                  | Preview infrastructure changes                |
| `mise run setup`                                 | Set up the workstation                        |

Plans and applies run locally; review each plan before applying it.

Run `mise run init:offline` before `mise run check` on a fresh checkout to validate
without credentials. After a provider update, run `mise run init` and refresh the
lock file's checksums:

```shell
mise exec -- tofu providers lock -platform=darwin_arm64 -platform=linux_amd64
```

## Configuration

[data/](data/) holds the inventory and shared settings. Host provisioning uses
[data/machines.yaml](data/machines.yaml), [data/hosts/](data/hosts/) and
[templates/hosts/](templates/hosts/); [bluemax](https://github.com/maxexcloo/bluemax)
images own the host OS configuration. [AGENTS.md](AGENTS.md) covers ownership,
conventions and change safety.

Service entries with `credentials.username` get a generated 1Password login
titled and linked from the service's name and endpoint.

## Hosts

`locals.tf` derives the shared inventory used by OpenTofu and the host scripts;
SSH rendering and installation checks need no credentials.

`data/machines.yaml` contains each machine's inventory and optional `butane`
settings; omit unused settings. Set a machine's `hostname` to override the
hostname derived from its inventory key.

Syncthing's `AI` folder synchronises in both directions; changes and deletions
propagate to peers. Kubelab owns its private routes and authentication.

`ssh.authorized_keys` in [data/access.yaml](data/access.yaml) supplies the common
login keys. `butane.ssh_authorized_keys` adds keys for that machine's login;
`butane.users` and `butane.groups` define additional accounts. Pluto's `saturn`
user and group retain UID/GID 1001 for backup access. `butane.trees` installs
host-specific files, such as Pluto's sanoid configuration, from paths relative
to the repository root; sync does not deliver them.

Run `mise run hosts:ignition mercury` to render Mercury's installation file.
The output is `${XDG_CACHE_HOME:-$HOME/.cache}/homelab/ignition/mercury.ign`;
`IGNITION_OUTPUT_DIRECTORY` overrides the directory. Rendering needs an unlocked
1Password CLI and OpenSSL (`brew install openssl@3` on macOS). Mercury's
`Workstation: mercury.mbk.excloo.net` login must exist from a reviewed apply.
Its password is hashed locally for `core`; generated files stay private.
Password changes in 1Password do not update an installed host.

Installs boot Fedora CoreOS, then rebase to the signed `bluemax-server` image,
which owns the OS configuration and updates itself. Ignition also carries each
host's generated files, such as its Cloudflare Tunnel token.

`mise run hosts:sync [host...]` installs changed generated files on uCore and
Bazzite tunnel hosts after an apply and restarts cloudflared.

## Cluster Upgrades

Upgrade one cluster at a time, after reading the upstream
[Talos](https://docs.siderolabs.com/talos/) and
[Kubernetes](https://docs.siderolabs.com/kubernetes-guides/) upgrade notes:

1. Take an etcd snapshot and confirm recovery access.
2. Upgrade installed nodes with the matching Image Factory installer. TrueNAS
   container nodes change image when you apply; their volumes and bind mounts
   carry over.
3. Upgrade Kubernetes, checking node health after each step.
4. For OCI clusters, run `mise run clusters:image <cluster>` and export the
   printed `TF_VAR_oci_talos_image_path` so rebuilds boot the new version.
5. Review and apply the reconciliation plan.

Single-node clusters have an outage while they upgrade. Configuration applies use
`no_reboot`, and changing the installer doesn't upgrade running nodes.

## NanoKVM

NanoKVM uses Lego for Let's Encrypt certificates through the inventory's ACME
delegation. Its dedicated DNS token can edit only the challenge zone; OpenTofu
stores it in `Cloudflare ACME DNS: <hostname>` in the Homelab vault. The appliance
reads a root-only copy at `/etc/lego/cloudflare-token`. Keep Lego's public DNS
resolver override (`1.1.1.1:53`): the appliance's local resolver did not return
delegated TXT answers during validation.

`/etc/cron.d/nanokvm-acme` runs renewal, with certificate and account state under
`/var/lib/lego`. Its hook at `/usr/local/libexec/nanokvm-certificate` must install
the full chain and an RSA key, required by NanoKVM's startup validator, then
signal `NanoKVM-Server` to exit so its stock supervisor restarts it with the new
certificate.

## TrueNAS

Storage policy and SMB shares sit beside their datasets in
[data/storage.yaml](data/storage.yaml), keyed by full ZFS path.

Saturn’s native Beszel custom app discovers storage devices using a read-only
`/dev:/dev` directory bind and device cgroup rules (`b 8:* rw`, `b 259:* rw`,
`c 242:* rw`). It retains the explicit `/dev/zfs` mapping and its existing
`SYS_ADMIN`/`SYS_RAWIO` capabilities, with privileged mode disabled. Avoid
per-disk mappings: removing a drive would prevent the app from starting. The
NVMe character major is kernel-assigned; recheck it after kernel changes with
`ls -l /dev/nvme0` and update the character-device rule if necessary.
USB SSDs may require a device-type override for their limited SMART data.

These stay native because the provider can't represent them:

- Saturn's `truenas-nvme` pool: one Lexar NM790 4TB and two Crucial X9 4TB
  drives in RAIDZ1, with `autotrim=on`. The pinned provider cannot update pool
  topology or manage autotrim. Its USB discard workaround is managed through
  the `crucial-x9-trim` startup task in `data/machines.yaml`.
- Saturn's native replication tasks send each pool directly to Pluto. The SSD
  pool keeps its scheduled snapshots; whole-pool recovery uses the offsite replica.
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
