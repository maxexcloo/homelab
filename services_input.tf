# Stage: input — loads raw YAML and expands each target into its own keyed entry.
locals {
  services_input = {
    for file_path in fileset(path.module, "data/services/*.yml") :
    trimsuffix(basename(file_path), ".yml") => provider::deepmerge::mergo(
      local.defaults.services,
      yamldecode(file("${path.module}/${file_path}")),
    )
  }

  # Expands service × target into individual stacks keyed as "service-target"
  # (e.g. "immich-truenas-01"). Data, features, fly, truenas, and credentials
  # deep-merge with target values winning over service-level values.
  services_input_targets = merge([
    for service_key, service in local.services_input : {
      for target_key, target_config in service.targets : "${service_key}-${target_key}" => merge(
        {
          for key, value in service : key => value
          if key != "targets"
        },
        {
          target = target_key

          credentials = {
            fields = provider::deepmerge::mergo(
              service.credentials.fields,
              lookup(lookup(target_config, "credentials", {}), "fields", {}),
            )
          }

          # can(keys()) detects whether a value is a mergeable object; scalars,
          # arrays, and null replace the service-level value rather than merging.
          data = (
            can(keys(service.data)) && can(keys(target_config.data))
            ? provider::deepmerge::mergo(service.data, target_config.data)
            : try(target_config.data, service.data)
          )

          features = merge(
            service.features,
            lookup(target_config, "features", {}),
          )

          fly = provider::deepmerge::mergo(
            local.defaults.targets.fly,
            lookup(target_config, "fly", {}),
          )

          truenas = provider::deepmerge::mergo(
            local.defaults.targets.truenas,
            lookup(target_config, "truenas", {}),
          )
        },
      )
    }
  ]...)
}
