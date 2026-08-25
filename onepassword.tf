data "onepassword_vault" "default" {
  for_each = local.onepassword_vaults

  name = each.value
}

locals {
  # Content fingerprints update write-only values without manual revision counters.
  onepassword_cloudflare_acme_password_versions = {
    for name, token in cloudflare_account_token.acme : name => nonsensitive(
      parseint(substr(sha256(token.value), 0, 15), 16)
    )
  }

  onepassword_cloudflare_external_dns_password_versions = {
    for name, token in cloudflare_account_token.external_dns : name => nonsensitive(
      parseint(substr(sha256(token.value), 0, 15), 16)
    )
  }

  onepassword_cloudflare_tunnel_password_versions = {
    for name, tunnel in data.cloudflare_zero_trust_tunnel_cloudflared_token.cluster : name => nonsensitive(
      parseint(substr(sha256(tunnel.token), 0, 15), 16)
    )
  }

  onepassword_kubeconfig_note_versions = {
    for name, kubeconfig in talos_cluster_kubeconfig.cluster : name => nonsensitive(
      parseint(substr(sha256(kubeconfig.kubeconfig_raw), 0, 15), 16)
    )
  }

  onepassword_tailscale_auth_key_password_versions = {
    for name, auth_key in tailscale_tailnet_key.server : name => nonsensitive(
      parseint(substr(sha256(auth_key.key), 0, 15), 16)
    )
  }

  onepassword_tailscale_operator_password_versions = {
    for name, oauth_client in tailscale_oauth_client.kubernetes_operator : name => nonsensitive(
      parseint(substr(sha256(oauth_client.key), 0, 15), 16)
    )
  }

  onepassword_talos_recovery_note_values = {
    for name, cluster in local.talos_clusters : name => jsonencode({
      client_configuration = talos_machine_secrets.cluster[name].client_configuration
      cluster_name         = name
      machine_secrets      = talos_machine_secrets.cluster[name].machine_secrets
      talos_version        = cluster.talos_version
    })
  }

  onepassword_talos_recovery_note_versions = {
    for name, recovery in local.onepassword_talos_recovery_note_values : name => nonsensitive(
      parseint(substr(sha256(recovery), 0, 15), 16)
    )
  }

  onepassword_talosconfig_note_versions = {
    for name, talosconfig in data.talos_client_configuration.cluster : name => nonsensitive(
      parseint(substr(sha256(talosconfig.talos_config), 0, 15), 16)
    )
  }

  onepassword_vaults = merge(
    local.access.onepassword.vaults,
    {
      for name in keys(local.clusters) : "cluster/${name}" => "${local.access.onepassword.cluster_vault_prefix}${name}"
    },
  )
}

resource "onepassword_item" "cloudflare_acme" {
  for_each = local.cloudflare_consumers_acme

  category            = "login"
  password_wo         = cloudflare_account_token.acme[each.key].value
  password_wo_version = local.onepassword_cloudflare_acme_password_versions[each.key]
  tags                = ["ACME", "Cloudflare", "Homelab"]
  title               = each.value.title
  username            = each.value.credential_scope
  vault               = data.onepassword_vault.default[each.value.vault].uuid

  lifecycle {
    prevent_destroy = true
  }
}

resource "onepassword_item" "cloudflare_external_dns" {
  for_each = local.cloudflare_consumers_external_dns

  category            = "login"
  password_wo         = cloudflare_account_token.external_dns[each.key].value
  password_wo_version = local.onepassword_cloudflare_external_dns_password_versions[each.key]
  tags                = ["Cloudflare", "ExternalDNS", "Homelab"]
  title               = each.value.title
  username            = each.key
  vault               = data.onepassword_vault.default[each.value.vault].uuid

  lifecycle {
    prevent_destroy = true
  }
}

resource "onepassword_item" "cloudflare_tunnel" {
  for_each = local.cloudflare_consumers_tunnel

  category            = "login"
  password_wo         = data.cloudflare_zero_trust_tunnel_cloudflared_token.cluster[each.key].token
  password_wo_version = local.onepassword_cloudflare_tunnel_password_versions[each.key]
  tags                = each.value.tags
  title               = each.value.title
  username            = cloudflare_zero_trust_tunnel_cloudflared.cluster[each.key].id
  vault               = data.onepassword_vault.default[each.value.vault].uuid

  lifecycle {
    prevent_destroy = true
  }
}

resource "onepassword_item" "tailscale_auth_key" {
  for_each = local.machines

  category            = "login"
  password_wo         = tailscale_tailnet_key.server[each.key].key
  password_wo_version = local.onepassword_tailscale_auth_key_password_versions[each.key]
  tags                = ["Bootstrap", "Homelab", "Recovery", "Tailscale"]
  title               = "Tailscale Auth Key: ${local.machine_fqdns[each.key]}"
  vault               = data.onepassword_vault.default["homelab"].uuid

  username = try(
    each.value.ssh.user,
    each.value.platform == "talos" ? "talosctl" : each.key,
  )

  lifecycle {
    prevent_destroy = true
  }
}

resource "onepassword_item" "tailscale_operator" {
  for_each = local.clusters

  category            = "login"
  password_wo         = tailscale_oauth_client.kubernetes_operator[each.key].key
  password_wo_version = local.onepassword_tailscale_operator_password_versions[each.key]
  tags                = ["Homelab", "Kubernetes", "Operator", "Tailscale"]
  title               = "tailscale-operator"
  username            = tailscale_oauth_client.kubernetes_operator[each.key].id
  vault               = data.onepassword_vault.default["cluster/${each.key}"].uuid

  lifecycle {
    prevent_destroy = true
  }
}
