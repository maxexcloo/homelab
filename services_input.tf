locals {
  services_input = {
    for file_path in fileset(path.module, "data/services/*.yml") :
    trimsuffix(basename(file_path), ".yml") => provider::deepmerge::mergo(
      local.defaults.services,
      yamldecode(file("${path.module}/${file_path}")),
    )
  }

  # Each entry in `targets` becomes its own stack, so target-specific credentials
  # and rendered files have stable addresses like service-target. Per-target
  # data, features, and platform sections are flattened to the top level with
  # target defaults merged in (target wins).
  services_input_targets = merge([
    for service_key, service in local.services_input : {
      for target_key, target_config in service.targets : "${service_key}-${target_key}" => merge(
        {
          for key, value in service : key => value
          if key != "targets"
        },
        {
          target = target_key

          # can(keys()) detects whether a value is an object; non-objects
          # (scalars, arrays, null) replace instead of merging.
          data = (
            can(keys(service.data)) && can(keys(target_config.data))
            ? provider::deepmerge::mergo(service.data, target_config.data)
            : try(target_config.data, service.data)
          )

          features = merge(
            service.features,
            lookup(target_config, "features", {}),
          )

          credentials = {
            fields = provider::deepmerge::mergo(
              service.credentials.fields,
              lookup(lookup(target_config, "credentials", {}), "fields", {}),
            )
          }

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
