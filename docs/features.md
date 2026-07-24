# Features

Feature flags either provision provider resources, add credentials, render
config, or select automatic targets.

Defaults live in `data/defaults.yml`. Server and service YAML files usually
only set overrides.

Service-facing names stay provider-neutral. The current implementations are
Resend for `mail`, Backblaze B2 for `object_storage`, and Pocket ID for `oidc`.
Changing a default provider should preserve the feature names and runtime
credential interface.

## Server Features

- `beszel` creates a Beszel agent service target, adds agent credential fields,
  and installs the agent in generated setup artifacts when bootstrap is enabled.
- `bootstrap` renders platform-specific bootstrap artifacts. TrueNAS servers
  also receive a `truenas_cd_access_token` credential.
- `cloudflare_acme` provisions an ACME DNS token for the ACME zone.
- `cloudflare_acme_legacy` provisions an ACME DNS token for external and
  internal zones.
- `cloudflared` provisions a Cloudflare tunnel and tunnel credentials.
- `docker` installs Docker, renders Docker Compose deployments to the Docker
  repo, and installs doco-cd in generated setup artifacts.
- `dozzle` includes the server in the central Dozzle remote-agent list.
- `mail` provisions credentials for the default SMTP provider.
- `monitoring` includes the server in generated monitoring config.
- `monitoring_alerts` attaches generated monitoring alerts when monitoring is
  enabled.
- `monitoring_external` adds a public ICMP check when the server has a public
  hostname or IP address.
- `object_storage` provisions storage through the default S3-compatible provider.
- `password` adds a server password and password hash.
- `tailscale` provisions a Tailscale auth key and service target, and installs
  Tailscale in generated setup artifacts when bootstrap is enabled.
- `zfs` marks the server for ZFS-related config.

All servers also get read-only `age_secret_key` credentials.

## Service Features

- `mail` provisions credentials for the default SMTP provider and exposes the
  generic `mail_*` runtime values.
- `monitoring` includes the service in generated monitoring config and exposes a
  per-target `monitoring_token` runtime credential.
- `monitoring_alerts` attaches generated monitoring alerts when monitoring is
  enabled.
- `object_storage` provisions storage through the default S3-compatible provider
  and exposes generic `object_storage_*` runtime values.
- `oidc` provisions a client through the configured identity provider.
- `oidc_forward_auth` protects generated Traefik routes with the shared OAuth2
  Proxy forward-auth middleware. Monitored routes also receive a per-target
  Basic Auth route for machine clients such as Gatus and Homepage.
- `password` adds a service password and password hash.
- `tailscale` provisions a Tailscale auth key.

Target-level `features` deep-merge over service-level features.

## Target Selection

Services can use `target_feature` to target every server where that feature is
true. Explicit `targets` are merged over automatic targets, so they can override
per-target data, features, credentials, Fly settings, or TrueNAS settings.

## Credentials

Feature-created provider values are usually read-only and appear in 1Password
with `_ro` labels. User-entered or generator-seeded values are read-write and
appear with `_rw` labels. Password-purpose fields use the bare field label.

Named `credentials.generated` entries provision typed credentials. Scalar
types seed read-write 1Password fields. The `x509` type provisions an Ed25519
private key and self-signed certificate as paired read-only runtime credentials.
