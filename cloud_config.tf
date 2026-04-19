locals {
  # Cloud-init is rendered from the fully enriched server model because startup
  # scripts need generated credentials such as Tailscale and tunnel tokens.
  cloud_config = {
    for k, server in local.servers_template_context : k => templatefile(
      "${path.module}/templates/cloud_config/cloud_config.yaml.tftpl",
      {
        defaults = local.defaults
        server   = server
      }
    )
  }
}

output "cloud_config" {
  description = "Generated cloud-init configurations for servers"
  sensitive   = true
  value       = local.cloud_config
}
