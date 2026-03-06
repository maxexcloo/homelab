resource "htpasswd_password" "server" {
  for_each = {
    for k, v in local._servers : k => v
    if v.password != ""
  }

  password = each.value.password
}
