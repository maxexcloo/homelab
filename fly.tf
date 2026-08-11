# Stage: config — Fly.io deployment context.
locals {
  _github_fly_deployments = {
    for deployment in local.services_configs.fly.deployments : deployment.key => {
      app        = deployment.app
      owner      = local.defaults.github.owner
      repository = local.defaults.github.deployment_repositories.fly.name
    }
  }

  services_config_fly = {
    repository = "fly"
    workflow   = "deploy.yaml"

    deployments = [
      for service_key, service in local.services_model : {
        app           = service.fly.app_name
        backend       = service.routing.default.backend
        cpu_kind      = service.fly.cpu_kind
        cpus          = service.fly.cpus
        custom        = local.services_config_custom[service_key]
        force_https   = alltrue([for route in service.routing : route.https])
        image         = service.fly.image
        item          = try(local.onepassword_service_item_ids[service_key], null)
        key           = service_key
        machine_count = service.fly.machine_count
        memory_mb     = service.fly.memory_mb
        region        = service.fly.region
        service       = service.identity.service

        certificates = [
          for route in service.routing : route.host
          if route.host_configured
        ]
      }
      if service.target == "fly" && service.identity.service != null
    ]
  }
}
