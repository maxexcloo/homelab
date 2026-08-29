data "talos_client_configuration" "cluster" {
  for_each = local.talos_recovery_clusters

  cluster_name = each.key

  client_configuration = {
    ca_certificate     = talos_machine_secrets.cluster[each.key].client_configuration.ca_certificate
    client_certificate = talos_machine_secrets.cluster[each.key].client_configuration.client_certificate
    client_key         = talos_machine_secrets.cluster[each.key].client_configuration.client_key
  }

  endpoints = flatten([
    for node_name, node in each.value.nodes : local.talos_client_endpoints[node_name]
    if node.machine_type == "controlplane"
  ])

  nodes = flatten([
    for node_name, node in each.value.nodes : local.talos_client_endpoints[node_name]
  ])
}

data "talos_image_factory_urls" "cluster" {
  for_each = local.talos_clusters

  architecture  = each.value.image.architecture
  platform      = each.value.image.platform
  schematic_id  = local.talos_image_factory_schematic_ids[each.key]
  talos_version = each.value.talos_version
}

data "talos_machine_configuration" "node" {
  for_each = local.talos_nodes

  cluster_endpoint   = local.talos_cluster_endpoints[each.value.cluster]
  cluster_name       = each.value.cluster
  kubernetes_version = local.clusters[each.value.cluster].kubernetes_version
  machine_secrets    = talos_machine_secrets.cluster[each.value.cluster].machine_secrets
  machine_type       = each.value.machine_type
  talos_version      = local.clusters[each.value.cluster].talos_version

  config_patches = [
    for document in local.talos_machine_configuration_documents[each.key] : yamlencode(document)
  ]
}

locals {
  talos_client_endpoints = {
    for name, node in local.talos_nodes : name => compact([
      node.address,
      try(local.tailscale_device_ipv4[local.machines[name].tailscale_name], null),
    ])
  }

  talos_cluster_endpoints = {
    for name, cluster in local.clusters : name => try(
      cluster.endpoint,
      "https://${local.machines[cluster.api_node].address}:6443",
    )
  }

  talos_clusters = {
    for name, cluster in local.clusters : name => cluster
    if cluster.talos_enabled
  }

  talos_image_factory_schematic_ids = {
    for name, schematic in talos_image_factory_schematic.cluster :
    name => schematic.id
  }

  talos_machine_bootstrap_nodes = {
    for name, node in local.talos_nodes : name => node
    if node.machine_type == "controlplane" && try(node.bootstrap, false)
  }

  talos_machine_configuration_documents = {
    for name, node in local.talos_nodes : name => [
      provider::deepmerge::mergo(
        {
          cluster = {
            allowSchedulingOnControlPlanes = true
            network = {
              cni = {
                name = "none"
              }
              podSubnets     = [local.clusters[node.cluster].pod_subnet]
              serviceSubnets = [local.clusters[node.cluster].service_subnet]
            }
          }
          machine = {
            features = {
              hostDNS = {
                enabled              = true
                forwardKubeDNSToHost = true
                resolveMemberNames   = true
              }
            }
          }
        },
        node.install_disk != null ? {
          machine = {
            install = {
              disk  = node.install_disk
              image = data.talos_image_factory_urls.cluster[node.cluster].urls.installer
            }
          }
        } : {},
        length(node.sysctls) > 0 ? {
          machine = {
            sysctls = node.sysctls
          }
        } : {},
        length(node.time_servers) > 0 ? {
          machine = {
            time = {
              servers = node.time_servers
            }
          }
        } : {},
      ),
      {
        apiVersion = "v1alpha1"
        kind       = "HostnameConfig"
        auto       = "off"
        hostname   = local.machine_hostnames[name]
      },
      {
        apiVersion = "v1alpha1"
        kind       = "ExtensionServiceConfig"
        name       = "tailscale"
        environment = compact([
          "TS_AUTHKEY=${tailscale_tailnet_key.server[name].key}",
          "TS_HOSTNAME=${local.machine_hostnames[name]}",
          length(node.tailscale_routes) > 0 ? "TS_ROUTES=${join(",", node.tailscale_routes)}" : null,
        ])
      },
      yamldecode(
        can(local.machines[name].oci.volumes.data) ?
        yamlencode(local.talos_user_volume_local_path_partition) :
        yamlencode(local.talos_user_volume_local_path_directory)
      ),
    ]
  }

  talos_nodes = merge([
    for cluster_name, cluster in local.talos_clusters : {
      for node_name, node in cluster.nodes : node_name => merge(node, {
        address                = local.machines[node_name].address
        cluster                = cluster_name
        configuration_delivery = try(node.configuration_delivery, null)
        install_disk           = try(node.install_disk, null)
        sysctls                = try(node.sysctls, {})
        tailscale_routes       = try(node.tailscale_routes, [])
        time_servers           = try(node.time_servers, [])
      })
    }
  ]...)

  talos_recovery_clusters = {
    for cluster_name, cluster in local.talos_clusters : cluster_name => cluster
    if anytrue([
      for node in values(cluster.nodes) :
      node.machine_type == "controlplane" && try(node.bootstrap, false)
    ])
  }

  talos_user_volume_local_path_directory = {
    apiVersion = "v1alpha1"
    kind       = "UserVolumeConfig"
    name       = "local-path-provisioner"
    volumeType = "directory"
  }

  talos_user_volume_local_path_partition = {
    apiVersion = "v1alpha1"
    kind       = "UserVolumeConfig"
    name       = "local-path-provisioner"
    volumeType = "partition"
    provisioning = {
      grow    = true
      minSize = "1GiB"
      diskSelector = {
        match = "!system_disk"
      }
    }
  }
}

resource "talos_cluster_kubeconfig" "cluster" {
  for_each = local.talos_recovery_clusters

  endpoint = local.machines[each.value.api_node].address
  node     = local.machines[each.value.api_node].address

  client_configuration = {
    ca_certificate     = talos_machine_secrets.cluster[each.key].client_configuration.ca_certificate
    client_certificate = talos_machine_secrets.cluster[each.key].client_configuration.client_certificate
    client_key         = talos_machine_secrets.cluster[each.key].client_configuration.client_key
  }

  timeouts = {
    create = "10m"
    update = "10m"
  }
}

resource "talos_image_factory_schematic" "cluster" {
  for_each = local.talos_clusters

  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = each.value.image.extensions
      }
    }
  })
}

resource "talos_machine_bootstrap" "control_plane" {
  for_each = local.talos_machine_bootstrap_nodes

  endpoint = each.value.address
  node     = each.value.address

  client_configuration_wo = {
    ca_certificate     = talos_machine_secrets.cluster[each.value.cluster].client_configuration.ca_certificate
    client_certificate = talos_machine_secrets.cluster[each.value.cluster].client_configuration.client_certificate
    client_key         = talos_machine_secrets.cluster[each.value.cluster].client_configuration.client_key
  }

  timeouts = {
    create = "10m"
  }

  lifecycle {
    precondition {
      condition     = try(talos_machine_configuration_apply.node[each.key].id, "") != ""
      error_message = "Deliver this node's Talos configuration before bootstrapping it."
    }
  }
}

resource "talos_machine_configuration_apply" "node" {
  for_each = local.talos_nodes

  apply_mode                     = "staged_if_needing_reboot"
  endpoint                       = each.value.configuration_delivery == "metadata" ? oci_core_instance.node[each.key].private_ip : each.value.address
  machine_configuration_input_wo = data.talos_machine_configuration.node[each.key].machine_configuration
  node                           = each.value.address

  client_configuration_wo = {
    ca_certificate     = talos_machine_secrets.cluster[each.value.cluster].client_configuration.ca_certificate
    client_certificate = talos_machine_secrets.cluster[each.value.cluster].client_configuration.client_certificate
    client_key         = talos_machine_secrets.cluster[each.value.cluster].client_configuration.client_key
  }

  on_destroy = {
    graceful = false
    reboot   = false
    reset    = false
  }

  timeouts = {
    create = "10m"
    update = "10m"
  }

  lifecycle {
    precondition {
      condition     = onepassword_item.talos_recovery[each.value.cluster].uuid != ""
      error_message = "Store this cluster's Talos recovery material before applying node configuration."
    }
  }
}

resource "talos_machine_secrets" "cluster" {
  for_each = local.talos_clusters

  talos_version = each.value.talos_version

  lifecycle {
    prevent_destroy = true
  }
}
