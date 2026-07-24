locals {
  _onepassword_integration_ready = (
    local.defaults.onepassword.enabled &&
    nonsensitive(var.onepassword_connect_token != null) &&
    var.onepassword_connect_url != null
  )

  _pocketid_integration_ready = (
    local.defaults.pocketid.enabled &&
    nonsensitive(var.pocketid_api_token != null) &&
    var.pocketid_url != null
  )

  onepassword_connect_request_headers = local._onepassword_integration_ready ? {
    "Authorization" = "Bearer ${var.onepassword_connect_token}"
    "Content-Type"  = "application/json"
  } : {}
}

provider "github" {
  owner = local.defaults.github.owner
}

provider "oci" {
  private_key  = base64decode(var.oci_private_key_base64)
  tenancy_ocid = var.oci_tenancy_ocid
}

provider "pocketid" {
  api_token = local._pocketid_integration_ready ? var.pocketid_api_token : "disabled"
  base_url  = local._pocketid_integration_ready ? var.pocketid_url : "http://127.0.0.1"
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
  uri                   = local._onepassword_integration_ready ? var.onepassword_connect_url : "http://127.0.0.1"
}

provider "restapi" {
  alias                 = "resend"
  bearer_token          = var.resend_api_key
  create_returns_object = true
  rate_limit            = 1
  uri                   = "https://api.resend.com"
}
