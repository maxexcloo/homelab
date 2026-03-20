resource "htpasswd_password" "server" {
  for_each = local.servers_by_feature.password

  password = random_password.server[each.key].result
}
