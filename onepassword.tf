data "onepassword_vault" "configured" {
  for_each = local.onepassword_vaults

  name = each.value
}

locals {
  # Provider 3.3.1 updates write-only values only when their version increases.
  # The offset keeps replacement timestamps above historical 60-bit fingerprints.
  onepassword_timestamp_version_offset = pow(2, 61)

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

  onepassword_machine_access = {
    for name, machine in local.machines : name => {
      title    = "${lookup(local.onepassword_machine_access_display_names, coalesce(try(machine.type, null), machine.platform), title(coalesce(try(machine.type, null), machine.platform)))}: ${local.machine_fqdns[name]}"
      url      = can(machine.services.management) ? "${machine.services.management.scheme}://${local.machine_fqdns[name]}${contains(["http:80", "https:443"], "${machine.services.management.scheme}:${machine.services.management.port}") ? "" : ":${machine.services.management.port}"}" : "ssh://${machine.username}@${local.machine_fqdns[name]}"
      username = machine.username
    }
    if machine.platform != "talos" && try(machine.username, null) != null
  }

  onepassword_machine_access_display_names = {
    macos   = "macOS"
    steamos = "SteamOS"
  }

  onepassword_machine_access_password_policy = {
    length  = 32
    special = false
  }

  onepassword_talos_recovery_note_values = {
    for name, cluster in local.clusters : name => jsonencode({
      client_configuration = talos_machine_secrets.cluster[name].client_configuration
      cluster_name         = name
      machine_secrets      = talos_machine_secrets.cluster[name].machine_secrets
      talos_version        = cluster.talos_version
    })
  }

  onepassword_vaults = merge(
    local.access.onepassword.vaults,
    {
      for name in keys(local.clusters) : "cluster/${name}" => "${local.access.onepassword.cluster_vault_prefix}${upper(name)}"
    },
  )

  onepassword_version_triggers = merge(
    { for name in local.b2_clusters : "backblaze_cluster/${name}" => sha256(b2_application_key.cluster[name].application_key_id) },
    { for name in keys(local.b2_hosts) : "backblaze_host/${name}" => sha256(b2_application_key.host[name].application_key_id) },
    { for name in keys(local.cloudflare_consumers_acme) : "cloudflare_acme/${name}" => sha256(cloudflare_account_token.acme[name].id) },
    { for name in keys(local.cloudflare_consumers_external_dns) : "cloudflare_external_dns/${name}" => sha256(cloudflare_account_token.external_dns[name].id) },
    { for name in keys(local.cloudflare_consumers_tunnel) : "cloudflare_tunnel/${name}" => sha256(cloudflare_zero_trust_tunnel_cloudflared.cluster[name].id) },
    { for name in keys(local.cloudflare_consumers_waf) : "cloudflare_waf/${name}" => sha256(cloudflare_account_token.waf[name].id) },
    {
      for name in keys(local.onepassword_machine_access) : "machine_access/${name}" => sha256(jsonencode({
        machine = name
        policy  = local.onepassword_machine_access_password_policy
      }))
    },
    { for name in keys(local.clusters) : "resend/${name}" => sha256(resend_api_key.cluster[name].id) },
    { resend_fly = sha256(resend_api_key.fly.id) },
    { for name in local.resend_hosts : "resend_host/${name}" => sha256(resend_api_key.host[name].id) },
    { for name in keys(local.tailscale_key_machines) : "tailscale_auth_key/${name}" => sha256(tailscale_tailnet_key.server[name].id) },
    { tailscale_fly = sha256(tailscale_oauth_client.fly.id) },
    { for name in keys(local.clusters) : "tailscale_operator/${name}" => sha256(tailscale_oauth_client.kubernetes_operator[name].id) },
    {
      for name, cluster in local.clusters : "talos_recovery/${name}" => sha256(jsonencode({
        machine_secrets_id = talos_machine_secrets.cluster[name].id
        talos_version      = cluster.talos_version
      }))
    },
    {
      for name in keys(local.clusters) : "talosconfig/${name}" => sha256(jsonencode({
        client_certificate = talos_machine_secrets.cluster[name].client_configuration.client_certificate
        endpoints          = data.talos_client_configuration.cluster[name].endpoints
        machine_secrets_id = talos_machine_secrets.cluster[name].id
        nodes              = data.talos_client_configuration.cluster[name].nodes
      }))
    },
  )

  onepassword_versions = {
    for key, version in terraform_data.onepassword_version :
    key => local.onepassword_timestamp_version_offset + parseint(formatdate("YYYYMMDDhhmmss", version.output), 10)
  }
}

ephemeral "random_password" "machine_access" {
  for_each = local.onepassword_machine_access

  length  = local.onepassword_machine_access_password_policy.length
  special = local.onepassword_machine_access_password_policy.special
}

resource "onepassword_item" "backblaze_cluster" {
  for_each = local.b2_clusters

  category            = "login"
  password_wo         = b2_application_key.cluster[each.key].application_key
  password_wo_version = local.onepassword_versions["backblaze_cluster/${each.key}"]
  tags                = [local.access.onepassword.ownership_tag]
  title               = "Backblaze B2"
  url                 = local.b2_endpoint
  username            = b2_application_key.cluster[each.key].application_key_id
  vault               = data.onepassword_vault.configured["cluster/${each.key}"].uuid
}

resource "onepassword_item" "backblaze_host" {
  for_each = local.b2_hosts

  category            = "login"
  password_wo         = b2_application_key.host[each.key].application_key
  password_wo_version = local.onepassword_versions["backblaze_host/${each.key}"]
  title               = "Backblaze B2: ${try(local.machine_fqdns[each.key], each.key)}"
  url                 = local.b2_endpoint
  username            = b2_application_key.host[each.key].application_key_id
  vault               = data.onepassword_vault.configured["homelab"].uuid

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

resource "onepassword_item" "cloudflare_acme" {
  for_each = local.cloudflare_consumers_acme

  category            = "login"
  password_wo         = cloudflare_account_token.acme[each.key].value
  password_wo_version = local.onepassword_versions["cloudflare_acme/${each.key}"]
  tags                = can(local.machines[each.key]) ? [] : [local.access.onepassword.ownership_tag]
  title               = can(local.machines[each.key]) ? "Cloudflare ACME DNS: ${local.machine_fqdns[each.key]}" : "Cloudflare ACME DNS"
  vault               = data.onepassword_vault.configured[can(local.machines[each.key]) ? "homelab" : "cluster/${each.key}"].uuid
}

resource "onepassword_item" "cloudflare_external_dns" {
  for_each = local.cloudflare_consumers_external_dns

  category            = "login"
  password_wo         = cloudflare_account_token.external_dns[each.key].value
  password_wo_version = local.onepassword_versions["cloudflare_external_dns/${each.key}"]
  tags                = [local.access.onepassword.ownership_tag]
  title               = "Cloudflare ExternalDNS"
  vault               = data.onepassword_vault.configured["cluster/${each.key}"].uuid
}

resource "onepassword_item" "cloudflare_tunnel" {
  for_each = local.cloudflare_consumers_tunnel

  category            = "login"
  password_wo         = data.cloudflare_zero_trust_tunnel_cloudflared_token.cluster[each.key].token
  password_wo_version = local.onepassword_versions["cloudflare_tunnel/${each.key}"]
  tags                = can(local.machines[each.key]) ? [] : [local.access.onepassword.ownership_tag]
  title               = can(local.machines[each.key]) ? "Cloudflare Tunnel: ${local.machine_fqdns[each.key]}" : "Cloudflare Tunnel"
  vault               = data.onepassword_vault.configured[can(local.machines[each.key]) ? "homelab" : "cluster/${each.key}"].uuid
}

resource "onepassword_item" "cloudflare_waf" {
  for_each = local.cloudflare_consumers_waf

  category            = "login"
  password_wo         = cloudflare_account_token.waf[each.key].value
  password_wo_version = local.onepassword_versions["cloudflare_waf/${each.key}"]
  tags                = [local.access.onepassword.ownership_tag]
  title               = "Cloudflare WAF"
  vault               = data.onepassword_vault.configured["cluster/${each.key}"].uuid
}

resource "onepassword_item" "control_d" {
  for_each = local.clusters

  category = "login"
  password = var.control_d_api_key
  tags     = [local.access.onepassword.ownership_tag]
  title    = "Control D"
  vault    = data.onepassword_vault.configured["cluster/${each.key}"].uuid
}

resource "onepassword_item" "infrastructure_inventory" {
  for_each = local.clusters

  # This snapshot contains only provider identities, never credentials.
  category   = "secure_note"
  note_value = jsonencode(local.infrastructure_inventory)
  tags       = [local.access.onepassword.ownership_tag]
  title      = "Infrastructure Inventory"
  vault      = data.onepassword_vault.configured["cluster/${each.key}"].uuid
}

resource "onepassword_item" "kubeconfig" {
  for_each = local.clusters

  category              = "secure_note"
  note_value_wo         = local.onepassword_kubeconfig_note_values[each.key]
  note_value_wo_version = local.onepassword_timestamp_version_offset + parseint(formatdate("YYYYMMDDhhmmss", terraform_data.onepassword_kubeconfig_note_value_version[each.key].output), 10)
  tags                  = [local.access.onepassword.ownership_tag]
  title                 = "Kubernetes Client Configuration"
  vault                 = data.onepassword_vault.configured["cluster/${each.key}"].uuid
}

resource "onepassword_item" "machine_access" {
  for_each = local.onepassword_machine_access

  category            = "login"
  password_wo         = ephemeral.random_password.machine_access[each.key].result
  password_wo_version = local.onepassword_versions["machine_access/${each.key}"]
  title               = each.value.title
  url                 = each.value.url
  username            = each.value.username
  vault               = data.onepassword_vault.configured["homelab"].uuid
}

resource "onepassword_item" "resend" {
  for_each = local.clusters

  category            = "login"
  password_wo         = resend_api_key.cluster[each.key].token
  password_wo_version = local.onepassword_versions["resend/${each.key}"]
  tags                = [local.access.onepassword.ownership_tag]
  title               = "Resend"
  url                 = "https://resend.com/api-keys"
  username            = resend_api_key.cluster[each.key].id
  vault               = data.onepassword_vault.configured["cluster/${each.key}"].uuid
}

resource "onepassword_item" "resend_fly" {
  category            = "login"
  password_wo         = resend_api_key.fly.token
  password_wo_version = local.onepassword_versions["resend_fly"]
  tags                = [local.access.onepassword.ownership_tag]
  title               = "Resend"
  url                 = "https://resend.com/api-keys"
  username            = resend_api_key.fly.id
  vault               = data.onepassword_vault.configured["flylab"].uuid
}

resource "onepassword_item" "resend_host" {
  for_each = local.resend_hosts

  category            = "login"
  password_wo         = resend_api_key.host[each.key].token
  password_wo_version = local.onepassword_versions["resend_host/${each.key}"]
  title               = "Resend: ${local.machine_fqdns[each.key]}"
  url                 = "https://resend.com/api-keys"
  username            = resend_api_key.host[each.key].id
  vault               = data.onepassword_vault.configured["homelab"].uuid
}

resource "onepassword_item" "tailscale_auth_key" {
  for_each = local.tailscale_key_machines

  category            = "login"
  password_wo         = tailscale_tailnet_key.server[each.key].key
  password_wo_version = local.onepassword_versions["tailscale_auth_key/${each.key}"]
  title               = "Tailscale Auth Key: ${local.machine_fqdns[each.key]}"
  vault               = data.onepassword_vault.configured["homelab"].uuid
}

resource "onepassword_item" "tailscale_fly" {
  category            = "login"
  password_wo         = tailscale_oauth_client.fly.key
  password_wo_version = local.onepassword_versions["tailscale_fly"]
  tags                = [local.access.onepassword.ownership_tag]
  title               = "Tailscale OAuth Client"
  url                 = "https://login.tailscale.com/admin/settings/oauth"
  username            = tailscale_oauth_client.fly.id
  vault               = data.onepassword_vault.configured["flylab"].uuid
}

resource "onepassword_item" "tailscale_operator" {
  for_each = local.clusters

  category            = "login"
  password_wo         = tailscale_oauth_client.kubernetes_operator[each.key].key
  password_wo_version = local.onepassword_versions["tailscale_operator/${each.key}"]
  tags                = [local.access.onepassword.ownership_tag]
  title               = "Tailscale Kubernetes Operator"
  username            = tailscale_oauth_client.kubernetes_operator[each.key].id
  vault               = data.onepassword_vault.configured["cluster/${each.key}"].uuid
}

resource "onepassword_item" "talos_recovery" {
  for_each = local.clusters

  category              = "secure_note"
  note_value_wo         = local.onepassword_talos_recovery_note_values[each.key]
  note_value_wo_version = local.onepassword_versions["talos_recovery/${each.key}"]
  title                 = "Talos Recovery: ${each.key}"
  vault                 = data.onepassword_vault.configured["homelab"].uuid

  lifecycle {
    prevent_destroy = true
  }
}

resource "onepassword_item" "talosconfig" {
  for_each = local.clusters

  category              = "secure_note"
  note_value_wo         = data.talos_client_configuration.cluster[each.key].talos_config
  note_value_wo_version = local.onepassword_versions["talosconfig/${each.key}"]
  tags                  = [local.access.onepassword.ownership_tag]
  title                 = "Talos Client Configuration"
  vault                 = data.onepassword_vault.configured["cluster/${each.key}"].uuid
}

# Keep kubeconfig tracking separate: its trigger waits for bootstrap, whose node
# configuration waits for the recovery item versioned by the shared resource.
resource "terraform_data" "onepassword_kubeconfig_note_value_version" {
  for_each = local.clusters

  input = plantimestamp()
  triggers_replace = sha256(jsonencode({
    client_certificate = talos_cluster_kubeconfig.cluster[each.key].kubernetes_client_configuration.client_certificate
    endpoint           = local.talos_cluster_endpoints[each.key]
    machine_secrets_id = talos_machine_secrets.cluster[each.key].id
  }))

  lifecycle {
    ignore_changes = [input]
  }
}

resource "terraform_data" "onepassword_version" {
  for_each = local.onepassword_version_triggers

  input            = plantimestamp()
  triggers_replace = each.value

  lifecycle {
    ignore_changes = [input]
  }
}
