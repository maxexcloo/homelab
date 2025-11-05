provider "age" {}

provider "b2" {}

provider "cloudflare" {}

provider "github" {}

provider "restapi" {
  alias                 = "resend"
  create_returns_object = true
  rate_limit            = 1
  uri                   = "https://api.resend.com"

  headers = {
    "Authorization" = "Bearer ${var.resend_api_key}",
    "Content-Type"  = "application/json"
  }
}

provider "shell" {}

provider "tailscale" {}
