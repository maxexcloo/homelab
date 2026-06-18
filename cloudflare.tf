data "cloudflare_account" "default" {
  filter = {
    name = local.defaults.cloudflare.account_name
  }
}

data "cloudflare_account_api_token_permission_groups_list" "dns_write" {
  account_id = data.cloudflare_account.default.id
  max_items  = 1
  name       = "DNS%20Write"
  scope      = "com.cloudflare.api.account.zone"
}

data "cloudflare_zero_trust_access_identity_providers" "all" {
  account_id = data.cloudflare_account.default.id
}

data "cloudflare_zone" "all" {
  for_each = local.dns_input

  filter = {
    name = each.key
  }
}

locals {
  # Flatten service routing URLs with cloudflare_access configs into a map keyed
  # by "{service_key}-{route_name}-{access_id}" for stable resource addressing.
  # access_id is derived from name (lowercased, special chars → hyphens).
  cloudflare_access_applications = {
    for item in flatten([
      for service_key, service in local.services_model : [
        for route in service.routing.urls : [
          for access_index, access in try(route.cloudflare_access, []) : {
            access       = access
            access_id    = replace(lower(access.name), "/[^a-z0-9]+/", "-")
            access_index = access_index
            route        = route
            service      = service
            service_key  = service_key
          }
        ]
      ]
    ]) : "${item.service_key}-${item.route.name}-${item.access_id}" => item
  }

  cloudflare_access_idp_ids = {
    for alias, identity_provider in local.defaults.cloudflare.access.identity_providers :
    alias => one([
      for provider in data.cloudflare_zero_trust_access_identity_providers.all.result : provider.id
      if provider.name == identity_provider.display_name
    ])
  }

  # Flatten service rate limiting rules by zone. Each zone gets one
  # cloudflare_ruleset resource managing the http_ratelimit phase.
  cloudflare_rate_limiting_rules_by_zone = {
    for rule in flatten([
      for service_key, service in local.services_model : [
        for route in service.routing.urls : [
          for rule in try(route.cloudflare_rate_limiting_rules, []) : {
            action      = rule.action
            description = try(rule.description, null)
            enabled     = try(rule.enabled, true)
            expression  = rule.expression
            ratelimit   = rule.ratelimit
            zone        = route.zone
          }
        ]
        if route.zone != null
      ]
    ]) : rule.zone => rule...
  }

  # Routes are only added when backed by a managed DNS record. The
  # http_status:503 catch-all is required by Cloudflare Tunnel.
  cloudflare_tunnel_ingress = {
    for server_key, server in local.servers_by_feature.cloudflared : server_key => concat(
      flatten([
        for service_key, service in local.services_model : [
          for route in service.routing.urls : merge(
            {
              hostname = route.host
              service  = route.backend_url
            },
            startswith(route.backend_url, "https://") ? {
              origin_request = {
                no_tls_verify = true
              }
            } : {},
          )
          if(
            route.expose == "cloudflare" &&
            route.host != null
          )
        ]
        if service.target == server_key
      ]),
      [
        for route in server.routing.urls : merge(
          {
            hostname = route.url
            service  = route.backend_url
          },
          startswith(route.backend_url, "https://") ? {
            origin_request = {
              no_tls_verify = true
            }
          } : {},
        )
        if(
          route.expose == "cloudflare" &&
          try(local.dns_model_managed_zones_by_url[route.url], null) != null
        )
      ],
      [
        {
          service = "http_status:503"
        }
      ]
    )
  }

  # Flatten service WAF rules by zone. Each zone gets one cloudflare_ruleset
  # resource managing the http_request_firewall_custom phase.
  cloudflare_waf_rules_by_zone = {
    for rule in flatten([
      for service_key, service in local.services_model : [
        for route in service.routing.urls : [
          for rule in try(route.cloudflare_waf_rules, []) : {
            action      = rule.action
            description = try(rule.description, null)
            enabled     = try(rule.enabled, true)
            expression  = rule.expression
            zone        = route.zone
          }
        ]
        if route.zone != null
      ]
    ]) : rule.zone => rule...
  }
}

resource "cloudflare_account_token" "server_acme" {
  for_each = local.servers_by_feature.cloudflare_acme

  account_id = data.cloudflare_account.default.id
  name       = each.key

  policies = [
    {
      effect = "allow"
      permission_groups = [
        {
          id = one(data.cloudflare_account_api_token_permission_groups_list.dns_write.result).id
        }
      ]
      resources = jsonencode({
        "com.cloudflare.api.account.zone.${data.cloudflare_zone.all[local.defaults.domains.acme].zone_id}" = "*"
      })
    }
  ]
}

resource "cloudflare_account_token" "server_acme_legacy" {
  for_each = local.servers_by_feature.cloudflare_acme_legacy

  account_id = data.cloudflare_account.default.id
  name       = "${each.key}-zones"

  policies = [
    {
      effect = "allow"
      permission_groups = [
        {
          id = one(data.cloudflare_account_api_token_permission_groups_list.dns_write.result).id
        }
      ]
      resources = jsonencode({
        "com.cloudflare.api.account.zone.${data.cloudflare_zone.all[local.defaults.domains.external].zone_id}" = "*"
        "com.cloudflare.api.account.zone.${data.cloudflare_zone.all[local.defaults.domains.internal].zone_id}" = "*"
      })
    }
  ]
}

resource "cloudflare_dns_record" "all" {
  for_each = local.dns_render_records

  comment  = local.defaults.organization.managed_comment
  content  = each.value.content
  name     = each.value.name
  priority = each.value.priority
  proxied  = each.value.proxied
  ttl      = each.value.ttl
  type     = each.value.type
  zone_id  = data.cloudflare_zone.all[each.value.zone].zone_id
}

resource "cloudflare_ruleset" "rate_limiting" {
  for_each = local.cloudflare_rate_limiting_rules_by_zone

  description = local.defaults.organization.managed_comment
  kind        = "zone"
  name        = "default"
  phase       = "http_ratelimit"
  zone_id     = data.cloudflare_zone.all[each.key].zone_id

  rules = [
    for rule in each.value : {
      action      = rule.action
      description = rule.description
      enabled     = rule.enabled
      expression  = rule.expression
      ratelimit   = rule.ratelimit
    }
  ]
}

resource "cloudflare_ruleset" "waf" {
  for_each = local.cloudflare_waf_rules_by_zone

  description = local.defaults.organization.managed_comment
  kind        = "zone"
  name        = "default"
  phase       = "http_request_firewall_custom"
  zone_id     = data.cloudflare_zone.all[each.key].zone_id

  rules = [
    for rule in each.value : {
      action      = rule.action
      description = rule.description
      enabled     = rule.enabled
      expression  = rule.expression
    }
  ]
}

resource "cloudflare_zero_trust_access_application" "all" {
  for_each = local.cloudflare_access_applications

  account_id                = data.cloudflare_account.default.id
  auto_redirect_to_identity = try(each.value.access.auto_redirect_to_identity, false)
  name                      = try(each.value.access.name, each.value.access_index == 0 ? each.value.service.identity.title : "${each.value.service.identity.title} - ${title(each.value.access_id)}")
  session_duration          = try(each.value.access.session_duration, null)
  type                      = "self_hosted"

  allowed_idps = try(length(each.value.access.allowed_idps) > 0 ? [
    for alias in each.value.access.allowed_idps :
    local.cloudflare_access_idp_ids[alias]
  ] : null, null)

  destinations = [
    {
      type = "public"
      uri  = "${each.value.route.host}${try(each.value.access.path, "/*")}"
    }
  ]

  policies = [
    for i, policy in each.value.access.policies : {
      decision   = policy.decision
      exclude    = try(policy.exclude, [])
      include    = policy.include
      name       = try(policy.name, policy.decision == "allow" ? "Allow Authenticated" : policy.decision == "bypass" ? "Bypass" : "Deny")
      precedence = try(policy.precedence, i + 1)
      require    = try(policy.require, [])
    }
  ]
}

module "cloudflare_tunnel" {
  for_each = local.servers_by_feature.cloudflared
  source   = "./modules/cloudflare_tunnel"

  account_id = data.cloudflare_account.default.id
  ingress    = local.cloudflare_tunnel_ingress[each.key]
  name       = each.key
}
