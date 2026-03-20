provider "bitwarden" {
  client_implementation = "embedded"

  experimental {
    disable_sync_after_write_verification = true
  }
}

provider "incus" {
  accept_remote_certificate    = true
  generate_client_certificates = true

  dynamic "remote" {
    for_each = local.incus_servers

    content {
      address = "https://${remote.value.networking.management_address}:${remote.value.networking.management_port}"
      name    = remote.key
    }
  }
}

provider "oci" {
  private_key  = base64decode(var.oci_private_key_base64)
  tenancy_ocid = var.oci_tenancy_ocid
}

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
