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

# Proxmox providers will be configured based on 1Password entries
# Each proxmox-* section in the providers entry will create a provider instance
# Format: proxmox-servername with fields: endpoint, username, password, insecure (optional)

# Example configuration (uncomment and modify based on your proxmox-* sections):
# provider "proxmox" {
#   alias    = "server1"
#   endpoint = "https://proxmox1.example.com:8006"
#   insecure = true
#   password = "password_from_1password"
#   username = "root@pam"
#
#   ssh {
#     agent    = true
#     username = "root"
#
#     node {
#       address = "proxmox1.example.com"
#       name    = "server1"
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
