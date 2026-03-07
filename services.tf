locals {
  _services_raw = {
    for filepath in fileset(path.module, "data/services/*.yml") :
    yamldecode(file("${path.module}/${filepath}")).name => yamldecode(file("${path.module}/${filepath}"))
  }

  _services = {
    for k, v in local._services_raw : k => merge(
      var.service_defaults,
      v,
      { id = k }
    )
  }

  services = {
    for k, v in local._services : k => merge(
      v,
      {
        deployments = try(v.deploy_to, [])
        url         = try(v.url, null)
      },
      length(try(v.deploy_to, [])) > 0 ? {
        for target in v.deploy_to : target => {
          fqdn_external = "${v.name}.${local.servers[target].fqdn_external}"
          fqdn_internal = "${v.name}.${local.servers[target].fqdn_internal}"
        }
      } : {}
    )
  }

  services_deployments = {
    for k, v in local._services : k => try(v.deploy_to, [])
  }

  services_instances = merge([
    for service_key, service in local.services : {
      for target in service.deployments : "${service.name}-${local.servers[target].slug}" => {
        server  = target
        service = service_key
      }
    }
  ]...)

  services_urls = {
    for k, v in local.services : k => concat(
      v.url != null ? [
        {
          href    = v.url
          label   = "url"
          primary = true
        }
      ] : [],
      flatten([
        for target, output in v : [
          for field in sort(keys(output)) : {
            href    = output[field]
            label   = "${field}_${target}"
            primary = field == "fqdn_internal" && v.url == null && target == keys(v)[0]
          }
          if can(regex(var.url_field_pattern, field)) && output[field] != null
        ]
        if can(keys(output)) # Safely ensures we only parse objects, not our new boolean toggles
      ])
    )
  }
}

# Automatically generate optional secrets when toggled in the UI
resource "random_password" "service_db" {
  for_each = { for k, v in local._services : k => v if v.enable_database_password }
  length   = 32
  special  = true
}

resource "random_password" "service_api" {
  for_each = { for k, v in local._services : k => v if v.enable_api_key }
  length   = 32
  special  = true
}

resource "random_id" "service_secret" {
  for_each    = { for k, v in local._services : k => v if v.enable_secret_hash }
  byte_length = 32
}

output "services" {
  value     = keys(local._services)
  sensitive = false
}
