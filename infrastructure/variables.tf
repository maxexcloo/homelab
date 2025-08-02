variable "default_email" {
  description = "Default email for notifications and accounts"
  type        = string
}

variable "default_region" {
  description = "Default region for resources"
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

variable "onepassword_vault_infrastructure" {
  description = "1Password Infrastructure vault"
  type        = string
}

variable "onepassword_vault_services" {
  description = "1Password Services vault"
  type        = string
}

variable "organization" {
  description = "Organization name"
  type        = string
}
