output "bootstrap_cloud_config" {
  description = "Generated cloud-init configurations for servers"
  sensitive   = true
  value       = module.servers.bootstrap.cloud_config
}

output "bootstrap_setup_commands" {
  description = "Generated shell setup scripts for manual server provisioning"
  sensitive   = true
  value       = module.servers.bootstrap.setup_commands
}

output "bootstrap_truenas_custom_apps" {
  description = "Generated TrueNAS custom app definitions for bootstrap services"
  sensitive   = true
  value       = module.servers.bootstrap.truenas_custom_apps
}

output "servers" {
  description = "Server configurations"
  sensitive   = true

  # Top-level false/null/empty defaults are filtered out to reduce output noise.
  # Nested objects keep their full schema shape.
  value = {
    for server_key, server in module.servers.runtime : server_key => {
      for field_name, field_value in server : field_name => field_value
      if(
        field_value != null &&
        field_value != "" &&
        field_value != false
      )
    }
  }
}

output "services" {
  description = "Service configurations"
  sensitive   = true

  # Top-level false/null/empty defaults are filtered out to reduce output noise.
  # Nested objects keep their full schema shape.
  value = {
    for service_key, service in module.services.runtime : service_key => {
      for field_name, field_value in service : field_name => field_value
      if(
        field_value != null &&
        field_value != "" &&
        field_value != false
      )
    }
  }
}

output "summary" {
  description = "Summary of infrastructure managed by OpenTofu"
  sensitive   = false

  value = {
    servers  = keys(module.servers.model.servers)
    services = keys(module.services.model.services)

    counts = {
      dns_records = length(local.dns_render_records)
      servers     = length(module.servers.model.servers)
      services    = length(module.services.model.services)
    }

    servers_by_feature = {
      for feature, enabled_by_default in local.defaults.servers.features :
      (enabled_by_default ? "${feature}_disabled" : feature) => [
        for server_key, server in module.servers.model.servers : server_key
        if server.features[feature] != enabled_by_default
      ]
      if enabled_by_default || length(module.servers.model.by_feature[feature]) > 0
    }

    services_by_feature = {
      for feature, enabled_by_default in local.defaults.services.features :
      (enabled_by_default ? "${feature}_disabled" : feature) => [
        for service_key, service in module.services.model.services : service_key
        if service.features[feature] != enabled_by_default
      ]
      if enabled_by_default || length(module.services.model.by_feature[feature]) > 0
    }
  }
}
