data "http" "onepassword_service_item" {
  for_each = {
    for service_key, item_id in local.onepassword_service_existing_ids : service_key => item_id
    if item_id != null
  }

  url = "${var.onepassword_connect_url}/v1/vaults/${local.defaults.onepassword.vaults.services.id}/items/${each.value}"

  request_headers = {
    "Authorization" = "Bearer ${var.onepassword_connect_token}"
    "Content-Type"  = "application/json"
  }
}

data "http" "onepassword_service_search" {
  for_each = local.onepassword_service_items

  url = "${var.onepassword_connect_url}/v1/vaults/${local.defaults.onepassword.vaults.services.id}/items?filter=${urlencode("title eq \"${each.value.identity.title} (${each.value.target})\"")}"

  request_headers = {
    "Authorization" = "Bearer ${var.onepassword_connect_token}"
    "Content-Type"  = "application/json"
  }
}

locals {
  onepassword_service_credential_features = toset([
    "b2",
    "password",
    "pushover",
    "resend",
    "tailscale",
  ])

  onepassword_service_dashboard_urls = {
    for service_key, urls in local.onepassword_service_dashboard_urls_by_sort : service_key => [
      for sort_key in sort(keys(urls)) : urls[sort_key]
    ]
  }

  onepassword_service_dashboard_urls_by_sort = {
    for service_key, service in local.services : service_key => {
      for card_index, dashboard_card in local.services_render_template_context[service_key].service.dashboard :
      "${lower(dashboard_card.name)}:${format("%05d", card_index)}" => {
        href    = dashboard_card.href
        label   = dashboard_card.name
        primary = dashboard_card.href == service.url
      }
      if dashboard_card.href != null && dashboard_card.href != ""
      && !contains([for url in values(service.urls) : url.href], dashboard_card.href)
    }
  }

  onepassword_service_existing_fields = {
    for service_key, item in data.http.onepassword_service_item : service_key => {
      for field in try(jsondecode(item.response_body).fields, []) : field.id => try(field.value, "")
      if try(field.id, "") != "" && try(field.value, "") != ""
    }
  }

  onepassword_service_existing_ids = {
    for service_key, item in data.http.onepassword_service_search : service_key => try(jsondecode(item.response_body)[0].id, null)
  }

  onepassword_service_fqdn_urls = {
    for service_key, service in local.services : service_key => [
      for url_key in ["fqdn_external", "fqdn_internal"] : {
        href    = service.urls[url_key].href
        label   = service.urls[url_key].label
        primary = service.urls[url_key].href == service.url
      }
      if contains(keys(service.urls), url_key)
    ]
  }

  # Service fields use the same label-keyed shape as server fields, with _rw
  # labels reserved for values operators may maintain in 1Password.
  onepassword_service_item_fields = {
    for service_key, service in local.services : service_key => {
      for field in concat(
        [
          {
            id      = "username"
            label   = "username"
            purpose = "USERNAME"
            value   = service.identity.username
          }
        ],
        service.features.password ? [
          {
            id      = "password"
            label   = "password"
            purpose = "PASSWORD"
            value   = service.state.secrets.password
          }
        ] : [],
        [
          for field_name, field_value in service.state.fields : {
            id    = field_name
            label = "${field_name}_ro"
            type  = "STRING"
            value = tostring(field_value)
          }
          if field_value != null && field_value != ""
        ],
        [
          for secret_name, secret_value in service.state.secrets : {
            id    = secret_name
            label = "${secret_name}_${contains(local.onepassword_service_rw_secret_names[service_key], secret_name) ? "rw" : "ro"}"
            type  = "CONCEALED"
            value = tostring(secret_value)
          }
          if secret_name != "password" && secret_value != null && (
            secret_value != "" ||
            contains(local.onepassword_service_manual_secret_names[service_key], secret_name)
          )
        ],
      ) : field.label => field
    }
    if contains(keys(local.onepassword_service_items), service_key)
  }

  onepassword_service_item_payloads = {
    for service_key, service in local.services : service_key => {
      category = "LOGIN"
      id       = local.onepassword_service_existing_ids[service_key]
      tags     = local.defaults.onepassword.vaults.services.tags
      title    = "${service.identity.title} (${service.target})"

      fields = [
        for label in sort(keys(local.onepassword_service_item_fields[service_key])) :
        local.onepassword_service_item_fields[service_key][label]
      ]

      urls = concat(
        [
          for url_key in sort([
            for key in keys(service.urls) : key
            if !contains(["fqdn_external", "fqdn_internal"], key)
            ]) : {
            href    = service.urls[url_key].href
            label   = service.urls[url_key].label
            primary = service.urls[url_key].href == service.url
          }
        ],
        local.onepassword_service_dashboard_urls[service_key],
        local.onepassword_service_fqdn_urls[service_key],
      )

      vault = {
        id = local.defaults.onepassword.vaults.services.id
      }
    }
    if contains(keys(local.onepassword_service_items), service_key)
  }

  # Services that get a 1Password item: any with credential material to store.
  # Dashboard cards and routable URLs alone are not credentials. Iterates
  # services_model (no state) so the search/fetch HTTP calls don't depend on
  # the resources whose values they read.
  onepassword_service_items = {
    for service_key, service in local.services_model : service_key => service
    if service.identity.username != "" || length(service.secrets) > 0 || anytrue([
      for feature in local.onepassword_service_credential_features : try(tobool(service.features[feature]), false)
    ])
  }

  onepassword_service_manual_secret_names = {
    for service_key, service in local.services : service_key => toset([
      for secret in service.secrets : secret.name
      if secret.bootstrap_type == null
    ])
    if contains(keys(local.onepassword_service_items), service_key)
  }

  onepassword_service_rw_secret_names = {
    for service_key, service in local.services : service_key => toset(concat(
      service.features.password ? ["password"] : [],
      [for secret in service.secrets : secret.name],
    ))
    if contains(keys(local.onepassword_service_items), service_key)
  }
}

resource "restapi_object" "onepassword_service" {
  for_each = local.onepassword_service_items

  data                    = sensitive(jsonencode(local.onepassword_service_item_payloads[each.key]))
  id_attribute            = "id"
  ignore_server_additions = true
  path                    = "/v1/vaults/${local.defaults.onepassword.vaults.services.id}/items"
  provider                = restapi.onepassword
  read_path               = "/v1/vaults/${local.defaults.onepassword.vaults.services.id}/items/{id}"
  update_data             = sensitive(jsonencode(local.onepassword_service_item_payloads[each.key]))
}
