locals {
  # 1Password fields store scalar values only. Field labels end in _rw when
  # 1Password can become source of truth (only `password` for now), and _ro
  # when OpenTofu remains source.

  onepassword_server_existing_fields = {
    for server_key, item in data.http.onepassword_server_item : server_key => {
      for field in try(jsondecode(item.response_body).fields, []) : field.id => try(field.value, "")
      if try(field.id, "") != "" && try(field.value, "") != ""
    }
  }

  # Non-null state fields per server, ready for 1Password STRING entries.
  onepassword_server_fields = {
    for server_key, server in local.servers : server_key => {
      for field_name, field_value in server.state.fields : field_name => field_value
      if field_value != null && field_value != ""
    }
  }

  onepassword_server_item_ids = {
    for server_key, item in data.http.onepassword_server_search : server_key => try(jsondecode(item.response_body)[0].id, null)
  }

  onepassword_server_item_payloads = {
    for server_key, server in local.servers : server_key => {
      category = "LOGIN"
      tags     = local.defaults.onepassword.vaults.servers.tags
      title    = server_key

      fields = concat(
        [
          {
            id      = "username"
            label   = "username_ro"
            purpose = "USERNAME"
            value   = server.identity.username
          }
        ],
        server.state.secrets.password != null ? [
          {
            id      = "password"
            label   = "password_rw"
            purpose = "PASSWORD"
            value   = server.state.secrets.password
          }
        ] : [],
        [
          for field_name, field_value in local.onepassword_server_fields[server_key] : {
            id    = field_name
            label = "${field_name}_ro"
            type  = "STRING"
            value = tostring(field_value)
          }
        ],
        [
          for field_name, field_value in local.onepassword_server_secrets[server_key] : {
            id    = field_name
            label = "${field_name}_ro"
            type  = "CONCEALED"
            value = tostring(field_value)
          }
          if field_name != "password"
        ],
      )

      urls = [
        for url_index, url_label in sort(keys(local.onepassword_server_urls[server_key])) : {
          href    = local.onepassword_server_urls[server_key][url_label]
          label   = url_label
          primary = url_index == 0
        }
      ]
      vault = {
        id = local.defaults.onepassword.vaults.servers.id
      }
    }
  }

  # Non-null state secrets per server, ready for 1Password CONCEALED entries.
  onepassword_server_secrets = {
    for server_key, server in local.servers : server_key => {
      for secret_name, secret_value in server.state.secrets : secret_name => secret_value
      if secret_value != null && secret_value != ""
    }
  }

  # Formatted URL items per server. Bare addresses from state.urls become
  # https://<host>[:<port>] — IPv6 gets brackets, port appended when not 443.
  onepassword_server_urls = {
    for server_key, server in local.servers : server_key => {
      for url_label, url_value in server.state.urls : url_label => format(
        "https://%s%s",
        can(cidrhost("${url_value}/128", 0)) ? "[${url_value}]" : url_value,
        server.networking.management_port != 443 ? ":${server.networking.management_port}" : ""
      )
      if url_value != null && url_value != ""
    }
  }

  onepassword_service_existing_fields = {
    for service_key, item in data.http.onepassword_service_item : service_key => {
      for field in try(jsondecode(item.response_body).fields, []) : field.id => try(field.value, "")
      if try(field.id, "") != "" && try(field.value, "") != ""
    }
  }

  onepassword_service_fields = {
    for service_key, service in local.services : service_key => {
      for field_name, field_value in service : field_name => field_value
      if(
        field_value != null &&
        field_value != false &&
        !can(regex(local.defaults.onepassword.url_field_pattern, field_name)) &&
        !contains(keys(local.defaults_service), field_name) &&
        can(tostring(field_value)) &&
        (
          # Manually supplied secrets sync even when empty so 1Password gets the
          # placeholder field for the operator to fill in on the first apply.
          field_value != "" ||
          contains(local.onepassword_service_manual_secret_names[service_key], field_name)
        )
      )
    }
  }

  onepassword_service_item_ids = {
    for service_key, item in data.http.onepassword_service_search : service_key => try(jsondecode(item.response_body)[0].id, null)
  }

  onepassword_service_item_payloads = {
    for service_key, service in local.onepassword_service_items : service_key => {
      category = "LOGIN"
      tags     = local.defaults.onepassword.vaults.services.tags
      title    = local.onepassword_service_item_titles[service_key]

      fields = concat(
        [
          {
            id      = "username"
            label   = "username_ro"
            purpose = "USERNAME"
            value   = local.services[service_key].identity.username
          }
        ],
        local.services[service_key].password_sensitive != null ? [
          {
            id      = "password"
            label   = "password_rw"
            purpose = "PASSWORD"
            value   = local.services[service_key].password_sensitive
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
        for url_index, url_field in sort(keys(local.onepassword_service_urls[service_key])) : {
          href    = local.onepassword_service_urls[service_key][url_field]
          label   = url_field
          primary = url_index == 0
        }
      ]
      vault = {
        id = local.defaults.onepassword.vaults.services.id
      }
    }
  }

  onepassword_service_item_titles = {
    for service_key, service in local.onepassword_service_items : service_key => "${service.identity.title} (${service.target})"
  }

  onepassword_service_items = {
    for service_key, service in local.services_model : service_key => service
    if anytrue([for feature_name, feature_enabled in service.features : tobool(feature_enabled) if can(tobool(feature_enabled))]) || length(service.features.secrets) > 0 || service.networking.scheme != null
  }

  # Secret fields with bootstrap_type == null are manually supplied in
  # 1Password; they should be synced even when the value is empty.
  onepassword_service_manual_secret_names = {
    for service_key, service in local.services : service_key => [
      for secret in service.features.secrets : "${secret.name}_sensitive"
      if try(secret.bootstrap_type, null) == null
    ]
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
    for service_key, service in local.services : service_key => {
      for field_name, field_value in service : field_name => startswith(field_value, "http://") || startswith(field_value, "https://") ? field_value : "https://${field_value}"
      if field_value != null && field_value != "" && field_value != false && can(regex(local.defaults.onepassword.url_field_pattern, field_name)) && can(tostring(field_value))
    }
  }
}

resource "restapi_object" "onepassword_server" {
  for_each = local.servers_model

  id_attribute            = "id"
  ignore_server_additions = true
  path                    = "/v1/vaults/${local.defaults.onepassword.vaults.servers.id}/items"
  provider                = restapi.onepassword
  read_path               = "/v1/vaults/${local.defaults.onepassword.vaults.servers.id}/items/{id}"
  update_data             = sensitive(jsonencode(merge(local.onepassword_server_item_payloads[each.key], { id = local.onepassword_server_item_ids[each.key] })))

  data = sensitive(jsonencode(local.onepassword_server_item_payloads[each.key]))
}

resource "restapi_object" "onepassword_service" {
  for_each = local.onepassword_service_items

  id_attribute            = "id"
  ignore_server_additions = true
  path                    = "/v1/vaults/${local.defaults.onepassword.vaults.services.id}/items"
  provider                = restapi.onepassword
  read_path               = "/v1/vaults/${local.defaults.onepassword.vaults.services.id}/items/{id}"
  update_data             = sensitive(jsonencode(merge(local.onepassword_service_item_payloads[each.key], { id = local.onepassword_service_item_ids[each.key] })))

  data = sensitive(jsonencode(local.onepassword_service_item_payloads[each.key]))
}

data "http" "onepassword_server_item" {
  for_each = {
    for server_key, item_id in local.onepassword_server_item_ids : server_key => item_id
    if item_id != null
  }

  url = "${var.onepassword_connect_url}/v1/vaults/${local.defaults.onepassword.vaults.servers.id}/items/${each.value}"

  request_headers = {
    "Authorization" = "Bearer ${var.onepassword_connect_token}"
    "Content-Type"  = "application/json"
  }
}

data "http" "onepassword_server_search" {
  for_each = local.servers_model

  url = "${var.onepassword_connect_url}/v1/vaults/${local.defaults.onepassword.vaults.servers.id}/items?filter=${urlencode("title eq \"${each.key}\"")}"

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

  url = "${var.onepassword_connect_url}/v1/vaults/${local.defaults.onepassword.vaults.services.id}/items/${each.value}"

  request_headers = {
    "Authorization" = "Bearer ${var.onepassword_connect_token}"
    "Content-Type"  = "application/json"
  }
}

data "http" "onepassword_service_search" {
  for_each = local.onepassword_service_items

  url = "${var.onepassword_connect_url}/v1/vaults/${local.defaults.onepassword.vaults.services.id}/items?filter=${urlencode("title eq \"${local.onepassword_service_item_titles[each.key]}\"")}"

  request_headers = {
    "Authorization" = "Bearer ${var.onepassword_connect_token}"
    "Content-Type"  = "application/json"
  }
}
