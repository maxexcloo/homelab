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
  # Pre-computed tunnel ingress rules per server so the module receives a clean list.
  cloudflare_tunnel_ingress = {
    for server_key, server in local.servers_by_feature.cloudflare_zero_trust_tunnel : server_key => concat(
      flatten([
        for service_key, service in local.services_model : [
          for hostname in distinct(concat(
            service.fqdn_external != null ? [service.fqdn_external] : [],
            [for url in service.networking.urls : url if lookup(local.dns_model_zones_urls, url, null) != null]
            )) : {
            hostname = hostname
            service  = "https://localhost"

            origin_request = {
              no_tls_verify      = true
              origin_server_name = hostname
            }
          }
        ]
        if service.target == server_key && service.networking.expose == "cloudflare"
      ]),
      [
        {
          service = "http_status:503"
        }
      ]
    )
  }
}

resource "cloudflare_account_token" "server_acme" {
  for_each = local.servers_by_feature.cloudflare_acme_token

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

resource "cloudflare_dns_record" "all" {
  for_each = local.dns_model_records_all

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
  source   = "./modules/cloudflare_tunnel"
  for_each = local.servers_by_feature.cloudflare_zero_trust_tunnel

  account_id = data.cloudflare_account.default.id
  ingress    = local.cloudflare_tunnel_ingress[each.key]
  name       = each.key
}
