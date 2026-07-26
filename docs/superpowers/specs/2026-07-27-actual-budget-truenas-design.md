# Actual Budget TrueNAS Design

## Goal

Deploy Actual Budget through the TrueNAS community catalog using the
repository's standard service integrations. Store all application data in a
TrueNAS-managed ixVolume and expose the service over internal HTTPS.

## Service Model

Add `data/services/actual-budget.yml` with:

- an Applications dashboard entry titled Actual Budget;
- `actual-budget` as the service implementation key;
- Pocket ID OIDC and a generated fallback password stored in 1Password;
- the catalog's default web port, `31012`;
- the standard derived TrueNAS hostname; and
- an additional internal route at `budget.excloo.com`.

The OIDC client registers `https://budget.excloo.com/openid/callback`. Actual
Budget receives the Pocket ID discovery URL, client credentials, and canonical
server URL through its supported `ACTUAL_OPENID_*` environment variables.
Automatic user creation on login is enabled. Password authentication remains
available for bootstrap and recovery.

Actual Budget requires the initial owner/password setup in its web interface.
The generated 1Password credential will be used for that password so the
repository remains the source of truth for the fallback credential.

## TrueNAS Catalog Configuration

Add `templates/services/actual-budget/app.json.tftpl` for the
`actual-budget` community catalog app. The rendered values will:

- publish `network.web_port` on the modeled host port;
- create an ixVolume dataset named `data`;
- mount that volume at the catalog-defined `/data` destination; and
- use the catalog's default unprivileged user and resource settings.

No custom Compose file, host-path storage, additional storage, or container
image override is needed.

## Environment Key Normalization

The shared TrueNAS renderer currently uses the catalog name as the catalog
values key for `additional_envs`. TrueNAS catalog names use hyphens, while the
corresponding values objects use underscores. For example, the catalog
`actual-budget` reads `values.actual_budget`.

Normalize hyphens to underscores only when building the app-specific
`additional_envs` values key. Catalog lookup, app identity, artifact paths, and
container names continue to use the original hyphenated name. This also makes
environment injection correct for other hyphenated catalog apps, including
Pocket ID.

## Routing and Security

The explicit `budget.excloo.com` route uses `expose: internal`, which applies
the shared Traefik IP allowlist and obtains a managed HTTPS certificate. The
derived `actual-budget.truenas.au.excloo.dev` route remains available under the
normal internal routing model.

Pocket ID protects the application at the application layer. Actual Budget's
password login remains enabled as a recovery path. No Cloudflare Tunnel route
or public exposure is created.

## Verification

Run `mise run check` and confirm that:

- the service YAML validates against `schemas/service.json`;
- the catalog app renders valid JSON;
- `actual_budget.additional_envs` contains the OIDC settings;
- the storage values contain only the catalog-supported `data` ixVolume;
- both internal hostnames produce valid routing models; and
- existing catalog app rendering remains valid after key normalization.

Applying the OpenTofu changes is outside this task and requires separate,
explicit approval.
