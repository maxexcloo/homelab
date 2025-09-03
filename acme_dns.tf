locals {
  acme_dns_homelab = {
    for k, v in shell_script.acme_dns_homelab : k => v.output
  }
}

resource "shell_script" "acme_dns_homelab" {
  for_each = local.homelab_discovered

  lifecycle_commands {
    create = "curl -s -X POST '${var.acme_dns_server}/register'"
    delete = "echo 'ACME DNS registration is write-only; no delete action required.'"
  }
}
