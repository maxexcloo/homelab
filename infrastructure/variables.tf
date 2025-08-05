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

variable "domain_external" {
  description = "External domain for public services"
  type        = string
}

variable "domain_internal" {
  description = "Internal domain for private services"
  type        = string
}

variable "onepassword_vault" {
  description = "1Password vault"
  type        = string
}

variable "organization" {
  description = "Organization name"
  type        = string
}

variable "proxmox_servers" {
  default     = {}
  description = "Proxmox server configurations (extracted from 1Password)"

  type = map(object({
    endpoint = string
    insecure = optional(string, "true")
    password = string
    username = string
  }))
}
