locals {
  _dns_acme_candidates = [
    for record in concat(
      values(local.dns_records_homelab),
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
      content = nonsensitive(shell_sensitive_script.acme_dns_homelab[group[0].server].output.fulldomain)
      name    = "_acme-challenge.${group[0].name}"
      type    = "CNAME"
      zone    = group[0].zone
    }
  }

  dns_records_homelab = merge(
    {
      for key, server in local.homelab_discovered : "${var.domain_external}-${key}-cname" => {
        content = server.input.public_address
        name    = "${server.fqdn}.${var.domain_external}"
        server  = key
        type    = "CNAME"
        zone    = var.domain_external
      }
      if server.input.public_address != null
    },
    {
      for key, server in local.homelab_discovered : "${var.domain_external}-${key}-a" => {
        content = server.input.public_ipv4
        name    = "${server.fqdn}.${var.domain_external}"
        server  = key
        type    = "A"
        zone    = var.domain_external
      }
      if server.input.public_address == null && server.input.public_ipv4 != null && can(cidrhost("${server.input.public_ipv4}/32", 0))
    },
    {
      for key, server in local.homelab_discovered : "${var.domain_external}-${key}-aaaa" => {
        content = server.input.public_ipv6
        name    = "${server.fqdn}.${var.domain_external}"
        server  = key
        type    = "AAAA"
        zone    = var.domain_external
      }
      if server.input.public_address == null && server.input.public_ipv6 != null && can(cidrhost("${server.input.public_ipv6}/128", 0))
    },
    {
      for key, server in local.homelab_discovered : "${var.domain_internal}-${key}-a" => {
        content = local.homelab[key].output.tailscale_ipv4
        name    = "${server.fqdn}.${var.domain_internal}"
        server  = key
        type    = "A"
        zone    = var.domain_internal
      }
      if local.homelab[key].output.tailscale_ipv4 != null
    },
    {
      for key, server in local.homelab_discovered : "${var.domain_internal}-${key}-aaaa" => {
        content = local.homelab[key].output.tailscale_ipv6
        name    = "${server.fqdn}.${var.domain_internal}"
        server  = key
        type    = "AAAA"
        zone    = var.domain_internal
      }
      if local.homelab[key].output.tailscale_ipv6 != null
    }
  )

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

  dns_records_services = merge([
    for key, service in local.services : (
      length(local.services_deployments[key]) == 0 || contains(local.services_tags[key], "no_dns")
      ) ? {} : merge(
      {
        for target in local.services_deployments[key] : "${var.domain_external}-${key}-${target}" => {
          content  = "${local.homelab_discovered[target].fqdn}.${var.domain_external}"
          name     = "${service.name}.${local.homelab_discovered[target].fqdn}.${var.domain_external}"
          server   = target
          type     = "CNAME"
          wildcard = true
          zone     = var.domain_external
        }
      },
      {
        for target in local.services_deployments[key] : "${var.domain_internal}-${key}-${target}" => {
          content  = "${local.homelab_discovered[target].fqdn}.${var.domain_internal}"
          name     = "${service.name}.${local.homelab_discovered[target].fqdn}.${var.domain_internal}"
          server   = target
          type     = "CNAME"
          wildcard = true
          zone     = var.domain_internal
        }
      }
    )
  ]...)

  dns_records_services_urls = {
    for key, service in local.services : "${key}-url" => {
      content = (
        contains(local.homelab_tags[local.services_deployments[key][0]], "proxied") &&
        local.homelab_resources[local.services_deployments[key][0]].cloudflare ?
        "${cloudflare_zero_trust_tunnel_cloudflared.homelab[local.services_deployments[key][0]].id}.cfargotunnel.com" :
        "${service.name}.${local.homelab_discovered[local.services_deployments[key][0]].fqdn}.${contains(local.services_tags[key], "external") ? var.domain_external : var.domain_internal}"
      )
      name    = service.url
      proxied = contains(local.homelab_tags[local.services_deployments[key][0]], "proxied")
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
