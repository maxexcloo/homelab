# 1Password Connect search only returns item summaries, so item fetches are a
# second step gated by IDs found in the search calls.
data "http" "onepassword_server_item" {
  for_each = {
    for server_key, item_id in local.onepassword_server_existing_ids : server_key => item_id
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
  onepassword_server_existing_fields = {
    for server_key, item in data.http.onepassword_server_item : server_key => {
      for field in try(jsondecode(item.response_body).fields, []) : field.id => try(field.value, "")
      if try(field.id, "") != "" && try(field.value, "") != ""
    }
  }

  onepassword_server_existing_ids = {
    for server_key, item in data.http.onepassword_server_search : server_key => try(jsondecode(item.response_body)[0].id, null)
  }

  # Keying fields by their final 1Password label gives deterministic ordering
  # and avoids scanning the same field list repeatedly while building payloads.
  onepassword_server_item_fields = {
    for server_key, server in local.servers : server_key => {
      for field in concat(
        [
          {
            id      = "username"
            label   = "username"
            purpose = "USERNAME"
            value   = server.identity.username
          }
        ],
        server.features.password ? [
          {
            id      = "password"
            label   = "password"
            purpose = "PASSWORD"
            value   = server.state.secrets.password
          }
        ] : [],
        [
          for field_name, field_value in server.state.fields : {
            id    = field_name
            label = "${field_name}_ro"
            type  = "STRING"
            value = tostring(field_value)
          }
          if field_value != null && field_value != ""
        ],
        # Manually supplied secrets (no bootstrap_type) sync even when empty so
        # 1Password gets the placeholder for the operator to fill in.
        [
          for secret_name, secret_value in server.state.secrets : {
            id    = secret_name
            label = "${secret_name}_${contains(local.onepassword_server_rw_secret_names[server_key], secret_name) ? "rw" : "ro"}"
            type  = "CONCEALED"
            value = tostring(secret_value)
          }
          if secret_name != "password" && secret_value != null && (
            secret_value != "" ||
            contains(local.onepassword_server_manual_secret_names[server_key], secret_name)
          )
        ],
      ) : field.label => field
    }
  }

  # Field labels end in _rw when 1Password can become source of truth (password,
  # operator-supplied secrets), and _ro when OpenTofu remains source.
  onepassword_server_item_payloads = {
    for server_key, server in local.servers : server_key => {
      category = "LOGIN"
      id       = local.onepassword_server_existing_ids[server_key]
      tags     = local.defaults.onepassword.vaults.servers.tags
      title    = server_key

      fields = [
        for label in sort(keys(local.onepassword_server_item_fields[server_key])) :
        local.onepassword_server_item_fields[server_key][label]
      ]

      urls = [
        for url in local.onepassword_server_item_urls[server_key] : {
          href    = url.href
          label   = url.label
          primary = url.href == local.servers_model[server_key].url
        }
      ]

      vault = {
        id = local.defaults.onepassword.vaults.servers.id
      }
    }
  }

  onepassword_server_item_urls = {
    for server_key, server in local.servers : server_key => concat(
      [
        for url_label, url_value in server.state.urls : {
          href = format(
            "https://%s%s",
            can(cidrhost("${url_value}/128", 0)) ? "[${url_value}]" : url_value,
            server.networking.management_port != 443 ? ":${server.networking.management_port}" : ""
          )
          label = url_label
        }
        if url_value != null && url_value != ""
      ],
      [
        for url_label, url_value in {
          ssh_private_address   = server.state.urls.private_address
          ssh_tailscale_address = server.state.urls.tailscale_address
          } : {
          href  = "ssh://${server.identity.username}@${url_value}"
          label = url_label
        }
        if url_value != null && url_value != ""
      ],
    )
  }

  # Secrets without a bootstrap_type are manually filled by an operator in
  # 1Password and must sync even when the value is still empty.
  onepassword_server_manual_secret_names = {
    for server_key, server in local.servers : server_key => toset([
      for secret in server.secrets : secret.name
      if secret.bootstrap_type == null
    ])
  }

  onepassword_server_rw_secret_names = {
    for server_key, server in local.servers : server_key => toset(concat(
      server.features.password ? ["password"] : [],
      [for secret in server.secrets : secret.name],
    ))
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
        # Manually supplied secrets (no bootstrap_type) sync even when empty so
        # 1Password gets the placeholder for the operator to fill in.
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
          for url in values(service.urls) : {
            href    = url.href
            label   = url.label
            primary = url.href == service.url
          }
        ],
        [
          for dashboard_card in local.services_render_context[service_key].service.dashboard : {
            href    = dashboard_card.href
            label   = dashboard_card.name
            primary = dashboard_card.href == service.url
          }
          if dashboard_card.href != null && dashboard_card.href != ""
          && !contains([for url in values(service.urls) : url.href], dashboard_card.href)
        ],
      )

      vault = {
        id = local.defaults.onepassword.vaults.services.id
      }
    }
    if contains(keys(local.onepassword_service_items), service_key)
  }

  # Services that get a 1Password item: any with a feature enabled, declared
  # secrets, or a backend scheme that produces accessible URLs. Iterates
  # services_model (no state) so the search/fetch HTTP calls don't depend on
  # the resources whose values they read.
  onepassword_service_items = {
    for service_key, service in local.services_model : service_key => service
    if anytrue([for feature_enabled in values(service.features) : tobool(feature_enabled) if can(tobool(feature_enabled))]) || length(service.secrets) > 0 || length(service.dashboard) > 0 || service.routing.scheme != null
  }

  # Secrets without a bootstrap_type are manually filled by an operator in
  # 1Password and must sync even when the value is still empty.
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

# The REST resource owns item creation/update while existing 1Password fields
# are read back through Connect before payload construction.
resource "restapi_object" "onepassword_server" {
  for_each = local.servers_model

  data                    = sensitive(jsonencode(local.onepassword_server_item_payloads[each.key]))
  id_attribute            = "id"
  ignore_server_additions = true
  path                    = "/v1/vaults/${local.defaults.onepassword.vaults.servers.id}/items"
  provider                = restapi.onepassword
  read_path               = "/v1/vaults/${local.defaults.onepassword.vaults.servers.id}/items/{id}"
  update_data             = sensitive(jsonencode(local.onepassword_server_item_payloads[each.key]))
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
