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

data "cloudflare_account_api_token_permission_groups_list" "zone_waf_write" {
  account_id = data.cloudflare_account.default.id
  max_items  = 1
  name       = "Zone%20WAF%20Write"
  scope      = "com.cloudflare.api.account.zone"
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "cluster" {
  for_each = local.cloudflare_consumers_tunnel

  account_id = data.cloudflare_account.default.id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.cluster[each.key].id
}

data "cloudflare_zone" "configured" {
  for_each = local.cloudflare_zones

  filter = {
    name = each.value
  }
}

locals {
  cloudflare_consumers_acme = {
    for name, challenge_mode in local.cloudflare.acme_consumers : name => {
      challenge_hostname = can(local.machines[name]) ? local.machine_fqdns[name] : "${name}.${local.domains.services}"
      challenge_mode     = challenge_mode
      challenge_zone     = can(local.machines[name]) ? local.domains.infrastructure : local.domains.services
      credential_scope   = can(local.machines[name]) ? local.machine_fqdns[name] : name
      dns_write_zone     = challenge_mode == "direct" ? (can(local.machines[name]) ? local.domains.infrastructure : local.domains.services) : local.domains.acme
      target_hostname    = can(local.machines[name]) ? "${name}.${local.domains.acme}" : "_acme-challenge.${name}.${local.domains.services}.${local.domains.acme}"
      title              = can(local.machines[name]) ? "Cloudflare ACME DNS: ${local.machine_fqdns[name]}" : "Cloudflare ACME DNS"
      vault              = can(local.machines[name]) ? "homelab" : "cluster/${name}"
    }
  }

  cloudflare_consumers_external_dns = {
    for name, zones in local.cloudflare.external_dns_consumers : name => {
      title = "Cloudflare ExternalDNS"
      vault = "cluster/${name}"
      zones = zones
    }
  }

  cloudflare_consumers_tunnel = {
    for name, consumer in local.cloudflare.tunnel_consumers : name => {
      is_cluster = can(local.clusters[name])
      title      = can(local.machines[name]) ? "Cloudflare Tunnel: ${local.machine_fqdns[name]}" : "Cloudflare Tunnel"
      vault      = can(local.machines[name]) ? "homelab" : "cluster/${name}"
      ingress = concat(
        [
          for route in try(consumer.ingress, []) : merge(
            {
              hostname = route.hostname
              service  = route.service
            },
            try(route.path, null) != null ? {
              path = route.path
            } : {},
            try(route.origin_request, null) != null ? {
              origin_request = route.origin_request
            } : {},
          )
        ],
        [
          {
            service = try(
              consumer.fallback_service,
              can(local.clusters[name]) ? "http://traefik-tunnel.networking.svc.cluster.local:80" : "http_status:503",
            )
          },
        ],
      )
    }
  }

  cloudflare_consumers_waf = {
    for name in keys(local.cloudflare.acme_consumers) : name => {
      title = "Cloudflare WAF: ${name}"
      zones = local.cloudflare.waf_zones
    } if can(local.clusters[name])
  }

  cloudflare_tunnel_route_entries = flatten([
    for consumer_name, consumer in local.cloudflare.tunnel_consumers : [
      for ingress in try(consumer.ingress, []) : {
        consumer = consumer_name
        hostname = ingress.hostname
        zone     = ingress.zone
      }
    ]
  ])

  cloudflare_tunnel_route_entries_by_hostname = {
    for route in local.cloudflare_tunnel_route_entries : route.hostname => route...
  }

  cloudflare_tunnel_routes = {
    for route_key, routes in {
      for route in local.cloudflare_tunnel_route_entries : "${route.consumer}/${route.hostname}" => route...
    } : route_key => routes[0]
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

  policies = concat(
    [
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
          "com.cloudflare.api.account.zone.${data.cloudflare_zone.configured[each.value.dns_write_zone].zone_id}" = "*"
        })
      },
    ],
    [
      for zone in local.cloudflare_zones : {
        effect = "allow"

        permission_groups = [
          {
            id = one(data.cloudflare_account_api_token_permission_groups_list.zone_read.result).id
          },
        ]

        resources = jsonencode({
          "com.cloudflare.api.account.zone.${data.cloudflare_zone.configured[zone].zone_id}" = "*"
        })
      }
      if zone != each.value.dns_write_zone
    ],
  )

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
        for zone in each.value.zones :
        "com.cloudflare.api.account.zone.${data.cloudflare_zone.configured[zone].zone_id}" => "*"
      })
    },
  ]

  depends_on = [terraform_data.external_dns_validation]
}

resource "cloudflare_account_token" "waf" {
  for_each = local.cloudflare_consumers_waf

  account_id = data.cloudflare_account.default.id
  name       = each.value.title

  policies = [
    {
      effect = "allow"

      permission_groups = [
        {
          id = one(data.cloudflare_account_api_token_permission_groups_list.zone_read.result).id
        },
        {
          id = one(data.cloudflare_account_api_token_permission_groups_list.zone_waf_write.result).id
        },
      ]

      resources = jsonencode({
        for zone in each.value.zones :
        "com.cloudflare.api.account.zone.${data.cloudflare_zone.configured[zone].zone_id}" => "*"
      })
    },
  ]

  depends_on = [terraform_data.waf_validation]
}

resource "cloudflare_dns_record" "managed" {
  for_each = local.dns_records

  comment  = each.value.comment
  content  = each.value.content
  name     = each.value.name
  priority = each.value.priority
  proxied  = each.value.proxied
  ttl      = each.value.ttl
  type     = each.value.type
  zone_id  = data.cloudflare_zone.configured[each.value.zone].zone_id

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
  for_each = local.cloudflare_consumers_tunnel

  account_id = data.cloudflare_account.default.id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.cluster[each.key].id

  config = {
    ingress = each.value.ingress
  }
}

resource "terraform_data" "acme_validation" {
  input = sort(keys(local.cloudflare_consumers_acme))

  lifecycle {
    precondition {
      condition = alltrue([
        for name in keys(local.cloudflare.acme_consumers) :
        can(local.machines[name]) != can(local.clusters[name])
      ])
      error_message = "Each ACME consumer must name exactly one existing machine or cluster."
    }

    precondition {
      condition = alltrue([
        for challenge_mode in values(local.cloudflare.acme_consumers) :
        contains(["delegated", "direct"], challenge_mode)
      ])
      error_message = "Every ACME consumer challenge mode must be delegated or direct."
    }
  }
}

resource "terraform_data" "external_dns_validation" {
  input = sort(keys(local.cloudflare_consumers_external_dns))

  lifecycle {
    precondition {
      condition = alltrue([
        for name in keys(local.cloudflare.external_dns_consumers) : can(local.clusters[name])
      ])
      error_message = "Every ExternalDNS consumer must name an existing cluster."
    }

    precondition {
      condition = alltrue([
        for zones in values(local.cloudflare.external_dns_consumers) : length(distinct(zones)) == length(zones)
      ])
      error_message = "ExternalDNS consumer zones must be unique."
    }

    precondition {
      condition = alltrue(flatten([
        for zones in values(local.cloudflare.external_dns_consumers) : [
          for zone in zones : contains(local.cloudflare_zones, zone)
        ]
      ]))
      error_message = "Every ExternalDNS consumer zone must have a DNS data file or a configured domain role."
    }
  }
}

resource "terraform_data" "tunnel_validation" {
  input = {
    consumers = sort(keys(local.cloudflare_consumers_tunnel))
    routes    = sort(keys(local.cloudflare_tunnel_routes))
  }

  lifecycle {
    precondition {
      condition = alltrue([
        for name in keys(local.cloudflare.tunnel_consumers) :
        can(local.machines[name]) != can(local.clusters[name])
      ])
      error_message = "Every Cloudflare Tunnel consumer must name exactly one existing machine or cluster."
    }

    precondition {
      condition = alltrue([
        for route in local.cloudflare_tunnel_route_entries :
        contains(local.cloudflare_zones, route.zone) &&
        (route.hostname == route.zone || endswith(route.hostname, ".${route.zone}"))
      ])
      error_message = "Every Cloudflare Tunnel ingress hostname must belong to its configured managed zone."
    }

    precondition {
      condition = alltrue([
        for routes in values(local.cloudflare_tunnel_route_entries_by_hostname) : (
          length(distinct([for route in routes : route.consumer])) == 1 &&
          length(distinct([for route in routes : route.zone])) == 1
        )
      ])
      error_message = "Every Cloudflare Tunnel ingress hostname must belong to one consumer and zone."
    }
  }
}

resource "terraform_data" "waf_validation" {
  input = sort(keys(local.cloudflare_consumers_waf))

  lifecycle {
    precondition {
      condition = alltrue([
        for name in keys(local.clusters) : contains(keys(local.cloudflare.acme_consumers), name)
      ])
      error_message = "Every cluster must be a Cloudflare ACME consumer before it receives a WAF credential."
    }

    precondition {
      condition     = length(local.cloudflare.waf_zones) > 0 && length(distinct(local.cloudflare.waf_zones)) == length(local.cloudflare.waf_zones)
      error_message = "Cloudflare WAF must have at least one unique zone."
    }

    precondition {
      condition     = alltrue([for zone in local.cloudflare.waf_zones : contains(local.cloudflare_zones, zone)])
      error_message = "Every Cloudflare WAF zone must have a DNS data file or a configured domain role."
    }
  }
}
