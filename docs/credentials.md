# Credentials

Generated credentials are stored in 1Password through 1Password Connect.

- Servers use the vault configured at `onepassword.vaults.servers.id`.
- Services use the vault configured at `onepassword.vaults.services.id`.

Provider access comes from `TF_VAR_onepassword_connect_url` and
`TF_VAR_onepassword_connect_token`.

Server and service item titles use stable keys, such as `au-hsp` and
`pocket-id-au-truenas`. OpenTofu searches by that title and uses the matching
1Password item ID for updates, so item IDs do not need to be stored in the
repository.

## Fields

Manually supplied credential fields are declared under `credentials.fields`.
OpenTofu creates missing fields on the matching 1Password item, reads values
back, and exposes them as `runtime.credentials.<name>`.

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
- `string` and `alphanumeric` lengths are character counts.
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

- `b2` adds `b2_application_key` as read-only.
- `docker` adds read-write `doco_cd_git_access_token` and generated
  read-write `doco_cd_webhook_secret`.
- `oidc` adds generated `oidc_client_id` and `oidc_client_secret` as
  read-write.
- `password` adds a read-write password and read-only `password_hash`.
- `resend` adds read-only `resend_api_key`.
- `tailscale` adds read-only `tailscale_auth_key`.

Servers also always get read-only `age_secret_key`.

## Imports

Services can reference another service by declaring an `imports.services` alias.
Imported services are exposed to templates through the `services` map under the
declared alias.

Each import value is an explicit expanded service key, for example
`pocket_id: pocket-id-au-truenas`. Keeping aliases separate from target keys
lets templates use readable references such as `${services.pocket_id...}`
without making dependency identity depend on target counts.
