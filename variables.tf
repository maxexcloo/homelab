variable "truenas_read_only" {
  default     = true
  description = "Refuse TrueNAS mutations. Set false only in the reviewed saved plan used for an approved apply."
  type        = bool
}

variable "truenas_url" {
  description = "TrueNAS API base URL reached through the unchanged management interface."
  type        = string

  validation {
    condition     = can(regex("^https://[^/]+$", var.truenas_url))
    error_message = "The TrueNAS URL must use HTTPS and contain no path or trailing slash."
  }
}
