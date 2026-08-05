locals {
  _onepassword_server_field_names = {
    for server_key, server in local.servers_model : server_key => toset([
      for field_name, field in server.credentials.fields : field_name
      if field.mode == "rw"
    ])
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
            label = field_name
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
                label = field_name

                value = (
                  field_config.mode == "rw" &&
                  !can(server.credentials.generated[field_name])
                ) ? "" : try(tostring(server.runtime.credentials[field_name]), "")
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

  _onepassword_server_managed_fields = {
    for server_key, server in local.servers : server_key => sort(tolist(setintersection(
      toset(keys(local._onepassword_server_item_fields[server_key])),
      toset(concat(
        server.identity.username != "" ? ["username"] : [],
        keys(server.runtime.attributes),
        [
          for field_name, field in server.credentials.fields : field_name
          if field.mode == "ro" || can(server.credentials.generated[field_name])
        ],
      )),
    )))
  }

  _onepassword_server_missing_titles = {
    for server_key in module.onepassword.missing_items :
    server_key => local._onepassword_server_titles[server_key]
  }

  _onepassword_server_placeholder_fields = {
    for server_key in keys(local._onepassword_server_item_fields) : server_key => sort(tolist(setsubtract(
      toset(keys(local._onepassword_server_item_fields[server_key])),
      toset(local._onepassword_server_managed_fields[server_key]),
    )))
  }

  _onepassword_server_titles = {
    for server_key, server in local.servers_model :
    server_key => "${server.identity.title} (${server_key})"
  }

  onepassword_server_existing_fields = module.onepassword.existing_fields

  onepassword_server_item_ids = {
    for server_key in keys(local._onepassword_server_titles) : server_key => (
      can(module.onepassword.item_ids[server_key])
      ? module.onepassword.item_ids[server_key]
      : module.onepassword_created.item_ids[server_key]
    )
  }

  onepassword_server_manifest = {
    vault_id = local.defaults.onepassword.vaults.servers.id

    items = {
      for server_key, payload in local._onepassword_server_item_payloads : server_key => {
        managed_fields     = local._onepassword_server_managed_fields[server_key]
        managed_urls       = [for url in payload.urls : url.label]
        payload            = payload
        placeholder_fields = local._onepassword_server_placeholder_fields[server_key]
      }
    }
  }
}

module "onepassword" {
  source = "../onepassword"

  field_names = local._onepassword_server_field_names
  titles      = local._onepassword_server_titles
  vault_id    = try(local.defaults.onepassword.vaults.servers.id, "disabled")
}

resource "terraform_data" "onepassword" {
  triggers_replace = [nonsensitive(sha256(jsonencode(local.onepassword_server_manifest)))]

  provisioner "local-exec" {
    command = "uv run ${path.root}/scripts/reconcile_onepassword.py --write"

    environment = {
      ONEPASSWORD_MANIFEST = jsonencode({ vaults = { servers = local.onepassword_server_manifest } })
    }
  }
}

module "onepassword_created" {
  source = "../onepassword"

  titles   = local._onepassword_server_missing_titles
  vault_id = try(local.defaults.onepassword.vaults.servers.id, "disabled")

  depends_on = [terraform_data.onepassword]
}
