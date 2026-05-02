locals {
  # Merge schema defaults into each server file before deriving inherited fields.
  servers_input = {
    for server_key, server in {
      for file_path in fileset(path.module, "data/servers/*.yml") :
      trimsuffix(basename(file_path), ".yml") => yamldecode(file("${path.module}/${file_path}"))
    } : server_key => provider::deepmerge::mergo(local.defaults_server, server)
  }

  # Inheritance is intentionally bounded to self, parent, and grandparent; the
  # validation below fails if data tries to exceed that model.
  servers_input_ancestors = {
    for server_key, server in local.servers_input : server_key => compact([
      server_key,
      server.parent,
      try(local.servers_input[server.parent].parent, ""),
    ])
  }

  # Parent context keeps inherited description logic readable without adding
  # broader parent inheritance.
  servers_input_context = {
    for server_key, server in local.servers_input : server_key => {
      region_matches = try(server.identity.region == local.servers_input[server.parent].identity.name, false)
      title          = try(local.servers_input[server.parent].identity.title, server.parent)
    }
  }

  # Non-provider derived fields used by DNS, templates, 1Password, and inventory.
  servers_input_derived = {
    for server_key, server in local.servers_input : server_key => {
      fqdn = length(split("-", server_key)) == 1 ? server_key : "${server.identity.name}.${server.identity.region}"
      slug = server_key

      description = (
        server.parent == "" ? server.identity.title :
        local.servers_input_context[server_key].region_matches ? "${server.identity.title} (${upper(server.identity.region)})" :
        "${local.servers_input_context[server_key].title} ${server.identity.title} (${upper(server.identity.region)})"
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
}
