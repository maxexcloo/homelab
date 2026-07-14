locals {
  onepassword_connect_request_headers = {
    "Authorization" = "Bearer ${var.onepassword_connect_token}"
    "Content-Type"  = "application/json"
  }
}

provider "github" {
  owner = local.defaults.github.owner
}

provider "incus" {
  accept_remote_certificate    = true
  generate_client_certificates = true

  # Incus requires provider-level remotes, so the provider is configured from
  # server data before individual incus_instance resources are declared.
  dynamic "remote" {
    for_each = local.incus_servers

    content {
      address = "https://${remote.value.networking.management_host}:${remote.value.networking.management_port}"
      name    = remote.key
    }
  }
}

provider "oci" {
  private_key  = base64decode(var.oci_private_key_base64)
  tenancy_ocid = var.oci_tenancy_ocid
}

provider "restapi" {
  alias        = "controld"
  bearer_token = var.controld_api_token
  uri          = "https://api.controld.com"
}

provider "restapi" {
  alias                 = "onepassword"
  create_returns_object = true
  headers               = local.onepassword_connect_request_headers
  uri                   = var.onepassword_connect_url
}

provider "restapi" {
  alias                 = "resend"
  bearer_token          = var.resend_api_key
  create_returns_object = true
  rate_limit            = 1
  uri                   = "https://api.resend.com"
}
