# 1Password Connect search only returns item summaries, so item fetches are a
# second step gated by IDs found in the search calls.
data "http" "onepassword_server_item" {
  for_each = local._onepassword_server_existing_items

  request_headers = local.onepassword_connect_request_headers
  url             = "${var.onepassword_connect_url}/v1/vaults/${local.defaults.onepassword.vaults.servers.id}/items/${each.value}"
}

data "http" "onepassword_server_search" {
  for_each = local.servers_model

  request_headers = local.onepassword_connect_request_headers
  url             = "${var.onepassword_connect_url}/v1/vaults/${local.defaults.onepassword.vaults.servers.id}/items?filter=${urlencode("title eq \"${each.key}\"")}"
}

locals {
  _onepassword_server_search_results = {
    for server_key, item in data.http.onepassword_server_search : server_key => jsondecode(item.response_body)
  }

  _onepassword_server_duplicate_items = [
    for server_key, items in local._onepassword_server_search_results : server_key
    if length(items) > 1
  ]

  _onepassword_server_existing_ids = {
    for server_key, items in local._onepassword_server_search_results : server_key => length(items) == 1 ? one(items).id : null
  }

  _onepassword_server_existing_items = {
    for server_key, item_id in local._onepassword_server_existing_ids : server_key => item_id
    if item_id != null
  }

  onepassword_server_existing_fields = {
    for server_key, item in data.http.onepassword_server_item : server_key => {
      for field in jsondecode(item.response_body).fields : field.id => try(field.value, "")
      if try(coalesce(field.value, ""), "") != ""
    }
  }

  _onepassword_server_item_fields = {
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
          if(
            field_value != null &&
            field_value != ""
          )
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
          if(
            try(server.runtime.credentials[field_name], null) != null &&
            (
              try(server.runtime.credentials[field_name], "") != "" ||
              field_config.mode == "rw"
            )
          )
        ],
      ) : field.label => field
    }
  }

  _onepassword_server_item_payloads = {
    for server_key, server in local.servers : server_key => {
      category = "LOGIN"
      id       = local._onepassword_server_existing_ids[server_key]
      tags     = local.defaults.onepassword.vaults.servers.tags
      title    = server_key

      fields = [
        for label in sort(keys(local._onepassword_server_item_fields[server_key])) :
        local._onepassword_server_item_fields[server_key][label]
      ]

      urls = [
        for label in sort(keys(server.runtime.urls)) : {
          href    = server.runtime.urls[label].href
          label   = server.runtime.urls[label].label
          primary = server.runtime.urls[label].href == try(server.runtime.urls.management.href, server.runtime.urls.internal.href)
        }
      ]

      vault = {
        id = local.defaults.onepassword.vaults.servers.id
      }
    }
  }
}

resource "restapi_object" "onepassword_server" {
  for_each = local.servers_model

  data                    = sensitive(jsonencode(local._onepassword_server_item_payloads[each.key]))
  id_attribute            = "id"
  ignore_server_additions = true
  path                    = "/v1/vaults/${local.defaults.onepassword.vaults.servers.id}/items"
  provider                = restapi.onepassword
  read_path               = "/v1/vaults/${local.defaults.onepassword.vaults.servers.id}/items/{id}"
  update_data             = sensitive(jsonencode(local._onepassword_server_item_payloads[each.key]))

  lifecycle {
    precondition {
      condition     = length(local._onepassword_server_duplicate_items) == 0
      error_message = "Multiple 1Password server items have the same title: ${join(", ", nonsensitive(local._onepassword_server_duplicate_items))}"
    }
  }
}
