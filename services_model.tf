locals {
  # Generated bootstrap value per declared service secret. Null when the secret
  # has no bootstrap_type — those are operator-supplied via 1Password and the
  # runtime model falls through to an empty placeholder until populated.
  _services_model_secret_bootstrap = {
    for entry in flatten([
      for service_key, service in local.services_input_targets : [
        for secret in service.features.secrets : {
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

  # Desired service model: expanded deployment target data plus deterministic
  # names, URLs, and server FQDNs. Runtime credentials are added separately.
  services_model_desired = {
    for service_key, service in local.services_input_targets : service_key => provider::deepmerge::mergo(
      service,
      {
        fqdn_internal = contains(local.servers_input_keys, service.target) ? "${service.identity.name}.${local.servers_model_desired[service.target].fqdn_internal}" : service.fqdn_internal
        key           = service_key

        # coalesce is safe here because defaults.yml sets app_name to null, and
        # null is ignored by coalesce in favour of the fallback expression.
        fqdn_external = (
          service.target == "fly"
          ? "${coalesce(service.platform_config.fly.app_name, "${local.defaults.organization.name}-${service.identity.name}")}.fly.dev"
          : contains(local.servers_input_keys, service.target) && contains(["cloudflare", "external"], service.networking.expose)
          ? "${service.identity.name}.${local.servers_model_desired[service.target].fqdn_external}"
          : service.fqdn_external
        )

        identity = {
          group = coalesce(
            service.identity.group,
            try(local.servers_model_desired[service.target].description, null),
            "Applications",
          )
        }

        platform_config = {
          fly = {
            app_name = (
              service.target == "fly"
              ? coalesce(service.platform_config.fly.app_name, "${local.defaults.organization.name}-${service.identity.name}")
              : service.platform_config.fly.app_name
            )
          }
        }
      }
    )
  }

  # Runtime service model: generated credentials and provider-backed values.
  # Keeping this separate makes secret dependencies easier to spot.
  services_model_runtime = {
    for service_key, service in local.services_input_targets : service_key => merge(
      service.features.b2 ? {
        b2_application_key_id        = b2_application_key.service[service_key].application_key_id
        b2_application_key_sensitive = b2_application_key.service[service_key].application_key
        b2_bucket_name               = b2_bucket.service[service_key].bucket_name
        b2_endpoint                  = local.b2_endpoint
      } : {},
      service.features.password ? {
        password_hash_sensitive = bcrypt_hash.service[service_key].id
        password_sensitive      = sensitive(try(local.onepassword_service_existing_fields[service_key].password, random_password.service[service_key].result))
      } : {},
      service.features.pushover ? {
        pushover_application_token_sensitive = var.pushover_application_token
        pushover_user_key_sensitive          = var.pushover_user_key
      } : {},
      service.features.resend ? {
        resend_api_key_sensitive = jsondecode(restapi_object.resend_api_key_service[service_key].create_response).token
      } : {},
      {
        for secret in service.features.secrets : "${secret.name}_sensitive" => sensitive(try(coalesce(
          try(local.onepassword_service_existing_fields[service_key][secret.name], null),
          local._services_model_secret_bootstrap["${service_key}-${secret.name}"],
        ), ""))
      },
      service.features.tailscale ? {
        tailscale_auth_key_sensitive = tailscale_tailnet_key.service[service_key].key
      } : {}
    )
  }
}
