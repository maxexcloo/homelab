data "cloudflare_zone" "configured" {
  for_each = var.dns

  filter = {
    name = each.key
  }
}

locals {
  dns_records_all = merge(
    local.dns_records_manual,
    local.dns_records_wildcard
  )

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
        proxied  = false # Wildcards can't be proxied
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
  ttl      = each.value.proxied ? 1 : 300
  type     = each.value.type
  zone_id  = each.value.zone_id

  lifecycle {
    create_before_destroy = true
  }
}
