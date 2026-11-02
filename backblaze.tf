locals {
  b2_clusters = toset([for name, cluster in local.clusters : name if try(cluster.backblaze, false)])
  b2_endpoint = local.provider_settings.providers.backblaze.endpoint

  b2_hosts = {
    for name, machine in local.machines : name => {
      bucket_name = machine.backblaze.bucket_name
    }
    if can(machine.backblaze)
  }
}

resource "b2_application_key" "cluster" {
  for_each = local.b2_clusters

  key_name = "cluster-${each.key}"

  capabilities = [
    "listBuckets",
    "listKeys",
    "readBucketEncryption",
    "writeBucketEncryption",
    "writeBuckets",
    "writeKeys",
  ]
}

resource "b2_application_key" "host" {
  for_each = local.b2_hosts

  # HAOS and TrueNAS require the legacy single-bucket application key format.
  bucket_id = b2_bucket.host[each.key].id
  key_name  = "host-${each.key}"

  capabilities = [
    "deleteFiles",
    "listBuckets",
    "listFiles",
    "readBuckets",
    "readFiles",
    "shareFiles",
    "writeFiles",
  ]
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
