locals {
  dns_helpers_service_url_matches = {
    for key, service in local.dns_helpers_services_with_urls : key => [
      for zone in local.dns_zones : zone
      if endswith(service.url, zone)
    ]
  }

  dns_helpers_service_url_zone = {
    for key, matches in local.dns_helpers_service_url_matches : key => (
      length(matches) > 0 ?
      [
        for zone in matches : zone
        if length(zone) == max([for candidate in matches : length(candidate)]...)
      ][0] :
      null
    )
  }

  dns_helpers_services_with_dns = {
    for key, service in local.services : key => service
    if length(local.services_deployments[key]) > 0 && !contains(local.services_tags[key], "no_dns")
  }

  dns_helpers_services_with_urls = {
    for key, service in local.services : key => service
    if service.url != null && length(local.services_deployments[key]) == 1
  }

  dns_records_homelab_external = merge(
    {
      for key, server in local.homelab_discovered : "${var.domain_external}-${key}-cname" => {
        content = server.input.public_address
        name    = "${server.fqdn}.${var.domain_external}"
        server  = key
        type    = "CNAME"
        zone    = var.domain_external
      } if server.input.public_address != null
    },
    {
      for key, server in local.homelab_discovered : "${var.domain_external}-${key}-a" => {
        content = server.input.public_ipv4
        name    = "${server.fqdn}.${var.domain_external}"
        server  = key
        type    = "A"
        zone    = var.domain_external
      } if server.input.public_address == null && server.input.public_ipv4 != null && can(cidrhost("${server.input.public_ipv4}/32", 0))
    },
    {
      for key, server in local.homelab_discovered : "${var.domain_external}-${key}-aaaa" => {
        content = server.input.public_ipv6
        name    = "${server.fqdn}.${var.domain_external}"
        server  = key
        type    = "AAAA"
        zone    = var.domain_external
      } if server.input.public_address == null && server.input.public_ipv6 != null && can(cidrhost("${server.input.public_ipv6}/128", 0))
    }
  )

  dns_records_homelab_internal = merge(
    {
      for key, server in local.homelab_discovered : "${var.domain_internal}-${key}-a" => {
        content = local.homelab[key].output.tailscale_ipv4
        name    = "${server.fqdn}.${var.domain_internal}"
        server  = key
        type    = "A"
        zone    = var.domain_internal
      } if local.homelab[key].output.tailscale_ipv4 != null
    },
    {
      for key, server in local.homelab_discovered : "${var.domain_internal}-${key}-aaaa" => {
        content = local.homelab[key].output.tailscale_ipv6
        name    = "${server.fqdn}.${var.domain_internal}"
        server  = key
        type    = "AAAA"
        zone    = var.domain_internal
      } if local.homelab[key].output.tailscale_ipv6 != null
    }
  )

  dns_records_manual = merge([
    for zone, records in var.dns : {
      for index, record in records : "${zone}-manual-${record.type}-${index}" => {
        content  = record.content
        name     = record.name == "@" ? zone : "${record.name}.${zone}"
        priority = record.type == "MX" ? record.priority : null
        proxied  = record.proxied
        type     = record.type
        wildcard = record.wildcard
        zone     = zone
      }
    }
  ]...)

  dns_records_services_external = merge([
    for key, service in local.dns_helpers_services_with_dns : {
      for target in local.services_deployments[key] : "${var.domain_external}-${key}-${target}" => {
        content = "${local.homelab_discovered[target].fqdn}.${var.domain_external}"
        name    = "${service.name}.${local.homelab_discovered[target].fqdn}.${var.domain_external}"
        server  = target
        type    = "CNAME"
        zone    = var.domain_external
      }
    }
  ]...)

  dns_records_services_internal = merge([
    for key, service in local.dns_helpers_services_with_dns : {
      for target in local.services_deployments[key] : "${var.domain_internal}-${key}-${target}" => {
        content = "${local.homelab_discovered[target].fqdn}.${var.domain_internal}"
        name    = "${service.name}.${local.homelab_discovered[target].fqdn}.${var.domain_internal}"
        server  = target
        type    = "CNAME"
        zone    = var.domain_internal
      }
    }
  ]...)

  dns_records_services_urls = {
    for key, service in local.dns_helpers_services_with_urls : "${key}-url" => {
      content = (
        local.homelab_resources[local.services_deployments[key][0]].cloudflare && contains(local.homelab_tags[local.services_deployments[key][0]], "proxied") ?
        "${cloudflare_zero_trust_tunnel_cloudflared.homelab[local.services_deployments[key][0]].id}.cfargotunnel.com" :
        "${service.name}.${local.homelab_discovered[local.services_deployments[key][0]].fqdn}.${contains(local.services_tags[key], "external") ? var.domain_external : var.domain_internal}"
      )
      name    = service.url
      proxied = contains(local.homelab_tags[local.services_deployments[key][0]], "proxied")
      server  = local.services_deployments[key][0]
      type    = "CNAME"
      zone    = local.dns_helpers_service_url_zone[key]
    } if length(local.dns_helpers_service_url_matches[key]) > 0 && local.dns_helpers_service_url_zone[key] != null
  }

  dns_acme_targets = distinct(flatten([
    [
      for record in concat(
        values(local.dns_records_homelab_external),
        values(local.dns_records_homelab_internal),
        values(local.dns_records_manual),
        values(local.dns_records_services_external),
        values(local.dns_records_services_internal)
        ) : {
        name   = record.name
        server = try(record.server, null)
        zone   = record.zone
      } if contains(["A", "AAAA", "CNAME"], record.type) && try(record.wildcard, true)
    ]
  ]))

  dns_records_acme = {
    for target in local.dns_acme_targets : "${target.name}-acme" => {
      content = shell_script.acme_dns_homelab[target.server].output.subdomain
      name    = "_acme-challenge.${target.name}"
      type    = "CNAME"
      zone    = target.zone
    } if target.server != null
  }

  dns_records_wildcards = {
    for target in local.dns_acme_targets : "${target.name}-wildcard" => {
      content = target.name
      name    = "*.${target.name}"
      type    = "CNAME"
      zone    = target.zone
    }
  }

  dns_records = {
    for key, record in merge(
      local.dns_records_acme,
      local.dns_records_homelab_external,
      local.dns_records_homelab_internal,
      local.dns_records_manual,
      local.dns_records_services_external,
      local.dns_records_services_internal,
      local.dns_records_services_urls,
      local.dns_records_wildcards
      ) : key => merge(
      {
        comment  = "OpenTofu Managed"
        priority = null
        proxied  = false
        wildcard = true
      },
      record,
      {
        zone_id = data.cloudflare_zone.all[record.zone].zone_id
      }
    )
  }

  dns_zones = keys(var.dns)
}
