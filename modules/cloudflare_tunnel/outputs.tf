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
