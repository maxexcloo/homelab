variable "onepassword_connect_token" {
  description = "1Password Connect API token."
  type        = string
  sensitive   = true
}

variable "onepassword_connect_url" {
  description = "1Password Connect API base URL."
  type        = string

  validation {
    condition     = can(regex("^https?://[^/]+", var.onepassword_connect_url)) && !endswith(var.onepassword_connect_url, "/")
    error_message = "The 1Password Connect URL must be HTTP(S) and must not end with a slash."
  }
}

provider "onepassword" {
  connect_token = var.onepassword_connect_token
  connect_url   = var.onepassword_connect_url
}

data "onepassword_vault" "talos_recovery" {
  name = local.home_cluster.recovery_vault
}
