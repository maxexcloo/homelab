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

output "configs" {
  description = "Non-secret deployment configs keyed by repository"

  value = nonsensitive({
    truenas = local.services_config_truenas

    docker = {
      repository = "docker"
      version    = 1
      workflow   = "render.yaml"

      deployments = [
        for service_key, service in local._docker_services : {
          item    = try(local.onepassword_service_item_ids[service_key], null)
          key     = service_key
          service = service.identity.service
          target  = service.target

          attributes = local.services[service_key].runtime.attributes

          custom = try(
            local.services_render_custom_traefik_context[service_key].custom,
            {},
          )

          imports = {
            for alias, imported_service_key in local.services_model_imports[service_key] : alias => {
              item = try(local.onepassword_service_item_ids[imported_service_key], null)
              key  = imported_service_key
            }
          }

          labels = {
            for label_key, label_value in try(
              local._services_render_traefik_routing_labels[service_key][service.identity.service],
              {},
              ) : label_key => (
              endswith(label_key, ".basicauth.users")
              ? "$${MONITORING_PASSWORD_HASH}"
              : label_value
            )
          }

          routing = {
            backend_port = service.routing.backend_port
          }

          urls = {
            for url_key, url in local.services_render_services[service_key].urls : url_key => {
              href = url.href
            }
          }
        }
      ]

      targets = [
        for server_key, server in local._docker_servers : {
          age_public_key = var.servers.age_public_keys[server_key]
          email          = local.defaults.organization.email
          hosts          = server.hosts
          item           = var.servers.item_ids[server_key]
          key            = server_key

          addresses = {
            tailscale_ipv4 = local.servers_render_servers[server_key].runtime.addresses.tailscale_ipv4
          }
        }
      ]

      vaults = {
        servers  = local.defaults.onepassword.vaults.servers.id
        services = local.defaults.onepassword.vaults.services.id
      }
    }

    fly = {
      gatus      = local.services_config_gatus
      repository = "fly"
      vault_id   = local.defaults.onepassword.vaults.services.id
      version    = 2
      workflow   = "deploy.yaml"

      deployments = [
        for service_key, service in local.services_model : {
          app           = service.fly.app_name
          backend_port  = service.routing.backend_port
          cpu_kind      = service.fly.cpu_kind
          cpus          = service.fly.cpus
          force_https   = alltrue([for route in service.routing.routes : route.https])
          image         = service.fly.image
          item          = try(local.onepassword_service_item_ids[service_key], null)
          key           = service_key
          machine_count = service.fly.machine_count
          memory_mb     = service.fly.memory_mb
          region        = service.fly.region
          service       = service.identity.service

          certificates = [
            for route in service.routing.routes : route.host
            if route.host_configured
          ]
        }
        if service.target == "fly" && service.identity.service != null
      ]

      services = [
        for service_key in sort(keys(local.services_model)) : {
          item   = try(local.onepassword_service_item_ids[service_key], null)
          key    = service_key
          target = local.services_model[service_key].target
          title  = local.services_model[service_key].identity.title

          features = {
            monitoring_alerts = local.services_model[service_key].features.monitoring_alerts
            oidc_forward_auth = local.services_model[service_key].features.oidc_forward_auth
          }

          urls = [
            for url_key, url in local.services_render_services[service_key].urls : {
              host = url.zone
              href = url.href
            }
            if url_key != "default" && url.href != null && url.zone != null
          ]
        }
        if(
          local.services_model[service_key].features.monitoring &&
          local.services_model[service_key].routing.backend_scheme != ""
        )
      ]
    }

  })
}

output "runtime" {
  description = "Service runtime objects keyed by service"
  sensitive   = true
  value       = local.services
}
