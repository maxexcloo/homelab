variable "defaults" {
  description = "Merged global configuration and defaults"
  type        = any
}

variable "dns" {
  description = "Managed DNS zones and manual records"
  type        = any
}

variable "integrations" {
  description = "External integration inputs required by server resources"

  type = object({
    tailscale_auth_keys        = map(string)
    tailscale_device_addresses = any

    cloudflare = object({
      account_id = string
      zone_ids   = map(string)
    })

    github = object({
      docker_repository = string
    })

    onepassword = object({
      connect_url     = string
      enabled         = bool
      ready           = bool
      request_headers = map(string)
    })

    oci = object({
      always_free  = bool
      tenancy_ocid = string
    })
  })

  validation {
    error_message = "1Password Connect URL and token are required when onepassword.enabled is true."

    condition = (
      !var.integrations.onepassword.enabled ||
      nonsensitive(var.integrations.onepassword.ready)
    )
  }
}
