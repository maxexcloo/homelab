locals {
  _bootstrap_setup_commands = {
    for server_key, server in local.servers_render_servers : server_key => templatefile(
      "${path.root}/templates/bootstrap/setup.sh.tftpl",
      {
        defaults = local.defaults
        doco_cd  = try(local.doco_cd_compose[server_key], null)
        server   = server
        beszel   = local.defaults.beszel
      },
    )
    if(
      server.features.bootstrap &&
      server.platform != "truenas"
    )
  }

  _bootstrap_truenas_custom_apps = {
    for server_key, server in local.servers_render_servers : server_key => templatefile(
      "${path.root}/templates/bootstrap/truenas-cd.yaml.tftpl",
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
      "${path.root}/templates/bootstrap/cloud-config.yaml.tftpl",
      {
        defaults = local.defaults
        doco_cd  = try(local.doco_cd_compose[server_key], null)
        server   = server
        beszel   = local.defaults.beszel
      },
    )
    if(
      server.features.bootstrap &&
      server.platform != "truenas"
    )
  }

  doco_cd_compose = {
    for server_key, server in local.servers_render_servers : server_key => templatefile(
      "${path.root}/templates/doco_cd/docker-compose.yaml.tftpl",
      {
        defaults = local.defaults
        server   = server
      },
    )
    if server.features.docker
  }
}
