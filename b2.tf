data "b2_account_info" "default" {}

resource "b2_application_key" "server" {
  for_each = b2_bucket.server

  bucket_id = each.value.id
  key_name  = each.key

  capabilities = [
    "deleteFiles",
    "listBuckets",
    "listFiles",
    "readBuckets",
    "readFiles",
    "shareFiles",
    "writeFiles"
  ]
}

resource "b2_application_key" "service" {
  for_each = b2_bucket.service

  bucket_id = each.value.id
  key_name  = each.key

  capabilities = [
    "deleteFiles",
    "listBuckets",
    "listFiles",
    "readBuckets",
    "readFiles",
    "shareFiles",
    "writeFiles"
  ]
}

resource "b2_bucket" "server" {
  for_each = random_string.b2_server

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
  for_each = {
    for k, v in local._services_deployments : k => v
    if v.enable_b2
  }

  bucket_name = "${each.key}-${random_string.b2_service[each.key].result}"
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
  for_each = {
    for k, v in local._servers : k => v
    if v.enable_b2
  }

  length  = 6
  special = false
  upper   = false
}

resource "random_string" "b2_service" {
  for_each = {
    for k, v in local._services_deployments : k => v
    if v.enable_b2
  }

  length  = 6
  special = false
  upper   = false
}
