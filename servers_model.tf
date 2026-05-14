locals {
  # Deterministic computed fields derived from YAML input and ancestor chains.
  # Kept as a focused local so the desired model below can reference them
  # without repeating expressions.
  _servers_model_computed = {
    for server_key, server in local.servers_input : server_key => {
      fqdn_external  = "${local._servers_model_fqdn[server_key]}.${local.defaults.domains.external}"
      fqdn_internal  = "${local._servers_model_fqdn[server_key]}.${local.defaults.domains.internal}"
      url_internal   = "https://${local._servers_model_fqdn[server_key]}.${local.defaults.domains.internal}"
      url_management = "https://${local._servers_model_fqdn[server_key]}.${local.defaults.domains.internal}${server.networking.management_port != 443 ? ":${server.networking.management_port}" : ""}"

      # Root servers use the title alone. Children whose region matches their
      # parent's name (e.g. a VM inside an "au" host) omit the parent prefix
      # since the region already implies it; other children prepend parent title.
      description = (
        server.parent == "" ? server.identity.title :
        try(server.identity.region == local.servers_input[server.parent].identity.name, false)
        ? "${server.identity.title} (${upper(server.identity.region)})"
        : "${try(local.servers_input[server.parent].identity.title, server.parent)} ${server.identity.title} (${upper(server.identity.region)})"
      )

      # Public addresses inherit from self, then parent, then grandparent; the
      # first non-empty valid value wins.
      public_address = try([
        for ancestor_key in local.servers_input_ancestors[server_key] : local.servers_input[ancestor_key].networking.public_address
        if local.servers_input[ancestor_key].networking.public_address != ""
      ][0], null)

      public_ipv4 = try([
        for ancestor_key in local.servers_input_ancestors[server_key] : local.servers_input[ancestor_key].networking.public_ipv4
        if can(cidrhost(local.servers_input[ancestor_key].networking.public_ipv4, 0))
      ][0], null)

      public_ipv6 = try([
        for ancestor_key in local.servers_input_ancestors[server_key] : local.servers_input[ancestor_key].networking.public_ipv6
        if can(cidrhost("${local.servers_input[ancestor_key].networking.public_ipv6}/128", 0))
      ][0], null)
    }
  }

  _servers_model_fqdn = {
    for server_key, server in local.servers_input : server_key =>
    server.identity.name == server.identity.region ? server.identity.name : "${server.identity.name}.${server.identity.region}"
  }

  _servers_model_url = {
    for server_key, server in local.servers_input : server_key =>
    local._servers_model_computed[server_key].url_management
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

  # Desired server model: YAML plus defaults plus deterministic computed fields.
  # This layer is safe for references that should not depend on generated secrets.
  servers_model = {
    for server_key, server in local.servers_input : server_key => merge(
      server,
      local._servers_model_computed[server_key],
      {
        fqdn     = local._servers_model_computed[server_key].fqdn_internal
        key      = server_key
        ssh_keys = data.github_user.default.ssh_keys
        url      = local._servers_model_url[server_key]

        dashboard = server.dashboard != null ? server.dashboard : local._servers_model_dashboard_default_cards[server_key]

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
