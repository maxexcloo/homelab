locals {
  _services = {
    for k, v in {
      for filepath in fileset(path.module, "data/services/*.yml") :
      trimsuffix(basename(filepath), ".yml") => yamldecode(file("${path.module}/${filepath}"))
    } : k => provider::deepmerge::mergo(local.service_defaults, v)
  }

  _services_computed = merge([
    for service_key, service in local._services : {
      for target in service.deploy_to : "${service_key}-${target}" => merge(
        service,
        {
          target = target
        }
      )
    }
  ]...)

  services = {
    for k, v in local._services_computed : k => merge(
      v,
      {
        for secret in v.features.secrets : "${secret.name}_sensitive" => (
          contains(["hex", "base64"], secret.type) ? (
            secret.type == "hex" ?
            random_id.service_secret["${k}-${secret.name}"].hex :
            random_id.service_secret["${k}-${secret.name}"].b64_std
          ) :
          random_password.service_secret["${k}-${secret.name}"].result
        )
      },
      v.features.b2 ? {
        b2_application_key_id        = b2_application_key.service[k].application_key_id
        b2_application_key_sensitive = b2_application_key.service[k].application_key
        b2_bucket_name               = b2_bucket.service[k].bucket_name
        b2_endpoint                  = replace(data.b2_account_info.default.s3_api_url, "https://", "")
      } : {},
      v.features.password ? {
        password_hash_sensitive = bcrypt_hash.service[k].id
        password_sensitive      = random_password.service[k].result
      } : {},
      v.features.resend ? {
        resend_api_key_sensitive = jsondecode(restapi_object.resend_api_key_service[k].create_response).token
      } : {},
      v.features.tailscale ? {
        tailscale_auth_key_sensitive = tailscale_tailnet_key.service[k].key
      } : {},
      v.networking.scheme != null ? merge(
        {
          for i, url in v.networking.urls : "url_${i}" => url
        },
        contains(keys(local.servers), v.target) ? {
          fqdn_external = "${v.identity.name}.${local.servers[v.target].fqdn_external}"
          fqdn_internal = "${v.identity.name}.${local.servers[v.target].fqdn_internal}"
        } : {}
      ) : {}
    )
  }

  services_by_feature = {
    for feature, default_value in local.service_defaults.features : feature => {
      for k, v in local._services_computed : k => v
      if v.features[feature]
    }
    if can(tobool(default_value))
  }

  services_filtered = {
    for k, v in local.services : k => {
      for kk, vv in v : kk => vv
      if vv != null && vv != "" && vv != false
    }
  }
}

resource "random_id" "service_secret" {
  for_each = {
    for item in flatten([
      for k, v in local._services_computed : [
        for secret in v.features.secrets : {
          key         = "${k}-${secret.name}"
          byte_length = secret.length
        }
        if contains(["hex", "base64"], secret.type)
      ]
    ]) : item.key => item
  }

  byte_length = each.value.byte_length
}

resource "random_password" "service" {
  for_each = local.services_by_feature.password

  length = 32
}

resource "random_password" "service_secret" {
  for_each = {
    for item in flatten([
      for k, v in local._services_computed : [
        for secret in v.features.secrets : {
          key     = "${k}-${secret.name}"
          length  = secret.length
          special = secret.type == "string"
        }
        if contains(["string", "alphanumeric"], secret.type)
      ]
    ]) : item.key => item
  }

  length  = each.value.length
  special = each.value.special
}

resource "terraform_data" "services_validation" {
  input = join(", ", flatten([
    for k, v in local._services : [
      for target in v.deploy_to : "${k} -> ${target}"
      if !contains(keys(local.servers), target) && target != "fly"
    ]
  ]))

  lifecycle {
    precondition {
      condition     = length(flatten([for k, v in local._services : [for target in v.deploy_to : target if !contains(keys(local.servers), target) && target != "fly"]])) == 0
      error_message = "Invalid server references found in services configuration"
    }

    precondition {
      condition     = length([for k, v in local._services : k if contains(v.deploy_to, "fly") && v.networking.port == null]) == 0
      error_message = "Fly services must have networking.port set: ${join(", ", [for k, v in local._services : k if contains(v.deploy_to, "fly") && v.networking.port == null])}"
    }
  }
}

output "services" {
  description = "Service configurations"
  sensitive   = true
  value       = local.services_filtered
}
