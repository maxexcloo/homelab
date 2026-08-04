# Stage: render — Gatus-specific global inventory.
locals {
  _services_render_custom_gatus_provider_endpoints = [
    for provider in local.services_render_providers : {
      group = "Providers"
      name  = provider.title
      url   = provider.href

      alerts = [
        {
          type = "email"
        },
      ]

      conditions = [
        "[STATUS] == any(200, 401, 403)",
        "[RESPONSE_TIME] < 5000",
      ]
    }
  ]

  _services_render_custom_gatus_service_key = one([
    for service_key, service in local.services_model : service_key
    if service.identity.service == "gatus"
  ])

  services_config_gatus = {
    mail = {
      from     = local.services[local._services_render_custom_gatus_service_key].runtime.attributes.mail_from_address
      host     = local.services[local._services_render_custom_gatus_service_key].runtime.attributes.mail_host
      port     = local.services[local._services_render_custom_gatus_service_key].runtime.attributes.mail_port
      to       = local.defaults.organization.email
      username = local.services[local._services_render_custom_gatus_service_key].runtime.attributes.mail_username

      default-alert = {
        description       = "${local.services[local._services_render_custom_gatus_service_key].identity.title} Check Failed"
        failure-threshold = 5
        send-on-resolved  = true
        success-threshold = 5
      }
    }

    probes = concat(
      flatten([
        for server_key in sort(keys(local.servers_model)) : concat(
          local.servers_model[server_key].features.monitoring ? [merge(
            {
              group = "Internal / ${local.defaults.server_types[local.servers_model[server_key].type].display_name}"
              name  = "${local.servers_model[server_key].identity.title} (${server_key})"
              url   = "icmp://${local.servers_model[server_key].hosts.internal}"

              conditions = [
                "[CONNECTED] == true",
                "[RESPONSE_TIME] < 5000",
              ]
            },
            local.servers_model[server_key].features.monitoring_alerts ? {
              alerts = [
                {
                  type = "email"
                },
              ]
            } : {},
          )] : [],
          local.servers_model[server_key].features.monitoring && local.servers_model[server_key].features.monitoring_external ? [merge(
            {
              group = "External / ${local.defaults.server_types[local.servers_model[server_key].type].display_name}"
              name  = "${local.servers_model[server_key].identity.title} (${server_key})"
              url   = "icmp://${local.servers_model[server_key].hosts.external}"

              conditions = [
                "[CONNECTED] == true",
                "[RESPONSE_TIME] < 5000",
              ]
            },
            local.servers_model[server_key].features.monitoring_alerts ? {
              alerts = [
                {
                  type = "email"
                },
              ]
            } : {},
          )] : [],
        )
      ]),
      local.services_render_services[local._services_render_custom_gatus_service_key].data.endpoints,
      local._services_render_custom_gatus_provider_endpoints,
    )

    ui = {
      dashboard-heading    = local.services[local._services_render_custom_gatus_service_key].identity.title
      dashboard-subheading = local.services[local._services_render_custom_gatus_service_key].identity.description
      default-sort-by      = "group"
      description          = local.services[local._services_render_custom_gatus_service_key].identity.description
      header               = local.services[local._services_render_custom_gatus_service_key].identity.title
      title                = local.services[local._services_render_custom_gatus_service_key].identity.title
    }
  }
}
