locals {
  _servers_model_credentials = {
    for server_key, server in local.servers_input : server_key => {
      fields = merge(
        {
          for field_name, field in server.credentials.fields : field_name => merge(
            {
              bootstrap_length = null
              bootstrap_type   = null
              mode             = "rw"
              purpose          = null
              type             = "CONCEALED"
            },
            field,
          )
        },
        {
          age_secret_key = {
            bootstrap_length = null
            bootstrap_type   = null
            mode             = "ro"
            purpose          = null
            type             = "CONCEALED"
          }
          komodo_passkey = {
            bootstrap_length = null
            bootstrap_type   = null
            mode             = "ro"
            purpose          = null
            type             = "CONCEALED"
          }
        },
        server.features.b2 ? {
          b2_application_key = {
            bootstrap_length = null
            bootstrap_type   = null
            mode             = "ro"
            purpose          = null
            type             = "CONCEALED"
          }
        } : {},
        server.features.cloudflare_acme_token ? {
          cloudflare_acme_token = {
            bootstrap_length = null
            bootstrap_type   = null
            mode             = "ro"
            purpose          = null
            type             = "CONCEALED"
          }
        } : {},
        server.features.cloudflare_zero_trust_tunnel ? {
          cloudflare_tunnel_read_token = {
            bootstrap_length = null
            bootstrap_type   = null
            mode             = "ro"
            purpose          = null
            type             = "CONCEALED"
          }
          cloudflare_tunnel_token = {
            bootstrap_length = null
            bootstrap_type   = null
            mode             = "ro"
            purpose          = null
            type             = "CONCEALED"
          }
        } : {},
        server.features.password ? merge(
          {
            password = {
              bootstrap_length = null
              bootstrap_type   = null
              mode             = "rw"
              purpose          = "PASSWORD"
              type             = null
            }
          },
          {
            password_hash = {
              bootstrap_length = null
              bootstrap_type   = null
              mode             = "ro"
              purpose          = null
              type             = "CONCEALED"
            }
          },
        ) : {},
        server.features.pushover ? {
          pushover_application_token = {
            bootstrap_length = null
            bootstrap_type   = null
            mode             = "rw"
            purpose          = null
            type             = "CONCEALED"
          }
          pushover_user_key = {
            bootstrap_length = null
            bootstrap_type   = null
            mode             = "rw"
            purpose          = null
            type             = "CONCEALED"
          }
        } : {},
        server.features.resend ? {
          resend_api_key = {
            bootstrap_length = null
            bootstrap_type   = null
            mode             = "ro"
            purpose          = null
            type             = "CONCEALED"
          }
        } : {},
        server.features.tailscale ? {
          tailscale_auth_key = {
            bootstrap_length = null
            bootstrap_type   = null
            mode             = "ro"
            purpose          = null
            type             = "CONCEALED"
          }
        } : {},
      )
    }
  }

  # Computed once so the final model can stay mostly declarative.
  _servers_model_computed = {
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

      # Children under a same-region parent omit the parent title; the region
      # already disambiguates them.
      description = (
        server.parent == "" ? server.identity.title :
        try(server.identity.region == local.servers_input[server.parent].identity.name, false)
        ? "${server.identity.title} (${upper(server.identity.region)})"
        : "${try(local.servers_input[server.parent].identity.title, server.parent)} ${server.identity.title} (${upper(server.identity.region)})"
      )

      hosts = {
        default    = "${local._servers_model_host_prefix[server_key]}.${local.defaults.domains.internal}"
        external   = "${local._servers_model_host_prefix[server_key]}.${local.defaults.domains.external}"
        internal   = "${local._servers_model_host_prefix[server_key]}.${local.defaults.domains.internal}"
        management = server.networking.management_host != "" ? server.networking.management_host : null

        # Public host inherits from the nearest ancestor that declares one.
        public = local._servers_model_public_host[server_key]
      }

      urls = merge(
        {
          default = {
            href  = "https://${local._servers_model_host_prefix[server_key]}.${local.defaults.domains.internal}${server.networking.management_port != 443 ? ":${server.networking.management_port}" : ""}"
            label = "default"
          }
          internal = {
            href  = "https://${local._servers_model_host_prefix[server_key]}.${local.defaults.domains.internal}"
            label = "internal"
          }
          management = {
            href  = "https://${local._servers_model_host_prefix[server_key]}.${local.defaults.domains.internal}${server.networking.management_port != 443 ? ":${server.networking.management_port}" : ""}"
            label = "management"
          }
        },
        local._servers_model_public_host[server_key] != null ? {
          public = {
            href  = "https://${local._servers_model_public_host[server_key]}"
            label = "public"
          }
        } : {},
      )
    }
  }

  _servers_model_dashboard_default_cards = {
    for server_key, server in local.servers_input : server_key => [
      {
        description = local._servers_model_computed[server_key].description
        group       = local.defaults.server_types[server.type].label
        href        = local._servers_model_url[server_key]
        icon        = local.defaults.server_types[server.type].icon
        name        = "${server.identity.title} (${upper(server.identity.region)})"
        siteMonitor = local._servers_model_url[server_key]
        widgets     = []
      }
    ]
  }

  _servers_model_host_prefix = {
    for server_key, server in local.servers_input : server_key =>
    server.identity.name == server.identity.region ? server.identity.name : "${server.identity.name}.${server.identity.region}"
  }

  _servers_model_public_host = {
    for server_key, server in local.servers_input : server_key => try([
      for ancestor_key in local.servers_input_ancestors[server_key] : local.servers_input[ancestor_key].networking.public_host
      if local.servers_input[ancestor_key].networking.public_host != ""
    ][0], null)
  }

  _servers_model_url = {
    for server_key, server in local.servers_input : server_key =>
    local._servers_model_computed[server_key].urls.default.href
  }

  servers_model = {
    for server_key, server in local.servers_input : server_key => merge(
      server,
      local._servers_model_computed[server_key],
      {
        dashboard   = server.dashboard != null ? server.dashboard : local._servers_model_dashboard_default_cards[server_key]
        credentials = local._servers_model_credentials[server_key]
        key         = server_key
        ssh_keys    = data.github_user.default.ssh_keys
      }
    )
  }
}
