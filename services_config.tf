# Stage: config — target repository deployment payloads.
locals {
  services_config_deployments = {
    for service_key, service in local.services_config_services : service_key => {
      key            = service_key
      name           = service.identity.name
      routing_labels = local.services_config_traefik_routing_labels[service_key]
      target         = service.target
      template       = service.identity.service

      custom = merge(
        service.identity.service == "gatus" ? {
          gatus = local.services_config_gatus
        } : {},
        service.identity.service == "homepage" ? {
          homepage = local.services_config_homepage
        } : {},
      )

      defaults = {
        organisation = {
          email = local.defaults.organisation.email
        }

        system = {
          timezone = local.defaults.system.timezone
        }
      }

      imports = {
        for alias, imported_service_key in local.services_model_imports[service_key] : alias => {
          routing = local.services_config_services[imported_service_key].routing
          urls    = local.services_config_services[imported_service_key].urls

          runtime = {
            credentials = local.services_config_services[imported_service_key].runtime.credentials
          }
        }
      }

      server = service.target == "fly" ? null : {
        age_public_key = try(age_secret_key.server[service.target].public_key, null)
        hosts          = local.services_config_servers[service.target].hosts
        key            = service.target

        runtime = {
          addresses   = local.services_config_servers[service.target].runtime.addresses
          credentials = local.services_config_servers[service.target].runtime.credentials
        }
      }

      servers = {
        for server_key, server_config in local.services_config_servers : server_key => {
          features = server_config.features
          hosts    = server_config.hosts
        }
      }

      service = {
        data     = service.data
        identity = service.identity
        routing  = service.routing
        target   = service.target
        urls     = service.urls

        runtime = {
          attributes  = service.runtime.attributes
          credentials = service.runtime.credentials
        }
      }

      services = {
        for shared_service_key, shared_service in local.services_config_services : shared_service_key => {
          target = shared_service.target

          data = shared_service.data.shared
        }
        if try(length(keys(local.services_model[shared_service_key].data.shared)), 0) > 0
      }
    }
  }
}
