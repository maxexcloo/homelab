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
  _cloudflare_access_idp_ids = {
    for alias, identity_provider in local.defaults.cloudflare.access.identity_providers :
    alias => one([
      for provider in data.cloudflare_zero_trust_access_identity_providers.all.result : provider.id
      if provider.name == identity_provider.display_name
    ])
  }

  # Stable model-only service route inventory shared by Cloudflare features.
  _cloudflare_service_routes = merge([
    for service_key, service in local.services_model : {
      for route in service.routing.urls : jsonencode([service_key, route.host]) => {
        route       = route
        service     = service
        service_key = service_key
      }
      if route.host != null
    }
  ]...)

  cloudflare_routes = {
    for route_key, route in local.dns_model_routes : route_key => route
    if route.expose == "cloudflare"
  }

  # Natural identity separates the mutable display name from the routed
  # hostname and protected path that uniquely identify an Access application.
  _cloudflare_access_applications = {
    for item in flatten([
      for route_config in values(local._cloudflare_service_routes) : [
        for access in try(route_config.route.cloudflare_access, []) : merge(
          route_config,
          {
            access      = access
            access_path = try(access.path, "/*")
          },
        )
      ]
    ]) : jsonencode([item.service_key, item.route.host, item.access_path]) => item
  }

  # Flatten service rate limiting rules by zone. Each zone gets one
  # cloudflare_ruleset resource managing the http_ratelimit phase.
  _cloudflare_rate_limiting_rules_by_zone = {
    for rule in flatten([
      for route_config in values(local._cloudflare_service_routes) : [
        for rule in try(route_config.route.cloudflare_rate_limiting_rules, []) : {
          action      = rule.action
          description = try(rule.description, null)
          enabled     = try(rule.enabled, true)
          expression  = rule.expression
          ratelimit   = rule.ratelimit
          zone        = route_config.route.zone
        }
      ]
      if route_config.route.zone != null
    ]) : rule.zone => rule...
  }

  _cloudflare_routes_tunnel = {
    for route_key, route in local.cloudflare_routes : route_key => route
    if route.tunnel != null
  }

  # Flatten service WAF rules by zone. Each zone gets one cloudflare_ruleset
  # resource managing the http_request_firewall_custom phase.
  _cloudflare_waf_rules_model_by_zone = {
    for rule in flatten([
      for route_config in values(local._cloudflare_service_routes) : [
        for rule in try(route_config.route.cloudflare_waf_rules, []) : {
          action      = rule.action
          description = try(rule.description, null)
          enabled     = try(rule.enabled, true)
          expression  = rule.expression
          service_key = route_config.service_key
          zone        = route_config.route.zone
        }
      ]
      if route_config.route.zone != null
    ]) : rule.zone => rule...
  }

  _cloudflare_waf_rules_runtime_by_zone = {
    for zone, rules in local._cloudflare_waf_rules_model_by_zone : zone => [
      for rule in rules : merge(
        rule,
        {
          expression = sensitive(templatestring(
            rule.expression,
            local.services_render_context_base[rule.service_key],
          ))
        },
      )
    ]
  }

  # Routes are only added when backed by a managed DNS record. The
  # http_status:503 catch-all is required by Cloudflare Tunnel.
  _cloudflare_tunnel_ingress = {
    for server_key in keys(local.servers_model_by_feature.cloudflared) : server_key => concat(
      [
        for route in values(local._cloudflare_routes_tunnel) : merge(
          {
            hostname = route.hostname
            service  = route.tunnel.url
          },
          startswith(route.tunnel.url, "https://") ? {
            origin_request = {
              no_tls_verify = true
            }
          } : {},
        )
        if route.tunnel.server_key == server_key
      ],
      [
        {
          service = "http_status:503"
        }
      ]
    )
  }
}

resource "cloudflare_account_token" "server_acme" {
  for_each = local.servers_model_by_feature.cloudflare_acme

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
  for_each = local.servers_model_by_feature.cloudflare_acme_legacy

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
  for_each = local._cloudflare_rate_limiting_rules_by_zone

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
  for_each = local._cloudflare_waf_rules_model_by_zone

  description = local.defaults.organization.managed_comment
  kind        = "zone"
  name        = "default"
  phase       = "http_request_firewall_custom"
  zone_id     = data.cloudflare_zone.all[each.key].zone_id

  rules = [
    for rule in local._cloudflare_waf_rules_runtime_by_zone[each.key] : {
      action      = rule.action
      description = rule.description
      enabled     = rule.enabled
      expression  = rule.expression
    }
  ]
}

resource "cloudflare_zero_trust_access_application" "all" {
  for_each = local._cloudflare_access_applications

  account_id                = data.cloudflare_account.default.id
  auto_redirect_to_identity = try(each.value.access.auto_redirect_to_identity, false)
  name                      = each.value.access.name
  session_duration          = try(each.value.access.session_duration, null)
  type                      = "self_hosted"

  allowed_idps = try(length(each.value.access.allowed_idps) > 0 ? [
    for alias in each.value.access.allowed_idps :
    local._cloudflare_access_idp_ids[alias]
  ] : null, null)

  destinations = [
    {
      type = "public"
      uri  = "${each.value.route.host}${each.value.access_path}"
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
  for_each = local.servers_model_by_feature.cloudflared
  source   = "./modules/cloudflare_tunnel"

  account_id = data.cloudflare_account.default.id
  ingress    = local._cloudflare_tunnel_ingress[each.key]
  name       = each.key
}
