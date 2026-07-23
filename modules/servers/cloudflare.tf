resource "cloudflare_account_token" "server_acme" {
  for_each = local.servers_model_by_feature.cloudflare_acme

  account_id = var.integrations.cloudflare.account_id
  name       = each.key

  policies = [
    {
      effect = "allow"
      permission_groups = [
        {
          id = var.integrations.cloudflare.dns_write_permission_group_id
        }
      ]
      resources = jsonencode({
        "com.cloudflare.api.account.zone.${var.integrations.cloudflare.zone_ids[local.defaults.domains.acme]}" = "*"
      })
    }
  ]
}

resource "cloudflare_account_token" "server_acme_legacy" {
  for_each = local.servers_model_by_feature.cloudflare_acme_legacy

  account_id = var.integrations.cloudflare.account_id
  name       = "${each.key}-zones"

  policies = [
    {
      effect = "allow"
      permission_groups = [
        {
          id = var.integrations.cloudflare.dns_write_permission_group_id
        }
      ]
      resources = jsonencode({
        "com.cloudflare.api.account.zone.${var.integrations.cloudflare.zone_ids[local.defaults.domains.external]}" = "*"
        "com.cloudflare.api.account.zone.${var.integrations.cloudflare.zone_ids[local.defaults.domains.internal]}" = "*"
      })
    }
  ]
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "server" {
  for_each = local.servers_model_by_feature.cloudflared

  account_id = var.integrations.cloudflare.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.server[each.key].id
}

resource "cloudflare_account_token" "server_tunnel_read" {
  for_each = local.servers_model_by_feature.cloudflared

  account_id = var.integrations.cloudflare.account_id
  name       = "${each.key}-tunnel-read"

  policies = [
    {
      effect = "allow"
      permission_groups = [
        {
          id = var.integrations.cloudflare.tunnel_read_permission_group_id
        }
      ]
      resources = jsonencode({
        "com.cloudflare.api.account.${var.integrations.cloudflare.account_id}" = "*"
      })
    }
  ]
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "server" {
  for_each = local.servers_model_by_feature.cloudflared

  account_id = var.integrations.cloudflare.account_id
  config_src = "cloudflare"
  name       = each.key
}
