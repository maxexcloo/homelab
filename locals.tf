locals {
  defaults = provider::deepmerge::mergo(
    yamldecode(file("${path.module}/data/config.yml")),
    yamldecode(file("${path.module}/data/defaults.yml")),
  )
}
