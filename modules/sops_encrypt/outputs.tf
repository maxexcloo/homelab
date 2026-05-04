output "encrypted_content" {
  sensitive = true
  value     = shell_sensitive_script.encrypt.output["encrypted_content"]
}
