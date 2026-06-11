locals {
  # cloud-init runs at first boot to install the cloudflared package and bring
  # the tunnel up; the long-running cloudflared service on TrueNAS hosts comes
  # from services/cloudflared instead. Same tunnel token, different lifecycle.
  cloud_config = {
    for server_key, server in local.servers_render_servers : server_key => templatefile(
      "${path.module}/templates/cloud_config/cloud_config.yaml.tftpl",
      {
        defaults = local.defaults
        server   = server
        services = local.services_render_services_safe
      },
    )
    if server.features.cloud_init
  }

  setup_commands = {
    for server_key, server in local.servers_render_servers : server_key => templatefile(
      "${path.module}/templates/cloud_config/setup.sh.tftpl",
      {
        defaults = local.defaults
        server   = server
        services = local.services_render_services_safe
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

output "setup_commands" {
  description = "Generated shell setup scripts for manual server provisioning"
  sensitive   = true
  value       = local.setup_commands
}
