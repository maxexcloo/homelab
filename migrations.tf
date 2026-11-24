removed {
  from = truenas_app.talos_container

  lifecycle {
    destroy = false
  }
}

import {
  for_each = local.truenas_talos_containers

  to = truenas_app.controlplane[each.key]
  id = "talos"
}

removed {
  from = truenas_cronjob.host

  lifecycle {
    destroy = false
  }
}

import {
  for_each = {
    "saturn/icloud-photos-check" = "4"
    "saturn/icloud-photos-copy"  = "3"
    "saturn/smart-long"          = "2"
    "saturn/smart-short"         = "1"
  }

  to = truenas_cronjob.configured[each.key]
  id = each.value
}

removed {
  from = truenas_dataset.child

  lifecycle {
    destroy = false
  }
}

import {
  for_each = local.truenas_datasets_child

  to = truenas_dataset.nested[each.key]
  id = each.value.path
}

removed {
  from = truenas_dataset.root

  lifecycle {
    destroy = false
  }
}

import {
  for_each = local.truenas_datasets_root

  to = truenas_dataset.top_level[each.key]
  id = each.value.path
}

removed {
  from = truenas_init_script.host

  lifecycle {
    destroy = false
  }
}

import {
  for_each = {
    "saturn/crucial-x9-trim" = "1"
  }

  to = truenas_init_shutdown_script.host[each.key]
  id = each.value
}

removed {
  from = truenas_mail_config.host

  lifecycle {
    destroy = false
  }
}

import {
  for_each = {
    for name, host in local.truenas_hosts : name => host
    if contains(local.resend_hosts, name)
  }

  to = truenas_mail.host[each.key]
  id = "mail"
}

removed {
  from = truenas_network_config.host

  lifecycle {
    destroy = false
  }
}

import {
  for_each = {
    for name, host in local.truenas_hosts : name => host
    if can(host.network_configuration)
  }

  to = truenas_network_config.global[each.key]
  id = "network_config"
}

removed {
  from = truenas_network_interface.container_bridge

  lifecycle {
    destroy = false
  }
}

import {
  for_each = local.truenas_container_bridges

  to = truenas_network_interface.talos_bridge[each.key]
  id = each.value.bridge
}

removed {
  from = truenas_network_interface.container_physical

  lifecycle {
    destroy = false
  }
}

import {
  for_each = local.truenas_container_bridges

  to = truenas_network_interface.talos_uplink[each.key]
  id = each.value.name
}

removed {
  from = truenas_service.host

  lifecycle {
    destroy = false
  }
}

import {
  for_each = local.truenas_services

  to = truenas_service.configured[each.key]
  id = each.value.service
}

removed {
  from = truenas_service.s3

  lifecycle {
    destroy = false
  }
}

import {
  for_each = {
    for name, host in local.truenas_hosts : name => host
    if can(host.services.s3)
  }

  to = truenas_service.backup_storage[each.key]
  id = "s3"
}

removed {
  from = truenas_share_smb.dataset

  lifecycle {
    destroy = false
  }
}

import {
  for_each = {
    "saturn/truenas/backups"                   = "6"
    "saturn/truenas/documents"                 = "7"
    "saturn/truenas/games"                     = "12"
    "saturn/truenas/home-assistant"            = "4"
    "saturn/truenas/icloud-photos"             = "10"
    "saturn/truenas/music"                     = "15"
    "saturn/truenas/pictures"                  = "16"
    "saturn/truenas/projects"                  = "8"
    "saturn/truenas/public"                    = "9"
    "saturn/truenas/time-machine/ginny.koh"    = "17"
    "saturn/truenas/time-machine/max.schaefer" = "2"
    "saturn/truenas/unsorted"                  = "13"
  }

  to = truenas_smb_share.dataset[each.key]
  id = each.value
}

removed {
  from = truenas_smb_config.host

  lifecycle {
    destroy = false
  }
}

import {
  for_each = {
    for name, host in local.truenas_hosts : name => host
    if can(host.smb)
  }

  to = truenas_smb_config.global[each.key]
  id = "smb_config"
}

removed {
  from = truenas_snapshot_task.pool

  lifecycle {
    destroy = false
  }
}

import {
  for_each = {
    "saturn/truenas-daily"        = "1"
    "saturn/truenas-monthly"      = "4"
    "saturn/truenas-nvme-daily"   = "3"
    "saturn/truenas-nvme-monthly" = "5"
  }

  to = truenas_periodic_snapshot_task.pool[each.key]
  id = each.value
}

removed {
  from = truenas_ssh_config.host

  lifecycle {
    destroy = false
  }
}

import {
  for_each = {
    for name, host in local.truenas_hosts : name => host
    if can(host.ssh)
  }

  to = truenas_ssh_config.global[each.key]
  id = "ssh_config"
}

removed {
  from = truenas_tunable.host

  lifecycle {
    destroy = false
  }
}

import {
  for_each = {
    "saturn/net.core.rmem_max"            = "3"
    "saturn/net.core.wmem_max"            = "4"
    "saturn/net.ipv4.conf.all.forwarding" = "5"
    "saturn/net.ipv6.conf.all.forwarding" = "6"
  }

  to = truenas_tunable.configured[each.key]
  id = each.value
}

removed {
  from = truenas_ups_config.host

  lifecycle {
    destroy = false
  }
}

import {
  for_each = {
    for name, host in local.truenas_hosts : name => host
    if can(host.ups)
  }

  to = truenas_ups_config.global[each.key]
  id = "ups_config"
}

removed {
  from = truenas_user.s3

  lifecycle {
    destroy = false
  }
}

import {
  for_each = {
    "saturn" = "80"
  }

  to = truenas_user.backup_storage[each.key]
  id = each.value
}
