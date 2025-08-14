locals {
  dns_records = merge(
    # Homelab records - one per server per domain
    {
      for record in flatten([
        for k, v in local.homelab_discovered : flatten([
          # External domain
          # CNAME takes precedence if public_address is set
          local.homelab[k].public_address != null ? [{
            content = local.homelab[k].public_address
            key     = "${var.domain_external}-${k}-cname"
            name    = "${v.fqdn}.${var.domain_external}"
            type    = "CNAME"
            zone    = var.domain_external
            }] : flatten([
            # A record for IPv4 (if no CNAME and IPv4 exists)
            local.homelab[k].public_ipv4 != null && can(cidrhost("${local.homelab[k].public_ipv4}/32", 0)) ? [{
              content = local.homelab[k].public_ipv4
              key     = "${var.domain_external}-${k}-a"
              name    = "${v.fqdn}.${var.domain_external}"
              type    = "A"
              zone    = var.domain_external
            }] : [],
            # AAAA record for IPv6 (if no CNAME and IPv6 exists)
            local.homelab[k].public_ipv6 != null && can(cidrhost("${local.homelab[k].public_ipv6}/128", 0)) ? [{
              content = local.homelab[k].public_ipv6
              key     = "${var.domain_external}-${k}-aaaa"
              name    = "${v.fqdn}.${var.domain_external}"
              type    = "AAAA"
              zone    = var.domain_external
            }] : []
          ]),
          # Internal domain - both IPv4 and IPv6 can coexist
          local.homelab[k].tailscale_ipv4 != null ? [{
            content = local.homelab[k].tailscale_ipv4
            key     = "${var.domain_internal}-${k}-a"
            name    = "${v.fqdn}.${var.domain_internal}"
            type    = "A"
            zone    = var.domain_internal
          }] : [],
          local.homelab[k].tailscale_ipv6 != null ? [{
            content = local.homelab[k].tailscale_ipv6
            key     = "${var.domain_internal}-${k}-aaaa"
            name    = "${v.fqdn}.${var.domain_internal}"
            type    = "AAAA"
            zone    = var.domain_internal
          }] : []
        ])
      ]) : record.key => record
    },
    # Service records - subdomains pointing to homelab servers
    {
      for record in flatten([
        for service_key, service in local.services : flatten([
          for target in local.services_deployments[service_key].targets : [
            {
              content = "${local.homelab_discovered[target].fqdn}.${var.domain_external}"
              key     = "${var.domain_external}-${service_key}-${target}"
              name    = "${service.name}.${local.homelab_discovered[target].fqdn}.${var.domain_external}"
              type    = "CNAME"
              zone    = var.domain_external
            },
            {
              content = "${local.homelab_discovered[target].fqdn}.${var.domain_internal}"
              key     = "${var.domain_internal}-${service_key}-${target}"
              name    = "${service.name}.${local.homelab_discovered[target].fqdn}.${var.domain_internal}"
              type    = "CNAME"
              zone    = var.domain_internal
            }
          ]
        ]) if length(local.services_deployments[service_key].targets) > 0
      ]) : record.key => record
    },
    # Custom service URLs from 1Password
    {
      for service_key, service in local.services : "${service_key}-url" => {
        # If proxied flag is set and the target server has a Cloudflare tunnel, use the tunnel
        # Otherwise, point to the service subdomain
        content = contains(local.services_flags[service_key].tags, "proxied") && contains(local.homelab_flags[local.services_deployments[service_key].targets[0]].resources, "cloudflare") ? "${cloudflare_zero_trust_tunnel_cloudflared.homelab[local.services_deployments[service_key].targets[0]].id}.cfargotunnel.com" : "${service.name}.${local.homelab_discovered[local.services_deployments[service_key].targets[0]].fqdn}.${contains(local.services_flags[service_key].tags, "external") ? var.domain_external : var.domain_internal}"
        name    = service.url
        proxied = contains(local.services_flags[service_key].tags, "proxied")
        type    = "CNAME"
        zone    = [for zone in keys(var.dns) : zone if endswith(service.url, zone)][0]
      } if service.url != null && length(local.services_deployments[service_key].targets) > 0 && length([for zone in keys(var.dns) : zone if endswith(service.url, zone)]) > 0
    },
    # Manual DNS records from var.dns
    merge([
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
  )

  dns_records_all = {
    for k, v in merge(
      local.dns_records,
      local.dns_records_acme,
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

  # Create ACME challenge records for each unique subdomain (plus root domains)
  dns_records_acme = merge(
    # ACME for root domains
    {
      for zone in distinct([for k, v in local.dns_records : v.zone]) : "${zone}-acme" => {
        content = "${replace(zone, ".", "-")}.${var.domain_acme}"
        name    = "_acme-challenge.${zone}"
        type    = "CNAME"
        zone    = zone
      }
    },
    # ACME for subdomains
    {
      for subdomain in local.dns_records_unique : "${subdomain.name}-acme" => {
        content = "${replace(subdomain.name, ".", "-")}.${var.domain_acme}"
        name    = "_acme-challenge.${subdomain.name}"
        type    = "CNAME"
        zone    = subdomain.zone
      } if subdomain.name != subdomain.zone
    }
  )

  # Get all unique subdomains
  dns_records_unique = distinct([
    for k, v in local.dns_records : {
      name = v.name
      zone = v.zone
    } if contains(["A", "AAAA", "CNAME"], v.type) && try(v.wildcard, true)
  ])

  # Create wildcard records for each unique subdomain
  dns_records_wildcards = {
    for subdomain in local.dns_records_unique : "${subdomain.name}-wildcard" => {
      content = subdomain.name
      name    = "*.${subdomain.name}"
      type    = "CNAME"
      zone    = subdomain.zone
    }
  }
}
