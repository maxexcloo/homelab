locals {
  access = yamldecode(file("${path.module}/data/access.yaml"))

  cloudflare = yamldecode(file("${path.module}/data/domains.yaml")).cloudflare

  clusters = yamldecode(file("${path.module}/data/clusters.yaml")).clusters

  domains = yamldecode(file("${path.module}/data/domains.yaml")).domains

  machines = yamldecode(file("${path.module}/data/machines.yaml")).machines

  networks = yamldecode(file("${path.module}/data/networks.yaml")).networks

  storage = yamldecode(file("${path.module}/data/storage.yaml"))

  machine_fqdns = {
    for name, machine in local.machines :
    name => "${name}.${machine.network}.${local.domains.infrastructure}"
  }

  truenas_hosts = {
    for name, machine in local.machines : name => machine
    if machine.platform == "truenas"
  }

  truenas_provider_hosts = setunion(
    toset(keys(local.truenas_hosts)),
    toset(local.access.truenas.retired_hosts),
  )
}
