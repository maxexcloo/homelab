# Stage: config — target repository deployment payloads.
locals {
  services_config_custom = {
    for service_key, service in local.services_model : service_key => merge(
      service.identity.service == "dozzle" ? {
        dozzle = {
          agents = [
            for server_key in sort(keys(local.servers_model)) : {
              host = local.servers_model[server_key].hosts.internal
              key  = server_key
            }
            if local.servers_model[server_key].features.dozzle
          ]
        }
      } : {},
      service.identity.service == "gatus" ? {
        gatus = local.services_config_gatus
      } : {},
      service.identity.service == "homepage" ? {
        homepage = local.services_config_homepage
      } : {},
      service.identity.service == "traefik" ? {
        traefik = local.services_config_traefik[service_key]
      } : {},
    )
  }

  services_configs = {
    docker  = local.services_config_docker
    fly     = local.services_config_fly
    truenas = local.services_config_truenas
  }
}
