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
      account_id                      = string
      dns_write_permission_group_id   = string
      tunnel_read_permission_group_id = string
      zone_ids                        = map(string)
    })

    github = object({
      docker_repository = string
      ssh_keys          = any
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
    condition = (
      !var.integrations.onepassword.enabled ||
      nonsensitive(var.integrations.onepassword.ready)
    )
    error_message = "1Password Connect URL and token are required when onepassword.enabled is true."
  }
}
