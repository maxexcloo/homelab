locals {
  access = yamldecode(file("${path.module}/data/access.yaml"))

  cloudflare = yamldecode(file("${path.module}/data/domains.yaml")).cloudflare

  clusters = yamldecode(file("${path.module}/data/clusters.yaml")).clusters

  domains = yamldecode(file("${path.module}/data/domains.yaml")).domains

  machines = yamldecode(file("${path.module}/data/machines.yaml")).machines

  networks = yamldecode(file("${path.module}/data/networks.yaml")).networks

  storage = yamldecode(file("${path.module}/data/storage.yaml"))

  machine_hostnames = {
    for name, machine in local.machines :
    name => try(machine.hostname, name)
  }

  machine_fqdns = {
    for name, machine in local.machines :
    name => "${local.machine_hostnames[name]}.${machine.network}.${local.domains.infrastructure}"
  }
}
