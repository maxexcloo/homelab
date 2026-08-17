data "onepassword_vault" "default" {
  for_each = local.onepassword_vaults

  name = each.value
}

resource "onepassword_item" "cloudflare_acme" {
  for_each = local.cloudflare_acme_consumers

  category            = "login"
  password_wo         = cloudflare_account_token.acme[each.key].value
  password_wo_version = try(each.value.secret_revision, 1)
  tags                = ["Homelab", "Cloudflare", "ACME"]
  title               = each.value.title
  url                 = "https://dash.cloudflare.com"
  username            = each.value.credential_scope
  vault               = data.onepassword_vault.default[each.value.vault].uuid

  lifecycle {
    prevent_destroy = true
  }
}

resource "onepassword_item" "cloudflare_tunnel" {
  for_each = local.cloudflare_tunnels

  category            = "login"
  password_wo         = data.cloudflare_zero_trust_tunnel_cloudflared_token.cluster[each.key].token
  password_wo_version = try(local.domains.cloudflare.tunnel_secret_revision, 1)
  tags                = each.value.tags
  title               = each.value.title
  username            = cloudflare_zero_trust_tunnel_cloudflared.cluster[each.key].id
  vault               = data.onepassword_vault.default["cluster/${each.key}"].uuid

  lifecycle {
    prevent_destroy = true
  }
}

resource "onepassword_item" "machine_access" {
  for_each = local.machines

  category            = "login"
  password_wo         = tailscale_tailnet_key.server[each.key].key
  password_wo_version = try(local.access.tailscale.server_secret_revision, 1)
  tags                = ["Homelab", "Tailscale", "Bootstrap"]
  title               = "Tailscale Recovery Key: ${local.machine_fqdns[each.key]}"
  url                 = local.machine_access[each.key].url
  username            = local.machine_access[each.key].username
  vault               = data.onepassword_vault.default["homelab"].uuid

  lifecycle {
    prevent_destroy = true
  }
}

resource "onepassword_item" "tailscale_operator" {
  for_each = local.clusters

  category            = "login"
  password_wo         = tailscale_oauth_client.kubernetes_operator[each.key].key
  password_wo_version = try(local.access.tailscale.operator.secret_revision, 1)
  tags                = ["Homelab", "Tailscale", "Kubernetes"]
  title               = "tailscale-operator"
  username            = tailscale_oauth_client.kubernetes_operator[each.key].id
  vault               = data.onepassword_vault.default["cluster/${each.key}"].uuid

  lifecycle {
    prevent_destroy = true
  }
}
