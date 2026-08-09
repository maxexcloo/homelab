# Stage: config — TrueNAS deployment context.
locals {
  _services_config_truenas_services = {
    for service_key, service in local.services_model : service_key => service
    if(
      service.identity.service != null &&
      try(local.servers_model[service.target].platform, null) == "truenas"
    )
  }

  services_config_truenas = {
    repository = "truenas"
    version    = 2
    workflow   = "deploy.yaml"

    defaults = {
      organisation = {
        email = local.defaults.organisation.email
      }

      system = {
        timezone = local.defaults.system.timezone
      }
    }

    deployments = [
      for service_key in sort(keys(local._services_config_truenas_services)) : {
        name    = local.services_model[service_key].identity.name
        custom  = local.services_config_custom[service_key]
        imports = local.services_model_imports[service_key]
        key     = service_key
        service = local.services_model[service_key].identity.service
        target  = local.services_model[service_key].target
      }
    ]

    routing_labels = {
      for service_key in sort(keys(local._services_config_truenas_services)) : service_key => {
        for container, labels in local.services_config_traefik_routing_labels[service_key] :
        container => labels
      }
    }

    servers = {
      for server_key, server in local.services_config_servers : server_key => {
        age_public_key = try(age_secret_key.server[server_key].public_key, null)
        features       = server.features
        hosts          = server.hosts
        key            = server_key

        identity = server.identity

        runtime = {
          addresses   = server.runtime.addresses
          credentials = server.runtime.credentials
        }
      }
    }

    services = {
      for service_key, service in local.services_config_services : service_key => {
        data     = service.data
        identity = service.identity
        routing  = service.routing
        target   = service.target
        truenas  = service.truenas
        urls     = service.urls

        runtime = {
          attributes  = service.runtime.attributes
          credentials = service.runtime.credentials
        }
      }
      if can(local._services_config_truenas_services[service_key]) || contains(
        flatten(values(local.services_model_imports)),
        service_key,
      )
    }
  }
}
