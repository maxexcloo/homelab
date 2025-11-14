resource "htpasswd_password" "server" {
  for_each = local._servers

  password = each.value.password
}
