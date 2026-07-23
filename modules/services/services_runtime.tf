# Stage: runtime — merges provider-backed credential values into services_model. Never used as for_each key.
locals {
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
              object_storage_access_key_id = module.object_storage.items[service_key].access_key_id
              object_storage_bucket        = module.object_storage.items[service_key].bucket
              object_storage_endpoint      = module.object_storage.items[service_key].endpoint
            } : {},
            service.features.oidc && local._pocketid_integration_ready ? {
              oidc_issuer_url = var.integrations.pocketid.url
            } : {},
          )

          credentials = merge(
            {
              for field_name, field in service.credentials.fields : field_name => sensitive(try(coalesce(
                try(local.onepassword_service_existing_fields[service_key][field_name], null),
                try(module.credentials.values["${service_key}-${field_name}"], null),
              ), ""))
              if field.mode == "rw"
            },
            (
              service.credentials.source == "target" &&
              can(var.servers.runtime[service.target])
              ) ? {
              password = var.servers.runtime[service.target].runtime.credentials.password
            } : {},
            service.features.mail ? {
              mail_password = jsondecode(restapi_object.resend_api_key_service[service_key].create_response).token
            } : {},
            service.features.object_storage ? {
              object_storage_secret_access_key = module.object_storage.items[service_key].secret_access_key
            } : {},
            service.features.oidc && local._pocketid_integration_ready ? merge(
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
              password      = module.credentials.passwords[service_key].value
              password_hash = module.credentials.passwords[service_key].hash
            } : {},
            service.features.tailscale ? {
              tailscale_auth_key = var.integrations.tailscale_auth_keys[service_key]
            } : {},
            merge({}, [
              for credential_name, generator in service.credentials.generated : {
                "${credential_name}_certificate" = module.credentials.x509["${service_key}-${credential_name}"].certificate
                "${credential_name}_private_key" = module.credentials.x509["${service_key}-${credential_name}"].private_key
              }
              if generator.type == "x509"
            ]...),
          )
        }
      },
    )
  }
}
