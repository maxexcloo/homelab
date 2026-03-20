locals {
  _services = {
    for k, v in {
      for filepath in fileset(path.module, "data/services/*.yml") :
      trimsuffix(basename(filepath), ".yml") => yamldecode(file("${path.module}/${filepath}"))
    } : k => provider::deepmerge::mergo(local.service_defaults, v)
  }

  _services_deployments = merge([
    for service_key, service in local._services : {
      for target in service.deploy_to : "${service_key}-${target}" => merge(
        service,
        {
          server = target
          fqdn   = "${service.identity.name}.${local.servers[target].fqdn}"
        }
      )
    }
  ]...)

  services = {
    for k, v in local._services_deployments : k => merge(
      v,
      {
        fqdn_external      = "${v.identity.name}.${local.servers[v.server].fqdn_external}"
        fqdn_internal      = "${v.identity.name}.${local.servers[v.server].fqdn_internal}"
        password_sensitive = v.features.password ? random_password.service[k].result : null
      },
      {
        for secret in v.features.secrets : "${secret}_sensitive" => (
          secret == "secret_hash" ?
          random_id.service_secret["${k}-${secret}"].b64_std :
          random_password.service_secret["${k}-${secret}"].result
        )
      },
      {
        for i, url in v.networking.urls : "url_${i}" => url
      },
      v.features.b2 ? {
        b2_application_key_id        = b2_application_key.service[k].application_key_id
        b2_application_key_sensitive = b2_application_key.service[k].application_key
        b2_bucket_name               = b2_bucket.service[k].bucket_name
        b2_endpoint                  = replace(data.b2_account_info.default.s3_api_url, "https://", "")
      } : {},
      v.features.resend ? {
        resend_api_key_sensitive = jsondecode(restapi_object.resend_api_key_service[k].create_response).token
      } : {},
      v.features.tailscale ? {
        tailscale_auth_key_sensitive = tailscale_tailnet_key.service[k].key
      } : {}
    )
  }

  services_by_feature = {
    for feature in keys(local.service_defaults.features) : feature => {
      for k, v in local._services_deployments : k => v
      if v.features[feature]
    }
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
    for s in flatten([
      for k, v in local._services_deployments : [
        for secret in v.features.secrets : "${k}-${secret}"
        if secret == "secret_hash"
      ]
    ]) : s => s
  }

  byte_length = 32
}

resource "random_password" "service" {
  for_each = local.services_by_feature.password

  length = 32
}

resource "random_password" "service_secret" {
  for_each = {
    for s in flatten([
      for k, v in local._services_deployments : [
        for secret in v.features.secrets : "${k}-${secret}"
        if secret != "secret_hash"
      ]
    ]) : s => s
  }

  length = 32
}

resource "terraform_data" "services_validation" {
  input = join(", ", flatten([
    for k, v in local._services : [
      for target in v.deploy_to : "${k} -> ${target}"
      if !contains(keys(local.servers), target)
    ]
  ]))

  lifecycle {
    precondition {
      condition     = length(flatten([for k, v in local._services : [for target in v.deploy_to : target if !contains(keys(local.servers), target)]])) == 0
      error_message = "Invalid server references found in services configuration"
    }
  }
}

output "services" {
  description = "Service configurations"
  sensitive   = true
  value       = local.services_filtered
}
