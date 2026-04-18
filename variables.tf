variable "debug_dir" {
  default     = ""
  description = "Optional local directory to write plaintext rendered content for debugging. Leave empty unless actively troubleshooting encryption output."
  sensitive   = false
  type        = string

  validation {
    condition     = var.debug_dir == "" || !can(regex("[\r\n]", var.debug_dir))
    error_message = "Debug directory must be empty or a single-line path."
  }
}

variable "oci_private_key_base64" {
  description = "OCI private key (base64 encoded)"
  sensitive   = true
  type        = string

  validation {
    condition     = can(base64decode(nonsensitive(var.oci_private_key_base64))) && startswith(trimspace(base64decode(nonsensitive(var.oci_private_key_base64))), "-----BEGIN")
    error_message = "OCI private key must be a base64-encoded PEM private key."
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

variable "pushover_application_token" {
  default     = ""
  description = "Pushover application API token"
  sensitive   = true
  type        = string

  validation {
    condition     = nonsensitive(var.pushover_application_token) == "" || can(regex("^[A-Za-z0-9]{30}$", nonsensitive(var.pushover_application_token)))
    error_message = "Pushover application API token must be empty or a 30-character alphanumeric token."
  }
}

variable "pushover_user_key" {
  default     = ""
  description = "Pushover user or group key"
  sensitive   = true
  type        = string

  validation {
    condition     = nonsensitive(var.pushover_user_key) == "" || can(regex("^[A-Za-z0-9]{30}$", nonsensitive(var.pushover_user_key)))
    error_message = "Pushover user or group key must be empty or a 30-character alphanumeric key."
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
