locals {
  # Merge schema defaults into each source service before expanding deploy targets.
  _services = {
    for k, v in {
      for filepath in fileset(path.module, "data/services/*.yml") :
      trimsuffix(basename(filepath), ".yml") => yamldecode(file("${path.module}/${filepath}"))
    } : k => provider::deepmerge::mergo(local.service_defaults, v)
  }

  # Each deploy_to target becomes its own stack, so target-specific secrets and
  # rendered files have stable addresses like service-target.
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

  services = {
    for k, v in local._services_computed : k => merge(
      v,
      v.features.b2 ? {
        b2_application_key_id        = b2_application_key.service[k].application_key_id
        b2_application_key_sensitive = b2_application_key.service[k].application_key
        b2_bucket_name               = b2_bucket.service[k].bucket_name
        b2_endpoint                  = replace(data.b2_account_info.default.s3_api_url, "https://", "")
      } : {},
      lookup(local._services_fly_computed, k, {}),
      v.target == "fly" ? {
        fqdn_external = "${local._services_fly_computed[k].platform_config.fly.app_name}.fly.dev"
      } : {},
      v.features.password ? {
        password_hash_sensitive = bcrypt_hash.service[k].id
        password_sensitive      = random_password.service[k].result
      } : {},
      v.features.pushover ? {
        pushover_application_token_sensitive = var.pushover_application_token
        pushover_user_key_sensitive          = var.pushover_user_key
      } : {},
      v.features.resend ? {
        resend_api_key_sensitive = jsondecode(restapi_object.resend_api_key_service[k].create_response).token
      } : {},
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
      contains(keys(local.servers), v.target) ? merge(
        {
          fqdn_internal = "${v.identity.name}.${local.servers[v.target].fqdn_internal}"
        },
        contains(["cloudflare", "external"], v.networking.expose) ? {
          fqdn_external = "${v.identity.name}.${local.servers[v.target].fqdn_external}"
        } : {}
      ) : {},
      v.features.tailscale ? {
        tailscale_auth_key_sensitive = tailscale_tailnet_key.service[k].key
      } : {},
      {
        for i, url in v.networking.urls : "url_${i}" => url
      }
    )
  }

  # Template contexts are intentionally small: templates get the current service,
  # the selected server when present, all services, and global defaults.
  services_base_template_vars = {
    for k, v in local.services : k => {
      defaults = local.defaults
      server   = try(local.servers[v.target], null)
      servers  = local.servers
      service  = v
    }
  }

  services_by_feature = {
    for feature, default_value in local.service_defaults.features : feature => {
      for k, v in local._services_computed : k => v
      if v.features[feature]
    }
    if can(tobool(default_value))
  }

  # Fail fast on bad interpolation rather than silently rendering a literal
  # ${...} expression into deployment config.
  services_env = {
    for k, v in local.services : k => {
      for key, value in v.platform_config.docker.env :
      key => templatestring(tostring(value), local.services_base_template_vars[k])
      if value != null
    }
  }

  # SOPS supports structured encryption for these formats. Everything else is
  # encrypted as binary JSON so static files can still be transported safely.
  services_file_content_types = {
    ".dotenv" = "dotenv"
    ".env"    = "dotenv"
    ".json"   = "json"
    ".yaml"   = "yaml"
    ".yml"    = "yaml"
  }

  services_docker_labels = {
    for k, v in local.services : k => {
      for key, value in v.platform_config.docker.labels :
      key => templatestring(tostring(value), local.services_base_template_vars[k])
      if value != null
    }
  }

  # Product-specific label rules live in a template; Terraform only merges in
  # generic user-provided Docker labels after template interpolation.
  services_labels = {
    for k, v in local.services : k => merge(
      yamldecode(templatefile("${path.module}/templates/docker/labels.yaml", local.services_base_template_vars[k])),
      local.services_docker_labels[k]
    )
  }

  services_template_vars = {
    for k, v in local.services : k => merge(local.services_base_template_vars[k], {
      env             = local.services_env[k]
      labels          = local.services_labels[k]
      services        = local.services
      services_labels = local.services_labels
    })
  }

  services_compose = {
    for k, v in local.services : k => templatefile(
      "${path.module}/services/${v.identity.service}/docker-compose.yaml",
      local.services_template_vars[k]
    )
    if fileexists("${path.module}/services/${v.identity.service}/docker-compose.yaml")
  }

  # Files with template markers are rendered. Other files use filebase64(), which
  # lets static or binary assets share the same SOPS/GitHub delivery path.
  services_file_sources = flatten([
    for k, v in local.services : [
      for filepath in fileset(path.module, "services/${v.identity.service}/**") : {
        path            = "${path.module}/${filepath}"
        rel_path        = trimprefix(filepath, "services/${v.identity.service}/")
        render_template = can(regex("(?s)(\\$\\{|%\\{)", file("${path.module}/${filepath}")))
        service_name    = v.identity.service
        stack           = k
        target          = v.target
      }
      if !endswith(filepath, "docker-compose.yaml")
    ]
  ])

  services_files = {
    for pair in local.services_file_sources : "${pair.stack}/${pair.rel_path}" => merge(
      pair,
      {
        content_base64 = pair.render_template ? base64encode(templatefile(pair.path, local.services_template_vars[pair.stack])) : filebase64(pair.path)
        content_type   = lookup(local.services_file_content_types, try(regex("\\.[^.]+$", lower(pair.rel_path)), ""), "binary")
      }
    )
  }

  services_files_age_public_keys = {
    for k, v in local.services_files : k => v.target == "fly" ? age_secret_key.fly.public_key : local.servers[v.target].age_public_key
  }

  services_filtered = {
    for k, v in local.services : k => {
      for kk, vv in v : kk => vv
      if vv != null && vv != "" && vv != false
    }
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

# Password-like secrets are separate from random_id because string and
# alphanumeric formats need random_password's character controls.
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

# Renders service config files, encrypts them with the target's age key, and
# stores only encrypted content for GitHub repository_file resources to consume.
resource "shell_sensitive_script" "service_file_encrypt" {
  for_each = local.services_files

  environment = {
    AGE_PUBLIC_KEY = local.services_files_age_public_keys[each.key]
    CONTENT        = sensitive(each.value.content_base64)
    CONTENT_TYPE   = each.value.content_type
    DEBUG_PATH     = var.debug_dir != "" ? "${var.debug_dir}/${each.key}" : ""
    FILENAME       = each.value.rel_path
  }

  lifecycle_commands {
    create = sensitive(local.sops_encrypt_script)
    delete = "true"
    read   = sensitive(local.sops_encrypt_script)
    update = sensitive(local.sops_encrypt_script)
  }

  triggers = {
    age_public_key_hash = sha256(local.services_files_age_public_keys[each.key])
    script_hash         = sha256(local.sops_encrypt_script)
  }
}

resource "terraform_data" "services_validation" {
  input = keys(local._services)

  lifecycle {
    # Cloudflare-exposed services on servers need a tunnel token available from
    # the target server feature set.
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

    precondition {
      condition     = length([for k, v in local._services : k if contains(v.deploy_to, "fly") && v.networking.port == null]) == 0
      error_message = "Fly services must have networking.port set: ${join(", ", [for k, v in local._services : k if contains(v.deploy_to, "fly") && v.networking.port == null])}"
    }

    # Pushover values are pass-through variables, so provider validation will not
    # catch missing credentials for enabled services.
    precondition {
      condition     = length([for k, v in local._services_computed : k if v.features.pushover && (nonsensitive(var.pushover_application_token) == "" || nonsensitive(var.pushover_user_key) == "")]) == 0
      error_message = "Services with features.pushover enabled require pushover_application_token and pushover_user_key: ${join(", ", [for k, v in local._services_computed : k if v.features.pushover && (nonsensitive(var.pushover_application_token) == "" || nonsensitive(var.pushover_user_key) == "")])}"
    }

    precondition {
      condition     = length(flatten([for k, v in local._services : [for target in v.deploy_to : target if !contains(keys(local.servers), target) && target != "fly"]])) == 0
      error_message = "Invalid server references found in services configuration: ${join(", ", flatten([for k, v in local._services : [for target in v.deploy_to : "${k} -> ${target}" if !contains(keys(local.servers), target) && target != "fly"]]))}"
    }
  }
}

output "services" {
  description = "Service configurations"
  sensitive   = true
  value       = local.services_filtered
}
