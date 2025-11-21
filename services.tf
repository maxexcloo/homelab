data "external" "onepassword_services" {
  program = [
    "${path.module}/scripts/onepassword-vault-read.sh",
    var.onepassword_services_vault
  ]

  query = {
    connect_host  = var.onepassword_connect_host
    connect_token = var.onepassword_connect_token
  }
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
        url = try(v.urls[0], null)
        output = length(local.services_deployments[k]) > 0 ? {
          for target in local.services_deployments[k] : target => {
            fqdn_external = "${v.name}.${local.servers[target].output.fqdn_external}"
            fqdn_internal = "${v.name}.${local.servers[target].output.fqdn_internal}"
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

  services_outputs_filtered = {
    for k, v in local.services : k => {
      for target, output in v.output : target => {
        for output_key, output_value in output : output_key => output_value
        if !can(regex(var.url_field_pattern, output_key))
      }
    }
  }

  services_resources = {
    for k, v in local._services : k => {
      for resource in var.service_resources : resource => contains(try(split(",", replace(v.input.resources, " ", "")), []), resource)
    }
  }

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
        for target, output in v.output : [
          for field in sort(keys(output)) : {
            href    = output[field]
            label   = "${field}_${target}"
            primary = field == "fqdn_internal" && v.url == null && target == keys(v.output)[0]
          }
          if can(regex(var.url_field_pattern, field)) && output[field] != null
        ]
      ])
    )
  }
}

output "services" {
  value     = keys(local._services)
  sensitive = false
}

resource "shell_sensitive_script" "onepassword_service_sync" {
  for_each = local.services

  environment = {
    CONNECT_HOST  = var.onepassword_connect_host
    CONNECT_TOKEN = var.onepassword_connect_token
    ID            = each.value.id
    OUTPUTS_JSON  = jsonencode(local.services_outputs_filtered[each.key])
    URLS_JSON     = jsonencode(local.services_urls[each.key])
    VAULT         = var.onepassword_services_vault
  }

  lifecycle_commands {
    create = "${path.module}/scripts/onepassword-service-write.sh"
    delete = "true"
    update = "${path.module}/scripts/onepassword-service-write.sh"
  }

  triggers = {
    outputs_hash      = sha256(jsonencode(local.services_outputs_filtered[each.key]))
    script_read_hash  = filemd5("${path.module}/scripts/onepassword-vault-read.sh")
    script_write_hash = filemd5("${path.module}/scripts/onepassword-service-write.sh")
    urls_hash         = sha256(jsonencode(local.services_urls[each.key]))
  }
}
