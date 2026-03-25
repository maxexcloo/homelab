resource "age_secret_key" "server" {
  for_each = local.servers_by_feature.docker
}
