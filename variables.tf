variable "onepassword_connect_token" {
  description = "1Password Connect API token."
  type        = string
  sensitive   = true

  validation {
    condition     = length(nonsensitive(var.onepassword_connect_token)) > 0
    error_message = "The 1Password Connect API token must not be empty."
  }
}

variable "onepassword_connect_url" {
  description = "1Password Connect API base URL."
  type        = string

  validation {
    condition     = can(regex("^https?://[^/]+", var.onepassword_connect_url)) && !endswith(var.onepassword_connect_url, "/")
    error_message = "The 1Password Connect URL must be HTTP(S) and must not end with a slash."
  }
}

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
  description = "Absolute path to the prepared Talos Oracle image archive."
  type        = string

  validation {
    condition     = startswith(var.oci_talos_image_path, "/")
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
