variable "default_email" {
  description = "Default email for notifications and accounts"
  type        = string
  default     = "max@excloo.com"
}

variable "default_region" {
  description = "Default region for resources"
  type        = string
  default     = "au"
}

variable "external_domain" {
  description = "External domain for public services"
  type        = string
  default     = "excloo.net"
}

variable "internal_domain" {
  description = "Internal domain for private services"
  type        = string
  default     = "excloo.dev"
}

variable "organization" {
  description = "Organization name"
  type        = string
  default     = "excloo"
}
