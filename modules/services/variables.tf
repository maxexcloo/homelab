variable "defaults" {
  description = "Merged global configuration and defaults"
  type        = any
}

variable "dns" {
  description = "Managed DNS zones and manual records"
  type        = any
}

variable "integrations" {
  description = "External integration inputs required by service resources"

  type = object({
    debug_dir           = string
    tailscale_auth_keys = map(string)

    cloudflare = object({
      account_id = string
      zone_ids   = map(string)
    })

    github = object({
      repositories       = map(string)
      workflow_revisions = map(string)
    })

    onepassword = object({
      connect_url     = string
      enabled         = bool
      ready           = bool
      request_headers = map(string)
    })

    pocketid = object({
      enabled = bool
      ready   = bool
      url     = string
    })
  })

  validation {
    error_message = "1Password Connect URL and token are required when onepassword.enabled is true."

    condition = (
      !var.integrations.onepassword.enabled ||
      nonsensitive(var.integrations.onepassword.ready)
    )
  }

  validation {
    error_message = "Pocket ID URL and API token are required when pocketid.enabled is true."

    condition = (
      !var.integrations.pocketid.enabled ||
      nonsensitive(var.integrations.pocketid.ready)
    )
  }
}

variable "servers" {
  description = "Server model, runtime, render, and encryption interface"

  type = object({
    age_public_keys = map(string)
    model           = any
    render          = any
    runtime         = any
  })
}
