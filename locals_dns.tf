locals {
  # Get unique subdomains that need ACME and wildcard records
  # Note: Only include base records to avoid circular dependency with ACME/wildcards
  _dns_unique_subdomains = distinct(flatten([
    # From homelab external DNS records (computed directly from homelab data)
    [for k, v in local.homelab_discovered : {
      name = "${v.fqdn}.${var.domain_external}"
      zone = var.domain_external
    }],
    # From homelab internal DNS records (computed directly from homelab data)
    [for k, v in local.homelab_discovered : {
      name = "${v.fqdn}.${var.domain_internal}"
      zone = var.domain_internal
    }],
    # From manual DNS records
    flatten([
      for zone_name, records in var.dns : [
        for record in records : {
          name = record.name == "@" ? zone_name : "${record.name}.${zone_name}"
          zone = zone_name
        } if contains(["A", "AAAA", "CNAME"], record.type) && try(record.wildcard, true)
      ]
    ]),
    # Add root domains
    [for zone in keys(var.dns) : {
      name = zone
      zone = zone
    }]
  ]))

  # All DNS records with metadata
  dns_records = {
    for k, v in merge(
      local.dns_records_acme,
      local.dns_records_homelab_external,
      local.dns_records_homelab_internal,
      local.dns_records_manual,
      local.dns_records_services_external,
      local.dns_records_services_internal,
      local.dns_records_services_urls,
      local.dns_records_wildcards
      ) : k => merge(
      {
        comment  = "OpenTofu Managed"
        priority = null
        proxied  = false
        wildcard = true
      },
      v,
      {
        zone_id = data.cloudflare_zone.all[v.zone].zone_id
      }
    )
  }

  # ACME challenge records for all unique subdomains
  dns_records_acme = {
    for subdomain in local._dns_unique_subdomains : "${subdomain.name}-acme" => {
      content = "${replace(subdomain.name, ".", "-")}.${var.domain_acme}"
      name    = "_acme-challenge.${subdomain.name}"
      type    = "CNAME"
      zone    = subdomain.zone
    }
  }

  # Homelab external DNS records
  dns_records_homelab_external = merge(
    # CNAME records (take precedence)
    {
      for k, v in local.homelab_discovered : "${var.domain_external}-${k}-cname" => {
        content = local.homelab[k].public_address
        name    = "${v.fqdn}.${var.domain_external}"
        type    = "CNAME"
        zone    = var.domain_external
      } if local.homelab[k].public_address != null
    },
    # A records (only if no CNAME)
    {
      for k, v in local.homelab_discovered : "${var.domain_external}-${k}-a" => {
        content = local.homelab[k].public_ipv4
        name    = "${v.fqdn}.${var.domain_external}"
        type    = "A"
        zone    = var.domain_external
      } if local.homelab[k].public_address == null &&
      local.homelab[k].public_ipv4 != null &&
      can(cidrhost("${local.homelab[k].public_ipv4}/32", 0))
    },
    # AAAA records (only if no CNAME)
    {
      for k, v in local.homelab_discovered : "${var.domain_external}-${k}-aaaa" => {
        content = local.homelab[k].public_ipv6
        name    = "${v.fqdn}.${var.domain_external}"
        type    = "AAAA"
        zone    = var.domain_external
      } if local.homelab[k].public_address == null &&
      local.homelab[k].public_ipv6 != null &&
      can(cidrhost("${local.homelab[k].public_ipv6}/128", 0))
    }
  )

  # Homelab internal DNS records
  dns_records_homelab_internal = merge(
    {
      for k, v in local.homelab_discovered : "${var.domain_internal}-${k}-a" => {
        content = local.homelab[k].tailscale_ipv4
        name    = "${v.fqdn}.${var.domain_internal}"
        type    = "A"
        zone    = var.domain_internal
      } if local.homelab[k].tailscale_ipv4 != null
    },
    {
      for k, v in local.homelab_discovered : "${var.domain_internal}-${k}-aaaa" => {
        content = local.homelab[k].tailscale_ipv6
        name    = "${v.fqdn}.${var.domain_internal}"
        type    = "AAAA"
        zone    = var.domain_internal
      } if local.homelab[k].tailscale_ipv6 != null
    }
  )

  # Manual DNS records from var.dns
  dns_records_manual = merge([
    for zone_name, records in var.dns : {
      for i, record in records : "${zone_name}-manual-${record.type}-${i}" => {
        content  = record.content
        name     = record.name == "@" ? zone_name : "${record.name}.${zone_name}"
        priority = record.type == "MX" ? record.priority : null
        proxied  = record.proxied
        type     = record.type
        wildcard = record.wildcard
        zone     = zone_name
      }
    }
  ]...)

  # Service external DNS records
  dns_records_services_external = merge([
    for service_key, service in local.services : {
      for target in local.services_deployments[service_key].targets : "${var.domain_external}-${service_key}-${target}" => {
        content = "${local.homelab_discovered[target].fqdn}.${var.domain_external}"
        name    = "${service.name}.${local.homelab_discovered[target].fqdn}.${var.domain_external}"
        type    = "CNAME"
        zone    = var.domain_external
      }
    } if length(local.services_deployments[service_key].targets) > 0
  ]...)

  # Service internal DNS records
  dns_records_services_internal = merge([
    for service_key, service in local.services : {
      for target in local.services_deployments[service_key].targets : "${var.domain_internal}-${service_key}-${target}" => {
        content = "${local.homelab_discovered[target].fqdn}.${var.domain_internal}"
        name    = "${service.name}.${local.homelab_discovered[target].fqdn}.${var.domain_internal}"
        type    = "CNAME"
        zone    = var.domain_internal
      }
    } if length(local.services_deployments[service_key].targets) > 0
  ]...)

  # Service custom URL DNS records
  dns_records_services_urls = {
    for service_key, service in local.services : "${service_key}-url" => {
      content = (
        contains(local.services[service_key].tags, "proxied") &&
        local.homelab_resources[local.services_deployments[service_key].targets[0]].cloudflare ?
        "${cloudflare_zero_trust_tunnel_cloudflared.homelab[local.services_deployments[service_key].targets[0]].id}.cfargotunnel.com" :
        "${service.name}.${local.homelab_discovered[local.services_deployments[service_key].targets[0]].fqdn}.${
          contains(local.services[service_key].tags, "external") ? var.domain_external : var.domain_internal
        }"
      )
      name    = service.url
      proxied = contains(local.services[service_key].tags, "proxied")
      type    = "CNAME"
      zone    = try([for zone in keys(var.dns) : zone if endswith(service.url, zone)][0], null)
    } if service.url != null &&
    length(local.services_deployments[service_key].targets) > 0 &&
    try([for zone in keys(var.dns) : zone if endswith(service.url, zone)][0], null) != null
  }

  # Wildcard DNS records for all unique subdomains
  dns_records_wildcards = {
    for subdomain in local._dns_unique_subdomains : "${subdomain.name}-wildcard" => {
      content = subdomain.name
      name    = "*.${subdomain.name}"
      type    = "CNAME"
      zone    = subdomain.zone
    }
  }
}