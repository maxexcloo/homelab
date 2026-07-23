data "http" "pocketid_discovery" {
  url = "${var.pocketid_url}/.well-known/openid-configuration"
}

locals {
  pocketid_cloudflare_access_identity_providers = {
    for alias, identity_provider in local.defaults.cloudflare.access.identity_providers : alias => identity_provider
    if identity_provider.provider == "pocketid"
  }

  pocketid_discovery = jsondecode(data.http.pocketid_discovery.response_body)
}

resource "pocketid_application_config" "default" {
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
  for_each = local.services_model_by_feature.oidc

  client_id    = each.key
  is_public    = try(each.value.data.oidc_is_public, false)
  launch_url   = each.value.urls.default.href
  name         = each.value.identity.title
  pkce_enabled = try(each.value.data.oidc_pkce_enabled, false)

  callback_urls = [
    for callback_url in each.value.data.oidc_callback_urls :
    startswith(callback_url, "/") ? "${each.value.urls.default.href}${callback_url}" : callback_url
  ]
}

moved {
  from = pocketid_client.service["auth-au-hsp"]
  to   = pocketid_client.service["oauth2-proxy-au-hsp"]
}

moved {
  from = pocketid_client.service["auth-au-truenas"]
  to   = pocketid_client.service["oauth2-proxy-au-truenas"]
}
