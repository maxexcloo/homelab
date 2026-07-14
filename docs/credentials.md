# Credentials

Generated credentials are stored in 1Password through 1Password Connect.

- Servers use the vault configured at `onepassword.vaults.servers.id`.
- Services use the vault configured at `onepassword.vaults.services.id`.

Provider access comes from `TF_VAR_onepassword_connect_url` and
`TF_VAR_onepassword_connect_token`.

## Fields

Credential fields are declared under `credentials.fields`. OpenTofu creates
missing fields on the matching 1Password item, reads values back, and exposes
them as `runtime.credentials.<name>`.

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

Fields without `bootstrap_type` are created empty for manual entry. Fields with
`bootstrap_type` and `bootstrap_length` receive an initial generated value:

- `hex` and `base64` lengths are byte counts.
- `string` and `alphanumeric` lengths are character counts.
- Generated password-style values use `special = false`.

Existing non-empty 1Password values win over generated bootstrap values. This
lets generated values seed a field once while preserving later manual changes.

## Generated Fields

Feature flags add credential fields automatically:

- `b2` adds `b2_application_key` as read-only.
- `docker` adds read-write `doco_cd_git_access_token` and bootstrapped
  read-write `doco_cd_webhook_secret`.
- `oidc` adds bootstrapped `oidc_client_id` and `oidc_client_secret` as
  read-write.
- `password` adds a read-write password and read-only `password_hash`.
- `resend` adds read-only `resend_api_key`.
- `tailscale` adds read-only `tailscale_auth_key`.

Servers also always get read-only `age_secret_key`.

## Imports

Services can reference another service by declaring an `imports.services` alias.
Imported services are exposed to templates through the `services` map under the
declared alias.

`imports.services.<alias>: auto` resolves only when the imported service has one
expanded target. Hyphenated service names also get a snake_case auto key, so an
alias like `pocket_id` can resolve the `pocket-id` service.
