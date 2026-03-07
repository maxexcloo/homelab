variable "server_defaults" {
  description = "Default values for server configurations"
  type        = any

  default = {
    description        = null
    enable_b2          = false
    enable_cloudflare  = false
    enable_cloudflared = false
    enable_docker      = false
    enable_resend      = false
    enable_tailscale   = false
    management_port    = null
    parent             = null
    platform           = null
    public_address     = null
    public_ipv4        = null
    public_ipv6        = null
    region             = "au"
  }
}

variable "service_defaults" {
  description = "Default values for service configurations"
  type        = any

  default = {
    deploy_to                = []
    description              = null
    enable_api_key           = false
    enable_b2                = false
    enable_database_password = false
    enable_resend            = false
    enable_secret_hash       = false
    enable_tailscale         = false
    icon                     = null
    port                     = null
    service                  = null
    url                      = null
  }
}

variable "resend_api_key" {
  description = "Resend API key"
  type        = string
}

variable "url_field_pattern" {
  default     = "(^fqdn_|_(ipv[46]|address)$)"
  description = "Regex pattern to identify fields that should be treated as URLs in 1Password"
  type        = string
}
