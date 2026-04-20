resource "bcrypt_hash" "server" {
  for_each = local.servers_output_by_feature.password

  cleartext = random_password.server[each.key].result
}

resource "bcrypt_hash" "service" {
  for_each = local.services_output_by_feature.password

  cleartext = random_password.service[each.key].result
}
