data "bitwarden_org_collection" "servers" {
  organization_id = data.bitwarden_organization.default.id
  search          = local.defaults.bitwarden.collections.servers
}

data "bitwarden_org_collection" "services" {
  organization_id = data.bitwarden_organization.default.id
  search          = local.defaults.bitwarden.collections.services
}

data "bitwarden_organization" "default" {
  search = local.defaults.bitwarden.organization
}

resource "bitwarden_item_login" "server" {
  for_each = local.servers

  collection_ids  = [data.bitwarden_org_collection.servers.id]
  name            = each.key
  organization_id = data.bitwarden_organization.default.id
  password        = each.value.password_sensitive
  username        = each.value.identity.username

  dynamic "field" {
    for_each = {
      for k, v in local.servers_filtered[each.key] : k => v
      if !can(regex(local.defaults.bitwarden.url_field_pattern, k)) && !contains(keys(local.server_defaults), k) && can(tostring(v))
    }

    content {
      hidden = endswith(field.key, "_sensitive") ? field.value : null
      name   = trimsuffix(field.key, "_sensitive")
      text   = endswith(field.key, "_sensitive") ? null : field.value
    }
  }

  dynamic "uri" {
    for_each = merge(
      {
        for k, v in local.servers_filtered[each.key] : k => v
        if can(regex(local.defaults.bitwarden.url_field_pattern, k)) && can(tostring(v))
      },
      each.value.networking.management_address != "" ? {
        management_address = each.value.networking.management_address
      } : {}
    )

    content {
      match = "host"
      value = format(
        "%s%s",
        can(cidrhost("${uri.value}/128", 0)) ? "[${uri.value}]" : uri.value,
        each.value.networking.management_port != 443 ? ":${each.value.networking.management_port}" : ""
      )
    }
  }
}

resource "bitwarden_item_login" "service" {
  for_each = {
    for k, v in local.services : k => v
    if anytrue([for k, v in v.features : tobool(v) if can(tobool(v))]) || length(v.features.secrets) > 0 || v.networking.scheme != null
  }

  collection_ids  = [data.bitwarden_org_collection.services.id]
  name            = "${each.value.identity.title} (${each.value.target})"
  organization_id = data.bitwarden_organization.default.id
  password        = each.value.password_sensitive
  username        = each.value.identity.username

  dynamic "field" {
    for_each = {
      for k, v in local.services_filtered[each.key] : k => v
      if !can(regex(local.defaults.bitwarden.url_field_pattern, k)) && !contains(keys(local.service_defaults), k) && can(tostring(v))
    }

    content {
      hidden = endswith(field.key, "_sensitive") ? field.value : null
      name   = trimsuffix(field.key, "_sensitive")
      text   = endswith(field.key, "_sensitive") ? null : field.value
    }
  }

  dynamic "uri" {
    for_each = {
      for k, v in local.services_filtered[each.key] : k => v
      if can(regex(local.defaults.bitwarden.url_field_pattern, k)) && can(tostring(v))
    }

    content {
      match = "host"
      value = uri.value
    }
  }
}
