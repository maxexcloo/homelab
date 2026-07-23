data "cloudflare_account" "default" {
  filter = {
    name = local.defaults.cloudflare.account_name
  }
}

data "cloudflare_zone" "all" {
  for_each = local.dns_input

  filter = {
    name = each.key
  }
}

locals {
  _cloudflare_routes = {
    for route_key, route in local.dns_model_routes : route_key => route
    if route.expose == "cloudflare"
  }

  _cloudflare_routes_tunnel = {
    for route_key, route in local._cloudflare_routes : route_key => route
    if route.tunnel != null
  }

  # Routes are only added when backed by a managed DNS record. The
  # http_status:503 catch-all is required by Cloudflare Tunnel.
  _cloudflare_tunnel_ingress = {
    for server_key in keys(module.servers.model.by_feature.cloudflared) : server_key => concat(
      [
        for route in values(local._cloudflare_routes_tunnel) : merge(
          {
            hostname = route.hostname
            service  = route.tunnel.url
          },
          startswith(route.tunnel.url, "https://") ? {
            origin_request = {
              no_tls_verify = true
            }
          } : {},
        )
        if route.tunnel.server_key == server_key
      ],
      [
        {
          service = "http_status:503"
        }
      ]
    )
  }

  cloudflare_zone_ids = {
    for zone_name, zone in data.cloudflare_zone.all : zone_name => zone.zone_id
  }
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "server" {
  for_each = module.servers.model.by_feature.cloudflared

  account_id = data.cloudflare_account.default.id
  tunnel_id  = module.servers.infrastructure.cloudflare_tunnel_ids[each.key]

  config = {
    ingress = local._cloudflare_tunnel_ingress[each.key]

    warp_routing = {
      enabled = false
    }
  }
}

resource "cloudflare_dns_record" "all" {
  for_each = local.dns_render_records

  comment  = local.defaults.organization.managed_comment
  content  = each.value.content
  name     = each.value.name
  priority = each.value.priority
  proxied  = each.value.proxied
  ttl      = each.value.ttl
  type     = each.value.type
  zone_id  = data.cloudflare_zone.all[each.value.zone].zone_id
}
