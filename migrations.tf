moved {
  from = b2_application_key.host["hass"]
  to   = b2_application_key.host["luna"]
}

moved {
  from = b2_bucket.host["hass"]
  to   = b2_bucket.host["luna"]
}

moved {
  from = cloudflare_account_token.acme["hass"]
  to   = cloudflare_account_token.acme["luna"]
}

moved {
  from = cloudflare_dns_record.managed["acme/hass"]
  to   = cloudflare_dns_record.managed["acme/luna"]
}

moved {
  from = cloudflare_dns_record.managed["machine/hass/a"]
  to   = cloudflare_dns_record.managed["machine/luna/a"]
}

moved {
  from = cloudflare_dns_record.managed["machine/hass/aaaa"]
  to   = cloudflare_dns_record.managed["machine/luna/aaaa"]
}

moved {
  from = cloudflare_dns_record.managed["service-acme/hass/roborock"]
  to   = cloudflare_dns_record.managed["service-acme/luna/roborock"]
}

moved {
  from = cloudflare_dns_record.managed["service/hass/roborock"]
  to   = cloudflare_dns_record.managed["service/luna/roborock"]
}

moved {
  from = cloudflare_dns_record.managed["tunnel/hass/home-assistant.excloo.com"]
  to   = cloudflare_dns_record.managed["tunnel/luna/home-assistant.excloo.com"]
}

moved {
  from = cloudflare_zero_trust_tunnel_cloudflared.cluster["hass"]
  to   = cloudflare_zero_trust_tunnel_cloudflared.cluster["luna"]
}

moved {
  from = cloudflare_zero_trust_tunnel_cloudflared_config.cluster["hass"]
  to   = cloudflare_zero_trust_tunnel_cloudflared_config.cluster["luna"]
}

moved {
  from = controld_custom_rule.service["hass/roborock"]
  to   = controld_custom_rule.service["luna/roborock"]
}

moved {
  from = onepassword_item.backblaze_host["hass"]
  to   = onepassword_item.backblaze_host["luna"]
}

moved {
  from = onepassword_item.cloudflare_acme["hass"]
  to   = onepassword_item.cloudflare_acme["luna"]
}

moved {
  from = onepassword_item.cloudflare_tunnel["hass"]
  to   = onepassword_item.cloudflare_tunnel["luna"]
}

moved {
  from = onepassword_item.machine_access["hass"]
  to   = onepassword_item.machine_access["luna"]
}

moved {
  from = onepassword_item.resend_host["hass"]
  to   = onepassword_item.resend_host["luna"]
}

moved {
  from = onepassword_item.service_access["hass/roborock"]
  to   = onepassword_item.service_access["luna/roborock"]
}

moved {
  from = onepassword_item.tailscale_auth_key["hass"]
  to   = onepassword_item.tailscale_auth_key["luna"]
}

moved {
  from = resend_api_key.host["hass"]
  to   = resend_api_key.host["luna"]
}

moved {
  from = tailscale_tailnet_key.server["hass"]
  to   = tailscale_tailnet_key.server["luna"]
}
