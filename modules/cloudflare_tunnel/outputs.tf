output "tunnel_id" {
  description = "Cloudflare tunnel ID"
  value       = cloudflare_zero_trust_tunnel_cloudflared.tunnel.id
}

output "tunnel_read_token" {
  description = "API token scoped to reading tunnel metadata"
  sensitive   = true
  value       = cloudflare_account_token.tunnel_read.value
}

output "tunnel_token" {
  description = "Connector token used by cloudflared"
  sensitive   = true
  value       = data.cloudflare_zero_trust_tunnel_cloudflared_token.tunnel.token
}
