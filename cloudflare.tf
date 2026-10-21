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
  cloudflare = local.provider_settings.providers.cloudflare

  cloudflare_access_client_secret = one(flatten([
    for section in onepassword_item.cloudflare_access.section : [
      for field in section.field : field.value
      if field.label == "oidc-client-secret"
    ]
  ]))

  cloudflare_consumers = {
    for name, consumer in merge(local.machines, local.clusters) : name => consumer.cloudflare
    if can(consumer.cloudflare)
  }

  cloudflare_consumers_acme = {
    for name, consumer in local.cloudflare_consumers : name => {
      challenge_hostname = can(local.machines[name]) ? local.machine_fqdns[name] : "${name}.${local.domains.services}"
      challenge_mode     = consumer.acme
      challenge_zone     = can(local.machines[name]) ? local.domains.infrastructure : local.domains.services
      credential_scope   = can(local.machines[name]) ? local.machine_fqdns[name] : name
      dns_write_zone     = consumer.acme == "direct" ? (can(local.machines[name]) ? local.domains.infrastructure : local.domains.services) : local.domains.acme
      target_hostname    = can(local.machines[name]) ? "_acme-challenge.${name}.${local.domains.acme}" : "_acme-challenge.${name}.${local.domains.services}.${local.domains.acme}"
    }
    if can(consumer.acme)
  }

  cloudflare_consumers_external_dns = {
    for name, cluster in local.clusters : name => {
      zones = cluster.cloudflare.external_dns
    }
    if can(cluster.cloudflare.external_dns)
  }

  cloudflare_consumers_tunnel = {
    for name, consumer in local.cloudflare_consumers : name => {
      is_cluster = can(local.clusters[name])
      ingress = concat(
        [
          for route in try(consumer.tunnel.ingress, []) : merge(
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
              consumer.tunnel.fallback_service,
              can(local.clusters[name]) ? "http://traefik-tunnel.networking.svc.cluster.local:80" : "http_status:503",
            )
          },
        ],
      )
    }
    if can(consumer.tunnel)
  }

  cloudflare_consumers_waf = {
    for name, cluster in local.clusters : name => {
      title = "Cloudflare WAF: ${name}"
      zones = local.cloudflare_waf_zones
    }
    if try(cluster.cloudflare.waf, false)
  }

  cloudflare_tunnel_mtls_hostnames = {
    for route in local.cloudflare_tunnel_routes : route.zone => route.hostname...
    if anytrue([
      for ingress in local.cloudflare_consumers[route.consumer].tunnel.ingress :
      ingress.hostname == route.hostname && try(ingress.mtls, false)
    ])
  }

  cloudflare_tunnel_route_entries = flatten([
    for consumer_name, consumer in local.cloudflare_consumers : [
      for ingress in try(consumer.tunnel.ingress, []) : {
        consumer = consumer_name
        hostname = ingress.hostname
        zone     = one([for zone in local.cloudflare_zones : zone if endswith(".${ingress.hostname}", ".${zone}")])
      }
    ]
  ])

  cloudflare_tunnel_route_entries_by_hostname = {
    for route in local.cloudflare_tunnel_route_entries : route.hostname => route...
  }

  # Path-specific ingress rules repeat their hostname; each hostname needs one DNS route.
  cloudflare_tunnel_routes = {
    for route in distinct(local.cloudflare_tunnel_route_entries) : "${route.consumer}/${route.hostname}" => route
  }

  cloudflare_waf_zones = [
    for source_file in local.dns_zone_files : source_file.zone.name
    if try(source_file.zone.waf, false)
  ]

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
}

resource "cloudflare_certificate_authorities_hostname_associations" "mtls" {
  for_each = local.cloudflare_tunnel_mtls_hostnames

  hostnames = distinct(each.value)
  zone_id   = data.cloudflare_zone.configured[each.key].zone_id
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

resource "cloudflare_zero_trust_access_identity_provider" "pocket_id" {
  account_id = data.cloudflare_account.default.id
  name       = local.access.cloudflare_access.name
  type       = "oidc"

  config = {
    auth_url         = "${local.access.oidc_issuer_url}/authorize"
    certs_url        = "${local.access.oidc_issuer_url}/.well-known/jwks.json"
    client_id        = local.access.cloudflare_access.oidc_client_id
    client_secret    = local.cloudflare_access_client_secret
    email_claim_name = "email"
    pkce_enabled     = true
    scopes           = ["openid", "profile", "email"]
    token_url        = "${local.access.oidc_issuer_url}/api/oidc/token"
  }

  lifecycle {
    precondition {
      condition     = nonsensitive(try(length(local.cloudflare_access_client_secret), 0) > 0)
      error_message = "Kubelab has not yet published the Pocket ID client secret to the Cloudflare Access item."
    }
  }
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "cluster" {
  for_each = local.cloudflare_consumers_tunnel

  account_id = data.cloudflare_account.default.id
  config_src = "cloudflare"
  name       = each.key
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "cluster" {
  for_each = local.cloudflare_consumers_tunnel

  account_id = data.cloudflare_account.default.id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.cluster[each.key].id

  config = {
    ingress = each.value.ingress
  }
}

resource "cloudflare_zone_setting" "ssl" {
  for_each = {
    for source_file in local.dns_zone_files : source_file.zone.name => source_file.zone.ssl
    if try(source_file.zone.ssl, null) != null
  }

  setting_id = "ssl"
  value      = each.value
  zone_id    = data.cloudflare_zone.configured[each.key].zone_id
}
