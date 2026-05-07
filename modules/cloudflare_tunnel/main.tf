data "cloudflare_account_api_token_permission_groups_list" "tunnel_read" {
  account_id = var.account_id
  max_items  = 1
  name       = "Cloudflare%20Tunnel%20Read"
  scope      = "com.cloudflare.api.account"
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "tunnel" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.tunnel.id
}

resource "cloudflare_account_token" "tunnel_read" {
  account_id = var.account_id
  name       = "${var.name}-tunnel-read"

  # The deploy target only needs to read tunnel metadata/token material for its
  # own connector; write permissions stay in the root module.
  policies = [
    {
      effect = "allow"
      permission_groups = [
        {
          id = one(data.cloudflare_account_api_token_permission_groups_list.tunnel_read.result).id
        }
      ]
      resources = jsonencode({
        "com.cloudflare.api.account.${var.account_id}" = "*"
      })
    }
  ]
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "tunnel" {
  account_id = var.account_id
  config_src = "cloudflare"
  name       = var.name
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "tunnel" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.tunnel.id

  # Ingress is assembled by the root module from service routing data so this
  # module stays focused on the Cloudflare tunnel resources.
  config = {
    ingress = var.ingress

    warp_routing = {
      enabled = false
    }
  }
}
