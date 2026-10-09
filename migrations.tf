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
  from = cloudflare_dns_record.resend["043847.xyz/cname"]
  to   = cloudflare_dns_record.managed["resend/043847.xyz/cname"]
}

moved {
  from = cloudflare_dns_record.resend["043847.xyz/dkim"]
  to   = cloudflare_dns_record.managed["resend/043847.xyz/dkim"]
}

moved {
  from = cloudflare_dns_record.resend["043847.xyz/mx"]
  to   = cloudflare_dns_record.managed["resend/043847.xyz/mx"]
}

moved {
  from = cloudflare_dns_record.resend["043847.xyz/spf"]
  to   = cloudflare_dns_record.managed["resend/043847.xyz/spf"]
}

moved {
  from = cloudflare_dns_record.resend["bestmates.xyz/cname"]
  to   = cloudflare_dns_record.managed["resend/bestmates.xyz/cname"]
}

moved {
  from = cloudflare_dns_record.resend["bestmates.xyz/dkim"]
  to   = cloudflare_dns_record.managed["resend/bestmates.xyz/dkim"]
}

moved {
  from = cloudflare_dns_record.resend["bestmates.xyz/mx"]
  to   = cloudflare_dns_record.managed["resend/bestmates.xyz/mx"]
}

moved {
  from = cloudflare_dns_record.resend["bestmates.xyz/spf"]
  to   = cloudflare_dns_record.managed["resend/bestmates.xyz/spf"]
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
  from = cloudflare_dns_record.resend["excloo.com/cname"]
  to   = cloudflare_dns_record.managed["resend/excloo.com/cname"]
}

moved {
  from = cloudflare_dns_record.resend["excloo.com/dkim"]
  to   = cloudflare_dns_record.managed["resend/excloo.com/dkim"]
}

moved {
  from = cloudflare_dns_record.resend["excloo.com/mx"]
  to   = cloudflare_dns_record.managed["resend/excloo.com/mx"]
}

moved {
  from = cloudflare_dns_record.resend["excloo.com/spf"]
  to   = cloudflare_dns_record.managed["resend/excloo.com/spf"]
}

moved {
  from = cloudflare_dns_record.resend["excloo.dev/dkim"]
  to   = cloudflare_dns_record.managed["resend/excloo.dev/dkim"]
}

moved {
  from = cloudflare_dns_record.resend["excloo.dev/mx"]
  to   = cloudflare_dns_record.managed["resend/excloo.dev/mx"]
}

moved {
  from = cloudflare_dns_record.resend["excloo.dev/spf"]
  to   = cloudflare_dns_record.managed["resend/excloo.dev/spf"]
}

moved {
  from = cloudflare_dns_record.resend["excloo.net/cname"]
  to   = cloudflare_dns_record.managed["resend/excloo.net/cname"]
}

moved {
  from = cloudflare_dns_record.resend["excloo.net/dkim"]
  to   = cloudflare_dns_record.managed["resend/excloo.net/dkim"]
}

moved {
  from = cloudflare_dns_record.resend["excloo.net/mx"]
  to   = cloudflare_dns_record.managed["resend/excloo.net/mx"]
}

moved {
  from = cloudflare_dns_record.resend["excloo.net/spf"]
  to   = cloudflare_dns_record.managed["resend/excloo.net/spf"]
}

moved {
  from = cloudflare_dns_record.resend["excloo.org/cname"]
  to   = cloudflare_dns_record.managed["resend/excloo.org/cname"]
}

moved {
  from = cloudflare_dns_record.resend["excloo.org/dkim"]
  to   = cloudflare_dns_record.managed["resend/excloo.org/dkim"]
}

moved {
  from = cloudflare_dns_record.resend["excloo.org/mx"]
  to   = cloudflare_dns_record.managed["resend/excloo.org/mx"]
}

moved {
  from = cloudflare_dns_record.resend["excloo.org/spf"]
  to   = cloudflare_dns_record.managed["resend/excloo.org/spf"]
}

moved {
  from = cloudflare_dns_record.resend["maxexcloo.com/cname"]
  to   = cloudflare_dns_record.managed["resend/maxexcloo.com/cname"]
}

moved {
  from = cloudflare_dns_record.resend["maxexcloo.com/dkim"]
  to   = cloudflare_dns_record.managed["resend/maxexcloo.com/dkim"]
}

moved {
  from = cloudflare_dns_record.resend["maxexcloo.com/mx"]
  to   = cloudflare_dns_record.managed["resend/maxexcloo.com/mx"]
}

moved {
  from = cloudflare_dns_record.resend["maxexcloo.com/spf"]
  to   = cloudflare_dns_record.managed["resend/maxexcloo.com/spf"]
}

moved {
  from = cloudflare_dns_record.resend["mx"]
  to   = cloudflare_dns_record.resend["excloo.net/mx"]
}

moved {
  from = cloudflare_dns_record.resend["schaefer.au/cname"]
  to   = cloudflare_dns_record.managed["resend/schaefer.au/cname"]
}

moved {
  from = cloudflare_dns_record.resend["schaefer.au/dkim"]
  to   = cloudflare_dns_record.managed["resend/schaefer.au/dkim"]
}

moved {
  from = cloudflare_dns_record.resend["schaefer.au/mx"]
  to   = cloudflare_dns_record.managed["resend/schaefer.au/mx"]
}

moved {
  from = cloudflare_dns_record.resend["schaefer.au/spf"]
  to   = cloudflare_dns_record.managed["resend/schaefer.au/spf"]
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
