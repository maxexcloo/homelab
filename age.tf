resource "age_secret_key" "fly" {}

resource "age_secret_key" "server" {
  for_each = local._servers
}
