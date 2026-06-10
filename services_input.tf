# Stage: input — loads raw YAML and expands each target into its own keyed entry.
locals {
  _services_input_raw = {
    for file_path in fileset(path.module, "data/services/*.yml") :
    trimsuffix(basename(file_path), ".yml") => provider::deepmerge::mergo(
      local.defaults.services,
      yamldecode(file("${path.module}/${file_path}")),
    )
  }

  services_input = {
    for service_key, service in local._services_input_raw : service_key => merge(
      service,
      {
        targets = merge(
          {
            for server_key, server in local.servers_input : server_key => {}
            if try(server.features[join("_", split("-", service.identity.name))], false)
          },
          service.targets,
        )
      },
    )
  }

  # Expands service × target into individual stacks keyed as "service-target"
  # (e.g. "immich-truenas-01"). Data, features, fly, truenas, and credentials
  # deep-merge with target values winning over service-level values.
  services_input_targets = merge([
    for service_key, service in local.services_input : {
      for target_key, target_config in service.targets : "${service_key}-${target_key}" => provider::deepmerge::mergo(
        {
          for key, value in service : key => value
          if key != "targets"
        },
        {
          target = target_key

          credentials = {
            fields = {}
            source = service.credentials.source
          }

          fly     = local.defaults.targets.fly
          truenas = local.defaults.targets.truenas
        },
        target_config,
      )
    }
  ]...)
}
