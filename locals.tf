locals {
  # Global config (account/domain/onepassword/system/types) referenced as
  # local.defaults.* throughout. Stored in its own file so editing config
  # doesn't churn merge defaults.
  config = yamldecode(file("${path.module}/data/config.yml"))

  # Single defaults blob every consumer reads: config merged with data/defaults.yml.
  defaults = provider::deepmerge::mergo(local.config, yamldecode(file("${path.module}/data/defaults.yml")))

  # Default DNS record attributes merged into manual and generated records.
  defaults_dns = local.defaults.dns

  # Schema-shaped defaults merged into each server YAML file.
  defaults_server = local.defaults.servers

  # Schema-shaped defaults merged into each service YAML file.
  defaults_service = local.defaults.services

  # Per-platform defaults merged into each service deployment target during
  # expansion (services_input.tf).
  defaults_target = local.defaults.target_defaults
}
