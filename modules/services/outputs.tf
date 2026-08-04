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

output "catalog" {
  description = "Non-secret deployment catalogs"

  value = nonsensitive({
    gatus = local.services_catalog_gatus

    deployments = [
      for service_key, service in local.services_model : {
        app           = service.fly.app_name
        backend_port  = service.routing.backend_port
        cpu_kind      = service.fly.cpu_kind
        cpus          = service.fly.cpus
        force_https   = alltrue([for route in service.routing.routes : route.https])
        image         = service.fly.image
        key           = service_key
        machine_count = service.fly.machine_count
        memory_mb     = service.fly.memory_mb
        region        = service.fly.region
        service       = service.identity.service
        target        = service.target

        certificates = [
          for route in service.routing.routes : route.host
          if route.host_configured
        ]
      }
      if service.target == "fly" && service.identity.service != null
    ]
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
