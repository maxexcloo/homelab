locals {
  _services_config_gatus_provider_endpoints = [
    for provider in local.services_config_providers : {
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

  _services_config_gatus_service_key = one([
    for service_key, service in local.services_model : service_key
    if service.identity.service == "gatus"
  ])

  gatus_monitored_services = [
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
        for url_key, url in local.services_resolved[service_key].urls : {
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

  services_config_gatus = {
    environment = merge(
      {
        MAIL_PASSWORD      = "op://${local.defaults.onepassword.vaults.services.id}/${local.onepassword_service_item_ids[local._services_config_gatus_service_key]}/mail_password"
        TAILSCALE_AUTH_KEY = "op://${local.defaults.onepassword.vaults.services.id}/${local.onepassword_service_item_ids[local._services_config_gatus_service_key]}/tailscale_auth_key"
      },
      {
        for service in local.gatus_monitored_services :
        "MONITORING_TOKEN_${upper(replace(service.key, "-", "_"))}" => "op://${local.defaults.onepassword.vaults.services.id}/${service.item}/monitoring_token"
      },
    )

    mail = {
      from     = local.services[local._services_config_gatus_service_key].runtime.attributes.mail_from_address
      host     = local.services[local._services_config_gatus_service_key].runtime.attributes.mail_host
      port     = local.services[local._services_config_gatus_service_key].runtime.attributes.mail_port
      to       = local.defaults.organisation.email
      username = local.services[local._services_config_gatus_service_key].runtime.attributes.mail_username

      default-alert = {
        description       = "${local.services[local._services_config_gatus_service_key].identity.title} Check Failed"
        failure-threshold = 5
        send-on-resolved  = true
        success-threshold = 5
      }
    }

    probes = concat(
      flatten([
        for service in local.gatus_monitored_services : [
          for url in service.urls : merge(
            {
              group = " ${url.host}"
              name  = "${service.title} (${service.target})"
              url   = url.href

              conditions = [
                "[CERTIFICATE_EXPIRATION] > 168h",
                "[RESPONSE_TIME] < 5000",
                service.features.oidc_forward_auth ? "[STATUS] == 200" : "[STATUS] == any(200, 401)",
              ]

              headers = merge(
                {
                  X-Gatus-Token = format("$${MONITORING_TOKEN_%s}", upper(replace(service.key, "-", "_")))
                },
              )
            },
            service.features.monitoring_alerts ? {
              alerts = [
                {
                  type = "email"
                },
              ]
            } : {},
          )
        ]
      ]),
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
      local.services_config_services[local._services_config_gatus_service_key].data.endpoints,
      local._services_config_gatus_provider_endpoints,
    )

    ui = {
      dashboard-heading    = local.services[local._services_config_gatus_service_key].identity.title
      dashboard-subheading = local.services[local._services_config_gatus_service_key].identity.description
      default-sort-by      = "group"
      description          = local.services[local._services_config_gatus_service_key].identity.description
      header               = local.services[local._services_config_gatus_service_key].identity.title
      title                = local.services[local._services_config_gatus_service_key].identity.title
    }
  }
}
