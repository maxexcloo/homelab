terraform {
  required_version = "~> 1.10"

  required_providers {
    shell = {
      source  = "linyinfeng/shell"
      version = "~> 1.0"
    }
  }
}

locals {
  script = file("${path.module}/encrypt.sh")
}

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

resource "shell_sensitive_script" "encrypt" {
  environment = {
    AGE_PUBLIC_KEY = var.age_public_key
    CONTENT        = sensitive(var.content_base64)
    CONTENT_TYPE   = var.content_type
    DEBUG_PATH     = var.debug_path
    FILENAME       = var.filename
    SOPS_CONFIG    = "/dev/null"
  }

  lifecycle_commands {
    create = sensitive(local.script)
    delete = "true"
    read   = sensitive(local.script)
    update = sensitive(local.script)
  }

  triggers = {
    age_public_key_hash = sha256(var.age_public_key)
    script_hash         = sha256(local.script)
  }
}

output "encrypted_content" {
  sensitive = true
  value     = shell_sensitive_script.encrypt.output["encrypted_content"]
}
