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
    version    = 3
    workflow   = "deploy.yaml"

    contexts = {
      for service_key, service in local._services_config_truenas_services : service_key => {
        custom         = local.services_config_custom[service_key]
        routing_labels = local.services_config_traefik_routing_labels[service_key]

        defaults = {
          organisation = {
            email = local.defaults.organisation.email
          }

          system = {
            timezone = local.defaults.system.timezone
          }
        }

        server = {
          age_public_key = try(age_secret_key.server[service.target].public_key, null)
          hosts          = local.services_config_servers[service.target].hosts
          key            = service.target

          runtime = {
            addresses   = local.services_config_servers[service.target].runtime.addresses
            credentials = local.services_config_servers[service.target].runtime.credentials
          }
        }

        service = {
          data     = local.services_config_services[service_key].data
          identity = local.services_config_services[service_key].identity
          routing  = local.services_config_services[service_key].routing
          target   = local.services_config_services[service_key].target
          truenas  = local.services_config_services[service_key].truenas
          urls     = local.services_config_services[service_key].urls

          runtime = {
            attributes  = local.services_config_services[service_key].runtime.attributes
            credentials = local.services_config_services[service_key].runtime.credentials
          }
        }
      }
    }

    deployments = [
      for service_key in sort(keys(local._services_config_truenas_services)) : {
        name    = local.services_model[service_key].identity.name
        key     = service_key
        service = local.services_model[service_key].identity.service
        target  = local.services_model[service_key].target
      }
    ]
  }

  services_config_truenas_workflow_dispatches = {
    for target_key in toset([
      for deployment in local.services_config_truenas.deployments : deployment.target
      ]) : "truenas/${target_key}" => {
      fingerprint = sha256(jsonencode([
        for deployment in local.services_config_truenas.deployments :
        local.services_config_truenas.contexts[deployment.key]
        if deployment.target == target_key
      ]))

      inputs = {
        changed_only = true
        deployment   = target_key
      }
    }
  }
}
