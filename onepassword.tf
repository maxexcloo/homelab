locals {
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
                  (
                    !can(server.credentials.generated[field_name]) ||
                    can(local.server_onepassword_generators[server_key][field_name])
                  )
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

  _onepassword_server_manifest = {
    vault_id = local.defaults.onepassword.vaults.servers.id

    items = {
      for server_key, payload in local._onepassword_server_item_payloads : server_key => {
        generated_fields   = local.server_onepassword_generators[server_key]
        managed_fields     = local._onepassword_server_managed_fields[server_key]
        managed_urls       = [for url in payload.urls : url.label]
        payload            = payload
        placeholder_fields = local._onepassword_server_placeholder_fields[server_key]
      }
    }
  }

  _onepassword_server_missing_titles = {
    for server_key in module.server_onepassword.missing_items :
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

  _onepassword_service_dashboard_urls = {
    for service_key, service in local.services : service_key => values({
      for card_index, dashboard_card in local.services_resolved[service_key].dashboard :
      "${lower(try(dashboard_card.name, ""))}:${format("%05d", card_index)}" => {
        href    = try(dashboard_card.href, null)
        label   = try(dashboard_card.name, null)
        primary = try(dashboard_card.href, null) == service.urls.default.href
      }
      if(
        try(dashboard_card.name, "") != "" &&
        try(dashboard_card.href, "") != "" &&
        !contains([for url in values(service.urls) : url.href], try(dashboard_card.href, ""))
      )
    })
  }

  # Read only fields consumed by root providers; deployment-only fields remain op:// references.
  _onepassword_service_field_names = {
    for service_key in keys(local._onepassword_service_items) :
    service_key => local.service_provider_credential_names[service_key]
  }

  _onepassword_service_host_urls = {
    for service_key, service in local.services : service_key => [
      for url_key in ["external", "internal"] : {
        href    = service.urls[url_key].href
        label   = service.urls[url_key].label
        primary = service.urls[url_key].href == service.urls.default.href
      }
      if can(service.urls[url_key])
    ]
  }

  _onepassword_service_item_fields = {
    for service_key, service in local.services : service_key => {
      for field in concat(
        service.identity.username != "" ? [
          {
            id      = "username"
            label   = "username"
            purpose = "USERNAME"
            value   = service.identity.username
          }
        ] : [],
        [
          for field_name, field_value in service.runtime.attributes : {
            id    = field_name
            label = field_name
            type  = "STRING"
            value = tostring(field_value)
          }
          if(
            field_value != null &&
            field_value != ""
          )
        ],
        [
          for field_name, field_config in service.credentials.fields : {
            for item_key, item_value in merge(
              {
                id    = field_name
                label = field_name

                value = (
                  field_config.mode == "rw" &&
                  (
                    !can(service.credentials.generated[field_name]) ||
                    can(local.service_onepassword_generators[service_key][field_name])
                  )
                ) ? "" : try(tostring(service.runtime.credentials[field_name]), "")
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
            try(service.runtime.credentials[field_name], null) != null &&
            (
              try(service.runtime.credentials[field_name], "") != "" ||
              field_config.mode == "rw"
            )
          )
        ],
      ) : field.label => field
    }
    if can(local._onepassword_service_items[service_key])
  }

  _onepassword_service_item_payloads = {
    for service_key, service in local.services : service_key => {
      category = "LOGIN"
      tags     = try(local.defaults.onepassword.vaults.services.tags, [])
      title    = "${service.identity.title} (${service_key})"

      fields = [
        for label in sort(keys(local._onepassword_service_item_fields[service_key])) :
        local._onepassword_service_item_fields[service_key][label]
      ]

      urls = concat(
        [
          for url_key in [
            for key in sort(keys(service.urls)) : key
            if(
              !contains(["default", "external", "internal"], key) &&
              !contains(
                [
                  for alias in ["external", "internal"] : service.urls[alias].href
                  if can(service.urls[alias])
                ],
                service.urls[key].href,
              )
            )
            ] : {
            href    = service.urls[url_key].href
            label   = url_key
            primary = service.urls[url_key].href == service.urls.default.href
          }
        ],
        local._onepassword_service_dashboard_urls[service_key],
        local._onepassword_service_host_urls[service_key],
      )
    }
    if can(local._onepassword_service_items[service_key])
  }

  _onepassword_service_items = {
    for service_key, service in local.services_model : service_key => service
    if(
      service.identity.username != "" ||
      length(service.credentials.fields) > 0
    )
  }

  _onepassword_service_managed_fields = {
    for service_key, service in local.services : service_key => sort(tolist(setintersection(
      toset(keys(local._onepassword_service_item_fields[service_key])),
      toset(concat(
        service.identity.username != "" ? ["username"] : [],
        keys(service.runtime.attributes),
        [
          for field_name, field in service.credentials.fields : field_name
          if field.mode == "ro" || can(service.credentials.generated[field_name])
        ],
      )),
    )))
    if can(local._onepassword_service_item_fields[service_key])
  }

  _onepassword_service_manifest = {
    vault_id = local.defaults.onepassword.vaults.services.id

    items = {
      for service_key, payload in local._onepassword_service_item_payloads : service_key => {
        generated_fields   = local.service_onepassword_generators[service_key]
        managed_fields     = local._onepassword_service_managed_fields[service_key]
        managed_urls       = [for url in payload.urls : url.label]
        payload            = payload
        placeholder_fields = local._onepassword_service_placeholder_fields[service_key]
      }
    }
  }

  _onepassword_service_missing_titles = {
    for service_key in module.service_onepassword.missing_items :
    service_key => local._onepassword_service_titles[service_key]
  }

  _onepassword_service_placeholder_fields = {
    for service_key in keys(local._onepassword_service_item_fields) : service_key => sort(tolist(setsubtract(
      toset(keys(local._onepassword_service_item_fields[service_key])),
      toset(local._onepassword_service_managed_fields[service_key]),
    )))
  }

  _onepassword_service_titles = {
    for service_key, service in local._onepassword_service_items :
    service_key => "${service.identity.title} (${service_key})"
  }

  # Selected existing values consumed by server providers or bootstrap rendering.
  onepassword_server_existing_fields = module.server_onepassword.existing_fields

  # Existing item IDs, with a post-reconciliation lookup for newly created items.
  onepassword_server_item_ids = {
    for server_key in keys(local._onepassword_server_titles) : server_key => (
      can(module.server_onepassword.item_ids[server_key])
      ? module.server_onepassword.item_ids[server_key]
      : module.server_onepassword_created.item_ids[server_key]
    )
  }

  # Selected existing values consumed by root service providers.
  onepassword_service_existing_fields = module.service_onepassword.existing_fields

  # Existing item IDs, with a post-reconciliation lookup for newly created items.
  onepassword_service_item_ids = {
    for service_key in keys(local._onepassword_service_titles) : service_key => (
      can(module.service_onepassword.item_ids[service_key])
      ? module.service_onepassword.item_ids[service_key]
      : module.service_onepassword_created.item_ids[service_key]
    )
  }

}

module "server_onepassword" {
  source = "./modules/onepassword"

  field_names = local._onepassword_server_field_names
  titles      = local._onepassword_server_titles
  vault_id    = try(local.defaults.onepassword.vaults.servers.id, "disabled")
}

resource "terraform_data" "server_onepassword" {
  triggers_replace = [nonsensitive(sha256(jsonencode(local._onepassword_server_manifest)))]

  provisioner "local-exec" {
    command = "uv run ${path.root}/scripts/reconcile_onepassword.py --write"

    environment = {
      ONEPASSWORD_MANIFEST = jsonencode({ vaults = { servers = local._onepassword_server_manifest } })
    }
  }
}

module "server_onepassword_created" {
  source = "./modules/onepassword"

  # Re-read IDs after reconciliation so new items are usable in this apply.
  titles   = local._onepassword_server_missing_titles
  vault_id = try(local.defaults.onepassword.vaults.servers.id, "disabled")

  depends_on = [terraform_data.server_onepassword]
}

module "service_onepassword" {
  source = "./modules/onepassword"

  field_names = local._onepassword_service_field_names
  titles      = local._onepassword_service_titles
  vault_id    = try(local.defaults.onepassword.vaults.services.id, "disabled")
}

resource "terraform_data" "service_onepassword" {
  triggers_replace = [nonsensitive(sha256(jsonencode(local._onepassword_service_manifest)))]

  provisioner "local-exec" {
    command = "uv run ${path.root}/scripts/reconcile_onepassword.py --write"

    environment = {
      ONEPASSWORD_MANIFEST = jsonencode({ vaults = { services = local._onepassword_service_manifest } })
    }
  }
}

module "service_onepassword_created" {
  source = "./modules/onepassword"

  # Re-read IDs after reconciliation so new items are usable in this apply.
  titles   = local._onepassword_service_missing_titles
  vault_id = try(local.defaults.onepassword.vaults.services.id, "disabled")

  depends_on = [terraform_data.service_onepassword]
}
