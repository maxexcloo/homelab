locals {
  # cloud-init runs at first boot to install the cloudflared package and bring
  # the tunnel up; the long-running cloudflared service on TrueNAS hosts comes
  # from services/cloudflared instead. Same tunnel token, different lifecycle.
  cloud_config = {
    for server_key, server in local.servers_render_runtime : server_key => templatefile(
      "${path.module}/templates/cloud_config/cloud_config.yaml.tftpl",
      {
        defaults = local.defaults
        server   = server
      },
    )
    if server.features.cloud_init
  }
}

output "cloud_config" {
  description = "Generated cloud-init configurations for servers"
  sensitive   = true
  value       = local.cloud_config
}
