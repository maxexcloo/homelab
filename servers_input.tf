locals {
  servers_input = {
    for file_path in fileset(path.module, "data/servers/*.yml") :
    trimsuffix(basename(file_path), ".yml") => provider::deepmerge::mergo(
      local.defaults.servers,
      yamldecode(file("${path.module}/${file_path}")),
    )
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
}
