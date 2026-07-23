# Routing

Routes are declared under `routing.urls` and inherit shared fields from
`routing`. Services with `routing.backend_port` or `routing.backend_scheme` also
receive an implicit internal route with no custom hostname.

Use `service.urls.*.{host,href}` for service endpoints and `server.hosts.*` for
server hostnames.

## Route Defaults

Computed route behaviour:

- `id` defaults to the route index.
- `name` is `identity.name` for route `0`, otherwise `identity.name-id`.
- `container` defaults to `identity.service`.
- `host_port` defaults to `backend_port`.
- `href` uses `https` unless the route overrides it.
- `proxy_server` is set when `expose` is `proxy-<server>`.
- `zone` is the managed DNS zone for custom URLs, `fly.dev` for Fly hostnames,
  the internal domain for internal routes, and the external domain otherwise.

## URL Aliases

Aliases are derived from route order:

- `urls.default` is the first route with an href.
- `urls.external` is the first custom URL or explicit external route.
- `urls.internal` is the first derived internal route.
- Custom hostnames also appear by hostname key in `service.urls`.

## DNS

Custom service URLs create DNS records only when the hostname is in a managed
DNS zone. Cloudflare-exposed records point at the target server's tunnel.
Proxy routes point at the proxy server. Other server-backed routes point at the
route target host.

`dns_model_routes` normalizes server routes, service routes, and redirects into
one provider-neutral hostname map. Public Cloudflare records, Cloudflare Tunnel
ingress, and private Control D overrides consume that map.

Generated A, AAAA, and CNAME records also get ACME delegation records. Wildcard
CNAMEs are created from eligible generated server/manual records unless
`wildcard: false`.

### Tailscale DNS

The tailnet already uses the dedicated Control D profile configured by
`controld.profile_id` in `data/config.yml`. OpenTofu creates a Control D spoof
rule for every modeled server, service, and redirect hostname served by a
Tailscale-enabled server. Each rule returns that server's Tailscale IPv4 and
IPv6 addresses.

Set `TF_VAR_controld_api_token` in `.mise.local.toml`. The token is sensitive;
the profile ID is not. Existing unrelated custom rules in the profile are left
untouched.

This is split-horizon DNS without a Tailscale provider resource: clients using
the tailnet's Control D resolver receive Tailscale addresses, while all other
clients continue to receive the public Cloudflare records.

## Traefik Labels

Labels are generated per route and injected into the route's `container` in the
rendered Compose file. A route with no `backend_port` does not get generated
Traefik service labels.

Generated labels include:

- `traefik.enable=true`
- router entrypoints
- router rule from `route.host`
- router service name
- load balancer port from `backend_port`
- load balancer scheme when `backend_scheme` is `https`

Entrypoints:

- `proxy-*` routes use `webinternal` on the source server.
- HTTPS non-proxy routes use `websecure` and add a separate `-http` redirect
  router on `web`.
- HTTP non-proxy routes use `web`.
- Cloudflare Tunnel connects to service routes through
  `https://localhost:443`, so public and Tailscale requests use the same HTTPS
  router.

Middlewares:

- `internal` routes use `internal-only@docker`.
- HTTP redirect routers use `redirect-to-https@docker`.
- Internal HTTP redirect routers use both
  `internal-only@docker,redirect-to-https@docker`.

TLS:

- HTTPS non-proxy routes use the `cloudflare` cert resolver.
- Managed custom hostnames also set `tls.domains[0].main`.

Route `labels` are rendered with `templatestring()` and merged last, so custom
labels can override generated labels. Null labels are dropped.

## Redirects

Add redirect aliases to a route as hostname strings:

```yaml
routing:
  urls:
    - expose: cloudflare
      url: reddit.excloo.com
      redirects:
        - www.reddit.excloo.com
```

Aliases inherit the canonical route's target and exposure path. They receive a
public DNS record, ACME delegation, Traefik HTTPS redirect router, HTTP redirect
router, and Control D override. The redirect is permanent and preserves the
request suffix while replacing the hostname with the canonical route URL.

## Containers

The route `container` selects which Compose service receives generated labels.
If unset, it defaults to `identity.service`.

For services with multiple exposed containers, set `container` per route. The
Compose template must contain a matching service name or the labels have no
container to attach to.

## Proxy Routes

`proxy-<server>` routes are published through Traefik on another server. The
proxy Traefik service receives `custom.proxy_routes` in its template context.
Service proxy routes forward to the source target's Tailscale IPv4 address on
port `8000`, the `webinternal` Traefik entrypoint.

Server routes can also use `external`, `internal`, `cloudflare`, or
`proxy-<server>`. Non-Cloudflare server routes require a Traefik service on the
routing server.

## Cloudflare Rules

Route-level `cloudflare_access`, `cloudflare_rate_limiting_rules`, and
`cloudflare_waf_rules` are grouped by DNS zone in `cloudflare.tf`.
Cloudflare Access IDP aliases come from
`cloudflare.access.identity_providers` in `data/config.yml`. The `provider`
selects the integration, `client_name` names the client in the identity
provider, and `display_name` names the provider in Cloudflare Access.

Access application identity uses the expanded service key, routed hostname, and
protected path. Reordering routes or changing a display name does not replace
the application.
