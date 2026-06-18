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

Generated A, AAAA, and CNAME records also get ACME delegation records. Wildcard
CNAMEs are created from eligible generated server/manual records unless
`wildcard: false`.

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

- `cloudflare` and `proxy-*` routes use `web,websecure,webinternal`.
- other routes use `web,websecure`
- HTTPS non-Cloudflare, non-proxy routes replace the main router entrypoint with
  `websecure` and add a separate `-http` redirect router on `web`.

Middlewares:

- `internal` routes use `internal-only@docker`.
- HTTP redirect routers use `redirect-to-https@docker`.
- Internal HTTP redirect routers use both
  `internal-only@docker,redirect-to-https@docker`.

TLS:

- HTTPS non-Cloudflare, non-proxy routes use the `cloudflare` cert resolver.
- Managed custom hostnames also set `tls.domains[0].main`.

Route `labels` are rendered with `templatestring()` and merged last, so custom
labels can override generated labels. Null labels are dropped.

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
`defaults.cloudflare.access.identity_providers`.
