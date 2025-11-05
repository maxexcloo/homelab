moved {
  from = b2_application_key.homelab
  to   = b2_application_key.server
}
moved {
  from = b2_bucket.homelab
  to   = b2_bucket.server
}
moved {
  from = random_string.b2_homelab
  to   = random_string.b2_server
}

# Cloudflare Account Tokens
moved {
  from = cloudflare_account_token.homelab
  to   = cloudflare_account_token.server
}

# Cloudflare DNS Records
moved {
  from = cloudflare_dns_record.homelab
  to   = cloudflare_dns_record.server
}
moved {
  from = cloudflare_dns_record.services
  to   = cloudflare_dns_record.service
}
moved {
  from = cloudflare_dns_record.wildcards
  to   = cloudflare_dns_record.wildcard
}

# Cloudflare Tunnels
moved {
  from = cloudflare_zero_trust_tunnel_cloudflared.homelab
  to   = cloudflare_zero_trust_tunnel_cloudflared.server
}

# Resend API Keys
moved {
  from = restapi_object.resend_api_key_homelab
  to   = restapi_object.resend_api_key_server
}

# ACME DNS Shell Script
moved {
  from = shell_sensitive_script.acme_dns_homelab
  to   = shell_sensitive_script.acme_dns_server
}