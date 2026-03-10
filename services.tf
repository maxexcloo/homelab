locals {
  _services = {
    for k, v in {
      for filepath in fileset(path.module, "data/services/*.yml") :
      trimsuffix(basename(filepath), ".yml") => yamldecode(file("${path.module}/${filepath}"))
    } : k => merge(var.service_defaults, v)
  }

  # Validate that all deploy_to references exist as servers
  _services_validation = {
    for k, v in local._services : k => [
      for target in v.deploy_to : target
      if !contains(keys(local.servers), target)
    ]
  }

  _services_validation_errors = compact([
    for k, invalid_refs in local._services_validation :
    length(invalid_refs) > 0 ? "Service '${k}' references non-existent servers: ${join(", ", invalid_refs)}" : ""
  ])

  # Generate secrets for each service (once per service, not per deployment)
  _service_secrets = {
    for k, v in local._services : k => {
      for secret in v.secrets : "${secret}_sensitive" => (
        secret == "secret_hash" ?
        random_id.service_secret["${k}-${secret}"].b64_std :
        random_password.service_secret["${k}-${secret}"].result
      )
    }
  }

  services = length(local._services_validation_errors) > 0 ? tomap({
    ERROR = "Service validation failed: ${join("; ", local._services_validation_errors)}"
    }) : merge([
    for service_key, service in local._services : {
      for target in service.deploy_to : "${service_key}-${target}" => merge(
        service,
        {
          server        = target
          fqdn_external = "${service.name}.${local.servers[target].fqdn_external}"
          fqdn_internal = "${service.name}.${local.servers[target].fqdn_internal}"
          url           = service.url
        },
        local._service_secrets[service_key]
      )
    }
  ]...)

  services_urls = {
    for k, v in local.services : k => v.url != null ? [
      {
        href    = v.url
        label   = "url"
        primary = true
      }
      ] : [
      {
        href    = "https://${v.fqdn_internal}"
        label   = "internal"
        primary = true
      }
    ]
  }
}

# Generate secrets for services
resource "random_password" "service_secret" {
  for_each = {
    for pair in setproduct(
      keys(local._services),
      flatten([for k, v in local._services : [for s in v.secrets : s if s != "secret_hash"]])
    ) : "${pair[0]}-${pair[1]}" => pair
  }
  length  = 32
  special = true
}

resource "random_id" "service_secret" {
  for_each = {
    for pair in setproduct(
      keys(local._services),
      flatten([for k, v in local._services : [for s in v.secrets : s if s == "secret_hash"]])
    ) : "${pair[0]}-${pair[1]}" => pair
  }
  byte_length = 32
}

output "services" {
  value     = keys(local.services)
  sensitive = false
}
