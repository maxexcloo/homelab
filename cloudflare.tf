data "cloudflare_zone" "configured" {
  for_each = var.dns

  filter = {
    name = each.key
  }
}

locals {
  dns_records_all = nonsensitive(merge(
    local.dns_records_acme_challenge,
    local.dns_records_homelab_external_address,
    local.dns_records_homelab_external_ipv4,
    local.dns_records_homelab_external_ipv6,
    local.dns_records_homelab_external_wildcard,
    local.dns_records_homelab_internal_ipv4,
    local.dns_records_homelab_internal_ipv6,
    local.dns_records_homelab_internal_wildcard,
    local.dns_records_manual,
    local.dns_records_wildcard
  ))

  # Extract unique domains from all DNS records
  dns_domains_all = toset([
    for record_key, record_data in merge(
      local.dns_records_homelab_external_address,
      local.dns_records_homelab_external_ipv4,
      local.dns_records_homelab_external_ipv6,
      local.dns_records_homelab_external_wildcard,
      local.dns_records_homelab_internal_ipv4,
      local.dns_records_homelab_internal_ipv6,
      local.dns_records_homelab_internal_wildcard,
      local.dns_records_manual,
      local.dns_records_wildcard
    ) : regex("([^.]+\\.[^.]+)$", record_data.name)[0]
  ])

  dns_records_acme_challenge = {
    for domain in local.dns_domains_all : "${domain}-acme-challenge" => {
      content  = "_acme-challenge.${var.acme_domain}"
      name     = "_acme-challenge.${domain}"
      priority = null
      proxied  = false
      type     = "CNAME"
      zone_id  = data.cloudflare_zone.configured[domain].zone_id
    }
    if contains(keys(data.cloudflare_zone.configured), domain)
  }

  dns_records_homelab_external_ipv4 = {
    for server_key, server_data in local.onepassword_vault_homelab_all : "${var.domain_external}-homelab-ipv4-${server_data.fqdn}" => {
      content  = local.onepassword_vault_homelab_sections[server_key].input.public_ipv4
      name     = "${server_data.fqdn}.${var.domain_external}"
      priority = null
      proxied  = false
      type     = "A"
      zone_id  = data.cloudflare_zone.configured[var.domain_external].zone_id
    }
    if contains(keys(local.onepassword_vault_homelab_sections), server_key) &&
    try(local.onepassword_vault_homelab_sections[server_key].input.public_ipv4, "-") != "-" &&
    try(local.onepassword_vault_homelab_sections[server_key].input.public_address, "-") == "-"
  }

  dns_records_homelab_external_ipv6 = {
    for server_key, server_data in local.onepassword_vault_homelab_all : "${var.domain_external}-homelab-ipv6-${server_data.fqdn}" => {
      content  = local.onepassword_vault_homelab_sections[server_key].input.public_ipv6
      name     = "${server_data.fqdn}.${var.domain_external}"
      priority = null
      proxied  = false
      type     = "AAAA"
      zone_id  = data.cloudflare_zone.configured[var.domain_external].zone_id
    }
    if contains(keys(local.onepassword_vault_homelab_sections), server_key) &&
    try(local.onepassword_vault_homelab_sections[server_key].input.public_ipv6, "-") != "-" &&
    try(local.onepassword_vault_homelab_sections[server_key].input.public_address, "-") == "-"
  }

  dns_records_homelab_external_address = {
    for server_key, server_data in local.onepassword_vault_homelab_all : "${var.domain_external}-homelab-address-${server_data.fqdn}" => {
      content  = local.onepassword_vault_homelab_sections[server_key].input.public_address
      name     = "${server_data.fqdn}.${var.domain_external}"
      priority = null
      proxied  = false
      type     = "CNAME"
      zone_id  = data.cloudflare_zone.configured[var.domain_external].zone_id
    }
    if contains(keys(local.onepassword_vault_homelab_sections), server_key) &&
    try(local.onepassword_vault_homelab_sections[server_key].input.public_address, "-") != "-"
  }

  dns_records_homelab_external_wildcard = {
    for server_key, server_data in local.onepassword_vault_homelab_all : "${var.domain_external}-homelab-wildcard-${server_data.fqdn}" => {
      content  = "${server_data.fqdn}.${var.domain_external}"
      name     = "*.${server_data.fqdn}.${var.domain_external}"
      priority = null
      proxied  = false
      type     = "CNAME"
      zone_id  = data.cloudflare_zone.configured[var.domain_external].zone_id
    }
    if contains(keys(local.onepassword_vault_homelab_sections), server_key) &&
    (try(local.onepassword_vault_homelab_sections[server_key].input.public_address, "-") != "-" || try(local.onepassword_vault_homelab_sections[server_key].input.public_ipv4, "-") != "-")
  }

  dns_records_homelab_internal_ipv4 = {
    for server_key, server_data in local.onepassword_vault_homelab_all : "${var.domain_internal}-homelab-ipv4-${server_data.name}" => {
      content  = local.tailscale_devices[server_key].tailscale_ipv4
      name     = "${server_data.name}.${var.domain_internal}"
      priority = null
      proxied  = false
      type     = "A"
      zone_id  = data.cloudflare_zone.configured[var.domain_internal].zone_id
    }
    if contains(keys(local.tailscale_devices), server_key) && local.tailscale_devices[server_key].tailscale_ipv4 != null
  }

  dns_records_homelab_internal_ipv6 = {
    for server_key, server_data in local.onepassword_vault_homelab_all : "${var.domain_internal}-homelab-ipv6-${server_data.name}" => {
      content  = local.tailscale_devices[server_key].tailscale_ipv6
      name     = "${server_data.name}.${var.domain_internal}"
      priority = null
      proxied  = false
      type     = "AAAA"
      zone_id  = data.cloudflare_zone.configured[var.domain_internal].zone_id
    }
    if contains(keys(local.tailscale_devices), server_key) && local.tailscale_devices[server_key].tailscale_ipv6 != null
  }

  dns_records_homelab_internal_wildcard = {
    for server_key, server_data in local.onepassword_vault_homelab_all : "${var.domain_internal}-homelab-wildcard-${server_data.name}" => {
      content  = "${server_data.name}.${var.domain_internal}"
      name     = "*.${server_data.name}.${var.domain_internal}"
      priority = null
      proxied  = false
      type     = "CNAME"
      zone_id  = data.cloudflare_zone.configured[var.domain_internal].zone_id
    }
    if contains(keys(local.tailscale_devices), server_key) &&
    (local.tailscale_devices[server_key].tailscale_ipv4 != null || local.tailscale_devices[server_key].tailscale_ipv6 != null)
  }

  dns_records_manual = merge([
    for zone_name, records in var.dns : {
      for idx, record in records : "${zone_name}-manual-${record.type}-${idx}" => {
        name     = record.name == "@" ? zone_name : "${record.name}.${zone_name}"
        priority = record.type == "MX" ? record.priority : null
        proxied  = record.proxied
        type     = record.type
        content  = record.content
        zone_id  = data.cloudflare_zone.configured[zone_name].zone_id
      }
    }
  ]...)

  dns_records_wildcard = merge([
    for zone_name, records in var.dns : {
      for idx, record in records : "${zone_name}-wildcard-${idx}" => {
        name     = record.name == "@" ? "*.${zone_name}" : "*.${record.name}"
        priority = null
        proxied  = false
        type     = "CNAME"
        content  = record.name == "@" ? zone_name : "${record.name}.${zone_name}"
        zone_id  = data.cloudflare_zone.configured[zone_name].zone_id
      } if record.wildcard && record.type == "CNAME"
    }
  ]...)
}

resource "cloudflare_dns_record" "all" {
  for_each = local.dns_records_all

  content  = each.value.content
  name     = each.value.name
  priority = each.value.priority
  proxied  = each.value.proxied
  ttl      = 1
  type     = each.value.type
  zone_id  = each.value.zone_id

  lifecycle {
    create_before_destroy = true
  }
}
