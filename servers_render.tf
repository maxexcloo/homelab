locals {
  servers_runtime_rendered = {
    for server_key, server in local.servers : server_key => merge(
      server,
      yamldecode(
        templatestring(
          yamlencode({
            dashboard = server.dashboard
            data      = server.data
          }),
          {
            defaults = local.defaults
            server   = server
            servers  = local.servers
          },
        ),
      ),
    )
  }
}
