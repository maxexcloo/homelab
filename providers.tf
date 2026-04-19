provider "bitwarden" {
  client_implementation = "embedded"

  experimental {
    disable_sync_after_write_verification = true
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

  # Resend is modeled through the generic REST provider because no native
  # provider resource is used in this stack.
  headers = {
    "Authorization" = "Bearer ${var.resend_api_key}",
    "Content-Type"  = "application/json"
  }
}
