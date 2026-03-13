locals {
  _services = {
    for k, v in {
      for filepath in fileset(path.module, "data/services/*.yml") :
      trimsuffix(basename(filepath), ".yml") => yamldecode(file("${path.module}/${filepath}"))
    } : k => merge(var.service_defaults, v)
  }

  _services_deployments = merge([
    for service_key, service in local._services : {
      for target in service.deploy_to : "${service_key}-${target}" => merge(
        service,
        {
          server = target
          fqdn   = "${service.name}.${local.servers[target].fqdn}"
        }
      )
    }
  ]...)

  services = {
    for k, v in local._services_deployments : k => merge(
      v,
      {
        fqdn_external = "${v.name}.${local.servers[v.server].fqdn_external}"
        fqdn_internal = "${v.name}.${local.servers[v.server].fqdn_internal}"
      },
      {
        for secret in v.secrets : "${secret}_sensitive" => (
          secret == "secret_hash" ?
          random_id.service_secret["${k}-${secret}"].b64_std :
          random_password.service_secret["${k}-${secret}"].result
        )
      },
      {
        for i, url in(v.urls != null ? v.urls : []) : "url_${i}" => url
      },
      v.enable_b2 ? {
        b2_application_key_id        = b2_application_key.service[k].application_key_id
        b2_application_key_sensitive = b2_application_key.service[k].application_key
        b2_bucket_name               = b2_bucket.service[k].bucket_name
        b2_endpoint                  = replace(data.b2_account_info.default.s3_api_url, "https://", "")
      } : {},
      v.enable_resend ? {
        resend_api_key_sensitive = jsondecode(restapi_object.resend_api_key_service[k].create_response).token
      } : {},
      v.enable_tailscale ? {
        tailscale_auth_key_sensitive = tailscale_tailnet_key.service[k].key
      } : {}
    )
  }
}

resource "random_id" "service_secret" {
  for_each = {
    for s in flatten([
      for k, v in local._services_deployments : [
        for secret in v.secrets : "${k}-${secret}"
        if secret == "secret_hash"
      ]
    ]) : s => s
  }

  byte_length = 32
}

resource "random_password" "service" {
  for_each = {
    for k, v in local._services_deployments : k => v
    if v.enable_password
  }

  length = 32
}

resource "random_password" "service_secret" {
  for_each = {
    for s in flatten([
      for k, v in local._services_deployments : [
        for secret in v.secrets : "${k}-${secret}"
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
  value     = keys(local.services)
  sensitive = false
}
