provider "oci" {
  private_key                                      = base64decode(var.oci_private_key_base64)
  realm_specific_service_endpoint_template_enabled = true
  region                                           = one(values(local.oci_networks)).region
  tenancy_ocid                                     = var.oci_tenancy_ocid
}

provider "onepassword" {}

provider "truenas" {
  destroy_protection = true
}
