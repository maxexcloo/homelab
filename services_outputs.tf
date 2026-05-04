locals {
  # Feature maps are built from expanded input, not runtime services, to avoid
  # feature resources depending on the resources they create.
  services_outputs_by_feature = {
    for feature, default_value in local.defaults_service.features : feature => {
      for service_key, service in local.services_input_targets : service_key => service
      if service.features[feature]
    }
    if can(tobool(default_value))
  }

  # Private generated service view used where runtime fields are required.
  services_outputs_private = {
    for service_key, service in local.services_model_desired : service_key => merge(
      service,
      local.services_model_runtime[service_key]
    )
  }

  # Public service inventory without labels, used while labels are being built.
  services_outputs_public = {
    for service_key, service in local.services_model_desired : service_key => {
      for field_name, field_value in service : field_name => field_value
      if !contains(["password_hash_sensitive", "password_sensitive"], field_name)
    }
  }

  # Base template context used for rendering env, labels, and files. Declared
  # private service imports are overlaid by alias; undeclared services stay
  # public-only.
  services_template_context_base = {
    for service_key, service_config in local.services_outputs_private : service_key => {
      defaults = local.defaults
      server   = try(local.servers_outputs_private[service_config.target], null)
      servers  = local.servers_outputs_public
      service  = service_config
      services = merge(
        local.services_outputs_public,
        {
          for import_alias, service_ref in service_config.imports.services :
          import_alias => local.services_outputs_private[templatestring(service_ref, local.services_template_context_public[service_key])]
          if contains(keys(local.services_model_desired), templatestring(service_ref, local.services_template_context_public[service_key]))
        }
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
    for service_key, service in local.services_outputs_private : service_key => {
      for field_name, field_value in service : field_name => field_value
      if field_value != null && field_value != "" && field_value != false
    }
  }
}
