locals {
  # Longest matching zone wins for nested domains.
  _dns_render_zones_matching = {
    for url in distinct(flatten([
      for service_key, service in local.services_input_targets : service.routing.urls
      ])) : url => [
      for zone in keys(local.dns_input) : {
        length = length(zone)
        name   = zone
      }
      if url == zone || endswith(url, ".${zone}")
    ]
  }

  dns_render_managed_zones_by_url = {
    for url, matches in local._dns_render_zones_matching : url => try(
      [for match in matches : match.name if match.length == max(matches[*].length...)][0],
      null
    )
  }

  # Manual records are keyed independently from YAML list order.
  dns_render_records_manual = {
    for entry in flatten([
      for zone, records in local.dns_input : [
        for record in records : {
          key    = try(record.id, join("-", compact([record.type, replace(record.name, "@", "apex"), tostring(try(record.priority, ""))])))
          record = record
          zone   = zone
        }
      ]
      ]) : "${entry.zone}-manual-${entry.key}" => merge(
      local.defaults.dns,
      entry.record,
      {
        name = entry.record.name == "@" ? entry.zone : "${entry.record.name}.${entry.zone}"
        zone = entry.zone
      },
    )
  }

  dns_render_records_servers = merge([
    for server_key, server in local.servers_model : merge(
      server.addresses.public_ipv4 != null && server.platform != "oci" ? {
        "${local.defaults.domains.external}-${server_key}-a" = {
          content = server.addresses.public_ipv4
          name    = server.hosts.external
          proxied = false
          type    = "A"
          zone    = local.defaults.domains.external
        }
      } : {},
      server.addresses.public_ipv6 != null && server.platform != "oci" ? {
        "${local.defaults.domains.external}-${server_key}-aaaa" = {
          content = server.addresses.public_ipv6
          name    = server.hosts.external
          proxied = false
          type    = "AAAA"
          zone    = local.defaults.domains.external
        }
      } : {},
      server.platform == "oci" ? {
        "${local.defaults.domains.external}-${server_key}-a" = {
          content = data.oci_core_vnic.server[server_key].public_ip_address
          name    = server.hosts.external
          proxied = false
          type    = "A"
          zone    = local.defaults.domains.external
        }
        "${local.defaults.domains.external}-${server_key}-aaaa" = {
          content = data.oci_core_vnic.server[server_key].ipv6addresses[0]
          name    = server.hosts.external
          proxied = false
          type    = "AAAA"
          zone    = local.defaults.domains.external
        }
      } : {},
      server.hosts.public != null ? {
        "${local.defaults.domains.external}-${server_key}-cname" = {
          content = server.hosts.public
          name    = server.hosts.external
          proxied = false
          type    = "CNAME"
          zone    = local.defaults.domains.external
        }
      } : {},
      local.servers[server_key].runtime.addresses.tailscale_ipv4 != "" ? {
        "${local.defaults.domains.internal}-${server_key}-a" = {
          content = local.servers[server_key].runtime.addresses.tailscale_ipv4
          name    = server.hosts.internal
          proxied = false
          type    = "A"
          zone    = local.defaults.domains.internal
        }
      } : {},
      local.servers[server_key].runtime.addresses.tailscale_ipv6 != "" ? {
        "${local.defaults.domains.internal}-${server_key}-aaaa" = {
          content = local.servers[server_key].runtime.addresses.tailscale_ipv6
          name    = server.hosts.internal
          proxied = false
          type    = "AAAA"
          zone    = local.defaults.domains.internal
        }
      } : {},
    )
  ]...)

  # Custom service URLs resolve to the tunnel when Cloudflare-exposed.
  dns_render_records_services = merge(flatten([
    for service_key, service in local.services_model : [
      for url_index, url in service.routing.urls : {
        "${service_key}-url-${url_index}" = {
          name    = url
          proxied = service.routing.expose == "cloudflare"
          type    = "CNAME"
          zone    = local.dns_render_managed_zones_by_url[url]

          content = (
            local.servers_model[service.target].features.cloudflare_zero_trust_tunnel &&
            service.routing.expose == "cloudflare"
            ? "${local.servers[service.target].runtime.attributes.cloudflare_tunnel_id}.cfargotunnel.com"
            : local.services_model_proxy_server[service_key] != null
            ? local.servers_model[local.services_model_proxy_server[service_key]].hosts.external
            : try(coalesce(try(service.urls.external.host, null), try(service.urls.internal.host, null)), null)
          )
        }
      }
      if local.dns_render_managed_zones_by_url[url] != null
    ]
    if lookup(local.servers_model, service.target, null) != null
  ])...)

  # Fly's fly.dev hostnames are served directly by Fly; only custom URLs need DNS.
  dns_render_records_services_fly = merge(flatten([
    for service_key, service in local.services_model : [
      for url_index, url in service.routing.urls : {
        "${service_key}-url-${url_index}" = {
          content = "${service.fly.app_name}.fly.dev"
          name    = url
          proxied = service.routing.expose == "cloudflare"
          type    = "CNAME"
          zone    = local.dns_render_managed_zones_by_url[url]
        }
      }
      if local.dns_render_managed_zones_by_url[url] != null
    ]
    if service.target == "fly"
  ])...)

  # Delegate DNS-01 challenges to the ACME zone. Fly handles its own certs.
  dns_render_records_tls_delegation = {
    for record in distinct([
      for source_record in concat(
        values(local.dns_render_records_manual),
        values(local.dns_render_records_servers),
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
      if contains(["A", "AAAA", "CNAME"], record.type) && try(record.wildcard, true)
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
      local.dns_render_records_services_fly,
      local.dns_render_records_services,
      local.dns_render_records_tls_delegation,
      local.dns_render_records_wildcards,
    ) : key => merge(local.defaults.dns, record)
  }
}
