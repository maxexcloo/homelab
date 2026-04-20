locals {
  # Delegate ACME challenges for every generated hostname back to the dedicated
  # ACME zone, so one scoped Cloudflare token can satisfy DNS-01 clients.
  dns_records_acme_delegation = {
    for record in distinct([
      for r in concat(
        values(local.dns_records_manual),
        values(local.dns_records_servers),
        values(local.dns_records_services_urls)
        ) : {
        name = r.name
        zone = r.zone
      }
      if contains(["A", "AAAA", "CNAME"], r.type)
      ]) : "${record.zone}-${record.name}-acme-delegation" => {
      content = "${record.name}.${local.defaults.domains.acme}"
      name    = "_acme-challenge.${record.name}"
      type    = "CNAME"
      zone    = record.zone
    }
  }

  # Manual DNS records are keyed by either explicit id or stable record fields to
  # avoid identity churn when records are reordered in YAML.
  dns_records_manual = merge([
    for zone, records in local.dns : {
      for record in records : "${zone}-manual-${try(record.id, join("-", compact([record.type, replace(record.name, "@", "apex"), tostring(try(record.priority, ""))])))}" => provider::deepmerge::mergo(
        local.dns_defaults,
        merge(
          record,
          {
            name = record.name == "@" ? zone : "${record.name}.${zone}"
            zone = zone
          },
        )
      )
    }
  ]...)

  # Server records combine explicit public addresses, OCI-assigned addresses, and
  # Tailscale device lookups into external/internal DNS records.
  dns_records_servers = merge([
    for k, server in local.servers_desired : merge(
      server.public_address != null ? {
        "${local.defaults.domains.external}-${k}-cname" = {
          content = server.public_address
          name    = "${server.fqdn}.${local.defaults.domains.external}"
          proxied = server.features.cloudflare_proxy
          type    = "CNAME"
          zone    = local.defaults.domains.external
        }
      } : {},
      server.platform == "oci" ? {
        "${local.defaults.domains.external}-${k}-a" = {
          content = data.oci_core_vnic.server[k].public_ip_address
          name    = "${server.fqdn}.${local.defaults.domains.external}"
          proxied = server.features.cloudflare_proxy
          type    = "A"
          zone    = local.defaults.domains.external
        }
        "${local.defaults.domains.external}-${k}-aaaa" = {
          content = data.oci_core_vnic.server[k].ipv6addresses[0]
          name    = "${server.fqdn}.${local.defaults.domains.external}"
          proxied = server.features.cloudflare_proxy
          type    = "AAAA"
          zone    = local.defaults.domains.external
        }
      } : {},
      server.public_ipv4 != null && server.platform != "oci" ? {
        "${local.defaults.domains.external}-${k}-a" = {
          content = server.public_ipv4
          name    = "${server.fqdn}.${local.defaults.domains.external}"
          proxied = server.features.cloudflare_proxy
          type    = "A"
          zone    = local.defaults.domains.external
        }
      } : {},
      server.public_ipv6 != null && server.platform != "oci" ? {
        "${local.defaults.domains.external}-${k}-aaaa" = {
          content = server.public_ipv6
          name    = "${server.fqdn}.${local.defaults.domains.external}"
          proxied = server.features.cloudflare_proxy
          type    = "AAAA"
          zone    = local.defaults.domains.external
        }
      } : {},
      local.servers_runtime[k].tailscale_ipv4 != null ? {
        "${local.defaults.domains.internal}-${k}-a" = {
          content = local.servers_runtime[k].tailscale_ipv4
          name    = "${server.fqdn}.${local.defaults.domains.internal}"
          proxied = false
          type    = "A"
          zone    = local.defaults.domains.internal
        }
      } : {},
      local.servers_runtime[k].tailscale_ipv6 != null ? {
        "${local.defaults.domains.internal}-${k}-aaaa" = {
          content = local.servers_runtime[k].tailscale_ipv6
          name    = "${server.fqdn}.${local.defaults.domains.internal}"
          proxied = false
          type    = "AAAA"
          zone    = local.defaults.domains.internal
        }
      } : {}
    )
  ]...)

  # Server-hosted Cloudflare services point at the target server's tunnel.
  dns_records_services = {
    for k, service in local.services_desired : "${local.defaults.domains.external}-${k}" => provider::deepmerge::mergo(
      local.dns_defaults,
      {
        content = "${cloudflare_zero_trust_tunnel_cloudflared.server[service.target].id}.cfargotunnel.com"
        name    = service.fqdn_external
        proxied = true
        type    = "CNAME"
        zone    = local.defaults.domains.external
      }
    )
    if contains(keys(local.servers_desired), service.target) &&
    local.servers_desired[service.target].features.cloudflare_zero_trust_tunnel &&
    service.networking.expose == "cloudflare"
  }

  # Fly services get records for custom URLs; fly.dev hostnames are exposed as
  # computed service FQDNs and served directly by Fly.
  dns_records_services_fly = merge(flatten([
    for k, service in local.fly_services : [
      for i, url in service.networking.urls : {
        "${k}-url-${i}" = provider::deepmerge::mergo(
          local.dns_defaults,
          {
            content = "${service.platform_config.fly.app_name}.fly.dev"
            name    = url
            proxied = service.networking.expose == "cloudflare"
            type    = "CNAME"
            zone    = local.dns_zones_urls[url]
          }
        )
      }
      if local.dns_zones_urls[url] != null
    ]
  ])...)

  # Custom service URLs resolve to a tunnel when exposed through Cloudflare,
  # otherwise to the service's computed external or internal hostname.
  dns_records_services_urls = merge(flatten([
    for k, service in local.services_desired : [
      for i, url in service.networking.urls : {
        "${k}-url-${i}" = provider::deepmerge::mergo(
          local.dns_defaults,
          {
            content = (
              local.servers_desired[service.target].features.cloudflare_zero_trust_tunnel && service.networking.expose == "cloudflare" ?
              "${cloudflare_zero_trust_tunnel_cloudflared.server[service.target].id}.cfargotunnel.com" :
              service.fqdn_external != null ? service.fqdn_external : service.fqdn_internal
            )
            name    = url
            proxied = service.networking.expose == "cloudflare"
            type    = "CNAME"
            zone    = local.dns_zones_urls[url]
          }
        )
      }
      if local.dns_zones_urls[url] != null
    ]
    if contains(keys(local.servers_desired), service.target)
  ])...)

  # Wildcards follow each eligible A/AAAA/CNAME record unless the source record
  # explicitly opts out through wildcard = false.
  dns_records_wildcards = {
    for hostname in distinct([
      for record in concat(
        values(local.dns_records_manual),
        values(local.dns_records_servers),
        values(local.dns_records_services),
        values(local.dns_records_services_fly),
        values(local.dns_records_services_urls)
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

  # Managed Cloudflare zone names available for manual and generated records.
  dns_zones = keys(local.dns)

  # Pick the longest managed zone suffix for each custom URL, so nested domains
  # choose the most specific Cloudflare zone.
  dns_zones_urls = {
    for url in distinct(flatten([
      for k, service in local.services_desired : service.networking.urls
      ])) : url => try(
      split(":", reverse(sort([for z in local.dns_zones : format("%04d:%s", length(z), z) if url == z || endswith(url, ".${z}")]))[0])[1],
      null
    )
  }
}
