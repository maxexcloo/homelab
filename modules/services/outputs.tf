output "integrations" {
  description = "Service integration values consumed by shared root policy"
  sensitive   = true
  value = {
    pocketid = {
      cloudflare_access_identity_providers = local.pocketid_cloudflare_access_identity_providers
      discovery                            = local.pocketid_discovery

      cloudflare_access_clients = {
        for client_key, client in pocketid_client.cloudflare_access : client_key => {
          id            = client.id
          client_secret = client.client_secret
        }
      }
    }
  }
}

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
    context_base   = local.services_render_context_base
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
