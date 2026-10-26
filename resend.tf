locals {
  resend_domains = {
    for dns_zone in local.dns_zones : dns_zone.name => local.provider_settings.dns.resend
    if contains(try(dns_zone.providers, []), "resend")
  }

  resend_hosts = toset([
    for name, machine in local.machines : name
    if try(machine.smtp, null) == "resend"
  ])
}

resource "resend_api_key" "cluster" {
  for_each = local.clusters

  name       = "cluster-${each.key}"
  permission = "full_access"
}

resource "resend_api_key" "fly" {
  name       = "fly"
  permission = "sending_access"
}

resource "resend_api_key" "host" {
  for_each = local.resend_hosts

  name       = "host-${each.key}"
  permission = "sending_access"
}

resource "resend_domain" "configured" {
  for_each = local.resend_domains

  name   = each.key
  region = each.value.region
}

resource "resend_domain_verification" "configured" {
  for_each = local.resend_domains

  domain_id = resend_domain.configured[each.key].id

  depends_on = [cloudflare_dns_record.managed]
}
