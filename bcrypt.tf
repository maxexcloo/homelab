resource "bcrypt_hash" "server" {
  for_each = local.servers_outputs_by_feature.password

  cleartext = sensitive(try(local.onepassword_server_existing_fields[each.key].password, random_password.server[each.key].result))
}

resource "bcrypt_hash" "service" {
  for_each = local.services_outputs_by_feature.password

  cleartext = sensitive(try(local.onepassword_service_existing_fields[each.key].password, random_password.service[each.key].result))
}
