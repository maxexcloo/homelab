locals {
  _onepassword_service_dashboard_urls = {
    for service_key, service in local.services : service_key => values({
      for card_index, dashboard_card in local.services_render_services[service_key].dashboard :
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

  _onepassword_service_field_names = {
    for service_key, service in local._onepassword_service_items : service_key => toset([
      for field_name, field in service.credentials.fields : field_name
      if field.mode == "rw"
    ])
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
                  !can(service.credentials.generated[field_name])
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
        service.features.oidc_forward_auth ? [
          {
            id    = "monitoring_basic"
            label = "monitoring_basic"
            type  = "CONCEALED"
            value = base64encode("monitoring:${service.runtime.credentials.monitoring_token}")
          },
          {
            id    = "monitoring_password_hash"
            label = "monitoring_password_hash"
            type  = "CONCEALED"
            value = "monitoring:${module.credentials.hashes["${service_key}-monitoring_token"]}"
          },
        ] : [],
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
            label   = service.urls[url_key].label
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
        service.features.oidc_forward_auth ? [
          "monitoring_basic",
          "monitoring_password_hash",
        ] : [],
      )),
    )))
    if can(local._onepassword_service_item_fields[service_key])
  }

  _onepassword_service_missing_titles = {
    for service_key in module.onepassword.missing_items :
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

  onepassword_service_existing_fields = module.onepassword.existing_fields

  onepassword_service_item_ids = {
    for service_key in keys(local._onepassword_service_titles) : service_key => (
      can(module.onepassword.item_ids[service_key])
      ? module.onepassword.item_ids[service_key]
      : module.onepassword_created.item_ids[service_key]
    )
  }

  onepassword_service_manifest = {
    vault_id = local.defaults.onepassword.vaults.services.id

    items = {
      for service_key, payload in local._onepassword_service_item_payloads : service_key => {
        managed_fields     = local._onepassword_service_managed_fields[service_key]
        managed_urls       = [for url in payload.urls : url.label]
        payload            = payload
        placeholder_fields = local._onepassword_service_placeholder_fields[service_key]
      }
    }
  }
}

module "onepassword" {
  source = "../onepassword"

  field_names = local._onepassword_service_field_names
  titles      = local._onepassword_service_titles
  vault_id    = try(local.defaults.onepassword.vaults.services.id, "disabled")
}

resource "terraform_data" "onepassword" {
  triggers_replace = [nonsensitive(sha256(jsonencode(local.onepassword_service_manifest)))]

  provisioner "local-exec" {
    command = "uv run ${path.root}/scripts/reconcile_onepassword.py --write"

    environment = {
      ONEPASSWORD_MANIFEST = jsonencode({ vaults = { services = local.onepassword_service_manifest } })
    }
  }
}

module "onepassword_created" {
  source = "../onepassword"

  titles   = local._onepassword_service_missing_titles
  vault_id = try(local.defaults.onepassword.vaults.services.id, "disabled")

  depends_on = [terraform_data.onepassword]
}
