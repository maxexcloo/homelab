resource "shell_sensitive_script" "acme_dns_server" {
  for_each = local._servers

  lifecycle_commands {
    create = "curl -s -X POST '${var.acme_dns_server}/register'"
    delete = "true"
  }
}
