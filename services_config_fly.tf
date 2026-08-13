# Stage: config — Fly.io deployment context.
locals {
  services_config_fly = {
    repository = "fly"
    workflow   = "deploy.yaml"

    deployments = [
      for service_key, service in local.services_model : merge(
        local.services_config_deployments[service_key],
        {
          app           = service.fly.app_name
          cpu_kind      = service.fly.cpu_kind
          cpus          = service.fly.cpus
          force_https   = alltrue([for route in service.routing : route.https])
          image         = service.fly.image
          machine_count = service.fly.machine_count
          memory_mb     = service.fly.memory_mb
          region        = service.fly.region

          certificates = [
            for route in service.routing : route.host
            if route.host_configured
          ]
        },
      )
      if service.target == "fly" && service.identity.service != null
    ]
  }
}
