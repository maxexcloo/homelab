locals {
  truenas_compose_templates = {
    for k, v in local.truenas_custom_services : k => templatefile(
      "${path.module}/templates/docker/${v.identity.service}/docker-compose.yaml",
      {
        defaults = local.defaults
        server   = local.servers[v.target]
        servers  = local.servers
        service  = v
        services = local.services
      }
    )
  }

  truenas_labels = {
    for k, v in local.truenas_standard_services : k => {
      for label, value in merge(
        {
          "homepage.group" = try(coalesce(v.platform_config.homepage.group, v.identity.group != "" ? v.identity.group : null), null)
          "homepage.href"  = try(templatestring(v.platform_config.homepage.href, { defaults = local.defaults, service = v }), "https://${v.fqdn_external}", null)
          "homepage.icon"  = try(coalesce(v.platform_config.homepage.icon, "${v.identity.service}.svg"), "${v.identity.service}.svg")
          "homepage.name"  = try(coalesce(v.platform_config.homepage.name, v.identity.description), v.identity.description)
        },
        v.networking.port != null ? {
          "traefik.enable"                                                         = "true"
          "traefik.http.routers.${v.identity.service}.entrypoints"                 = "websecure"
          "traefik.http.routers.${v.identity.service}.middlewares"                 = try(v.platform_config.docker.middleware, null)
          "traefik.http.routers.${v.identity.service}.rule"                        = "Host(`${v.fqdn_external}`)"
          "traefik.http.routers.${v.identity.service}.tls"                         = "true"
          "traefik.http.services.${v.identity.service}.loadbalancer.server.port"   = tostring(v.networking.port)
          "traefik.http.services.${v.identity.service}.loadbalancer.server.scheme" = try(v.networking.scheme, null)
        } : {}
      ) : label => value if value != null
    }
  }

  truenas_container = {
    for k, v in local.truenas_services : k => try(v.platform_config.docker.container, v.identity.service)
  }

  truenas_custom_services = {
    for k, v in local.truenas_services : k => v
    if fileexists("${path.module}/templates/docker/${v.identity.service}/docker-compose.yaml")
  }

  truenas_servers = {
    for k, v in local.servers : k => v
    if v.platform == "truenas"
  }

  truenas_services = {
    for k, v in local.services : k => v
    if contains(keys(local.truenas_servers), v.target)
  }

  truenas_standard_services = {
    for k, v in local.truenas_services : k => v
    if !fileexists("${path.module}/templates/docker/${v.identity.service}/docker-compose.yaml")
  }
}

resource "github_actions_secret" "truenas_age_key" {
  for_each = local.truenas_servers

  plaintext_value = age_secret_key.server[each.key].secret_key
  repository      = local.defaults.github.repositories.truenas
  secret_name     = "AGE_KEY_${upper(replace(each.key, "-", "_"))}"
}

resource "github_repository_file" "truenas_compose" {
  for_each = local.truenas_custom_services

  commit_message      = "Update ${each.key} compose"
  file                = "${each.value.target}/${each.value.identity.service}/compose.json"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.truenas

  content = shell_sensitive_script.truenas_compose_encrypt[each.key].output["encrypted_content"]
}

resource "github_repository_file" "truenas_labels" {
  for_each = local.truenas_standard_services

  commit_message      = "Update ${each.key} labels"
  file                = "${each.value.target}/${each.value.identity.service}/${local.truenas_container[each.key]}/override.json"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.truenas

  content = shell_sensitive_script.truenas_labels_encrypt[each.key].output["encrypted_content"]
}

resource "github_repository_file" "truenas_sops_config" {
  commit_message      = "Update SOPS configuration"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.truenas

  file = ".sops.yaml"
  content = join("\n", concat(
    ["creation_rules:"],
    [for k, v in local.truenas_servers : "  - path_regex: '^${k}/'\n    age: ${age_secret_key.server[k].public_key}"]
  ))
}

resource "shell_sensitive_script" "truenas_compose_encrypt" {
  for_each = local.truenas_custom_services

  environment = {
    AGE_PUBLIC_KEY = age_secret_key.server[each.value.target].public_key
    CONTENT = base64encode(jsonencode({
      app_name                     = each.value.identity.service
      custom_app                   = true
      custom_compose_config_string = local.truenas_compose_templates[each.key]
    }))
    CONTENT_TYPE = "json"
  }

  lifecycle_commands {
    create = local.sops_encrypt_script
    delete = "true"
    read   = local.sops_encrypt_script
    update = local.sops_encrypt_script
  }

  triggers = {
    age_public_key_hash = sha256(age_secret_key.server[each.value.target].public_key)
    content_hash        = sha256(local.truenas_compose_templates[each.key])
    script_hash         = sha256(local.sops_encrypt_script)
  }
}

resource "shell_sensitive_script" "truenas_labels_encrypt" {
  for_each = local.truenas_standard_services

  environment = {
    AGE_PUBLIC_KEY = age_secret_key.server[each.value.target].public_key
    CONTENT = base64encode(jsonencode({
      values = {
        containerConfig = {
          env    = [for k, v in local.truenas_labels[each.key] : { name = k, value = tostring(v) }]
          labels = local.truenas_labels[each.key]
        }
      }
    }))
    CONTENT_TYPE = "json"
  }

  lifecycle_commands {
    create = local.sops_encrypt_script
    delete = "true"
    read   = local.sops_encrypt_script
    update = local.sops_encrypt_script
  }

  triggers = {
    age_public_key_hash = sha256(age_secret_key.server[each.value.target].public_key)
    content_hash        = sha256(jsonencode(local.truenas_labels[each.key]))
    script_hash         = sha256(local.sops_encrypt_script)
  }
}
