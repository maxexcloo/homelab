resource "age_secret_key" "fly" {}

resource "age_secret_key" "server" {
  for_each = local.servers_by_feature.docker
}

resource "age_secret_key" "server_truenas" {
  for_each = local.truenas_servers
}
