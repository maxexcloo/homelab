variable "controld_api_token" {
  description = "Control D API token used to manage the Tailscale profile's private DNS rules."
  sensitive   = true
  type        = string

  validation {
    condition     = length(nonsensitive(var.controld_api_token)) > 0
    error_message = "Control D API token must not be empty."
  }
}

variable "debug_dir" {
  default     = ""
  description = "Optional local directory to write plaintext rendered content for debugging. Leave empty unless actively troubleshooting encryption output."
  sensitive   = false
  type        = string

  validation {
    error_message = "Debug directory must be empty or a single-line path."

    condition = (
      var.debug_dir == "" ||
      !can(regex("[\r\n]", var.debug_dir))
    )
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
  default     = null
  description = "1Password Connect API token. Required when onepassword.enabled is true."
  nullable    = true
  sensitive   = true
  type        = string

  validation {
    condition     = var.onepassword_connect_token == null || length(nonsensitive(var.onepassword_connect_token)) > 0
    error_message = "1Password Connect API token must be null or non-empty."
  }
}

variable "onepassword_connect_url" {
  default     = null
  description = "1Password Connect API base URL. Required when onepassword.enabled is true."
  nullable    = true
  sensitive   = false
  type        = string

  validation {
    error_message = "1Password Connect URL must be null or start with http:// or https:// and not end with a slash."

    condition = (
      var.onepassword_connect_url == null ||
      (
        can(regex("^https?://[^/]+", var.onepassword_connect_url)) &&
        !endswith(var.onepassword_connect_url, "/")
      )
    )
  }
}

variable "pocketid_api_token" {
  default     = null
  description = "Pocket ID API token. Required when pocketid.enabled is true."
  nullable    = true
  sensitive   = true
  type        = string

  validation {
    condition     = var.pocketid_api_token == null || length(nonsensitive(var.pocketid_api_token)) > 0
    error_message = "Pocket ID API token must be null or non-empty."
  }
}

variable "pocketid_url" {
  default     = null
  description = "Pocket ID base URL. Required when pocketid.enabled is true."
  nullable    = true
  sensitive   = false
  type        = string

  validation {
    error_message = "Pocket ID URL must be null or start with http:// or https:// and not end with a slash."

    condition = (
      var.pocketid_url == null ||
      (
        can(regex("^https?://[^/]+", var.pocketid_url)) &&
        !endswith(var.pocketid_url, "/")
      )
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
