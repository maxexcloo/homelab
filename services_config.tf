# Stage: config — target repository deployment payloads.
locals {
  _services_config_docker_servers = {
    for server_key, server in local.servers_model : server_key => server
    if server.features.docker
  }

  _services_config_docker_services = {
    for service_key, service in local.services_model : service_key => service
    if(
      can(local._services_config_docker_servers[service.target]) &&
      service.identity.service != null &&
      (service.target_feature == "" || service.target_feature == "docker")
    )
  }

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

  services_config_workflow_dispatches = {
    truenas = local.services_config_truenas_workflow_dispatches
  }

  services_configs = {
    truenas = local.services_config_truenas

    docker = {
      repository = "docker"
      workflow   = "publish.yaml"

      deployments = [
        for service_key, service in local._services_config_docker_services : {
          attributes = local.services[service_key].runtime.attributes
          custom     = local.services_config_custom[service_key]
          item       = try(local.onepassword_service_item_ids[service_key], null)
          key        = service_key
          service    = service.identity.service
          target     = service.target

          imports = {
            for alias, imported_service_key in local.services_model_imports[service_key] : alias => {
              item = try(local.onepassword_service_item_ids[imported_service_key], null)
              key  = imported_service_key
            }
          }

          labels = {
            for label_key, label_value in try(
              local.services_config_traefik_routing_labels[service_key][service.identity.service],
              {},
              ) : label_key => replace(
              label_value,
              "op://${local.defaults.onepassword.vaults.services.id}/${local.onepassword_service_item_ids[service_key]}/monitoring_token",
              "$${MONITORING_TOKEN}",
            )
          }

          routing = {
            backend_port = try(service.routing.default.backend_port, null)
          }

          urls = {
            for url_key, url in service.urls : url_key => {
              href = url.href
            }
          }
        }
      ]

      targets = [
        for server_key, server in local._services_config_docker_servers : {
          age_public_key = age_secret_key.server[server_key].public_key
          email          = local.defaults.organisation.email
          hosts          = server.hosts
          item           = local.onepassword_server_item_ids[server_key]
          key            = server_key

          addresses = {
            tailscale_ipv4 = local.servers_resolved[server_key].runtime.addresses.tailscale_ipv4
          }
        }
      ]

      vaults = {
        servers  = local.defaults.onepassword.vaults.servers.id
        services = local.defaults.onepassword.vaults.services.id
      }
    }

    fly = {
      repository = "fly"
      workflow   = "deploy.yaml"

      deployments = [
        for service_key, service in local.services_model : {
          app           = service.fly.app_name
          backend_port  = service.routing.default.backend_port
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
}
