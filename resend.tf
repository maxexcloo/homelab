locals {
  resend_hosts = toset(yamldecode(file("${path.module}/data/domains.yaml")).resend.hosts)
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

resource "resend_domain" "infrastructure" {
  name = local.domains.infrastructure
}

resource "resend_domain_verification" "infrastructure" {
  domain_id = resend_domain.infrastructure.id

  depends_on = [cloudflare_dns_record.resend]
}
