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
  for_each = random_string.b2_homelab

  bucket_name = "${each.key}-${each.value.result}"
  bucket_type = "allPrivate"

  default_server_side_encryption {
    algorithm = "AES256"
    mode      = "SSE-B2"
  }

  lifecycle_rules {
    days_from_hiding_to_deleting  = 1
    days_from_uploading_to_hiding = 0
    file_name_prefix              = ""
  }
}

resource "random_string" "b2_homelab" {
  for_each = local.homelab_discovered

  length  = 6
  special = false
  upper   = false
}
