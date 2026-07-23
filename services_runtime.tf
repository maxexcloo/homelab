# Stage: runtime — merges provider-backed credential values into services_model. Never used as for_each key.
locals {
  # Flat "service_key-credential_name" → generated scalar value table. Same
  # pattern as _servers_runtime_credentials_generated.
  _services_runtime_credentials_generated = {
    for credential_key, generator in local.random_service_credentials : credential_key => (
      generator.type == "hex" ? random_id.service_secret[credential_key].hex
      : generator.type == "base64" ? random_id.service_secret[credential_key].b64_std
      : random_password.service_secret[credential_key].result
    )
  }

  # Full runtime service object. Never used as a for_each key — use services_model instead.
  services = {
    for service_key, service in local.services_model : service_key => merge(
      service,
      {
        runtime = {
          attributes = merge(
            service.features.mail ? {
              mail_host     = local.defaults.resend.host
              mail_port     = local.defaults.resend.port
              mail_username = local.defaults.resend.username
            } : {},
            service.features.object_storage ? {
              object_storage_access_key_id = b2_application_key.service[service_key].application_key_id
              object_storage_bucket        = b2_bucket.service[service_key].bucket_name
              object_storage_endpoint      = local.b2_endpoint
            } : {},
            service.features.oidc ? {
              oidc_issuer_url = var.pocketid_url
            } : {},
          )

          credentials = merge(
            {
              for field_name, field in service.credentials.fields : field_name => sensitive(try(coalesce(
                try(local.onepassword_service_existing_fields[service_key][field_name], null),
                try(local._services_runtime_credentials_generated["${service_key}-${field_name}"], null),
              ), ""))
              if field.mode == "rw"
            },
            (
              service.credentials.source == "target" &&
              can(local.servers[service.target])
              ) ? {
              password = local.servers[service.target].runtime.credentials.password
            } : {},
            service.features.mail ? {
              mail_password = jsondecode(restapi_object.resend_api_key_service[service_key].create_response).token
            } : {},
            service.features.object_storage ? {
              object_storage_secret_access_key = b2_application_key.service[service_key].application_key
            } : {},
            service.features.oidc ? merge(
              {
                oidc_client_id = pocketid_client.service[service_key].id
              },
              try(service.data.oidc_is_public, false) ? {} : {
                oidc_client_secret = pocketid_client.service[service_key].client_secret
              },
            ) : {},
            (
              service.credentials.source == "service" &&
              service.features.password
              ) ? {
              password      = sensitive(coalesce(try(local.onepassword_service_existing_fields[service_key].password, null), random_password.service_secret["${service_key}-password"].result))
              password_hash = htpasswd_password.service[service_key].bcrypt
            } : {},
            service.features.tailscale ? {
              tailscale_auth_key = tailscale_tailnet_key.service[service_key].key
            } : {},
            merge({}, [
              for credential_name, generator in service.credentials.generated : {
                "${credential_name}_certificate" = tls_self_signed_cert.service["${service_key}-${credential_name}"].cert_pem
                "${credential_name}_private_key" = tls_private_key.service["${service_key}-${credential_name}"].private_key_pem
              }
              if generator.type == "x509"
            ]...),
          )
        }
      },
    )
  }
}
