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

  servers_input_keys = toset(keys(local.servers_input))
}
