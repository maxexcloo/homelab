locals {
  # Feature maps use YAML/default data, not provider-enriched servers, to avoid
  # making feature resources depend on the resources they create.
  servers_outputs_by_feature = {
    for feature in keys(local.defaults_server.features) : feature => {
      for server_key, server in local.servers_input : server_key => server
      if server.features[feature]
    }
  }

  # Private generated server view used where runtime fields are required.
  servers_outputs_private = {
    for server_key, server in local.servers_model_desired : server_key => merge(
      server,
      local.servers_model_runtime[server_key]
    )
  }

  # Public server maps are safe for cross-service inventory templates.
  servers_outputs_public = {
    for server_key, server in local.servers_model_desired : server_key => {
      for field_name, field_value in server : field_name => field_value
      if !contains(["password_hash_sensitive", "password_sensitive"], field_name)
    }
  }

}

output "servers" {
  description = "Server configurations"
  sensitive   = true

  # Top-level false/null/empty defaults are filtered out to reduce output noise.
  # Nested objects keep their full schema shape.
  value = {
    for server_key, server in local.servers_outputs_private : server_key => {
      for field_name, field_value in server : field_name => field_value
      if field_value != null && field_value != "" && field_value != false
    }
  }
}
