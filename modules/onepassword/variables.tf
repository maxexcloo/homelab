variable "connect_url" {
  description = "1Password Connect API base URL"
  nullable    = true
  type        = string
}

variable "enabled" {
  description = "Whether to read and manage 1Password items"
  type        = bool
}

variable "payloads" {
  description = "Item payloads keyed identically to titles"
  sensitive   = true
  type        = any

  validation {
    condition     = toset(keys(var.payloads)) == toset(keys(var.titles))
    error_message = "1Password payload and title keys must match."
  }
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
