locals {
  _services_config_homepage_cards = flatten([
    for source in values(merge(
      {
        for server_key, server in local.services_config_servers :
        "server:${server_key}" => server
      },
      {
        for service_key, service in local.services_config_services :
        "service:${service_key}" => service
        if service.identity.service != "homepage"
      },
      )) : [
      for card_index, dashboard_card in source.dashboard : {
        group = dashboard_card.group
        name  = dashboard_card.name
        sort  = "${length(try(dashboard_card.widgets, [])) > 0 ? "0" : "1"}:${lower(dashboard_card.name)}:${source.key}:${card_index}"

        card = {
          for field, value in dashboard_card : field => value
          if(
            value != null &&
            !contains(["group", "name"], field)
          )
        }
      }
      if dashboard_card.name != ""
    ]
  ])

  _services_config_homepage_data = try(one([
    for service in values(local.services_config_services) : service.data
    if service.identity.service == "homepage"
  ]), {})

  _services_config_homepage_sort_index = {
    for dashboard_card in local._services_config_homepage_cards :
    dashboard_card.sort => dashboard_card
  }

  _services_config_homepage_sorted_by_group = {
    for card in [
      for sort_key in sort(keys(local._services_config_homepage_sort_index)) :
      local._services_config_homepage_sort_index[sort_key]
    ] : card.group => zipmap([card.name], [card.card])...
  }

  _services_config_homepage_sorted_groups = sort(distinct([
    for dashboard_card in values(local._services_config_homepage_sort_index) :
    dashboard_card.group
  ]))

  _services_config_homepage_sorted_server_groups = [
    for group in local._services_config_homepage_sorted_groups : group
    if contains([for server in values(local.servers_model) : server.identity.group], group)
  ]

  _services_config_homepage_sorted_service_groups = [
    for group in local._services_config_homepage_sorted_groups : group
    if !contains(local._services_config_homepage_sorted_server_groups, group)
  ]

  _services_config_homepage_union_groups = concat(
    local._services_config_homepage_sorted_service_groups,
    ["Providers"],
    local._services_config_homepage_sorted_server_groups,
  )

  services_config_homepage = {
    bookmarks = [
      {
        Providers = [
          for provider in local.services_config_providers : {
            (provider.title) = [
              {
                description = provider.description
                href        = provider.href
                icon        = provider.icon
              },
            ]
          }
        ]
      },
    ]

    layout = [
      for group in local._services_config_homepage_union_groups : {
        (group) = merge(
          {
            columns = 2
            style   = "row"
            tab     = contains(local._services_config_homepage_sorted_server_groups, group) ? "Servers" : "Services"
          },
          contains(local._services_config_homepage_sorted_service_groups, group) ? {
            columns = try(local._services_config_homepage_data.groups[group].columns, 2)
            style   = try(local._services_config_homepage_data.groups[group].style, "row")
          } : {},
        )
      }
    ]

    services = [
      for group in local._services_config_homepage_union_groups : {
        (group) = try(local._services_config_homepage_sorted_by_group[group], [])
      }
      if group != "Providers"
    ]
  }
}
