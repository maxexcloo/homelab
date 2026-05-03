locals {
  cloud_config = {
    for server_key, server in local.servers_outputs_by_feature.cloud_init : server_key => templatefile(
      "${path.module}/templates/cloud_config/cloud_config.yaml.tftpl",
      {
        defaults = local.defaults
        server   = local.servers_outputs_private[server_key]
      }
    )
  }
}

output "cloud_config" {
  description = "Generated cloud-init configurations for servers"
  sensitive   = true
  value       = local.cloud_config
}
