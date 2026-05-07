locals {
  # Generated bootstrap value per declared service secret. Null when the secret
  # has no bootstrap_type, so the state secret falls through to an empty
  # operator-filled 1Password placeholder.
  _services_outputs_secret_bootstrap = {
    for entry in flatten([
      for service_key, service in local.services_input_targets : [
        for secret in service.secrets : {
          key = "${service_key}-${secret.name}"
          value = (
            try(secret.bootstrap_type, null) == "hex" ? random_id.service_secret["${service_key}-${secret.name}"].hex
            : try(secret.bootstrap_type, null) == "base64" ? random_id.service_secret["${service_key}-${secret.name}"].b64_std
            : contains(["alphanumeric", "string"], try(secret.bootstrap_type, "")) ? random_password.service_secret["${service_key}-${secret.name}"].result
            : null
          )
        }
      ]
    ]) : entry.key => entry.value
  }

  services = {
    for service_key, service in local.services_model : service_key => merge(
      service,
      {
        state = {
          fields = merge(
            service.features.b2 ? {
              b2_application_key_id = b2_application_key.service[service_key].application_key_id
              b2_bucket_name        = b2_bucket.service[service_key].bucket_name
              b2_endpoint           = local.b2_endpoint
            } : {},
          )

          secrets = merge(
            {
              for secret in service.secrets : secret.name => sensitive(try(coalesce(
                try(local.onepassword_service_existing_fields[service_key][secret.name], null),
                local._services_outputs_secret_bootstrap["${service_key}-${secret.name}"],
              ), ""))
            },
            service.features.b2 ? {
              b2_application_key = b2_application_key.service[service_key].application_key
            } : {},
            service.features.password ? {
              password      = sensitive(try(local.onepassword_service_existing_fields[service_key].password, random_password.service[service_key].result))
              password_hash = bcrypt_hash.service[service_key].id
            } : {},
            service.features.pushover ? {
              pushover_application_token = var.pushover_application_token
              pushover_user_key          = var.pushover_user_key
            } : {},
            service.features.resend ? {
              resend_api_key = jsondecode(restapi_object.resend_api_key_service[service_key].create_response).token
            } : {},
            service.features.tailscale ? {
              tailscale_auth_key = tailscale_tailnet_key.service[service_key].key
            } : {},
          )

          urls = merge(
            {
              fqdn_external = service.fqdn_external
              fqdn_internal = service.fqdn_internal
            },
            {
              for url in service.routing.urls : url => url
            }
          )
        }
      },
    )
  }

  services_by_feature = {
    for feature, default_value in local.defaults.services.features : feature => {
      for service_key, service in local.services_input_targets : service_key => service
      if service.features[feature]
    }
    if can(tobool(default_value))
  }
}

output "services" {
  description = "Service configurations"
  sensitive   = true

  # Top-level false/null/empty defaults are filtered out to reduce output noise.
  # Nested objects keep their full schema shape.
  value = {
    for service_key, service in local.services : service_key => {
      for field_name, field_value in service : field_name => field_value
      if field_value != null && field_value != "" && field_value != false
    }
  }
}
