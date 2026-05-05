locals {
  config           = yamldecode(file("${path.module}/data/config.yml"))
  defaults         = provider::deepmerge::mergo(local.config, yamldecode(file("${path.module}/data/defaults.yml")))
  defaults_dns     = local.defaults.dns
  defaults_server  = local.defaults.servers
  defaults_service = local.defaults.services
  defaults_target  = local.defaults.target_defaults
}
