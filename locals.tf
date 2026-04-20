locals {
  # Raw defaults are the schema-shaped baseline for every loaded YAML object.
  _defaults = yamldecode(file("${path.module}/data/defaults.yml"))

  # DNS zone files stay keyed by filepath until each file's zone name is read.
  _dns = {
    for filepath in fileset(path.module, "data/dns/*.yml") :
    filepath => yamldecode(file("${path.module}/${filepath}"))
  }

  # Public defaults exclude per-domain schema defaults, which get their own locals.
  defaults = {
    for k, v in local._defaults : k => v
    if !contains(["dns", "servers", "services"], k)
  }

  # Default DNS record attributes merged into manual and generated records.
  defaults_dns = local._defaults.dns

  # Schema-shaped defaults merged into each server YAML file.
  defaults_server = local._defaults.servers

  # Schema-shaped defaults merged into each service YAML file.
  defaults_service = local._defaults.services

  # Final DNS input map: zone name -> list of manually declared records.
  dns = {
    for filepath, data in local._dns :
    data.name => try(data.records, [])
  }

  # Shared shell script used by shell_sensitive_script resources before GitHub writes.
  script_sops_encrypt = file("${path.module}/templates/scripts/sops_encrypt.sh")
}

output "summary" {
  description = "Summary of infrastructure managed by OpenTofu"
  sensitive   = false

  value = {
    counts = {
      dns_records = length(local.dns_records_acme_delegation) + length(local.dns_records_manual) + length(local.dns_records_servers) + length(local.dns_records_services) + length(local.dns_records_services_fly) + length(local.dns_records_services_urls) + length(local.dns_records_wildcards)
      servers     = length(local.servers_model_desired)
      services    = length(local.services_model_desired)
    }

    defaults = local.defaults
    servers  = keys(local.servers_model_desired)
    services = keys(local.services_model_desired)

    services_by_feature = {
      for feature, matches in local.services_output_by_feature : feature => keys(matches)
      if length(matches) > 0
    }
  }
}
