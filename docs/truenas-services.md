# TrueNAS Services

Follow this guide when creating or changing a service that deploys through a
TrueNAS community catalog app.

## Catalog schema

Look up the app in
[truenas/apps](https://github.com/truenas/apps/tree/master/trains/community)
before authoring anything. Read the latest version's `docker-compose.yaml`
template to identify:

- environment variables injected from `values.{app}.*`;
- storage keys mounted from `values.storage.*`;
- values hardcoded by the catalog template.

## Configuration

- Use app-specific keys in `app.json.tftpl` (`values.{app}.<key>`) for named
  app configuration exposed by the catalog. Do not repeat those values in
  `truenas.env`; the catalog would inject them again through `additional_envs`.
- Use `truenas.env` in service YAML for cross-cutting variables such as OIDC,
  mail, and base URLs that the catalog does not expose as named app fields.
- Match catalog key names exactly, such as `pocket_id` rather than `pocket-id`
  and `encrypt_password` rather than `encryption_password`.
- Do not duplicate environment variables or other values supplied from
  `values.consts.*` or hardcoded literals in the catalog template.
- Pass dollar signs in custom label values unchanged. The TrueNAS catalog
  renderer escapes them once for Docker Compose; pre-escaping values such as
  bcrypt hashes leaves doubled dollar signs in the final container label.

## Cross-service references

Declare cross-service references through `imports.services` with a
`snake_case` alias that points to the expanded `{name}-{target}` key. For
example:

```yaml
imports:
  services:
    pocket_id: pocket-id-au-truenas
```

Reference the imported service as `${services.pocket_id...}` in `truenas.env`
template strings. Do not hardcode the expanded service key in a template. The
alias must be a valid HCL identifier because `templatestring()` cannot parse
bracket notation such as `services["key-name"]`.

## Storage

Follow the catalog template's `add_storage()` calls exactly:

- Use `host_path` when the user supplies a host directory under
  `/mnt/truenas-nvme/<app>`.
- Use `ix_volume` otherwise.
- Do not add storage keys the catalog template does not reference.
- Mount every generated sidecar destination through writable `ix_volume`
  storage. The deployment workflow refuses to copy a sidecar into a container
  layer.

Follow the existing structures in `templates/services/aiostreams/`,
`templates/services/beszel/`, and `templates/services/grimmory/` for network
ports, storage, and app configuration.
