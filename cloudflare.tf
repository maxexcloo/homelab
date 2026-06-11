data "cloudflare_account" "default" {
  filter = {
    name = local.defaults.cloudflare.account_name
  }
}

data "cloudflare_account_api_token_permission_groups_list" "dns_write" {
  account_id = data.cloudflare_account.default.id
  max_items  = 1
  name       = "DNS%20Write"
  scope      = "com.cloudflare.api.account.zone"
}

data "cloudflare_zone" "all" {
  for_each = local.dns_input

  filter = {
    name = each.key
  }
}

locals {
  # Routes are only added when backed by a managed DNS record. The
  # http_status:503 catch-all is required by Cloudflare Tunnel.
  cloudflare_tunnel_ingress = {
    for server_key, server in local.servers_by_feature.cloudflared : server_key => concat(
      flatten([
        for service_key, service in local.services_model : [
          for route in service.routing.urls : merge(
            {
              hostname = route.host
              service  = route.backend_url
            },
            startswith(route.backend_url, "https://") ? {
              origin_request = {
                no_tls_verify = true
              }
            } : {},
          )
          if(
            route.expose == "cloudflare" &&
            route.host != null
          )
        ]
        if service.target == server_key
      ]),
      [
        for route in server.routing.urls : merge(
          {
            hostname = route.url
            service  = route.backend_url
          },
          startswith(route.backend_url, "https://") ? {
            origin_request = {
              no_tls_verify = true
            }
          } : {},
        )
        if(
          route.expose == "cloudflare" &&
          try(local.dns_render_managed_zones_by_url[route.url], null) != null
        )
      ],
      [
        {
          service = "http_status:503"
        }
      ]
    )
  }
}

resource "cloudflare_account_token" "server_acme" {
  for_each = local.servers_by_feature.cloudflare_acme

  account_id = data.cloudflare_account.default.id
  name       = each.key

  policies = [
    {
      effect = "allow"
      permission_groups = [
        {
          id = one(data.cloudflare_account_api_token_permission_groups_list.dns_write.result).id
        }
      ]
      resources = jsonencode({
        "com.cloudflare.api.account.zone.${data.cloudflare_zone.all[local.defaults.domains.acme].zone_id}" = "*"
      })
    }
  ]
}

resource "cloudflare_account_token" "server_acme_legacy" {
  for_each = local.servers_by_feature.cloudflare_acme_legacy

  account_id = data.cloudflare_account.default.id
  name       = "${each.key}-zones"

  policies = [
    {
      effect = "allow"
      permission_groups = [
        {
          id = one(data.cloudflare_account_api_token_permission_groups_list.dns_write.result).id
        }
      ]
      resources = jsonencode({
        "com.cloudflare.api.account.zone.${data.cloudflare_zone.all[local.defaults.domains.external].zone_id}" = "*"
        "com.cloudflare.api.account.zone.${data.cloudflare_zone.all[local.defaults.domains.internal].zone_id}" = "*"
      })
    }
  ]
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

module "cloudflare_tunnel" {
  for_each = local.servers_by_feature.cloudflared
  source   = "./modules/cloudflare_tunnel"

  account_id = data.cloudflare_account.default.id
  ingress    = local.cloudflare_tunnel_ingress[each.key]
  name       = each.key
}
