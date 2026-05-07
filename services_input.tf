locals {
  # Merge schema defaults into each source service before expanding targets.
  services_input = {
    for service_key, service in {
      for file_path in fileset(path.module, "data/services/*.yml") :
      trimsuffix(basename(file_path), ".yml") => yamldecode(file("${path.module}/${file_path}"))
    } : service_key => provider::deepmerge::mergo(local.defaults_service, service)
  }

  # Each entry in `targets` becomes its own stack, so target-specific secrets
  # and rendered files have stable addresses like service-target. Per-target
  # data, features, and platform sections are flattened to the top level with
  # target_defaults merged in (target wins).
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
            !can(target_config.data) ? service.data
            : can(keys(service.data)) && can(keys(target_config.data)) ? provider::deepmerge::mergo(service.data, target_config.data)
            : target_config.data
          )

          features = merge(
            service.features,
            try(target_config.features, {}),
          )

          fly = provider::deepmerge::mergo(
            local.defaults_target.fly,
            try(target_config.fly, {}),
          )

          truenas = provider::deepmerge::mergo(
            local.defaults_target.truenas,
            try(target_config.truenas, {}),
          )
        },
      )
    }
  ]...)
}
