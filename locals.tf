locals {
  # Raw defaults are the schema-shaped baseline for every loaded YAML object.
  defaults = yamldecode(file("${path.module}/data/defaults.yml"))

  # Default DNS record attributes merged into manual and generated records.
  defaults_dns = local.defaults.dns

  # Schema-shaped defaults merged into each server YAML file.
  defaults_server = local.defaults.servers

  # Schema-shaped defaults merged into each service YAML file.
  defaults_service = local.defaults.services
}

