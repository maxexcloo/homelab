locals {
  # 1Password fields store scalar values only. Field labels end in _rw when
  # 1Password can become source of truth (password and operator-supplied
  # secrets), and _ro when OpenTofu remains source.

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

      urls = concat(
        [
          for url_index, url_label in sort(keys(local.onepassword_server_urls[server_key])) : {
            href    = local.onepassword_server_urls[server_key][url_label]
            label   = url_label
            primary = url_index == 0
          }
        ],
        [
          for url_label, url_value in {
            ssh_internal  = server.state.urls.fqdn_internal
            ssh_tailscale = server.state.urls.tailscale_address
          } : {
            href  = "ssh://${server.identity.username}@${url_value}"
            label = url_label
          }
          if url_value != null && url_value != ""
        ]
      )
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

  # Formatted URL items per server. Server management UIs are HTTPS-only;
  # IPv6 gets brackets, port appended when not 443.
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

  # Non-null state fields per service, ready for 1Password STRING entries.
  onepassword_service_fields = {
    for service_key, service in local.services : service_key => {
      for field_name, field_value in service.state.fields : field_name => field_value
      if field_value != null && field_value != ""
    }
  }

  onepassword_service_item_ids = {
    for service_key, item in data.http.onepassword_service_search : service_key => try(jsondecode(item.response_body)[0].id, null)
  }

  onepassword_service_item_payloads = {
    for service_key, service in local.services : service_key => {
      category = "LOGIN"
      tags     = local.defaults.onepassword.vaults.services.tags
      title    = local.onepassword_service_item_titles[service_key]

      fields = concat(
        [
          {
            id      = "username"
            label   = "username_ro"
            purpose = "USERNAME"
            value   = service.identity.username
          }
        ],
        service.state.secrets.password != null ? [
          {
            id      = "password"
            label   = "password_rw"
            purpose = "PASSWORD"
            value   = service.state.secrets.password
          }
        ] : [],
        [
          for field_name, field_value in local.onepassword_service_fields[service_key] : {
            id    = field_name
            label = "${field_name}_ro"
            type  = "STRING"
            value = tostring(field_value)
          }
        ],
        [
          for field_name, field_value in local.onepassword_service_secrets[service_key] : {
            id    = field_name
            label = "${field_name}_${contains(local.onepassword_service_read_write_secrets[service_key], field_name) ? "rw" : "ro"}"
            type  = "CONCEALED"
            value = tostring(field_value)
          }
          if field_name != "password"
        ],
      )

      urls = [
        for url_index, url_label in sort(keys(local.onepassword_service_urls[service_key])) : {
          href    = local.onepassword_service_urls[service_key][url_label]
          label   = url_label
          primary = url_index == 0
        }
      ]
      vault = {
        id = local.defaults.onepassword.vaults.services.id
      }
    }
    if contains(keys(local.onepassword_service_items), service_key)
  }

  onepassword_service_item_titles = {
    for service_key, service in local.onepassword_service_items : service_key => "${service.identity.title} (${service.target})"
  }

  # Services that get a 1Password item: any with a feature enabled, declared
  # secrets, or a backend scheme that produces accessible URLs. Iterates
  # services_model (no state) so the search/fetch HTTP calls don't depend on
  # the resources whose values they read.
  onepassword_service_items = {
    for service_key, service in local.services_model : service_key => service
    if anytrue([for feature_name, feature_enabled in service.features : tobool(feature_enabled) if can(tobool(feature_enabled))]) || length(service.features.secrets) > 0 || service.networking.scheme != null
  }

  # Secret field IDs that 1Password may overwrite (treated as `_rw`). Includes
  # the password field and every declared custom secret.
  onepassword_service_read_write_secrets = {
    for service_key, service in local.onepassword_service_items : service_key => concat(
      service.features.password ? ["password"] : [],
      [for secret in service.features.secrets : secret.name],
    )
  }

  # Non-null state secrets per service. Manually supplied secrets (declared
  # without bootstrap_type) sync even when empty so 1Password gets the
  # placeholder field for the operator to fill in on the first apply.
  onepassword_service_secrets = {
    for service_key, service in local.services : service_key => {
      for secret_name, secret_value in service.state.secrets : secret_name => secret_value
      if secret_value != null && (
        secret_value != "" ||
        contains([
          for secret in service.features.secrets : secret.name
          if try(secret.bootstrap_type, null) == null
        ], secret_name)
      )
    }
  }

  # Formatted URL items per service. Scheme follows networking.ssl.
  onepassword_service_urls = {
    for service_key, service in local.services : service_key => {
      for url_label, url_value in service.state.urls : url_label => format(
        "%s://%s",
        service.networking.ssl ? "https" : "http",
        url_value,
      )
      if url_value != null && url_value != ""
    }
  }
}

resource "restapi_object" "onepassword_server" {
  for_each = local.servers_model

  data         = sensitive(jsonencode(local.onepassword_server_item_payloads[each.key]))
  id_attribute = "id"
  path         = "/v1/vaults/${local.defaults.onepassword.vaults.servers.id}/items"
  provider     = restapi.onepassword
  read_path    = "/v1/vaults/${local.defaults.onepassword.vaults.servers.id}/items/{id}"
  update_data  = sensitive(jsonencode(merge(
    local.onepassword_server_item_payloads[each.key],
    {
      id = local.onepassword_server_item_ids[each.key]
    },
  )))
}

resource "restapi_object" "onepassword_service" {
  for_each = local.onepassword_service_items

  data         = sensitive(jsonencode(local.onepassword_service_item_payloads[each.key]))
  id_attribute = "id"
  path         = "/v1/vaults/${local.defaults.onepassword.vaults.services.id}/items"
  provider     = restapi.onepassword
  read_path    = "/v1/vaults/${local.defaults.onepassword.vaults.services.id}/items/{id}"
  update_data  = sensitive(jsonencode(merge(
    local.onepassword_service_item_payloads[each.key],
    {
      id = local.onepassword_service_item_ids[each.key]
    },
  )))
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
