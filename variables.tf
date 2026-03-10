variable "dns_defaults" {
  description = "Default values for DNS"
  type        = any

  default = {
    proxied  = false
    ttl      = 1
    wildcard = false
  }
}

variable "resend_api_key" {
  description = "Resend API key"
  type        = string
}

variable "server_defaults" {
  description = "Default values for servers"
  type        = any

  default = {
    description                         = null
    enable_b2                           = false
    enable_cloudflare_acme_token        = false
    enable_cloudflare_proxy             = false
    enable_cloudflare_zero_trust_tunnel = false
    enable_docker                       = false
    enable_password                     = false
    enable_resend                       = false
    enable_tailscale                    = false
    fqdn                                = null
    id                                  = null
    management_port                     = 443
    name                                = null
    parent                              = null
    platform                            = "unmanaged"
    public_address                      = null
    public_ipv4                         = null
    public_ipv6                         = null
    region                              = "au"
    type                                = "server"
    username                            = "root"
  }
}

variable "service_defaults" {
  description = "Default values for services"
  type        = any

  default = {
    deploy_to        = []
    description      = null
    enable_b2        = false
    enable_resend    = false
    enable_tailscale = false
    icon             = null
    id               = null
    name             = null
    port             = null
    secrets          = []
    service          = null
    url              = null
  }
}

variable "url_field_pattern" {
  default     = "(^fqdn_|_(ipv[46]|address)$)"
  description = "Regex pattern to identify fields that should be treated as URLs"
  type        = string
}
