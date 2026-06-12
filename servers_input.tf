# Stage: input — loads raw YAML and merges global defaults.
locals {
  servers_input = {
    for file_path in fileset(path.module, "data/servers/*.yml") :
    trimsuffix(basename(file_path), ".yml") => provider::deepmerge::mergo(
      local.defaults.servers,
      yamldecode(file("${path.module}/${file_path}")),
    )
  }

  # Self + parent + grandparent. Bounded to two levels for predictable
  # address inheritance; servers_validation.tf enforces the limit.
  servers_input_ancestors = {
    for server_key, server in local.servers_input : server_key => compact([
      server_key,
      try(local.servers_input[server.parent], null) != null ? server.parent : "",
      try(local.servers_input[server.parent].parent, ""),
    ])
  }
}
