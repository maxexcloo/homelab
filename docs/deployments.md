# Deployments

Service artifacts are rendered from `templates/services/<identity.service>/`
and encrypted before they are written to deployment repositories.

Deployment repositories are generated outputs. Do not edit their files or
merge dependency updates there; make changes in this repository and publish
them through a reviewed OpenTofu apply. OpenTofu writes `renovate.json` with
`enabled: false` to each deployment repository so dependency updates originate
from the authoritative templates here.

## File Discovery

- `app.json.tftpl` is handled by the TrueNAS catalog renderer.
- `docker-compose.yaml.tftpl` is handled by Docker and custom TrueNAS Compose
  renderers.
- Other files under the service template directory become sidecars.
- `.tftpl` files are rendered and have the suffix stripped.
- `.raw.tftpl` files are rendered, have `.raw.tftpl` stripped, and are encrypted
  as binary.

Content type is inferred from the rendered file extension:

- `.env` becomes `dotenv`
- `.json` becomes `json`
- `.yaml` and `.yml` become `yaml`
- everything else becomes `binary`

## Docker

Docker targets render into the `docker` deployment repository for doco-cd.
Servers opt in with `features.docker`.

Each Docker server gets a target-specific deployment config:

- `.doco-cd.<server>.yml`
- `<server>/<service>/compose.yaml`
- sidecars under `<server>/<service>/...`

The target config is plaintext because doco-cd must parse it before deployment
decryption. It contains no credentials and uses auto-discovery with
`working_dir: <server>` and `depth: 1`, so each service directory becomes one
Compose project. Deleted service directories are removed by doco-cd, but
volumes are preserved.

All deployment files are SOPS-encrypted to the target server's age key. The
cloud-init and setup-script bootstrap writes `/opt/doco-cd/sops_age_key.txt`,
sets `SOPS_AGE_KEY_FILE`, configures polling against the `docker` repo with
`target: <server>`, and also sets `WEBHOOK_SECRET` for later webhook use.

The doco-cd container binds HTTP to `127.0.0.1:8089` and metrics to
`127.0.0.1:9120`. Traefik publishes its HTTP endpoints internally at
`doco-cd.<server internal host>` with the existing `internal-only@docker`
middleware. Cloudflare Tunnel can expose only the target-specific webhook path
at `doco-cd.<server external host>/v1/webhook/<server key>`.

## Fly

Fly targets render into the Fly deployment repository under the Fly app name.
If `targets.fly.fly.app_name` is empty, the app name defaults to
`<organization.name>-<identity.name>`.

Rendered files:

- `fly.toml`
- `.certs` when the service has custom URLs
- `.machine-count` when `fly.machine_count` is non-null
- sidecars

Fly uses one shared age key for the repository. The deploy request hashes the
rendered file content, the SOPS recipient key, and the workflow revision.

## TrueNAS

TrueNAS targets render under `<server>/<service>/` in the TrueNAS deployment
repository.

TrueNAS prefers catalog apps:

- If `app.json.tftpl` exists, render `app.json`.
- Otherwise, if `docker-compose.yaml.tftpl` exists, render `compose.json`.
- Sidecars are always included.

Each TrueNAS server has its own age key and GitHub Actions secret. The secret
name is `AGE_KEY_<SERVER_KEY>` with hyphens converted to underscores and letters
uppercased.

The deploy request stores a sorted file list and a hash. The workflow uses the
file lists to update, add, or remove managed sidecars.

## Debug Rendering

`mise run render` runs a refresh-free plan with `debug_dir` set. The encryption
module writes plaintext copies of rendered artifacts under that directory while
still producing encrypted repository content.
