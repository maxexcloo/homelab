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

  dns_records_acme = {
    for key, group in {
      for candidate in [
        for record in concat(
          values(local.dns_records_servers),
          values(local.dns_records_services),
          values(local.dns_records_services_urls)
        ) : record
        if contains(["A", "AAAA", "CNAME"], record.type)
      ] : "${candidate.zone}-${candidate.name}-${candidate.server}" => candidate...
      } : "${group[0].name}-acme" => {
      content = nonsensitive(shell_sensitive_script.acme_dns_server[group[0].server].output.fulldomain)
      name    = "_acme-challenge.${group[0].name}"
      type    = "CNAME"
      zone    = group[0].zone
    }
  }

  dns_records_manual = merge([
    for zone, records in var.dns : {
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
      for key, server in local._servers : "${var.defaults.domain_external}-${key}-cname" => {
        content = server.input.public_address
        name    = "${server.fqdn}.${var.defaults.domain_external}"
        server  = key
        type    = "CNAME"
        zone    = var.defaults.domain_external
      }
      if server.input.public_address != null
    },
    {
      for key, server in local._servers : "${var.defaults.domain_external}-${key}-a" => {
        content = server.input.public_ipv4
        name    = "${server.fqdn}.${var.defaults.domain_external}"
        server  = key
        type    = "A"
        zone    = var.defaults.domain_external
      }
      if server.input.public_ipv4 != null && can(cidrhost("${server.input.public_ipv4}/32", 0))
    },
    {
      for key, server in local._servers : "${var.defaults.domain_external}-${key}-aaaa" => {
        content = server.input.public_ipv6
        name    = "${server.fqdn}.${var.defaults.domain_external}"
        server  = key
        type    = "AAAA"
        zone    = var.defaults.domain_external
      }
      if server.input.public_ipv6 != null && can(cidrhost("${server.input.public_ipv6}/128", 0))
    },
    {
      for key, server in local._servers : "${var.defaults.domain_internal}-${key}-a" => {
        content = local.servers[key].output.tailscale_ipv4
        name    = "${server.fqdn}.${var.defaults.domain_internal}"
        server  = key
        type    = "A"
        zone    = var.defaults.domain_internal
      }
      if local.servers[key].output.tailscale_ipv4 != null
    },
    {
      for key, server in local._servers : "${var.defaults.domain_internal}-${key}-aaaa" => {
        content = local.servers[key].output.tailscale_ipv6
        name    = "${server.fqdn}.${var.defaults.domain_internal}"
        server  = key
        type    = "AAAA"
        zone    = var.defaults.domain_internal
      }
      if local.servers[key].output.tailscale_ipv6 != null
    }
  )

  dns_records_services = merge([
    for key, service in local.services : (length(service.deployments) == 0 || contains(service.tags, "no_dns")) ? {} : merge(
      {
        for target in service.deployments : "${var.defaults.domain_external}-${key}-${target}" => {
          content = contains(local.servers[target].tags, "proxied") && local.servers_resources[target].cloudflare ? "${cloudflare_zero_trust_tunnel_cloudflared.server[target].id}.cfargotunnel.com" : "${local._servers[target].fqdn}.${var.defaults.domain_external}"
          name    = "${service.name}.${local._servers[target].fqdn}.${var.defaults.domain_external}"
          proxied = contains(local.servers[target].tags, "proxied")
          server  = target
          type    = "CNAME"
          zone    = var.defaults.domain_external
        }
      },
      {
        for target in service.deployments : "${var.defaults.domain_internal}-${key}-${target}" => {
          content = contains(local.servers[target].tags, "proxied") && local.servers_resources[target].cloudflare ? "${cloudflare_zero_trust_tunnel_cloudflared.server[target].id}.cfargotunnel.com" : "${local._servers[target].fqdn}.${var.defaults.domain_internal}"
          name    = "${service.name}.${local._servers[target].fqdn}.${var.defaults.domain_internal}"
          proxied = contains(local.servers[target].tags, "proxied")
          server  = target
          type    = "CNAME"
          zone    = var.defaults.domain_internal
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
        contains(local.servers[service.deployments[0]].tags, "proxied") && local.servers_resources[service.deployments[0]].cloudflare ?
        "${cloudflare_zero_trust_tunnel_cloudflared.server[service.deployments[0]].id}.cfargotunnel.com" :
        "${service.name}.${local._servers[service.deployments[0]].fqdn}.${contains(local.services[key].tags, "external") ? var.defaults.domain_external : var.defaults.domain_internal}"
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

  dns_zones = keys(var.dns)
}
