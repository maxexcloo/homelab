# Stage: render — expands template strings in server dashboard and data fields.
locals {
  # Server view with dashboard and data fields rendered via templatestring(). Kept
  # separate from services_outputs.tf so service templates receive a consistent,
  # fully-rendered server object rather than the mid-pipeline runtime value.
  servers_render_servers = {
    for server_key, server in local.servers : server_key => merge(
      server,
      jsondecode(
        templatestring(
          replace(
            jsonencode({
              dashboard = server.dashboard
              data      = server.data
            }),
            local.render_json_template_expression_pattern,
            local.render_json_template_expression_replacement,
          ),
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
