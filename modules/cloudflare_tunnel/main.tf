terraform {
  required_version = "~> 1.10"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}

variable "account_id" {
  description = "Cloudflare account ID"
  type        = string
}

variable "ingress" {
  description = "Tunnel ingress rules (list of hostname objects plus a final catch-all)"
  type = list(object({
    hostname = optional(string)
    service  = string
    origin_request = optional(object({
      no_tls_verify      = optional(bool)
      origin_server_name = optional(string)
    }))
  }))
}

variable "name" {
  description = "Server key used for resource naming"
  type        = string
}

variable "permission_group_id" {
  description = "Tunnel read permission group ID"
  type        = string
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "tunnel" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.tunnel.id
}

resource "cloudflare_account_token" "tunnel_read" {
  account_id = var.account_id
  name       = "${var.name}-tunnel-read"

  policies = [
    {
      effect = "allow"
      permission_groups = [
        {
          id = var.permission_group_id
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

  config = {
    ingress = var.ingress

    warp_routing = {
      enabled = false
    }
  }
}

output "tunnel_id" {
  value = cloudflare_zero_trust_tunnel_cloudflared.tunnel.id
}

output "tunnel_read_token" {
  sensitive = true
  value     = cloudflare_account_token.tunnel_read.value
}

output "tunnel_token" {
  sensitive = true
  value     = data.cloudflare_zero_trust_tunnel_cloudflared_token.tunnel.token
}
