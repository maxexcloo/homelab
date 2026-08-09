provider "github" {
  owner = local.defaults.github.owner
}

provider "oci" {
  private_key  = base64decode(var.oci_private_key_base64)
  tenancy_ocid = var.oci_tenancy_ocid
}

provider "pocketid" {
  api_token = var.pocketid_api_token
  base_url  = var.pocketid_url
}

provider "restapi" {
  alias        = "controld"
  bearer_token = var.controld_api_token
  uri          = "https://api.controld.com"
}

provider "restapi" {
  alias                 = "resend"
  bearer_token          = var.resend_api_key
  create_returns_object = true
  rate_limit            = 1
  uri                   = "https://api.resend.com"
}

# Incus remotes are derived from the deterministic server model.
provider "incus" {
  accept_remote_certificate    = true
  generate_client_certificates = true

  dynamic "remote" {
    for_each = local.incus_servers

    content {
      address = "https://${remote.value.networking.management_host}:${remote.value.networking.management_port}"
      name    = remote.key
    }
  }
}
