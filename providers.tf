provider "oci" {
  private_key                                      = base64decode(var.oci_private_key_base64)
  realm_specific_service_endpoint_template_enabled = true
  region                                           = one(local.oci_network_regions)
  tenancy_ocid                                     = var.oci_tenancy_ocid
}

provider "truenas" {
  for_each = local.truenas_hosts

  alias              = "hosts"
  destroy_protection = true
}
