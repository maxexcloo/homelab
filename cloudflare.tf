data "cloudflare_accounts" "default" {}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "server" {
  for_each = cloudflare_zero_trust_tunnel_cloudflared.server

  account_id = data.cloudflare_accounts.default.result[0].id
  tunnel_id  = each.value.id
}

data "cloudflare_zone" "all" {
  for_each = var.dns

  filter = {
    name = each.key
  }
}

resource "cloudflare_account_token" "server" {
  for_each = {
    for k, v in local._servers : k => v
    if local.servers_resources[k].cloudflare
  }

  account_id = data.cloudflare_accounts.default.result[0].id
  name       = each.key

  policies = [
    {
      effect = "allow"
      permission_groups = [
        {
          id = "4755a26eedb94da69e1066d98aa820be" # Zone - DNS: Edit
        }
      ]
      resources = {
        "com.cloudflare.api.account.zone.${data.cloudflare_zone.all[var.defaults.domain_external].zone_id}" = "*",
        "com.cloudflare.api.account.zone.${data.cloudflare_zone.all[var.defaults.domain_internal].zone_id}" = "*"
      }
    }
  ]
}

resource "cloudflare_dns_record" "acme" {
  for_each = local.dns_records_acme

  comment = var.defaults.managed_comment
  content = each.value.content
  name    = each.value.name
  proxied = false
  ttl     = 1
  type    = each.value.type
  zone_id = data.cloudflare_zone.all[each.value.zone].zone_id
}

resource "cloudflare_dns_record" "manual" {
  for_each = local.dns_records_manual

  comment  = var.defaults.managed_comment
  content  = each.value.content
  name     = each.value.name
  priority = each.value.priority
  proxied  = each.value.proxied
  ttl      = each.value.ttl
  type     = each.value.type
  zone_id  = data.cloudflare_zone.all[each.value.zone].zone_id
}

resource "cloudflare_dns_record" "server" {
  for_each = local.dns_records_servers

  comment = var.defaults.managed_comment
  content = each.value.content
  name    = each.value.name
  proxied = false
  ttl     = 1
  type    = each.value.type
  zone_id = data.cloudflare_zone.all[each.value.zone].zone_id
}

resource "cloudflare_dns_record" "service" {
  for_each = local.dns_records_services

  comment = var.defaults.managed_comment
  content = each.value.content
  name    = each.value.name
  proxied = try(each.value.proxied, false)
  ttl     = 1
  type    = each.value.type
  zone_id = data.cloudflare_zone.all[each.value.zone].zone_id
}

resource "cloudflare_dns_record" "service_url" {
  for_each = local.dns_records_services_urls

  comment = var.defaults.managed_comment
  content = each.value.content
  name    = each.value.name
  proxied = try(each.value.proxied, false)
  ttl     = 1
  type    = each.value.type
  zone_id = data.cloudflare_zone.all[each.value.zone].zone_id
}

resource "cloudflare_dns_record" "wildcard" {
  for_each = local.dns_records_wildcards

  comment = var.defaults.managed_comment
  content = each.value.content
  name    = each.value.name
  proxied = false
  ttl     = 1
  type    = each.value.type
  zone_id = data.cloudflare_zone.all[each.value.zone].zone_id
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "server" {
  for_each = {
    for k, v in local._servers : k => v
    if local.servers_resources[k].cloudflared
  }

  account_id = data.cloudflare_accounts.default.result[0].id
  config_src = "cloudflare"
  name       = each.key
}
