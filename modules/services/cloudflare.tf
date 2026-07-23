data "cloudflare_zero_trust_organization" "default" {
  account_id = var.integrations.cloudflare.account_id
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

  # Stable model-only service route inventory shared by Cloudflare features.
  _cloudflare_service_routes = merge([
    for service_key, service in local.services_model : {
      for route in service.routing.routes : jsonencode([service_key, route.host]) => {
        route       = route
        service     = service
        service_key = service_key
      }
      if route.host != null
    }
  ]...)

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
          # The template context is broadly sensitive; preserve sensitivity
          # because a WAF expression may interpolate a credential.
          expression = sensitive(templatestring(
            rule.expression,
            nonsensitive(local.services_render_context_base[rule.service_key]),
          ))
        },
      )
    ]
  }
}

resource "cloudflare_ruleset" "rate_limiting" {
  for_each = local._cloudflare_rate_limiting_rules_by_zone

  description = local.defaults.organization.managed_comment
  kind        = "zone"
  name        = "default"
  phase       = "http_ratelimit"
  zone_id     = var.integrations.cloudflare.zone_ids[each.key]

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
  zone_id     = var.integrations.cloudflare.zone_ids[each.key]

  rules = [
    for rule in local._cloudflare_waf_rules_runtime_by_zone[each.key] : {
      action      = rule.action
      description = rule.description
      enabled     = rule.enabled
      expression  = rule.expression
    }
  ]
}

resource "cloudflare_zero_trust_access_identity_provider" "pocketid" {
  for_each = nonsensitive(local.pocketid_cloudflare_access_identity_providers)

  account_id = var.integrations.cloudflare.account_id
  name       = each.value.display_name
  type       = "oidc"

  config = {
    auth_url         = nonsensitive(local.pocketid_discovery.authorization_endpoint)
    certs_url        = nonsensitive(local.pocketid_discovery.jwks_uri)
    client_id        = nonsensitive(pocketid_client.cloudflare_access[each.key].id)
    client_secret    = pocketid_client.cloudflare_access[each.key].client_secret
    email_claim_name = "email"
    pkce_enabled     = true
    scopes           = ["openid", "profile", "email"]
    token_url        = nonsensitive(local.pocketid_discovery.token_endpoint)
  }
}

resource "cloudflare_zero_trust_access_application" "all" {
  for_each = local._cloudflare_access_applications

  account_id                = var.integrations.cloudflare.account_id
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
