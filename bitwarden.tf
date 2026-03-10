data "bitwarden_folder" "servers" {
  search = "Servers"
}

resource "bitwarden_item_login" "server" {
  for_each = local.servers

  folder_id = data.bitwarden_folder.servers.id
  name      = each.key
  password  = each.value.enable_password ? random_password.server[each.key].result : null
  username  = each.value.username

  # URIs from URL-like fields
  dynamic "uri" {
    for_each = [
      for k, v in each.value : {
        key   = k
        value = v
      }
      if can(regex(var.url_field_pattern, k)) && v != null && v != ""
    ]
    content {
      match = "host"
      value = format(
        "%s%s",
        can(cidrhost("${uri.value.value}/128", 0)) ? "[${uri.value.value}]" : uri.value.value,
        each.value.management_port != 443 ? ":${each.value.management_port}" : ""
      )
    }
  }

  # Custom fields - only scalar values, exclude defaults and URL fields
  dynamic "field" {
    for_each = {
      for k, v in each.value : k => v
      if !can(regex(var.url_field_pattern, k)) &&
      !contains(keys(var.server_defaults), k) &&
      v != null &&
      v != "" &&
      v != false &&
      can(tostring(v))
    }
    content {
      name   = replace(field.key, "_sensitive$", "")
      text   = can(regex("_sensitive$", field.key)) ? null : field.value
      hidden = can(regex("_sensitive$", field.key)) ? field.value : null
    }
  }
}
