variable "default_email" {
  description = "Default email for notifications and accounts"
  type        = string
  # Set in terraform.tfvars or environment
}

variable "default_region" {
  description = "Default region for resources"
  type        = string
  # Set in terraform.tfvars or environment
}

variable "enable_backups" {
  description = "Enable automated backups"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Enable monitoring and alerting"
  type        = bool
  default     = true
}

variable "external_domain" {
  description = "External domain for public services"
  type        = string
  # Set in terraform.tfvars or environment
}

variable "internal_domain" {
  description = "Internal domain for private services"
  type        = string
  # Set in terraform.tfvars or environment
}

variable "organization" {
  description = "Organization name"
  type        = string
  # Set in terraform.tfvars or environment
}