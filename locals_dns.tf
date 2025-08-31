locals {
  # Get unique subdomains that need ACME and wildcard records with server mapping
  _dns_unique = distinct(flatten([
    [
      for k, v in merge(
        local.dns_records_homelab_external,
        local.dns_records_homelab_internal,
        local.dns_records_manual,
        local.dns_records_services_external,
        local.dns_records_services_internal,
        local.dns_records_services_urls
        ) : {
        name   = v.name
        server = try(v.server, null)
        zone   = v.zone
      } if contains(["A", "AAAA", "CNAME"], v.type) && try(v.wildcard, true)
    ]
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

  # ACME challenge records for server-specific subdomains only
  dns_records_acme = {
    for subdomain in local._dns_unique : "${subdomain.name}-acme" => {
      content = local.acme_dns_homelab_registrations[subdomain.server].subdomain
      name    = "_acme-challenge.${subdomain.name}"
      type    = "CNAME"
      zone    = subdomain.zone
    } if subdomain.server != null
  }

  # Homelab external DNS records
  dns_records_homelab_external = merge(
    # CNAME records (take precedence)
    {
      for k, v in local.homelab_discovered : "${var.domain_external}-${k}-cname" => {
        content = local.homelab[k].public_address
        name    = "${v.fqdn}.${var.domain_external}"
        server  = k
        type    = "CNAME"
        zone    = var.domain_external
      } if local.homelab[k].public_address != null
    },
    # A records (only if no CNAME)
    {
      for k, v in local.homelab_discovered : "${var.domain_external}-${k}-a" => {
        content = local.homelab[k].public_ipv4
        name    = "${v.fqdn}.${var.domain_external}"
        server  = k
        type    = "A"
        zone    = var.domain_external
      } if local.homelab[k].public_address == null && local.homelab[k].public_ipv4 != null && can(cidrhost("${local.homelab[k].public_ipv4}/32", 0))
    },
    # AAAA records (only if no CNAME)
    {
      for k, v in local.homelab_discovered : "${var.domain_external}-${k}-aaaa" => {
        content = local.homelab[k].public_ipv6
        name    = "${v.fqdn}.${var.domain_external}"
        server  = k
        type    = "AAAA"
        zone    = var.domain_external
      } if local.homelab[k].public_address == null && local.homelab[k].public_ipv6 != null && can(cidrhost("${local.homelab[k].public_ipv6}/128", 0))
    }
  )

  # Homelab internal DNS records
  dns_records_homelab_internal = merge(
    {
      for k, v in local.homelab_discovered : "${var.domain_internal}-${k}-a" => {
        content = local.homelab[k].tailscale_ipv4
        name    = "${v.fqdn}.${var.domain_internal}"
        server  = k
        type    = "A"
        zone    = var.domain_internal
      } if local.homelab[k].tailscale_ipv4 != null
    },
    {
      for k, v in local.homelab_discovered : "${var.domain_internal}-${k}-aaaa" => {
        content = local.homelab[k].tailscale_ipv6
        name    = "${v.fqdn}.${var.domain_internal}"
        server  = k
        type    = "AAAA"
        zone    = var.domain_internal
      } if local.homelab[k].tailscale_ipv6 != null
    }
  )

  # Manual DNS records from var.dns
  dns_records_manual = merge([
    for zone, records in var.dns : {
      for i, record in records : "${zone}-manual-${record.type}-${i}" => {
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

  # Service external DNS records
  dns_records_services_external = merge([
    for k, service in local.services : {
      for target in local.services_deployments[k].targets : "${var.domain_external}-${k}-${target}" => {
        content = "${local.homelab_discovered[target].fqdn}.${var.domain_external}"
        name    = "${service.name}.${local.homelab_discovered[target].fqdn}.${var.domain_external}"
        server  = target
        type    = "CNAME"
        zone    = var.domain_external
      }
    } if length(local.services_deployments[k].targets) > 0
  ]...)

  # Service internal DNS records
  dns_records_services_internal = merge([
    for k, service in local.services : {
      for target in local.services_deployments[k].targets : "${var.domain_internal}-${k}-${target}" => {
        content = "${local.homelab_discovered[target].fqdn}.${var.domain_internal}"
        name    = "${service.name}.${local.homelab_discovered[target].fqdn}.${var.domain_internal}"
        server  = target
        type    = "CNAME"
        zone    = var.domain_internal
      }
    } if length(local.services_deployments[k].targets) > 0
  ]...)

  # Service custom URL DNS records
  dns_records_services_urls = {
    for k, service in local.services : "${k}-url" => {
      content = (
        contains(local.services[k].tags, "proxied") && local.homelab_resources[local.services_deployments[k].targets[0]].cloudflare ?
        "${cloudflare_zero_trust_tunnel_cloudflared.homelab[local.services_deployments[k].targets[0]].id}.cfargotunnel.com" :
        "${service.name}.${local.homelab_discovered[local.services_deployments[k].targets[0]].fqdn}.${contains(local.services[k].tags, "external") ? var.domain_external : var.domain_internal}"
      )
      name    = service.url
      proxied = contains(local.services[k].tags, "proxied")
      server  = local.services_deployments[k].targets[0]
      type    = "CNAME"
      zone    = try([for zone in keys(var.dns) : zone if endswith(service.url, zone)][0], null)
    } if service.url != null && length(local.services_deployments[k].targets) > 0 && try([for zone in keys(var.dns) : zone if endswith(service.url, zone)][0], null) != null
  }

  # Wildcard DNS records for all unique subdomains
  dns_records_wildcards = {
    for subdomain in local._dns_unique : "${subdomain.name}-wildcard" => {
      content = subdomain.name
      name    = "*.${subdomain.name}"
      type    = "CNAME"
      zone    = subdomain.zone
    }
  }
}
