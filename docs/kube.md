# Kubernetes

## Status

Kubernetes is currently a learning environment, not the production deployment
platform. The existing OpenTofu, TrueNAS, Docker, routing, Tailscale, dashboard,
and external-service automation remain authoritative.

The current local lab is a disposable Talos cluster running inside OrbStack on
macOS:

```text
macOS
└── OrbStack
    ├── talos-default-controlplane-1  192.168.250.2
    └── talos-default-worker-1        192.168.250.3
```

The default Talos Docker subnet, `10.5.0.0/24`, conflicts with an existing
homelab network. Local Talos clusters must use an unused subnet, currently
`192.168.250.0/24`:

```shell
talosctl cluster create docker --subnet 192.168.250.0/24
```

OrbStack works for this learning cluster. Cluster creation may report that it
cannot find an expected node while Kubernetes is still starting. Check the
actual state before recreating it:

```shell
kubectl get nodes -o wide
kubectl get pods --all-namespaces
talosctl cluster show --name talos-default
```

Container mode does not exercise installation, disks, operating-system
upgrades, or resets. A persistent VM is required to learn those parts of Talos.

## Current Decision

Do not migrate production services merely to adopt Kubernetes. The current
system already solves deployment, routing, secrets, dashboards, external
integrations, and multi-server placement. Kubernetes initially provides a safe
way to learn reconciliation, scheduling, service discovery, and declarative
workloads.

Keep the boundary explicit:

```text
Production homelab                 Kubernetes lab
├── OpenTofu automation            └── Disposable Talos cluster
├── TrueNAS applications               └── Experimental applications
├── Docker deployments
├── Existing routing
└── Existing Tailscale
```

Do not initially add Flux, Rancher, Omni, Crossplane, External Secrets,
Cilium, MetalLB, TrueNAS storage, or multi-cluster networking. Add a component
only after encountering the problem it solves.

## Current Estate and Ownership

The migration surface spans five repositories. Kubernetes can replace the
application delivery repositories, but it does not automatically replace the
infrastructure and external API ownership in this repository.

| Repository          | Current responsibility                                      | Eventual disposition                                       |
| ------------------- | ----------------------------------------------------------- | ---------------------------------------------------------- |
| `homelab`           | Models infrastructure, credentials, routes, and deployments | Retain a reduced external-infrastructure foundation        |
| `homelab-docker`    | Renders encrypted Compose packages consumed by Doco-CD      | Remove after the remaining Docker targets are migrated     |
| `homelab-fly`       | Deploys the externally hosted Gatus instance                | Retain while Gatus remains outside the home failure domain |
| `homelab-truenas`   | Renders and reconciles catalogue and custom TrueNAS apps    | Remove after application and storage migrations complete   |
| `homelab-workflows` | Runs guarded games-library operations beside RoMM storage   | Retain until an equivalent storage-local runner is proven  |

The root OpenTofu configuration currently owns more than machines. It also
owns or derives:

- 1Password item structure, generated fields, URLs, and ownership metadata.
- Backblaze B2 buckets and application credentials.
- Cloudflare DNS, tunnels, access applications, WAF rules, rate limits, and
  scoped tokens.
- Deployment repositories, `CONFIG` variables, and workflow dispatches.
- Homepage cards and Gatus probes aggregated from the service model.
- Incus and OCI virtual machines and their networks.
- Pocket ID groups and OIDC clients.
- Resend API keys.
- Tailscale ACLs, tags, routes, and per-server or per-service authentication
  keys.
- UniFi resources and appliance inventory.

These responsibilities need an explicit owner during migration. Moving a Pod
without transferring its OIDC client, DNS, secret, storage, monitoring, and
deletion ownership leaves two partially authoritative systems.

## Core Concepts

The minimum learning toolset is:

| Component  | Responsibility                                  |
| ---------- | ----------------------------------------------- |
| Kubernetes | Schedules and reconciles workloads              |
| Talos      | Immutable operating system for Kubernetes nodes |
| `kubectl`  | Manages Kubernetes resources                    |
| `talosctl` | Configures and operates Talos nodes             |

A basic workload contains four important layers:

```text
Deployment → ReplicaSet → Pod
Service ─────────────────→ Pods
```

- A `Deployment` declares the desired application and replica count.
- A `ReplicaSet` maintains that number of Pods.
- A `Pod` is a running instance of one or more containers.
- A `Service` gives changing Pods a stable name and virtual address.

The reconciliation loop is the central idea: deleting a managed Pod does not
delete the application because its Deployment creates a replacement.

## Learning Path

### Workloads and Services

Create an isolated namespace and a simple application:

```shell
kubectl create namespace learning
kubectl create deployment nginx --namespace learning --image nginx
kubectl expose deployment nginx --namespace learning --port 80 --type ClusterIP
kubectl get all --namespace learning
kubectl port-forward --namespace learning service/nginx 8080:80
```

Scale it and observe reconciliation:

```shell
kubectl scale deployment nginx --namespace learning --replicas 3
kubectl get pods --namespace learning --output wide --watch
kubectl delete pod --namespace learning --selector app=nginx
```

After learning the imperative commands, express the Deployment and Service in
YAML and use `kubectl apply`. Then learn, in order:

1. ConfigMaps.
2. Secrets.
3. Readiness and liveness probes.
4. CPU and memory requests and limits.
5. Temporary volumes.
6. Persistent volumes.
7. Node labels, affinity, and topology spread constraints.
8. Ingress or Gateway routing.
9. Helm.
10. Flux and GitOps.

### Persistent Talos Lab

After the local cluster, create one disposable Talos VM with approximately four
CPUs, 8 GB of memory, and 40–100 GB of disk. Do not overwrite an existing
server. A TrueNAS-hosted VM or new OCI VM would both be suitable experiments.

A single-node lab runs the control plane and workloads together and therefore
needs:

```yaml
cluster:
  allowSchedulingOnControlPlanes: true
```

Confirm the VM IP and installation disk from Talos maintenance mode before
generating or applying its machine configuration. Do not assume the disk is
`/dev/sda`; virtual platforms commonly use `/dev/vda`.

The first persistent success criterion is:

> Recreate a Talos VM and deploy one disposable application without using the
> existing OpenTofu deployment pipeline.

OpenSpeedTest is the preferred first real application because it has no
important database, object storage, mail, or OIDC dependency.

A TrueNAS-hosted Talos VM is useful for learning, but it shares a failure domain
with the storage system. It is not a highly available production design,
especially when its PVCs also come from that TrueNAS host. A production home
cluster eventually needs independent compute nodes or an explicit acceptance
that a TrueNAS outage removes both compute and storage.

## Tooling Map

The following components solve separate problems. They are not all required.

| Component          | Responsibility                                            | Initial decision                         |
| ------------------ | --------------------------------------------------------- | ---------------------------------------- |
| Talos              | Kubernetes node operating system                          | Preferred for the lab                    |
| K3s                | Kubernetes distribution installed on ordinary Linux       | Alternative to Talos                     |
| Flux               | Reconciles cluster configuration from Git                 | Add after basic Kubernetes               |
| Helm               | Packages Kubernetes applications                          | Add after direct manifests               |
| Traefik            | Routes HTTP traffic to Services                           | Add when stable HTTP ingress is needed   |
| Cilium             | Pod networking, policy, load balancing, and observability | Optional replacement for a simpler CNI   |
| MetalLB            | Assigns and advertises `LoadBalancer` IPs on a LAN        | Add only for direct LAN ingress          |
| cert-manager       | Creates and renews TLS certificates                       | Add with production-style ingress        |
| external-dns       | Creates DNS records from Kubernetes routes                | Optional; define strict record ownership |
| External Secrets   | Reads secrets from 1Password into Kubernetes              | Add when a real secret is needed         |
| Cloudflared        | Publishes selected Services through Cloudflare Tunnel     | Retain for public ingress                |
| Tailscale operator | Connects users, appliances, and separate clusters         | Add only at the cluster boundary         |
| Crossplane         | Reconciles external APIs from Kubernetes resources        | Do not adopt initially                   |
| Rancher            | UI and management plane for multiple clusters             | Not needed                               |
| Omni               | Optional Talos management plane                           | Not needed                               |

Talos and K3s are alternatives. Talos is the operating system and Kubernetes
distribution. K3s runs on a conventional Linux operating system. Do not install
K3s on Talos.

Omni is not required by Talos. Hosted Omni has a limited trial, while
self-hosting it for a homelab adds an always-available service, TLS,
authentication, networking, backups, and upgrades. `talosctl`, `kubectl`, and
Flux are sufficient for a small number of clusters.

Rancher similarly adds a management plane and UI but does not remove an initial
homelab requirement. Reconsider it only if direct Git and CLI operation of
several clusters becomes difficult.

## Networking

### CNI and Cilium

Every Kubernetes cluster requires a Container Network Interface implementation.
The CNI assigns Pod addresses and implements connectivity between Pods and
nodes. Cilium is an advanced CNI that also provides network policy,
observability through Hubble, optional WireGuard encryption, service load
balancing, ingress, and Gateway API support.

Cilium is not synonymous with Kubernetes networking. A simpler CNI such as
Flannel is sufficient while learning. Adopt Cilium only when its policy,
observability, or consolidation is wanted.

### MetalLB

Cloud Kubernetes providers allocate addresses for Services of type
`LoadBalancer`. A bare-metal cluster has no cloud load balancer, so MetalLB can
allocate an address from a reserved LAN pool and announce it on the local
network:

```text
reddit.excloo.dev
        │ DNS
        ▼
10.0.3.200
        │ MetalLB
        ▼
Traefik
        ▼
Redlib Service
        ▼
Redlib Pod
```

MetalLB does not route hostnames, create DNS records, or issue certificates. It
only allocates and advertises addresses. It can be omitted when all traffic
arrives through Cloudflared, Tailscale, a node address, or `kubectl
port-forward`.

Avoid deploying MetalLB and an overlapping Cilium load-balancer implementation
without a deliberate separation of ownership.

### Kubernetes and Tailscale

Kubernetes replaces per-application Tailscale connectivity inside one cluster:

- Pods use Kubernetes DNS rather than server hostnames.
- Services provide stable addresses and load balancing.
- Applications do not need published host ports.
- Applications do not know which node runs their dependencies.

Kubernetes is not a general VPN. It does not inherently connect a Mac, phone,
TrueNAS, HAOS, UniFi, Bazzite, non-Kubernetes servers, or independent clusters.
Tailscale remains useful at those boundaries.

The eventual pattern would be one Tailscale operator per cluster, not one
Tailscale identity per application. The operator can expose selected Services,
provide private API access, reach tailnet appliances, and bridge selected
services between clusters.

Talos KubeSpan can use WireGuard between Talos nodes in the same cluster across
different networks. This solves node connectivity, not WAN latency, etcd
quorum, region-local storage, or connectivity for devices outside the cluster.
Do not use it initially to stretch one control plane between Australia and the
United States.

## Nodes, Clusters, and Regions

Multiple servers in one cluster are normal. A future home cluster could be:

```text
AU home cluster
├── talos-au-01  Control plane and workloads
├── talos-au-02  Control plane and workloads
├── talos-au-03  Control plane and workloads
└── TrueNAS      External storage, not a Kubernetes node
```

Three control-plane nodes allow etcd to tolerate one node failure. A
single-node control plane is appropriate for a lab but is not highly
available.

Use independent clusters across remote locations:

```text
Git repository
├── Flux → AU home cluster
├── Flux → AU OCI cluster
└── Flux → US cluster
```

Do not stretch etcd across regions. A remote worker still depends continuously
on its control plane, while persistent storage and application data remain
region-local. Stateless applications can be deployed independently into
several clusters; stateful multi-region applications require application-aware
replication and failover.

Services should select clusters or capabilities, not individual nodes. Within
a cluster, Kubernetes schedules the Pods. Explicit node selection remains
appropriate for special hardware such as GPUs.

## Dashboard Discovery

Homepage can discover Services in its local Kubernetes cluster from Ingress,
Traefik IngressRoute, or Gateway API annotations. Those annotations can provide
the application name, group, icon, URL, and Pod selector. This removes most
separate dashboard configuration for local Kubernetes applications.

Homepage does not natively aggregate automatic discovery from several
Kubernetes clusters through multiple simultaneous Kubernetes connections. The
clean options are:

1. Run one Homepage per cluster and link them.
2. Run one global Homepage, use local discovery where useful, and keep a small
   explicit `services.yaml` for remote clusters and non-Kubernetes resources.

The second option best matches this homelab because TrueNAS, UniFi, HAOS, Fly,
and external providers require explicit entries regardless. Direct dashboard
data in Git is preferable to rebuilding the current OpenTofu dashboard
generator.

## Hypothetical Kubernetes-First Homelab

If Kubernetes later replaces the application platform, use one off-the-shelf
component per responsibility:

```text
Physical infrastructure
├── UniFi              VLANs, DHCP, routing, and firewall
├── TrueNAS            ZFS, snapshots, and storage exports
└── Talos machines     Kubernetes compute

Kubernetes platform
├── Flux               Git deployment
├── CNI                 Pod networking
├── MetalLB             Optional LAN addresses
├── Traefik             HTTP routing
├── cert-manager        TLS
├── external-dns        Application DNS
├── External Secrets   1Password consumption
├── Cloudflared         Public ingress
└── Application operators

External foundation
└── Small OpenTofu roots
    ├── Servers and networks
    ├── Cloudflare account policy
    ├── Pocket ID clients
    ├── Resend keys
    ├── B2 buckets and credentials
    └── UniFi
```

Kubernetes should replace the application deployment layer, not the router,
storage appliance, or every mature external provider integration.

### GitOps Repository

A direct GitOps repository could be organised as:

```text
homelab-kubernetes/
├── apps/
│   ├── actual-budget/
│   ├── immich/
│   ├── miniflux/
│   └── redlib/
├── clusters/
│   ├── au-cloud/
│   ├── au-home/
│   └── us/
├── infrastructure/
│   ├── networking/
│   ├── observability/
│   ├── security/
│   └── storage/
└── platform/
    ├── databases/
    └── namespaces/
```

Flux reconciles a unique path for each cluster. An application base is reusable,
while cluster directories decide where it runs. Do not make OpenTofu render
Helm values or Kubernetes manifests.

Use an official Helm chart where one is well maintained. Use a generic chart
such as `bjw-s/app-template` for straightforward containers that lack a chart.
Some repetition in direct values files is preferable to a new generic
application renderer.

### Bootstrap and Recovery Chain

Git cannot contain every value required to rebuild the platform. Keep the
bootstrap chain short and document where each non-Git input is recovered:

```text
Talos machine secrets and configuration
        ↓
Kubernetes API and CNI
        ↓
Flux deploy key
        ↓
Flux controllers and platform definitions
        ↓
1Password Connect credentials
        ↓
External Secrets and application credentials
        ↓
Storage, ingress, observability, and applications
```

Talos machine secrets, the Flux bootstrap credential, the 1Password Connect
credentials, backup encryption keys, and any age or SOPS recovery keys must
have an off-cluster recovery copy. A cluster is not recoverable merely because
its non-secret manifests are in Git.

The current repository consumes 1Password Connect but does not declare where
Connect itself is hosted or recovered. Record that service's location, vault
credentials, backup expectations, and failure behaviour before applications
depend on it for cluster startup. The GCS OpenTofu state backend and its Google
credentials likewise remain part of foundation recovery while OpenTofu owns
external infrastructure.

The initial bootstrap should install only the CNI and Flux directly. Flux can
then install the remaining controllers in dependency order. Do not make Flux
depend on a secret that only an ExternalSecret managed by Flux can create
without retaining a documented manual bootstrap path.

### Routing

Internal application communication uses Kubernetes Services and DNS:

```text
http://cliproxyapi.ai.svc.cluster.local
```

LAN traffic can use MetalLB and Traefik. Public traffic can continue to use
Cloudflare Tunnel:

```text
Internet → Cloudflare → Cloudflared → Traefik → Service → Pod
```

Assign each DNS record to exactly one controller. For example, external-dns may
own Kubernetes application records while OpenTofu owns appliance, account, and
non-Kubernetes records. Do not allow both systems to manage the same hostname.

### Secrets and External Resources

External Secrets can read selected 1Password fields into Kubernetes Secrets:

```text
1Password → ExternalSecret → Kubernetes Secret → Pod
```

1Password is the durable secret inventory; Kubernetes Secrets are disposable
runtime copies. Restrict Secret access with namespace RBAC and enable
encryption at rest for the Kubernetes API data store.

The current OpenTofu reconciler also creates 1Password items, generates scalar
fields, preserves manually populated placeholders, maintains URLs, and prunes
owned fields and items. External Secrets does not automatically reproduce that
ownership model. Choose whether future item structure is human-managed in
1Password or created through `PushSecret`, and never let both systems write the
same field.

Credentials created through a Kubernetes controller need the reverse path:

```text
Crossplane → Kubernetes Secret → PushSecret → 1Password
                                             ↓
                                  ExternalSecret → Pod
```

Use `PushSecret` with `deletionPolicy: None` for write-once credentials so
deleting a Kubernetes object cannot delete the durable copy. Use
`updatePolicy: Replace` for deliberate rotation. There is still a brief
non-transactional interval between external creation and the push to
1Password; do not delete or rotate the external resource until the push reports
healthy.

Secret consumption is different from secret creation. Pocket ID clients,
Resend keys, B2 buckets, Cloudflare policy, and similar external resources need
one authoritative lifecycle owner.

Keep these in a reduced OpenTofu foundation initially. The existing providers
and reviewed plan are cleaner than introducing Crossplane HTTP reconciliation
for write-once keys. OpenTofu should cease deploying applications but may still
register application dependencies with external providers.

Crossplane is a Kubernetes control plane for external APIs, conceptually like a
continuously reconciling infrastructure provider. It is worthwhile where a
mature provider exists. Resend and Pocket ID would likely require generic HTTP
lifecycle definitions, creating duplicate-key, adoption, deletion, and secret
recovery risks. Do not adopt Crossplane unless a proof of concept demonstrates
less ownership and code than the reduced OpenTofu alternative.

Use the following initial ownership boundary:

| Resource                       | Initial owner      | Kubernetes alternative           | Transfer condition                                         |
| ------------------------------ | ------------------ | -------------------------------- | ---------------------------------------------------------- |
| 1Password item structure       | OpenTofu           | External Secrets `PushSecret`    | Field ownership and deletion semantics are unambiguous     |
| Application deployment         | Existing deployers | Flux and Helm                    | Parallel deployment and rollback have been tested          |
| Backblaze B2                   | OpenTofu           | Mature Crossplane provider       | Import, deletion, and credential recovery are proven       |
| Cloudflare account policy      | OpenTofu           | Crossplane provider              | DNS and policy ownership are divided without overlap       |
| Cloudflare application records | OpenTofu           | `external-dns`                   | Each DNS record has exactly one controller                 |
| Pocket ID clients              | OpenTofu           | Generic Crossplane HTTP resource | Adoption and client-secret recovery are proven             |
| Resend API keys                | OpenTofu           | Generic Crossplane HTTP resource | One-time tokens reach 1Password before deletion is enabled |
| Tailscale policy               | OpenTofu           | Retain outside Kubernetes        | The policy still covers non-Kubernetes devices             |
| UniFi                          | OpenTofu           | Retain outside Kubernetes        | No migration is currently justified                        |

The first Crossplane proof of concept should create one disposable Resend
`sending_access` key, retain its ID and one-time token in a Kubernetes Secret,
push both fields into 1Password, restore the application Secret from
1Password, and test deletion and whole-cluster recovery. Resend supports create,
list, and delete but does not return a stored token again, so observation must
filter the list response and preserve the creation response. The proof succeeds
only if the result is simpler than the current `modules/resend` implementation.

### Storage and Databases

TrueNAS remains the storage system. Kubernetes consumes storage through CSI
storage classes, for example:

| Storage class     | Intended use                                   |
| ----------------- | ---------------------------------------------- |
| `truenas-nfs`     | Shared files, media, and other RWX data        |
| `truenas-iscsi`   | Single-writer application and database volumes |
| `local-ephemeral` | Replaceable caches and temporary data          |

`democratic-csi` supports TrueNAS/ZFS NFS and iSCSI provisioning, snapshots,
clones, and resizing, but its newer TrueNAS SCALE API drivers are experimental.
Test provisioning, expansion, snapshots, node drain, deletion, and restore
before migrating a service. Start with `Retain` reclaim policies so deleting a
Kubernetes claim cannot automatically destroy important data.

Do not present AU TrueNAS storage to US or remote OCI workloads as though it
were local storage.

CloudNativePG is the preferred off-the-shelf operator for PostgreSQL workloads.
Use database-native backups, WAL archiving, and tested point-in-time recovery
rather than relying only on PVC snapshots. Other PVCs require an explicit
backup and restore system such as VolSync, together with TrueNAS snapshots and
an off-site copy.

### TrueNAS and Doco-CD Transition

The current TrueNAS repository deploys both catalogue applications and custom
Compose applications through the TrueNAS API. The Docker repository separately
publishes SOPS-encrypted OCI packages that Doco-CD reconciles. Kubernetes should
replace these delivery paths instead of adding another adapter between them.

Plain Compose workloads do not become first-class TrueNAS catalogue entries.
Doco-CD pre- and post-deployment hooks could create and remove TrueNAS custom
applications, but that would couple two reconcilers and preserve custom glue.
Do not build that bridge as part of the Kubernetes migration.

TrueNAS remains authoritative for ZFS datasets, snapshots, shares, and storage
exports. Kubernetes owns PVCs that consume explicitly exported storage. The
existing host-path relationships require deliberate migration:

- Bichon and Papra use dedicated host datasets.
- BookOrbit and Shelfmark share the BookOrbit book-drop dataset.
- Immich reads the iCloud Photos dataset and owns its main library and database
  data.
- RoMM uses shared assets, library, resources, PostgreSQL, and runner-visible
  games paths.
- Syncthing has broad access to both main TrueNAS mount trees.

Do not run the same application concurrently from TrueNAS and Kubernetes
against one writable dataset. Use a snapshot, application-consistent export, or
database-native migration, then give write ownership to exactly one platform.

Remove `homelab-truenas` only when no application implementation, sidecar,
catalogue value, or self-hosted runner still depends on it. Remove
`homelab-docker` only when every Doco-CD target has migrated or been explicitly
retained as a standalone Compose host.

### Observability and Automation

The hypothetical platform could use:

- Actions Runner Controller for GitHub runners.
- Fly-hosted Gatus for an external availability vantage point.
- Grafana for dashboards.
- Homepage annotations for local application discovery.
- Renovate for chart, image, Talos, Kubernetes, and controller updates.
- VictoriaLogs or Loki for aggregated logs.
- VictoriaMetrics Kubernetes stack for metrics.

Docker-socket-dependent Dozzle and Beszel agents do not translate directly to
containerd. Prefer Kubernetes-native metrics and log collection.

## Workload Fit

Most ordinary web services can run in Kubernetes, but their current inputs and
outputs determine the migration effort. The repository inventory gives the
following initial disposition:

| Service         | Important dependency or behaviour                           | Initial Kubernetes disposition                             |
| --------------- | ----------------------------------------------------------- | ---------------------------------------------------------- |
| Actual Budget   | OIDC and persistent application data                        | Early stateful pilot after CSI and restore testing         |
| AIOMetadata     | Local Redis and persistent metadata                         | Move after basic PVC and backup support                    |
| AIOStreams      | Persistent configuration and generated secret               | Move after basic PVC and secret support                    |
| Anisette        | Small persistent identity directory                         | Early stateful workload                                    |
| Beszel          | Mail, OIDC, B2, and persistent hub data                     | Replace or move after observability design                 |
| Beszel Agent    | Host networking, Docker socket, and host metrics            | Replace with Kubernetes-native node telemetry              |
| Bichon          | Dedicated TrueNAS mail archive dataset                      | Move only after dataset and restore testing                |
| Bifrost         | Persistent data and imports two internal API credentials    | Move with its dependency group                             |
| BookOrbit       | PostgreSQL and shared book-drop and library datasets        | Late stateful migration                                    |
| Byparr          | Replaceable screenshot data                                 | Early application candidate                                |
| CLI Proxy API   | Persistent authentication material                          | Move after secret and PVC recovery testing                 |
| Cloudflared     | Cluster public-ingress boundary                             | Replace target instances with a cluster deployment         |
| Comfy Control   | Many external API keys, persistent data, and internal APIs  | Move after its dependency and secret model is proven       |
| Dozzle          | Docker API and generated agent certificates                 | Replace with Kubernetes-native log collection              |
| Dozzle Agent    | Docker socket                                               | Do not migrate                                             |
| Gatus           | External failure vantage point, mail, and Tailscale         | Retain on Fly                                              |
| GitHub Runner   | Ephemeral runners with repository credentials               | Replace with Actions Runner Controller                     |
| Grafana         | OIDC, provisioned files, plugins, and persistent data       | Deploy through a maintained Kubernetes chart               |
| Homepage        | Generated cards, Docker discovery, and appliance widgets    | Use local discovery plus explicit external entries         |
| Immich          | PostgreSQL, Redis, photo datasets, and iCloud Photos input  | Move last after database and storage recovery tests        |
| LaraPaper       | SQLite and generated-image storage                          | Move after single-writer PVC testing                       |
| Linkwarden      | PostgreSQL, Meilisearch, mail, OIDC, and persistent data    | Late stateful migration                                    |
| Miniflux        | PostgreSQL, OIDC, and Homepage API credential               | Good CloudNativePG application pilot                       |
| Netboot         | PXE, LAN, and layer-two behaviour                           | Retain on a dedicated host unless proven in-cluster        |
| OAuth2 Proxy    | Shared OIDC forward authentication                          | Deploy centrally or replace with ingress-native auth       |
| Open WebUI      | Redis, model data, OIDC, and potential GPU dependency       | Move after storage and accelerator scheduling are proven   |
| OpenSpeedTest   | Stateless HTTP application                                  | First real migration candidate                             |
| Papra           | Dedicated document dataset, OIDC, and external AI key       | Late stateful migration                                    |
| Pocket ID       | Identity-provider database, mail, and bootstrap credentials | Move only after independent recovery and break-glass tests |
| Redlib          | Control D sidecar and shared Pod networking                 | Early candidate using a two-container Pod                  |
| RoMM            | PostgreSQL, Redis, several datasets, and external metadata  | Move last with the games workflow                          |
| RoMM Workflows  | Runner mounts and guarded games-library operations          | Retain storage-local or prove ARC with the same mounts     |
| Shelfmark       | Shared BookOrbit book-drop and external metadata APIs       | Move with BookOrbit                                        |
| Syncthing       | Broad access to both TrueNAS storage trees                  | Retain beside TrueNAS initially                            |
| Tailscale       | Cluster and non-Kubernetes network boundary                 | Replace app instances with the Tailscale operator          |
| Traefik         | Host networking, Docker socket, ACME, and generated labels  | Replace with cluster ingress or Gateway API                |
| VictoriaMetrics | Metrics storage, scraping, and Graphite listener            | Deploy through its operator after telemetry design         |

HAOS, UniFi, TrueNAS, and Bazzite remain appliances or hosts. The AU HSP OCI VM
and US Hotdog VM remain infrastructure decisions rather than workloads; either
can host a separate Talos cluster, but neither should become a remote worker in
the home cluster.

Migration groups must preserve service imports. Bifrost currently depends on
CLI Proxy API and Comfy Control; Comfy Control also depends on CLI Proxy API.
BookOrbit and Shelfmark share storage. RoMM and RoMM Workflows share storage and
operational safety gates. Move each group together or provide a temporary,
explicit cross-platform route while ownership is transferred.

## Migration Principles

If the production migration is pursued:

1. Build a new Talos cluster alongside the existing platform.
2. Bootstrap Flux and core networking.
3. Connect one test secret from 1Password.
4. Move disposable stateless applications first.
5. Prove TrueNAS storage and restore before moving stateful applications.
6. Run old and new deployments in parallel behind temporary hostnames.
7. Cut routing only after validation.
8. Stop but retain the old deployment during the rollback window.
9. Remove its old OpenTofu deployment ownership without destroying shared
   external resources.
10. Delete the old deployment only after backup and rollback tests succeed.

Do not combine workload migration, OpenTofu state splitting, and backend
migration in one change. Preserve stable resource identities and use reviewed
OpenTofu plans for every ownership transfer.

The recovery test for a migrated service is:

1. Recreate the cluster or node configuration.
2. Let Flux restore the platform from Git.
3. Restore secrets from 1Password.
4. Restore persistent data from backup.
5. Confirm external resources are adopted rather than duplicated.
6. Confirm routing can be returned to the old deployment.

## Delivery Plan

### Phase 0: Learn Locally

1. Recreate the disposable OrbStack Talos cluster without reusing a homelab
   subnet.
2. Deploy, expose, scale, and deliberately break a direct-manifest workload.
3. Learn ConfigMaps, Secrets, probes, resources, volumes, scheduling, and Helm.
4. Delete the cluster and repeat from documented commands.

Exit when the cluster is disposable rather than precious.

### Phase 1: Build a Persistent Lab

1. Create one Talos VM without changing a production server.
2. Install a simple CNI and bootstrap Flux.
3. Create a dedicated Git path for that cluster.
4. Deploy OpenSpeedTest through Flux.
5. Rebuild the VM and confirm Flux restores the application.

Do not add ingress, storage, Crossplane, or External Secrets until the direct
GitOps loop works.

### Phase 2: Add One Platform Capability at a Time

1. Add ingress and a temporary hostname.
2. Add cert-manager and prove certificate renewal.
3. Add External Secrets and fetch one test credential from 1Password.
4. Add observability sufficient to diagnose the control plane and workloads.
5. Add TrueNAS CSI with a disposable dataset and `Retain` reclaim policy.
6. Test provisioning, snapshots, expansion, node drain, deletion, and restore.

Record the bootstrap input, owner, recovery procedure, and removal procedure for
each controller before adding the next one.

### Phase 3: Prove a Real Application

1. Move OpenSpeedTest first.
2. Move one low-risk stateful service such as Actual Budget or Anisette.
3. Move Miniflux with CloudNativePG as the first database-backed proof.
4. Run each old and new deployment in parallel behind different hostnames.
5. Exercise backup, restore, secret recovery, routing cutover, and rollback.

Keep the production OpenTofu and deployment repositories authoritative during
these proofs.

### Phase 4: Establish the Production Cluster

1. Decide whether home availability requires three independent control-plane
   nodes or accepts a single failure domain.
2. Keep remote OCI and US locations as separate clusters.
3. Add Cilium only if its policy, observability, or load-balancing features are
   now required.
4. Add MetalLB only if applications need direct LAN `LoadBalancer` addresses.
5. Add the Tailscale operator at cluster boundaries rather than per Pod.

Exit when node replacement, Talos upgrades, Kubernetes upgrades, etcd recovery,
and off-cluster monitoring have all been exercised.

### Phase 5: Migrate by Dependency Group

1. Move disposable and stateless web applications.
2. Replace Docker-specific monitoring and logging agents.
3. Move isolated PVC workloads.
4. Move database-backed workloads after point-in-time recovery is proven.
5. Move the Bifrost, CLI Proxy API, and Comfy Control dependency group.
6. Move the BookOrbit and Shelfmark shared-storage group.
7. Move Immich and its external photo input.
8. Move RoMM and its workflow runner only after storage-local safety is
   equivalent.
9. Retain Netboot and Syncthing outside Kubernetes unless migration provides a
   clear operational improvement.

### Phase 6: Reduce the Old Control Plane

1. Stop publishing Kubernetes application deployment context through GitHub
   `CONFIG` variables.
2. Remove Homepage, routing-label, and published-port generation that Flux and
   cluster discovery have replaced.
3. Transfer external resource ownership individually with reviewed OpenTofu
   plans and imports where required.
4. Remove `homelab-docker` after its final Doco-CD target is gone.
5. Remove `homelab-truenas` after its final application and sidecar is gone.
6. Retain `homelab-fly` for Gatus and `homelab-workflows` for any remaining
   storage-local workflow.
7. Simplify `homelab` to servers, networks, appliances, external providers, and
   any intentionally retained credentials.

The migration is complete only when a new operator can identify every
authoritative system, rebuild a cluster, restore a service, rotate a credential,
and roll back a deployment without relying on undocumented state.

## Potential Outcome

A successful Kubernetes migration could remove:

- The TrueNAS catalogue and deployment repository.
- Most or all of the Docker deployment repository.
- Compose and catalogue template rendering.
- GitHub `CONFIG` deployment payloads and workflow dispatch deployers.
- Published-port allocation.
- Traefik label generation.
- Homepage generation.
- Per-service server targets.
- Most service runtime aggregation.

OpenTofu would remain for infrastructure and mature external providers. This is
intentional: a small direct OpenTofu foundation is cleaner than moving every
external API behind a less mature Kubernetes controller.

Kubernetes would exchange custom HCL, templates, and deployment scripts for a
set of upstream controllers. That may improve standardisation, reconciliation,
portability, and learning, but does not guarantee fewer moving parts. Migration
should proceed only where the resulting ownership boundary is demonstrably
simpler than the current working system.

## References

- [Actions Runner Controller](https://docs.github.com/en/actions/tutorials/use-actions-runner-controller)
- [Cilium documentation](https://docs.cilium.io/)
- [CloudNativePG](https://cloudnative-pg.io/)
- [Crossplane HTTP provider](https://github.com/crossplane-contrib/provider-http)
- [democratic-csi](https://github.com/democratic-csi/democratic-csi)
- [External Secrets 1Password Connect provider](https://external-secrets.io/latest/provider/1password-automation/)
- [External Secrets PushSecret](https://external-secrets.io/latest/guides/pushsecrets/)
- [Flux documentation](https://fluxcd.io/flux/)
- [Homepage Kubernetes discovery](https://gethomepage.dev/configs/kubernetes/)
- [Kubernetes documentation](https://kubernetes.io/docs/)
- [MetalLB concepts](https://metallb.io/concepts/)
- [Talos documentation](https://docs.siderolabs.com/talos/)
- [Tailscale Kubernetes operator](https://tailscale.com/docs/features/kubernetes-operator)
- [VictoriaMetrics Kubernetes operator](https://docs.victoriametrics.com/operator/)
