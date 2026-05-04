variable "age_public_key" {
  description = "Age public key for encryption"
  sensitive   = true
  type        = string
}

variable "content_base64" {
  description = "Base64-encoded plaintext to encrypt"
  sensitive   = true
  type        = string
}

variable "content_type" {
  description = "SOPS input/output type (binary, json, yaml, dotenv)"
  type        = string
}

variable "debug_path" {
  default     = ""
  description = "Optional local path to write plaintext for debugging"
  type        = string
}

variable "filename" {
  description = "Filename override for SOPS"
  type        = string
}
