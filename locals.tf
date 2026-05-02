locals {
  # Raw defaults are the schema-shaped baseline for every loaded YAML object.
  defaults = yamldecode(file("${path.module}/data/defaults.yml"))

  # Default DNS record attributes merged into manual and generated records.
  defaults_dns = local.defaults.dns

  # Schema-shaped defaults merged into each server YAML file.
  defaults_server = local.defaults.servers

  # Schema-shaped defaults merged into each service YAML file.
  defaults_service = local.defaults.services

  # Shared SOPS encryption script used by shell_sensitive_script resources
  # before GitHub writes.
  script_encrypt_sops = file("${path.module}/templates/scripts/sops_encrypt.sh")
}

output "summary" {
  description = "Summary of infrastructure managed by OpenTofu"
  sensitive   = false

  value = {
    counts = {
      dns_records = (
        length(local.dns_records_acme_delegation) +
        length(local.dns_records_manual) +
        length(local.dns_records_servers) +
        length(local.dns_records_services) +
        length(local.dns_records_services_fly) +
        length(local.dns_records_services_urls) +
        length(local.dns_records_wildcards)
      )
      servers  = length(local.servers_model_desired)
      services = length(local.services_model_desired)
    }

    servers  = keys(local.servers_model_desired)
    services = keys(local.services_model_desired)

    services_by_feature = {
      for feature, matches in local.services_outputs_by_feature : feature => keys(matches)
      if length(matches) > 0
    }
  }
}
