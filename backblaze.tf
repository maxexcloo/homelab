locals {
  b2_endpoint = local.provider_settings.providers.backblaze.endpoint

  b2_application_key_capabilities = [
    "deleteFiles",
    "listBuckets",
    "listFiles",
    "readBuckets",
    "readFiles",
    "shareFiles",
    "writeFiles",
  ]

  b2_applications = merge([
    for cluster_name, cluster in local.clusters : {
      for name, application in try(cluster.backblaze, {}) : "${cluster_name}/${name}" => {
        bucket_name = trimspace(application.bucket_name)
        cluster     = cluster_name
        name        = application.name
      }
    }
  ]...)

  b2_hosts = {
    for name, machine in local.machines : name => {
      bucket_name = trimspace(machine.backblaze.bucket_name)
    }
    if can(machine.backblaze)
  }
}

resource "b2_application_key" "application" {
  for_each = local.b2_applications

  bucket_ids   = [b2_bucket.application[each.key].id]
  capabilities = local.b2_application_key_capabilities
  key_name     = replace(each.key, "/", "-")
}

resource "b2_application_key" "host" {
  for_each = local.b2_hosts

  # HAOS and TrueNAS require the legacy single-bucket application key format.
  bucket_id    = b2_bucket.host[each.key].id
  capabilities = local.b2_application_key_capabilities
  key_name     = "host-${each.key}"
}

resource "b2_bucket" "application" {
  for_each = local.b2_applications

  bucket_name = each.value.bucket_name
  bucket_type = "allPrivate"

  default_server_side_encryption {
    algorithm = "AES256"
    mode      = "SSE-B2"
  }

  lifecycle_rules {
    days_from_hiding_to_deleting = 1
    file_name_prefix             = ""
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "b2_bucket" "host" {
  for_each = local.b2_hosts

  bucket_name = each.value.bucket_name
  bucket_type = "allPrivate"

  default_server_side_encryption {
    algorithm = "AES256"
    mode      = "SSE-B2"
  }

  lifecycle_rules {
    days_from_hiding_to_deleting = 1
    file_name_prefix             = ""
  }

  lifecycle {
    prevent_destroy = true
  }
}
