locals {
  _services = {
    for k, v in {
      for filepath in fileset(path.module, "data/services/*.yml") :
      trimsuffix(basename(filepath), ".yml") => yamldecode(file("${path.module}/${filepath}"))
    } : k => merge(var.service_defaults, v)
  }

  # Validate deploy_to references  
  _services_invalid_refs = flatten([
    for k, v in local._services : [
      for target in v.deploy_to : "${k} -> ${target}"
      if !contains(keys(local.servers), target)
    ]
  ])

  # Build flat map of all service secrets
  _service_secrets_flat = flatten([
    for service_key, service in local._services : [
      for secret in service.secrets : {
        key  = "${service_key}-${secret}"
        type = secret
        hash = secret == "secret_hash"
      }
    ]
  ])

  _service_secrets = {
    for k, v in local._services : k => {
      for secret in v.secrets : "${secret}_sensitive" => (
        secret == "secret_hash" ?
        random_id.service_secret["${k}-${secret}"].b64_std :
        random_password.service_secret["${k}-${secret}"].result
      )
    }
  }

  services = length(local._services_invalid_refs) > 0 ? tomap({
    ERROR = "Invalid server references: ${join(", ", local._services_invalid_refs)}"
    }) : merge([
    for service_key, service in local._services : {
      for target in service.deploy_to : "${service_key}-${target}" => merge(
        service,
        {
          server        = target
          fqdn_external = "${service.name}.${local.servers[target].fqdn_external}"
          fqdn_internal = "${service.name}.${local.servers[target].fqdn_internal}"
        },
        local._service_secrets[service_key]
      )
    }
  ]...)
}

# Generate password-based secrets
resource "random_password" "service_secret" {
  for_each = {
    for s in local._service_secrets_flat : s.key => s
    if !s.hash
  }
  length  = 32
  special = true
}

# Generate hash-based secrets  
resource "random_id" "service_secret" {
  for_each = {
    for s in local._service_secrets_flat : s.key => s
    if s.hash
  }
  byte_length = 32
}

output "services" {
  value     = keys(local.services)
  sensitive = false
}
