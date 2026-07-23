resource "random_string" "suffix" {
  for_each = var.items

  length  = 6
  special = false
  upper   = false
}

resource "b2_bucket" "item" {
  for_each = var.items

  bucket_name = "${each.key}-${random_string.suffix[each.key].result}"
  bucket_type = "allPrivate"

  lifecycle {
    prevent_destroy = true
  }

  default_server_side_encryption {
    algorithm = "AES256"
    mode      = "SSE-B2"
  }

  lifecycle_rules {
    days_from_hiding_to_deleting = 1
    file_name_prefix             = ""
  }
}

resource "b2_application_key" "item" {
  for_each = var.items

  # bucket_ids is provider-preferred but cannot create an equivalent scoped key.
  bucket_id    = b2_bucket.item[each.key].id
  capabilities = var.capabilities
  key_name     = each.key
}
