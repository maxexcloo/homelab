resource "bcrypt_hash" "server" {
  for_each = local.servers_model_by_feature.password

  cleartext = sensitive(try(local.onepassword_server_existing_fields[each.key].password, random_password.server_secret["${each.key}-password"].result))
}

resource "bcrypt_hash" "service" {
  for_each = local.services_model_by_feature.password

  cleartext = sensitive(try(local.onepassword_service_existing_fields[each.key].password, random_password.service_secret["${each.key}-password"].result))
}
