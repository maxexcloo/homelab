locals {
  # 1Password fields store scalar values only. Field labels end in _rw when
  # 1Password can become source of truth, and _ro when OpenTofu remains source.
  onepassword_server_existing_fields = {
    for server_key, item in data.http.onepassword_server_item : server_key => {
      for field in try(jsondecode(item.response_body).fields, []) : field.id => try(field.value, "")
      if try(field.id, "") != "" && try(field.value, "") != ""
    }
  }

  onepassword_server_fields = {
    for server_key, server in local.servers_outputs_private : server_key => {
      for field_name, field_value in server : field_name => field_value
      if field_value != null && field_value != "" && field_value != false && !can(regex(local.defaults.onepassword.url_field_pattern, field_name)) && !contains(keys(local.defaults_server), field_name) && can(tostring(field_value))
    }
  }

  onepassword_server_item_ids = {
    for server_key, item in data.http.onepassword_server_search : server_key => try(jsondecode(item.response_body)[0].id, null)
  }

  onepassword_server_item_payloads = {
    for server_key, server in local.servers_model_desired : server_key => {
      category = "LOGIN"
      tags     = local.defaults.onepassword.tags.servers
      title    = server_key

      fields = concat(
        [
          {
            id      = "username"
            label   = "username_ro"
            purpose = "USERNAME"
            value   = local.servers_outputs_private[server_key].identity.username
          }
        ],
        local.servers_outputs_private[server_key].password_sensitive != null ? [
          {
            id      = "password"
            label   = "password_rw"
            purpose = "PASSWORD"
            value   = local.servers_outputs_private[server_key].password_sensitive
          }
        ] : [],
        [
          for field_name, field_value in local.onepassword_server_fields[server_key] : {
            id    = trimsuffix(field_name, "_sensitive")
            label = "${trimsuffix(field_name, "_sensitive")}_${contains(local.onepassword_server_read_write_fields[server_key], trimsuffix(field_name, "_sensitive")) ? "rw" : "ro"}"
            type  = endswith(field_name, "_sensitive") ? "CONCEALED" : "STRING"
            value = tostring(field_value)
          }
        ]
      )

      urls = [
        for url_index, url_field in concat(
          contains(keys(local.onepassword_server_urls[server_key]), "url_0") ? ["url_0"] : [],
          [
            for url_field in sort(keys(local.onepassword_server_urls[server_key])) : url_field
            if url_field != "url_0"
          ]
          ) : {
          href    = local.onepassword_server_urls[server_key][url_field]
          label   = url_field
          primary = contains(keys(local.onepassword_server_urls[server_key]), "url_0") ? url_field == "url_0" : url_index == 0
        }
      ]
      vault = {
        id = local.defaults.onepassword.vaults.servers
      }
    }
  }

  onepassword_server_read_write_fields = {
    for server_key, server in local.servers_model_desired : server_key => compact([
      server.features.password ? "password" : null
    ])
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

  onepassword_service_existing_fields = {
    for service_key, item in data.http.onepassword_service_item : service_key => {
      for field in try(jsondecode(item.response_body).fields, []) : field.id => try(field.value, "")
      if try(field.id, "") != "" && try(field.value, "") != ""
    }
  }

  onepassword_service_fields = {
    for service_key, service in local.services_outputs_private : service_key => {
      for field_name, field_value in service : field_name => field_value
      if field_value != null && field_value != false && !can(regex(local.defaults.onepassword.url_field_pattern, field_name)) && !contains(keys(local.defaults_service), field_name) && can(tostring(field_value)) && (
        field_value != "" ||
        contains([
          for secret in service.features.secrets : "${secret.name}_sensitive"
          if try(secret.bootstrap_type, null) == null
        ], field_name)
      )
    }
  }

  onepassword_service_item_ids = {
    for service_key, item in data.http.onepassword_service_search : service_key => try(jsondecode(item.response_body)[0].id, null)
  }

  onepassword_service_item_payloads = {
    for service_key, service in local.onepassword_service_items : service_key => {
      category = "LOGIN"
      tags     = local.defaults.onepassword.tags.services
      title    = local.onepassword_service_item_titles[service_key]

      fields = concat(
        [
          {
            id      = "username"
            label   = "username_ro"
            purpose = "USERNAME"
            value   = local.services_outputs_private[service_key].identity.username
          }
        ],
        local.services_outputs_private[service_key].password_sensitive != null ? [
          {
            id      = "password"
            label   = "password_rw"
            purpose = "PASSWORD"
            value   = local.services_outputs_private[service_key].password_sensitive
          }
        ] : [],
        [
          for field_name, field_value in local.onepassword_service_fields[service_key] : {
            id    = trimsuffix(field_name, "_sensitive")
            label = "${trimsuffix(field_name, "_sensitive")}_${contains(local.onepassword_service_read_write_fields[service_key], trimsuffix(field_name, "_sensitive")) ? "rw" : "ro"}"
            type  = endswith(field_name, "_sensitive") ? "CONCEALED" : "STRING"
            value = tostring(field_value)
          }
        ]
      )

      urls = [
        for url_index, url_field in concat(
          contains(keys(local.onepassword_service_urls[service_key]), "url_0") ? ["url_0"] : [],
          [
            for url_field in sort(keys(local.onepassword_service_urls[service_key])) : url_field
            if url_field != "url_0"
          ]
          ) : {
          href    = local.onepassword_service_urls[service_key][url_field]
          label   = url_field
          primary = contains(keys(local.onepassword_service_urls[service_key]), "url_0") ? url_field == "url_0" : url_index == 0
        }
      ]
      vault = {
        id = local.defaults.onepassword.vaults.services
      }
    }
  }

  onepassword_service_item_titles = {
    for service_key, service in local.onepassword_service_items : service_key => "${service.identity.title} (${service.target})"
  }

  onepassword_service_items = {
    for service_key, service in local.services_model_desired : service_key => service
    if anytrue([for feature_name, feature_enabled in service.features : tobool(feature_enabled) if can(tobool(feature_enabled))]) || length(service.features.secrets) > 0 || service.networking.scheme != null
  }

  onepassword_service_read_write_fields = {
    for service_key, service in local.onepassword_service_items : service_key => concat(
      service.features.password ? ["password"] : [],
      [
        for secret in service.features.secrets : secret.name
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

  id_attribute            = "id"
  ignore_server_additions = true
  path                    = "/v1/vaults/${local.defaults.onepassword.vaults.servers}/items"
  provider                = restapi.onepassword
  read_path               = "/v1/vaults/${local.defaults.onepassword.vaults.servers}/items/{id}"
  update_data             = sensitive(jsonencode(merge(local.onepassword_server_item_payloads[each.key], { id = local.onepassword_server_item_ids[each.key] })))

  data = sensitive(jsonencode(local.onepassword_server_item_payloads[each.key]))
}

resource "restapi_object" "onepassword_service" {
  for_each = local.onepassword_service_items

  id_attribute            = "id"
  ignore_server_additions = true
  path                    = "/v1/vaults/${local.defaults.onepassword.vaults.services}/items"
  provider                = restapi.onepassword
  read_path               = "/v1/vaults/${local.defaults.onepassword.vaults.services}/items/{id}"
  update_data             = sensitive(jsonencode(merge(local.onepassword_service_item_payloads[each.key], { id = local.onepassword_service_item_ids[each.key] })))

  data = sensitive(jsonencode(local.onepassword_service_item_payloads[each.key]))
}

data "http" "onepassword_server_item" {
  for_each = {
    for server_key, item_id in local.onepassword_server_item_ids : server_key => item_id
    if item_id != null
  }

  url = "${var.onepassword_connect_url}/v1/vaults/${local.defaults.onepassword.vaults.servers}/items/${each.value}"

  request_headers = {
    "Authorization" = "Bearer ${var.onepassword_connect_token}"
    "Content-Type"  = "application/json"
  }
}

data "http" "onepassword_server_search" {
  for_each = local.servers_model_desired

  url = "${var.onepassword_connect_url}/v1/vaults/${local.defaults.onepassword.vaults.servers}/items?filter=${urlencode("title eq \"${each.key}\"")}"

  request_headers = {
    "Authorization" = "Bearer ${var.onepassword_connect_token}"
    "Content-Type"  = "application/json"
  }
}

data "http" "onepassword_service_item" {
  for_each = {
    for service_key, item_id in local.onepassword_service_item_ids : service_key => item_id
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
