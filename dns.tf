locals {
  _dns_acme_candidates = [
    for record in concat(
      values(local.dns_records_servers),
      values(local.dns_records_manual),
      values(local.dns_records_services),
      values(local.dns_records_services_urls)
    ) : record
    if contains(["A", "AAAA", "CNAME"], record.type) && try(record.wildcard, true)
  ]

  _dns_acme_groups = {
    for candidate in local._dns_acme_candidates : "${candidate.zone}|${candidate.name}|${try(candidate.server, "")}" => candidate...
    if try(candidate.server, null) != null
  }

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
    for key, group in local._dns_acme_groups : "${group[0].name}-acme" => {
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
        priority = record.type == "MX" ? try(record.priority, null) : null
        proxied  = try(record.proxied, false)
        type     = record.type
        wildcard = try(record.wildcard, true)
        zone     = zone
      }
    }
  ]...)

  dns_records_servers = merge(
    {
      for key, server in local._servers : "${var.defaults.domain_external}-${key}-cname" => {
        content = server.input.public_address.value
        name    = "${server.fqdn}.${var.defaults.domain_external}"
        server  = key
        type    = "CNAME"
        zone    = var.defaults.domain_external
      }
      if server.input.public_address.value != null
    },
    {
      for key, server in local._servers : "${var.defaults.domain_external}-${key}-a" => {
        content = server.input.public_ipv4.value
        name    = "${server.fqdn}.${var.defaults.domain_external}"
        server  = key
        type    = "A"
        zone    = var.defaults.domain_external
      }
      if server.input.public_address.value == null && server.input.public_ipv4.value != null && can(cidrhost("${server.input.public_ipv4.value}/32", 0))
    },
    {
      for key, server in local._servers : "${var.defaults.domain_external}-${key}-aaaa" => {
        content = server.input.public_ipv6.value
        name    = "${server.fqdn}.${var.defaults.domain_external}"
        server  = key
        type    = "AAAA"
        zone    = var.defaults.domain_external
      }
      if server.input.public_address.value == null && server.input.public_ipv6.value != null && can(cidrhost("${server.input.public_ipv6.value}/128", 0))
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
    for key, service in local.services : (
      length(local.services_deployments[key]) == 0 || contains(local.services[key].tags, "no_dns")
      ) ? {} : merge(
      {
        for target in local.services_deployments[key] : "${var.defaults.domain_external}-${key}-${target}" => {
          content  = "${local._servers[target].fqdn}.${var.defaults.domain_external}"
          name     = "${service.name}.${local._servers[target].fqdn}.${var.defaults.domain_external}"
          server   = target
          type     = "CNAME"
          wildcard = true
          zone     = var.defaults.domain_external
        }
      },
      {
        for target in local.services_deployments[key] : "${var.defaults.domain_internal}-${key}-${target}" => {
          content  = "${local._servers[target].fqdn}.${var.defaults.domain_internal}"
          name     = "${service.name}.${local._servers[target].fqdn}.${var.defaults.domain_internal}"
          server   = target
          type     = "CNAME"
          wildcard = true
          zone     = var.defaults.domain_internal
        }
      }
    )
  ]...)

  dns_records_services_urls = {
    for key, service in local.services : "${key}-url" => {
      content = (
        contains(local.servers[local.services_deployments[key][0]].tags, "proxied") &&
        local.servers_resources[local.services_deployments[key][0]].cloudflare ?
        "${cloudflare_zero_trust_tunnel_cloudflared.server[local.services_deployments[key][0]].id}.cfargotunnel.com" :
        "${service.name}.${local._servers[local.services_deployments[key][0]].fqdn}.${contains(local.services[key].tags, "external") ? var.defaults.domain_external : var.defaults.domain_internal}"
      )
      name    = service.url
      proxied = contains(local.servers[local.services_deployments[key][0]].tags, "proxied")
      server  = local.services_deployments[key][0]
      type    = "CNAME"
      zone    = local._dns_services_url_zone[key]
    }
    if service.url != null &&
    length(local.services_deployments[key]) == 1 &&
    local._dns_services_url_zone[key] != null
  }

  dns_records_wildcards = {
    for key, group in {
      for candidate in local._dns_acme_candidates : "${candidate.zone}|${candidate.name}" => candidate...
      } : "${group[0].name}-wildcard" => {
      content = group[0].name
      name    = "*.${group[0].name}"
      type    = "CNAME"
      zone    = group[0].zone
    }
  }

  dns_zones = keys(var.dns)
}
