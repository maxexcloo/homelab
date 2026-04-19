locals {
  cloud_config = {
    for k, server in local.servers : k => templatefile(
      "${path.module}/templates/cloud_config/cloud_config.yaml.tftpl",
      {
        defaults = local.defaults
        server   = server
      }
    )
  }
}

output "cloud_config" {
  description = "Generated cloud-init configurations for servers"
  sensitive   = true
  value       = local.cloud_config
}
