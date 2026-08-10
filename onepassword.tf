locals {
  _onepassword_cleanup = {
    vaults = {
      for vault_key, manifest in local._onepassword_manifests : vault_key => {
        vault_id = manifest.vault_id

        items = {
          for item_key, title in local._onepassword_titles[vault_key] : item_key => {
            title = title
          }
        }
      }
    }
  }

  _onepassword_item_fields = {
    for item_id, item in local._onepassword_items : item_id => {
      for field in concat(
        item.username != "" ? [
          {
            id      = "username"
            label   = "username"
            purpose = "USERNAME"
            value   = item.username
          }
        ] : [],
        [
          for field_name, field_value in item.attributes : {
            id    = field_name
            label = field_name
            type  = "STRING"
            value = tostring(field_value)
          }
          if(
            field_value != null &&
            try(tostring(field_value), "") != ""
          )
        ],
        [
          for field_name, field_config in item.credential_fields : {
            for field_key, field_value in merge(
              {
                id    = field_name
                label = field_name

                value = (
                  field_config.mode == "rw" &&
                  (
                    !can(item.generated[field_name]) ||
                    can(item.generators[field_name])
                  )
                ) ? "" : try(tostring(item.credentials[field_name]), "")
              },
              field_config.purpose != null ? {
                purpose = field_config.purpose
                } : {
                type = field_config.type
              },
            ) : field_key => field_value
            if field_value != null
          }
          if(
            try(item.credentials[field_name], null) != null &&
            (
              try(item.credentials[field_name], "") != "" ||
              field_config.mode == "rw"
            )
          )
        ],
      ) : field.label => field
    }
  }

  _onepassword_item_managed_fields = {
    for item_id, item in local._onepassword_items : item_id => sort(tolist(setintersection(
      toset(keys(local._onepassword_item_fields[item_id])),
      toset(concat(
        item.username != "" ? ["username"] : [],
        keys(item.attributes),
        [
          for field_name, field in item.credential_fields : field_name
          if field.mode == "ro" || can(item.generated[field_name])
        ],
      )),
    )))
  }

  _onepassword_item_payloads = {
    for item_id, item in local._onepassword_items : item_id => {
      category = "LOGIN"
      tags     = item.tags
      title    = item.title
      urls     = item.urls

      fields = [
        for label in sort(keys(local._onepassword_item_fields[item_id])) :
        local._onepassword_item_fields[item_id][label]
      ]
    }
  }

  _onepassword_item_placeholder_fields = {
    for item_id in keys(local._onepassword_items) : item_id => sort(tolist(setsubtract(
      toset(keys(local._onepassword_item_fields[item_id])),
      toset(local._onepassword_item_managed_fields[item_id]),
    )))
  }

  _onepassword_items = merge(
    {
      for server_key, server in local.servers_model : "servers/${server_key}" => {
        attributes        = local.servers[server_key].runtime.attributes
        credential_fields = server.credentials.fields
        credentials       = local.servers[server_key].runtime.credentials
        generated         = server.credentials.generated
        generators        = local.server_onepassword_generators[server_key]
        item_key          = server_key
        tags              = try(local.defaults.onepassword.vaults.servers.tags, [])
        title             = "${server.identity.title} (${server_key})"
        username          = server.identity.username
        vault_key         = "servers"

        urls = [
          for url_key in sort(keys(local.servers[server_key].runtime.urls)) : {
            href    = local.servers[server_key].runtime.urls[url_key].href
            label   = local.servers[server_key].runtime.urls[url_key].label
            primary = local.servers[server_key].runtime.urls[url_key].href == try(local.servers[server_key].runtime.urls.management.href, local.servers[server_key].runtime.urls.internal.href)
          }
        ]
      }
    },
    {
      for service_key, service in local._onepassword_service_items : "services/${service_key}" => {
        attributes        = local.services[service_key].runtime.attributes
        credential_fields = service.credentials.fields
        credentials       = local.services[service_key].runtime.credentials
        generated         = service.credentials.generated
        generators        = local.service_onepassword_generators[service_key]
        item_key          = service_key
        tags              = try(local.defaults.onepassword.vaults.services.tags, [])
        title             = "${service.identity.title} (${service_key})"
        username          = service.identity.username
        vault_key         = "services"

        urls = [
          for url_key in sort(keys(local._onepassword_service_urls[service_key])) :
          local._onepassword_service_urls[service_key][url_key]
        ]
      }
    },
  )

  _onepassword_manifests = {
    for vault_key in toset(["servers", "services"]) : vault_key => {
      vault_id = local.defaults.onepassword.vaults[vault_key].id

      items = {
        for item_id, payload in local._onepassword_item_payloads : local._onepassword_items[item_id].item_key => {
          generated_fields   = local._onepassword_items[item_id].generators
          managed_fields     = local._onepassword_item_managed_fields[item_id]
          managed_urls       = [for url in payload.urls : url.label]
          payload            = payload
          placeholder_fields = local._onepassword_item_placeholder_fields[item_id]
        }
        if local._onepassword_items[item_id].vault_key == vault_key
      }
    }
  }

  _onepassword_reconciliations = merge([
    for vault_key, manifest in local._onepassword_manifests : {
      for item_key, item in manifest.items : "${vault_key}/${item_key}" => {
        item      = item
        item_key  = item_key
        vault_id  = manifest.vault_id
        vault_key = vault_key
      }
    }
  ]...)

  # Read only the server fields OpenTofu consumes; deployment-only fields remain op:// references.
  _onepassword_server_field_names = {
    for server_key, server in local.servers_model : server_key => toset(concat(
      (
        server.features.bootstrap &&
        server.features.password &&
        server.platform != "truenas"
      ) ? ["password"] : [],
      server.features.bootstrap && server.features.beszel ? ["beszel_agent_token"] : [],
      server.features.bootstrap && server.platform == "truenas" ? ["truenas_cd_access_token"] : [],
    ))
  }

  # Read only fields consumed by root providers; deployment-only fields remain op:// references.
  _onepassword_service_field_names = {
    for service_key in keys(local._onepassword_service_items) :
    service_key => local.service_provider_credential_names[service_key]
  }

  _onepassword_service_items = {
    for service_key, service in local.services_model : service_key => service
    if(
      service.identity.username != "" ||
      length(service.credentials.fields) > 0
    )
  }

  _onepassword_service_urls = {
    for service_key in keys(local._onepassword_service_items) : service_key => merge(
      {
        for dashboard_card in jsondecode(templatestring(
          replace(
            jsonencode(local.services[service_key].dashboard),
            local.render_json_template_expression_pattern,
            local.render_json_template_expression_replacement,
          ),
          local.services_template_contexts[service_key],
          )) : lower(try(dashboard_card.name, "")) => {
          href    = try(dashboard_card.href, null)
          label   = try(dashboard_card.name, null)
          primary = try(try(dashboard_card.href, null) == local.services[service_key].urls.default.href, false)
        }
        if(
          try(dashboard_card.name, "") != "" &&
          try(dashboard_card.href, "") != "" &&
          !contains([for route in values(local.services[service_key].routing) : route.href], try(dashboard_card.href, ""))
        )
      },
      {
        for route_id, route in local.services[service_key].routing : route_id => {
          href    = route.href
          label   = route_id
          primary = try(route.href == local.services[service_key].urls.default.href, false)
        }
        if route.href != null
      },
    )
  }

  _onepassword_titles = {
    servers = {
      for server_key, server in local.servers_model :
      server_key => "${server.identity.title} (${server_key})"
    }

    services = {
      for service_key, service in local._onepassword_service_items :
      service_key => "${service.identity.title} (${service_key})"
    }
  }

  # Selected existing values consumed by server providers or bootstrap rendering.
  onepassword_server_existing_fields = module.server_onepassword.existing_fields

  # Existing item IDs, with a post-reconciliation lookup for newly created items.
  onepassword_server_item_ids = {
    for server_key in keys(local._onepassword_titles.servers) : server_key => (
      can(module.server_onepassword.item_ids[server_key])
      ? module.server_onepassword.item_ids[server_key]
      : module.server_onepassword_created.item_ids[server_key]
    )
  }

  # Selected existing values consumed by root service providers.
  onepassword_service_existing_fields = module.service_onepassword.existing_fields

  # Existing item IDs, with a post-reconciliation lookup for newly created items.
  onepassword_service_item_ids = {
    for service_key in keys(local._onepassword_titles.services) : service_key => (
      can(module.service_onepassword.item_ids[service_key])
      ? module.service_onepassword.item_ids[service_key]
      : module.service_onepassword_created.item_ids[service_key]
    )
  }

}

module "server_onepassword" {
  source = "./modules/onepassword"

  field_names = local._onepassword_server_field_names
  titles      = local._onepassword_titles.servers
  vault_id    = try(local.defaults.onepassword.vaults.servers.id, "disabled")
}

module "service_onepassword" {
  source = "./modules/onepassword"

  field_names = local._onepassword_service_field_names
  titles      = local._onepassword_titles.services
  vault_id    = try(local.defaults.onepassword.vaults.services.id, "disabled")
}

resource "terraform_data" "onepassword" {
  for_each = nonsensitive(toset(keys(local._onepassword_reconciliations)))

  triggers_replace = [sha256(jsonencode(local._onepassword_reconciliations[each.key]))]

  provisioner "local-exec" {
    command = "uv run ${path.root}/scripts/reconcile_onepassword.py --write"

    environment = {
      ONEPASSWORD_MANIFEST = jsonencode({
        vaults = {
          (local._onepassword_reconciliations[each.key].vault_key) = {
            vault_id = local._onepassword_reconciliations[each.key].vault_id

            items = {
              (local._onepassword_reconciliations[each.key].item_key) = local._onepassword_reconciliations[each.key].item
            }
          }
        }
      })
    }
  }
}

resource "terraform_data" "onepassword_cleanup" {
  triggers_replace = [sha256(jsonencode(local._onepassword_cleanup))]

  depends_on = [terraform_data.onepassword]

  provisioner "local-exec" {
    command = "uv run ${path.root}/scripts/reconcile_onepassword.py --prune --write"

    environment = {
      ONEPASSWORD_MANIFEST = jsonencode(local._onepassword_cleanup)
    }
  }
}

module "server_onepassword_created" {
  source = "./modules/onepassword"

  depends_on = [terraform_data.onepassword_cleanup]
  vault_id   = try(local.defaults.onepassword.vaults.servers.id, "disabled")

  # Re-read IDs after reconciliation so new items are usable in this apply.
  titles = {
    for server_key in module.server_onepassword.missing_items :
    server_key => local._onepassword_titles.servers[server_key]
  }
}

module "service_onepassword_created" {
  source = "./modules/onepassword"

  depends_on = [terraform_data.onepassword_cleanup]
  vault_id   = try(local.defaults.onepassword.vaults.services.id, "disabled")

  # Re-read IDs after reconciliation so new items are usable in this apply.
  titles = {
    for service_key in module.service_onepassword.missing_items :
    service_key => local._onepassword_titles.services[service_key]
  }
}
