variable "control_d_api_key" {
  description = "Control D API key supplied by the OpenTofu 1Password item."
  sensitive   = true
  type        = string
}

variable "oci_private_key_base64" {
  description = "OCI private key encoded as base64."
  sensitive   = true
  type        = string
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
  sensitive   = true
  type        = string
}

variable "onepassword_connect_token" {
  description = "1Password Connect token."
  sensitive   = true
  type        = string
}

variable "onepassword_connect_url" {
  description = "1Password Connect server URL."
  type        = string
}

variable "truenas_connections" {
  description = "TrueNAS API connections keyed by machine name, supplied by 1Password."
  sensitive   = true
  type = map(object({
    api_key = string
    url     = string
  }))
}
