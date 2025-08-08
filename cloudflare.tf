data "cloudflare_zone" "configured" {
  for_each = var.dns

  filter = {
    name = each.key
  }
}

resource "cloudflare_dns_record" "all" {
  for_each = nonsensitive(merge(local.dns_records_homelab, local.dns_records_manual))

  comment  = "OpenTofu Managed"
  content  = each.value.content
  name     = each.value.name
  priority = try(each.value.priority, null)
  proxied  = try(each.value.proxied, false)
  ttl      = 1
  type     = each.value.type
  zone_id  = each.value.zone_id
}
