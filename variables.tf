variable "fly_repository" {
  default     = "fly"
  description = "GitHub repository name for Fly.io configuration sync"
  type        = string
}

variable "komodo_repository" {
  default     = "komodo"
  description = "GitHub repository name for Komodo configuration sync"
  type        = string
}

variable "oci_private_key_base64" {
  description = "OCI private key (base64 encoded)"
  sensitive   = true
  type        = string
}

variable "oci_tenancy_ocid" {
  description = "OCI tenancy OCID"
  sensitive   = true
  type        = string
}

variable "resend_api_key" {
  description = "Resend API key"
  sensitive   = true
  type        = string
}

variable "servers_folder" {
  default     = "Servers"
  description = "Server folder name in Bitwarden"
  type        = string
}

variable "services_folder" {
  default     = "Services"
  description = "Service folder name in Bitwarden"
  type        = string
}

variable "url_field_pattern" {
  default     = "(^fqdn_|^url_|_(ipv[46]|address)$)"
  description = "Regex pattern to identify fields that should be treated as URLs"
  type        = string
}
