# Stage: config — shared non-secret deployment context.
locals {
  _services_config_provider_index = {
    for provider_key, provider in local.defaults.providers :
    "${lower(provider.title)}:${provider_key}" => provider
  }

  _services_config_server_bases = {
    for server_key, server in local.servers_model : server_key => merge(
      server,
      {
        runtime = merge(
          local.servers_resolved[server_key].runtime,
          {
            credentials = {
              for credential_name in keys(server.credentials.fields) :
              credential_name => "op://${local.defaults.onepassword.vaults.servers.id}/${local.onepassword_server_item_ids[server_key]}/${credential_name}"
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
              for credential_name in distinct(concat(
                keys(service.credentials.fields),
                service.credentials.source == "target" ? ["password"] : [],
                )) : credential_name => (
                credential_name == "password" && service.credentials.source == "target"
                ? "op://${local.defaults.onepassword.vaults.servers.id}/${local.onepassword_server_item_ids[service.target]}/password"
                : "op://${local.defaults.onepassword.vaults.services.id}/${local.onepassword_service_item_ids[service_key]}/${credential_name}"
              )
            }
          },
        )
      },
    )
  }

  services_config_providers = [
    for sort_key in sort(keys(local._services_config_provider_index)) :
    local._services_config_provider_index[sort_key]
  ]

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
            defaults = local.defaults
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
            defaults = local.defaults
            server   = try(local.services_config_servers[service.target], null)
            service  = service

            servers = merge(
              local.servers_model,
              service.target != "fly" && can(local.services_config_servers[service.target]) ? {
                (service.target) = local.services_config_servers[service.target]
              } : {},
              {
                for alias, imported_server_key in local.services_model_server_imports[service_key] :
                alias => local.services_config_servers[imported_server_key]
                if can(local.services_config_servers[imported_server_key])
              },
            )

            services = merge(
              local.services_model,
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
}
