output "model" {
  description = "Deterministic service input and computed model"
  value = nonsensitive({
    by_feature       = local.services_model_by_feature
    input            = local.services_input
    input_targets    = local.services_input_targets
    server_imports   = local.services_model_server_imports
    service_imports  = local.services_model_imports
    services         = local.services_model
    x509_credentials = local.services_model_x509_credentials
  })
}

output "render" {
  description = "Rendered service objects and deterministic artifact inventories"
  sensitive   = true
  value = {
    compose_inputs = local.services_render_compose_inputs
    inventory      = local.services_render_services_inventory
    services       = local.services_render_services

    truenas = {
      catalog_templates = local.truenas_catalog_templates
      servers           = local.truenas_servers
      services          = local.truenas_services
    }
  }
}

output "runtime" {
  description = "Service runtime objects keyed by service"
  sensitive   = true
  value       = local.services
}
