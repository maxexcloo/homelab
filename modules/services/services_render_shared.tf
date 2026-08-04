# Stage: render — shared cross-service values.
locals {
  _services_render_provider_index = {
    for provider_key, provider in local.defaults.providers :
    "${lower(provider.title)}:${provider_key}" => provider
  }

  services_render_providers = [
    for sort_key in sort(keys(local._services_render_provider_index)) :
    local._services_render_provider_index[sort_key]
  ]
}
