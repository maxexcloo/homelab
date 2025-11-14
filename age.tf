resource "age_secret_key" "server" {
  for_each = {
    for k, v in local._servers : k => v
    if local.servers_resources[k].komodo
  }
}
