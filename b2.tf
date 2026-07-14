data "b2_account_info" "default" {}

locals {
  # Bucket-scoped keys get broad object permissions because services own their
  # buckets and need to manage backup/object lifecycles themselves.
  _b2_application_key_capabilities = [
    "deleteFiles",
    "listBuckets",
    "listFiles",
    "readBuckets",
    "readFiles",
    "shareFiles",
    "writeFiles"
  ]

  # B2 S3 endpoint with the https:// prefix stripped for service templates.
  b2_endpoint = replace(data.b2_account_info.default.s3_api_url, "https://", "")
}

resource "b2_application_key" "server" {
  for_each = local.servers_model_by_feature.b2

  bucket_id    = b2_bucket.server[each.key].id
  capabilities = local._b2_application_key_capabilities
  key_name     = each.key
}

resource "b2_application_key" "service" {
  for_each = local.services_model_by_feature.b2

  bucket_id    = b2_bucket.service[each.key].id
  capabilities = local._b2_application_key_capabilities
  key_name     = each.key
}

resource "b2_bucket" "server" {
  for_each = local.servers_model_by_feature.b2

  # B2 bucket names are global, so a stable random suffix is part of identity.
  bucket_name = "${each.key}-${random_string.b2_server[each.key].result}"
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

resource "b2_bucket" "service" {
  for_each = local.services_model_by_feature.b2

  # Service buckets use the expanded service-target key plus a stable suffix.
  bucket_name = "${each.key}-${random_string.b2_service[each.key].result}"
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
