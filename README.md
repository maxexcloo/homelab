# Homelab

OpenTofu configuration for my homelab: infrastructure, host configuration and
everything needed to rebuild and reach the Kubernetes clusters. Kubernetes
resources and application integrations live in the separate `kubelab` repository,
where Flux reconciles them.

## Setup

Install the [shared Mise configuration](https://github.com/maxexcloo/dotfiles#shared-tools--tasks)
before running local Mise tasks.

Install [Mise](https://mise.jdx.dev/) and the 1Password desktop app, and turn on
its CLI integration. The workstation also needs `curl` and `shasum`.

Create the provider accounts, remote backend and external services referenced by
the configuration before initialising the project:

```shell
mise trust
mise run setup
mise run check
```

Setup installs the configured tools and initialises providers. If the provider
credential item doesn't exist yet, setup creates it; fill in its fields and run
setup again. Existing items are left alone. Store the Control D API key in
`Homelab/OpenTofu/control_d_api_key`, and OpenTofu copies it into each cluster's
managed `Control D` item. Credential references live in [fnox.toml](fnox.toml).
Tasks that need credentials resolve them through the 1Password desktop app
without exporting the values to the parent shell.

TrueNAS connection credentials use a JSON map keyed by configured machine names,
with `api_key` and `url` fields for each connection. Use the API endpoint declared
for that machine, including its actual scheme and port.

## Usage

| Task                                                | Purpose                                       |
| --------------------------------------------------- | --------------------------------------------- |
| `mise run apply`                                    | Apply explicitly approved changes             |
| `mise run check`                                    | Run all repository checks                     |
| `mise run clients:sync`                             | Sync Kubernetes & Talos client configurations |
| `mise run fmt`                                      | Format repository files                       |
| `mise run ignition`                                 | Render host installation files                |
| `mise run init`                                     | Initialise providers & the remote backend     |
| `mise run init:check`                               | Initialise providers without the backend      |
| `mise run oci:image:prepare <cluster-or-image-url>` | Download a cluster installation image         |
| `mise run plan`                                     | Preview requested infrastructure changes      |
| `mise run setup`                                    | Set up the workstation                        |
| `mise run ssh:configure`                            | Install configured SSH aliases                |

Every apply needs explicit approval after reviewing the exact plan it shows.
Plans and applies skip the Docker resources of hosts that SSH cannot reach.
Plans and applies run locally. Merge pull requests into `main` after review. The
single GitHub job validates changes and refreshes external monitoring after a
merge. It never applies infrastructure. Its cross-repository dispatch token needs
Actions write access to the configured monitoring repository, and the workflow
defines the Actions secret it needs.

### Checks & Updates

For credential-free validation on a fresh checkout:

```shell
mise install
mise run init:check
mise run check
```

Run `mise run hooks:install` to turn on the optional commit hooks. Static checks
don't verify live provider behaviour or plan preconditions. After a provider
update, reinitialise with `mise run init`. To regenerate checksums for the
supported workstation and validation platforms, run:

```shell
mise exec -- tofu providers lock -platform=darwin_arm64 -platform=linux_amd64
```

Renovate opens update pull requests from [renovate.json5](renovate.json5), and
`mise run dependencies:check` previews them locally. Cluster versions in
`data/clusters.yaml` update together with their matching `kubectl` and
`talosctl` pins. Check provider release notes and cluster compatibility before
accepting updates. Host and cluster upgrades are done on purpose; changing the
installation configuration doesn't update existing hosts.

### Client Certificates

Set `mtls: true` on a tunnel ingress entry to enable [Cloudflare client certificates](https://developers.cloudflare.com/api-shield/security/mtls/)
for its hostname. Kubelab owns enforcement and webhook exceptions. After review,
activate and verify its WAF rule before opening the application route. Keep one
certificate per device in 1Password.

### TrueNAS Configuration

Storage policy and SMB shares sit beside their datasets in `data/storage.yaml`,
and non-secret host settings sit beside their machine in `data/machines.yaml`.
Dataset keys use full ZFS paths such as `pool/dataset`. Root `truenas.tf` uses
native provider resources, and the inventory only records settings that differ
from the defaults. Factory-default tasks and settings stay native.

Bento owns the active AI model and LoRA library. TrueNAS's native **AI Model
Library Mirror** task pulls Bento's `ai/models/` into kimbap's `/mnt/truenas/ai/`
every 15 minutes. The dataset root contains only `comfyui/` and `radiance/`,
with no additional `models/` wrapper. Studio's media, configuration and profiles
live separately in `/mnt/truenas-nvme/studio/`.
Keep this rsync task native while the provider cannot represent its SSH
credentials, archive mode and deletion settings.

### TrueNAS App Access

Shared TrueNAS ingress uses wildcard DNS and a wildcard certificate under the
host's configured machine name. Traefik picks up apps with `traefik.enable=true`,
and the Compose service name becomes the subdomain. Set the app's backend port
with `traefik.http.services.<service>.loadbalancer.server.port`. Native app labels
sit beside their service in the machine inventory and go in the app's custom
labels settings.

If an app supports TrueNAS certificates natively, use that. Those apps keep their
own HTTPS ports and don't need Traefik labels. Use Traefik for other web apps,
including ones whose native TLS only offers a self-signed certificate, and set
their private upstream to HTTP through the app's own settings.

Ingress accepts the host's LAN subnets and Tailscale on its configured HTTPS port.
It reads Docker labels through the host socket and reuses the native TrueNAS
wildcard certificate through a read-only directory mount. TrueNAS handles renewal,
and an hourly native cron job reloads Traefik's certificate without restarting
it. TrueNAS management keeps its existing ports. Review and approve the plan
before deploying ingress, then check DNS, trusted certificates and application
access.

### Native S3

OpenTofu manages the S3 parent dataset, turns the service on and sets up its
private DNS. The pinned provider doesn't expose HTTPS listeners, bucket ownership
or access keys, so configure those in TrueNAS's native S3 settings. Reuse the UI
certificate for HTTPS. TrueNAS creates and keeps each bucket's child dataset.
Keep client credentials in 1Password, outside Git.

### Workstation Access

After `mise run ssh:configure`, add this near the start of `~/.ssh/config`:

```sshconfig
Include config.d/homelab
```

SSH aliases come from the machine inventory. `mise run clients:sync` merges
cluster credentials into existing client configurations, keeps unrelated contexts
and backs up each destination as `.bak`.

## Configuration

Deployed names, endpoints, versions and settings are in the configuration that
owns them:

- [data/](data/) defines access policy, clusters, DNS, machines, networks, providers
  and storage.
- [hosts/](hosts/) contains host installation and service configuration.
- [backend.tf](backend.tf) defines the externally managed state location.
- [locals.tf](locals.tf) decodes shared inputs and derives common values.
- Other root HCL files define direct provider resources by domain.

Monitoring and dashboards read the non-secret inventory from this repository.
Credential references are kept separate, and application credentials and
Kubernetes resources belong with their workload configuration. See
[AGENTS.md](AGENTS.md) for repository conventions and change safety rules.

## Operations

Keep state, plans, credentials, installation output and recovery material out of
Git. Changing a stored login credential doesn't change the matching host
account.

Service entries opt into generated 1Password logins with `credentials.username`.
Their name and endpoint define the item title and URL. Application-specific
settings remain in the application configuration.

### Cluster Installation & Upgrades

Architecture, versions and extensions come from the cluster inventory. For the
first OCI image upload, run `mise run oci:image:prepare` with a configured cluster
or an explicit Image Factory URL, then export the printed
`TF_VAR_oci_talos_image_path` before planning. You need an explicit URL when
state has no cluster image output.

Review upstream [Talos](https://docs.siderolabs.com/talos/) and
[Kubernetes](https://docs.siderolabs.com/kubernetes-guides/) upgrade instructions
for the configured versions. Upgrade one cluster at a time:

1. Approve the upgrade and any outage, verify recovery access and take an etcd
   snapshot outside Git.
2. For installed Talos nodes, upgrade with the Image Factory installer matching
   the desired version and schematic. For a container node, review and apply the
   container image version change through its TrueNAS app or Docker container;
   preserve the dataset bind mounts and Docker volumes. The container shares its
   host's kernel. Verify node health after either operation.
3. Upgrade Kubernetes and verify node health again.
4. For OCI clusters, run `mise run oci:image:prepare <cluster>` and export the
   printed `TF_VAR_oci_talos_image_path`, so the stored image matches the new
   version and later rebuilds boot it. Running nodes keep their boot volumes.
5. Review and approve the OpenTofu reconciliation plan before applying it.

Single-node upgrades mean an outage. Changing the configured installer doesn't
upgrade installed Talos nodes, and configuration applies use `no_reboot`.

### Host Installation

Butane files embed shared configuration and host overlays. Render them with
`mise run ignition`; `IGNITION_OUTPUT_DIRECTORY` overrides the task's output
location. Supply credentials separately during installation. Keep generated
identities, certificates and application state out of Git.

The first certificate issue and registration need the configured scoped provider
credentials. Installation definitions only cover bootstrap. Existing hosts need a
separately approved update through their own management tools. The supported OS
channels are update channels, not fixed release pins.

### State Recovery

Restore a previous generation of the versioned state object in the backend
configured in [backend.tf](backend.tf), then review a refresh-only plan. Don't
migrate the backend to recover.

## Licence

AGPL-3.0 - see [LICENSE](LICENSE).
