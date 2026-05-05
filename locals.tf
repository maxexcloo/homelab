locals {
  # Global config (account/domain/onepassword/system/types) referenced as
  # local.defaults.* throughout. Stored in its own file so editing config
  # doesn't churn merge defaults.
  config = yamldecode(file("${path.module}/data/config.yml"))

  # Single defaults blob every consumer reads. Three sources are deep-merged:
  #   config       — global parameters (cloudflare/domains/github/...)
  #   defaults_raw — values merged into each server/service/DNS record
  #   scaffolding  — null placeholders so models can reference runtime/computed
  #                  fields without try() and so 1Password's keys-of-defaults
  #                  filter excludes them from generated field lists
  defaults = provider::deepmerge::mergo(local.config, local.defaults_raw, local.scaffolding)

  # Default DNS record attributes merged into manual and generated records.
  defaults_dns = local.defaults.dns

  # Raw deep-merge defaults loaded from data/defaults.yml.
  defaults_raw = yamldecode(file("${path.module}/data/defaults.yml"))

  # Schema-shaped defaults merged into each server YAML file.
  defaults_server = local.defaults.servers

  # Schema-shaped defaults merged into each service YAML file.
  defaults_service = local.defaults.services

  # Placeholder fields loaded from data/scaffolding.yml.
  scaffolding = yamldecode(file("${path.module}/data/scaffolding.yml"))
}
