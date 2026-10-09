import {
  id = "b653cb67-6662-4d1e-9bcb-65aa24f79c62"
  to = resend_domain.configured["excloo.dev"]
}

moved {
  from = cloudflare_dns_record.managed["excloo.dev-manual-MX-resend-10"]
  to   = cloudflare_dns_record.resend["excloo.dev/mx"]
}

moved {
  from = cloudflare_dns_record.managed["excloo.dev-manual-TXT-resend"]
  to   = cloudflare_dns_record.resend["excloo.dev/spf"]
}

moved {
  from = cloudflare_dns_record.managed["excloo.dev-manual-TXT-resend._domainkey"]
  to   = cloudflare_dns_record.resend["excloo.dev/dkim"]
}

moved {
  from = cloudflare_dns_record.resend["cname"]
  to   = cloudflare_dns_record.resend["excloo.net/cname"]
}

moved {
  from = cloudflare_dns_record.resend["dkim"]
  to   = cloudflare_dns_record.resend["excloo.net/dkim"]
}

moved {
  from = cloudflare_dns_record.resend["mx"]
  to   = cloudflare_dns_record.resend["excloo.net/mx"]
}

moved {
  from = cloudflare_dns_record.resend["spf"]
  to   = cloudflare_dns_record.resend["excloo.net/spf"]
}

moved {
  from = onepassword_item.resend_flylab
  to   = onepassword_item.resend_fly
}

moved {
  from = onepassword_item.tailscale_flylab
  to   = onepassword_item.tailscale_fly
}

moved {
  from = resend_api_key.flylab
  to   = resend_api_key.fly
}

moved {
  from = resend_domain.infrastructure
  to   = resend_domain.configured["excloo.net"]
}

moved {
  from = resend_domain_verification.infrastructure
  to   = resend_domain_verification.configured["excloo.net"]
}

moved {
  from = tailscale_oauth_client.flylab
  to   = tailscale_oauth_client.fly
}

moved {
  from = terraform_data.onepassword_resend_flylab_password_version
  to   = terraform_data.onepassword_resend_fly_password_version
}

moved {
  from = terraform_data.onepassword_tailscale_flylab_password_version
  to   = terraform_data.onepassword_tailscale_fly_password_version
}
