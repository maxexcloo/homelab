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

data "cloudflare_account_api_token_permission_groups_list" "tunnel_read" {
  account_id = data.cloudflare_account.default.id
  max_items  = 1
  name       = "Cloudflare%20Tunnel%20Read"
  scope      = "com.cloudflare.api.account"
}

data "cloudflare_zero_trust_organization" "default" {
  account_id = data.cloudflare_account.default.id
}

data "cloudflare_zone" "all" {
  for_each = local.dns_input

  filter = {
    name = each.key
  }
}

locals {
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

  # Stable model-only service route inventory shared by Cloudflare features.
  _cloudflare_service_routes = merge([
    for service_key, service in module.services.model.services : {
      for route in service.routing.routes : jsonencode([service_key, route.host]) => {
        route       = route
        service     = service
        service_key = service_key
      }
      if route.host != null
    }
  ]...)

  # Routes are only added when backed by a managed DNS record. The
  # http_status:503 catch-all is required by Cloudflare Tunnel.
  _cloudflare_tunnel_ingress = {
    for server_key in keys(module.servers.model.by_feature.cloudflared) : server_key => concat(
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
            nonsensitive(module.services.render.context_base[rule.service_key]),
          ))
        },
      )
    ]
  }

  cloudflare_routes = {
    for route_key, route in local.dns_model_routes : route_key => route
    if route.expose == "cloudflare"
  }
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "server" {
  for_each = module.servers.model.by_feature.cloudflared

  account_id = data.cloudflare_account.default.id
  tunnel_id  = module.servers.infrastructure.cloudflare_tunnel_ids[each.key]

  config = {
    ingress = local._cloudflare_tunnel_ingress[each.key]

    warp_routing = {
      enabled = false
    }
  }
}

resource "cloudflare_zero_trust_access_identity_provider" "pocketid" {
  for_each = nonsensitive(module.services.integrations.pocketid.cloudflare_access_identity_providers)

  account_id = data.cloudflare_account.default.id
  name       = each.value.display_name
  type       = "oidc"

  config = {
    auth_url         = nonsensitive(module.services.integrations.pocketid.discovery.authorization_endpoint)
    certs_url        = nonsensitive(module.services.integrations.pocketid.discovery.jwks_uri)
    client_id        = nonsensitive(module.services.integrations.pocketid.cloudflare_access_clients[each.key].id)
    client_secret    = module.services.integrations.pocketid.cloudflare_access_clients[each.key].client_secret
    email_claim_name = "email"
    pkce_enabled     = true
    scopes           = ["openid", "profile", "email"]
    token_url        = nonsensitive(module.services.integrations.pocketid.discovery.token_endpoint)
  }
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
    cloudflare_zero_trust_access_identity_provider.pocketid[alias].id
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
