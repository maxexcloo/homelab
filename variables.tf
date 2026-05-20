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
  description = "1Password Connect API token"
  sensitive   = true
  type        = string

  validation {
    condition     = length(nonsensitive(var.onepassword_connect_token)) > 0
    error_message = "1Password Connect API token must not be empty."
  }
}

variable "onepassword_connect_url" {
  description = "1Password Connect API base URL, for example https://onepassword-connect.example.com"
  sensitive   = false
  type        = string

  validation {
    error_message = "1Password Connect URL must start with http:// or https:// and must not end with a slash."

    condition = (
      can(regex("^https?://[^/]+", var.onepassword_connect_url)) &&
      !endswith(var.onepassword_connect_url, "/")
    )
  }
}

variable "pushover_user_key" {
  description = "Pushover user key for notifications"
  sensitive   = true
  type        = string

  validation {
    condition     = length(nonsensitive(var.pushover_user_key)) > 0
    error_message = "Pushover user key must not be empty."
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
