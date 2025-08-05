data "b2_account_info" "default" {}

resource "b2_application_key" "homelab" {
  for_each = b2_bucket.homelab

  bucket_id = each.value.id
  key_name  = each.key

  capabilities = [
    "deleteFiles",
    "listFiles",
    "readFiles",
    "writeFiles"
  ]
}

resource "b2_bucket" "homelab" {
  for_each = local.onepassword_vault_homelab_all

  bucket_name = "${each.key}-${random_string.b2_homelab[each.key].result}"
  bucket_type = "allPrivate"
}

resource "random_string" "b2_homelab" {
  for_each = local.onepassword_vault_homelab_all

  length  = 6
  special = false
  upper   = false
}
