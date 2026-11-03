import {
  id = "accounts/${data.cloudflare_account.default.id}/2bfa1894-5412-49cb-bf0f-705736e6a12d"
  to = cloudflare_zero_trust_access_application.app_launcher
}

moved {
  from = cloudflare_zone_setting.ssl["excloo.com"]
  to   = cloudflare_zone_setting.configured["excloo.com/ssl"]
}
