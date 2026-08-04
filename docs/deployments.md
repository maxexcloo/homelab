# Deployments

Docker and Fly repositories own their service implementations, workflows, and
dependency updates. OpenTofu owns repository governance and publishes a small
non-secret `CONFIG` variable to each repository. TrueNAS artifacts remain
rendered from this repository.

## File Discovery

- `app.json.tftpl` is handled by the TrueNAS catalog renderer.
- `docker-compose.yaml.tftpl` is handled by the custom TrueNAS Compose renderer.
- Other files under the service template directory become sidecars.
- `.tftpl` files are rendered and have the suffix stripped.
- `.raw.tftpl` files are rendered, have `.raw.tftpl` stripped, and are encrypted
  as binary.

Content type is inferred from the rendered file extension:

- `.env` becomes `dotenv`
- `.json` becomes `json`
- `.yaml` becomes `yaml`
- everything else becomes `binary`

## Docker

Docker services and Compose templates live in the Docker deployment repository.
Servers opt in with `features.docker`; OpenTofu publishes their stable
deployment identity, non-secret runtime data, age recipient, and programmatic
1Password references.

Each Docker server gets a target-specific deployment config:

- `.doco-cd.<server>.yaml`
- `<server>/<service>/compose.yaml`
- sidecars under `<server>/<service>/...`

The target config is plaintext because doco-cd must parse it before deployment
decryption. It contains no credentials and uses auto-discovery with
`working_dir: <server>` and `depth: 1`, so each service directory becomes one
Compose project. Deleted service directories are removed by doco-cd, but
volumes are preserved.

GitHub Actions renders plaintext Compose files and streams secret `.env`, PEM,
and other secret files directly from 1Password into SOPS using the target age
recipient. Plaintext secrets are never written to disk or committed. Doco-cd
holds only its target age key and deploys through the local Docker socket.

The bootstrap writes `/opt/doco-cd/sops_age_key.txt`, sets
`SOPS_AGE_KEY_FILE`, configures repository polling with `target: <server>`, and
sets `WEBHOOK_SECRET` for webhook use.

The doco-cd container binds HTTP to `127.0.0.1:8089` and metrics to
`127.0.0.1:9120`. Traefik publishes its HTTP endpoints internally at
`doco-cd.<server internal host>` with the existing `internal-only@docker`
middleware. Cloudflare Tunnel can expose only the target-specific webhook path
at `doco-cd.<server external host>/v1/webhook/<server key>`.

## Fly

Fly service implementations live in the Fly deployment repository. Its workflow
renders the selected deployment, resolves 1Password references in memory,
reconciles certificates and secrets, deploys with `flyctl`, and applies the
configured machine count.

## TrueNAS

TrueNAS targets render under `<server>/<service>/` in the TrueNAS deployment
repository.

TrueNAS prefers catalog apps:

- If `app.json.tftpl` exists, render `app.json`.
- Otherwise, if `docker-compose.yaml.tftpl` exists, render `compose.json`.
- Sidecars are always included.

Each TrueNAS server has its own age key. The key is included in its sensitive
`bootstrap_truenas_custom_apps` output and stays local to the target's
`truenas-cd` runner.

The deploy request stores a sorted file list and a hash. The workflow uses the
file lists to update, add, or remove managed sidecars. A sidecar destination
must be backed by writable managed storage exposed by the catalog or custom app:
either a Docker volume or an app-scoped TrueNAS `ix_volume`. Deployment fails
rather than writing to a container layer or an arbitrary host-path bind.
Changed sidecars are followed by an app redeploy so the app reads the new
volume content.

The workflow reads the app's reported volume mounts and copies through the
mounted container path. It does not depend on TrueNAS dataset paths or Docker
volume names. After creating or updating an app, the workflow starts it when
TrueNAS reports any state other than `RUNNING`.

Retrieve the copy/paste custom app definition for a server with:

```bash
tofu output -json bootstrap_truenas_custom_apps | jq -r '.["au-truenas"]'
```

## Debug Rendering

`mise run render` runs a refresh-free plan with `debug_dir` set. The encryption
module writes plaintext copies of rendered artifacts under that directory while
still producing encrypted repository content.
