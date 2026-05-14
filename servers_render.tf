locals {
  _servers_runtime_rendered_context = {
    for server_key, server in local.servers : server_key => {
      defaults = local.defaults
      server   = server
      servers  = local.servers
    }
  }

  servers_runtime_rendered = {
    for server_key, server in local.servers : server_key => merge(
      server,
      yamldecode(
        templatestring(
          yamlencode({
            dashboard = server.dashboard
            data      = server.data
          }),
          local._servers_runtime_rendered_context[server_key],
        ),
      ),
    )
  }
}
