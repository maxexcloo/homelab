data "http" "pocketid_discovery" {
  for_each = local._pocketid_integration_ready ? { default = true } : {}

  url = "${var.integrations.pocketid.url}/.well-known/openid-configuration"
}

locals {
  _pocketid_groups = {
    for group_name, group in local.defaults.pocketid.groups : group_name => group
    if local._pocketid_integration_ready
  }

  _pocketid_service_groups = {
    for service_key in local._pocketid_services : service_key => distinct(concat(
      local.defaults.pocketid.default_groups,
      local.services_model[service_key].identity.access_groups,
    ))
  }

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

  pocketid_provider_name = try(one([
    for service in values(local.services_model) : service.identity.title
    if service.identity.name == "pocket-id"
  ]), "Pocket ID")
}

resource "pocketid_group" "all" {
  for_each = local._pocketid_groups

  friendly_name = each.value.display_name
  name          = each.key
}

resource "pocketid_client" "cloudflare_access" {
  for_each = local.pocketid_cloudflare_access_identity_providers

  client_id    = "cloudflare-access-${each.key}"
  is_public    = false
  launch_url   = "https://${data.cloudflare_zero_trust_organization.default.auth_domain}"
  name         = each.value.client_name
  pkce_enabled = true

  allowed_user_groups = [
    for group_name in local.defaults.pocketid.default_groups :
    pocketid_group.all[group_name].id
  ]

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

  allowed_user_groups = [
    for group_name in local._pocketid_service_groups[each.key] :
    pocketid_group.all[group_name].id
  ]

  callback_urls = [
    for callback_url in local.services_model[each.key].data.oidc_callback_urls :
    startswith(callback_url, "/") ? "${local.services_model[each.key].urls.default.href}${callback_url}" : callback_url
  ]
}
