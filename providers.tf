data "onepassword_item" "providers" {
  vault = var.onepassword_homelab_vault
  title = "providers"
}

locals {
  providers = {
    for section in try(data.onepassword_item.providers.section, []) : section.label => {
      for field in section.field : field.label => field.value
    }
  }
}

provider "b2" {
  application_key    = local.providers.b2.application_key
  application_key_id = local.providers.b2.application_key_id
}

provider "cloudflare" {
  api_key = local.providers.cloudflare.api_key
  email   = local.providers.cloudflare.email
}

provider "desec" {
  api_token = local.providers.desec.api_token
}

provider "github" {
  token = local.providers.github.token
}

provider "onepassword" {}

provider "restapi" {
  alias                 = "resend"
  create_returns_object = true
  rate_limit            = 1
  uri                   = "https://api.resend.com"

  headers = {
    "Authorization" = "Bearer ${local.providers.resend.api_key}",
    "Content-Type"  = "application/json"
  }
}

provider "tailscale" {
  oauth_client_id     = local.providers.tailscale.oauth_client_id
  oauth_client_secret = local.providers.tailscale.oauth_client_secret
  tailnet             = local.providers.tailscale.tailnet
}
