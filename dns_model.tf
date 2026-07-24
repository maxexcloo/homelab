locals {
  _dns_model_hosts = distinct(flatten([
    [
      for service in values(module.services.model.input_targets) : [
        for route in service.routing.routes : route.host
        if route.host != null
      ]
    ],
    [
      for service in values(module.services.model.input_targets) : [
        for route in service.routing.routes : [
          for redirect in try(route.redirects, []) : redirect
        ]
      ]
    ],
    [
      for server in values(module.servers.model.input) : [
        for route in server.routing.routes : route.host
      ]
    ],
  ]))

  _dns_model_managed_zones_by_host = {
    for host, matches in local._dns_model_zones_by_host : host => try(
      one([for match in matches : match.name if match.length == max(matches[*].length...)]),
      null,
    )
  }

  _dns_model_manual_entries = flatten([
    for zone, records in local.dns_input : [
      for record in records : {
        key    = try(record.id, join("-", compact([record.type, replace(record.name, "@", "apex"), tostring(try(record.priority, ""))])))
        record = record
        zone   = zone
      }
    ]
  ])

  # Longest matching zone wins for nested domains.
  _dns_model_zones_by_host = {
    for host in local._dns_model_hosts : host => [
      for zone in keys(local.dns_input) : {
        length = length(zone)
        name   = zone
      }
      if(
        host == zone ||
        endswith(host, ".${zone}")
      )
    ]
  }

  dns_model_manual_entries_by_key = {
    for entry in local._dns_model_manual_entries :
    "${entry.zone}-manual-${entry.key}" => entry...
  }

  dns_model_routes = merge(
    merge([
      for server_key, server in module.servers.model.servers : {
        for route in server.routing.routes : "${server_key}-route-${route.id}" => {
          expose     = route.expose
          hostname   = route.host
          server_key = startswith(route.expose, "proxy-") ? trimprefix(route.expose, "proxy-") : server_key
          source     = "server"

          dns = local._dns_model_managed_zones_by_host[route.host] != null ? {
            proxied = route.expose == "cloudflare"
            zone    = local._dns_model_managed_zones_by_host[route.host]

            content = (
              startswith(route.expose, "proxy-")
              ? try(module.servers.model.servers[trimprefix(route.expose, "proxy-")].hosts.external, null)
              : route.expose == "external"
              ? server.hosts.external
              : server.hosts.internal
            )
          } : null

          tunnel = (
            route.expose == "cloudflare" &&
            server.features.cloudflared &&
            local._dns_model_managed_zones_by_host[route.host] != null
            ) ? {
            server_key = server_key
            url        = route.backend_url
          } : null
        }
      }
    ]...),
    merge([
      for service_key, service in module.services.model.services : {
        for route in service.routing.routes : "${service_key}-url-${route.id}" => {
          expose   = route.expose
          hostname = route.host
          source   = "service"

          dns = (
            route.host_configured &&
            route.zone != null
            ) ? {
            proxied = route.expose == "cloudflare"
            zone    = route.zone

            content = (
              service.target == "fly" ? "${service.fly.app_name}.fly.dev"
              : route.proxy_server != null ? module.servers.model.servers[route.proxy_server].hosts.external
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
            try(module.servers.model.servers[service.target].features.cloudflared, false)
            ) ? {
            server_key = service.target
            url        = "https://localhost:443"
          } : null
        }
      }
    ]...),
    merge(flatten([
      for service_key, service in module.services.model.services : [
        for route in service.routing.routes : {
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
                ? module.servers.model.servers[redirect.proxy_server].hosts.external
                : redirect.expose == "external"
                ? module.servers.model.servers[service.target].hosts.external
                : module.servers.model.servers[service.target].hosts.internal
              )
            } : null
          }
        }
      ]
    ])...),
  )
}
