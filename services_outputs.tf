# Stage: runtime — merges provider-backed credential values into services_model. Never used as for_each key.
locals {
  # Flat "service_key-field_name" → bootstrap_value table. Same pattern as
  # _servers_outputs_credentials_bootstrap — see that local for rationale.
  _services_outputs_credentials_bootstrap = {
    for entry in flatten([
      for service_key, service in local.services_model : [
        for field_name, field in service.credentials.fields : {
          key = "${service_key}-${field_name}"
          value = (
            field.bootstrap_type == "hex" ? random_id.service_secret["${service_key}-${field_name}"].hex
            : field.bootstrap_type == "base64" ? random_id.service_secret["${service_key}-${field_name}"].b64_std
            : (
              field.bootstrap_type != null &&
              contains(["alphanumeric", "string"], field.bootstrap_type)
            ) ? random_password.service_secret["${service_key}-${field_name}"].result
            : null
          )
        }
      ]
    ]) : entry.key => entry.value
  }

  # Full runtime service object. Never used as a for_each key — use services_model instead.
  services = {
    for service_key, service in local.services_model : service_key => merge(
      service,
      {
        runtime = {
          attributes = merge(
            service.features.b2 ? {
              b2_application_key_id = b2_application_key.service[service_key].application_key_id
              b2_bucket_name        = b2_bucket.service[service_key].bucket_name
              b2_endpoint           = local.b2_endpoint
            } : {},
          )

          credentials = merge(
            {
              for field_name, field in service.credentials.fields : field_name => sensitive(try(coalesce(
                try(local.onepassword_service_existing_fields[service_key][field_name], null),
                local._services_outputs_credentials_bootstrap["${service_key}-${field_name}"],
              ), ""))
              if(
                field.bootstrap_type != null ||
                field.mode == "rw"
              )
            },
            (
              service.credentials.source == "target" &&
              try(local.servers[service.target], null) != null
              ) ? {
              password = local.servers[service.target].runtime.credentials.password
            } : {},
            service.features.b2 ? {
              b2_application_key = b2_application_key.service[service_key].application_key
            } : {},
            (
              service.credentials.source == "service" &&
              service.features.password
              ) ? {
              password      = sensitive(coalesce(try(local.onepassword_service_existing_fields[service_key].password, null), random_password.service[service_key].result))
              password_hash = bcrypt_hash.service[service_key].id
            } : {},
            service.features.pushover ? {
              pushover_application_token = sensitive(try(local.onepassword_service_existing_fields[service_key].pushover_application_token, ""))
              pushover_user_key          = sensitive(var.pushover_user_key)
            } : {},
            service.features.resend ? {
              resend_api_key = jsondecode(restapi_object.resend_api_key_service[service_key].create_response).token
            } : {},
            service.features.tailscale ? {
              tailscale_auth_key = tailscale_tailnet_key.service[service_key].key
            } : {},
          )
        }
      },
    )
  }

  # Services indexed by feature flag. Model-only — safe for for_each in feature-specific resource files.
  services_by_feature = {
    for feature in keys(local.defaults.services.features) : feature => {
      for service_key, service in local.services_model : service_key => service
      if service.features[feature]
    }
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
      if(
        field_value != null &&
        field_value != "" &&
        field_value != false
      )
    }
  }
}
