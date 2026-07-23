output "encrypted_content" {
  description = "SOPS-encrypted content"
  sensitive   = true
  value       = shell_sensitive_script.encrypt.output["encrypted_content"]
}
