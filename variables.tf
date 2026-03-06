variable "defaults" {
  description = "Defaults for homelab infrastructure"
  type = object({
    domain_acme = string
    domain_external = string
    domain_internal = string
    email           = string
    locale          = string
    managed_comment = string
    organization    = string
    shell           = string
    timezone        = string
  })
}

variable "dns" {
  default     = {}
  description = "DNS records by zone"

  type = map(list(object({
    content  = string
    name     = string
    priority = optional(number)
    proxied  = optional(bool, false)
    ttl      = optional(number, 1)
    type     = string
    wildcard = optional(bool, false)
  })))
}

variable "server_defaults" {
  description = "Default values for server configurations"
  type        = any

  default = {
    description     = null
    management_port = null
    parent          = null
    public_address  = null
    public_ipv4     = null
    public_ipv6     = null
    resources       = null
  }
}

variable "server_resources" {
  description = "List of all available server resources that can be enabled"
  type        = list(string)
}

variable "service_defaults" {
  description = "Default values for service configurations"
  type        = any

  default = {
    api_key           = null
    database_password = null
    deploy_to         = null
    description       = null
    icon              = null
    port              = null
    resources         = null
    secret_hash       = null
    service           = null
  }
}

variable "service_resources" {
  description = "List of all available service resources that can be enabled"
  type        = list(string)
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
