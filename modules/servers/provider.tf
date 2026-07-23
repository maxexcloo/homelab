# Incus remotes are derived from the deterministic server model.
provider "incus" {
  accept_remote_certificate    = true
  generate_client_certificates = true

  dynamic "remote" {
    for_each = local.incus_servers

    content {
      address = "https://${remote.value.networking.management_host}:${remote.value.networking.management_port}"
      name    = remote.key
    }
  }
}
