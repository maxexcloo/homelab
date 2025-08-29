data "cloudflare_zero_trust_tunnel_cloudflared_token" "homelab" {
  for_each = cloudflare_zero_trust_tunnel_cloudflared.homelab

  account_id = local.providers.cloudflare.account_id
  tunnel_id  = each.value.id
}

data "cloudflare_zone" "all" {
  for_each = var.dns

  filter = {
    name = each.key
  }
}

resource "cloudflare_account_token" "homelab" {
  for_each = {
    for k, v in local.homelab_discovered : k => v
    if local.homelab_resources[k].cloudflare
  }

  account_id = local.providers.cloudflare.account_id
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
        "com.cloudflare.api.account.zone.${data.cloudflare_zone.all[var.domain_external].zone_id}" = "*",
        "com.cloudflare.api.account.zone.${data.cloudflare_zone.all[var.domain_internal].zone_id}" = "*"
      }
    }
  ]
}

resource "cloudflare_dns_record" "all" {
  for_each = nonsensitive(local.dns_records_all)

  comment  = each.value.comment
  content  = each.value.content
  name     = each.value.name
  priority = each.value.priority
  proxied  = each.value.proxied
  ttl      = 1
  type     = each.value.type
  zone_id  = each.value.zone_id
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "homelab" {
  for_each = {
    for k, v in local.homelab_discovered : k => v
    if local.homelab_resources[k].cloudflare
  }

  account_id = local.providers.cloudflare.account_id
  config_src = "cloudflare"
  name       = each.key
}
