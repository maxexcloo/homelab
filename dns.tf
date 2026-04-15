locals {
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

  dns_records_manual = merge([
    for zone, records in local.dns : {
      for record in records : "${zone}-manual-${record.type}-${substr(sha256(jsonencode(record)), 0, 8)}" => provider::deepmerge::mergo(
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

  dns_records_servers = merge([
    for k, server in local.servers : merge(
      server.public_address != null ? {
        "${local.defaults.domains.external}-${k}-cname" = {
          content = server.public_address
          name    = "${server.fqdn}.${local.defaults.domains.external}"
          server  = k
          type    = "CNAME"
          zone    = local.defaults.domains.external
        }
      } : {},
      server.platform == "oci" ? {
        "${local.defaults.domains.external}-${k}-a" = {
          content = data.oci_core_vnic.server[k].public_ip_address
          name    = "${server.fqdn}.${local.defaults.domains.external}"
          server  = k
          type    = "A"
          zone    = local.defaults.domains.external
        }
        "${local.defaults.domains.external}-${k}-aaaa" = {
          content = data.oci_core_vnic.server[k].ipv6addresses[0]
          name    = "${server.fqdn}.${local.defaults.domains.external}"
          server  = k
          type    = "AAAA"
          zone    = local.defaults.domains.external
        }
      } : {},
      server.public_ipv4 != null && server.platform != "oci" ? {
        "${local.defaults.domains.external}-${k}-a" = {
          content = server.public_ipv4
          name    = "${server.fqdn}.${local.defaults.domains.external}"
          server  = k
          type    = "A"
          zone    = local.defaults.domains.external
        }
      } : {},
      server.public_ipv6 != null && server.platform != "oci" ? {
        "${local.defaults.domains.external}-${k}-aaaa" = {
          content = server.public_ipv6
          name    = "${server.fqdn}.${local.defaults.domains.external}"
          server  = k
          type    = "AAAA"
          zone    = local.defaults.domains.external
        }
      } : {},
      server.tailscale_ipv4 != null ? {
        "${local.defaults.domains.internal}-${k}-a" = {
          content = server.tailscale_ipv4
          name    = "${server.fqdn}.${local.defaults.domains.internal}"
          server  = k
          type    = "A"
          zone    = local.defaults.domains.internal
        }
      } : {},
      server.tailscale_ipv6 != null ? {
        "${local.defaults.domains.internal}-${k}-aaaa" = {
          content = server.tailscale_ipv6
          name    = "${server.fqdn}.${local.defaults.domains.internal}"
          server  = k
          type    = "AAAA"
          zone    = local.defaults.domains.internal
        }
      } : {}
    )
  ]...)

  dns_records_services = merge([
    for zone in [local.defaults.domains.external, local.defaults.domains.internal] : {
      for k, service in local.services : "${zone}-${k}" => provider::deepmerge::mergo(
        local.dns_defaults,
        {
          content = "${cloudflare_zero_trust_tunnel_cloudflared.server[service.server].id}.cfargotunnel.com"
          name    = "${service.identity.name}.${local.servers[service.server].fqdn}.${zone}"
          proxied = true
          type    = "CNAME"
          zone    = zone
        }
      )
      if contains(keys(local.servers), service.server) &&
      local.servers[service.server].features.cloudflare_zero_trust_tunnel &&
      service.features.cloudflare_proxy &&
      zone == local.defaults.domains.external
    }
  ]...)

  dns_records_services_urls = merge(
    flatten([
      for k, service in local.services : [
        for i, url in service.networking.urls : {
          "${k}-url-${i}" = provider::deepmerge::mergo(
            local.dns_defaults,
            {
              name    = url
              proxied = local.servers[service.server].features.cloudflare_proxy
              server  = service.server
              type    = "CNAME"

              content = (
                local.servers[service.server].features.cloudflare_zero_trust_tunnel && service.features.cloudflare_proxy ?
                "${cloudflare_zero_trust_tunnel_cloudflared.server[service.server].id}.cfargotunnel.com" :
                "${service.identity.name}.${local.servers[service.server].fqdn}.${local.defaults.domains.internal}"
              )

              zone = try(
                split(":", reverse(sort([for z in local.dns_zones : format("%04d:%s", length(z), z) if endswith(url, z)]))[0])[1],
                null
              )
            }
          )
        }
        if length([for z in local.dns_zones : z if endswith(url, z)]) > 0 && contains(keys(local.servers), service.server)
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
