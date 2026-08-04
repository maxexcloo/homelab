# Credentials

Credentials are stored in 1Password through 1Password Connect. Set
`onepassword.enabled` in `data/config.yaml` to select the credential source:

- `true` reads existing values from 1Password and uses generated values as
  fallbacks for OpenTofu consumers.
- `false` skips all 1Password API calls and item writes. Generated credentials
  remain in sensitive OpenTofu state; target deployments cannot resolve their
  credential references until 1Password is enabled.

- Servers use the vault configured at `onepassword.vaults.servers.id`.
- Services use the vault configured at `onepassword.vaults.services.id`.

Provider access comes from `TF_VAR_onepassword_connect_url` and
`TF_VAR_onepassword_connect_token`. Both are required only when the integration
is enabled.

OpenTofu looks up items by exact title and requires every configured item to
exist. `mise run check-onepassword` compares the desired inventory without
writing. `mise run sync-onepassword` fills missing values and metadata while
preserving non-empty and unknown fields. Both stream the sensitive manifest
directly from state and print no values.

Pocket ID follows the same opt-in pattern. Set `pocketid.enabled` in
`data/config.yaml`; `TF_VAR_pocketid_url` and `TF_VAR_pocketid_api_token` are
required only while it is enabled. Disabling it skips discovery, application
configuration, OIDC clients, and the Cloudflare Access identity provider.
Planning fails while Pocket ID is disabled and any service still enables
`features.oidc`.

## Fields

Manually supplied credential fields are declared under `credentials.fields`.
The reconciler creates missing fields on the matching 1Password item. OpenTofu
temporarily reads required values back as `runtime.credentials.<name>`.

The 1Password item is built from the complete modeled credential map. Declared
fields, typed generators, and feature-created provider values are all surfaced;
there is no service-specific allowlist.

The server and service modules shape their domain-specific item payloads.
`modules/onepassword` owns exact-title search and reads; the external reconciler
owns writes. `modules/credentials` owns generated scalar values, X.509 material,
and bcrypt hashes.

Declared fields default to `credentials.rw` from `data/defaults.yaml`.
Read-write fields are created in 1Password even when empty, so values can be
entered manually later. Read-only fields are written from provider-generated
runtime values.

1Password field IDs and labels use the same `snake_case` name. Ownership mode
stays in repository configuration. Deployment configs publish the same field
names as `op://` references.

## Typed Generators

Typed credential generators are declared under `credentials.generated`:

```yaml
credentials:
  generated:
    api_secret:
      length: 32
      type: hex
```

Scalar generators let the reconciler create an initial value directly in a
read-write 1Password field:

- `hex` and `base64` lengths are byte counts.
- `alphanumeric` lengths are character counts.
- Generated password-style values use `special = false`.

Generation happens only when both the desired and stored value are empty.
Existing non-empty 1Password values always win, preserving later manual changes.

The `x509` generator creates an Ed25519 private key and self-signed certificate:

```yaml
credentials:
  generated:
    agent:
      type: x509
```

An X.509 generator named `agent` exposes read-only `agent_certificate` and
`agent_private_key` fields. Both values are stored in 1Password and sensitive
OpenTofu state. `common_name` and `validity_period_hours` may override their
global defaults.

## Generated Fields

Feature flags add credential fields automatically:

Services may receive:

- `mail`: read-only `mail_password`.
- `monitoring`: read-write `monitoring_token`.
- `object_storage`: read-only `object_storage_secret_access_key`.
- `oidc`: read-only `oidc_client_id` and, for confidential clients,
  `oidc_client_secret`.
- `password`: read-write `password` and read-only `password_hash`.
- `tailscale`: read-only `tailscale_auth_key`.

Servers may receive:

- `beszel`: read-write `beszel_agent_token` and `beszel_system_id`.
- `bootstrap`: read-write `truenas_cd_access_token` on TrueNAS servers.
- `cloudflare_acme`: read-only `cloudflare_acme_token`.
- `cloudflare_acme_legacy`: read-only `cloudflare_acme_legacy_token`.
- `cloudflared`: read-only tunnel and tunnel-read tokens.
- Docker hosts share the sensitive `homelab_packages_token` root input for
  pulling private deployment packages from GHCR. Set it through
  `TF_VAR_homelab_packages_token`.
- `mail`: read-only `mail_password`.
- `object_storage`: read-only `object_storage_secret_access_key`.
- `password`: read-write `password` and read-only `password_hash`.
- `tailscale`: read-only `tailscale_auth_key`.

Servers also always get read-only `age_secret_key`.

## Imports

Services can reference another server or service by declaring an
`imports.servers` or `imports.services` alias. Imported dependencies are
published to target deployment contexts under that alias.

Each service import value is an explicit expanded service key, for example
`pocket_id: pocket-id-au-truenas`. Keeping aliases separate from target keys
keeps template references readable without making dependency identity depend on
target counts.
