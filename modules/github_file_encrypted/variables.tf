variable "age_public_key" {
  description = "Age public key for SOPS encryption"
  sensitive   = true
  type        = string
}

variable "commit_message" {
  description = "Git commit message for the file update"
  type        = string
}

variable "content_base64" {
  description = "Base64-encoded plaintext content to encrypt and push"
  sensitive   = true
  type        = string
}

variable "content_type" {
  default     = "binary"
  description = "SOPS input/output type (binary, json, yaml, dotenv)"
  type        = string

  validation {
    condition     = contains(["binary", "dotenv", "json", "yaml"], var.content_type)
    error_message = "Content type must be binary, dotenv, json, or yaml."
  }
}

variable "debug_path" {
  default     = ""
  description = "Optional local path to write plaintext for debugging"
  type        = string
}

variable "encrypt" {
  default     = true
  description = "Whether to SOPS-encrypt content before writing it"
  type        = bool
}

variable "file" {
  description = "Repository file path"
  type        = string
}

variable "repository" {
  description = "GitHub repository name (owner is set at provider level)"
  type        = string
}
