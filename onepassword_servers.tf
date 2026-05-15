# 1Password Connect search only returns item summaries, so item fetches are a
# second step gated by IDs found in the search calls.
data "http" "onepassword_server_item" {
  for_each = {
    for server_key, item_id in local.onepassword_server_existing_ids : server_key => item_id
    if item_id != null
  }

  request_headers = local.onepassword_connect_request_headers
  url             = "${var.onepassword_connect_url}/v1/vaults/${local.defaults.onepassword.vaults.servers.id}/items/${each.value}"
}

data "http" "onepassword_server_search" {
  for_each = local.servers_model

  request_headers = local.onepassword_connect_request_headers
  url             = "${var.onepassword_connect_url}/v1/vaults/${local.defaults.onepassword.vaults.servers.id}/items?filter=${urlencode("title eq \"${each.key}\"")}"
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

  onepassword_server_item_fields = {
    for server_key, server in local.servers : server_key => {
      for field in concat(
        server.identity.username != "" ? [
          {
            id      = "username"
            label   = "username"
            purpose = "USERNAME"
            value   = server.identity.username
          }
        ] : [],
        [
          for field_name, field_value in server.runtime.attributes : {
            id    = field_name
            label = "${field_name}_ro"
            type  = "STRING"
            value = tostring(field_value)
          }
          if field_value != null && field_value != ""
        ],
        [
          for field_name, field_config in server.credentials.fields : {
            for item_key, item_value in merge(
              {
                id    = field_name
                label = field_config.purpose == "PASSWORD" ? field_name : "${field_name}_${field_config.mode}"
                value = try(tostring(server.runtime.credentials[field_name]), "")
              },
              field_config.purpose != null ? {
                purpose = field_config.purpose
                } : {
                type = field_config.type
              },
            ) : item_key => item_value
            if item_value != null
          }
          if try(server.runtime.credentials[field_name], null) != null &&
          (try(server.runtime.credentials[field_name], "") != "" || field_config.mode == "rw")
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
        for label in sort(keys(server.runtime.urls)) : {
          href    = server.runtime.urls[label].href
          label   = server.runtime.urls[label].label
          primary = server.runtime.urls[label].href == server.urls.default.href
        }
        if label != "default"
      ]

      vault = {
        id = local.defaults.onepassword.vaults.servers.id
      }
    }
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
