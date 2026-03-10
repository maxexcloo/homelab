resource "htpasswd_password" "server" {
  for_each = {
    for k, v in local._servers : k => v
    if v.enable_password
  }

  password = random_password.server[each.key].result
}
