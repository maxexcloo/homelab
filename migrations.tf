moved {
  from = cloudflare_dns_record.managed["machine/hotdog/a"]
  to   = cloudflare_dns_record.managed["machine/pluto/a"]
}

moved {
  from = cloudflare_dns_record.managed["machine/hotdog/aaaa"]
  to   = cloudflare_dns_record.managed["machine/pluto/aaaa"]
}

moved {
  from = cloudflare_dns_record.managed["machine/hotdog/public-a"]
  to   = cloudflare_dns_record.managed["machine/pluto/public-a"]
}

moved {
  from = cloudflare_dns_record.managed["machine/hotdog/public-aaaa"]
  to   = cloudflare_dns_record.managed["machine/pluto/public-aaaa"]
}

moved {
  from = cloudflare_zero_trust_tunnel_cloudflared.cluster["hotdog"]
  to   = cloudflare_zero_trust_tunnel_cloudflared.cluster["pluto"]
}

moved {
  from = cloudflare_zero_trust_tunnel_cloudflared_config.cluster["hotdog"]
  to   = cloudflare_zero_trust_tunnel_cloudflared_config.cluster["pluto"]
}

moved {
  from = onepassword_item.cloudflare_tunnel["hotdog"]
  to   = onepassword_item.cloudflare_tunnel["pluto"]
}

moved {
  from = onepassword_item.machine_access["hotdog"]
  to   = onepassword_item.machine_access["pluto"]
}

moved {
  from = onepassword_item.resend_host["hotdog"]
  to   = onepassword_item.resend_host["pluto"]
}

moved {
  from = onepassword_item.tailscale_auth_key["hotdog"]
  to   = onepassword_item.tailscale_auth_key["pluto"]
}

moved {
  from = resend_api_key.host["hotdog"]
  to   = resend_api_key.host["pluto"]
}

moved {
  from = tailscale_tailnet_key.server["hotdog"]
  to   = tailscale_tailnet_key.server["pluto"]
}
