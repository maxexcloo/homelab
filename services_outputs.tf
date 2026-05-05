locals {
  # Consolidated service view: model fields plus runtime state. The template
  # context that overlays import aliases lives in services_render.tf.
  services = {
    for service_key, service in local.services_model : service_key => merge(
      service,
      local.services_state[service_key],
    )
  }

  # Feature maps are built from expanded input, not the consolidated services
  # view, so feature resources don't depend on the resources they create.
  services_by_feature = {
    for feature, default_value in local.defaults_service.features : feature => {
      for service_key, service in local.services_input_targets : service_key => service
      if service.features[feature]
    }
    if can(tobool(default_value))
  }
}

output "services" {
  description = "Service configurations"
  sensitive   = true

  # Top-level false/null/empty defaults are filtered out to reduce output noise.
  # Nested objects keep their full schema shape.
  value = {
    for service_key, service in local.services : service_key => {
      for field_name, field_value in service : field_name => field_value
      if field_value != null && field_value != "" && field_value != false
    }
  }
}
