# Features

Feature flags either provision provider resources, add credentials, render
config, or select automatic targets.

Defaults live in `data/defaults.yml`. Server and service YAML files usually
only set overrides.

## Service Features

- `b2` provisions a Backblaze bucket and application key. It exposes
  `runtime.attributes.b2_*` and read-only `b2_application_key`.
- `monitoring` includes the service in generated monitoring config.
- `monitoring_alerts` attaches generated monitoring alerts when monitoring is
  enabled.
- `password` adds a service password and password hash.
- `resend` provisions a Resend API key.
- `tailscale` provisions a Tailscale auth key.

Target-level `features` deep-merge over service-level features.

## Server Features

- `b2` provisions a Backblaze bucket and application key.
- `beszel` adds Beszel agent credential fields.
- `bootstrap` renders platform-specific bootstrap artifacts.
- `cloudflare_acme` provisions an ACME DNS token for the ACME zone.
- `cloudflare_acme_legacy` provisions an ACME DNS token for external and
  internal zones.
- `cloudflared` provisions a Cloudflare tunnel and tunnel credentials.
- `docker` installs Docker, renders Docker Compose deployments to the Docker
  repo, and installs doco-cd in generated setup artifacts.
- `monitoring` includes the server in generated monitoring config.
- `monitoring_alerts` attaches generated monitoring alerts when monitoring is
  enabled.
- `password` adds a server password and password hash.
- `resend` provisions a Resend API key.
- `tailscale` provisions a Tailscale auth key.
- `zfs` marks the server for ZFS-related config.

All servers also get read-only `age_secret_key` credentials.

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
