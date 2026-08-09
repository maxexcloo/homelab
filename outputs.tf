output "bootstrap_cloud_config" {
  description = "Generated cloud-init configurations for servers"
  sensitive   = true
  value       = local.bootstrap_cloud_config
}

output "bootstrap_setup_commands" {
  description = "Generated shell setup scripts for manual server provisioning"
  sensitive   = true
  value       = local.bootstrap_setup_commands
}

output "bootstrap_truenas_custom_apps" {
  description = "Generated TrueNAS custom app definitions for bootstrap services"
  sensitive   = true
  value       = local.bootstrap_truenas_custom_apps
}

output "summary" {
  description = "Summary of infrastructure managed by OpenTofu"
  sensitive   = false

  value = {
    servers  = keys(local.servers_model)
    services = keys(local.services_model)

    counts = {
      dns_records = length(local.dns_render_records)
      servers     = length(local.servers_model)
      services    = length(local.services_model)
    }

    servers_by_feature = {
      for feature, enabled_by_default in local.defaults.servers.features :
      (enabled_by_default ? "${feature}_disabled" : feature) => [
        for server_key, server in local.servers_model : server_key
        if server.features[feature] != enabled_by_default
      ]
      if enabled_by_default || length(local.servers_model_by_feature[feature]) > 0
    }

    services_by_feature = {
      for feature, enabled_by_default in local.defaults.services.features :
      (enabled_by_default ? "${feature}_disabled" : feature) => [
        for service_key, service in local.services_model : service_key
        if service.features[feature] != enabled_by_default
      ]
      if enabled_by_default || length(local.services_model_by_feature[feature]) > 0
    }
  }
}
