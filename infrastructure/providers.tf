data "onepassword_item" "providers" {
  vault = var.onepassword_vault_infrastructure
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
  api_token = local.providers.cloudflare.api_token
}

provider "github" {
  token = local.providers.github.token
}

provider "oci" {
  fingerprint  = local.providers.oci.fingerprint
  private_key  = local.providers.oci.private_key
  region       = local.providers.oci.region
  tenancy_ocid = local.providers.oci.tenancy_ocid
  user_ocid    = local.providers.oci.user_ocid
}

provider "onepassword" {}

# provider "proxmox" {
#   for_each = nonsensitive(var.terraform.proxmox)

#   alias    = "by_host"
#   endpoint = "https://${each.value.host}:${each.value.port}"
#   insecure = true
#   password = each.value.password
#   username = "${each.value.username}@pam"

#   ssh {
#     agent    = true
#     username = each.value.username

#     node {
#       address = each.value.host
#       name    = each.key
#     }
#   }
# }

provider "restapi" {
  alias                 = "resend"
  create_returns_object = true
  rate_limit            = 1
  uri                   = local.providers.resend.url

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
