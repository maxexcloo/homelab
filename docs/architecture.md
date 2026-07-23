# Architecture

This repository is the control plane for a YAML-defined homelab. Files in
`data/` describe DNS zones, servers, services, global config, and defaults.
OpenTofu loads that data, computes stable models, provisions provider
resources, stores credentials, and renders deployment artifacts.

## Data Flow

Each domain module is organized as a staged pipeline:

1. `{domain}_input.tf` loads YAML and applies defaults.
2. `{domain}_model.tf` computes deterministic fields that are safe for `for_each`.
3. Runtime files overlay provider-backed values and credentials.
4. Render files produce bootstrap and deployment artifacts.
5. `{domain}_validation.tf` enforces cross-file and relationship rules with
   `terraform_data` preconditions.

Service-specific cross-service aggregation belongs in
`modules/services/services_render_custom_*.tf`. Other render stages stay
service-agnostic.

The model layer is the boundary between input data and provider resources.
Resource keys and collection membership should come from input/model data, not
runtime values.

`dns_model_routes` is the shared routing boundary for DNS providers. It gives
each server route, service route, and redirect a stable key plus its hostname,
managed zone, public target, serving server, and tunnel origin. Cloudflare and
Control D derive their provider-specific resources from this shape.

## Model & Runtime Boundaries

Each server and service has two shapes:

- `*_model` contains YAML input plus deterministic computed fields.
- runtime objects add provider-backed addresses, URLs, attributes, hosts, and
  credentials.

Use model locals for resource keys and filters. Runtime values can be unknown at
plan time, so they should only feed resource arguments, outputs, and render
content after the resource address set is already fixed.

## Data Contracts

JSON Schemas in `schemas/` define the YAML API. They validate both source YAML
and default-merged objects via `scripts/validate_data.py`.

Use schemas for shape and type checks. Use HCL validation locals for
cross-resource relationships that need the expanded model, such as missing
targets, invalid routes, duplicate IDs, or unmanaged DNS.

Defaults from `data/config.yml` and `data/defaults.yml` are deep-merged before
models are built. Per-resource YAML should usually contain only overrides.

## Service Deployment

Services expand into one modeled service per target. Each expanded service
renders through its target platform:

- Docker services render Compose projects on Docker hosts.
- Fly services render `fly.toml`, optional cert and scale files, plus sidecars.
- TrueNAS services prefer catalog `app.json.tftpl` and fall back to custom
  Compose when only `docker-compose.yaml.tftpl` exists.

Rendered artifacts are SOPS-encrypted through `modules/github_file_encrypted`
and written to the platform repositories configured in `data/config.yml`.

Those deployment repositories are generated outputs, not independent sources
of truth. Repository-owned files, workflows, and Renovate disablement are also
managed here and published by OpenTofu.

Template inventory is discovered by file name:

- `app.json.tftpl` is handled by the TrueNAS catalog renderer.
- `docker-compose.yaml.tftpl` is handled by Compose renderers.
- Other files under `templates/services/<identity.service>/` become sidecars.
- `.tftpl` files are rendered and have the suffix stripped.
- `.raw.tftpl` files are rendered, have `.raw.tftpl` stripped, and are encrypted
  as binary.

## When To Split

Keep this as one OpenTofu stack while the graph benefits from shared DNS,
credential, service, and server context. Consider splitting only if applies
become operationally painful, provider credentials need hard isolation, or a
low-risk service deploy should not share a plan with core infrastructure.

Use a module only when it removes real duplication or defines a stable
boundary. The encryption/write path is shared, while Docker, Fly, and TrueNAS
remain separate because their deployment requests and SOPS rules differ.

Reusable capability modules own duplicated provider lifecycles:

- `modules/credentials` generates scalar credentials, X.509 material, and
  password hashes.
- `modules/object_storage` provisions isolated B2 buckets and application keys.
- `modules/onepassword` reads and persists generic 1Password Connect items.

`modules/servers` owns server YAML input, deterministic modeling, credentials,
runtime enrichment, rendered bootstrap content, webhooks, Cloudflare tunnels
and tokens, and the Incus and OCI compute lifecycle.

`modules/services` owns service YAML input, deterministic modeling, credentials,
Pocket ID clients, runtime and template rendering, and Docker, Fly, and TrueNAS
deployment publications.

The root is the composition layer. It loads shared config and DNS data,
configures providers, and owns only cross-domain DNS, routing, repository,
Tailscale, tunnel ingress, and access policy. Module outputs create the
dependency graph directly; there are no fingerprint marker resources or broad
module-level `depends_on` lists.

The two root calls live in `servers.tf` and `services.tf`. Their contracts are
kept broad: merged `defaults`, shared DNS data, and provider-facing
`integrations`; the service module additionally receives the server module's
model/runtime/render interface. Each module exposes its deterministic model for
shared root consumers. Default provider configurations inherit from the root,
while aliased REST providers are passed explicitly.
