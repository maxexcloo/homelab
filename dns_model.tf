locals {
  _dns_model_manual_entries = flatten([
    for zone, records in local.dns_input : [
      for record in records : {
        key    = try(record.id, join("-", compact([record.type, replace(record.name, "@", "apex"), tostring(try(record.priority, ""))])))
        record = record
        zone   = zone
      }
    ]
  ])

  _dns_model_urls = distinct(flatten([
    [
      for service in values(local.services_input_targets) : [
        for url in service.routing.urls : url.url
        if url.url != null
      ]
    ],
    [
      for service in values(local.services_input_targets) : [
        for url in service.routing.urls : [
          for redirect in try(url.redirects, []) : redirect
        ]
      ]
    ],
    [
      for server in values(local.servers_input) : [
        for url in server.routing.urls : url.url
      ]
    ],
  ]))

  # Longest matching zone wins for nested domains.
  _dns_model_zones_matching = {
    for url in local._dns_model_urls : url => [
      for zone in keys(local.dns_input) : {
        length = length(zone)
        name   = zone
      }
      if(
        url == zone ||
        endswith(url, ".${zone}")
      )
    ]
  }

  dns_model_managed_zones_by_url = {
    for url, matches in local._dns_model_zones_matching : url => try(
      one([for match in matches : match.name if match.length == max(matches[*].length...)]),
      null,
    )
  }

  dns_model_manual_entries_by_key = {
    for entry in local._dns_model_manual_entries :
    "${entry.zone}-manual-${entry.key}" => entry...
  }

  dns_model_routes = merge(
    merge([
      for server_key, server in local.servers_model : {
        for route in server.routing.urls : "${server_key}-route-${route.id}" => {
          expose     = route.expose
          hostname   = route.url
          server_key = startswith(route.expose, "proxy-") ? trimprefix(route.expose, "proxy-") : server_key
          source     = "server"

          dns = local.dns_model_managed_zones_by_url[route.url] != null ? {
            proxied = route.expose == "cloudflare"
            zone    = local.dns_model_managed_zones_by_url[route.url]

            content = (
              startswith(route.expose, "proxy-")
              ? try(local.servers_model[trimprefix(route.expose, "proxy-")].hosts.external, null)
              : route.expose == "external"
              ? server.hosts.external
              : server.hosts.internal
            )
          } : null
          tunnel = (
            route.expose == "cloudflare" &&
            server.features.cloudflared &&
            local.dns_model_managed_zones_by_url[route.url] != null
            ) ? {
            server_key = server_key
            url        = route.backend_url
          } : null
        }
      }
    ]...),
    merge([
      for service_key, service in local.services_model : {
        for route in service.routing.urls : "${service_key}-url-${route.id}" => {
          expose   = route.expose
          hostname = route.host
          source   = "service"

          dns = (
            route.url != null &&
            route.zone != null
            ) ? {
            proxied = route.expose == "cloudflare"
            zone    = route.zone

            content = (
              service.target == "fly" ? "${service.fly.app_name}.fly.dev"
              : route.proxy_server != null ? local.servers_model[route.proxy_server].hosts.external
              : route.dns_target_host
            )
          } : null
          server_key = (
            service.target == "fly" ? null
            : route.proxy_server != null ? route.proxy_server
            : service.target
          )
          tunnel = (
            route.expose == "cloudflare" &&
            route.host != null &&
            route.zone != null &&
            try(local.servers_model[service.target].features.cloudflared, false)
            ) ? {
            server_key = service.target
            url        = "https://localhost:443"
          } : null
        }
      }
    ]...),
    merge(flatten([
      for service_key, service in local.services_model : [
        for route in service.routing.urls : {
          for redirect in route.redirects : "${service_key}-redirect-${substr(sha1(redirect.host), 0, 12)}" => {
            expose     = redirect.expose
            hostname   = redirect.host
            server_key = redirect.proxy_server != null ? redirect.proxy_server : service.target
            source     = "redirect"
            tunnel     = null

            dns = redirect.zone != null ? {
              proxied = false
              zone    = redirect.zone

              content = (
                redirect.proxy_server != null
                ? local.servers_model[redirect.proxy_server].hosts.external
                : redirect.expose == "external"
                ? local.servers_model[service.target].hosts.external
                : local.servers_model[service.target].hosts.internal
              )
            } : null
          }
        }
      ]
    ])...),
  )
}
