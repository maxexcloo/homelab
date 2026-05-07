locals {
  config   = yamldecode(file("${path.module}/data/config.yml"))
  defaults = provider::deepmerge::mergo(local.config, yamldecode(file("${path.module}/data/defaults.yml")))
}
