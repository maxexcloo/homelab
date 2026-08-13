# Stage: config — TrueNAS deployment context.
locals {
  _services_config_truenas_deployments = {
    for service_key, service in local.services_model : service_key => merge(
      local.services_config_deployments[service_key],
      {
        service = merge(
          local.services_config_deployments[service_key].service,
          {
            truenas = local.services_config_services[service_key].truenas
          },
        )
      },
    )
    if(
      service.identity.service != null &&
      try(local.servers_model[service.target].platform, null) == "truenas"
    )
  }

  services_config_truenas = {
    repository = "truenas"
    workflow   = "deploy.yaml"

    deployments = [
      for service_key in sort(keys(local._services_config_truenas_deployments)) :
      local._services_config_truenas_deployments[service_key]
    ]
  }
}
