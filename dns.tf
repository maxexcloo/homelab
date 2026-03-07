locals {
  _dns_services_url_zone = {
    for key, service in local.services : key => (
      service.url == null ?
      null :
      try(
        split(
          reverse(sort([
            for zone_name in local.dns_zones : format("%04d:%s", length(zone_name), zone_name)
            if endswith(service.url, zone_name)
          ]))[0],
          ":"
        )[1],
        null
      )
    )
  }

  dns_records_acme_delegation = {
    for zone in [local.defaults.domain_external, local.defaults.domain_internal] : "${zone}-acme-delegation" => {
      content = "${zone}.${local.defaults.domain_acme}"
      name    = "_acme-challenge"
      type    = "CNAME"
      zone    = zone
    }
  }

  dns_records_manual = merge([
    for zone, records in local.dns : {
      for index, record in records : "${zone}-manual-${record.type}-${index}" => {
        content  = record.content
        name     = record.name == "@" ? zone : "${record.name}.${zone}"
        priority = try(record.priority, null)
        proxied  = record.proxied
        ttl      = record.ttl
        type     = record.type
        wildcard = record.wildcard
        zone     = zone
      }
    }
  ]...)

  dns_records_servers = merge(
    {
      for key, server in local._servers : "${local.defaults.domain_external}-${key}-cname" => {
        content = server.public_address
        name    = "${server.fqdn}.${local.defaults.domain_external}"
        server  = key
        type    = "CNAME"
        zone    = local.defaults.domain_external
      }
      if server.public_address != null
    },
    {
      for key, server in local._servers : "${local.defaults.domain_external}-${key}-a" => {
        content = server.public_ipv4
        name    = "${server.fqdn}.${local.defaults.domain_external}"
        server  = key
        type    = "A"
        zone    = local.defaults.domain_external
      }
      if server.public_ipv4 != null && can(cidrhost("${server.public_ipv4}/32", 0))
    },
    {
      for key, server in local._servers : "${local.defaults.domain_external}-${key}-aaaa" => {
        content = server.public_ipv6
        name    = "${server.fqdn}.${local.defaults.domain_external}"
        server  = key
        type    = "AAAA"
        zone    = local.defaults.domain_external
      }
      if server.public_ipv6 != null && can(cidrhost("${server.public_ipv6}/128", 0))
    },
    {
      for key, server in local._servers : "${local.defaults.domain_internal}-${key}-a" => {
        content = local.servers[key].tailscale_ipv4
        name    = "${server.fqdn}.${local.defaults.domain_internal}"
        server  = key
        type    = "A"
        zone    = local.defaults.domain_internal
      }
      if local.servers[key].tailscale_ipv4 != null
    },
    {
      for key, server in local._servers : "${local.defaults.domain_internal}-${key}-aaaa" => {
        content = local.servers[key].tailscale_ipv6
        name    = "${server.fqdn}.${local.defaults.domain_internal}"
        server  = key
        type    = "AAAA"
        zone    = local.defaults.domain_internal
      }
      if local.servers[key].tailscale_ipv6 != null
    }
  )

  dns_records_services = merge([
    for key, service in local.services : (length(service.deployments) == 0 || contains(service.tags, "no_dns")) ? {} : merge(
      {
        for target in service.deployments : "${local.defaults.domain_external}-${key}-${target}" => {
          content = contains(local.servers[target].tags, "proxied") && local.servers[target].enable_cloudflare ? "${cloudflare_zero_trust_tunnel_cloudflared.server[target].id}.cfargotunnel.com" : "${local._servers[target].fqdn}.${local.defaults.domain_external}"
          name    = "${service.name}.${local._servers[target].fqdn}.${local.defaults.domain_external}"
          proxied = contains(local.servers[target].tags, "proxied")
          server  = target
          type    = "CNAME"
          zone    = local.defaults.domain_external
        }
      },
      {
        for target in service.deployments : "${local.defaults.domain_internal}-${key}-${target}" => {
          content = contains(local.servers[target].tags, "proxied") && local.servers[target].enable_cloudflare ? "${cloudflare_zero_trust_tunnel_cloudflared.server[target].id}.cfargotunnel.com" : "${local._servers[target].fqdn}.${local.defaults.domain_internal}"
          name    = "${service.name}.${local._servers[target].fqdn}.${local.defaults.domain_internal}"
          proxied = contains(local.servers[target].tags, "proxied")
          server  = target
          type    = "CNAME"
          zone    = local.defaults.domain_internal
        }
      }
    )
  ]...)

  dns_records_services_urls = {
    for key, service in local.services : "${key}-url" => {
      name    = service.url
      proxied = contains(local.servers[service.deployments[0]].tags, "proxied")
      server  = service.deployments[0]
      type    = "CNAME"
      zone    = local._dns_services_url_zone[key]

      content = (
        contains(local.servers[service.deployments[0]].tags, "proxied") && local.servers[service.deployments[0]].enable_cloudflare ?
        "${cloudflare_zero_trust_tunnel_cloudflared.server[service.deployments[0]].id}.cfargotunnel.com" :
        "${service.name}.${local._servers[service.deployments[0]].fqdn}.${contains(local.services[key].tags, "external") ? local.defaults.domain_external : local.defaults.domain_internal}"
      )
    }
    if service.url != null && length(service.deployments) == 1 && local._dns_services_url_zone[key] != null
  }

  dns_records_wildcards = {
    for key, group in {
      for candidate in [
        for record in concat(
          values(local.dns_records_servers),
          values(local.dns_records_manual),
          values(local.dns_records_services),
          values(local.dns_records_services_urls)
        ) : record
        if contains(["A", "AAAA", "CNAME"], record.type) && try(record.wildcard, true)
      ] : "${candidate.zone}-${candidate.name}" => candidate...
      } : "${group[0].name}-wildcard" => {
      content = group[0].name
      name    = "*.${group[0].name}"
      type    = "CNAME"
      zone    = group[0].zone
    }
  }

  dns_zones = keys(local.dns)
}
