locals {
  b2_clusters = toset(keys(local.clusters))

  b2_endpoint = try(local.storage.backblaze.endpoint, null)

  b2_application_key_capabilities_cluster = [
    "listBuckets",
    "listKeys",
    "readBucketEncryption",
    "writeBucketEncryption",
    "writeBuckets",
    "writeKeys",
  ]

  b2_application_key_capabilities_host = [
    "deleteFiles",
    "listBuckets",
    "listFiles",
    "readBuckets",
    "readFiles",
    "shareFiles",
    "writeFiles",
  ]

  b2_hosts = {
    for name, host in try(local.storage.backblaze.hosts, {}) : name => {
      bucket_name = try(trimspace(host.bucket_name), null)
    }
  }
}

resource "b2_application_key" "cluster" {
  for_each = local.b2_clusters

  capabilities = local.b2_application_key_capabilities_cluster
  key_name     = "cluster-${each.key}"

  depends_on = [terraform_data.b2_validation]
}

resource "b2_application_key" "host" {
  for_each = local.b2_hosts

  # HAOS and TrueNAS require the legacy single-bucket application key format.
  bucket_id    = b2_bucket.host[each.key].id
  capabilities = local.b2_application_key_capabilities_host
  key_name     = "host-${each.key}"

  depends_on = [terraform_data.b2_validation]
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

  depends_on = [terraform_data.b2_validation]

  lifecycle {
    prevent_destroy = true
  }
}

resource "terraform_data" "b2_validation" {
  input = {
    clusters = sort(tolist(local.b2_clusters))
    endpoint = local.b2_endpoint
    hosts    = local.b2_hosts
  }

  lifecycle {
    precondition {
      condition     = can(regex("^https://s3\\.[a-z0-9-]+\\.backblazeb2\\.com$", local.b2_endpoint))
      error_message = "The Backblaze B2 endpoint must be an HTTPS regional S3 API URL."
    }

    precondition {
      condition = alltrue([
        for name in keys(local.b2_hosts) : can(local.machines[name])
      ])
      error_message = "Every Backblaze B2 host must name an existing machine."
    }

    precondition {
      condition = alltrue([
        for name in keys(local.b2_hosts) : can(regex("^[a-z0-9-]+$", name))
      ])
      error_message = "Every Backblaze B2 application key name must contain only lowercase letters, numbers, and hyphens."
    }

    precondition {
      condition = alltrue([
        for host in values(local.b2_hosts) : can(regex("^[a-z0-9][a-z0-9-]{4,48}[a-z0-9]$", host.bucket_name))
      ])
      error_message = "Every Backblaze B2 bucket name must be a valid 6-50 character lowercase name."
    }

    precondition {
      condition     = length(distinct([for host in values(local.b2_hosts) : host.bucket_name])) == length(local.b2_hosts)
      error_message = "Backblaze B2 bucket names must be unique."
    }
  }
}
