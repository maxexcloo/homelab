locals {
  # Per-record key generation for manual records. Records may declare an
  # explicit `id`; otherwise a stable type-name-priority triplet is used.
  _dns_render_records_manual_input = flatten([
    for zone, records in local.dns_input : [
      for record in records : {
        record = record
        zone   = zone
        key = try(record.id, join("-", compact([
          record.type,
          replace(record.name, "@", "apex"),
          tostring(try(record.priority, "")),
        ])))
      }
    ]
  ])

  # For each custom URL, find all managed zones that match (exact or suffix).
  # The most specific (longest) zone wins so nested domains resolve correctly.
  _dns_render_zones_matching = {
    for url in distinct(flatten([
      for service_key, service in local.services_input_targets : service.routing.urls
      ])) : url => [
      for zone in local.dns_input_zones : {
        length = length(zone)
        name   = zone
      }
      if url == zone || endswith(url, ".${zone}")
    ]
  }

  # Delegate ACME challenges for managed server and server-hosted service
  # hostnames back to the dedicated ACME zone. Fly services are intentionally
  # excluded: Fly provisions TLS certificates via its own ACME implementation
  # and does not need external DNS-01 challenge delegation.
  dns_render_records_acme_delegation = {
    for record in distinct([
      for source_record in concat(
        values(local.dns_render_records_manual),
        values(local.dns_render_records_servers),
        values(local.dns_render_records_services),
        values(local.dns_render_records_services_urls)
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

  # Combined map of all DNS records for a single cloudflare_dns_record resource.
  # defaults_dns is applied at this layer so every record has a complete shape.
  dns_render_records_all = {
    for key, record in merge(
      local.dns_render_records_acme_delegation,
      local.dns_render_records_manual,
      local.dns_render_records_servers,
      local.dns_render_records_services,
      local.dns_render_records_services_fly,
      local.dns_render_records_services_urls,
      local.dns_render_records_wildcards,
    ) : key => merge(local.defaults.dns, record)
  }

  # Manual DNS records are keyed by either explicit id or stable record fields to
  # avoid identity churn when records are reordered in YAML.
  dns_render_records_manual = {
    for entry in local._dns_render_records_manual_input :
    "${entry.zone}-manual-${entry.key}" => merge(local.defaults.dns, entry.record, {
      name = entry.record.name == "@" ? entry.zone : "${entry.record.name}.${entry.zone}"
      zone = entry.zone
    })
  }

  # Server records combine explicit public addresses, OCI-assigned addresses, and
  # Tailscale device lookups into external/internal DNS records.
  dns_render_records_servers = merge([
    for server_key, server in local.servers_model : merge(
      server.public_address != null ? {
        "${local.defaults.domains.external}-${server_key}-cname" = {
          content = server.public_address
          name    = server.fqdn_external
          proxied = server.features.cloudflare_proxy
          type    = "CNAME"
          zone    = local.defaults.domains.external
        }
      } : {},
      server.platform == "oci" ? {
        "${local.defaults.domains.external}-${server_key}-a" = {
          content = data.oci_core_vnic.server[server_key].public_ip_address
          name    = server.fqdn_external
          proxied = server.features.cloudflare_proxy
          type    = "A"
          zone    = local.defaults.domains.external
        }
        "${local.defaults.domains.external}-${server_key}-aaaa" = {
          content = data.oci_core_vnic.server[server_key].ipv6addresses[0]
          name    = server.fqdn_external
          proxied = server.features.cloudflare_proxy
          type    = "AAAA"
          zone    = local.defaults.domains.external
        }
      } : {},
      server.public_ipv4 != null && server.platform != "oci" ? {
        "${local.defaults.domains.external}-${server_key}-a" = {
          content = server.public_ipv4
          name    = server.fqdn_external
          proxied = server.features.cloudflare_proxy
          type    = "A"
          zone    = local.defaults.domains.external
        }
      } : {},
      server.public_ipv6 != null && server.platform != "oci" ? {
        "${local.defaults.domains.external}-${server_key}-aaaa" = {
          content = server.public_ipv6
          name    = server.fqdn_external
          proxied = server.features.cloudflare_proxy
          type    = "AAAA"
          zone    = local.defaults.domains.external
        }
      } : {},
      local.servers[server_key].state.urls.tailscale_ipv4 != null ? {
        "${local.defaults.domains.internal}-${server_key}-a" = {
          content = local.servers[server_key].state.urls.tailscale_ipv4
          name    = server.fqdn_internal
          proxied = false
          type    = "A"
          zone    = local.defaults.domains.internal
        }
      } : {},
      local.servers[server_key].state.urls.tailscale_ipv6 != null ? {
        "${local.defaults.domains.internal}-${server_key}-aaaa" = {
          content = local.servers[server_key].state.urls.tailscale_ipv6
          name    = server.fqdn_internal
          proxied = false
          type    = "AAAA"
          zone    = local.defaults.domains.internal
        }
      } : {}
    )
  ]...)

  # Server-hosted Cloudflare services point at the target server's tunnel.
  # Skipped when the service already has managed routing.urls that cover external
  # access: deep fqdn_external subdomains exceed Cloudflare Universal SSL coverage
  # (one wildcard level), so custom short-form URLs are the canonical entry point.
  dns_render_records_services = {
    for service_key, service in local.services_model :
    "${local.defaults.domains.external}-${service_key}" => {
      content  = "${local.servers[service.target].state.fields.cloudflare_tunnel_id}.cfargotunnel.com"
      name     = service.fqdn_external
      proxied  = true
      type     = "CNAME"
      wildcard = false
      zone     = local.defaults.domains.external
    }
    if contains(local.servers_input_keys, service.target) &&
    local.servers_model[service.target].features.cloudflare_zero_trust_tunnel &&
    service.routing.expose == "cloudflare" &&
    length(compact([for url in service.routing.urls : lookup(local.dns_render_zones_urls, url, null)])) == 0
  }

  # Fly services get records for custom URLs; fly.dev hostnames are exposed as
  # computed service FQDNs and served directly by Fly.
  dns_render_records_services_fly = merge(flatten([
    for service_key, service in local.services_model : [
      for url_index, url in service.routing.urls : {
        "${service_key}-url-${url_index}" = {
          content  = "${service.fly.app_name}.fly.dev"
          name     = url
          proxied  = service.routing.expose == "cloudflare"
          type     = "CNAME"
          wildcard = false
          zone     = local.dns_render_zones_urls[url]
        }
      }
      if local.dns_render_zones_urls[url] != null
    ]
    if service.target == "fly"
  ])...)

  # Custom service URLs resolve to a tunnel when exposed through Cloudflare,
  # otherwise to the service's computed external or internal hostname.
  dns_render_records_services_urls = merge(flatten([
    for service_key, service in local.services_model : [
      for url_index, url in service.routing.urls : {
        "${service_key}-url-${url_index}" = {
          name     = url
          proxied  = service.routing.expose == "cloudflare"
          type     = "CNAME"
          wildcard = false
          zone     = local.dns_render_zones_urls[url]

          content = (
            local.servers_model[service.target].features.cloudflare_zero_trust_tunnel
            && service.routing.expose == "cloudflare"
            ? "${local.servers[service.target].state.fields.cloudflare_tunnel_id}.cfargotunnel.com"
            : coalesce(service.fqdn_external, service.fqdn_internal)
          )
        }
      }
      if local.dns_render_zones_urls[url] != null
    ]
    if contains(local.servers_input_keys, service.target)
  ])...)

  # Wildcards follow each eligible A/AAAA/CNAME record unless the source record
  # explicitly opts out through wildcard = false.
  dns_render_records_wildcards = {
    for hostname in distinct([
      for record in concat(
        values(local.dns_render_records_manual),
        values(local.dns_render_records_servers),
        values(local.dns_render_records_services),
        values(local.dns_render_records_services_fly),
        values(local.dns_render_records_services_urls)
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

  dns_render_zones_urls = {
    for url, matches in local._dns_render_zones_matching : url => try(
      [for match in matches : match.name if match.length == max([for candidate in matches : candidate.length]...)][0],
      null
    )
  }
}
