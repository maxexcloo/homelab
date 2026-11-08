moved {
  from = cloudflare_dns_record.managed["machine/mandu/a"]
  to   = cloudflare_dns_record.managed["machine/mars/a"]
}

moved {
  from = cloudflare_dns_record.managed["machine/mandu/aaaa"]
  to   = cloudflare_dns_record.managed["machine/mars/aaaa"]
}

moved {
  from = cloudflare_zero_trust_tunnel_cloudflared.cluster["mandu"]
  to   = cloudflare_zero_trust_tunnel_cloudflared.cluster["mars"]
}

moved {
  from = cloudflare_zero_trust_tunnel_cloudflared_config.cluster["mandu"]
  to   = cloudflare_zero_trust_tunnel_cloudflared_config.cluster["mars"]
}

moved {
  from = onepassword_item.cloudflare_tunnel["mandu"]
  to   = onepassword_item.cloudflare_tunnel["mars"]
}

moved {
  from = onepassword_item.machine_access["mandu"]
  to   = onepassword_item.machine_access["mars"]
}

moved {
  from = onepassword_item.resend_host["mandu"]
  to   = onepassword_item.resend_host["mars"]
}

moved {
  from = onepassword_item.tailscale_auth_key["mandu"]
  to   = onepassword_item.tailscale_auth_key["mars"]
}

moved {
  from = resend_api_key.host["mandu"]
  to   = resend_api_key.host["mars"]
}

moved {
  from = tailscale_tailnet_key.server["mandu"]
  to   = tailscale_tailnet_key.server["mars"]
}
