data "external" "onepassword_services" {
  program = [
    "${path.module}/scripts/onepassword-vault-read.sh",
    var.onepassword_services_vault
  ]
}

locals {
  _services = {
    for k, v in data.external.onepassword_services.result : k => merge(
      jsondecode(v),
      {
        name     = join("-", slice(split("-", k), 1, length(split("-", k))))
        platform = split("-", k)[0]
        input = merge(
          var.service_defaults,
          jsondecode(v).input
        )
      }
    )
  }

  services = {
    for k, v in local._services : k => merge(
      v,
      {
        output = length(local.services_deployments[k]) > 0 ? {
          for target in local.services_deployments[k] : target => {
            database_password_sensitive = try(v.input.database_password, null)
            fqdn_external               = "${v.name}.${local.servers[target].output.fqdn_external}"
            fqdn_internal               = "${v.name}.${local.servers[target].output.fqdn_internal}"
            secret_hash_sensitive       = try(v.input.secret_hash, null)
          }
        } : {}
      }
    )
  }

  services_deployments = {
    for k, v in local._services : k => (
      v.input.deploy_to == null ? [] :
      # Deploy to all servers
      v.input.deploy_to == "all" ? keys(local._servers) :
      # Direct server reference
      contains(keys(local._servers), v.input.deploy_to) ? [v.input.deploy_to] :
      # Pattern-based matches
      [
        for h_key, h_val in local._servers : h_key
        if(
          startswith(v.input.deploy_to, "platform:") && h_val.platform == trimprefix(v.input.deploy_to, "platform:") ||
          startswith(v.input.deploy_to, "region:") && h_val.region == trimprefix(v.input.deploy_to, "region:")
        )
      ]
    )
  }

  services_resources = {
    for k, v in local._services : k => {
      for resource in var.service_resources : resource => contains(try(split(",", replace(v.input.resources, " ", "")), []), resource)
    }
  }

  services_urls = {
    for k, v in local.services : k => [
      for url in distinct(concat(
        [try(v.urls[0], null)],
        flatten([
          for output in values(v.output) : [
            output.fqdn_external,
            output.fqdn_internal
          ]
        ])
      )) : url
      if url != null
    ]
  }
}

output "services" {
  value     = keys(local._services)
  sensitive = false
}

resource "shell_sensitive_script" "onepassword_service_sync" {
  for_each = local.services

  environment = {
    ID           = each.value.id
    OUTPUTS_JSON = jsonencode(each.value.output)
    URLS_JSON    = jsonencode(local.services_urls[each.key])
    VAULT        = var.onepassword_services_vault
  }

  lifecycle_commands {
    create = "${path.module}/scripts/onepassword-service-write.sh"
    delete = "true"
  }

  triggers = {
    outputs_hash      = sha256(jsonencode(each.value.output))
    script_read_hash  = filemd5("${path.module}/scripts/onepassword-vault-read.sh")
    script_write_hash = filemd5("${path.module}/scripts/onepassword-service-write.sh")
    urls_hash         = sha256(jsonencode(local.services_urls[each.key]))
  }
}
