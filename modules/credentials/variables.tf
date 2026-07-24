variable "generators" {
  description = "Credential generators keyed by stable compound identity"

  type = map(object({
    common_name           = optional(string)
    length                = optional(number)
    type                  = string
    validity_period_hours = optional(number)
  }))

  validation {
    error_message = "Generators must be alphanumeric, base64, hex, or complete x509 definitions."

    condition = alltrue([
      for generator in values(var.generators) : (
        contains(["alphanumeric", "base64", "hex"], generator.type) ? generator.length != null && generator.length > 0
        : generator.type == "x509" ? generator.common_name != null && generator.validity_period_hours != null
        : false
      )
    ])
  }
}

variable "hashes" {
  default     = []
  description = "Generated scalar credential keys requiring bcrypt hashes"
  type        = set(string)

  validation {
    error_message = "Hash keys must reference configured scalar credential generators."

    condition = alltrue([
      for credential_key in var.hashes : can(var.generators[credential_key])
    ])
  }
}

variable "organization" {
  description = "Organization written into generated X.509 subjects"
  type        = string
}

variable "password_overrides" {
  default     = {}
  description = "Existing non-empty passwords keyed by item"
  sensitive   = true
  type        = map(string)
}

variable "passwords" {
  default     = []
  description = "Stable item keys requiring bcrypt password hashes"
  type        = set(string)
}
