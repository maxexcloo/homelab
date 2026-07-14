# Servers

Servers are declared in `data/servers/*.yml`. Defaults from
`data/defaults.yml` are deep-merged before the model is built.

## Keys And Parents

Server YAML filenames must match the derived server key:

- region root: `identity.name == identity.region`, key is the region
- child server with parent: `<parent>-<identity.name>`
- other server: `<identity.region>-<identity.name>`

Parent inheritance supports at most two parent levels. A server's ancestor list
is self, parent, then grandparent.

## Identity

`identity.description` defaults from the server title and parent context.
`identity.group` defaults to `<title> (<REGION>)`.

Server dashboard cards are generated automatically when
`networking.management_port` is set and `dashboard` is null.

## Hosts And URLs

The host prefix is:

- `identity.name` for region roots
- `identity.name.identity.region` for other servers

Computed hosts:

- `hosts.external` is `<prefix>.<domains.external>`
- `hosts.internal` is `<prefix>.<domains.internal>`
- `hosts.management` is `networking.management_host` when set
- `hosts.public` is the nearest ancestor `networking.public_host`

Computed URLs:

- `urls.internal` always exists.
- `urls.management` exists when `networking.management_port` is set.
- `urls.public` exists when a public host is inherited or set.

Public IPv4 and IPv6 addresses are inherited from the nearest ancestor with a
valid configured address.

Runtime addresses and hosts add provider-discovered values such as private IP,
Tailscale IPs, Tailscale host, and UniFi DNS.

Provider-backed GitHub public SSH keys are available at
`runtime.attributes.ssh_keys`.

## Routes

Server-owned routes use the same exposure vocabulary as service routes:
`cloudflare`, `external`, `internal`, and `proxy-<server>`.

Cloudflare server routes require `features.cloudflared`. Non-Cloudflare server
routes require a Traefik service on the routing server.
