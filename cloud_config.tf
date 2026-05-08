locals {
  # cloud-init runs at first boot to install the cloudflared package and bring
  # the tunnel up; the long-running cloudflared service on TrueNAS hosts comes
  # from services/cloudflared instead. Same tunnel token, different lifecycle.
  cloud_config = {
    for server_key, server in local.servers_by_feature.cloud_init : server_key => templatefile(
      "${path.module}/templates/cloud_config/cloud_config.yaml.tftpl",
      {
        defaults = local.defaults
        server   = local.servers[server_key]
      },
    )
  }
}

output "cloud_config" {
  description = "Generated cloud-init configurations for servers"
  sensitive   = true
  value       = local.cloud_config
}
