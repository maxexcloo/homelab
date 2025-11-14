variable "acme_dns_server" {
  default     = "https://auth.acme-dns.io"
  description = "ACME DNS server URL for challenge validation"
  type        = string
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID"
  type        = string

  validation {
    condition     = can(regex("^[a-f0-9]{32}$", var.cloudflare_account_id))
    error_message = "Cloudflare account ID must be a 32-character hex string."
  }
}

variable "defaults" {
  description = "Defaults for homelab infrastructure"
  type = object({
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

variable "komodo_repository" {
  default     = "komodo"
  description = "GitHub repository for Komodo configuration deployment"
  type        = string
}

variable "onepassword_servers_vault" {
  default     = "servers"
  description = "1Password servers vault"
  type        = string
}

variable "onepassword_services_vault" {
  default     = "services"
  description = "1Password services vault"
  type        = string
}

variable "server_defaults" {
  description = "Default values for server configurations"
  type        = any

  default = {
    description     = null
    management_port = null
    parent          = null
    private_ipv4    = null
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

variable "url_fields" {
  description = "URL fields to filter"
  type        = list(string)

  default = [
    "fqdn_external",
    "fqdn_internal",
    "private_ipv4",
    "public_address",
    "public_ipv4",
    "public_ipv6",
    "tailscale_ipv4",
    "tailscale_ipv6"
  ]
}
