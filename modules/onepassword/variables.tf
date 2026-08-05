variable "field_names" {
  default     = {}
  description = "Field IDs to return for each item"
  type        = map(set(string))
}

variable "titles" {
  description = "Stable item keys mapped to exact 1Password titles"
  type        = map(string)
}

variable "vault_id" {
  description = "1Password vault ID containing the managed items"
  type        = string
}
