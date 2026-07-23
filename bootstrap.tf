locals {
  _bootstrap_setup_commands = {
    for server_key, server in local.servers_render_servers : server_key => templatefile(
      "${path.module}/templates/bootstrap/setup.sh.tftpl",
      {
        defaults = local.defaults
        doco_cd  = try(local.doco_cd_compose[server_key], null)
        server   = server
        services = local.services_render_services_inventory
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
        services = local.services_render_services_inventory
      },
    )
    if(
      server.features.bootstrap &&
      server.platform != "truenas"
    )
  }
}
