locals {
  # 1Password fields store scalar values only. Empty/default fields are skipped,
  # *_sensitive fields become concealed values, and URL-like fields become item URLs.
  onepassword_server_fields = {
    for server_key, server in local.servers_outputs_private : server_key => {
      for field_name, field_value in server : field_name => field_value
      if field_value != null && field_value != "" && field_value != false && !can(regex(local.defaults.onepassword.url_field_pattern, field_name)) && !contains(keys(local.defaults_server), field_name) && can(tostring(field_value))
    }
  }

  onepassword_server_url_fields = {
    for server_key, server in local.servers_outputs_private : server_key => concat(
      contains(keys(local.onepassword_server_urls[server_key]), "url_0") ? ["url_0"] : [],
      [
        for url_field in sort(keys(local.onepassword_server_urls[server_key])) : url_field
        if url_field != "url_0"
      ]
    )
  }

  onepassword_server_urls = {
    for server_key, server in local.servers_outputs_private : server_key => merge(
      {
        for field_name, field_value in server : field_name => format(
          "https://%s%s",
          can(cidrhost("${field_value}/128", 0)) ? "[${field_value}]" : field_value,
          server.networking.management_port != 443 ? ":${server.networking.management_port}" : ""
        )
        if field_value != null && field_value != "" && field_value != false && can(regex(local.defaults.onepassword.url_field_pattern, field_name)) && can(tostring(field_value))
      },
      server.networking.management_address != "" ? {
        management_address = format(
          "https://%s%s",
          can(cidrhost("${server.networking.management_address}/128", 0)) ? "[${server.networking.management_address}]" : server.networking.management_address,
          server.networking.management_port != 443 ? ":${server.networking.management_port}" : ""
        )
      } : {}
    )
  }

  onepassword_service_fields = {
    for service_key, service in local.services_outputs_private : service_key => {
      for field_name, field_value in service : field_name => field_value
      if field_value != null && field_value != "" && field_value != false && !can(regex(local.defaults.onepassword.url_field_pattern, field_name)) && !contains(keys(local.defaults_service), field_name) && can(tostring(field_value))
    }
  }

  onepassword_service_existing_fields = {
    for service_key, item in local.onepassword_service_existing_items : service_key => {
      for field in try(item.fields, []) : field.id => try(field.value, "")
      if try(field.id, "") != "" && try(field.value, "") != ""
    }
  }

  onepassword_service_existing_item_ids = {
    for service_key, item in data.http.onepassword_service_search : service_key => try(jsondecode(item.response_body)[0].id, null)
  }

  onepassword_service_existing_items = {
    for service_key, item in data.http.onepassword_service_item : service_key => jsondecode(item.response_body)
  }

  onepassword_service_external_secret_fields = {
    for service_key, service in local.onepassword_service_items : service_key => {
      for secret in service.features.secrets : secret.name => try(local.onepassword_service_existing_fields[service_key][secret.name], "")
      if secret.type == "external"
    }
  }

  onepassword_service_items = {
    for service_key, service in local.services_model_desired : service_key => service
    if anytrue([for feature_name, feature_enabled in service.features : tobool(feature_enabled) if can(tobool(feature_enabled))]) || length(service.features.secrets) > 0 || service.networking.scheme != null
  }

  onepassword_service_item_titles = {
    for service_key, service in local.onepassword_service_items : service_key => "${service.identity.title} (${service.target})"
  }

  onepassword_service_url_fields = {
    for service_key, service in local.services_outputs_private : service_key => concat(
      contains(keys(local.onepassword_service_urls[service_key]), "url_0") ? ["url_0"] : [],
      [
        for url_field in sort(keys(local.onepassword_service_urls[service_key])) : url_field
        if url_field != "url_0"
      ]
    )
  }

  onepassword_service_urls = {
    for service_key, service in local.services_outputs_private : service_key => {
      for field_name, field_value in service : field_name => startswith(field_value, "http://") || startswith(field_value, "https://") ? field_value : "https://${field_value}"
      if field_value != null && field_value != "" && field_value != false && can(regex(local.defaults.onepassword.url_field_pattern, field_name)) && can(tostring(field_value))
    }
  }
}

resource "restapi_object" "onepassword_server" {
  for_each = local.servers_model_desired

  id_attribute              = "id"
  ignore_all_server_changes = true
  path                      = "/v1/vaults/${local.defaults.onepassword.vaults.servers}/items"
  provider                  = restapi.onepassword
  read_path                 = "/v1/vaults/${local.defaults.onepassword.vaults.servers}/items"

  data = sensitive(jsonencode({
    category = "LOGIN"
    fields = concat(
      [
        {
          id      = "username"
          purpose = "USERNAME"
          value   = local.servers_outputs_private[each.key].identity.username
        }
      ],
      local.servers_outputs_private[each.key].password_sensitive != null ? [
        {
          id      = "password"
          purpose = "PASSWORD"
          value   = local.servers_outputs_private[each.key].password_sensitive
        }
      ] : [],
      [
        for field_name, field_value in local.onepassword_server_fields[each.key] : {
          id    = trimsuffix(field_name, "_sensitive")
          label = trimsuffix(field_name, "_sensitive")
          type  = endswith(field_name, "_sensitive") ? "CONCEALED" : "STRING"
          value = tostring(field_value)
        }
      ]
    )
    tags  = local.defaults.onepassword.tags.servers
    title = each.key
    urls = [
      for url_index, url_field in local.onepassword_server_url_fields[each.key] : {
        href    = local.onepassword_server_urls[each.key][url_field]
        label   = url_field
        primary = contains(local.onepassword_server_url_fields[each.key], "url_0") ? url_field == "url_0" : url_index == 0
      }
    ]
    vault = {
      id = local.defaults.onepassword.vaults.servers
    }
  }))

  read_search = {
    query_string = "filter=${urlencode("title eq \"${each.key}\"")}"
    search_key   = "title"
    search_value = each.key
  }

}

resource "restapi_object" "onepassword_service" {
  for_each = local.onepassword_service_items

  id_attribute              = "id"
  ignore_all_server_changes = true
  path                      = "/v1/vaults/${local.defaults.onepassword.vaults.services}/items"
  provider                  = restapi.onepassword
  read_path                 = "/v1/vaults/${local.defaults.onepassword.vaults.services}/items"

  data = sensitive(jsonencode({
    category = "LOGIN"
    fields = concat(
      [
        {
          id      = "username"
          purpose = "USERNAME"
          value   = local.services_outputs_private[each.key].identity.username
        }
      ],
      local.services_outputs_private[each.key].password_sensitive != null ? [
        {
          id      = "password"
          purpose = "PASSWORD"
          value   = local.services_outputs_private[each.key].password_sensitive
        }
      ] : [],
      [
        for field_name, field_value in local.onepassword_service_external_secret_fields[each.key] : {
          id    = field_name
          label = field_name
          type  = "CONCEALED"
          value = field_value
        }
        if !contains(keys(local.onepassword_service_fields[each.key]), "${field_name}_sensitive")
      ],
      [
        for field_name, field_value in local.onepassword_service_fields[each.key] : {
          id    = trimsuffix(field_name, "_sensitive")
          label = trimsuffix(field_name, "_sensitive")
          type  = endswith(field_name, "_sensitive") ? "CONCEALED" : "STRING"
          value = tostring(field_value)
        }
      ]
    )
    tags  = local.defaults.onepassword.tags.services
    title = local.onepassword_service_item_titles[each.key]
    urls = [
      for url_index, url_field in local.onepassword_service_url_fields[each.key] : {
        href    = local.onepassword_service_urls[each.key][url_field]
        label   = url_field
        primary = contains(local.onepassword_service_url_fields[each.key], "url_0") ? url_field == "url_0" : url_index == 0
      }
    ]
    vault = {
      id = local.defaults.onepassword.vaults.services
    }
  }))

  read_search = {
    query_string = "filter=${urlencode("title eq \"${local.onepassword_service_item_titles[each.key]}\"")}"
    search_key   = "title"
    search_value = local.onepassword_service_item_titles[each.key]
  }

}

data "http" "onepassword_service_item" {
  for_each = {
    for service_key, item_id in local.onepassword_service_existing_item_ids : service_key => item_id
    if item_id != null
  }

  url = "${var.onepassword_connect_url}/v1/vaults/${local.defaults.onepassword.vaults.services}/items/${each.value}"

  request_headers = {
    "Authorization" = "Bearer ${var.onepassword_connect_token}"
    "Content-Type"  = "application/json"
  }
}

data "http" "onepassword_service_search" {
  for_each = local.onepassword_service_items

  url = "${var.onepassword_connect_url}/v1/vaults/${local.defaults.onepassword.vaults.services}/items?filter=${urlencode("title eq \"${local.onepassword_service_item_titles[each.key]}\"")}"

  request_headers = {
    "Authorization" = "Bearer ${var.onepassword_connect_token}"
    "Content-Type"  = "application/json"
  }
}
