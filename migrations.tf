moved {
  from = cloudflare_account_token.crossplane
  to   = cloudflare_account_token.external_dns
}

moved {
  from = onepassword_item.cloudflare_crossplane
  to   = onepassword_item.cloudflare_external_dns
}
