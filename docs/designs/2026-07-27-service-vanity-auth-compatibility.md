# Service Vanity Authentication Compatibility

## Goal

Keep the legacy and vanity Linkwarden addresses usable while avoiding
cross-domain OAuth cookies for Dozzle:

- `linkwarden.truenas.au.excloo.dev` and `links.excloo.com` serve Linkwarden.
- `dozzle.truenas.au.excloo.dev` serves Dozzle.
- `logs.excloo.com` redirects to the legacy Dozzle address while preserving the
  path and query string.

## Current Failures

Linkwarden uses `links.excloo.com` as its canonical NextAuth URL, but the
existing `max@excloo.com` user has only an `email` account association.
NextAuth rejects the verified Pocket ID identity as `OAuthAccountNotLinked`
because no `keycloak` association exists.

Dozzle delegates authentication to OAuth2 Proxy. The proxy is intentionally
scoped to `.truenas.au.excloo.dev`, so requests through `logs.excloo.com`
produce an invalid cookie domain and a rejected post-authentication redirect.

Relative Pocket ID callback paths are expanded only against
`service.urls.default`. Adding a vanity route therefore stops registering the
legacy service URL as a callback.

## Design

### Pocket ID Callbacks

Expand every relative service callback path against every unique modeled
service URL. Keep absolute callback URLs unchanged. Sort and deduplicate the
result so provider input remains deterministic.

This preserves callbacks for both legacy derived routes and explicit vanity
routes without adding service-specific callback configuration.

### Linkwarden Account Association

Add a `keycloak` OAuth account association to the existing Linkwarden user
using the verified, enabled Pocket ID subject for `max@excloo.com`. Preserve
the existing `email` association and password.

The operation is additive. Rollback deletes only the newly added row identified
by provider `keycloak` and the exact Pocket ID subject.

### Dozzle Redirect

Allow shared routing configuration to define redirect hostnames inherited by
the derived internal route. Remove Dozzle's direct vanity backend route and
configure `logs.excloo.com` as a redirect alias of the derived legacy route.

The generated redirect remains internal-only, obtains its own certificate, and
preserves the request path and query string. OAuth2 Proxy continues operating
only within its existing cookie domain.

## Verification

- Run `mise run check`.
- Confirm the plan contains only the expected Pocket ID client, generated
  deployment artifacts, and routing metadata. Perform the Linkwarden account
  association separately after the infrastructure deployment.
- Verify both Linkwarden hosts return the application.
- Verify the Pocket ID client contains callbacks for both Linkwarden hosts.
- Verify the Linkwarden user retains `email` and gains `keycloak`.
- Verify `logs.excloo.com` redirects to the legacy Dozzle host with its path and
  query string intact.
- Verify the legacy Dozzle host initiates OAuth with a valid cookie domain and
  redirect.
- Have the user complete one Pocket ID login to Linkwarden.

## Risk Controls

- Do not broaden OAuth2 Proxy cookies to `.excloo.com`.
- Do not remove or replace Linkwarden password/email authentication.
- Back up the exact Linkwarden account association state before the additive
  database operation.
- Review the full OpenTofu plan and require explicit approval before apply.
