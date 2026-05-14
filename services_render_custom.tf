locals {
  _homepage_cards_by_group = {
    for card in [
      for sort_key in sort(keys(local._homepage_cards_by_sort)) :
      local._homepage_cards_by_sort[sort_key]
    ] : card.group => zipmap([card.name], [card.card])...
  }

  _homepage_cards_by_sort = {
    for dashboard_card in concat(local._homepage_service_cards, local._homepage_server_cards) : dashboard_card.sort => dashboard_card
  }

  _homepage_groups = concat(
    local._homepage_service_groups,
    ["Providers"],
    local._homepage_server_groups,
  )

  _homepage_server_cards = flatten([
    for server_key, server in local.servers_runtime_rendered : [
      for card_index, dashboard_card in server.dashboard : {
        group = dashboard_card.group
        name  = dashboard_card.name
        sort  = "1:${length(try(dashboard_card.widgets, [])) > 0 ? "0" : "1"}:${server_key}:${card_index}"

        card = {
          for field, value in dashboard_card : field => value
          if value != null && !contains(["group", "name"], field)
        }
      }
    ]
  ])

  _homepage_server_groups = concat(
    local._homepage_server_matched_groups,
    [
      for group in sort(distinct([
        for dashboard_card in local._homepage_server_cards : dashboard_card.group
      ])) : group
      if !contains(local._homepage_server_matched_groups, group)
    ],
  )

  _homepage_server_matched_groups = sort(distinct([
    for dashboard_card in local._homepage_service_cards : dashboard_card.group
    if contains(local._homepage_server_names, dashboard_card.group)
  ]))

  _homepage_server_names = [
    for dashboard_card in local._homepage_server_cards : dashboard_card.name
  ]

  _homepage_service_cards = flatten([
    for service_key, service in local.services_render_services : [
      for card_index, dashboard_card in service.dashboard : {
        group = dashboard_card.group
        name  = dashboard_card.name
        sort  = "0:${length(try(dashboard_card.widgets, [])) > 0 ? "0" : "1"}:${service_key}:${card_index}"

        card = {
          for field, value in dashboard_card : field => value
          if value != null && !contains(["group", "name"], field)
        }
      }
      if service.identity.name != "homepage" && dashboard_card.name != ""
    ]
  ])

  _homepage_service_groups = sort(distinct([
    for dashboard_card in local._homepage_service_cards : dashboard_card.group
    if !contains(local._homepage_server_names, dashboard_card.group)
  ]))

  services_render_custom_context = {
    for service_key, service in local.services : service_key =>
    lookup({
      homepage = {
        homepage = {
          layout = [
            for group in local._homepage_groups : {
              (group) = (
                group == "Providers" ? {
                  columns = 2
                  style   = "row"
                  tab     = "Services"
                  } : contains(local._homepage_service_groups, group) ? {
                  columns = local.services_input["homepage"].data.groups[group].columns
                  style   = local.services_input["homepage"].data.groups[group].style
                  tab     = "Services"
                  } : {
                  columns = 2
                  style   = "row"
                  tab     = "Servers"
                }
              )
            }
          ]

          services = [
            for group in local._homepage_groups : {
              (group) = try(local._homepage_cards_by_group[group], [])
            }
            if group != "Providers"
          ]
        }
      }
    }, service.identity.name, {})
  }
}
