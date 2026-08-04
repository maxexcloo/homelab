# Stage: config — non-secret deployment context for target repositories.
locals {
  _services_config_defaults = local.defaults

  _services_config_server_bases = {
    for server_key, server in local.servers_model : server_key => merge(
      server,
      {
        runtime = merge(
          local.servers_render_servers[server_key].runtime,
          {
            credentials = {
              for credential_name in keys(local.servers_render_servers[server_key].runtime.credentials) :
              credential_name => "op://${local.defaults.onepassword.vaults.servers.id}/${var.servers.item_ids[server_key]}/${credential_name}"
            }
          },
        )
      },
    )
  }

  _services_config_service_bases = {
    for service_key, service in local.services_model : service_key => merge(
      service,
      {
        runtime = merge(
          local.services[service_key].runtime,
          {
            credentials = {
              for credential_name in keys(local.services[service_key].runtime.credentials) :
              credential_name => "op://${local.defaults.onepassword.vaults.services.id}/${module.onepassword.item_ids[service_key]}/${credential_name}"
            }
          },
        )
      },
    )
  }

  services_config_servers = {
    for server_key, server in local._services_config_server_bases : server_key => merge(
      server,
      jsondecode(
        templatestring(
          replace(
            jsonencode({
              dashboard = server.dashboard
              data      = server.data
            }),
            local.render_json_template_expression_pattern,
            local.render_json_template_expression_replacement,
          ),
          {
            defaults = local._services_config_defaults
            server   = server
            servers  = local._services_config_server_bases
          },
        ),
      ),
    )
  }

  services_config_services = {
    for service_key, service in local._services_config_service_bases : service_key => merge(
      service,
      jsondecode(
        templatestring(
          replace(
            jsonencode({
              dashboard = service.dashboard
              data      = service.data
              truenas   = service.truenas
            }),
            local.render_json_template_expression_pattern,
            local.render_json_template_expression_replacement,
          ),
          {
            defaults = local._services_config_defaults
            server   = try(local.services_config_servers[service.target], null)
            service  = service

            servers = merge(
              local.services_config_servers,
              {
                for alias, imported_server_key in local.services_model_server_imports[service_key] :
                alias => local.services_config_servers[imported_server_key]
                if can(local.services_config_servers[imported_server_key])
              },
            )

            services = merge(
              local._services_config_service_bases,
              {
                for alias, imported_service_key in local.services_model_imports[service_key] :
                alias => local._services_config_service_bases[imported_service_key]
              },
            )
          },
        ),
      ),
    )
  }

  services_config_truenas = {
    repository = "truenas"
    version    = 1
    workflow   = "deploy.yaml"

    custom = {
      for service_key in sort(keys(local.truenas_services)) : service_key => try(
        local.services_render_custom_traefik_context[service_key].custom,
        {},
      )
    }

    defaults = {
      organization = {
        email = local.defaults.organization.email
      }

      system = {
        timezone = local.defaults.system.timezone
      }
    }

    deployments = [
      for service_key in sort(keys(local.truenas_services)) : {
        key     = service_key
        name    = local.services_model[service_key].identity.name
        service = local.services_model[service_key].identity.service
        target  = local.services_model[service_key].target

        imports = local.services_model_imports[service_key]
      }
    ]

    homepage = {
      providers = local.services_render_providers

      servers = [
        for server_key in sort(keys(local.services_config_servers)) : {
          dashboard = local.services_config_servers[server_key].dashboard
          key       = server_key
        }
      ]

      services = [
        for service_key in sort(keys(local.services_config_services)) : {
          dashboard = local.services_config_services[service_key].dashboard
          key       = service_key
          name      = local.services_config_services[service_key].identity.name
        }
      ]
    }

    routing_labels = {
      for service_key in sort(keys(local.truenas_services)) : service_key => {
        for container, labels in local._services_render_traefik_routing_labels[service_key] : container => {
          for label_key, label_value in labels : label_key => (
            endswith(label_key, ".basicauth.users")
            ? "op://${local.defaults.onepassword.vaults.services.id}/${module.onepassword.item_ids[service_key]}/monitoring_password_hash"
            : label_value
          )
        }
      }
    }

    servers = {
      for server_key, server in local.services_config_servers : server_key => {
        age_public_key = try(var.servers.age_public_keys[server_key], null)
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
      if can(local.truenas_services[service_key]) || contains(
        flatten(values(local.services_model_imports)),
        service_key,
      )
    }

  }
}
