locals {
  defaults = provider::deepmerge::mergo(
    yamldecode(file("${path.module}/data/config.yaml")),
    yamldecode(file("${path.module}/data/defaults.yaml")),
  )
}
