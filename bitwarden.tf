data "bitwarden_folder" "servers" {
  search = var.servers_folder
}

data "bitwarden_folder" "services" {
  search = var.services_folder
}

resource "bitwarden_item_login" "server" {
  for_each = local.servers

  folder_id = data.bitwarden_folder.servers.id
  name      = each.key
  password  = each.value.password_sensitive
  username  = each.value.identity.username

  dynamic "field" {
    for_each = {
      for k, v in local.servers_filtered[each.key] : k => v
      if !can(regex(var.url_field_pattern, k)) && !contains(keys(local.server_defaults), k) && can(tostring(v))
    }

    content {
      hidden = endswith(field.key, "_sensitive") ? field.value : null
      name   = trimsuffix(field.key, "_sensitive")
      text   = endswith(field.key, "_sensitive") ? null : field.value
    }
  }

  dynamic "uri" {
    for_each = {
      for k, v in local.servers_filtered[each.key] : k => v
      if can(regex(var.url_field_pattern, k))
    }

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
  for_each = local.services

  folder_id = data.bitwarden_folder.services.id
  name      = each.key
  password  = each.value.password_sensitive
  username  = each.value.identity.username

  dynamic "field" {
    for_each = {
      for k, v in local.services_filtered[each.key] : k => v
      if !can(regex(var.url_field_pattern, k)) && !contains(keys(local.service_defaults), k) && can(tostring(v))
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
      if can(regex(var.url_field_pattern, k))
    }

    content {
      match = "host"
      value = uri.value
    }
  }
}
