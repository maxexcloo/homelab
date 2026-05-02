locals {
  # Desired service model: expanded deployment target data plus deterministic
  # names, URLs, and server FQDNs. Runtime credentials are added separately.
  services_model_desired = {
    for service_key, service in local.services_input_targets : service_key => provider::deepmerge::mergo(
      service,
      {
        for url_index, url in service.networking.urls : "url_${url_index}" => url
      },
      {
        fqdn_external = service.target == "fly" ? "${coalesce(service.platform_config.fly.app_name, "${local.defaults.organization.name}-${service.identity.name}")}.fly.dev" : contains(keys(local.servers_model_desired), service.target) && contains(["cloudflare", "external"], service.networking.expose) ? "${service.identity.name}.${local.servers_model_desired[service.target].fqdn_external}" : service.fqdn_external
        fqdn_internal = contains(keys(local.servers_model_desired), service.target) ? "${service.identity.name}.${local.servers_model_desired[service.target].fqdn_internal}" : service.fqdn_internal
        key           = service_key

        identity = {
          group = service.identity.group != null ? service.identity.group : contains(keys(local.servers_model_desired), service.target) ? local.servers_model_desired[service.target].description : "Applications"
        }

        platform_config = {
          fly = {
            app_name = service.target == "fly" ? coalesce(service.platform_config.fly.app_name, "${local.defaults.organization.name}-${service.identity.name}") : service.platform_config.fly.app_name
          }
        }
      }
    )
  }

  services_model_passwords = {
    for service_key, service in local.services_outputs_by_feature.password : service_key => sensitive(try(local.onepassword_service_existing_fields[service_key].password, random_password.service[service_key].result))
  }

  # Runtime service model: generated credentials and provider-backed values.
  # Keeping this separate makes secret dependencies easier to spot.
  services_model_runtime = {
    for service_key, service in local.services_input_targets : service_key => merge(
      service.features.b2 ? {
        b2_application_key_id        = b2_application_key.service[service_key].application_key_id
        b2_application_key_sensitive = b2_application_key.service[service_key].application_key
        b2_bucket_name               = b2_bucket.service[service_key].bucket_name
        b2_endpoint                  = replace(data.b2_account_info.default.s3_api_url, "https://", "")
      } : {},
      service.features.password ? {
        password_hash_sensitive = bcrypt_hash.service[service_key].id
        password_sensitive      = local.services_model_passwords[service_key]
      } : {},
      service.features.pushover ? {
        pushover_application_token_sensitive = var.pushover_application_token
        pushover_user_key_sensitive          = var.pushover_user_key
      } : {},
      service.features.resend ? {
        resend_api_key_sensitive = jsondecode(restapi_object.resend_api_key_service[service_key].create_response).token
      } : {},
      {
        for secret in service.features.secrets : "${secret.name}_sensitive" => (
          try(secret.bootstrap_type, null) == null ? sensitive(try(local.onepassword_service_existing_fields[service_key][secret.name], "")) : sensitive(try(
            local.onepassword_service_existing_fields[service_key][secret.name],
            contains(["hex", "base64"], try(secret.bootstrap_type, null)) ? (
              try(secret.bootstrap_type, null) == "hex" ?
              random_id.service_secret["${service_key}-${secret.name}"].hex :
              random_id.service_secret["${service_key}-${secret.name}"].b64_std
            ) :
            random_password.service_secret["${service_key}-${secret.name}"].result
          ))
        )
      },
      service.features.tailscale ? {
        tailscale_auth_key_sensitive = tailscale_tailnet_key.service[service_key].key
      } : {}
    )
  }
}
