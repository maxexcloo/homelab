data "http" "pocketid_discovery" {
  for_each = local._pocketid_integration_ready ? { default = true } : {}

  url = "${var.integrations.pocketid.url}/.well-known/openid-configuration"
}

locals {
  _pocketid_services = {
    for service_key, service in local.services_input_targets :
    service_key => service_key
    if(
      local._pocketid_integration_ready &&
      service.features.oidc
    )
  }

  pocketid_cloudflare_access_identity_providers = {
    for alias, identity_provider in local.defaults.cloudflare.access.identity_providers : alias => identity_provider
    if(
      local._pocketid_integration_ready &&
      identity_provider.provider == "pocketid"
    )
  }

  pocketid_discovery = try(jsondecode(data.http.pocketid_discovery["default"].response_body), null)
}

resource "pocketid_application_config" "default" {
  for_each = local._pocketid_integration_ready ? { default = true } : {}

  emails_verified    = "true"
  require_user_email = "true"
}

resource "pocketid_client" "cloudflare_access" {
  for_each = local.pocketid_cloudflare_access_identity_providers

  client_id    = "cloudflare-access-${each.key}"
  is_public    = false
  launch_url   = "https://${data.cloudflare_zero_trust_organization.default.auth_domain}"
  name         = each.value.client_name
  pkce_enabled = true

  callback_urls = [
    "https://${data.cloudflare_zero_trust_organization.default.auth_domain}/cdn-cgi/access/callback",
  ]
}

resource "pocketid_client" "service" {
  for_each = local._pocketid_services

  client_id    = each.key
  is_public    = try(local.services_model[each.key].data.oidc_is_public, false)
  launch_url   = local.services_model[each.key].urls.default.href
  name         = local.services_model[each.key].identity.title
  pkce_enabled = try(local.services_model[each.key].data.oidc_pkce_enabled, false)

  callback_urls = [
    for callback_url in local.services_model[each.key].data.oidc_callback_urls :
    startswith(callback_url, "/") ? "${local.services_model[each.key].urls.default.href}${callback_url}" : callback_url
  ]
}
