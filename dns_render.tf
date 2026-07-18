locals {
  # Manual records are keyed independently from YAML list order.
  _dns_render_records_manual = {
    for record_key, entries in local.dns_model_manual_entries_by_key :
    record_key => merge(
      local.defaults.dns,
      one(entries).record,
      {
        name = one(entries).record.name == "@" ? one(entries).zone : "${one(entries).record.name}.${one(entries).zone}"
        zone = one(entries).zone
      },
    )
  }

  # Provider-neutral routing entries become public CNAMEs only when they have
  # an explicit hostname in a managed zone.
  _dns_render_records_routing = {
    for route_key, route in local.dns_model_routes : route_key => {
      content = route.tunnel != null ? "${local.servers[route.tunnel.server_key].runtime.attributes.cloudflare_tunnel_id}.cfargotunnel.com" : route.dns.content
      name    = route.hostname
      proxied = route.dns.proxied
      type    = "CNAME"
      zone    = route.dns.zone
    }
    if route.dns != null
  }

  _dns_render_records_servers = merge([
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
          content  = oci_core_instance.server[server_key].public_ip
          name     = server.hosts.external
          proxied  = false
          type     = "A"
          wildcard = true
          zone     = local.defaults.domains.external
        }
        "${local.defaults.domains.external}-${server_key}-aaaa" = {
          content  = one(one(oci_core_instance.server[server_key].create_vnic_details).ipv6address_ipv6subnet_cidr_pair_details).ipv6address
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

  # Delegate DNS-01 challenges to the ACME zone. Fly handles its own certs.
  _dns_render_records_tls_delegation = {
    for record in distinct([
      for source_record in concat(
        values(local._dns_render_records_manual),
        [
          for route_key, record in local._dns_render_records_routing : record
          if local.dns_model_routes[route_key].server_key != null
        ],
        values(local._dns_render_records_servers),
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
  _dns_render_records_wildcards = {
    for hostname in distinct([
      for record in concat(
        values(local._dns_render_records_manual),
        values(local._dns_render_records_servers),
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
      local._dns_render_records_manual,
      local._dns_render_records_routing,
      local._dns_render_records_servers,
      local._dns_render_records_tls_delegation,
      local._dns_render_records_wildcards,
    ) : key => merge(local.defaults.dns, record)
  }
}
