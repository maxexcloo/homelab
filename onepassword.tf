data "onepassword_vault" "default" {
  for_each = local.onepassword_vaults

  name = each.value
}

locals {
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
  password_wo_version = try(each.value.secret_revision, 1)
  tags                = ["Homelab", "Cloudflare", "ACME"]
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
  password_wo_version = try(each.value.secret_revision, 1)
  tags                = ["Homelab", "Cloudflare", "ExternalDNS"]
  title               = each.value.title
  username            = data.cloudflare_zone.default[each.value.zone].zone_id
  vault               = data.onepassword_vault.default[each.value.vault].uuid

  lifecycle {
    prevent_destroy = true
  }
}

resource "onepassword_item" "cloudflare_tunnel" {
  for_each = local.cloudflare_consumers_tunnel

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

resource "onepassword_item" "generated" {
  for_each = local.access.onepassword.generated_items

  category = "login"
  tags     = each.value.tags
  title    = each.key
  username = each.value.username
  vault    = data.onepassword_vault.default["cluster/${each.value.cluster}"].uuid

  password_recipe {
    digits  = each.value.password_recipe.digits
    length  = each.value.password_recipe.length
    symbols = each.value.password_recipe.symbols
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "onepassword_item" "tailscale_auth_key" {
  for_each = local.machines

  category            = "login"
  password_wo         = tailscale_tailnet_key.server[each.key].key
  password_wo_version = try(local.access.tailscale.server_secret_revision, 1)
  tags                = ["Homelab", "Tailscale", "Bootstrap"]
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
  password_wo_version = try(local.access.tailscale.operator.secret_revision, 1)
  tags                = ["Homelab", "Tailscale", "Kubernetes"]
  title               = "tailscale-operator"
  username            = tailscale_oauth_client.kubernetes_operator[each.key].id
  vault               = data.onepassword_vault.default["cluster/${each.key}"].uuid

  lifecycle {
    prevent_destroy = true
  }
}
