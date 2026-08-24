data "cloudflare_account" "default" {
  filter = {
    name = local.cloudflare.account_name
  }
}

data "cloudflare_account_api_token_permission_groups_list" "dns_write" {
  account_id = data.cloudflare_account.default.id
  max_items  = 1
  name       = "DNS%20Write"
  scope      = "com.cloudflare.api.account.zone"
}

data "cloudflare_account_api_token_permission_groups_list" "zone_read" {
  account_id = data.cloudflare_account.default.id
  max_items  = 1
  name       = "Zone%20Read"
  scope      = "com.cloudflare.api.account.zone"
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "cluster" {
  for_each = local.cloudflare_consumers_tunnel

  account_id = data.cloudflare_account.default.id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.cluster[each.key].id
}

data "cloudflare_zone" "default" {
  for_each = local.cloudflare_zones

  filter = {
    name = each.value
  }
}

locals {
  cloudflare_consumers_acme = {
    for name, consumer in local.cloudflare.acme_consumers : name => merge(consumer, {
      challenge_hostname = can(consumer.machine) ? local.machine_fqdns[consumer.machine] : "${consumer.cluster}.${local.domains.services}"
      challenge_zone     = can(consumer.machine) ? local.domains.infrastructure : local.domains.services
      credential_scope   = can(consumer.machine) ? local.machine_fqdns[consumer.machine] : name
      target_hostname    = can(consumer.machine) ? "${name}.${local.domains.acme}" : "_acme-challenge.${consumer.cluster}.${local.domains.services}.${local.domains.acme}"
      title              = can(consumer.machine) ? "Cloudflare ACME DNS: ${local.machine_fqdns[consumer.machine]}" : "cloudflare-acme"
      vault              = can(consumer.machine) ? "homelab" : "cluster/${name}"
    })
  }

  cloudflare_consumers_external_dns = {
    for name, consumer in local.cloudflare.external_dns_consumers : name => merge(consumer, {
      title = "cloudflare-external-dns"
      vault = "cluster/${name}"
    })
  }

  cloudflare_consumers_tunnel = {
    for name, consumer in local.cloudflare.tunnel_consumers : name => merge(consumer, {
      credential_scope = can(consumer.machine) ? local.machine_fqdns[consumer.machine] : name
      tags             = can(consumer.machine) ? toset(["Homelab", "Cloudflare", "Tunnel"]) : toset(["Homelab", "Cloudflare", "Kubernetes"])
      title            = can(consumer.machine) ? "Cloudflare Tunnel: ${local.machine_fqdns[consumer.machine]}" : "cloudflare-tunnel"
      vault            = can(consumer.machine) ? "homelab" : "cluster/${name}"
    })
  }

  cloudflare_zones = toset(concat(
    values(local.domains),
    [for source_file in local.dns_zone_files : source_file.zone.name],
  ))
}

resource "cloudflare_account_token" "acme" {
  for_each = local.cloudflare_consumers_acme

  account_id = data.cloudflare_account.default.id
  name       = "Cloudflare ACME DNS: ${each.value.credential_scope}"

  policies = [
    {
      effect = "allow"

      permission_groups = [
        {
          id = one(data.cloudflare_account_api_token_permission_groups_list.dns_write.result).id
        },
        {
          id = one(data.cloudflare_account_api_token_permission_groups_list.zone_read.result).id
        },
      ]

      resources = jsonencode({
        "com.cloudflare.api.account.zone.${data.cloudflare_zone.default[local.domains.acme].zone_id}" = "*"
      })
    },
    {
      effect = "allow"

      permission_groups = [
        {
          id = one(data.cloudflare_account_api_token_permission_groups_list.zone_read.result).id
        },
      ]

      resources = jsonencode({
        "com.cloudflare.api.account.zone.${data.cloudflare_zone.default[each.value.challenge_zone].zone_id}" = "*"
      })
    },
  ]

  depends_on = [terraform_data.acme_validation]
}

resource "cloudflare_account_token" "external_dns" {
  for_each = local.cloudflare_consumers_external_dns

  account_id = data.cloudflare_account.default.id
  name       = "Cloudflare ExternalDNS: ${each.key}"

  policies = [
    {
      effect = "allow"

      permission_groups = [
        {
          id = one(data.cloudflare_account_api_token_permission_groups_list.dns_write.result).id
        },
        {
          id = one(data.cloudflare_account_api_token_permission_groups_list.zone_read.result).id
        },
      ]

      resources = jsonencode({
        for zone in local.cloudflare_zones :
        "com.cloudflare.api.account.zone.${data.cloudflare_zone.default[zone].zone_id}" => "*"
      })
    },
  ]

  lifecycle {
    prevent_destroy = true
  }
}

resource "cloudflare_dns_record" "all" {
  for_each = local.dns_records

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
  for_each = local.cloudflare_consumers_tunnel

  account_id = data.cloudflare_account.default.id
  config_src = "cloudflare"
  name       = each.key

  depends_on = [terraform_data.tunnel_validation]
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "cluster" {
  for_each = {
    for name, consumer in local.cloudflare_consumers_tunnel : name => consumer
    if can(consumer.cluster)
  }

  account_id = data.cloudflare_account.default.id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.cluster[each.key].id

  config = {
    ingress = [
      {
        service = "http://traefik-tunnel.networking.svc.cluster.local:80"
      },
    ]
  }
}

resource "terraform_data" "acme_validation" {
  input = sort(keys(local.cloudflare_consumers_acme))

  lifecycle {
    precondition {
      condition = alltrue([
        for consumer in values(local.cloudflare.acme_consumers) :
        can(consumer.machine) != can(consumer.cluster)
      ])
      error_message = "Each ACME consumer must reference exactly one machine or cluster."
    }

    precondition {
      condition = alltrue([
        for consumer in values(local.cloudflare.acme_consumers) :
        can(consumer.machine) ? can(local.machines[consumer.machine]) : can(local.clusters[consumer.cluster])
      ])
      error_message = "Every ACME consumer must reference an existing machine or cluster."
    }
  }
}

resource "terraform_data" "tunnel_validation" {
  input = sort(keys(local.cloudflare_consumers_tunnel))

  lifecycle {
    precondition {
      condition = alltrue([
        for consumer in values(local.cloudflare.tunnel_consumers) :
        can(consumer.machine) != can(consumer.cluster)
      ])
      error_message = "Each tunnel consumer must reference exactly one machine or cluster."
    }

    precondition {
      condition = alltrue([
        for consumer in values(local.cloudflare.tunnel_consumers) :
        can(consumer.machine) ? can(local.machines[consumer.machine]) : can(local.clusters[consumer.cluster])
      ])
      error_message = "Every tunnel consumer must reference an existing machine or cluster."
    }
  }
}
