# Stage: runtime — merges provider-backed credential values into services_model. Never used as for_each key.
locals {
  # Flat "service_key-credential_name" → generated scalar value table. Same
  # pattern as _servers_outputs_credentials_generated.
  _services_outputs_credentials_generated = {
    for credential_key, generator in local.random_service_credentials : credential_key => (
      generator.type == "hex" ? random_id.service_secret[credential_key].hex
      : generator.type == "base64" ? random_id.service_secret[credential_key].b64_std
      : contains(["alphanumeric", "string"], generator.type) ? random_password.service_secret[credential_key].result
      : null
    )
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
                try(local._services_outputs_credentials_generated["${service_key}-${field_name}"], null),
              ), ""))
              if field.mode == "rw"
            },
            (
              service.credentials.source == "target" &&
              can(local.servers[service.target])
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
              password      = sensitive(coalesce(try(local.onepassword_service_existing_fields[service_key].password, null), random_password.service_secret["${service_key}-password"].result))
              password_hash = bcrypt_hash.service[service_key].id
            } : {},
            service.features.resend ? {
              resend_api_key = jsondecode(restapi_object.resend_api_key_service[service_key].create_response).token
            } : {},
            service.features.tailscale ? {
              tailscale_auth_key = tailscale_tailnet_key.service[service_key].key
            } : {},
            merge({}, [
              for credential_name, generator in service.credentials.generated : generator.type == "x509" ? {
                "${credential_name}_certificate" = tls_self_signed_cert.service["${service_key}-${credential_name}"].cert_pem
                "${credential_name}_private_key" = tls_private_key.service["${service_key}-${credential_name}"].private_key_pem
              } : {}
            ]...),
          )
        }
      },
    )
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
