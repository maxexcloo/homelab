# Deployments

Service artifacts are rendered from `templates/services/<identity.service>/`
and encrypted before they are written to deployment repositories.

## File Discovery

- `app.json.tftpl` is handled by the TrueNAS catalog renderer.
- `docker-compose.yaml.tftpl` is handled by Compose renderers.
- Other files under the service template directory become sidecars.
- `.tftpl` files are rendered and have the suffix stripped.
- `.raw.tftpl` files are rendered, have `.raw.tftpl` stripped, and are encrypted
  as binary.

Content type is inferred from the rendered file extension:

- `.env` becomes `dotenv`
- `.json` becomes `json`
- `.yaml` and `.yml` become `yaml`
- everything else becomes `binary`

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
