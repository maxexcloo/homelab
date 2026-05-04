locals {
  # DNS records are generated across seven categories and merged into a single
  # cloudflare_dns_record resource keyed by a stable, collision-safe identifier.
  #
  # Categories (each is a map of key => record object):
  #   manual          — records from data/dns/*.yml (e.g. MX, TXT, CNAME)
  #   servers         — A/AAAA/CNAME for server public IPs (e.g. hsp.au.excloo.net)
  #   services        — CNAME → tunnel for cloudflare-exposed services
  #   services_fly    — CNAME → fly.dev for Fly.io deployments
  #   services_urls   — CNAME for custom service URLs (e.g. reddit.excloo.com)
  #   acme_delegation — _acme-challenge CNAMEs for all A/AAAA/CNAME records
  #   wildcards       — *.hostname CNAMEs for eligible records
  #
  # Final DNS input map: zone name -> list of manually declared records.
  dns_input = {
    for dns_file in [
      for file_path in fileset(path.module, "data/dns/*.yml") :
      yamldecode(file("${path.module}/${file_path}"))
    ] : dns_file.name => try(dns_file.records, [])
  }

  # Delegate ACME challenges for managed server and server-hosted service
  # hostnames back to the dedicated ACME zone.
  dns_records_acme_delegation = {
    for record in distinct([
      for source_record in concat(
        values(local.dns_records_manual),
        values(local.dns_records_servers),
        values(local.dns_records_services),
        values(local.dns_records_services_urls)
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
  dns_records_all = merge(
    local.dns_records_acme_delegation,
    local.dns_records_manual,
    local.dns_records_servers,
    local.dns_records_services,
    local.dns_records_services_fly,
    local.dns_records_services_urls,
    local.dns_records_wildcards,
  )

  # Manual DNS records are keyed by either explicit id or stable record fields to
  # avoid identity churn when records are reordered in YAML.
  dns_records_manual = merge([
    for zone, records in local.dns_input : {
      for record in records : (
        "${zone}-manual-${try(record.id, join("-", compact([record.type, replace(record.name, "@", "apex"), tostring(try(record.priority, ""))])))}"
        ) => provider::deepmerge::mergo(
        local.defaults_dns,
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
    for server_key, server in local.servers_model_desired : merge(
      server.public_address != null ? {
        "${local.defaults.domains.external}-${server_key}-cname" = {
          content = server.public_address
          name    = "${server.fqdn}.${local.defaults.domains.external}"
          proxied = server.features.cloudflare_proxy
          type    = "CNAME"
          zone    = local.defaults.domains.external
        }
      } : {},
      server.platform == "oci" ? {
        "${local.defaults.domains.external}-${server_key}-a" = {
          content = data.oci_core_vnic.server[server_key].public_ip_address
          name    = "${server.fqdn}.${local.defaults.domains.external}"
          proxied = server.features.cloudflare_proxy
          type    = "A"
          zone    = local.defaults.domains.external
        }
        "${local.defaults.domains.external}-${server_key}-aaaa" = {
          content = data.oci_core_vnic.server[server_key].ipv6addresses[0]
          name    = "${server.fqdn}.${local.defaults.domains.external}"
          proxied = server.features.cloudflare_proxy
          type    = "AAAA"
          zone    = local.defaults.domains.external
        }
      } : {},
      server.public_ipv4 != null && server.platform != "oci" ? {
        "${local.defaults.domains.external}-${server_key}-a" = {
          content = server.public_ipv4
          name    = "${server.fqdn}.${local.defaults.domains.external}"
          proxied = server.features.cloudflare_proxy
          type    = "A"
          zone    = local.defaults.domains.external
        }
      } : {},
      server.public_ipv6 != null && server.platform != "oci" ? {
        "${local.defaults.domains.external}-${server_key}-aaaa" = {
          content = server.public_ipv6
          name    = "${server.fqdn}.${local.defaults.domains.external}"
          proxied = server.features.cloudflare_proxy
          type    = "AAAA"
          zone    = local.defaults.domains.external
        }
      } : {},
      local.servers_model_runtime[server_key].tailscale_ipv4 != null ? {
        "${local.defaults.domains.internal}-${server_key}-a" = {
          content = local.servers_model_runtime[server_key].tailscale_ipv4
          name    = "${server.fqdn}.${local.defaults.domains.internal}"
          proxied = false
          type    = "A"
          zone    = local.defaults.domains.internal
        }
      } : {},
      local.servers_model_runtime[server_key].tailscale_ipv6 != null ? {
        "${local.defaults.domains.internal}-${server_key}-aaaa" = {
          content = local.servers_model_runtime[server_key].tailscale_ipv6
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
    for service_key, service in local.services_model_desired : (
      "${local.defaults.domains.external}-${service_key}"
      ) => provider::deepmerge::mergo(
      local.defaults_dns,
      {
        content = "${module.cloudflare_tunnel[service.target].tunnel_id}.cfargotunnel.com"
        name    = service.fqdn_external
        proxied = true
        type    = "CNAME"
        zone    = local.defaults.domains.external
      }
    )
    if(
      contains(local._servers_target_keys, service.target) &&
      local.servers_model_desired[service.target].features.cloudflare_zero_trust_tunnel &&
      service.networking.expose == "cloudflare"
    )
  }

  # Fly services get records for custom URLs; fly.dev hostnames are exposed as
  # computed service FQDNs and served directly by Fly.
  dns_records_services_fly = merge(flatten([
    for service_key, service in local.fly_input_services : [
      for url_index, url in service.networking.urls : {
        "${service_key}-url-${url_index}" = provider::deepmerge::mergo(
          local.defaults_dns,
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
    for service_key, service in local.services_model_desired : [
      for url_index, url in service.networking.urls : {
        "${service_key}-url-${url_index}" = provider::deepmerge::mergo(
          local.defaults_dns,
          {
            content = (
              local.servers_model_desired[service.target].features.cloudflare_zero_trust_tunnel
              && service.networking.expose == "cloudflare"
              ? "${module.cloudflare_tunnel[service.target].tunnel_id}.cfargotunnel.com"
              : service.fqdn_external != null ? service.fqdn_external : service.fqdn_internal
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
    if contains(local._servers_target_keys, service.target)
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
  dns_zones = keys(local.dns_input)

  # Pick the longest managed zone suffix for each custom URL, so nested domains
  # choose the most specific Cloudflare zone.
  #
  # Algorithm: for each zone that matches the URL, build a sortable string
  # "{padded_length}:{zone_name}". Left-padding the length with zeros makes
  # lexical sort equivalent to length sort. Reverse-sorting picks the longest
  # (most specific) zone, then split(":")[1] extracts the zone name.
  dns_zones_urls = {
    for url in distinct(flatten([
      for service_key, service in local.services_model_desired : service.networking.urls
      ])) : url => try(
      split(":", reverse(sort([
        for zone in local.dns_zones : format("%04d:%s", length(zone), zone)
        if url == zone || endswith(url, ".${zone}")
      ]))[0])[1],
      null
    )
  }
}
