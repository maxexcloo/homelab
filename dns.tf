locals {
  dns_records_acme_delegation = {
    for record in distinct([
      for r in concat(
        values(local.dns_records_manual),
        values(local.dns_records_servers),
        values(local.dns_records_services),
        values(local.dns_records_services_urls)
        ) : {
        name = r.name
        zone = r.zone
      }
      if contains(["A", "AAAA", "CNAME"], r.type)
      ]) : "${record.zone}-${record.name}-acme-delegation" => {
      content = "${record.name}.${local.defaults.domain_acme}"
      name    = "_acme-challenge.${record.name}"
      type    = "CNAME"
      zone    = record.zone
    }
  }

  dns_records_manual = merge([
    for zone, records in local.dns : {
      for record in records : "${zone}-manual-${record.type}-${substr(sha256(jsonencode(record)), 0, 8)}" => merge(
        var.dns_defaults,
        record,
        {
          name = record.name == "@" ? zone : "${record.name}.${zone}"
          zone = zone
        },
      )
    }
  ]...)

  dns_records_servers = merge([
    for k, server in local.servers : merge(
      server.public_address != null ? {
        "${local.defaults.domain_external}-${k}-cname" = {
          content = server.public_address
          name    = "${server.fqdn}.${local.defaults.domain_external}"
          server  = k
          type    = "CNAME"
          zone    = local.defaults.domain_external
        }
      } : {},
      server.platform == "oci" ? {
        "${local.defaults.domain_external}-${k}-a" = {
          content = data.oci_core_vnic.server[k].public_ip_address
          name    = "${server.fqdn}.${local.defaults.domain_external}"
          server  = k
          type    = "A"
          zone    = local.defaults.domain_external
        }
        "${local.defaults.domain_external}-${k}-aaaa" = {
          content = data.oci_core_vnic.server[k].ipv6addresses[0]
          name    = "${server.fqdn}.${local.defaults.domain_external}"
          server  = k
          type    = "AAAA"
          zone    = local.defaults.domain_external
        }
      } : {},
      server.public_ipv4 != null && server.platform != "oci" ? {
        "${local.defaults.domain_external}-${k}-a" = {
          content = server.public_ipv4
          name    = "${server.fqdn}.${local.defaults.domain_external}"
          server  = k
          type    = "A"
          zone    = local.defaults.domain_external
        }
      } : {},
      server.public_ipv6 != null && server.platform != "oci" ? {
        "${local.defaults.domain_external}-${k}-aaaa" = {
          content = server.public_ipv6
          name    = "${server.fqdn}.${local.defaults.domain_external}"
          server  = k
          type    = "AAAA"
          zone    = local.defaults.domain_external
        }
      } : {},
      server.tailscale_ipv4 != null ? {
        "${local.defaults.domain_internal}-${k}-a" = {
          content = server.tailscale_ipv4
          name    = "${server.fqdn}.${local.defaults.domain_internal}"
          server  = k
          type    = "A"
          zone    = local.defaults.domain_internal
        }
      } : {},
      server.tailscale_ipv6 != null ? {
        "${local.defaults.domain_internal}-${k}-aaaa" = {
          content = server.tailscale_ipv6
          name    = "${server.fqdn}.${local.defaults.domain_internal}"
          server  = k
          type    = "AAAA"
          zone    = local.defaults.domain_internal
        }
      } : {}
    )
  ]...)

  dns_records_services = merge([
    for zone in [local.defaults.domain_external, local.defaults.domain_internal] : {
      for k, service in local.services : "${zone}-${k}" => merge(
        var.dns_defaults,
        {
          content = local.servers[service.server].enable_cloudflare_proxy && local.servers[service.server].enable_cloudflare_zero_trust_tunnel ? "${cloudflare_zero_trust_tunnel_cloudflared.server[service.server].id}.cfargotunnel.com" : "${local.servers[service.server].fqdn}.${zone}"
          name    = "${service.name}.${local.servers[service.server].fqdn}.${zone}"
          proxied = local.servers[service.server].enable_cloudflare_proxy
          type    = "CNAME"
          zone    = zone
        }
      )
    }
  ]...)

  dns_records_services_urls = merge(
    flatten([
      for k, service in local.services : [
        for i, url in(service.urls != null ? service.urls : []) : {
          "${k}-url-${i}" = merge(
            var.dns_defaults,
            {
              name    = url
              proxied = local.servers[service.server].enable_cloudflare_proxy
              server  = service.server
              type    = "CNAME"

              content = (
                local.servers[service.server].enable_cloudflare_proxy && local.servers[service.server].enable_cloudflare_zero_trust_tunnel ?
                "${cloudflare_zero_trust_tunnel_cloudflared.server[service.server].id}.cfargotunnel.com" :
                "${service.name}.${local.servers[service.server].fqdn}.${local.defaults.domain_internal}"
              )

              zone = try(
                split(":", reverse(sort([for z in local.dns_zones : format("%04d:%s", length(z), z) if endswith(url, z)]))[0])[1],
                null
              )
            }
          )
        }
        if length([for z in local.dns_zones : z if endswith(url, z)]) > 0
      ]
    ])
  ...)

  dns_records_wildcards = {
    for hostname in distinct([
      for record in concat(
        values(local.dns_records_servers),
        values(local.dns_records_manual),
        values(local.dns_records_services),
        values(local.dns_records_services_urls)
        ) : {
        name = record.name
        zone = record.zone
      }
      if contains(["A", "AAAA", "CNAME"], record.type) && try(record.wildcard, true)
      ]) : "${hostname.zone}-${hostname.name}-wildcard" => {
      content = hostname.name
      name    = "*.${hostname.name}"
      type    = "CNAME"
      zone    = hostname.zone
    }
  }

  dns_zones = keys(local.dns)
}
