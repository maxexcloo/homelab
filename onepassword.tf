# Kept by hand: Fly.io issues its deploy token outside OpenTofu.
data "onepassword_item" "fly" {
  title = "Fly.io"
  vault = data.onepassword_vault.configured["homelab"].uuid
}

# Restic owns its existing repository password.
data "onepassword_item" "s3_backups" {
  for_each = local.clusters

  title = "S3 Backups: ${each.key}"
  vault = data.onepassword_vault.configured["homelab"].uuid
}

data "onepassword_vault" "configured" {
  for_each = local.onepassword_vaults

  name = each.value
}

locals {
  onepassword_infrastructure_inventory = {
    cloudflare = {
      account_id = data.cloudflare_account.default.id
      access_policies = {
        bypass    = cloudflare_zero_trust_access_policy.bypass.id
        excloo_id = cloudflare_zero_trust_access_policy.pocket_id.id
        gatus     = cloudflare_zero_trust_access_policy.fly.id
      }
      tunnels = { for name, tunnel in cloudflare_zero_trust_tunnel_cloudflared.cluster : name => tunnel.id }
    }
    hosts = {
      for name, machine in local.machines : name => try(coalesce(
        can(local.dns_records_derived_specs["machine/${name}/a"]) || can(local.dns_records_derived_specs["machine/${name}/aaaa"]) ? local.machine_fqdns[name] : null,
        local.machine_private_ipv4_addresses[name],
        try(machine.public_ipv4, null),
      ), null)
    }
    tailscale = {
      for name, device_name in local.machine_tailscale_names :
      name => {
        id   = local.tailscale_devices[device_name].node_id
        ipv4 = local.tailscale_device_addresses[device_name].ipv4
      }
      if can(local.tailscale_devices[device_name])
    }
  }

  onepassword_kubeconfig_documents = {
    for name, configuration in talos_cluster_kubeconfig.cluster :
    name => yamldecode(configuration.kubeconfig_raw)
  }

  onepassword_kubeconfig_note_values = {
    for name, document in local.onepassword_kubeconfig_documents : name => yamlencode(merge(document, {
      clusters = [
        for kubeconfig_cluster in document.clusters : merge(kubeconfig_cluster, {
          cluster = merge(kubeconfig_cluster.cluster, {
            server = local.talos_cluster_endpoints[name]
          })
        })
      ]
    }))
  }

  # Untyped machines are personal devices; their logins stay outside OpenTofu.
  onepassword_machine_access = {
    for name, machine in local.machines : name => {
      title    = local.machine_login_titles[name]
      url      = "https://${local.machine_fqdns[name]}"
      username = machine.username
    }
    if machine.platform != "talos" && machine.type != null && try(machine.username, null) != null
  }

  onepassword_password_policy = {
    length  = 32
    special = false
  }

  onepassword_service_access = {
    for service_key, service in local.machine_services : service_key => {
      name     = service.name
      url      = service.url
      username = service.credentials.username
    }
    if can(service.credentials)
  }

  onepassword_vaults = merge(
    local.access.onepassword.vaults,
    {
      for name in keys(local.clusters) : "cluster/${name}" => "${local.access.onepassword.cluster_vault_prefix}${upper(name)}"
    },
  )
}

# Generated passwords are written once: the provider keeps the stored value
# unless the version increases.
ephemeral "random_password" "machine_access" {
  for_each = local.onepassword_machine_access

  length  = local.onepassword_password_policy.length
  special = local.onepassword_password_policy.special
}

ephemeral "random_password" "service_access" {
  for_each = local.onepassword_service_access

  length  = local.onepassword_password_policy.length
  special = local.onepassword_password_policy.special
}

resource "onepassword_item" "backblaze_cluster" {
  for_each = local.b2_clusters

  category = "login"
  password = b2_application_key.cluster[each.key].application_key
  tags     = [local.access.onepassword.ownership_tag]
  title    = "Backblaze B2"
  url      = local.b2_endpoint
  username = b2_application_key.cluster[each.key].application_key_id
  vault    = data.onepassword_vault.configured["cluster/${each.key}"].uuid
}

resource "onepassword_item" "backblaze_host" {
  for_each = local.b2_hosts

  category = "login"
  password = b2_application_key.host[each.key].application_key
  title    = "Backblaze B2: ${local.machine_fqdns[each.key]}"
  url      = local.b2_endpoint
  username = b2_application_key.host[each.key].application_key_id
  vault    = data.onepassword_vault.configured["homelab"].uuid

  section_map = {
    storage = {
      field_map = {
        bucket = {
          value = b2_bucket.host[each.key].bucket_name
        }
      }
    }
  }
}

resource "onepassword_item" "cloudflare_access" {
  tags  = [local.access.onepassword.ownership_tag]
  title = "Cloudflare Access"
  vault = data.onepassword_vault.configured["cluster/${local.access.cloudflare_access.cluster}"].uuid

  # Kubelab's PushSecret created this server item, a category the provider cannot
  # express, and owns its fields, including the Pocket ID client's generated secret.
  lifecycle {
    ignore_changes = [category, section]
  }
}

resource "onepassword_item" "cloudflare_access_applications" {
  for_each = local.cloudflare_consumers_access_applications

  category = "login"
  password = cloudflare_account_token.access_applications[each.key].value
  tags     = [local.access.onepassword.ownership_tag]
  title    = "Cloudflare Access Applications"
  vault    = data.onepassword_vault.configured["cluster/${each.key}"].uuid
}

resource "onepassword_item" "cloudflare_access_fly" {
  category = "login"
  password = cloudflare_zero_trust_access_service_token.fly.client_secret
  tags     = [local.access.onepassword.ownership_tag]
  title    = "Cloudflare Access Service Token"
  username = cloudflare_zero_trust_access_service_token.fly.client_id
  vault    = data.onepassword_vault.configured["flylab"].uuid
}

resource "onepassword_item" "cloudflare_acme" {
  for_each = local.cloudflare_consumers_acme

  category = "login"
  password = cloudflare_account_token.acme[each.key].value
  tags     = can(local.machines[each.key]) ? [] : [local.access.onepassword.ownership_tag]
  title    = can(local.machines[each.key]) ? "Cloudflare ACME DNS: ${local.machine_fqdns[each.key]}" : "Cloudflare ACME DNS"
  vault    = data.onepassword_vault.configured[can(local.machines[each.key]) ? "homelab" : "cluster/${each.key}"].uuid
}

resource "onepassword_item" "cloudflare_external_dns" {
  for_each = local.cloudflare_consumers_external_dns

  category = "login"
  password = cloudflare_account_token.external_dns[each.key].value
  tags     = [local.access.onepassword.ownership_tag]
  title    = "Cloudflare ExternalDNS"
  vault    = data.onepassword_vault.configured["cluster/${each.key}"].uuid
}

resource "onepassword_item" "cloudflare_tunnel" {
  for_each = local.cloudflare_consumers_tunnel

  category = "login"
  password = data.cloudflare_zero_trust_tunnel_cloudflared_token.cluster[each.key].token
  tags     = can(local.machines[each.key]) ? [] : [local.access.onepassword.ownership_tag]
  title    = can(local.machines[each.key]) ? "Cloudflare Tunnel: ${local.machine_fqdns[each.key]}" : "Cloudflare Tunnel"
  vault    = data.onepassword_vault.configured[can(local.machines[each.key]) ? "homelab" : "cluster/${each.key}"].uuid
}

resource "onepassword_item" "cloudflare_tunnel_monitoring" {
  for_each = local.clusters

  category = "login"
  password = cloudflare_account_token.tunnel_monitoring[each.key].value
  tags     = [local.access.onepassword.ownership_tag]
  title    = "Cloudflare Tunnel Monitoring"
  url      = local.cloudflare.url
  vault    = data.onepassword_vault.configured["cluster/${each.key}"].uuid
}

resource "onepassword_item" "cloudflare_waf" {
  for_each = local.cloudflare_consumers_waf

  category = "login"
  password = cloudflare_account_token.waf[each.key].value
  tags     = [local.access.onepassword.ownership_tag]
  title    = "Cloudflare WAF"
  vault    = data.onepassword_vault.configured["cluster/${each.key}"].uuid
}

resource "onepassword_item" "control_d" {
  for_each = local.clusters

  category = "login"
  password = var.control_d_api_key
  tags     = [local.access.onepassword.ownership_tag]
  title    = "Control D"
  vault    = data.onepassword_vault.configured["cluster/${each.key}"].uuid
}

resource "onepassword_item" "fly" {
  category = "login"
  password = data.onepassword_item.fly.password
  tags     = [local.access.onepassword.ownership_tag]
  title    = "Fly.io"
  url      = local.provider_settings.providers.fly.url
  vault    = data.onepassword_vault.configured["flylab"].uuid
}

resource "onepassword_item" "infrastructure_inventory" {
  for_each = local.clusters

  # This snapshot contains only provider identities, never credentials.
  category   = "secure_note"
  note_value = jsonencode(local.onepassword_infrastructure_inventory)
  tags       = [local.access.onepassword.ownership_tag]
  title      = "Infrastructure Inventory"
  vault      = data.onepassword_vault.configured["cluster/${each.key}"].uuid
}

resource "onepassword_item" "kubeconfig" {
  for_each = local.clusters

  category   = "secure_note"
  note_value = local.onepassword_kubeconfig_note_values[each.key]
  tags       = [local.access.onepassword.ownership_tag]
  title      = "Kubernetes Client Configuration"
  vault      = data.onepassword_vault.configured["cluster/${each.key}"].uuid
}

resource "onepassword_item" "machine_access" {
  for_each = local.onepassword_machine_access

  category            = "login"
  password_wo         = ephemeral.random_password.machine_access[each.key].result
  password_wo_version = 1
  title               = each.value.title
  url                 = each.value.url
  username            = each.value.username
  vault               = data.onepassword_vault.configured["homelab"].uuid
}

resource "onepassword_item" "resend" {
  for_each = local.clusters

  category = "login"
  password = resend_api_key.cluster[each.key].token
  tags     = [local.access.onepassword.ownership_tag]
  title    = "Resend"
  url      = "https://resend.com/api-keys"
  username = resend_api_key.cluster[each.key].id
  vault    = data.onepassword_vault.configured["cluster/${each.key}"].uuid
}

resource "onepassword_item" "resend_fly" {
  category = "login"
  password = resend_api_key.fly.token
  tags     = [local.access.onepassword.ownership_tag]
  title    = "Resend"
  url      = "https://resend.com/api-keys"
  username = resend_api_key.fly.id
  vault    = data.onepassword_vault.configured["flylab"].uuid
}

resource "onepassword_item" "resend_host" {
  for_each = local.resend_hosts

  category = "login"
  password = resend_api_key.host[each.key].token
  title    = "Resend: ${local.machine_fqdns[each.key]}"
  url      = "https://resend.com/api-keys"
  username = resend_api_key.host[each.key].id
  vault    = data.onepassword_vault.configured["homelab"].uuid
}

resource "onepassword_item" "s3_backup_access_key" {
  for_each = local.truenas_s3_backup_hosts

  category = "login"
  password = truenas_s3_access_key.backups[each.key].secret
  tags     = [local.access.onepassword.ownership_tag]
  title    = "S3 Backup Access Key"
  username = truenas_s3_access_key.backups[each.key].access_key
  vault    = data.onepassword_vault.configured["cluster/${each.key}"].uuid
}

resource "onepassword_item" "s3_backups" {
  for_each = local.clusters

  # An explicit empty password disables automatic password generation.
  category = "login"
  password = ""
  tags     = [local.access.onepassword.ownership_tag]
  title    = "S3 Backups"
  username = ""
  vault    = data.onepassword_vault.configured["cluster/${each.key}"].uuid

  section_map = {
    backup = {
      field_map = {
        for label, field in data.onepassword_item.s3_backups[each.key].section_map.backup.field_map : label => {
          type  = field.type
          value = field.value
        } if label == "restic-password"
      }
    }
  }
}

resource "onepassword_item" "service_access" {
  for_each = local.onepassword_service_access

  category            = "login"
  password_wo         = ephemeral.random_password.service_access[each.key].result
  password_wo_version = 1
  title               = each.value.name
  url                 = each.value.url
  username            = each.value.username
  vault               = data.onepassword_vault.configured["homelab"].uuid
}

resource "onepassword_item" "sidestore_vpn" {
  for_each = local.clusters

  category = "login"
  password = tailscale_tailnet_key.sidestore_vpn[each.key].key
  tags     = [local.access.onepassword.ownership_tag]
  title    = "SideStore VPN"
  vault    = data.onepassword_vault.configured["cluster/${each.key}"].uuid
}

resource "onepassword_item" "tailscale_auth_key" {
  for_each = local.tailscale_key_machines

  category = "login"
  password = tailscale_tailnet_key.server[each.key].key
  title    = "Tailscale Auth Key: ${local.machine_fqdns[each.key]}"
  vault    = data.onepassword_vault.configured["homelab"].uuid
}

resource "onepassword_item" "tailscale_fly" {
  category = "login"
  password = tailscale_oauth_client.fly.key
  tags     = [local.access.onepassword.ownership_tag]
  title    = "Tailscale OAuth Client"
  url      = "https://login.tailscale.com/admin/settings/oauth"
  username = tailscale_oauth_client.fly.id
  vault    = data.onepassword_vault.configured["flylab"].uuid
}

resource "onepassword_item" "talos_recovery" {
  for_each = local.clusters

  category = "secure_note"
  title    = "Talos Recovery: ${each.key}"
  vault    = data.onepassword_vault.configured["homelab"].uuid

  note_value = jsonencode({
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
  for_each = local.clusters

  category   = "secure_note"
  note_value = data.talos_client_configuration.cluster[each.key].talos_config
  tags       = [local.access.onepassword.ownership_tag]
  title      = "Talos Client Configuration"
  vault      = data.onepassword_vault.configured["cluster/${each.key}"].uuid
}

resource "onepassword_item" "truenas_monitoring" {
  for_each = {
    for name in keys(local.clusters) : name => one(values(local.truenas_monitoring_hosts))
  }

  category = "login"
  password = truenas_api_key.monitoring[each.value.machine].key
  tags     = [local.access.onepassword.ownership_tag]
  title    = "TrueNAS Monitoring"
  url      = each.value.url
  username = truenas_user.monitoring[each.value.machine].username
  vault    = data.onepassword_vault.configured["cluster/${each.key}"].uuid
}
