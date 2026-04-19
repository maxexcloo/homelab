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

  # Desired service model: expanded deployment target data plus deterministic
  # names/URLs. Runtime credentials are deliberately added in a separate layer.
  services_desired = {
    for k, v in local._services_computed : k => merge(
      v,
      lookup(local._services_fly_computed, k, {}),
      v.target == "fly" ? {
        fqdn_external = "${local._services_fly_computed[k].platform_config.fly.app_name}.fly.dev"
      } : {},
      contains(keys(local.servers_desired), v.target) ? merge(
        {
          fqdn_internal = "${v.identity.name}.${local.servers_desired[v.target].fqdn_internal}"
        },
        contains(["cloudflare", "external"], v.networking.expose) ? {
          fqdn_external = "${v.identity.name}.${local.servers_desired[v.target].fqdn_external}"
        } : {}
      ) : {},
      {
        for i, url in v.networking.urls : "url_${i}" => url
      }
    )
  }

  # Runtime service model: generated credentials and provider-backed values.
  # Keeping this separate makes secret dependencies easier to spot.
  services_runtime = {
    for k, v in local._services_computed : k => merge(
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
      v.features.tailscale ? {
        tailscale_auth_key_sensitive = tailscale_tailnet_key.service[k].key
      } : {}
    )
  }

  # Template contexts are intentionally small: templates get the current service,
  # the selected server when present, public inventory maps, and global defaults.
  services_base_template_vars = {
    for k, v in local.services_template_context : k => {
      defaults = local.defaults
      server   = try(local.servers_template_context[v.target], null)
      servers  = local.servers_public
      service  = v

      services = {
        for kk, vv in local.services_template_context : kk => {
          fqdn_external = vv.fqdn_external
          fqdn_internal = vv.fqdn_internal
          target        = vv.target

          identity   = vv.identity
          networking = vv.networking
        }
      }
    }
  }

  # Feature maps are built from expanded input, not runtime services, to avoid
  # feature resources depending on the resources they create.
  services_by_feature = {
    for feature, default_value in local.service_defaults.features : feature => {
      for k, v in local._services_computed : k => v
      if v.features[feature]
    }
    if can(tobool(default_value))
  }

  # Rendered Docker Compose content keyed by expanded service stack.
  services_compose = {
    for k, v in local.services_compose_sources : k => (
      v.render_template ? templatefile(v.path, local.services_template_vars[k]) : file(v.path)
    )
  }

  # Service compose files can be static or explicit OpenTofu templates. The
  # rendered filename is always docker-compose.yaml.
  services_compose_sources = merge(
    {
      for k, v in local.services_desired : k => {
        path            = "${path.module}/services/${v.identity.name}/docker-compose.yaml"
        render_template = false
      }
      if fileexists("${path.module}/services/${v.identity.name}/docker-compose.yaml")
    },
    {
      for k, v in local.services_desired : k => {
        path            = "${path.module}/services/${v.identity.name}/docker-compose.yaml.tftpl"
        render_template = true
      }
      if fileexists("${path.module}/services/${v.identity.name}/docker-compose.yaml.tftpl")
    }
  )

  # User-provided Docker labels are template-rendered against the safe base context.
  services_docker_labels = {
    for k, v in local.services_template_context : k => {
      for key, value in v.platform_config.docker.labels :
      key => templatestring(tostring(value), local.services_base_template_vars[k])
      if value != null
    }
  }

  # Fail fast on bad interpolation rather than silently rendering a literal
  # ${...} expression into deployment config.
  services_env = {
    for k, v in local.services_template_context : k => {
      for key, value in v.platform_config.docker.env :
      key => templatestring(tostring(value), local.services_base_template_vars[k])
      if value != null && templatestring(tostring(value), local.services_base_template_vars[k]) != ""
    }
  }

  # File extension -> SOPS input type. YAML/JSON still need a structural check
  # below because SOPS structured encryption expects an object, not a list/scalar.
  services_file_content_types = {
    ".env"  = "dotenv"
    ".json" = "json"
    ".yaml" = "yaml"
    ".yml"  = "yaml"
  }

  # Normalized extension lookup keeps the rendered-file local from repeating regexes.
  services_file_extensions = {
    for pair in local.services_file_sources : "${pair.stack}/${pair.rel_path}" => try(regex("\\.[^.]+$", lower(pair.rel_path)), "")
  }

  # Only .tftpl files are rendered; the suffix is stripped from the deployed path.
  # Other files use filebase64(), so static and binary assets share one path.
  services_file_sources = flatten([
    for k, v in local.services_desired : [
      for filepath in fileset(path.module, "services/${v.identity.name}/**") : {
        path            = "${path.module}/${filepath}"
        rel_path        = trimsuffix(trimprefix(filepath, "services/${v.identity.name}/"), ".tftpl")
        render_template = endswith(filepath, ".tftpl")
        service_name    = v.identity.name
        stack           = k
        target          = v.target
      }
      if !contains(["app.json", "app.json.tftpl", "docker-compose.yaml", "docker-compose.yaml.tftpl"], basename(filepath))
    ]
  ])

  # Text content is only loaded for files where we may need templating or SOPS
  # structured type detection. Other files stay base64-only.
  services_file_text_content = {
    for pair in local.services_file_sources : "${pair.stack}/${pair.rel_path}" => (
      pair.render_template ? templatefile(pair.path, local.services_template_vars[pair.stack]) :
      contains(keys(local.services_file_content_types), local.services_file_extensions["${pair.stack}/${pair.rel_path}"]) ? file(pair.path) :
      null
    )
  }

  # Deployed sidecar files include encrypted content metadata used by Fly, Komodo,
  # and TrueNAS GitHub repository file resources.
  services_files = {
    for pair in local.services_file_sources : "${pair.stack}/${pair.rel_path}" => merge(
      pair,
      {
        content_base64 = pair.render_template ? base64encode(templatefile(pair.path, local.services_template_vars[pair.stack])) : filebase64(pair.path)
        content_type = contains([".json", ".yaml", ".yml"], local.services_file_extensions["${pair.stack}/${pair.rel_path}"]) ? (
          can(keys(yamldecode(local.services_file_text_content["${pair.stack}/${pair.rel_path}"]))) ?
          local.services_file_content_types[local.services_file_extensions["${pair.stack}/${pair.rel_path}"]] :
          "binary"
        ) : lookup(local.services_file_content_types, local.services_file_extensions["${pair.stack}/${pair.rel_path}"], "binary")
      }
    )
  }

  # Routing label rules live in a template; service-owned labels are plain data.
  services_labels = {
    for k, v in local.services_template_context : k => merge(
      yamldecode(templatefile("${path.module}/templates/docker/labels.yaml.tftpl", local.services_base_template_vars[k])),
      local.services_docker_labels[k]
    )
  }

  # Public service inventory is safe to expose to other service templates.
  services_public = {
    for k, v in local.services_desired : k => {
      fqdn_external = v.fqdn_external
      fqdn_internal = v.fqdn_internal
      identity      = v.identity
      labels        = local.services_labels[k]
      networking    = v.networking
      target        = v.target
    }
  }

  # Templates get the full service object because service config files may need
  # generated passwords, API keys, and feature credentials.
  services_template_context = {
    for k, v in local.services_desired : k => merge(
      v,
      local.services_runtime[k]
    )
  }

  # Full template context adds rendered env, labels, and public service inventory.
  services_template_vars = {
    for k, v in local.services_template_context : k => merge(local.services_base_template_vars[k], {
      env      = local.services_env[k]
      labels   = local.services_labels[k]
      services = local.services_public
    })
  }
}

resource "random_id" "service_secret" {
  # Byte-oriented generated secrets use random_id so hex/base64 lengths map to
  # byte counts rather than password character counts.
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

resource "terraform_data" "services_validation" {
  input = keys(local._services)

  lifecycle {
    # Cloudflare-exposed services on servers need a tunnel token available from
    # the target server feature set.
    precondition {
      condition = length(flatten([
        for k, v in local._services : [
          for target in v.deploy_to : "${k} -> ${target}"
          if contains(keys(local.servers_desired), target) &&
          v.networking.expose == "cloudflare" &&
          !local.servers_desired[target].features.cloudflare_zero_trust_tunnel
        ]
      ])) == 0
      error_message = "Cloudflare-exposed services deployed to servers require cloudflare_zero_trust_tunnel on the target server: ${join(", ", flatten([for k, v in local._services : [for target in v.deploy_to : "${k} -> ${target}" if contains(keys(local.servers_desired), target) && v.networking.expose == "cloudflare" && !local.servers_desired[target].features.cloudflare_zero_trust_tunnel]]))}"
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
      condition     = length(flatten([for k, v in local._services : [for target in v.deploy_to : target if !contains(keys(local.servers_desired), target) && target != "fly"]])) == 0
      error_message = "Invalid server references found in services configuration: ${join(", ", flatten([for k, v in local._services : [for target in v.deploy_to : "${k} -> ${target}" if !contains(keys(local.servers_desired), target) && target != "fly"]]))}"
    }
  }
}

output "services" {
  description = "Service configurations"
  sensitive   = true

  # Output view removes empty fields but remains sensitive because it includes secrets.
  value = {
    for k, v in local.services_desired : k => {
      for kk, vv in merge(v, local.services_runtime[k]) : kk => vv
      if vv != null && vv != "" && vv != false
    }
  }
}
