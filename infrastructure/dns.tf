data "cloudflare_zone" "configured" {
  for_each = var.dns

  filter = {
    name = each.key
  }
}

locals {
  # Manual DNS records from dns.auto.tfvars
  manual_dns_records = merge([
    for zone_name, records in var.dns : {
      for idx, record in records :
      "${zone_name}-manual-${record.type}-${idx}" => {
        zone_id  = data.cloudflare_zone.configured[zone_name].zone_id
        name     = record.name
        type     = record.type
        value    = record.type == "MX" ? "${record.priority} ${record.content}" : record.content
        priority = record.type == "MX" ? record.priority : null
        proxied  = record.proxied
      }
    }
  ]...)

  # Wildcard DNS records (create additional *.name records)
  wildcard_dns_records = merge([
    for zone_name, records in var.dns : {
      for idx, record in records :
      "${zone_name}-wildcard-${idx}" => {
        zone_id  = data.cloudflare_zone.configured[zone_name].zone_id
        name     = record.name == "@" ? "*" : "*.${record.name}"
        type     = "CNAME"
        value    = record.name == "@" ? zone_name : "${record.name}.${zone_name}"
        priority = null
        proxied  = false # Wildcards can't be proxied
      } if record.wildcard && record.type == "CNAME"
    }
  ]...)

  # TODO: Extract server details from 1Password items
  server_details = {}

  # TODO: Auto-generated server DNS records
  server_dns_records = {}

  # TODO: Service names extracted from 1Password items
  service_names = {}

  # TODO: Determine deployment servers for services (placeholder for Komodo integration)
  service_deployment_servers = {}

  # TODO: Auto-generated service DNS records
  service_dns_records = {} # Services will be deployed via Komodo, DNS handled separately

  # Merge all DNS records
  all_dns_records = merge(
    local.manual_dns_records,
    local.wildcard_dns_records,
    local.server_dns_records,
    local.service_dns_records
  )
}

resource "cloudflare_dns_record" "all" {
  for_each = local.all_dns_records

  zone_id  = each.value.zone_id
  name     = each.value.name
  type     = each.value.type
  content  = each.value.value
  priority = each.value.priority
  proxied  = each.value.proxied
  ttl      = each.value.proxied ? 1 : 300

  lifecycle {
    create_before_destroy = true
  }
}

output "dns_records_summary" {
  description = "Summary of DNS records by type"

  value = {
    manual   = length(local.manual_dns_records)
    servers  = length(local.server_dns_records)
    services = length(local.service_dns_records)
    total    = length(local.all_dns_records)
  }
}

output "dns_zones" {
  description = "Configured DNS zones"

  value = {
    for zone_name, records in var.dns :
    zone_name => {
      zone_id        = data.cloudflare_zone.configured[zone_name].zone_id
      name_servers   = data.cloudflare_zone.configured[zone_name].name_servers
      manual_records = length(records)
      total_records  = length([for k, v in local.all_dns_records : k if strcontains(k, zone_name)])
    }
  }
}
