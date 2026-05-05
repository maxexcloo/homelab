locals {
  # 1Password STRING fields per service. Feature-gated entries default to null.
  _services_state_fields = {
    for service_key, service in local.services_input_targets : service_key => merge(
      {
        b2_application_key_id = null
        b2_bucket_name        = null
        b2_endpoint           = null
      },
      service.features.b2 ? {
        b2_application_key_id = b2_application_key.service[service_key].application_key_id
        b2_bucket_name        = b2_bucket.service[service_key].bucket_name
        b2_endpoint           = local.b2_endpoint
      } : {},
    )
  }

  # 1Password CONCEALED fields per service. Feature-gated entries plus declared
  # custom secrets default to null/empty; the runtime resolves them below.
  _services_state_secrets = {
    for service_key, service in local.services_input_targets : service_key => merge(
      {
        b2_application_key         = null
        password                   = null
        password_hash              = null
        pushover_application_token = null
        pushover_user_key          = null
        resend_api_key             = null
        tailscale_auth_key         = null
      },
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
  }

  # 1Password URL items per service. Mirrors model FQDNs so 1Password gets the
  # full set of access addresses; null entries are filtered at the consumer.
  _services_state_urls = {
    for service_key, service in local.services_input_targets : service_key => {
      fqdn_external = local.services_model[service_key].fqdn_external
      fqdn_internal = local.services_model[service_key].fqdn_internal
    }
  }

  # Runtime service state. Iterated by 1Password sync via the three sub-objects.
  services_state = {
    for service_key, service in local.services_input_targets : service_key => {
      fields  = local._services_state_fields[service_key]
      secrets = local._services_state_secrets[service_key]
      urls    = local._services_state_urls[service_key]
    }
  }
}
