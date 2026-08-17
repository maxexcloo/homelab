variable "talos_connection_endpoints" {
  default     = {}
  description = "Optional per-node Talos API endpoints, such as Tailscale addresses or local forwards."
  type        = map(string)
}

variable "oci_private_key_base64" {
  description = "OCI private key encoded as base64."
  type        = string
  sensitive   = true

  validation {
    condition = (
      can(base64decode(nonsensitive(var.oci_private_key_base64))) &&
      startswith(trimspace(base64decode(nonsensitive(var.oci_private_key_base64))), "-----BEGIN")
    )
    error_message = "The OCI private key must be a base64-encoded PEM private key."
  }
}

variable "oci_talos_image_path" {
  default     = null
  description = "Absolute path to the prepared Talos Oracle image archive."
  type        = string

  validation {
    condition     = var.oci_talos_image_path == null || startswith(var.oci_talos_image_path, "/")
    error_message = "The Talos Oracle image path must be absolute."
  }
}

variable "oci_tenancy_ocid" {
  description = "OCI tenancy OCID."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^ocid1\\.tenancy\\.", nonsensitive(var.oci_tenancy_ocid)))
    error_message = "The OCI tenancy OCID must start with ocid1.tenancy."
  }
}
