# Homelab

OpenTofu manages infrastructure, host configuration and the substrate needed to
rebuild and reach Kubernetes clusters. The separate `kubelab` repository owns
Kubernetes resources and application integrations reconciled by Flux.

## Setup

Install [Mise](https://mise.jdx.dev/), jq and the 1Password desktop app. Enable its
CLI integration. The workstation also needs `curl` and `shasum`.

Create the provider accounts, remote backend and external services referenced by
the configuration before initialising the project:

```shell
mise trust
mise run setup
mise run check
```

Setup installs pinned tools, initialises providers and installs Git hooks. It
creates the provider credential item if missing; populate its fields and rerun
setup. Existing items are left untouched. Credential references live in
[.mise.toml](.mise.toml); credential-consuming tasks resolve them through the
1Password desktop app without exporting resolved values to the parent shell.

TrueNAS connection credentials use a JSON map keyed by configured machine names,
with `api_key` and `url` fields for each connection. Use the API endpoint declared
for that machine, including its actual scheme and port.

## Usage

| Task                                                | Purpose                                       |
| --------------------------------------------------- | --------------------------------------------- |
| `mise run apply`                                    | Apply explicitly approved changes             |
| `mise run check`                                    | Run all repository checks                     |
| `mise run client-configs`                           | Sync Kubernetes & Talos client configurations |
| `mise run fmt`                                      | Format repository files                       |
| `mise run ignition`                                 | Render host installation files                |
| `mise run init`                                     | Initialise providers & the remote backend     |
| `mise run init-ci`                                  | Initialise providers without the backend      |
| `mise run plan`                                     | Preview requested infrastructure changes      |
| `mise run prepare-oci-image <cluster-or-image-url>` | Download a cluster installation image         |
| `mise run setup`                                    | Set up the workstation                        |
| `mise run ssh-config`                               | Install configured SSH aliases                |

Every apply requires explicit approval and review of the exact plan it presents.
Plans and applies run locally. CI validates source and refreshes external
monitoring after successful pushes; it does not apply infrastructure. Its
cross-repository dispatch token needs Actions write access to the configured
monitoring repository. The workflow defines the required Actions secret.

### Checks & Updates

For credential-free validation on a fresh checkout:

```shell
mise install
mise run init-ci
mise run check
```

Commit hooks check changed files; the check task and CI run the full suite.
Static checks do not verify live provider behaviour or plan preconditions.
Provider updates require reinitialisation with `mise run init`. Regenerate
checksums for supported workstation and CI platforms with:

```shell
mise exec -- tofu providers lock -platform=darwin_arm64 -platform=linux_amd64
```

Renovate proposes updates for manual review. Its grouping and schedule are defined
in [renovate.json](renovate.json). Review provider release notes and cluster
compatibility before accepting updates. Host and cluster upgrades are deliberate
operations; changing installation configuration does not update existing hosts.

### Workstation Access

After `mise run ssh-config`, add this near the start of `~/.ssh/config`:

```sshconfig
Include config.d/homelab
```

SSH aliases are derived from the machine inventory. `mise run client-configs`
merges cluster credentials into existing client configurations, preserves unrelated
contexts and backs up each destination as `.bak`.

## Configuration

Read the owning configuration for deployed names, endpoints, versions and settings.

- [data/](data/) defines access policy, clusters, DNS, machines, networks, providers
  and storage.
- [hosts/](hosts/) contains host installation and service configuration.
- [backend.tf](backend.tf) defines the externally managed state location.
- [locals.tf](locals.tf) decodes shared inputs and derives common values.
- Other root HCL files define direct provider resources by domain.

Monitoring and dashboard consumers read non-secret inventory from this repository.
Credential references remain separate; application credentials and Kubernetes
resources belong to their owning workload configuration. See [AGENTS.md](AGENTS.md)
for repository conventions and change-safety requirements.

## Operations

Keep state, plans, credentials, installation output and recovery material outside
Git. State readers can read secrets even when plan output is redacted. Changing a
stored login credential does not change the corresponding host account.

### Backup Recovery

Keep backup receivers read-only and unmounted. Replicate recursively without
source mount or sharing properties; exclude receiver trees from destination
snapshot jobs and onward replication. After rebuilding a receiver, verify matching
snapshot GUIDs and an incremental transfer. Mount recovery snapshots read-only
with `nosuid,nodev,noexec` in a root-owned `0700` directory, then unmount them when
finished.

### Cluster Installation & Upgrades

Select architecture, desired versions and extensions from the cluster inventory.
For VM installation, deliver the matching installation image to the configured
boot-media path. For an initial OCI image upload, run `mise run prepare-oci-image`
with a configured cluster or explicit Image Factory URL, then export the printed
`TF_VAR_oci_talos_image_path` before planning. An explicit URL is required when
state has no cluster image output. Raw images from other sources require
`qemu-img` and the appropriate decompressor.

Review upstream [Talos](https://docs.siderolabs.com/talos/) and
[Kubernetes](https://docs.siderolabs.com/kubernetes-guides/) upgrade instructions
for the configured versions. Upgrade one cluster at a time:

1. Approve the upgrade and any outage, verify recovery access and take an etcd
   snapshot outside Git.
2. Upgrade Talos with the Image Factory installer matching the desired version
   and schematic, then verify node health.
3. Upgrade Kubernetes and verify node health again.
4. Review and approve the OpenTofu reconciliation plan before applying it.

Single-node upgrades require an outage. If disruption budgets prevent draining,
use `--drain=false` only for an approved Talos upgrade; workloads still stop during
reboot. Changing the configured installer does not upgrade the running OS, while
applying a changed Kubernetes version can restart components. Follow the upgrade
sequence before reconciliation. Existing state outputs can contain an older
installer; obtain the desired image from Image Factory. Configuration applies use
`no_reboot`; handle changes requiring reboot in an approved maintenance window.

### Host Installation

Butane files embed shared configuration and host overlays. Render them with
`mise run ignition`; `IGNITION_OUTPUT_DIRECTORY` can override the output location
defined by the task. Deliver credentials separately during installation. Keep
generated identities, certificates and application state outside Git.

Initial certificate issuance and registration need the configured scoped provider
credentials. Installation definitions describe bootstrap behaviour; existing hosts
require a separately approved update through their supported management tools.
Supported OS channels are update channels rather than immutable release pins.

### State Recovery

Use the backend location configured in [backend.tf](backend.tf). Stop plans and
applies before recovery:

1. Record the operator, OpenTofu version, workspace and affected backend generation;
   save the current resource list.
2. Securely copy the current and selected historical generations outside Git.
3. Restore the selected generation at the same location and compare its resource
   list with the saved list.
4. Review a refresh-only plan and obtain explicit approval before corrective apply.

Do not migrate the backend for recovery. Before force-unlocking state, identify
its lock holder, process and timestamp and prove that no apply is running.
Archived state and branches must never be applied to the active backend.

## Licence

AGPL-3.0 - see [LICENSE](LICENSE).
