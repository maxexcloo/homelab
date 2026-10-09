locals {
  resend       = yamldecode(file("${path.module}/data/domains.yaml")).resend
  resend_hosts = toset(local.resend.hosts)

  resend_domains = {
    for domain in local.cloudflare_zones : domain => merge(
      {
        cname  = true
        region = "us-east-1"
      },
      try(local.resend.domains[domain], {}),
    )
  }
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

  lifecycle {
    precondition {
      condition     = can(local.machines[each.key])
      error_message = "Every Resend host must name an existing machine."
    }
  }
}

resource "resend_domain" "configured" {
  for_each = local.resend_domains

  name   = each.key
  region = each.value.region
}

resource "resend_domain_verification" "configured" {
  for_each = local.resend_domains

  domain_id = resend_domain.configured[each.key].id

  depends_on = [cloudflare_dns_record.resend]
}
