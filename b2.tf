data "b2_account_info" "default" {}

locals {
  # Bucket-scoped keys get broad object permissions because services own their
  # buckets and need to manage backup/object lifecycles themselves.
  b2_application_key_capabilities = [
    "deleteFiles",
    "listBuckets",
    "listFiles",
    "readBuckets",
    "readFiles",
    "shareFiles",
    "writeFiles"
  ]
}

resource "b2_application_key" "server" {
  for_each = b2_bucket.server

  bucket_id = each.value.id
  key_name  = each.key

  capabilities = local.b2_application_key_capabilities
}

resource "b2_application_key" "service" {
  for_each = b2_bucket.service

  bucket_id = each.value.id
  key_name  = each.key

  capabilities = local.b2_application_key_capabilities
}

resource "b2_bucket" "server" {
  for_each = random_string.b2_server

  # B2 bucket names are global, so a stable random suffix is part of identity.
  bucket_name = "${each.key}-${each.value.result}"
  bucket_type = "allPrivate"

  default_server_side_encryption {
    algorithm = "AES256"
    mode      = "SSE-B2"
  }

  lifecycle_rules {
    days_from_hiding_to_deleting = 1
    file_name_prefix             = ""
  }
}

resource "b2_bucket" "service" {
  for_each = random_string.b2_service

  # Service buckets use the expanded service-target key plus a stable suffix.
  bucket_name = "${each.key}-${each.value.result}"
  bucket_type = "allPrivate"

  default_server_side_encryption {
    algorithm = "AES256"
    mode      = "SSE-B2"
  }

  lifecycle_rules {
    days_from_hiding_to_deleting = 1
    file_name_prefix             = ""
  }
}

resource "random_string" "b2_server" {
  for_each = local.servers_by_feature.b2

  length  = 6
  special = false
  upper   = false
}

resource "random_string" "b2_service" {
  for_each = local.services_by_feature.b2

  length  = 6
  special = false
  upper   = false
}
