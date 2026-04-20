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
  for_each = local.servers_output_private

  collection_ids  = [data.bitwarden_org_collection.servers.id]
  name            = each.key
  organization_id = data.bitwarden_organization.default.id
  password        = each.value.password_sensitive
  username        = each.value.identity.username

  # Store scalar non-default fields as custom fields. *_sensitive fields become
  # hidden Bitwarden fields; URL-like fields are handled as URI entries below.
  dynamic "field" {
    for_each = {
      for k, v in each.value : k => v
      if v != null && v != "" && v != false && !can(regex(local.defaults.bitwarden.url_field_pattern, k)) && !contains(keys(local.defaults_server), k) && can(tostring(v))
    }

    content {
      hidden = endswith(field.key, "_sensitive") ? field.value : null
      name   = trimsuffix(field.key, "_sensitive")
      text   = endswith(field.key, "_sensitive") ? null : field.value
    }
  }

  # Bitwarden URI matching expects host-style values; IPv6 literals need brackets
  # and non-standard management ports are appended.
  dynamic "uri" {
    for_each = merge(
      {
        for k, v in each.value : k => v
        if v != null && v != "" && v != false && can(regex(local.defaults.bitwarden.url_field_pattern, k)) && can(tostring(v))
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
    for k, v in local.services_output_private : k => v
    if anytrue([for k, v in v.features : tobool(v) if can(tobool(v))]) || length(v.features.secrets) > 0 || v.networking.scheme != null
  }

  collection_ids  = [data.bitwarden_org_collection.services.id]
  name            = "${each.value.identity.title} (${each.value.target})"
  organization_id = data.bitwarden_organization.default.id
  password        = each.value.password_sensitive
  username        = each.value.identity.username

  # Store generated and computed scalar service fields, excluding defaults and URLs.
  dynamic "field" {
    for_each = {
      for k, v in each.value : k => v
      if v != null && v != "" && v != false && !can(regex(local.defaults.bitwarden.url_field_pattern, k)) && !contains(keys(local.defaults_service), k) && can(tostring(v))
    }

    content {
      hidden = endswith(field.key, "_sensitive") ? field.value : null
      name   = trimsuffix(field.key, "_sensitive")
      text   = endswith(field.key, "_sensitive") ? null : field.value
    }
  }

  # Service URI entries come from computed fqdn_/url_ fields.
  dynamic "uri" {
    for_each = {
      for k, v in each.value : k => v
      if v != null && v != "" && v != false && can(regex(local.defaults.bitwarden.url_field_pattern, k)) && can(tostring(v))
    }

    content {
      match = "host"
      value = uri.value
    }
  }
}
