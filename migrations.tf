moved {
  from = cloudflare_account_token.acme["ramen"]
  to   = cloudflare_account_token.acme["gateway-mbk"]
}

moved {
  from = cloudflare_dns_record.all["acme/ramen"]
  to   = cloudflare_dns_record.all["acme/gateway-mbk"]
}

moved {
  from = cloudflare_dns_record.all["machine/ramen/a"]
  to   = cloudflare_dns_record.all["machine/gateway-mbk/a"]
}

moved {
  from = onepassword_item.cloudflare_acme["ramen"]
  to   = onepassword_item.cloudflare_acme["gateway-mbk"]
}

moved {
  from = onepassword_item.tailscale_auth_key["ramen"]
  to   = onepassword_item.tailscale_auth_key["gateway-mbk"]
}

moved {
  from = tailscale_tailnet_key.server["ramen"]
  to   = tailscale_tailnet_key.server["gateway-mbk"]
}
