locals {
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
            href = "https://${local._servers_model_host_prefix[server_key]}.${local.defaults.domains.internal}${server.networking.management_port != 443 ? ":${server.networking.management_port}" : ""}"
          }
          internal = {
            href = "https://${local._servers_model_host_prefix[server_key]}.${local.defaults.domains.internal}"
          }
          management = {
            href = "https://${local._servers_model_host_prefix[server_key]}.${local.defaults.domains.internal}${server.networking.management_port != 443 ? ":${server.networking.management_port}" : ""}"
          }
        },
        local._servers_model_public_host[server_key] != null ? {
          public = {
            href = "https://${local._servers_model_public_host[server_key]}"
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
        dashboard = server.dashboard != null ? server.dashboard : local._servers_model_dashboard_default_cards[server_key]
        key       = server_key
        ssh_keys  = data.github_user.default.ssh_keys

        secrets = [
          for secret in server.secrets : merge(
            {
              bootstrap_length = null,
              bootstrap_type   = null
            },
            secret
          )
        ]
      }
    )
  }
}
