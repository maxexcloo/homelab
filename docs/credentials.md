# Credentials

Generated credentials can be preserved and stored in 1Password through
1Password Connect. Set `onepassword.enabled` in `data/config.yml` to select the
credential source:

- `true` reads existing values from 1Password, uses generated values as
  fallbacks, and writes the complete credential inventory back to 1Password.
- `false` skips all 1Password API calls and item writes. Generated credentials
  come from OpenTofu-managed random, TLS, and provider resources and remain in
  sensitive state and encrypted deployment artifacts.

- Servers use the vault configured at `onepassword.vaults.servers.id`.
- Services use the vault configured at `onepassword.vaults.services.id`.

Provider access comes from `TF_VAR_onepassword_connect_url` and
`TF_VAR_onepassword_connect_token`. Both are required only when the integration
is enabled.

Pocket ID follows the same opt-in pattern. Set `pocketid.enabled` in
`data/config.yml`; `TF_VAR_pocketid_url` and `TF_VAR_pocketid_api_token` are
required only while it is enabled. Disabling it skips discovery, application
configuration, OIDC clients, and the Cloudflare Access identity provider.
Planning fails while Pocket ID is disabled and any service still enables
`features.oidc`.

Choose the integration mode before the first apply. Disabling an established
integration can change credentials whose current value exists only in
1Password. Managed 1Password items have `prevent_destroy`; leave the integration
enabled until those resources are deliberately detached from state if
1Password should stop being managed without deleting its items.

Server and service item titles use stable keys, such as `au-hsp` and
`pocket-id-au-truenas`. OpenTofu searches by that title and uses the matching
1Password item ID for updates, so item IDs do not need to be stored in the
repository.

## Fields

Manually supplied credential fields are declared under `credentials.fields`.
OpenTofu creates missing fields on the matching 1Password item, reads values
back, and exposes them as `runtime.credentials.<name>`.

The 1Password item is built from the complete modeled credential map. Declared
fields, typed generators, and feature-created provider values are all surfaced;
there is no service-specific allowlist.

The server and service modules shape their domain-specific item payloads, then
use `modules/onepassword` for the shared Connect search, read, and write
lifecycle. `modules/credentials` owns generated scalar values, X.509 material,
and bcrypt hashes.

Declared fields default to `credentials.rw` from `data/defaults.yml`.
Read-write fields are created in 1Password even when empty, so values can be
entered manually later. Read-only fields are written from provider-generated
runtime values.

1Password labels include the mode suffix:

- `field_rw` for editable fields
- `field_ro` for provider-owned values
- `field` for fields with `purpose: PASSWORD`

The stable field ID remains `field` in every case. Templates use
`runtime.credentials.field`, not the 1Password label.

## Typed Generators

Typed credential generators are declared under `credentials.generated`:

```yaml
credentials:
  generated:
    api_secret:
      length: 32
      type: hex
```

Scalar generators create an initial value for a read-write 1Password field:

- `hex` and `base64` lengths are byte counts.
- `alphanumeric` lengths are character counts.
- Generated password-style values use `special = false`.

Existing non-empty 1Password values win over generated seed values. This
lets generated values seed a field once while preserving later manual changes.

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
- `docker`: read-write `doco_cd_git_access_token` and generated
  `doco_cd_webhook_secret`.
- `mail`: read-only `mail_password`.
- `object_storage`: read-only `object_storage_secret_access_key`.
- `password`: read-write `password` and read-only `password_hash`.
- `tailscale`: read-only `tailscale_auth_key`.

Servers also always get read-only `age_secret_key`.

## Imports

Services can reference another server or service by declaring an
`imports.servers` or `imports.services` alias. Imported dependencies are
exposed to templates through the matching `servers` or `services` map under the
declared alias.

Each service import value is an explicit expanded service key, for example
`pocket_id: pocket-id-au-truenas`. Keeping aliases separate from target keys
lets templates use readable references such as `${services.pocket_id...}`
without making dependency identity depend on target counts.
