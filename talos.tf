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

data "talos_cluster_health" "cluster" {
  for_each = local.talos_recovery_clusters

  control_plane_nodes    = local.talos_cluster_endpoints_control_plane[each.key]
  endpoints              = local.talos_cluster_endpoints_control_plane[each.key]
  skip_kubernetes_checks = true
  worker_nodes           = local.talos_cluster_endpoints_worker[each.key]

  client_configuration = {
    ca_certificate     = talos_machine_secrets.cluster[each.key].client_configuration.ca_certificate
    client_certificate = talos_machine_secrets.cluster[each.key].client_configuration.client_certificate
    client_key         = talos_machine_secrets.cluster[each.key].client_configuration.client_key
  }

  timeouts = {
    read = "10m"
  }

  lifecycle {
    precondition {
      condition     = talos_machine_bootstrap.control_plane[each.value.api_node].id != ""
      error_message = "Bootstrap this cluster's API node before checking cluster health."
    }
  }
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
    yamlencode({
      machine = merge(
        {
          features = {
            hostDNS = {
              enabled              = true
              forwardKubeDNSToHost = true
              resolveMemberNames   = true
            }
          }
        },
        try(each.value.install_disk, null) != null ? {
          install = {
            disk  = each.value.install_disk
            image = data.talos_image_factory_urls.cluster[each.value.cluster].urls.installer
          }
        } : {},
        try(length(each.value.time_servers), 0) > 0 ? {
          time = {
            servers = each.value.time_servers
          }
        } : {},
      )
      cluster = {
        allowSchedulingOnControlPlanes = true
        network = {
          cni = {
            name = "none"
          }
          podSubnets     = [local.clusters[each.value.cluster].pod_subnet]
          serviceSubnets = [local.clusters[each.value.cluster].service_subnet]
        }
      }
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "HostnameConfig"
      auto       = "off"
      hostname   = each.key
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "ExtensionServiceConfig"
      name       = "tailscale"
      environment = concat(
        [
          "TS_AUTHKEY=${tailscale_tailnet_key.server[each.key].key}",
          "TS_HOSTNAME=${each.key}",
        ],
        try(length(each.value.tailscale_routes), 0) > 0 ? [
          "TS_ROUTES=${join(",", each.value.tailscale_routes)}",
        ] : [],
      )
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "UserVolumeConfig"
      name       = "local-path-provisioner"
      volumeType = "directory"
    }),
  ]
}

locals {
  talos_client_endpoints = {
    for name, node in local.talos_nodes : name => compact([
      node.address,
      try(local.tailscale_device_ipv4[name], null),
    ])
  }

  talos_cluster_endpoints = {
    for name, cluster in local.clusters : name => try(
      cluster.endpoint,
      "https://${local.machines[cluster.api_node].address}:6443",
    )
  }

  talos_cluster_endpoints_control_plane = {
    for cluster_name, cluster in local.talos_clusters : cluster_name => [
      for node_name, node in cluster.nodes : local.machines[node_name].address
      if node.machine_type == "controlplane"
    ]
  }

  talos_cluster_endpoints_worker = {
    for cluster_name, cluster in local.talos_clusters : cluster_name => [
      for node_name, node in cluster.nodes : local.machines[node_name].address
      if node.machine_type == "worker"
    ]
  }

  talos_clusters = {
    for name, cluster in local.clusters : name => cluster
    if cluster.talos_enabled
  }

  talos_machine_bootstrap_nodes = {
    for name, node in local.talos_nodes : name => node
    if node.machine_type == "controlplane" && try(node.bootstrap, false)
  }

  talos_nodes = merge([
    for cluster_name, cluster in local.talos_clusters : {
      for node_name, node in cluster.nodes : node_name => merge(node, {
        address = local.machines[node_name].address
        cluster = cluster_name
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
}

resource "onepassword_item" "kubeconfig" {
  for_each = local.talos_recovery_clusters

  category              = "secure_note"
  note_value_wo         = talos_cluster_kubeconfig.cluster[each.key].kubeconfig_raw
  note_value_wo_version = try(each.value.kubeconfig_secret_revision, 1)
  tags                  = ["Homelab", "Kubernetes", "Recovery"]
  title                 = "kubeconfig"
  vault                 = data.onepassword_vault.default["cluster/${each.key}"].uuid

  lifecycle {
    prevent_destroy = true
  }
}

resource "onepassword_item" "talos_recovery" {
  for_each = local.talos_clusters

  category              = "secure_note"
  note_value_wo_version = try(each.value.secret_revision, 1)
  tags                  = ["Homelab", "Talos", "Recovery"]
  title                 = "Talos Recovery: ${each.key}"
  vault                 = data.onepassword_vault.default["homelab"].uuid

  note_value_wo = jsonencode({
    client_configuration = talos_machine_secrets.cluster[each.key].client_configuration
    cluster_name         = each.key
    machine_secrets      = talos_machine_secrets.cluster[each.key].machine_secrets
    talos_version        = each.value.talos_version
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "onepassword_item" "talosconfig" {
  for_each = local.talos_recovery_clusters

  category              = "secure_note"
  note_value_wo         = data.talos_client_configuration.cluster[each.key].talos_config
  note_value_wo_version = try(each.value.talosconfig_secret_revision, 1)
  tags                  = ["Homelab", "Talos"]
  title                 = "talosconfig"
  vault                 = data.onepassword_vault.default["cluster/${each.key}"].uuid

  lifecycle {
    prevent_destroy = true
  }
}

resource "talos_cluster_kubeconfig" "cluster" {
  for_each = local.talos_recovery_clusters

  endpoint = one(local.talos_cluster_endpoints_control_plane[each.key])
  node     = one(local.talos_cluster_endpoints_control_plane[each.key])

  client_configuration = {
    ca_certificate     = talos_machine_secrets.cluster[each.key].client_configuration.ca_certificate
    client_certificate = talos_machine_secrets.cluster[each.key].client_configuration.client_certificate
    client_key         = talos_machine_secrets.cluster[each.key].client_configuration.client_key
  }

  timeouts = {
    create = "10m"
    update = "10m"
  }

  lifecycle {
    precondition {
      condition     = data.talos_cluster_health.cluster[each.key].id != ""
      error_message = "Verify this cluster's health before retrieving its kubeconfig."
    }
  }
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
