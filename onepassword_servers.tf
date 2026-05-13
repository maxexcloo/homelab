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
        for label in sort(keys(local.onepassword_server_item_urls[server_key])) : {
          href    = local.onepassword_server_item_urls[server_key][label].href
          label   = label
          primary = local.onepassword_server_item_urls[server_key][label].href == local.servers_model[server_key].url
        }
      ]

      vault = {
        id = local.defaults.onepassword.vaults.servers.id
      }
    }
  }

  onepassword_server_item_urls = {
    for server_key, server in local.servers : server_key => merge(
      {
        for url_label, url_value in server.state.urls : url_label => {
          href = format(
            "https://%s%s",
            can(cidrhost("${url_value}/128", 0)) ? "[${url_value}]" : url_value,
            server.networking.management_port != 443 ? ":${server.networking.management_port}" : ""
          )
          label   = url_label
          primary = false
        }
        if url_value != null && url_value != ""
      },
      {
        for url_label, url_value in server.state.urls : "${url_label}_ssh" => {
          href = format(
            "ssh://%s@%s%s",
            server.identity.username,
            can(cidrhost("${url_value}/128", 0)) ? "[${url_value}]" : url_value,
            server.networking.ssh_port != 22 ? ":${server.networking.ssh_port}" : ""
          )
          label   = "${url_label}_ssh"
          primary = false
        }
        if url_label != "management_address" && url_value != null && url_value != ""
      },
    )
  }

  onepassword_server_manual_secret_names = {
    for server_key, server in local.servers : server_key => toset([
      for secret in server.secrets : secret.name
      if secret.bootstrap_type == null
    ])
  }

  # Field labels end in _rw when 1Password can become source of truth (password,
  # operator-supplied secrets), and _ro when OpenTofu remains source.
  onepassword_server_rw_secret_names = {
    for server_key, server in local.servers : server_key => toset(concat(
      server.features.password ? ["password"] : [],
      [for secret in server.secrets : secret.name],
    ))
  }
}

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
