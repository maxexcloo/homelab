variable "controld_api_token" {
  description = "Control D API token used to manage the Tailscale profile's private DNS rules."
  sensitive   = true
  type        = string

  validation {
    condition     = length(nonsensitive(var.controld_api_token)) > 0
    error_message = "Control D API token must not be empty."
  }
}

variable "homelab_packages_token" {
  description = "Shared read-only GitHub Packages token used by external deployment hosts."
  sensitive   = true
  type        = string

  validation {
    condition     = length(nonsensitive(var.homelab_packages_token)) > 0
    error_message = "Homelab packages token must not be empty."
  }
}

variable "oci_always_free" {
  default     = true
  description = "Enforce OCI Always Free quota limits during planning. Set to false if you have a paid tenancy."
  sensitive   = false
  type        = bool
}

variable "oci_private_key_base64" {
  description = "OCI private key (base64 encoded)"
  sensitive   = true
  type        = string

  validation {
    error_message = "OCI private key must be a base64-encoded PEM private key."

    condition = (
      can(base64decode(nonsensitive(var.oci_private_key_base64))) &&
      startswith(trimspace(base64decode(nonsensitive(var.oci_private_key_base64))), "-----BEGIN")
    )
  }
}

variable "oci_tenancy_ocid" {
  description = "OCI tenancy OCID"
  sensitive   = true
  type        = string

  validation {
    condition     = can(regex("^ocid1\\.tenancy\\.", nonsensitive(var.oci_tenancy_ocid)))
    error_message = "OCI tenancy OCID must start with ocid1.tenancy."
  }
}

variable "onepassword_connect_token" {
  description = "1Password Connect API token"
  sensitive   = true
  type        = string

  validation {
    condition     = length(nonsensitive(var.onepassword_connect_token)) > 0
    error_message = "1Password Connect API token must be non-empty."
  }
}

variable "onepassword_connect_url" {
  description = "1Password Connect API base URL"
  type        = string

  validation {
    error_message = "1Password Connect URL must start with http:// or https:// and not end with a slash."

    condition = (
      can(regex("^https?://[^/]+", var.onepassword_connect_url)) &&
      !endswith(var.onepassword_connect_url, "/")
    )
  }
}

variable "pocketid_api_token" {
  description = "Pocket ID API token"
  sensitive   = true
  type        = string

  validation {
    condition     = length(nonsensitive(var.pocketid_api_token)) > 0
    error_message = "Pocket ID API token must be non-empty."
  }
}

variable "pocketid_url" {
  description = "Pocket ID base URL"
  type        = string

  validation {
    error_message = "Pocket ID URL must start with http:// or https:// and not end with a slash."

    condition = (
      can(regex("^https?://[^/]+", var.pocketid_url)) &&
      !endswith(var.pocketid_url, "/")
    )
  }
}

variable "resend_api_key" {
  description = "Resend API key"
  sensitive   = true
  type        = string

  validation {
    condition     = startswith(nonsensitive(var.resend_api_key), "re_")
    error_message = "Resend API key must start with re_."
  }
}
