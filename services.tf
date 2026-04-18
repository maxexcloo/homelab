locals {
  _services = {
    for k, v in {
      for filepath in fileset(path.module, "data/services/*.yml") :
      trimsuffix(basename(filepath), ".yml") => yamldecode(file("${path.module}/${filepath}"))
    } : k => provider::deepmerge::mergo(local.service_defaults, v)
  }

  _services_computed = merge([
    for service_key, service in local._services : {
      for target in service.deploy_to : "${service_key}-${target}" => merge(
        service,
        {
          target = target
        }
      )
    }
  ]...)

  services_files = {
    for pair in flatten([
      for k, v in local.services : [
        for filepath in fileset(path.module, "services/${v.identity.service}/**") : {
          rel_path     = trimprefix(filepath, "services/${v.identity.service}/")
          service_name = v.identity.service
          stack        = k
          target       = v.target

          content = templatefile("${path.module}/${filepath}", {
            defaults        = local.defaults
            env             = local.services_env[k]
            labels          = local.services_labels[k]
            server          = try(local.servers[v.target], null)
            servers         = local.servers
            service         = v
            services        = local.services
            services_labels = local.services_labels
          })
        }
        if !endswith(filepath, "docker-compose.yaml")
      ]
      ]) : "${pair.stack}/${pair.rel_path}" => merge(
      pair,
      {
        content_type = endswith(pair.rel_path, ".toml") ? "toml" : (
          can(regex("\\.(yaml|yml)$", pair.rel_path)) && can(keys(yamldecode(pair.content))) ? "yaml" : "binary"
        )
      }
    )
  }

  services_env = {
    for k, v in local.services : k => {
      for key, value in v.platform_config.docker.env :
      key => try(templatestring(tostring(value), { defaults = local.defaults, server = try(local.servers[v.target], null), servers = local.servers, service = v }), tostring(value))
      if value != null
    }
  }

  services_labels = {
    for k, v in local.services : k => {
      for label, value in merge(
        v.networking.scheme != null ? {
          "homepage.description" = v.identity.description
          "homepage.group"       = v.identity.group
          "homepage.href"        = v.fqdn_external != null ? "https://${v.fqdn_external}" : (length(v.networking.urls) > 0 ? "https://${v.networking.urls[0]}" : (v.fqdn_internal != null ? "${v.networking.ssl ? "https" : "http"}://${v.fqdn_internal}" : null))
          "homepage.icon"        = coalesce(v.identity.icon, v.identity.service)
          "homepage.name"        = coalesce(v.identity.title, v.identity.name)
        } : {},
        v.networking.port != null ? {
          "traefik.enable"                                                         = "true"
          "traefik.http.routers.${v.identity.service}.entrypoints"                 = v.networking.ssl ? null : "web"
          "traefik.http.routers.${v.identity.service}.middlewares"                 = v.networking.expose == "tailscale" ? "tailscale-only@docker" : (v.networking.expose == "internal" ? "internal-only@docker" : null)
          "traefik.http.services.${v.identity.service}.loadbalancer.server.port"   = tostring(v.networking.port)
          "traefik.http.services.${v.identity.service}.loadbalancer.server.scheme" = v.networking.scheme == "https" ? "https" : null
          "traefik.http.routers.${v.identity.service}.rule" = join(" || ", concat(
            v.fqdn_internal != null ? ["Host(`${v.fqdn_internal}`)"] : [],
            v.fqdn_external != null ? ["Host(`${v.fqdn_external}`)"] : [],
            [for url in v.networking.urls : "Host(`${url}`)"]
          ))
        } : {},
        {
          for key, value in v.platform_config.docker.labels :
          key => try(templatestring(tostring(value), { defaults = local.defaults, server = try(local.servers[v.target], null), servers = local.servers, service = v }), tostring(value))
          if value != null
        }
      ) : label => value if value != null
    }
  }

  services = {
    for k, v in local._services_computed : k => merge(
      v,
      {
        for secret in v.features.secrets : "${secret.name}_sensitive" => (
          contains(["hex", "base64"], secret.type) ? (
            secret.type == "hex" ?
            random_id.service_secret["${k}-${secret.name}"].hex :
            random_id.service_secret["${k}-${secret.name}"].b64_std
          ) :
          random_password.service_secret["${k}-${secret.name}"].result
        )
      },
      {
        for i, url in v.networking.urls : "url_${i}" => url
      },
      v.features.b2 ? {
        b2_application_key_id        = b2_application_key.service[k].application_key_id
        b2_application_key_sensitive = b2_application_key.service[k].application_key
        b2_bucket_name               = b2_bucket.service[k].bucket_name
        b2_endpoint                  = replace(data.b2_account_info.default.s3_api_url, "https://", "")
      } : {},
      v.features.password ? {
        password_hash_sensitive = bcrypt_hash.service[k].id
        password_sensitive      = random_password.service[k].result
      } : {},
      v.features.resend ? {
        resend_api_key_sensitive = jsondecode(restapi_object.resend_api_key_service[k].create_response).token
      } : {},
      v.features.tailscale ? {
        tailscale_auth_key_sensitive = tailscale_tailnet_key.service[k].key
      } : {},
      v.target == "fly" ? {
        platform_config = merge(v.platform_config, {
          fly = merge(v.platform_config.fly, {
            app_name = coalesce(v.platform_config.fly.app_name, "${v.identity.name}-${random_string.fly_service[k].result}")
          })
        })
      } : {},
      contains(keys(local.servers), v.target) ? merge(
        {
          fqdn_internal = "${v.identity.name}.${local.servers[v.target].fqdn_internal}"
        },
        contains(["cloudflare", "external"], v.networking.expose) ? {
          fqdn_external = "${v.identity.name}.${local.servers[v.target].fqdn_external}"
        } : {}
      ) : {}
    )
  }

  services_by_feature = {
    for feature, default_value in local.service_defaults.features : feature => {
      for k, v in local._services_computed : k => v
      if v.features[feature]
    }
    if can(tobool(default_value))
  }

  services_filtered = {
    for k, v in local.services : k => merge(
      {
        for kk, vv in v : kk => vv
        if vv != null && vv != "" && vv != false
      },
      v.target == "fly" ? {
        url_fly = "${v.platform_config.fly.app_name}.fly.dev"
      } : {}
    )
  }
}

resource "random_id" "service_secret" {
  for_each = {
    for item in flatten([
      for k, v in local._services_computed : [
        for secret in v.features.secrets : {
          key         = "${k}-${secret.name}"
          byte_length = secret.length
        }
        if contains(["hex", "base64"], secret.type)
      ]
    ]) : item.key => item
  }

  byte_length = each.value.byte_length
}

resource "random_password" "service" {
  for_each = local.services_by_feature.password

  length = 32
}

resource "random_password" "service_secret" {
  for_each = {
    for item in flatten([
      for k, v in local._services_computed : [
        for secret in v.features.secrets : {
          key     = "${k}-${secret.name}"
          length  = secret.length
          special = secret.type == "string"
        }
        if contains(["string", "alphanumeric"], secret.type)
      ]
    ]) : item.key => item
  }

  length  = each.value.length
  special = each.value.special
}

resource "shell_sensitive_script" "service_file_encrypt" {
  for_each = local.services_files

  environment = {
    AGE_PUBLIC_KEY = each.value.target == "fly" ? age_secret_key.fly.public_key : local.servers[each.value.target].age_public_key
    CONTENT        = sensitive(base64encode(each.value.content))
    CONTENT_TYPE   = each.value.content_type
    FILENAME       = each.value.rel_path
    DEBUG_PATH     = var.debug_dir != "" ? "${var.debug_dir}/${each.key}" : ""
  }

  lifecycle_commands {
    create = sensitive(local.sops_encrypt_script)
    delete = "true"
    read   = sensitive(local.sops_encrypt_script)
    update = sensitive(local.sops_encrypt_script)
  }

  triggers = {
    age_public_key_hash = sha256(each.value.target == "fly" ? age_secret_key.fly.public_key : local.servers[each.value.target].age_public_key)
    script_hash         = sha256(local.sops_encrypt_script)
  }
}

resource "terraform_data" "services_validation" {
  input = join(", ", flatten([
    for k, v in local._services : [
      for target in v.deploy_to : "${k} -> ${target}"
      if !contains(keys(local.servers), target) && target != "fly"
    ]
  ]))

  lifecycle {
    precondition {
      condition     = length(flatten([for k, v in local._services : [for target in v.deploy_to : target if !contains(keys(local.servers), target) && target != "fly"]])) == 0
      error_message = "Invalid server references found in services configuration"
    }

    precondition {
      condition     = length([for k, v in local._services : k if contains(v.deploy_to, "fly") && v.networking.port == null]) == 0
      error_message = "Fly services must have networking.port set: ${join(", ", [for k, v in local._services : k if contains(v.deploy_to, "fly") && v.networking.port == null])}"
    }

    precondition {
      condition = length(flatten([
        for k, v in local._services : [
          for target in v.deploy_to : "${k} -> ${target}"
          if contains(keys(local.servers), target) &&
          v.networking.expose == "cloudflare" &&
          !local.servers[target].features.cloudflare_zero_trust_tunnel
        ]
      ])) == 0
      error_message = "Cloudflare-exposed services deployed to servers require cloudflare_zero_trust_tunnel on the target server: ${join(", ", flatten([for k, v in local._services : [for target in v.deploy_to : "${k} -> ${target}" if contains(keys(local.servers), target) && v.networking.expose == "cloudflare" && !local.servers[target].features.cloudflare_zero_trust_tunnel]]))}"
    }
  }
}

output "services" {
  description = "Service configurations"
  sensitive   = true
  value       = local.services_filtered
}
