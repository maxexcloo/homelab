locals {
  defaults = yamldecode(file("${path.module}/data/defaults.yml"))

  dns = {
    for filepath in fileset(path.module, "data/dns/*.yml") :
    yamldecode(file("${path.module}/${filepath}")).name => try(yamldecode(file("${path.module}/${filepath}")).records, [])
  }
}
