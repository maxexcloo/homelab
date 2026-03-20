locals {
  talos_control_planes = {
    for k, v in local.talos_servers : k => v
    if v.platform_config.talos.role == "controlplane"
  }

  talos_servers = {
    for k, v in local.servers : k => v
    if v.features.talos
  }

  talos_workers = {
    for k, v in local.talos_servers : k => v
    if v.platform_config.talos.role == "worker"
  }
}
