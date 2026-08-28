data "onepassword_vault" "default" {
  for_each = local.onepassword_vaults

  name = each.value
}

locals {
  onepassword_machine_access = {
    for name, machine in local.machines : name => {
      title    = "${title(machine.tag)}: ${local.machine_fqdns[name]}"
      url      = try(machine.management_port, null) != null ? "https://${local.machine_fqdns[name]}${machine.management_port == 443 ? "" : ":${machine.management_port}"}" : "ssh://${machine.username}@${local.machine_fqdns[name]}"
      username = machine.username
    }
    if machine.platform != "talos"
  }

  onepassword_machine_access_password_policy = {
    length  = 32
    special = false
  }

  onepassword_talos_recovery_note_values = {
    for name, cluster in local.talos_clusters : name => jsonencode({
      client_configuration = talos_machine_secrets.cluster[name].client_configuration
      cluster_name         = name
      machine_secrets      = talos_machine_secrets.cluster[name].machine_secrets
      talos_version        = cluster.talos_version
    })
  }

  # Keep timestamp-derived versions above the 60-bit content fingerprints used elsewhere.
  onepassword_timestamp_version_offset = pow(2, 61)

  onepassword_vaults = merge(
    local.access.onepassword.vaults,
    {
      for name in keys(local.clusters) : "cluster/${name}" => "${local.access.onepassword.cluster_vault_prefix}${name}"
    },
  )
}

ephemeral "random_password" "machine_access" {
  for_each = local.onepassword_machine_access

  length  = local.onepassword_machine_access_password_policy.length
  special = local.onepassword_machine_access_password_policy.special
}

resource "onepassword_item" "backblaze" {
  for_each = local.b2_hosts

  category            = "login"
  password_wo         = b2_application_key.host[each.key].application_key
  password_wo_version = local.onepassword_timestamp_version_offset + parseint(formatdate("YYYYMMDDhhmmss", terraform_data.onepassword_backblaze_password_version[each.key].output), 10)
  title               = "Backblaze B2: ${try(local.machine_fqdns[each.key], each.key)}"
  url                 = local.b2_endpoint
  username            = b2_application_key.host[each.key].application_key_id
  vault               = data.onepassword_vault.default["homelab"].uuid

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

resource "onepassword_item" "backblaze_cluster" {
  for_each = local.b2_clusters

  category            = "login"
  password_wo         = b2_application_key.cluster[each.key].application_key
  password_wo_version = local.onepassword_timestamp_version_offset + parseint(formatdate("YYYYMMDDhhmmss", terraform_data.onepassword_backblaze_cluster_password_version[each.key].output), 10)
  tags                = ["Homelab"]
  title               = "Backblaze B2"
  url                 = local.b2_endpoint
  username            = b2_application_key.cluster[each.key].application_key_id
  vault               = data.onepassword_vault.default["cluster/${each.key}"].uuid

  lifecycle {
    create_before_destroy = true
  }
}

resource "onepassword_item" "cloudflare_acme" {
  for_each = local.cloudflare_consumers_acme

  category            = "login"
  password_wo         = cloudflare_account_token.acme[each.key].value
  password_wo_version = nonsensitive(parseint(substr(sha256(cloudflare_account_token.acme[each.key].value), 0, 15), 16))
  tags                = each.value.vault == "homelab" ? [] : ["Homelab"]
  title               = each.value.title
  vault               = data.onepassword_vault.default[each.value.vault].uuid
}

resource "onepassword_item" "cloudflare_external_dns" {
  for_each = local.cloudflare_consumers_external_dns

  category            = "login"
  password_wo         = cloudflare_account_token.external_dns[each.key].value
  password_wo_version = nonsensitive(parseint(substr(sha256(cloudflare_account_token.external_dns[each.key].value), 0, 15), 16))
  tags                = ["Homelab"]
  title               = each.value.title
  vault               = data.onepassword_vault.default[each.value.vault].uuid
}

resource "onepassword_item" "cloudflare_tunnel" {
  for_each = local.cloudflare_consumers_tunnel

  category            = "login"
  password_wo         = data.cloudflare_zero_trust_tunnel_cloudflared_token.cluster[each.key].token
  password_wo_version = nonsensitive(parseint(substr(sha256(data.cloudflare_zero_trust_tunnel_cloudflared_token.cluster[each.key].token), 0, 15), 16))
  tags                = each.value.vault == "homelab" ? [] : ["Homelab"]
  title               = each.value.title
  vault               = data.onepassword_vault.default[each.value.vault].uuid
}

resource "onepassword_item" "cloudflare_waf" {
  for_each = local.cloudflare_consumers_waf

  category            = "login"
  password_wo         = cloudflare_account_token.waf[each.key].value
  password_wo_version = nonsensitive(parseint(substr(sha256(cloudflare_account_token.waf[each.key].value), 0, 15), 16))
  tags                = ["Homelab"]
  title               = "Cloudflare WAF"
  vault               = data.onepassword_vault.default["cluster/${each.key}"].uuid

  lifecycle {
    create_before_destroy = true
  }
}

resource "onepassword_item" "control_d" {
  for_each = local.clusters

  # Keep version zero unchanged so a manually populated password is preserved.
  category            = "login"
  password_wo         = ""
  password_wo_version = 0
  tags                = ["Homelab"]
  title               = "Control D"
  vault               = data.onepassword_vault.default["cluster/${each.key}"].uuid

  lifecycle {
    create_before_destroy = true
  }
}

resource "onepassword_item" "machine_access" {
  for_each = local.onepassword_machine_access

  category    = "login"
  password_wo = ephemeral.random_password.machine_access[each.key].result
  password_wo_version = nonsensitive(parseint(substr(sha256(jsonencode({
    machine = each.key
    policy  = local.onepassword_machine_access_password_policy
  })), 0, 15), 16))
  title    = each.value.title
  url      = each.value.url
  username = each.value.username
  vault    = data.onepassword_vault.default["homelab"].uuid
}

resource "onepassword_item" "resend" {
  for_each = local.clusters

  category            = "login"
  password_wo         = resend_api_key.cluster[each.key].token
  password_wo_version = nonsensitive(parseint(substr(sha256(resend_api_key.cluster[each.key].id), 0, 15), 16))
  tags                = ["Homelab"]
  title               = "Resend"
  url                 = "https://resend.com/api-keys"
  username            = resend_api_key.cluster[each.key].id
  vault               = data.onepassword_vault.default["cluster/${each.key}"].uuid

  lifecycle {
    create_before_destroy = true
  }
}

resource "onepassword_item" "tailscale_auth_key" {
  for_each = local.machines

  category            = "login"
  password_wo         = tailscale_tailnet_key.server[each.key].key
  password_wo_version = nonsensitive(parseint(substr(sha256(tailscale_tailnet_key.server[each.key].key), 0, 15), 16))
  title               = "Tailscale Auth Key: ${local.machine_fqdns[each.key]}"
  vault               = data.onepassword_vault.default["homelab"].uuid
}

resource "onepassword_item" "tailscale_operator" {
  for_each = local.clusters

  category            = "login"
  password_wo         = tailscale_oauth_client.kubernetes_operator[each.key].key
  password_wo_version = nonsensitive(parseint(substr(sha256(tailscale_oauth_client.kubernetes_operator[each.key].key), 0, 15), 16))
  tags                = ["Homelab"]
  title               = "Tailscale Kubernetes Operator"
  username            = tailscale_oauth_client.kubernetes_operator[each.key].id
  vault               = data.onepassword_vault.default["cluster/${each.key}"].uuid
}

resource "terraform_data" "onepassword_backblaze_cluster_password_version" {
  for_each = local.b2_clusters

  input            = plantimestamp()
  triggers_replace = sha256(b2_application_key.cluster[each.key].application_key_id)

  lifecycle {
    ignore_changes = [input]
  }
}

resource "terraform_data" "onepassword_backblaze_password_version" {
  for_each = local.b2_hosts

  input            = plantimestamp()
  triggers_replace = sha256(b2_application_key.host[each.key].application_key_id)

  lifecycle {
    ignore_changes = [input]
  }
}
