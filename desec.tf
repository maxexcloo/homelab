resource "desec_domain" "acme" {
  name = var.domain_acme
}

resource "desec_token" "homelab" {
  for_each = {
    for k, v in local.homelab_discovered : k => v
    if contains(local.homelab_flags[k].resources, "desec")
  }

  name = each.key

  lifecycle {
    ignore_changes = all
  }
}
