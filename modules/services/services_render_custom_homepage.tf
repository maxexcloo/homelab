# Stage: render — Homepage-specific dashboard aggregation.
locals {
  _services_render_custom_homepage_data = try(one([
    for service in values(local.services_render_services) : service.data
    if service.identity.name == "homepage"
  ]), {})

  _services_render_custom_homepage_server_cards = flatten([
    for server_key, server in local.servers_render_servers : [
      for card_index, dashboard_card in server.dashboard : {
        group = dashboard_card.group
        name  = dashboard_card.name
        sort  = "${length(try(dashboard_card.widgets, [])) > 0 ? "0" : "1"}:${lower(dashboard_card.name)}:${server_key}:${card_index}"

        card = {
          for field, value in dashboard_card : field => value
          if(
            value != null &&
            !contains(["group", "name"], field)
          )
        }
      }
    ]
  ])

  _services_render_custom_homepage_service_cards = flatten([
    for service_key, service in local.services_render_services : [
      for card_index, dashboard_card in service.dashboard : {
        group = dashboard_card.group
        name  = dashboard_card.name
        sort  = "${length(try(dashboard_card.widgets, [])) > 0 ? "0" : "1"}:${lower(dashboard_card.name)}:${service_key}:${card_index}"

        card = {
          for field, value in dashboard_card : field => value
          if(
            value != null &&
            !contains(["group", "name"], field)
          )
        }
      }
      if(
        service.identity.name != "homepage" &&
        dashboard_card.name != ""
      )
    ]
  ])

  _services_render_custom_homepage_sort_index = {
    for dashboard_card in concat(local._services_render_custom_homepage_service_cards, local._services_render_custom_homepage_server_cards) : dashboard_card.sort => dashboard_card
  }

  _services_render_custom_homepage_sorted_by_group = {
    for card in [
      for sort_key in sort(keys(local._services_render_custom_homepage_sort_index)) :
      local._services_render_custom_homepage_sort_index[sort_key]
    ] : card.group => zipmap([card.name], [card.card])...
  }

  _services_render_custom_homepage_sorted_groups = sort(distinct([
    for dashboard_card in values(local._services_render_custom_homepage_sort_index) :
    dashboard_card.group
  ]))

  _services_render_custom_homepage_sorted_server_groups = [
    for group in local._services_render_custom_homepage_sorted_groups : group
    if contains([for server in values(local.servers_model) : server.identity.group], group)
  ]

  _services_render_custom_homepage_sorted_service_groups = [
    for group in local._services_render_custom_homepage_sorted_groups : group
    if !contains(local._services_render_custom_homepage_sorted_server_groups, group)
  ]

  _services_render_custom_homepage_union_groups = concat(
    local._services_render_custom_homepage_sorted_service_groups,
    ["Providers"],
    local._services_render_custom_homepage_sorted_server_groups,
  )

  _services_render_custom_homepage_view = {
    layout = [
      for group in local._services_render_custom_homepage_union_groups : {
        (group) = merge(
          {
            columns = 2
            style   = "row"
            tab     = contains(local._services_render_custom_homepage_sorted_server_groups, group) ? "Servers" : "Services"
          },
          contains(local._services_render_custom_homepage_sorted_service_groups, group) ? {
            columns = try(local._services_render_custom_homepage_data.groups[group].columns, 2)
            style   = try(local._services_render_custom_homepage_data.groups[group].style, "row")
          } : {},
        )
      }
    ]

    services = [
      for group in local._services_render_custom_homepage_union_groups : {
        (group) = try(local._services_render_custom_homepage_sorted_by_group[group], [])
      }
      if group != "Providers"
    ]
  }

  services_render_custom_homepage_context = {
    for service_key, service in local.services_model : service_key => {
      custom = {
        homepage = local._services_render_custom_homepage_view
      }
    }
    if service.identity.name == "homepage"
  }
}
