locals {
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
          if try(tostring(field_value), "") != ""
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
      tags     = try(local.defaults.onepassword.vaults.servers.tags, [])
      title    = "${server.identity.title} (${server_key})"

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
    }
  }

  _onepassword_server_titles = {
    for server_key, server in local.servers_model :
    server_key => "${server.identity.title} (${server_key})"
  }

  onepassword_server_existing_fields = module.onepassword.existing_fields
}

module "onepassword" {
  source = "../onepassword"

  connect_url     = var.integrations.onepassword.connect_url
  enabled         = local._onepassword_integration_ready
  payloads        = local._onepassword_server_item_payloads
  request_headers = var.integrations.onepassword.request_headers
  titles          = local._onepassword_server_titles
  vault_id        = try(local.defaults.onepassword.vaults.servers.id, "disabled")

  providers = {
    restapi = restapi.onepassword
  }
}
