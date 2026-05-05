locals {
  services_state = {
    for service_key, service in local.services_input_targets : service_key => {
      fields = merge(
        service.features.b2 ? {
          b2_application_key_id = b2_application_key.service[service_key].application_key_id
          b2_bucket_name        = b2_bucket.service[service_key].bucket_name
          b2_endpoint           = local.b2_endpoint
        } : {},
      )

      secrets = merge(
        {
          for secret in service.features.secrets : secret.name => sensitive(try(coalesce(
            try(local.onepassword_service_existing_fields[service_key][secret.name], null),
            local._services_model_secret_bootstrap["${service_key}-${secret.name}"],
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
          fqdn_external = local.services_model[service_key].fqdn_external
          fqdn_internal = local.services_model[service_key].fqdn_internal
        },
        {
          for url in service.networking.urls : url => url
        }
      )
    }
  }
}
