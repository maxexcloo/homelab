moved {
  from = cloudflare_account_token.acme["gateway"]
  to   = cloudflare_account_token.acme["sol"]
}

moved {
  from = cloudflare_dns_record.managed["acme/gateway"]
  to   = cloudflare_dns_record.managed["acme/sol"]
}

moved {
  from = cloudflare_dns_record.managed["machine/gateway/a"]
  to   = cloudflare_dns_record.managed["machine/sol/a"]
}

moved {
  from = cloudflare_dns_record.managed["machine/gateway/aaaa"]
  to   = cloudflare_dns_record.managed["machine/sol/aaaa"]
}

moved {
  from = onepassword_item.cloudflare_acme["gateway"]
  to   = onepassword_item.cloudflare_acme["sol"]
}

moved {
  from = onepassword_item.machine_access["gateway"]
  to   = onepassword_item.machine_access["sol"]
}

moved {
  from = onepassword_item.tailscale_auth_key["gateway"]
  to   = onepassword_item.tailscale_auth_key["sol"]
}

moved {
  from = tailscale_tailnet_key.server["gateway"]
  to   = tailscale_tailnet_key.server["sol"]
}
