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

variable "talos_apply_endpoint" {
  description = "Optional Talos API connection endpoint, such as a local SSH forward."
  type        = string
  default     = null
  nullable    = true
}
