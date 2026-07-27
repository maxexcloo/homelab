# Service Vanity Authentication Compatibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep Linkwarden usable through its legacy and vanity hostnames while making the Dozzle vanity hostname redirect safely to its legacy OAuth-protected hostname.

**Architecture:** Expand relative Pocket ID callbacks across every concrete modeled route URL so legacy and vanity routes remain registered. Add shared redirect aliases to derived service routes and use that capability for Dozzle. Preserve Linkwarden's password/email account and add one exact, reversible `keycloak` association for the verified Pocket ID subject.

**Tech Stack:** OpenTofu 1.12.5, Cloudflare provider 5.22.x, Pocket ID provider 2.3.0, Traefik 3.7.9, Linkwarden 2.15.1, PostgreSQL, TrueNAS Apps

## Global Constraints

- Keep model values—not runtime values—as the source of resource identity and collection membership.
- Keep root and module HCL service-agnostic.
- Preserve both `linkwarden.truenas.au.excloo.dev` and `links.excloo.com`.
- Redirect `logs.excloo.com` to `dozzle.truenas.au.excloo.dev` while preserving path and query string.
- Do not broaden OAuth2 Proxy cookies to `.excloo.com`.
- Do not remove or replace Linkwarden password/email authentication.
- Run `mise run check` before handoff.
- Run `mise run plan` only immediately before an explicitly approved apply.
- Never run `mise run apply` without explicit user approval.

---

### Task 1: Derived Route Redirect Aliases

**Files:**
- Modify: `schemas/service.json:504`
- Modify: `data/defaults.yml:132`
- Modify: `data/services/dozzle.yml:16`

**Interfaces:**
- Consumes: `routing.redirects` as a list of hostnames inherited by the derived internal route.
- Produces: Existing `route.redirects` model entries and Traefik redirect labels without service-specific HCL.

- [ ] **Step 1: Add shared routing redirects to the JSON Schema**

Add this property immediately before `routes` in `routing.properties`:

```json
"redirects": {
  "description": "Additional hostnames that permanently redirect to the derived service route while preserving the path and query string.",
  "minItems": 1,
  "type": "array",
  "uniqueItems": true,
  "items": {
    "pattern": "^(?=.{1,253}$)([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,}$",
    "type": "string"
  }
},
```

- [ ] **Step 2: Normalize the new field in defaults**

Add the scalar-only list between `labels` and `routes`:

```yaml
    labels: {}
    redirects: []
    routes: []
```

- [ ] **Step 3: Convert Dozzle's vanity backend route to a redirect alias**

Replace the explicit `routes` block with:

```yaml
routing:
  backend_port: 30064

  redirects:
    - logs.excloo.com
```

The existing model merge passes shared routing fields into the derived route, and the existing Traefik renderer generates an internal-only permanent redirect.

- [ ] **Step 4: Format and validate the routing change**

Run:

```bash
mise run fmt
mise run check
```

Expected: schema validation, sorting, formatting, and OpenTofu validation all pass.

- [ ] **Step 5: Commit the routing change**

```bash
git add schemas/service.json data/defaults.yml data/services/dozzle.yml
git commit -m "fix: redirect Dozzle vanity hostname"
```

### Task 2: Preserve OIDC Callbacks Across Modeled Routes

**Files:**
- Modify: `modules/services/pocketid.tf:47`

**Interfaces:**
- Consumes: `local.services_model[each.key].routing.routes[*].href` and `data.oidc_callback_urls`.
- Produces: A sorted, deduplicated `callback_urls` list containing each relative callback path for every concrete service route.

- [ ] **Step 1: Expand relative callbacks over concrete route URLs**

Replace the existing `callback_urls` comprehension with:

```hcl
  callback_urls = sort(distinct(flatten([
    for callback_url in local.services_model[each.key].data.oidc_callback_urls :
    startswith(callback_url, "/") ? [
      for route in local.services_model[each.key].routing.routes :
      "${route.href}${callback_url}"
      if route.href != null
    ] : [callback_url]
  ])))
```

Absolute callback URLs remain unchanged. Using modeled routes avoids alias duplicates and does not introduce runtime-derived resource membership.

- [ ] **Step 2: Format and validate the callback change**

Run:

```bash
mise run fmt
mise run check
```

Expected: formatting and OpenTofu validation pass with deterministic callback ordering.

- [ ] **Step 3: Commit the callback change**

```bash
git add modules/services/pocketid.tf
git commit -m "fix: preserve OIDC callbacks for service aliases"
```

### Task 3: Review and Deploy the Infrastructure Changes

**Files:**
- Verify: `modules/services/pocketid.tf`
- Verify: `data/services/dozzle.yml`
- Verify: generated deployment resources in the OpenTofu plan

**Interfaces:**
- Consumes: Tasks 1 and 2.
- Produces: Updated Pocket ID client callbacks and TrueNAS Traefik routing artifacts.

- [ ] **Step 1: Run the required final repository check**

Run:

```bash
mise run check
git diff --check
git status --short
```

Expected: checks pass and only intentional committed changes or the plan document remain.

- [ ] **Step 2: Obtain explicit apply approval**

Summarize the intended plan scope to the user and request approval to run both `mise run plan` and, after review, `mise run apply`.

- [ ] **Step 3: Generate and review the plan**

After approval, run:

```bash
mise run plan
```

Expected changes:

- Pocket ID clients with relative callback paths gain legacy-route callbacks.
- Dozzle and Traefik generated deployment artifacts change.
- `logs.excloo.com` remains in DNS and ACME routing but becomes a redirect.
- No servers, application storage, credentials, or DNS records are deleted.

Stop and report any unrelated destructive action before applying.

- [ ] **Step 4: Apply the reviewed plan**

Run only with explicit approval:

```bash
mise run apply
```

Expected: OpenTofu completes without errors and publishes the updated TrueNAS deployment request.

- [ ] **Step 5: Monitor the TrueNAS deployment**

Run:

```bash
deployment_run_id=$(gh run list --repo maxexcloo/homelab-truenas --limit 1 \
  --json databaseId --jq '.[0].databaseId')
gh run watch "$deployment_run_id" \
  --repo maxexcloo/homelab-truenas --exit-status
```

Expected: the deployment workflow completes successfully.

- [ ] **Step 6: Verify Dozzle's red/green feedback loop**

Run:

```bash
curl -sS -o /dev/null -D - 'https://logs.excloo.com/path?source=vanity'
curl -sS -o /dev/null -D - 'https://dozzle.truenas.au.excloo.dev/'
```

Expected:

- The vanity response is a permanent redirect to `https://dozzle.truenas.au.excloo.dev/path?source=vanity`.
- The legacy response initiates Pocket ID authentication.
- The legacy response cookie domain is `.truenas.au.excloo.dev`.
- OAuth2 Proxy logs contain no new `logs.excloo.com` cookie-domain or whitelist rejection.

### Task 4: Add the Existing Linkwarden OIDC Association

**Files:**
- Modify live data: Linkwarden PostgreSQL `Account` table
- Verify live data: Pocket ID SQLite `users` table

**Interfaces:**
- Consumes: Pocket ID subject `2f781a4c-d2fd-4c1c-98bd-ff9269400341` for verified, enabled `max@excloo.com`.
- Produces: An additive Linkwarden `keycloak` account association while retaining the existing `email` association and password.

- [ ] **Step 1: Reconfirm both identity records before mutation**

Run read-only queries that confirm:

```text
Pocket ID: 2f781a4c-d2fd-4c1c-98bd-ff9269400341|max@excloo.com|email_verified=1|disabled=0
Linkwarden: max@excloo.com|has_password=true|providers=email
```

Stop if the email, Pocket ID subject, verification state, or current Linkwarden providers differ.

- [ ] **Step 2: Capture the pre-change Linkwarden association state**

Run a read-only query selecting only:

```sql
SELECT a.id, u.email, a.type, a.provider, a."providerAccountId"
FROM "User" u
LEFT JOIN "Account" a ON a."userId" = u.id
WHERE lower(u.email) = 'max@excloo.com'
ORDER BY a.provider, a."providerAccountId";
```

Retain the command output in the apply transcript. Do not select token columns.

- [ ] **Step 3: Insert the exact association transactionally**

Execute this statement inside the Linkwarden PostgreSQL container:

```sql
BEGIN;

INSERT INTO "Account" (
  id,
  "userId",
  type,
  provider,
  "providerAccountId"
)
SELECT
  'oidc-keycloak-2f781a4c-d2fd-4c1c-98bd-ff9269400341',
  u.id,
  'oauth',
  'keycloak',
  '2f781a4c-d2fd-4c1c-98bd-ff9269400341'
FROM "User" u
WHERE lower(u.email) = 'max@excloo.com'
  AND NOT EXISTS (
    SELECT 1
    FROM "Account" a
    WHERE a.provider = 'keycloak'
      AND a."providerAccountId" = '2f781a4c-d2fd-4c1c-98bd-ff9269400341'
  );

COMMIT;
```

Expected: one row inserted. Zero rows means the association already exists and must be inspected rather than duplicated.

- [ ] **Step 4: Verify Linkwarden's database invariant**

Run:

```sql
SELECT
  u.email,
  (u.password IS NOT NULL) AS has_password,
  string_agg(a.provider, ',' ORDER BY a.provider) AS providers
FROM "User" u
JOIN "Account" a ON a."userId" = u.id
WHERE lower(u.email) = 'max@excloo.com'
GROUP BY u.id, u.email, u.password;
```

Expected:

```text
max@excloo.com|true|email,keycloak
```

Rollback, if required:

```sql
DELETE FROM "Account"
WHERE id = 'oidc-keycloak-2f781a4c-d2fd-4c1c-98bd-ff9269400341'
  AND provider = 'keycloak'
  AND "providerAccountId" = '2f781a4c-d2fd-4c1c-98bd-ff9269400341';
```

- [ ] **Step 5: Verify both Linkwarden hosts and callback registration**

Run:

```bash
curl -sS -o /dev/null -w 'legacy code=%{http_code} verify=%{ssl_verify_result}\n' \
  'https://linkwarden.truenas.au.excloo.dev/'
curl -sS -o /dev/null -w 'vanity code=%{http_code} verify=%{ssl_verify_result}\n' \
  'https://links.excloo.com/'
```

Expected: both hosts serve Linkwarden with `verify=0`.

Confirm Pocket ID contains both:

```text
https://linkwarden.truenas.au.excloo.dev/api/v1/auth/callback/keycloak
https://links.excloo.com/api/v1/auth/callback/keycloak
```

- [ ] **Step 6: Complete the human-in-the-loop OAuth verification**

Ask the user to open a private browser window, visit `https://links.excloo.com`,
and sign in with Pocket ID.

Expected:

- Authentication completes without `OAuthAccountNotLinked`.
- The existing Linkwarden links and collections are present.
- Password/email login remains available.

### Task 5: Final Verification and Handoff

**Files:**
- Verify: repository worktree
- Verify: live Linkwarden, Dozzle, OAuth2 Proxy, Pocket ID, and Traefik state

**Interfaces:**
- Consumes: Tasks 1 through 4.
- Produces: Evidence-backed completion report and documented rollback commands.

- [ ] **Step 1: Run fresh completion checks**

Run:

```bash
mise run check
git diff --check
git status --short
```

Expected: repository checks pass and the implementation worktree is clean.

- [ ] **Step 2: Re-run the original live failure probes**

Run the Dozzle redirect probe from Task 3 and query the Linkwarden provider list from Task 4.

Expected:

- Dozzle no longer emits an invalid `.truenas.au.excloo.dev` cookie from `logs.excloo.com`; it redirects before authentication.
- Linkwarden reports both `email` and `keycloak` providers for the existing user.
- The user confirms Pocket ID login succeeds without `OAuthAccountNotLinked`.

- [ ] **Step 3: Report outcome and rollback**

Report:

- Repository commits created.
- OpenTofu apply summary and deployment workflow result.
- Both legacy and vanity URL behavior.
- Linkwarden account association result.
- Exact rollback command for the additive `keycloak` row.
