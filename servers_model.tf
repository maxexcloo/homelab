# Stage: model — adds deterministic computed fields. No provider values; safe for for_each keys.
locals {
  # Credential field shape for each server. Runtime values are added in servers_outputs.tf.
  _servers_model_credentials = {
    for server_key, server in local.servers_input : server_key => {
      fields = merge(
        {
          for field_name, field in server.credentials.fields : field_name => merge(
            local.defaults.credentials.rw,
            field,
          )
        },
        {
          age_secret_key = local.defaults.credentials.ro
        },
        server.features.b2 ? {
          b2_application_key = local.defaults.credentials.ro
        } : {},
        server.features.beszel ? {
          beszel_agent_token = local.defaults.credentials.rw
          beszel_system_id   = local.defaults.credentials.rw
        } : {},
        server.features.cloudflare_acme ? {
          cloudflare_acme_token = local.defaults.credentials.ro
        } : {},
        server.features.cloudflare_acme_legacy ? {
          cloudflare_acme_legacy_token = local.defaults.credentials.ro
        } : {},
        server.features.cloudflared ? {
          cloudflare_tunnel_read_token = local.defaults.credentials.ro
          cloudflare_tunnel_token      = local.defaults.credentials.ro
        } : {},
        server.features.password ? {
          password_hash = local.defaults.credentials.ro
          password = merge(
            local.defaults.credentials.rw,
            {
              purpose = "PASSWORD"
              type    = null
            }
          )
        } : {},
        server.features.pushover ? {
          pushover_application_token = local.defaults.credentials.rw
          pushover_user_key          = local.defaults.credentials.ro
        } : {},
        server.features.resend ? {
          resend_api_key = local.defaults.credentials.ro
        } : {},
        server.features.tailscale ? {
          tailscale_auth_key = local.defaults.credentials.ro
        } : {},
      )
    }
  }

  # "name.region" for child servers; plain name when name equals region (region root).
  _servers_model_host_prefix = {
    for server_key, server in local.servers_input : server_key =>
    server.identity.name == server.identity.region ? server.identity.name : "${server.identity.name}.${server.identity.region}"
  }

  _servers_model_identity = {
    for server_key, server in local.servers_input : server_key => merge(
      server.identity,
      {
        description = (
          server.identity.description != "" ? server.identity.description
          : server.parent == "" ? server.identity.title
          : try(server.identity.region == local.servers_input[server.parent].identity.name, false)
          ? "${server.identity.title} (${upper(server.identity.region)})"
          : "${try(local.servers_input[server.parent].identity.title, server.parent)} ${server.identity.title} (${upper(server.identity.region)})"
        )
        group = (
          server.identity.group != "" ? server.identity.group
          : "${server.identity.title} (${upper(server.identity.region)})"
        )
      },
    )
  }

  # Nearest ancestor with networking.public_host set; null when none declare one.
  _servers_model_public_host = {
    for server_key, server in local.servers_input : server_key => try([
      for ancestor_key in local.servers_input_ancestors[server_key] : local.servers_input[ancestor_key].networking.public_host
      if local.servers_input[ancestor_key].networking.public_host != ""
    ][0], null)
  }

  _servers_model_resolved = {
    for server_key, server in local.servers_input : server_key => {
      addresses = {
        public_ipv4 = try([
          for ancestor_key in local.servers_input_ancestors[server_key] : local.servers_input[ancestor_key].networking.public_ipv4
          if can(cidrhost(local.servers_input[ancestor_key].networking.public_ipv4, 0))
        ][0], null)

        public_ipv6 = try([
          for ancestor_key in local.servers_input_ancestors[server_key] : local.servers_input[ancestor_key].networking.public_ipv6
          if can(cidrhost("${local.servers_input[ancestor_key].networking.public_ipv6}/128", 0))
        ][0], null)
      }

      hosts = {
        external   = "${local._servers_model_host_prefix[server_key]}.${local.defaults.domains.external}"
        internal   = "${local._servers_model_host_prefix[server_key]}.${local.defaults.domains.internal}"
        management = server.networking.management_host != "" ? server.networking.management_host : null
        public     = local._servers_model_public_host[server_key]
      }

      urls = merge(
        {
          internal = {
            href  = "https://${local._servers_model_host_prefix[server_key]}.${local.defaults.domains.internal}"
            label = "internal"
          }
        },
        server.networking.management_port != "" ? {
          management = {
            href  = "https://${local._servers_model_host_prefix[server_key]}.${local.defaults.domains.internal}${server.networking.management_port != 443 ? ":${server.networking.management_port}" : ""}"
            label = "management"
          }
        } : {},
        local._servers_model_public_host[server_key] != null ? {
          public = {
            href  = "https://${local._servers_model_public_host[server_key]}"
            label = "public"
          }
        } : {},
      )
    }
  }

  _servers_model_routes = {
    for server_key, server in local.servers_input : server_key => [
      for route_index, url in server.routing.urls : merge(
        {
          for field_name, field_value in server.routing : field_name => field_value
          if field_name != "urls"
        },
        url,
        {
          id = try(url.id, tostring(route_index))
        },
      )
    ]
  }

  servers_model = {
    for server_key, server in local.servers_input : server_key => merge(
      server,
      local._servers_model_resolved[server_key],
      {
        credentials = local._servers_model_credentials[server_key]
        identity    = local._servers_model_identity[server_key]
        key         = server_key
        ssh_keys    = data.github_user.default.ssh_keys

        dashboard = jsondecode(server.dashboard != null ? jsonencode(server.dashboard) : jsonencode(server.networking.management_port != "" ? [
          {
            description = local._servers_model_identity[server_key].description
            group       = local._servers_model_identity[server_key].group
            href        = try(local._servers_model_resolved[server_key].urls.management.href, local._servers_model_resolved[server_key].urls.internal.href)
            icon        = local.defaults.server_types[server.type].icon
            name        = "${server.identity.title} (${upper(server.identity.region)})"
            siteMonitor = try(local._servers_model_resolved[server_key].urls.management.href, local._servers_model_resolved[server_key].urls.internal.href)
            widgets     = []
          }
        ] : []))

        routing = merge(
          server.routing,
          {
            urls = local._servers_model_routes[server_key]
          },
        )
      }
    )
  }
}
