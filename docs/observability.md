# Observability

Grafana is the central infrastructure telemetry dashboard. VictoriaMetrics is
its Prometheus-compatible metrics store and scraper. Both services target every
server with the `observability` feature; currently that is au-truenas. Neither
is part of the ingress request path. Grafana uses the maintained TrueNAS
Community Catalog app, while VictoriaMetrics remains a custom app because it is
not available in the Catalog.

VictoriaMetrics builds its scrape jobs from services that declare
`data.shared.metrics_url`, currently the modelled Cloudflare Tunnel and Traefik
instances, Gatus, and itself. It also listens for the Graphite protocol on TCP
port 2003 so TrueNAS can publish its built-in Netdata reporting metrics without
a separate collector.

Grafana provisions VictoriaMetrics as its data source. Cloudflare Tunnel, Gatus,
and Traefik telemetry is collected through VictoriaMetrics without additional
Grafana plugins or credentials.

## TrueNAS Reporting

After VictoriaMetrics is deployed, add an enabled Graphite reporting exporter
in TrueNAS with these settings:

- Destination IP: the observability host's Tailscale IPv4 address
- Destination port: `2003`
- Namespace: the observability host key
- Prefix: `truenas`
- Send names instead of IDs: enabled
- Update interval: `10`

Start with the default chart selection, then exclude noisy charts after the
first retention cycle. Continue using Beszel for detailed host and container
metrics, Dozzle for logs, and Homepage for links to the native consoles.

## Exposure

Grafana uses its native Generic OAuth integration with Pocket ID. VictoriaMetrics
does not provide an interactive OIDC browser login, so its internal web route
continues to use the shared OIDC forward-auth middleware. Its optional `vmauth`
component can validate existing OIDC-issued JWTs, but adding that proxy would not
replace the browser login flow.

Direct metrics listeners are bound only to Tailscale addresses. The tailnet
policy permits their collection from server-tagged devices and retains the
existing router and administrator access. Appliance-, ephemeral-, and VM-tagged
devices have no rules granting access to ports 2003, 8428, 20241, and 28083.

Network policy is the common authentication boundary for these listeners.
Traefik and Cloudflare Tunnel Prometheus endpoints do not provide a common
native credential scheme, and the Graphite listener has no HTTP authentication
layer. Adding VictoriaMetrics HTTP authentication alone would therefore add a
credential without protecting the complete ingestion path. Use OIDC for the
human-facing web routes and Tailscale policy for collector traffic.
