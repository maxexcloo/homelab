locals {
  dns_records_homelab = merge(
    # External CNAME records (for domains with public addresses)
    {
      for k, v in local.onepassword_vault_homelab :
      "${var.domain_external}-${v.fqdn}-cname" => {
        content = local.homelab[k].public_address
        name    = "${v.fqdn}.${var.domain_external}"
        proxied = false
        type    = "CNAME"
        zone_id = data.cloudflare_zone.all[var.domain_external].zone_id
      } if local.homelab[k].public_address != null
    },
    # External A records (for domains with IPv4 but no CNAME)
    {
      for k, v in local.onepassword_vault_homelab :
      "${var.domain_external}-${v.fqdn}-a" => {
        content = local.homelab[k].public_ipv4
        name    = "${v.fqdn}.${var.domain_external}"
        proxied = false
        type    = "A"
        zone_id = data.cloudflare_zone.all[var.domain_external].zone_id
      } if local.homelab[k].public_address == null && local.homelab[k].public_ipv4 != null
    },
    # External AAAA records (only valid IPv6)
    {
      for k, v in local.onepassword_vault_homelab :
      "${var.domain_external}-${v.fqdn}-aaaa" => {
        content = local.homelab[k].public_ipv6
        name    = "${v.fqdn}.${var.domain_external}"
        proxied = false
        type    = "AAAA"
        zone_id = data.cloudflare_zone.all[var.domain_external].zone_id
      } if local.homelab[k].public_ipv6 != null && can(cidrhost("${local.homelab[k].public_ipv6}/128", 0))
    },
    # External wildcard records
    {
      for k, v in local.onepassword_vault_homelab :
      "${var.domain_external}-${v.fqdn}-wildcard" => {
        content = "${v.fqdn}.${var.domain_external}"
        name    = "*.${v.fqdn}.${var.domain_external}"
        proxied = false
        type    = "CNAME"
        zone_id = data.cloudflare_zone.all[var.domain_external].zone_id
      } if local.homelab[k].public_address != null || local.homelab[k].public_ipv4 != null ||
      (local.homelab[k].public_ipv6 != null && can(cidrhost("${local.homelab[k].public_ipv6}/128", 0)))
    },
    # Tailscale A records
    {
      for k, v in local.onepassword_vault_homelab :
      "${var.domain_internal}-${v.fqdn}-a" => {
        content = local.homelab[k].tailscale_ipv4
        name    = "${v.fqdn}.${var.domain_internal}"
        proxied = false
        type    = "A"
        zone_id = data.cloudflare_zone.all[var.domain_internal].zone_id
      } if local.homelab[k].tailscale_ipv4 != null
    },
    # Tailscale AAAA records (only valid IPv6)
    {
      for k, v in local.onepassword_vault_homelab :
      "${var.domain_internal}-${v.fqdn}-aaaa" => {
        content = local.homelab[k].tailscale_ipv6
        name    = "${v.fqdn}.${var.domain_internal}"
        proxied = false
        type    = "AAAA"
        zone_id = data.cloudflare_zone.all[var.domain_internal].zone_id
      } if local.homelab[k].tailscale_ipv6 != null && can(cidrhost("${local.homelab[k].tailscale_ipv6}/128", 0))
    },
    # Tailscale wildcard records
    {
      for k, v in local.onepassword_vault_homelab :
      "${var.domain_internal}-${v.fqdn}-wildcard" => {
        content = "${v.fqdn}.${var.domain_internal}"
        name    = "*.${v.fqdn}.${var.domain_internal}"
        proxied = false
        type    = "CNAME"
        zone_id = data.cloudflare_zone.all[var.domain_internal].zone_id
      } if local.homelab[k].tailscale_ipv4 != null ||
      (local.homelab[k].tailscale_ipv6 != null && can(cidrhost("${local.homelab[k].tailscale_ipv6}/128", 0)))
    },
    # ACME challenge records for homelab subdomains
    {
      for subdomain, zone in local.dns_records_homelab_acme :
      "acme-homelab-${replace(subdomain, ".", "-")}" => {
        content = "_acme-challenge.${var.domain_acme}"
        name    = "_acme-challenge.${subdomain}"
        proxied = false
        type    = "CNAME"
        zone_id = data.cloudflare_zone.all[zone].zone_id
      } if subdomain != var.domain_acme
    }
  )

  # Collect homelab subdomains that need ACME challenges
  dns_records_homelab_acme = merge(
    # External homelab subdomains
    {
      for k, v in local.onepassword_vault_homelab :
      "${v.fqdn}.${var.domain_external}" => var.domain_external
      if local.homelab[k].public_address != null || local.homelab[k].public_ipv4 != null ||
      (local.homelab[k].public_ipv6 != null && can(cidrhost("${local.homelab[k].public_ipv6}/128", 0)))
    },
    # Tailscale homelab subdomains
    {
      for k, v in local.onepassword_vault_homelab :
      "${v.fqdn}.${var.domain_internal}" => var.domain_internal
      if local.homelab[k].tailscale_ipv4 != null ||
      (local.homelab[k].tailscale_ipv6 != null && can(cidrhost("${local.homelab[k].tailscale_ipv6}/128", 0)))
    }
  )

  dns_records_manual = merge(
    # Manual DNS records from var.dns
    merge([
      for zone_name, records in var.dns : {
        for idx, record in records : "${zone_name}-manual-${record.type}-${idx}" => {
          content  = record.content
          name     = record.name == "@" ? zone_name : "${record.name}.${zone_name}"
          priority = record.type == "MX" ? record.priority : null
          proxied  = record.proxied
          type     = record.type
          zone_id  = data.cloudflare_zone.all[zone_name].zone_id
        }
      }
    ]...),
    # Manual wildcard records
    merge([
      for zone_name, records in var.dns : {
        for idx, record in records : "${zone_name}-wildcard-${idx}" => {
          content = record.name == "@" ? zone_name : "${record.name}.${zone_name}"
          name    = record.name == "@" ? "*.${zone_name}" : "*.${record.name}.${zone_name}"
          proxied = false
          type    = "CNAME"
          zone_id = data.cloudflare_zone.all[zone_name].zone_id
        } if record.wildcard && record.type == "CNAME"
      }
    ]...),
    # ACME challenge records for manual subdomains
    {
      for subdomain, zone in local.dns_records_manual_acme : "acme-manual-${replace(subdomain, ".", "-")}" => {
        content = "_acme-challenge.${var.domain_acme}"
        name    = "_acme-challenge.${subdomain}"
        proxied = false
        type    = "CNAME"
        zone_id = data.cloudflare_zone.all[zone].zone_id
      } if subdomain != var.domain_acme
    }
  )

  # Collect manual subdomains that need ACME challenges
  dns_records_manual_acme = merge(
    # Manual record subdomains (A, AAAA, CNAME only)
    merge([
      for zone_name, records in var.dns : {
        for record in records : record.name == "@" ? zone_name : "${record.name}.${zone_name}" => zone_name
        if contains(["A", "AAAA", "CNAME"], record.type)
      }
    ]...),
    # Root domains
    {
      for domain in keys(var.dns) : domain => domain
      if domain != var.domain_acme
    }
  )
}
