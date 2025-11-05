variable "acme_dns_server" {
  default     = "https://auth.acme-dns.io"
  description = "ACME DNS server URL for challenge validation"
  type        = string
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID"
  type        = string
}

variable "defaults" {
  description = "Defaults for homelab infrastructure"
  type = object({
    domain_external = string
    domain_internal = string
    email           = string
    organization    = string
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
  description = "List of all server defaults"

  type = map(object({
    type  = string
    value = any
  }))
}

variable "server_resources" {
  description = "List of all available server resources that can be enabled"
  type        = list(string)
}

variable "service_defaults" {
  description = "List of all service defaults"

  type = map(object({
    type  = string
    value = any
  }))
}

variable "service_resources" {
  description = "List of all available service resources that can be enabled"
  type        = list(string)
}

variable "resend_api_key" {
  description = "Resend API key"
  type        = string
}
