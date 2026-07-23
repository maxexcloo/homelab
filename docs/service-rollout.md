# Service Rollout

This runbook covers the manual and stateful parts of the authentication,
storage, and alerting rollout. Apply only a reviewed OpenTofu plan. Stop if the
plan replaces a 1Password item, destroys a B2 bucket, or changes unrelated
services.

## Before planning

Populate these read-write fields in the existing 1Password service items:

- `gatus-fly`: `homeassistant_token`
- `papra-au-truenas`: `openrouter_api_key`

The first migration plan renames 1Password items in place from their current
stable-ID titles to `Title (stable-id)`. It must retain the existing item IDs
and resource addresses. The configuration deliberately fails when both titles
exist, either search returns multiple items, or the combined lookup is
ambiguous. Remove the legacy-title searches immediately after every item has
been confirmed under its formatted title. The two OAuth2 Proxy `previous`
title searches are part of the same one-apply migration and must be removed at
the same time.

## Immich

Before restarting Immich, inspect the rendered TrueNAS `app.json` and the
running server and microservices environments. The rendered
`values.immich.additional_envs` must contain only the repository-owned
`IMMICH_LOG_FORMAT=json` entry. It must not contain `IMMICH_CONFIG_FILE`.

After deployment, confirm both workers start without an attempt to read
`/server/config/immich.yml`.

## Linkwarden

Do not upgrade Linkwarden or remove password login during this procedure.

1. Take and verify a PostgreSQL backup.
2. Confirm Pocket ID's issuer is its base URL without a trailing slash, signing
   uses RS256, and the callback is exactly
   `/api/v1/auth/callback/keycloak` on the Linkwarden URL.
3. Confirm Pocket ID returns the existing Linkwarden user's email exactly.
4. Inspect the affected Prisma `User` and `Account` rows. Mark the existing
   email verified if required, without recreating the user.
5. In the currently installed Linkwarden application, temporarily set
   `allowDangerousEmailAccountLinking: true` only on the Keycloak provider.
6. Sign in once through `Excloo ID`, then verify that a Keycloak-provider
   `Account` row points to the original user.
7. Immediately restore the stock application and restart it.
8. Test Pocket ID and password recovery logins. Confirm collections and saved
   links are unchanged.

## Application setup

- Papra: enable AI and auto-tagging for the organization in the UI. Leave
  outgoing webhooks disabled.
- Beszel: configure Pocket ID and SMTP through the PocketBase admin UI. Enter
  the generated B2 S3 endpoint, bucket, access key, and secret in its backup
  settings. Run a backup, restore it to a test instance, then configure host
  down, sustained CPU/memory, disk, SMART, and temperature alerts. Keep password
  recovery enabled until OIDC succeeds.
- Grimmory: select the existing public PKCE Pocket ID client, label it
  `Excloo ID`, and enable provisioning/linking while retaining local recovery.
  Configure BookDrop, OPDS, Kobo/KOReader sync, metadata sources, magic shelves,
  and email-to-Kindle where applicable.
- Bichon: confirm the default administrator credentials were replaced and
  schedule IMAP synchronization in the UI.

## OAuth2 Proxy and Dozzle

OAuth2 Proxy is deployed once per reverse-proxy server at that server's
`oauth2-proxy` hostname and uses stable keys such as `oauth2-proxy-au-hsp`. Each
target has a separate confidential Pocket ID client, PKCE S256
callback, and cookie secret. The generated configuration validates itself
before startup and probes `/ready` for container health.

Dozzle requires the internal-IP allowlist and Pocket ID. Test the following
from allowed and denied networks:

- unauthenticated login and return to the original URL;
- authenticated access and identity headers;
- `/oauth2/sign_out` followed by denied access;
- a denied Pocket ID user;
- OAuth2 Proxy `/ping`, `/ready`, and configuration validation.

In Dozzle's persistent UI configuration, enable notifications for OOM events,
unhealthy containers, and unexpected exits. Exclude exit codes `0`, `130`,
`137`, and `143`. Do not add broad error-log matching. Confirm shell, container
actions, and MCP still work after the auth cutover.

## Gatus and Home Assistant

Create a dedicated, non-administrator Home Assistant service user named
`gatus`. Create a long-lived access token for that user and store it in the
`Gatus (gatus-fly)` item. Do not use a personal user's token. Add an automation
for the `gatus_alert` event that sends its triggered and resolved payloads
through the existing notification action.

The deployed Gatus version supports the Home Assistant provider but has no
native endpoint dependency graph. The `1.1.1.1:53` connectivity check therefore
reports the upstream failure separately; it cannot suppress unrelated endpoint
alerts by itself. Do not claim storm suppression until Gatus adds that feature
or an alert-routing layer is introduced.

From the Fly-hosted ephemeral Tailscale node, verify ICMP to every displayed
Tailscale IPv4 address and confirm failure and recovery delivery through both
email and Home Assistant. HTTP service checks remain separate. Also confirm the
OAuth2 Proxy endpoint is monitored and protected Dozzle returns its expected
unauthorized response.

## Acceptance

Run `mise run check` and save a separate OpenTofu plan for review. After an
approved apply, acceptance requires successful Pocket ID and recovery logins,
a Beszel B2 restore, Dozzle authorization and notification tests, Gatus
email/Home Assistant failure and recovery delivery, direct Tailscale-IP probes,
working Traefik Homepage widgets, and clean Immich worker startup.
