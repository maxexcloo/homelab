locals {
  cloud_config = {
    for k, server in local.servers : k => templatefile(
      "templates/cloud_config/cloud_config.yaml",
      {
        defaults = var.defaults
        server   = server
      }
    )
  }
}

output "cloud_config" {
  sensitive = true
  value     = local.cloud_config
}
