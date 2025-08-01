# DNS Zone and Record Management

variable "dns_zones" {
  description = "DNS zone configuration"
  type = map(object({
    enabled         = bool
    proxied_default = bool
    records = list(object({
      name     = string
      type     = string
      content  = string
      priority = optional(number)
      proxied  = optional(bool)
    }))
  }))
  default = {}
}

# Get Cloudflare zones
data "cloudflare_zones" "configured" {
  for_each = { for k, v in var.dns_zones : k => v if v.enabled }
  
  filter {
    name       = each.key
    account_id = local.providers.cloudflare.account_id
  }
}

locals {
  # Manual DNS records from dns.auto.tfvars
  manual_dns_records = merge([
    for zone_name, zone in var.dns_zones : {
      for idx, record in zone.records : 
      "${zone_name}-manual-${record.type}-${idx}" => {
        zone_id  = data.cloudflare_zones.configured[zone_name].zones[0].id
        name     = record.name
        type     = record.type
        value    = record.type == "MX" ? "${record.priority} ${record.content}" : record.content
        priority = record.type == "MX" ? record.priority : null
        proxied  = try(record.proxied, zone.proxied_default, false)
      }
    } if zone.enabled
  ]...)

  # Auto-generated server DNS records
  server_dns_records = merge([
    for server_name, server in local.servers : {
      # External DNS
      "${server_name}-external" = {
        zone_id = data.cloudflare_zones.configured["excloo.net"].zones[0].id
        name    = "${server.short_name}.${server.inputs.region}"
        type    = "A"
        value   = server.outputs.public_ip
        proxied = true
      }
      # Internal DNS  
      "${server_name}-internal" = {
        zone_id = data.cloudflare_zones.configured["excloo.dev"].zones[0].id
        name    = "${server.short_name}.${server.inputs.region}"
        type    = "A"
        value   = server.outputs.tailscale_ip
        proxied = false
      }
    } if server.outputs.public_ip != "" || server.outputs.tailscale_ip != ""
  ]...)

  # Auto-generated service DNS records
  service_dns_records = merge([
    for service_name, service in local.services : merge(
      # Primary external DNS
      service.inputs.dns.external ? {
        "${service_name}-external" = {
          zone_id = data.cloudflare_zones.configured["excloo.net"].zones[0].id
          name    = local.service_names[service_name]
          type    = "CNAME"
          value   = "${local.service_deployment_servers[service_name]}.${var.dns_zones["excloo.net"].enabled ? "excloo.net" : "example.com"}"
          proxied = true
        }
      } : {},
      # Internal DNS
      service.inputs.dns.internal ? {
        "${service_name}-internal" = {
          zone_id = data.cloudflare_zones.configured["excloo.dev"].zones[0].id
          name    = local.service_names[service_name]
          type    = "CNAME"
          value   = "${local.service_deployment_servers[service_name]}.${var.dns_zones["excloo.dev"].enabled ? "excloo.dev" : "example.local"}"
          proxied = false
        }
      } : {}
    )
  ]...)

  # Merge all DNS records
  all_dns_records = merge(
    local.manual_dns_records,
    local.server_dns_records,
    local.service_dns_records
  )
}

# Create all DNS records
resource "cloudflare_record" "all" {
  for_each = local.all_dns_records

  zone_id  = each.value.zone_id
  name     = each.value.name
  type     = each.value.type
  value    = each.value.value
  priority = each.value.priority
  proxied  = each.value.proxied
  ttl      = each.value.proxied ? 1 : 300

  lifecycle {
    create_before_destroy = true
  }
}

# Output DNS information
output "dns_zones" {
  description = "Configured DNS zones"
  value = {
    for zone_name, zone in var.dns_zones :
    zone_name => {
      enabled         = zone.enabled
      zone_id         = zone.enabled ? data.cloudflare_zones.configured[zone_name].zones[0].id : null
      name_servers    = zone.enabled ? data.cloudflare_zones.configured[zone_name].zones[0].name_servers : []
      manual_records  = length(zone.records)
      total_records   = length([for k, v in local.all_dns_records : k if strcontains(k, zone_name)])
    }
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
