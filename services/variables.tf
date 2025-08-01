variable "default_deployment" {
  description = "Default deployment target for services"
  type        = string
  # Set in terraform.tfvars
}

variable "default_email" {
  description = "Default email for service accounts"
  type        = string
  # Set in terraform.tfvars
}

variable "default_external_dns" {
  description = "Enable external DNS by default"
  type        = bool
  default     = true
}

variable "default_internal_dns" {
  description = "Enable internal DNS by default"
  type        = bool
  default     = true
}

variable "docker_network" {
  description = "Default Docker network name"
  type        = string
  default     = "proxy"
}

variable "fly_region" {
  description = "Default Fly.io region"
  type        = string
  default     = "syd"
}

variable "organization" {
  description = "Organization name"
  type        = string
  # Set in terraform.tfvars
}

variable "vercel_framework" {
  description = "Default Vercel framework"
  type        = string
  default     = "nextjs"
}