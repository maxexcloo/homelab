locals {
  # Consolidated server view: model fields plus runtime state under `state`.
  servers = {
    for server_key, server in local.servers_model : server_key => merge(
      server,
      { state = local.servers_state[server_key] },
    )
  }

  # Feature maps use input data, not the consolidated view, so feature resources
  # don't depend on the resources they create.
  servers_by_feature = {
    for feature in keys(local.defaults_server.features) : feature => {
      for server_key, server in local.servers_input : server_key => server
      if server.features[feature]
    }
  }
}

output "servers" {
  description = "Server configurations"
  sensitive   = true

  # Top-level false/null/empty defaults are filtered out to reduce output noise.
  # Nested objects keep their full schema shape.
  value = {
    for server_key, server in local.servers : server_key => {
      for field_name, field_value in server : field_name => field_value
      if field_value != null && field_value != "" && field_value != false
    }
  }
}
