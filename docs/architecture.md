# Architecture

This repository is the control plane for a YAML-defined homelab. Files in
`data/` describe DNS zones, servers, services, global config, and defaults.
OpenTofu loads that data, computes stable models, provisions provider
resources, stores credentials, and renders deployment artifacts.

## Data Flow

The root HCL files are organized as staged pipelines:

1. `*_input.tf` loads YAML and applies defaults.
2. `*_model.tf` computes deterministic fields that are safe for `for_each`.
3. `*_outputs.tf` overlays provider-backed runtime values and credentials.
4. `*_render.tf` and platform files render deployment artifacts.
5. `*_validation.tf` enforces cross-file and relationship rules with
   `terraform_data` preconditions.

The model layer is the boundary between input data and provider resources.
Resource keys and collection membership should come from input/model data, not
runtime values.

## Model And Runtime Boundaries

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

Services expand into one modeled service per target. Each expanded service may
render artifacts for one or more deployment paths:

- Fly services render `fly.toml`, optional cert and scale files, plus sidecars.
- TrueNAS services prefer catalog `app.json.tftpl` and fall back to custom
  Compose when only `docker-compose.yaml.tftpl` exists.
- Komodo receives Docker Compose stacks for Docker-capable server targets.

Rendered artifacts are SOPS-encrypted through `modules/github_file_encrypted`
and pushed to the platform-specific GitHub repositories configured in
`data/config.yml`.

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

Within this repo, prefer small modules only when they remove real duplication.
The encryption/write path is already shared by `modules/github_file_encrypted`;
Fly, TrueNAS, and Komodo keep separate root files because their deployment
request formats and SOPS rules are platform-specific.
