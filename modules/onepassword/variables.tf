variable "connect_url" {
  description = "1Password Connect API base URL"
  nullable    = true
  type        = string
}

variable "enabled" {
  description = "Whether to read 1Password items"
  type        = bool
}

variable "request_headers" {
  description = "1Password Connect request headers"
  sensitive   = true
  type        = map(string)
}

variable "titles" {
  description = "Stable item keys mapped to exact 1Password titles"
  type        = map(string)
}

variable "vault_id" {
  description = "1Password vault ID containing the managed items"
  type        = string
}
