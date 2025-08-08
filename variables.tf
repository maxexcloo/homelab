variable "default_email" {
  description = "Default email for notifications and accounts"
  type        = string
}

variable "default_region" {
  description = "Default region for resources"
  type        = string
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

variable "domain_acme" {
  description = "Domain to use for ACME challenge validation"
  type        = string
}

variable "domain_external" {
  description = "External domain for public services"
  type        = string
}

variable "domain_internal" {
  description = "Internal domain for private services"
  type        = string
}

variable "onepassword_vault_homelab" {
  description = "1Password homelab vault"
  type        = string
}

variable "onepassword_vault_services" {
  description = "1Password services vault"
  type        = string
}

variable "organization" {
  description = "Organization name"
  type        = string
}
