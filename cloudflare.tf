data "cloudflare_account" "default" {
  filter = {
    name = local.cloudflare_account_name
  }
}

data "cloudflare_account_api_token_permission_groups_list" "dns_write" {
  account_id = data.cloudflare_account.default.id
  max_items  = 1
  name       = "DNS%20Write"
  scope      = "com.cloudflare.api.account.zone"
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "cluster" {
  for_each = local.cloudflare_tunnels

  account_id = data.cloudflare_account.default.id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.cluster[each.key].id
}

data "cloudflare_zone" "default" {
  for_each = local.cloudflare_zones

  filter = {
    name = each.value
  }
}

resource "cloudflare_account_token" "acme" {
  for_each = local.cloudflare_acme_consumers

  account_id = data.cloudflare_account.default.id
  name       = "Cloudflare ACME DNS: ${each.value.credential_scope}"

  policies = [
    {
      effect = "allow"

      permission_groups = [
        {
          id = one(data.cloudflare_account_api_token_permission_groups_list.dns_write.result).id
        },
      ]

      resources = jsonencode({
        "com.cloudflare.api.account.zone.${data.cloudflare_zone.default[local.domains.domains.acme].zone_id}" = "*"
      })
    },
  ]

  depends_on = [terraform_data.acme_validation]
}

resource "cloudflare_dns_record" "all" {
  for_each = local.dns_all_records

  comment  = each.value.comment
  content  = each.value.content
  name     = each.value.name
  priority = each.value.priority
  proxied  = each.value.proxied
  ttl      = each.value.ttl
  type     = each.value.type
  zone_id  = data.cloudflare_zone.default[each.value.zone].zone_id

  depends_on = [terraform_data.dns_validation]
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "cluster" {
  for_each = local.cloudflare_tunnels

  account_id = data.cloudflare_account.default.id
  config_src = "cloudflare"
  name       = each.key

  depends_on = [terraform_data.tunnel_validation]
}

resource "terraform_data" "acme_validation" {
  input = sort(keys(local.cloudflare_acme_consumers))

  lifecycle {
    precondition {
      condition = alltrue([
        for consumer in values(local.domains.cloudflare.acme_consumers) :
        (try(consumer.machine, null) != null) != (try(consumer.cluster, null) != null)
      ])
      error_message = "Each ACME consumer must reference exactly one machine or cluster."
    }

    precondition {
      condition = alltrue([
        for consumer in values(local.domains.cloudflare.acme_consumers) :
        try(consumer.machine, null) != null ? contains(keys(local.machines), consumer.machine) : contains(keys(local.clusters), consumer.cluster)
      ])
      error_message = "Every ACME consumer must reference an existing machine or cluster."
    }
  }
}

resource "terraform_data" "tunnel_validation" {
  input = sort(keys(local.cloudflare_tunnels))

  lifecycle {
    precondition {
      condition = alltrue([
        for consumer in values(local.domains.cloudflare.tunnel_consumers) :
        (try(consumer.machine, null) != null) != (try(consumer.cluster, null) != null)
      ])
      error_message = "Each tunnel consumer must reference exactly one machine or cluster."
    }

    precondition {
      condition = alltrue([
        for consumer in values(local.domains.cloudflare.tunnel_consumers) :
        try(consumer.machine, null) != null ? contains(keys(local.machines), consumer.machine) : contains(keys(local.clusters), consumer.cluster)
      ])
      error_message = "Every tunnel consumer must reference an existing machine or cluster."
    }
  }
}
