locals {
  _dns_render_records_manual_entries = flatten([
    for zone, records in local.dns_input : [
      for record in records : {
        key    = try(record.id, join("-", compact([record.type, replace(record.name, "@", "apex"), tostring(try(record.priority, ""))])))
        record = record
        zone   = zone
      }
    ]
  ])

  _dns_render_records_manual_entries_by_key = {
    for entry in local._dns_render_records_manual_entries :
    "${entry.zone}-manual-${entry.key}" => entry...
  }

  # Manual records are keyed independently from YAML list order.
  dns_render_records_manual = {
    for record_key, entries in local._dns_render_records_manual_entries_by_key :
    record_key => merge(
      local.defaults.dns,
      entries[0].record,
      {
        name = entries[0].record.name == "@" ? entries[0].zone : "${entries[0].record.name}.${entries[0].zone}"
        zone = entries[0].zone
      },
    )
  }

  dns_render_records_servers = merge([
    for server_key, server in local.servers_model : merge(
      (
        server.platform != "oci" &&
        server.addresses.public_ipv4 != null
        ) ? {
        "${local.defaults.domains.external}-${server_key}-a" = {
          content  = server.addresses.public_ipv4
          name     = server.hosts.external
          proxied  = false
          type     = "A"
          wildcard = true
          zone     = local.defaults.domains.external
        }
      } : {},
      (
        server.platform != "oci" &&
        server.addresses.public_ipv6 != null
        ) ? {
        "${local.defaults.domains.external}-${server_key}-aaaa" = {
          content  = server.addresses.public_ipv6
          name     = server.hosts.external
          proxied  = false
          type     = "AAAA"
          wildcard = true
          zone     = local.defaults.domains.external
        }
      } : {},
      server.platform == "oci" ? {
        "${local.defaults.domains.external}-${server_key}-a" = {
          content  = data.oci_core_vnic.server[server_key].public_ip_address
          name     = server.hosts.external
          proxied  = false
          type     = "A"
          wildcard = true
          zone     = local.defaults.domains.external
        }
        "${local.defaults.domains.external}-${server_key}-aaaa" = {
          content  = one(data.oci_core_vnic.server[server_key].ipv6addresses)
          name     = server.hosts.external
          proxied  = false
          type     = "AAAA"
          wildcard = true
          zone     = local.defaults.domains.external
        }
      } : {},
      server.hosts.public != null ? {
        "${local.defaults.domains.external}-${server_key}-cname" = {
          content  = server.hosts.public
          name     = server.hosts.external
          proxied  = false
          type     = "CNAME"
          wildcard = true
          zone     = local.defaults.domains.external
        }
      } : {},
      try(local.tailscale_device_addresses[server_key].ipv4, "") != "" ? {
        "${local.defaults.domains.internal}-${server_key}-a" = {
          content  = local.tailscale_device_addresses[server_key].ipv4
          name     = server.hosts.internal
          proxied  = false
          type     = "A"
          wildcard = true
          zone     = local.defaults.domains.internal
        }
      } : {},
      try(local.tailscale_device_addresses[server_key].ipv6, "") != "" ? {
        "${local.defaults.domains.internal}-${server_key}-aaaa" = {
          content  = local.tailscale_device_addresses[server_key].ipv6
          name     = server.hosts.internal
          proxied  = false
          type     = "AAAA"
          wildcard = true
          zone     = local.defaults.domains.internal
        }
      } : {},
    )
  ]...)

  # Server-owned routes resolve according to their exposure method.
  dns_render_records_servers_routing = merge(flatten([
    for server_key, server in local.servers_model : [
      for route in server.routing.urls : {
        "${server_key}-route-${route.id}" = {
          content = (
            route.expose == "cloudflare"
            ? "${local.servers[server_key].runtime.attributes.cloudflare_tunnel_id}.cfargotunnel.com"
            : startswith(route.expose, "proxy-")
            ? try(local.servers_model[trimprefix(route.expose, "proxy-")].hosts.external, null)
            : route.expose == "external"
            ? server.hosts.external
            : server.hosts.internal
          )
          name    = route.url
          proxied = route.expose == "cloudflare"
          type    = "CNAME"
          zone    = local.dns_model_managed_zones_by_url[route.url]
        }
      }
      if local.dns_model_managed_zones_by_url[route.url] != null
    ]
  ])...)

  # Custom service URLs resolve to the tunnel when Cloudflare-exposed.
  dns_render_records_services = merge(flatten([
    for service_key, service in local.services_model : [
      for route in service.routing.urls : {
        "${service_key}-url-${route.id}" = {
          name    = route.url
          proxied = route.expose == "cloudflare"
          type    = "CNAME"
          zone    = local.dns_model_managed_zones_by_url[route.url]

          content = (
            route.expose == "cloudflare" &&
            local.servers_model[service.target].features.cloudflared
            ? "${local.servers[service.target].runtime.attributes.cloudflare_tunnel_id}.cfargotunnel.com"
            : route.proxy_server != null
            ? local.servers_model[route.proxy_server].hosts.external
            : route.dns_target_host
          )
        }
      }
      if(
        route.url != null &&
        local.dns_model_managed_zones_by_url[route.url] != null
      )
    ]
    if try(local.servers_model[service.target], null) != null
  ])...)

  # Fly's fly.dev hostnames are served directly by Fly; only custom URLs need DNS.
  dns_render_records_services_fly = merge(flatten([
    for service_key, service in local.services_model : [
      for route in service.routing.urls : {
        "${service_key}-url-${route.id}" = {
          content = "${service.fly.app_name}.fly.dev"
          name    = route.url
          proxied = route.expose == "cloudflare"
          type    = "CNAME"
          zone    = local.dns_model_managed_zones_by_url[route.url]
        }
      }
      if(
        route.url != null &&
        local.dns_model_managed_zones_by_url[route.url] != null
      )
    ]
    if service.target == "fly"
  ])...)

  # Delegate DNS-01 challenges to the ACME zone. Fly handles its own certs.
  dns_render_records_tls_delegation = {
    for record in distinct([
      for source_record in concat(
        values(local.dns_render_records_manual),
        values(local.dns_render_records_servers),
        values(local.dns_render_records_servers_routing),
        values(local.dns_render_records_services)
        ) : {
        name = source_record.name
        zone = source_record.zone
      }
      if contains(["A", "AAAA", "CNAME"], source_record.type)
      ]) : "${record.zone}-${record.name}-acme-delegation" => {
      content = "${record.name}.${local.defaults.domains.acme}"
      name    = "_acme-challenge.${record.name}"
      type    = "CNAME"
      zone    = record.zone
    }
  }

  # Wildcards follow eligible generated records unless wildcard = false.
  dns_render_records_wildcards = {
    for hostname in distinct([
      for record in concat(
        values(local.dns_render_records_manual),
        values(local.dns_render_records_servers),
        ) : {
        name    = record.name
        proxied = record.proxied
        zone    = record.zone
      }
      if(
        contains(["A", "AAAA", "CNAME"], record.type) &&
        record.wildcard
      )
      ]) : "${hostname.zone}-${hostname.name}-wildcard" => {
      content = hostname.name
      name    = "*.${hostname.name}"
      proxied = hostname.proxied
      type    = "CNAME"
      zone    = hostname.zone
    }
  }

  # Stage output; kept last so dependencies read top to bottom.
  dns_render_records = {
    for key, record in merge(
      local.dns_render_records_manual,
      local.dns_render_records_servers,
      local.dns_render_records_servers_routing,
      local.dns_render_records_services_fly,
      local.dns_render_records_services,
      local.dns_render_records_tls_delegation,
      local.dns_render_records_wildcards,
    ) : key => merge(local.defaults.dns, record)
  }
}
