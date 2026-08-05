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
      packages_token    = string
    })

    oci = object({
      always_free  = bool
      tenancy_ocid = string
    })
  })

}
