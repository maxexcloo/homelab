# Fly deploys share one repository key because app files are isolated by app
# directory in the deploy repo.
resource "age_secret_key" "fly" {}

# Server-targeted deploy repos use one age key per server so encrypted files can
# be scoped to the runner that is allowed to decrypt them.
resource "age_secret_key" "server" {
  for_each = local.servers_input
}
