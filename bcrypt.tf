resource "bcrypt_hash" "server" {
  for_each = local.servers_outputs_by_feature.password

  cleartext = local.servers_model_passwords[each.key]
}

resource "bcrypt_hash" "service" {
  for_each = local.services_outputs_by_feature.password

  cleartext = local.services_model_passwords[each.key]
}
