resource "shell_sensitive_script" "acme_dns_homelab" {
  for_each = local.homelab_discovered

  lifecycle_commands {
    create = "curl -s -X POST '${var.acme_dns_server}/register'"
    delete = "true"
  }
}
