locals {
  infrastructure      = yamldecode(file("${path.module}/data/infrastructure.yaml"))
  home_network        = local.infrastructure.networks.mbk
  truenas_service_nic = local.home_network.interfaces.services
}
