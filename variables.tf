variable "dns_record_defaults" {
  description = "Default values for DNS records"
  type        = any

  default = {
    proxied  = false
    ttl      = 1
    wildcard = false
  }
}

variable "server_defaults" {
  description = "Default values for server configurations"
  type        = any

  default = {
    description                  = null
    enable_b2                    = false
    enable_cloudflare_acme_token = false
    enable_cloudflared_tunnel    = false
    enable_docker                = false
    enable_proxied               = false
    enable_resend                = false
    enable_tailscale             = false
    management_port              = null
    parent                       = null
    platform                     = "unmanaged"
    public_address               = null
    public_ipv4                  = null
    public_ipv6                  = null
    region                       = "au"
    type                         = "server"
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
  description = "Regex pattern to identify fields that should be treated as URLs"
  type        = string
}
