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
  onepassword_service_dashboard_urls = {
    for service_key, service in local.services : service_key => values({
      for card_index, dashboard_card in local.services_render_template_context[service_key].service.dashboard :
      "${lower(try(dashboard_card.name, ""))}:${format("%05d", card_index)}" => {
        href    = try(dashboard_card.href, null)
        label   = try(dashboard_card.name, null)
        primary = try(dashboard_card.href, null) == service.urls.default.href
      }
      if try(dashboard_card.name, "") != ""
      && try(dashboard_card.href, "") != ""
      && !contains([for url in values(service.urls) : url.href], try(dashboard_card.href, ""))
    })
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

  onepassword_service_host_urls = {
    for service_key, service in local.services : service_key => [
      for url_key in ["external", "internal"] : {
        href    = service.urls[url_key].href
        label   = service.urls[url_key].label
        primary = service.urls[url_key].href == service.urls.default.href
      }
      if contains(keys(service.urls), url_key)
    ]
  }

  onepassword_service_item_fields = {
    for service_key, service in local.services : service_key => {
      for field in concat(
        service.identity.username != "" ? [
          {
            id      = "username"
            label   = "username"
            purpose = "USERNAME"
            value   = service.identity.username
          }
        ] : [],
        [
          for field_name, field_value in service.runtime.attributes : {
            id    = field_name
            label = "${field_name}_ro"
            type  = "STRING"
            value = tostring(field_value)
          }
          if field_value != null && field_value != ""
        ],
        [
          for field_name, field_config in service.credentials.fields : {
            for item_key, item_value in merge(
              {
                id    = field_name
                label = field_config.purpose == "PASSWORD" ? field_name : "${field_name}_${field_config.mode}"
                value = try(tostring(service.runtime.credentials[field_name]), "")
              },
              field_config.purpose != null ? {
                purpose = field_config.purpose
                } : {
                type = field_config.type
              },
            ) : item_key => item_value
            if item_value != null
          }
          if try(service.runtime.credentials[field_name], null) != null &&
          (try(service.runtime.credentials[field_name], "") != "" || field_config.mode == "rw")
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
            if !contains(["default", "external", "internal"], key)
            ]) : {
            href    = service.urls[url_key].href
            label   = service.urls[url_key].label
            primary = service.urls[url_key].href == service.urls.default.href
          }
        ],
        local.onepassword_service_dashboard_urls[service_key],
        local.onepassword_service_host_urls[service_key],
      )

      vault = {
        id = local.defaults.onepassword.vaults.services.id
      }
    }
    if contains(keys(local.onepassword_service_items), service_key)
  }

  # Services that get a 1Password item: any with credential material to store.
  # Dashboard cards and routable URLs alone are not credentials. Iterates
  # services_model (no runtime) so the search/fetch HTTP calls don't depend on
  # the resources whose values they read.
  onepassword_service_items = {
    for service_key, service in local.services_model : service_key => service
    if service.identity.username != "" || length(service.credentials.fields) > 0
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
