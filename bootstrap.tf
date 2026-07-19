locals {
  _bootstrap_setup_commands = {
    for server_key, server in local.servers_render_servers : server_key => templatefile(
      "${path.module}/templates/bootstrap/setup.sh.tftpl",
      {
        defaults = local.defaults
        doco_cd  = try(local.doco_cd_compose[server_key], null)
        server   = server
        services = local.services_render_services_safe
      },
    )
    if(
      server.features.bootstrap &&
      server.platform != "truenas"
    )
  }

  _bootstrap_truenas_custom_apps = {
    for server_key, server in local.servers_render_servers : server_key => templatefile(
      "${path.module}/templates/bootstrap/truenas-cd.yaml.tftpl",
      {
        defaults = local.defaults
        server   = server
      },
    )
    if(
      server.features.bootstrap &&
      server.platform == "truenas"
    )
  }

  bootstrap_cloud_config = {
    for server_key, server in local.servers_render_servers : server_key => templatefile(
      "${path.module}/templates/bootstrap/cloud-config.yaml.tftpl",
      {
        defaults = local.defaults
        doco_cd  = try(local.doco_cd_compose[server_key], null)
        server   = server
        services = local.services_render_services_safe
      },
    )
    if(
      server.features.bootstrap &&
      server.platform != "truenas"
    )
  }
}

output "bootstrap_cloud_config" {
  description = "Generated cloud-init configurations for servers"
  sensitive   = true
  value       = local.bootstrap_cloud_config
}

output "bootstrap_setup_commands" {
  description = "Generated shell setup scripts for manual server provisioning"
  sensitive   = true
  value       = local._bootstrap_setup_commands
}

output "bootstrap_truenas_custom_apps" {
  description = "Generated TrueNAS custom app definitions for bootstrap services"
  sensitive   = true
  value       = local._bootstrap_truenas_custom_apps
}
