locals {
  # Deterministic computed fields derived from YAML input and ancestor chains.
  # Kept as a focused local so the desired model below can reference them
  # without repeating expressions.
  _servers_model_computed = {
    for server_key, server in local.servers_input : server_key => {
      fqdn       = server.identity.name == server.identity.region ? server.identity.name : "${server.identity.name}.${server.identity.region}"
      type_icon  = local.defaults.types[server.type].icon
      type_label = local.defaults.types[server.type].label

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

  # Desired server model: YAML plus defaults plus deterministic computed fields.
  # This layer is safe for references that should not depend on generated secrets.
  servers_model = {
    for server_key, server in local.servers_input : server_key => merge(
      server,
      local._servers_model_computed[server_key],
      {
        fqdn_external = "${local._servers_model_computed[server_key].fqdn}.${local.defaults.domains.external}"
        fqdn_internal = "${local._servers_model_computed[server_key].fqdn}.${local.defaults.domains.internal}"
        key           = server_key
        ssh_keys      = data.github_user.default.ssh_keys
      }
    )
  }
}
