variable "talos_apply_endpoint" {
  description = "Optional Talos API connection endpoint, such as a local SSH forward."
  type        = string
  default     = null
  nullable    = true
}

resource "talos_machine_secrets" "cluster" {
  talos_version = local.home_cluster.talos_version

  lifecycle {
    prevent_destroy = true
  }
}

resource "onepassword_item" "talos_recovery" {
  vault = data.onepassword_vault.talos_recovery.uuid

  category = "secure_note"
  note_value_wo = jsonencode({
    client_configuration = talos_machine_secrets.cluster.client_configuration
    cluster_name         = "mbk"
    machine_secrets      = talos_machine_secrets.cluster.machine_secrets
    talos_version        = local.home_cluster.talos_version
  })
  note_value_wo_version = local.home_cluster.recovery_version
  tags                  = ["Homelab", "Talos", "Recovery"]
  title                 = "mbk Talos recovery"

  lifecycle {
    prevent_destroy = true
  }
}

ephemeral "talos_machine_configuration" "node" {
  for_each = local.talos_nodes

  cluster_endpoint   = local.home_cluster.endpoint
  cluster_name       = "mbk"
  kubernetes_version = local.home_cluster.kubernetes_version
  machine_secrets    = talos_machine_secrets.cluster.machine_secrets
  machine_type       = each.value.machine_type
  talos_version      = local.home_cluster.talos_version

  config_patches = [
    yamlencode({
      machine = {
        features = {
          hostDNS = {
            enabled              = true
            forwardKubeDNSToHost = true
            resolveMemberNames   = true
          }
        }
        install = {
          disk  = each.value.install_disk
          image = data.talos_image_factory_urls.home.urls.installer
        }
      }
      cluster = {
        allowSchedulingOnControlPlanes = true
        network = {
          cni = {
            name = "none"
          }
          podSubnets     = [local.home_cluster.pod_subnet]
          serviceSubnets = [local.home_cluster.service_subnet]
        }
      }
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "HostnameConfig"
      auto       = "off"
      hostname   = each.key
    }),
  ]
}

resource "talos_machine_configuration_apply" "node" {
  for_each = local.talos_nodes

  apply_mode = "auto"
  client_configuration_wo = {
    ca_certificate     = talos_machine_secrets.cluster.client_configuration.ca_certificate
    client_certificate = talos_machine_secrets.cluster.client_configuration.client_certificate
    client_key         = talos_machine_secrets.cluster.client_configuration.client_key
  }
  endpoint                       = local.talos_connection_endpoints[each.key]
  machine_configuration_input_wo = ephemeral.talos_machine_configuration.node[each.key].machine_configuration
  node                           = local.talos_connection_endpoints[each.key]

  on_destroy = {
    graceful = false
    reboot   = false
    reset    = false
  }

  timeouts = {
    create = "10m"
    update = "10m"
  }

  depends_on = [onepassword_item.talos_recovery]
}
