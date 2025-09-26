locals {
  _dns_challenge_candidates = [
    for record in flatten([
      for records_map in local._dns_record_sets_challenge : values(records_map)
      ]) : {
      name   = record.name
      zone   = record.zone
      server = try(record.server, null)
    }
    if contains(["A", "AAAA", "CNAME"], record.type) && try(record.wildcard, true)
  ]

  _dns_challenge_grouped = {
    for candidate in local._dns_challenge_candidates :
    "${candidate.zone}|${candidate.name}|${candidate.server != null ? candidate.server : ""}" => candidate...
  }

  _dns_record_sets_challenge = [
    local.dns_records_homelab_external,
    local.dns_records_homelab_internal,
    local.dns_records_manual,
    local.dns_records_services_external,
    local.dns_records_services_internal
  ]

  _dns_service_primary_target = {
    for key in keys(local._dns_services_with_url) : key => local.services_deployments[key][0]
  }

  _dns_service_records = flatten([
    for key, service in local._dns_services_with_dns : [
      for target in local.services_deployments[key] : [
        {
          key = "${var.domain_external}-${key}-${target}"
          value = {
            content = "${local.homelab_discovered[target].fqdn}.${var.domain_external}"
            name    = "${service.name}.${local.homelab_discovered[target].fqdn}.${var.domain_external}"
            server  = target
            type    = "CNAME"
            zone    = var.domain_external
          }
        },
        {
          key = "${var.domain_internal}-${key}-${target}"
          value = {
            content = "${local.homelab_discovered[target].fqdn}.${var.domain_internal}"
            name    = "${service.name}.${local.homelab_discovered[target].fqdn}.${var.domain_internal}"
            server  = target
            type    = "CNAME"
            zone    = var.domain_internal
          }
        }
      ]
    ]
  ])

  _dns_service_url_context = {
    for key in keys(local._dns_services_with_url) : key => {
      target  = local._dns_service_primary_target[key]
      zone    = local._dns_service_url_zone[key]
      proxied = contains(local.homelab_tags[local._dns_service_primary_target[key]], "proxied")
    }
  }

  _dns_service_url_matches = {
    for key, service in local._dns_services_with_url : key => [
      for zone in local._dns_zones : zone
      if endswith(service.url, zone)
    ]
  }

  _dns_service_url_zone = {
    for key, matches in local._dns_service_url_matches : key => (
      length(matches) > 0 ?
      split(
        ":",
        reverse(sort([
          for zone in matches : format("%04d:%s", length(zone), zone)
        ]))[0]
      )[1] :
      ""
    )
  }

  _dns_services_with_dns = {
    for key, service in local.services : key => service
    if length(local.services_deployments[key]) > 0 && !contains(local.services_tags[key], "no_dns")
  }

  _dns_services_with_url = {
    for key, service in local.services : key => service
    if service.url != null && length(local.services_deployments[key]) == 1
  }

  _dns_wildcard_grouped = {
    for candidate in local._dns_challenge_candidates :
    "${candidate.zone}|${candidate.name}" => candidate...
  }

  _dns_zones = keys(var.dns)

  dns_records = {
    for key, record in merge(
      local.dns_records_acme,
      local.dns_records_wildcards,
      local.dns_records_services_urls,
      merge(local._dns_record_sets_challenge...)
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

  dns_records_acme = {
    for key, group in local._dns_challenge_grouped :
    "${group[0].name}-acme" => {
      content = nonsensitive(shell_sensitive_script.acme_dns_homelab[group[0].server].output.subdomain)
      name    = "_acme-challenge.${group[0].name}"
      type    = "CNAME"
      zone    = group[0].zone
    }
    if group[0].server != null
  }

  dns_records_homelab_external = flatten([
    for key, server in local.homelab_discovered : concat(
      server.input.public_address != null ? [{
        key = "${var.domain_external}-${key}-cname"
        value = {
          content = server.input.public_address
          name    = "${server.fqdn}.${var.domain_external}"
          server  = key
          type    = "CNAME"
          zone    = var.domain_external
        }
      }] : [],
      server.input.public_address == null && server.input.public_ipv4 != null && can(cidrhost("${server.input.public_ipv4}/32", 0)) ? [{
        key = "${var.domain_external}-${key}-a"
        value = {
          content = server.input.public_ipv4
          name    = "${server.fqdn}.${var.domain_external}"
          server  = key
          type    = "A"
          zone    = var.domain_external
        }
      }] : [],
      server.input.public_address == null && server.input.public_ipv6 != null && can(cidrhost("${server.input.public_ipv6}/128", 0)) ? [{
        key = "${var.domain_external}-${key}-aaaa"
        value = {
          content = server.input.public_ipv6
          name    = "${server.fqdn}.${var.domain_external}"
          server  = key
          type    = "AAAA"
          zone    = var.domain_external
        }
      }] : []
    )
  ])

  dns_records_homelab_internal = flatten([
    for key, server in local.homelab_discovered : concat(
      local.homelab[key].output.tailscale_ipv4 != null ? [{
        key = "${var.domain_internal}-${key}-a"
        value = {
          content = local.homelab[key].output.tailscale_ipv4
          name    = "${server.fqdn}.${var.domain_internal}"
          server  = key
          type    = "A"
          zone    = var.domain_internal
        }
      }] : [],
      local.homelab[key].output.tailscale_ipv6 != null ? [{
        key = "${var.domain_internal}-${key}-aaaa"
        value = {
          content = local.homelab[key].output.tailscale_ipv6
          name    = "${server.fqdn}.${var.domain_internal}"
          server  = key
          type    = "AAAA"
          zone    = var.domain_internal
        }
      }] : []
    )
  ])

  dns_records_manual = merge([
    for zone, records in var.dns : {
      for index, record in records : "${zone}-manual-${record.type}-${index}" => {
        content  = record.content
        name     = record.name == "@" ? zone : "${record.name}.${zone}"
        priority = record.type == "MX" ? record.priority : null
        proxied  = try(record.proxied, false)
        type     = record.type
        wildcard = try(record.wildcard, true)
        zone     = zone
      }
    }
  ]...)

  dns_records_services_external = {
    for item in local._dns_service_records : item.key => item.value
    if item.value.zone == var.domain_external
  }

  dns_records_services_internal = {
    for item in local._dns_service_records : item.key => item.value
    if item.value.zone == var.domain_internal
  }

  dns_records_services_urls = {
    for key, service in local._dns_services_with_url : "${key}-url" => {
      content = (
        local._dns_service_url_context[key].proxied && local.homelab_resources[local._dns_service_url_context[key].target].cloudflare ?
        "${cloudflare_zero_trust_tunnel_cloudflared.homelab[local._dns_service_url_context[key].target].id}.cfargotunnel.com" :
        "${service.name}.${local.homelab_discovered[local._dns_service_url_context[key].target].fqdn}.${contains(local.services_tags[key], "external") ? var.domain_external : var.domain_internal}"
      )
      name    = service.url
      proxied = local._dns_service_url_context[key].proxied
      server  = local._dns_service_url_context[key].target
      type    = "CNAME"
      zone    = local._dns_service_url_context[key].zone
    }
    if length(local._dns_service_url_matches[key]) > 0 && local._dns_service_url_zone[key] != ""
  }

  dns_records_wildcards = {
    for key, group in local._dns_wildcard_grouped :
    "${group[0].name}-wildcard" => {
      content = group[0].name
      name    = "*.${group[0].name}"
      type    = "CNAME"
      zone    = group[0].zone
    }
  }
}
